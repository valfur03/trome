import type { Logger } from "../logging/logger";
import type { ApnsClient } from "../push/apns-client";
import type { ApnsKey, ApnsSettings } from "../push/apns-settings";
import type { RelayAnswer } from "../relay/relay";
import type { Clock } from "../time/clock";
import type { StartAnswer } from "../usage/start-answers";
import { minute } from "../time/clock";
import { readStation } from "./content-of-station";
import type { StationCatalog } from "./station-catalog";
import { stationContent } from "./station-content";
import { startPayload } from "./start-payload";
import { StationUpdates, updateWindow } from "./station-updates";

/**
 * Starts the Live Activity of a station on the iPhone of a rider, when the app, woken near the station, asks for it.
 *
 * - The same token and station asked again within 45 minutes (the longest outing) answer "already-started" and send nothing: iOS gives the app each event of an area twice, and each start is an alert.
 *   To know it without keeping the token, the server keeps only a keyed hash of the token and the station, with a key that is made at random in memory and never leaves it; a sleep or a deploy forgets both, and the next ask then starts again.
 * - Apple gives a token to its production service or to its development one, and the token does not say which: the start goes to production first, then to development when production answers that the token is not its own.
 * - Each station has one broadcast channel in each service, made at its first start and deleted 45 minutes after its last one.
 *   Until then, `StationUpdates` sends the new minutes of the station on it.
 * - A log line holds the result only: never the token, the station or an error text (which may hold the address, and so the token).
 * - Each answer, and each ask that the route refuses as bad, is counted in its hour by its result (`UsageCounts.countStartAnswer`), so that the owner sees where a start stopped: no ask, an ask that Apple took, or one that failed.
 */
export type StartResult =
  | { result: "started" }
  | { result: "already-started" }
  | { result: "refused"; reason: string }
  | { result: "not-set-up" }
  | { result: "unknown-station" };

export interface LiveActivityStartsDependencies {
  settings: ApnsSettings | undefined;
  apns: ApnsClient;
  catalog: StationCatalog;
  departures: (stopRef: string) => Promise<RelayAnswer>;
  clock: Clock;
  logger: Logger;
  /** The keyed hash of a token and a station (`createStartKeys`). */
  startKey: (text: string) => Promise<string>;
  counts: { countStartAnswer(answer: StartAnswer, at: number): void };
}

export const startWindow = 45 * minute;
/** A start that Apple has not given to the iPhone after this time is dropped: the rider has walked on. */
const startExpiration = 2 * minute;
/** Apple's answer when the token belongs to the other service. */
const otherServiceReason = "BadDeviceToken";

interface Channel {
  id: Promise<string | { reason: string }>;
  key: ApnsKey;
  lastStart: number;
}

export class LiveActivityStarts {
  private readonly starts = new Map<string, { until: number; result: Promise<StartResult> }>();
  private readonly channels = new Map<string, Channel>();
  private readonly updates: StationUpdates;

  constructor(private readonly dependencies: LiveActivityStartsDependencies) {
    const { catalog, departures, clock, logger } = dependencies;
    this.updates = new StationUpdates({ catalog, departures, clock, logger, send: (stationId, payload) => this.broadcast(stationId, payload) });
  }

  async start(stationId: string, token: string): Promise<StartResult> {
    let answer: StartResult;
    try {
      answer = await this.answer(stationId, token);
    } catch (error) {
      // A fault before the send, which the route answers 500: the app falls back, as from a refusal.
      this.count({ result: "refused", reason: "server-error" });
      throw error;
    }
    this.count(answer);
    return answer;
  }

  /** Counts an ask that the route refused as bad, such as a body with no start token. */
  badRequest(): void {
    this.count({ result: "bad-request" });
  }

  /** A count that fails (a write refused by the storage) never changes the answer: a started Live Activity answered as a fault would also bring the notification. */
  private count(answer: StartAnswer): void {
    const { counts, clock, logger } = this.dependencies;
    try {
      counts.countStartAnswer(answer, clock.now());
    } catch {
      logger.error("live-activity-start-count", { result: "not-counted" });
    }
  }

  private async answer(stationId: string, token: string): Promise<StartResult> {
    const { settings, catalog, clock, logger, startKey } = this.dependencies;
    if (settings === undefined) {
      logger.info("live-activity-start", { result: "not-set-up" });
      return { result: "not-set-up" };
    }
    const station = catalog.station(stationId);
    if (station === undefined) {
      return { result: "unknown-station" };
    }
    this.forgetPastStarts();
    const key = await startKey(`${token}|${stationId}`);
    const earlier = this.starts.get(key);
    if (earlier !== undefined) {
      const result = await earlier.result;
      const answer: StartResult = result.result === "started" ? { result: "already-started" } : result;
      logger.info("live-activity-start", { ...answer });
      return answer;
    }
    // A fault of the server is a refusal, so that the app falls back and the next ask tries again: an entry left with no end would refuse that rider until a sleep.
    const result = this.send(settings, stationId, token).catch((): StartResult => {
      logger.error("live-activity-start", { result: "refused", reason: "server-error" });
      return { result: "refused", reason: "server-error" };
    });
    const entry = { until: Number.POSITIVE_INFINITY, result };
    this.starts.set(key, entry);
    const answer = await result;
    if (answer.result === "started") {
      entry.until = clock.now() + startWindow;
    } else {
      this.starts.delete(key);
    }
    return answer;
  }

  /** When the next work is due: to send an update, to forget a start or to delete a channel; undefined when memory holds nothing of the starts. */
  nextWake(): number | undefined {
    const ends = [
      ...[...this.starts.values()].map((start) => start.until),
      ...[...this.channels.values()].map((channel) => channel.lastStart + startWindow),
      this.updates.nextUpdate() ?? Number.POSITIVE_INFINITY,
    ].filter((end) => Number.isFinite(end));
    if (ends.length === 0) {
      return undefined;
    }
    return Math.min(...ends);
  }

  /** Does what is due at `nextWake`: sends the updates, forgets the starts past their window, and deletes the channels with no start in the last 45 minutes. */
  async wake(): Promise<void> {
    await this.updates.sendDue();
    await this.forgetPast();
  }

  private async forgetPast(): Promise<void> {
    this.forgetPastStarts();
    const now = this.dependencies.clock.now();
    const due = [...this.channels.entries()].filter(([, channel]) => channel.lastStart + startWindow <= now);
    for (const [name] of due) {
      this.channels.delete(name);
    }
    await Promise.all(
      due.map(async ([, channel]) => {
        const id = await channel.id;
        if (typeof id !== "string") {
          return;
        }
        const answer = await this.dependencies.apns.deleteChannel(channel.key, id);
        this.dependencies.logger.info("live-activity-channel-delete", answer.ok ? { result: "deleted" } : { result: "refused", reason: answer.reason });
      }),
    );
  }

  private forgetPastStarts(): void {
    const now = this.dependencies.clock.now();
    for (const [key, start] of this.starts) {
      if (start.until <= now) {
        this.starts.delete(key);
      }
    }
  }

  private async send(settings: ApnsSettings, stationId: string, token: string): Promise<StartResult> {
    const { apns, catalog, departures, clock, logger } = this.dependencies;
    const station = catalog.station(stationId);
    if (station === undefined) {
      return { result: "unknown-station" };
    }
    const reading = await readStation(station, catalog, departures);
    const content = stationContent(station, reading.stations, reading.trains, catalog, clock.now());
    let refusal: { reason: string; environment: string } | undefined;
    for (const key of settings.keys) {
      const channelId = await this.channel(key, stationId);
      if (typeof channelId !== "string") {
        refusal ??= { reason: channelId.reason, environment: key.environment };
        continue;
      }
      const now = clock.now();
      const answer = await apns.start(key, token, startPayload(station, content, channelId, now, now + updateWindow), now + startExpiration);
      if (answer.ok) {
        this.updates.follow(station, reading, content, now + updateWindow);
        logger.info("live-activity-start", { result: "started", environment: key.environment });
        return { result: "started" };
      }
      if (refusal === undefined || refusal.reason === otherServiceReason) {
        refusal = { reason: answer.reason, environment: key.environment };
      }
      if (answer.reason !== otherServiceReason) {
        break;
      }
    }
    const reason = refusal?.reason ?? "no-answer";
    logger.info("live-activity-start", { result: "refused", reason, ...(refusal ? { environment: refusal.environment } : {}) });
    return { result: "refused", reason };
  }

  /** Sends an update on the channel of the station in each service; a log line holds the result and the service only. */
  private async broadcast(stationId: string, payload: string): Promise<void> {
    const { apns, logger } = this.dependencies;
    const channels = [...this.channels.entries()].filter(([name]) => name.endsWith(`|${stationId}`)).map(([, channel]) => channel);
    await Promise.all(
      channels.map(async (channel) => {
        const id = await channel.id;
        if (typeof id !== "string") {
          return;
        }
        const answer = await apns.broadcast(channel.key, id, payload);
        logger.info(
          "live-activity-update",
          answer.ok ? { result: "sent", environment: channel.key.environment } : { result: "refused", reason: answer.reason, environment: channel.key.environment },
        );
      }),
    );
  }

  /** The channel of the station in the service of the key, made at its first start; a failed one is made again at the next start. */
  private async channel(key: ApnsKey, stationId: string): Promise<string | { reason: string }> {
    const name = `${key.environment}|${stationId}`;
    const now = this.dependencies.clock.now();
    const held = this.channels.get(name);
    if (held !== undefined) {
      held.lastStart = now;
      return held.id;
    }
    const id = this.dependencies.apns.createChannel(key).then((answer) => {
      if (answer.ok && answer.channelId !== undefined) {
        return answer.channelId;
      }
      this.channels.delete(name);
      const reason = answer.ok ? "no-channel-id" : answer.reason;
      this.dependencies.logger.info("live-activity-channel-create", { result: "refused", reason });
      return { reason };
    });
    this.channels.set(name, { id, key, lastStart: now });
    return id;
  }
}

/** The keyed hash of the starts: HMAC-SHA-256 with a key made at random for this memory, so that the hash of a token cannot be checked by anyone, even with the token. */
export function createStartKeys(): (text: string) => Promise<string> {
  const secret = crypto.subtle.importKey("raw", crypto.getRandomValues(new Uint8Array(32)), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  return async (text) => {
    const signature = await crypto.subtle.sign("HMAC", await secret, new TextEncoder().encode(text));
    return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  };
}
