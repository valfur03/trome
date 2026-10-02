import { PrimBudget } from "../../../src/core/budget/prim-budget";
import { relaySettings, type RelaySettings } from "../../../src/core/config/relay-settings";
import { createLogger } from "../../../src/core/logging/logger";
import { AnswerStore } from "../../../src/core/relay/answer-store";
import { Relay } from "../../../src/core/relay/relay";
import type { SqlDatabase } from "../../../src/core/storage/sql-database";
import { UsageCounts } from "../../../src/core/usage/usage-counts";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";
import { FakeClock } from "../time/fake-clock";
import { FakePrimClient } from "./fake-prim-client";

export interface RelayHarness {
  relay: Relay;
  usage: UsageCounts;
  prim: FakePrimClient;
  clock: FakeClock;
  database: SqlDatabase;
  logLines: string[];
  flushTimes: number[];
  restart(): RelayHarness;
}

export function relayHarness({
  now = "2026-10-02T08:30:00.000Z",
  dailyCap = "800",
  database = new NodeSqliteDatabase(),
  clock = FakeClock.at(now),
  prim = new FakePrimClient(),
  settings: overrides = {},
}: {
  now?: string;
  dailyCap?: string;
  database?: SqlDatabase;
  clock?: FakeClock;
  prim?: FakePrimClient;
  settings?: Partial<RelaySettings>;
} = {}): RelayHarness {
  const settings = { ...relaySettings({ PRIM_DAILY_CAP: dailyCap }), ...overrides };
  const logLines: string[] = [];
  const flushTimes: number[] = [];
  const usage = new UsageCounts(database, (at) => flushTimes.push(at));
  const relay = new Relay({
    answers: new AnswerStore(database),
    budget: new PrimBudget(database, settings),
    usage,
    prim,
    clock,
    logger: createLogger(["prim-secret"], (line) => logLines.push(line)),
    settings,
  });
  return {
    relay,
    usage,
    prim,
    clock,
    database,
    logLines,
    flushTimes,
    restart: () => relayHarness({ dailyCap, database, clock, prim, settings: overrides }),
  };
}
