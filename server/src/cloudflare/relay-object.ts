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
 * The one server object. Cloudflare puts an idle object to sleep after about 10 s with no request, no open call and no timer, and a sleep empties its memory.
 * So the object keeps in storage what must outlive a sleep (the copy of each answer, the counts), and keeps a timer only while memory holds what storage must not:
 * the counts not yet written (at most 10 s), and the failed stops during their pause.
 * A storage alarm, which does not keep it awake, wakes it to delete each answer and copy at the end of its life.
 */
export class RelayObject extends DurableObject<Env> {
  private readonly relay: Relay;
  private readonly usage: UsageCounts;
  private alarmAt: number | undefined;
  private failureTimerAt: number | undefined;

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
      this.planForget();
    }
  }

  counts(): CountsReport {
    const report = this.relay.counts();
    this.planForget();
    return report;
  }

  metrics(): MetricsSnapshot {
    const snapshot = this.relay.metrics();
    this.planForget();
    return snapshot;
  }

  override alarm(): void {
    this.alarmAt = undefined;
    this.relay.forgetPastUse();
    this.planForget();
  }

  private planForget(): void {
    const forgetAt = this.relay.nextAnswerForgetAt();
    if (forgetAt !== undefined && (this.alarmAt === undefined || forgetAt < this.alarmAt)) {
      this.alarmAt = forgetAt;
      void this.ctx.storage.setAlarm(forgetAt);
    }
    const pauseEnd = this.relay.nextFailurePauseEnd();
    if (pauseEnd !== undefined && (this.failureTimerAt === undefined || pauseEnd < this.failureTimerAt)) {
      this.failureTimerAt = pauseEnd;
      setTimeout(() => {
        this.failureTimerAt = undefined;
        this.relay.forgetPastUse();
        this.planForget();
      }, pauseEnd - Date.now());
    }
  }
}

export function relayObject(env: Env): DurableObjectStub<RelayObject> {
  return env.RELAY.getByName(relayObjectName);
}
