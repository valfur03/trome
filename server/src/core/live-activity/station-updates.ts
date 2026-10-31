import type { Logger } from "../logging/logger";
import type { RelayAnswer } from "../relay/relay";
import type { Clock } from "../time/clock";
import { minute, second } from "../time/clock";
import { readStation, type StationReading } from "./content-of-station";
import { departuresToKeep, type LastTrains } from "./departure-board";
import type { Station, StationCatalog } from "./station-catalog";
import { encodeContent, stationContent, staleDate, type StationContent } from "./station-content";
import type { Departure } from "./station-departures";
import { broadcastSizeLimit, payloadBytes, updatePayload } from "./update-payload";

/**
 * Keeps the minutes of the Live Activities that the server started moving, with no app to do it: it sends the new content of the station on its channel, as the app sends it to its own Live Activity in the background.
 *
 * - **When.** As the app in the background asks (`BackgroundTrainsRefresh`): 5 seconds after the first train of the content leaves, but at least 30 seconds and at most 2 minutes after the last ask; when the server is out for every stop, at the time when it asks PRIM again.
 *   Each ask goes through the relay, as an app's would, so it gets the same held answers and the same quota: a station asked again within 60 seconds costs no PRIM call.
 * - **How long.** Until 20 minutes after the last start at the station (`updateWindow`); then the server forgets the station, and each push has had that end as its latest stale date, so that the lock screen reads old when the updates stop.
 * - **What.** The content that the app would send from the same answers, with its rules for a failed call: the times shown stay after a failure, marked stale once their first train has left; "No trains" becomes "Times unavailable"; a stop that does not answer keeps the trains of its last answer.
 *   The content is the same for every rider of the station, so it holds the first page, as at the start.
 * - **Size.** An update over Apple's limit for a channel is not sent, and a log line says so: the Live Activity keeps its last content, which goes stale at its stale date.
 */
export interface StationUpdatesDependencies {
  catalog: StationCatalog;
  departures: (stopRef: string) => Promise<RelayAnswer>;
  clock: Clock;
  logger: Logger;
  /** Sends the payload on each channel of the station. */
  send: (stationId: string, payload: string) => Promise<void>;
}

/**
 * How long the updates of a station go on after its last start: a wait at a station, with a missed train on most lines.
 * Each minute of it costs up to one PRIM call for each stop of the station, so it is shorter than the 45 minutes of the memory of a start: in the model of 15 riders, 45 minutes would reach the daily cap of PRIM calls, and a fifth of the answers at the busy hours would read "Times unavailable".
 */
export const updateWindow = 20 * minute;
export const minimumDelay = 30 * second;
export const maximumDelay = 2 * minute;
const delayAfterDeparture = 5 * second;

interface Followed {
  station: Station;
  until: number;
  nextAt: number;
  sent: StationContent;
  keptStaleDate: number | undefined;
  last: LastTrains | undefined;
  running: boolean;
}

export class StationUpdates {
  private readonly followed = new Map<string, Followed>();

  constructor(private readonly dependencies: StationUpdatesDependencies) {}

  /**
   * A start at the station: its updates go on until `until`, and the first one comes as the app's would after this content.
   * When stops of the station were late for the start (`lateStops`), it comes at the shortest wait instead: their trains are what the rider waits for.
   */
  follow(station: Station, reading: StationReading, content: StationContent, until: number, { lateStops = 0 }: { lateStops?: number } = {}): void {
    const now = this.dependencies.clock.now();
    const held = this.followed.get(station.id);
    if (held !== undefined) {
      // The riders already there have the old end as their latest stale date: an update at once gives them the new one, from the answers that the start has just read, so with no PRIM call.
      held.nextAt = Math.min(held.nextAt, now);
      held.until = Math.max(held.until, until);
      return;
    }
    this.followed.set(station.id, {
      station,
      until,
      nextAt: now + (lateStops > 0 ? minimumDelay : delay(staleDate(content), now)),
      sent: content,
      keptStaleDate: undefined,
      last: lastTrains(reading, []),
      running: false,
    });
  }

  /** The time of the next update, or of the end of a station's window. */
  nextUpdate(): number | undefined {
    const times = [...this.followed.values()].map((followed) => Math.min(followed.nextAt, followed.until));
    return times.length === 0 ? undefined : Math.min(...times);
  }

  /** Sends the updates that are due, and forgets the stations past their window. */
  async sendDue(): Promise<void> {
    const now = this.dependencies.clock.now();
    for (const [stationId, followed] of this.followed) {
      if (followed.until <= now) {
        this.followed.delete(stationId);
      }
    }
    const due = [...this.followed.values()].filter((followed) => followed.nextAt <= now && !followed.running);
    await Promise.all(due.map((followed) => this.update(followed)));
  }

  private async update(followed: Followed): Promise<void> {
    const { catalog, departures, clock, logger, send } = this.dependencies;
    followed.running = true;
    try {
      const reading = await readStation(followed.station, catalog, departures);
      const now = clock.now();
      const content = this.nextContent(followed, reading, now);
      followed.nextAt = this.nextAsk(followed, content ?? followed.sent, reading, now);
      if (content === undefined) {
        return;
      }
      const payload = updatePayload(content, now, followed.until);
      const bytes = payloadBytes(payload);
      if (bytes > broadcastSizeLimit) {
        logger.error("live-activity-update", { result: "too-large", bytes });
        return;
      }
      followed.sent = content;
      await send(followed.station.id, payload);
    } catch {
      // A fault of the server skips this update only: the Live Activity keeps its content, and the next ask comes at the longest wait.
      followed.nextAt = clock.now() + maximumDelay;
      logger.error("live-activity-update", { result: "server-error" });
    } finally {
      followed.running = false;
    }
  }

  /** The content to send, or undefined when the Live Activity must keep the one it has, as the app's `update(station:trains:)` does. */
  private nextContent(followed: Followed, reading: StationReading, now: number): StationContent | undefined {
    const { trains } = reading;
    const shownStaleDate = followed.sent.trains.kind === "lines" ? staleDate(followed.sent) : undefined;
    if (trains.kind === "failed" && shownStaleDate !== undefined) {
      followed.keptStaleDate ??= shownStaleDate;
      const kept: StationContent = {
        ...followed.sent,
        serverIsOut: trains.serverIsOut,
        isMarkedStale: followed.sent.isMarkedStale === true || now >= followed.keptStaleDate,
      };
      return sameContent(kept, followed.sent) ? undefined : kept;
    }
    followed.keptStaleDate = undefined;
    const earlier =
      trains.kind === "departures" && trains.unansweredStops.size > 0 && followed.last !== undefined
        ? departuresToKeep(followed.last, trains.unansweredStops, now)
        : [];
    if (trains.kind === "departures") {
      followed.last = lastTrains(reading, earlier);
    }
    return stationContent(followed.station, reading.stations, trains, this.dependencies.catalog, now, earlier);
  }

  /** The next ask, as the app's `BackgroundTrainsRefresh.nextCall`, and the moment when kept times get old, which the app marks stale at once. */
  private nextAsk(followed: Followed, sent: StationContent, reading: StationReading, now: number): number {
    let next =
      reading.retryAt !== undefined && reading.retryAt > now
        ? Math.max(reading.retryAt, now + minimumDelay)
        : now + delay(sent.isMarkedStale === true ? undefined : staleDate(sent), now);
    if (followed.keptStaleDate !== undefined && sent.isMarkedStale !== true && followed.keptStaleDate > now) {
      next = Math.min(next, followed.keptStaleDate);
    }
    return next;
  }
}

/** `BackgroundTrainsRefresh.delay(untilStale:now:)` of the app. */
function delay(stale: number | undefined, now: number): number {
  if (stale === undefined) {
    return maximumDelay;
  }
  return Math.min(Math.max(stale - now + delayAfterDeparture, minimumDelay), maximumDelay);
}

function lastTrains(reading: StationReading, earlier: readonly Departure[]): LastTrains | undefined {
  const { trains } = reading;
  return trains.kind === "departures" ? { departures: trains.departures, unansweredStops: trains.unansweredStops, earlier } : undefined;
}

function sameContent(first: StationContent, second: StationContent): boolean {
  return JSON.stringify(encodeContent(first)) === JSON.stringify(encodeContent(second));
}
