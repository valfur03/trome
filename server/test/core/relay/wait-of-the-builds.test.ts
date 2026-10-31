import { afterEach, describe, expect, it, vi } from "vitest";
import { PrimBudget } from "../../../src/core/budget/prim-budget";
import { relaySettings } from "../../../src/core/config/relay-settings";
import { route } from "../../../src/core/http/router";
import { createLogger } from "../../../src/core/logging/logger";
import { AnswerStore } from "../../../src/core/relay/answer-store";
import { createPrimClient } from "../../../src/core/relay/prim-client";
import { Relay } from "../../../src/core/relay/relay";
import { UsageCounts } from "../../../src/core/usage/usage-counts";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";
import { FakeClock } from "../time/fake-clock";
import { marginForThePhone, shortestRecordedWait, wakeOfASleepingServerObject } from "./recorded-waits";

// A build in the field gives up on an answer after the wait that its recorded set names (contracts/builds/).
// The server must answer before that, even when PRIM never answers, so that the build reads the out answer and its retry time,
// not a failure of its own; recorded-waits.ts gives the room for the parts that this test cannot run.

afterEach(() => {
  vi.useRealTimers();
});

describe("the longest wait of the server for PRIM", () => {
  it("ends, with its out answer, early enough for the shortest wait of a build in the field", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    const settings = relaySettings({ PRIM_DAILY_CAP: "800" });
    const database = new NodeSqliteDatabase();
    const clock = FakeClock.at("2026-10-02T08:30:00.000Z");
    const neverAnswers = (_url: string, init: RequestInit): Promise<Response> =>
      new Promise((_resolve, reject) => {
        init.signal?.addEventListener("abort", () => {
          reject(init.signal?.reason as Error);
        });
      });
    const relay = new Relay({
      answers: new AnswerStore(database),
      budget: new PrimBudget(database, settings),
      usage: new UsageCounts(database, () => undefined),
      prim: createPrimClient({ apiKey: "prim-key-of-the-test", timeout: settings.primTimeout, fetch: neverAnswers }),
      clock,
      logger: createLogger([], () => undefined),
      settings,
    });
    const ask = (): Promise<Response> =>
      route(
        new Request("https://server.test/v1/stops/STIF:StopArea:SP:42155:/departures", {
          headers: { authorization: "Bearer app-token-of-the-test" },
        }),
        {
          logger: createLogger([], () => undefined),
          clock,
          tokens: { app: ["app-token-of-the-test"], owner: "owner-token-of-the-test" },
          relay: {
            departures: (stopRef) => relay.departures(stopRef),
            counts: () => Promise.resolve(relay.counts()),
            metrics: () => Promise.resolve(relay.metrics()),
          },
          liveActivities: { start: () => Promise.reject(new Error("no start in this test")), badRequest: () => Promise.resolve() },
        },
      );

    let answered: Response | undefined;
    void ask().then((response) => (answered = response));
    let waited = 0;
    while (answered === undefined && waited < 60_000) {
      await vi.advanceTimersByTimeAsync(100);
      waited += 100;
    }

    expect(answered, `no answer after ${String(waited)} ms`).toBeDefined();
    expect(Math.floor((answered?.status ?? 0) / 100), "the builds read a 2xx as times").not.toBe(2);
    expect(await answered?.json()).toMatchObject({ status: "out" });
    const shortest = shortestRecordedWait((set) => set.app.waitForOneAnswerSeconds);
    if (shortest === undefined) {
      throw new Error("contracts/builds/ holds no set");
    }
    expect(
      waited + wakeOfASleepingServerObject + marginForThePhone,
      `The server waits ${String(waited)} ms for PRIM. With ${String(wakeOfASleepingServerObject)} ms for the wake of the server object and ` +
        `${String(marginForThePhone)} ms for the phone, that passes the ${String(shortest.seconds)} s that the builds of ` +
        `contracts/builds/${shortest.set}/ wait for one answer: they would read a failure, not the out answer.`,
    ).toBeLessThanOrEqual(shortest.seconds * 1000);
  });
});
