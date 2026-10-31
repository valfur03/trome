import { exports } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { primEndpoint } from "../../src/core/relay/prim-client";
import { brokenPromises, type Answered, type PromisedAnswer, type PromiseSet } from "./build-promises";
import { filled, recordedSets } from "./recorded-sets";
import { judgeTheStartPromises } from "./start-promises";
import { forgetEverything } from "./forget-everything";

// Every recorded set of contracts/builds/ is asked to the whole Worker (the router, the server object, its storage and its
// PRIM client), with PRIM faked by the recorded answers of the set, and each answer is judged as the builds of the set read it.
// Why: a build that riders hold never changes, so the server keeps every answer of its set until the release guide retires it.

type PrimReply = Response | "unreachable";

interface FakePrim {
  reply: (stopRef: string) => PrimReply;
  calls: string[];
}

function fakePrim(): FakePrim {
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  // 02:30 in Paris: the day has given few calls yet, so a dozen stops spend them, and every run asks at the same time.
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-02T00:30:00.000Z"));
  const prim: FakePrim = { reply: () => new Response("{}"), calls: [] };
  vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (`${url.origin}${url.pathname}` !== primEndpoint) {
      return Promise.reject(new Error(`No network in the tests: ${url.origin}`));
    }
    const stopRef = url.searchParams.get("MonitoringRef") ?? "";
    prim.calls.push(stopRef);
    const reply = prim.reply(stopRef);
    return reply === "unreachable" ? Promise.reject(new TypeError("Network connection lost.")) : Promise.resolve(reply);
  });
  return prim;
}

async function ask(set: PromiseSet, stop: string, requestHeaders: Record<string, string> = {}): Promise<Answered> {
  const headers = Object.fromEntries(
    Object.entries({ ...set.request.headers, ...requestHeaders }).map(([name, value]) => [name, filled(value)]),
  );
  const response = await exports.default.fetch(`https://server.test${set.request.path.replace("<STOP>", stop)}`, {
    method: set.request.method,
    headers,
  });
  return { status: response.status, headers: response.headers, text: await response.text() };
}

// Spends the PRIM calls of this hour on other stops, until a new stop gets no PRIM call.
async function spendTheCallsOfTheHour(set: PromiseSet, prim: { calls: string[] }): Promise<void> {
  for (let index = 1; index <= 1000; index += 1) {
    const callsBefore = prim.calls.length;
    await ask(set, `STIF:StopArea:SP:${String(index)}:`);
    if (prim.calls.length === callsBefore) {
      return;
    }
  }
  throw new Error("the server still asked PRIM after 1000 stops: the calls of the hour never ran out");
}

type Situation = (context: {
  set: PromiseSet;
  promise: PromisedAnswer;
  stop: string;
  primAnswer: string;
  prim: FakePrim;
}) => Promise<Answered>;

const primAnswers: Situation = ({ set, stop, primAnswer, prim }) => {
  prim.reply = () => new Response(primAnswer);
  return ask(set, stop);
};

// Each "when" of a recorded set, in each way that the server meets it, as the server is brought to it.
// A recorded "when" with no situation here fails the check. A way is added when the server gets a new path to the same answer.
const situations: Record<string, Record<string, Situation>> = {
  "PRIM answers": { "with the recorded answer": primAnswers },
  "PRIM answers with no train": { "with the recorded answer": primAnswers },
  "the calls of the hour are spent, and the server holds a recent answer of the stop": {
    "after an answer of the stop": async ({ set, stop, primAnswer, prim }) => {
      prim.reply = () => new Response(primAnswer);
      await ask(set, stop);
      await spendTheCallsOfTheHour(set, prim);
      return ask(set, stop);
    },
  },
  "the calls of the hour are spent": {
    "with no answer of the stop": async ({ set, stop, primAnswer, prim }) => {
      prim.reply = () => new Response(primAnswer);
      await spendTheCallsOfTheHour(set, prim);
      return ask(set, stop);
    },
  },
  "PRIM answered 429": {
    "with status 429": ({ set, stop, prim }) => {
      prim.reply = () => new Response('{"message":"Too many requests"}', { status: 429 });
      return ask(set, stop);
    },
  },
  "PRIM fails": {
    "with status 500": ({ set, stop, prim }) => {
      prim.reply = () => new Response('{"message":"Internal error"}', { status: 500 });
      return ask(set, stop);
    },
    "with no connection": ({ set, stop, prim }) => {
      prim.reply = () => "unreachable";
      return ask(set, stop);
    },
    "with status 200 and no times": ({ set, stop, prim }) => {
      prim.reply = () => new Response("<html>Bad gateway</html>");
      return ask(set, stop);
    },
  },
  "the server does not accept the app token": {
    "with a token it does not know": ({ set, stop, promise }) => ask(set, stop, promise.requestHeaders),
  },
};

afterEach(forgetEverything);

describe("the recorded sets of promises of contracts/builds/", () => {
  const sets = recordedSets();

  it("are read: at least the set of the first builds", () => {
    expect(sets.map(({ set }) => set.builds).flat()).toContain("1.0.0 (1)");
  });

  for (const { folder, set, file } of sets) {
    for (const promise of set.answers) {
      const builds = set.builds.join(", ");
      it(`${builds}: when ${promise.when}, the server gives what they read`, async () => {
        const situation = situations[promise.when];
        expect(
          situation,
          `${builds} (contracts/builds/${folder}/): the server tests have no situation for "${promise.when}". Add it to server/test/cloudflare/build-promises.test.ts; never edit the set.`,
        ).toBeDefined();
        const stops = promise.askFor === "every stop" ? set.stops : promise.askFor === "the first stop" ? set.stops.slice(0, 1) : [];
        expect(stops.length, `${builds}: askFor "${promise.askFor}" names no stop`).toBeGreaterThan(0);

        for (const { stop, prim: recording } of stops) {
          for (const [way, bring] of Object.entries(situation ?? {})) {
            const prim = fakePrim();
            const primAnswer = file(promise.prim ?? recording);
            const answered = await bring({ set, promise, stop, primAnswer, prim });
            expect(
              brokenPromises(promise, answered, primAnswer),
              `The server breaks a promise to builds ${builds} (contracts/builds/${folder}/promises.json): when ${promise.when} (${way}), for ${stop}, ` +
                `they read ${promise.reads}. Riders of these builds still use them: change the server by adding, never by changing what they read.`,
            ).toEqual([]);
            await forgetEverything();
          }
        }
      });
    }
  }
});

judgeTheStartPromises("with no push key");
