import { afterEach, describe, expect, it, vi } from "vitest";
import { PrimBudget } from "../../../src/core/budget/prim-budget";
import { relaySettings } from "../../../src/core/config/relay-settings";
import { route } from "../../../src/core/http/router";
import { LiveActivityStarts } from "../../../src/core/live-activity/live-activity-starts";
import { createLogger } from "../../../src/core/logging/logger";
import { createApnsClient, type Fetch } from "../../../src/core/push/apns-client";
import { apnsHosts } from "../../../src/core/push/apns-settings";
import { ProviderTokens } from "../../../src/core/push/provider-token";
import { AnswerStore } from "../../../src/core/relay/answer-store";
import { createPrimClient } from "../../../src/core/relay/prim-client";
import { Relay } from "../../../src/core/relay/relay";
import { UsageCounts } from "../../../src/core/usage/usage-counts";
import { testApnsSettings } from "../push/fake-apple";
import { primFixture } from "../relay/prim-fixtures";
import { marginForThePhone, shortestRecordedWait, wakeOfASleepingServerObject } from "../relay/recorded-waits";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";
import { FakeClock } from "../time/fake-clock";
import { catalog } from "./live-activity-harness";

// A build gives up on the start of a Live Activity after the wait that its recorded set names (liveActivityStart in contracts/builds/),
// and shows its arrival notification: a Live Activity that came later would come on top of it.
// So the start must answer before that, whatever PRIM and Apple do, up to their own timeouts; recorded-waits.ts gives the room
// for the parts that this test cannot run.

type Delay = number | "never";

/** A network that answers each request after `delay`, or only stops when the request is aborted. */
function lateNetwork(delay: Delay, reply: (url: string, init: RequestInit) => Response): Fetch {
  return (url, init) =>
    new Promise((resolve, reject) => {
      const timer =
        delay === "never"
          ? undefined
          : setTimeout(() => {
              resolve(reply(url, init));
            }, delay);
      init.signal?.addEventListener("abort", () => {
        clearTimeout(timer);
        reject(init.signal?.reason as Error);
      });
    });
}

/** Apple, with a token of a build that Xcode installs, the longest path: production refuses it, then development makes its channel and takes the start. */
function appleReply(token: "production" | "development") {
  return (url: string, init: RequestInit): Response => {
    if (url.endsWith("/channels") && init.method === "POST") {
      return new Response(null, { status: 201, headers: { "apns-channel-id": "channel-1" } });
    }
    if (token === "development" && url.startsWith(`${apnsHosts.production.device}/`)) {
      return new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: 400 });
    }
    return new Response(null, { status: 200 });
  };
}

interface Answer {
  waited: number;
  status: number;
  result: string;
}

async function askToStart(network: { prim: Delay; apple: Delay; token: "production" | "development" }): Promise<Answer> {
  const settings = relaySettings({ PRIM_DAILY_CAP: "800" });
  const database = new NodeSqliteDatabase();
  const clock = FakeClock.at("2026-10-02T08:30:00.000Z");
  const logger = createLogger([], () => undefined);
  const relay = new Relay({
    answers: new AnswerStore(database),
    budget: new PrimBudget(database, settings),
    usage: new UsageCounts(database, () => undefined),
    prim: createPrimClient({
      apiKey: "prim-key-of-the-test",
      timeout: settings.primTimeout,
      fetch: lateNetwork(network.prim, () => new Response(primFixture("stop-monitoring-abbesses-stop-area.json"))),
    }),
    clock,
    logger,
    settings,
  });
  const apns = (await testApnsSettings()).settings;
  // The signatures run on threads of their own, which fake timers do not wait for: the token of each key is made before the clock runs,
  // and the start key is a plain text, so that each step of this test waits for the code alone.
  const providerTokens = new ProviderTokens(apns.teamId, clock);
  await Promise.all(apns.keys.map((key) => providerTokens.token(key)));
  const starts = new LiveActivityStarts({
    settings: apns,
    apns: createApnsClient({ fetch: lateNetwork(network.apple, appleReply(network.token)), tokens: providerTokens, bundleId: apns.bundleId }),
    catalog,
    departures: (stopRef) => relay.departures(stopRef),
    clock,
    logger,
    startKey: (text) => Promise.resolve(text),
    counts: { countStartAnswer: () => undefined },
  });
  const ask = route(
    new Request("https://server.test/v1/stations/IDFM:22059/live-activity", {
      method: "POST",
      headers: { authorization: "Bearer app-token-of-the-test", "content-type": "application/json" },
      body: JSON.stringify({ startToken: "0b30557a9fc4e90e33587da2c7ec11365b80a5caef14395e83a8cdf2173c6186" }),
    }),
    {
      logger,
      clock,
      tokens: { app: ["app-token-of-the-test"], owner: "owner-token-of-the-test" },
      relay: {
        departures: (stopRef) => relay.departures(stopRef),
        counts: () => Promise.resolve(relay.counts()),
        metrics: () => Promise.resolve(relay.metrics()),
      },
      liveActivities: { start: (stationId, token) => starts.start(stationId, token), badRequest: () => Promise.resolve() },
    },
  );
  let answered: Response | undefined;
  void ask.then((response) => (answered = response));
  let waited = 0;
  while (answered === undefined && waited < 120_000) {
    await vi.advanceTimersByTimeAsync(100);
    waited += 100;
  }
  if (answered === undefined) {
    throw new Error(`no answer after ${String(waited)} ms`);
  }
  const body = (await answered.json()) as { result: string };
  // The work that goes on past the answer (the channel, the PRIM call) ends here, so that no timer leaks into the next case.
  await vi.runAllTimersAsync();
  return { waited, status: answered.status, result: body.result };
}

const primDelays: Delay[] = [0, 2_900, 3_100, 9_900, "never"];
const appleDelays: Delay[] = [0, 1_000, 2_900, 5_900, 9_900, "never"];
const tokens = ["production", "development"] as const;
const shortest = shortestRecordedWait((set) => set.liveActivityStart?.app.waitForTheAnswerSeconds);

afterEach(() => {
  vi.useRealTimers();
});

describe("the longest start of a Live Activity on the server", () => {
  it.skipIf(shortest === undefined)(
    "answers, with PRIM and Apple as late as their timeouts, early enough for the shortest wait of a build in the field",
    async () => {
      vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
      const room = (shortest?.seconds ?? 0) * 1000 - wakeOfASleepingServerObject - marginForThePhone;
      const tooLate: string[] = [];
      for (const prim of primDelays) {
        for (const apple of appleDelays) {
          for (const token of tokens) {
            const answer = await askToStart({ prim, apple, token });
            if (answer.waited > room) {
              tooLate.push(`PRIM ${String(prim)}, Apple ${String(apple)}, a ${token} token: ${String(answer.waited)} ms`);
            }
          }
        }
      }
      expect(
        tooLate,
        `With ${String(wakeOfASleepingServerObject)} ms for the wake of the server object and ${String(marginForThePhone)} ms for the phone, ` +
          `the server has ${String(room)} ms before the builds of contracts/builds/${shortest?.set ?? ""}/ stop waiting for the start ` +
          `and show their arrival notification. These starts answer later:`,
      ).toEqual([]);
    },
  );

  it("starts when PRIM is slow, with the stops that answered by then, rather than leave the rider with the notification", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    for (const prim of [9_900, "never"] as const) {
      expect(await askToStart({ prim, apple: 0, token: "development" })).toMatchObject({ status: 200, result: "started" });
    }
  });

  it("answers no start, so that the app falls back, when Apple does not answer in time", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    for (const apple of [5_900, "never"] as const) {
      const answer = await askToStart({ prim: 0, apple, token: "production" });
      expect(Math.floor(answer.status / 100), "the builds read only a 200 as a start").not.toBe(2);
      expect(answer.result).toBe("refused");
    }
  });
});
