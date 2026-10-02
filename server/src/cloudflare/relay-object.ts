import { DurableObject } from "cloudflare:workers";
import { PrimBudget } from "../core/budget/prim-budget";
import { relaySettings } from "../core/config/relay-settings";
import { secretValues } from "../core/config/secrets";
import { createLogger } from "../core/logging/logger";
import { AnswerStore } from "../core/relay/answer-store";
import { createPrimClient } from "../core/relay/prim-client";
import { Relay, type CountsReport, type RelayAnswer } from "../core/relay/relay";
import { UsageCounts } from "../core/usage/usage-counts";
import { DurableObjectSqlDatabase } from "./durable-object-sql-database";

export const relayObjectName = "relay";

export class RelayObject extends DurableObject<Env> {
  private readonly relay: Relay;
  private readonly usage: UsageCounts;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const database = new DurableObjectSqlDatabase(ctx.storage.sql);
    const settings = relaySettings(env);
    this.usage = new UsageCounts(database, (at) => {
      void ctx.storage.setAlarm(at);
    });
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

  departures(stopRef: string): Promise<RelayAnswer> {
    return this.relay.departures(stopRef);
  }

  counts(): CountsReport {
    return this.relay.counts();
  }

  override alarm(): void {
    this.usage.flushFromAlarm();
  }
}

export function relayObject(env: Env): DurableObjectStub<RelayObject> {
  return env.RELAY.getByName(relayObjectName);
}
