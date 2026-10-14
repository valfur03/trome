import { DurableObject } from "cloudflare:workers";
import { PrimBudget } from "../core/budget/prim-budget";
import { relaySettings } from "../core/config/relay-settings";
import { secretValues } from "../core/config/secrets";
import { createLogger } from "../core/logging/logger";
import { AnswerStore } from "../core/relay/answer-store";
import { createPrimClient } from "../core/relay/prim-client";
import { Relay, type CountsReport, type RelayAnswer } from "../core/relay/relay";
import type { MetricsSnapshot } from "../core/metrics/prometheus-metrics";
import { UsageCounts } from "../core/usage/usage-counts";
import { DurableObjectSqlDatabase } from "./durable-object-sql-database";

export const relayObjectName = "relay";

/**
 * The one server object. Cloudflare puts an idle object to sleep about 10 s after its last request when no timer and no call is open, and a sleep empties its memory.
 * Memory holds what storage must not: the answers of the stops and the failed stops, which a storage write would keep restorable for 30 days.
 * So the object keeps a timer while memory holds something of use, and stays awake through it: the counts not yet written (at most 10 s),
 * an answer until the oldest age at which it is given (5 minutes), and a failed stop until the end of its pause.
 * A pending timer holds off eviction for up to 15 minutes from its start, and each timer here ends at most 5 minutes after the latest PRIM answer, so the object still sleeps through a quiet night.
 */
export class RelayObject extends DurableObject<Env> {
  private readonly relay: Relay;
  private readonly usage: UsageCounts;
  private useTimer: { at: number; handle: ReturnType<typeof setTimeout> } | undefined;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const database = new DurableObjectSqlDatabase(ctx.storage.sql);
    const settings = relaySettings(env);
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
      clock: { now: () => Date.now() },
      logger: createLogger(secretValues(env), (line) => {
        console.log(line);
      }),
      settings,
    });
  }

  async departures(stopRef: string): Promise<RelayAnswer> {
    try {
      return await this.relay.departures(stopRef);
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
    const useEnd = this.relay.nextUseEnd();
    if (useEnd === undefined || (this.useTimer !== undefined && this.useTimer.at <= useEnd)) {
      return;
    }
    if (this.useTimer !== undefined) {
      clearTimeout(this.useTimer.handle);
    }
    const handle = setTimeout(() => {
      this.useTimer = undefined;
      this.relay.forgetPastUse();
      this.planUseTimer();
    }, useEnd - Date.now());
    this.useTimer = { at: useEnd, handle };
  }
}

export function relayObject(env: Env): DurableObjectStub<RelayObject> {
  return env.RELAY.getByName(relayObjectName);
}
