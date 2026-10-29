import { DurableObject } from "cloudflare:workers";
import { PrimBudget } from "../core/budget/prim-budget";
import { relaySettings } from "../core/config/relay-settings";
import { secretValues } from "../core/config/secrets";
import { createStartKeys, LiveActivityStarts, type StartResult } from "../core/live-activity/live-activity-starts";
import { StationCatalog } from "../core/live-activity/station-catalog";
import { createLogger } from "../core/logging/logger";
import { createApnsClient } from "../core/push/apns-client";
import { apnsSettings } from "../core/push/apns-settings";
import { ProviderTokens } from "../core/push/provider-token";
import { AnswerStore } from "../core/relay/answer-store";
import { createPrimClient } from "../core/relay/prim-client";
import { Relay, type CountsReport, type RelayAnswer } from "../core/relay/relay";
import type { MetricsSnapshot } from "../core/metrics/prometheus-metrics";
import { UsageCounts } from "../core/usage/usage-counts";
import { DurableObjectSqlDatabase } from "./durable-object-sql-database";
import { optionalSecrets } from "./optional-secrets";

export const relayObjectName = "relay";

/**
 * The one server object. Cloudflare puts an idle object to sleep about 10 s after its last request when no timer and no call is open, and a sleep empties its memory.
 * Memory holds what storage must not: the answers of the stops and the failed stops, which a storage write would keep restorable for 30 days.
 * So the object keeps a timer while memory holds something of use, and stays awake through it: the counts not yet written (at most 10 s),
 * an answer until the oldest age at which it is given (5 minutes), and a failed stop until the end of its pause.
 * A pending timer holds off eviction for up to 15 minutes from its start, and each timer here ends at most 5 minutes after the latest PRIM answer, so the object still sleeps through a quiet night.
 * A start of a Live Activity keeps the object awake 45 minutes more, with timers of at most 10 minutes: memory then knows the start, so that a second ask of the same rider sends no second alert, and the channel of the station, on which it sends the new minutes every 30 seconds to 2 minutes, and which it deletes at the end.
 */
export class RelayObject extends DurableObject<Env> {
  private readonly relay: Relay;
  private readonly usage: UsageCounts;
  private readonly starts: LiveActivityStarts;
  private useTimer: { at: number; handle: ReturnType<typeof setTimeout> } | undefined;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const database = new DurableObjectSqlDatabase(ctx.storage.sql);
    const settings = relaySettings(env);
    const logger = createLogger(secretValues(env), (line) => {
      console.log(line);
    });
    const clock = { now: () => Date.now() };
    let flushTimer: ReturnType<typeof setTimeout> | undefined;
    this.usage = new UsageCounts(
      database,
      (at) => {
        flushTimer = setTimeout(() => {
          flushTimer = undefined;
          this.usage.flushWhenDue();
        }, at - Date.now());
      },
      () => {
        if (flushTimer !== undefined) {
          clearTimeout(flushTimer);
          flushTimer = undefined;
        }
      },
    );
    this.relay = new Relay({
      answers: new AnswerStore(database),
      budget: new PrimBudget(database, settings),
      usage: this.usage,
      prim: createPrimClient({
        apiKey: env.PRIM_API_KEY,
        timeout: settings.primTimeout,
        fetch: (url, init) => fetch(url, init),
      }),
      clock,
      logger,
      settings,
    });
    const apns = apnsSettings(optionalSecrets(env));
    this.starts = new LiveActivityStarts({
      settings: apns,
      apns: createApnsClient({
        fetch: (url, init) => fetch(url, init),
        tokens: new ProviderTokens(apns?.teamId ?? "", clock),
        bundleId: apns?.bundleId ?? "",
      }),
      catalog: StationCatalog.bundled(),
      departures: (stopRef) => this.departures(stopRef),
      clock,
      logger,
      startKey: createStartKeys(),
    });
  }

  async departures(stopRef: string): Promise<RelayAnswer> {
    try {
      return await this.relay.departures(stopRef);
    } finally {
      this.planUseTimer();
    }
  }

  async startLiveActivity(stationId: string, startToken: string): Promise<StartResult> {
    try {
      return await this.starts.start(stationId, startToken);
    } finally {
      this.planUseTimer();
    }
  }

  counts(): CountsReport {
    const report = this.relay.counts();
    this.planUseTimer();
    return report;
  }

  metrics(): MetricsSnapshot {
    const snapshot = this.relay.metrics();
    this.planUseTimer();
    return snapshot;
  }

  /** The older version set a storage alarm to write the counts: one may still come after a deploy, and it only tidies the memory. */
  override alarm(): void {
    this.relay.forgetPastUse();
    this.planUseTimer();
  }

  private planUseTimer(): void {
    const ends = [this.relay.nextUseEnd(), this.starts.nextWake()].filter((end) => end !== undefined);
    const useEnd = ends.length === 0 ? undefined : Math.min(...ends);
    if (useEnd === undefined || (this.useTimer !== undefined && this.useTimer.at <= useEnd)) {
      return;
    }
    if (this.useTimer !== undefined) {
      clearTimeout(this.useTimer.handle);
    }
    const handle = setTimeout(() => {
      this.useTimer = undefined;
      this.relay.forgetPastUse();
      void this.starts.wake().finally(() => {
        this.planUseTimer();
      });
    }, useEnd - Date.now());
    this.useTimer = { at: useEnd, handle };
  }
}

export function relayObject(env: Env): DurableObjectStub<RelayObject> {
  return env.RELAY.getByName(relayObjectName);
}
