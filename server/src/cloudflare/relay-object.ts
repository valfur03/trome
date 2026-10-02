import { DurableObject } from "cloudflare:workers";
import { Counters } from "../core/counting/counters";
import { DurableObjectSqlDatabase } from "./durable-object-sql-database";

export const relayObjectName = "relay";

export class RelayObject extends DurableObject<Env> {
  private readonly counters: Counters;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.counters = new Counters(new DurableObjectSqlDatabase(ctx.storage.sql));
  }

  addToCounter(name: string, amount = 1): number {
    return this.counters.add(name, amount);
  }

  readCounter(name: string): number {
    return this.counters.read(name);
  }
}

export function relayObject(env: Env): DurableObjectStub<RelayObject> {
  return env.RELAY.getByName(relayObjectName);
}
