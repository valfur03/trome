import { env, exports } from "cloudflare:workers";
import { abortAllDurableObjects, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { relayObject } from "../../src/cloudflare/relay-object";
import { primEndpoint } from "../../src/core/relay/prim-client";
import { brokenPromises, type Answered, type PromisedAnswer, type StartPromises } from "./build-promises";
import { recordedAnswer } from "./fake-prim";
import { filled, recordedSets } from "./recorded-sets";

// The start of the Live Activity in each recorded set (its key liveActivityStart) is asked to the whole Worker, with PRIM
// and Apple's push service faked, and each answer is judged as the builds of the set read it.
// Most situations need a push key, which only the tests named *-with-push-key run with (vitest.config.ts):
// build-promises.test.ts judges the answers with no push key, and build-promises-with-push-key.test.ts the others.

export type PushKey = "with a push key" | "with no push key";

interface FakeNetwork {
  prim: "answers" | "unreachable";
  apple: "takes the start" | "refuses the start" | "refuses the channel" | "does not answer";
}

interface StartContext {
  start: StartPromises;
  promise: PromisedAnswer;
  station: string;
  startToken: string;
  network: FakeNetwork;
}

type StartSituation = (context: StartContext) => Promise<Answered>;

async function askToStart(start: StartPromises, station: string, startToken: string, requestHeaders: Record<string, string> = {}): Promise<Answered> {
  const headers = Object.fromEntries(Object.entries({ ...start.request.headers, ...requestHeaders }).map(([name, value]) => [name, filled(value)]));
  const body = Object.fromEntries(Object.entries(start.request.body).map(([key, value]) => [key, value.replace("<START_TOKEN>", startToken)]));
  const response = await exports.default.fetch(`https://server.test${start.request.path.replace("<STATION>", station)}`, {
    method: start.request.method,
    headers,
    body: JSON.stringify(body),
  });
  return { status: response.status, headers: response.headers, text: await response.text() };
}

const appleRefusal = (reason: string, status = 400): Response => new Response(JSON.stringify({ reason }), { status });

function fakeNetwork(): FakeNetwork {
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-10-02T06:30:00.000Z"));
  const network: FakeNetwork = { prim: "answers", apple: "takes the start" };
  vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
    const url = input instanceof Request ? input.url : String(input);
    const method = init?.method ?? "GET";
    if (url.startsWith(primEndpoint)) {
      return network.prim === "answers"
        ? Promise.resolve(new Response(recordedAnswer("stop-monitoring-abbesses-stop-area.json")))
        : Promise.reject(new TypeError("Network connection lost."));
    }
    if (!new URL(url).hostname.endsWith("push.apple.com")) {
      return Promise.reject(new Error(`No network in the tests: ${url}`));
    }
    if (network.apple === "does not answer") {
      return Promise.reject(new TypeError("Network connection lost."));
    }
    if (url.includes("api-manage-broadcast") && method === "POST") {
      return Promise.resolve(
        network.apple === "refuses the channel"
          ? appleRefusal("InvalidProviderToken", 403)
          : new Response(null, { status: 201, headers: { "apns-channel-id": "channel-1" } }),
      );
    }
    if (url.includes("/3/device/") && network.apple === "refuses the start") {
      return Promise.resolve(appleRefusal("BadDeviceToken"));
    }
    return Promise.resolve(new Response(null, { status: 200 }));
  });
  return network;
}

const ask: StartSituation = ({ start, station, startToken }) => askToStart(start, station, startToken);

// Each "when" of the start in a recorded set, in each way that the server meets it, as the server is brought to it.
// A recorded "when" with no situation here fails the check. A way is added when the server gets a new path to the same answer.
const situations: Record<PushKey, Record<string, Record<string, StartSituation>>> = {
  "with a push key": {
    "Apple's push service takes the start": {
      "while PRIM answers": ask,
      "while PRIM does not answer": (context) => {
        context.network.prim = "unreachable";
        return ask(context);
      },
    },
    "the same start token asks again for the same station, a moment after the start": {
      "after a start that Apple took": async (context) => {
        await ask(context);
        return ask(context);
      },
    },
    "Apple's push service refuses the start": {
      "with the reason BadDeviceToken of both services": (context) => {
        context.network.apple = "refuses the start";
        return ask(context);
      },
      "when it refuses the channel of the station": (context) => {
        context.network.apple = "refuses the channel";
        return ask(context);
      },
    },
    "Apple's push service does not answer": {
      "with no connection": (context) => {
        context.network.apple = "does not answer";
        return ask(context);
      },
    },
    "the server does not accept the app token": {
      "with a token it does not know": ({ start, station, startToken, promise }) => askToStart(start, station, startToken, promise.requestHeaders),
    },
  },
  "with no push key": {
    "the server has no push key of Apple": { "on a deploy with no push key": ask },
  },
};

async function forgetEverything(): Promise<void> {
  vi.useRealTimers();
  vi.restoreAllMocks();
  await runInDurableObject(relayObject(env), (_object, state) => state.storage.deleteAll());
  await abortAllDurableObjects();
}

function asks(start: StartPromises, askFor: string): { station: string; startToken: string }[] {
  const tokens = start.startTokens.map(({ startToken }) => startToken);
  const stations = start.stations.map(({ station }) => station);
  if (askFor === "every station and start token") {
    return stations.flatMap((station) => tokens.map((startToken) => ({ station, startToken })));
  }
  if (askFor === "the first station") {
    return stations.slice(0, 1).flatMap((station) => tokens.slice(0, 1).map((startToken) => ({ station, startToken })));
  }
  return [];
}

/** Judges the start answers of every recorded set that the server meets with this push key; the run with no push key also fails on an answer that no situation brings. */
export function judgeTheStartPromises(pushKey: PushKey): void {
  const own = situations[pushKey];
  const known = (when: string): boolean => Object.values(situations).some((situationsOfAKey) => situationsOfAKey[when] !== undefined);

  const judged = recordedSets().flatMap(({ folder, set }) =>
    (set.liveActivityStart?.answers ?? [])
      .filter((promise) => own[promise.when] !== undefined || (!known(promise.when) && pushKey === "with no push key"))
      .map((promise) => ({ folder, builds: set.builds.join(", "), start: set.liveActivityStart as StartPromises, promise })),
  );
  // Before the first set that holds the start, there is nothing to judge, and an empty suite would fail the run.
  if (judged.length === 0) {
    return;
  }

  describe(`the start of the Live Activity in the recorded sets of promises, ${pushKey}`, () => {
    afterEach(forgetEverything);

    for (const { folder, builds, start, promise } of judged) {
      it(`${builds}: when ${promise.when}, the server gives what they read`, async () => {
        const situation = own[promise.when];
        expect(
          situation,
          `${builds} (contracts/builds/${folder}/): the server tests have no situation for the start "${promise.when}". Add it to server/test/cloudflare/start-promises.ts; never edit the set.`,
        ).toBeDefined();
        const asked = asks(start, promise.askFor);
        expect(asked.length, `${builds}: askFor "${promise.askFor}" names no station`).toBeGreaterThan(0);

        for (const { station, startToken } of asked) {
          for (const [way, bring] of Object.entries(situation ?? {})) {
            const network = fakeNetwork();
            const answered = await bring({ start, promise, station, startToken, network });
            expect(
              brokenPromises(promise, answered, ""),
              `The server breaks a promise to builds ${builds} (contracts/builds/${folder}/promises.json): when ${promise.when} (${way}), for ${station}, ` +
                `they read ${promise.reads}. Riders of these builds still use them: change the server by adding, never by changing what they read.`,
            ).toEqual([]);
            await forgetEverything();
          }
        }
      });
    }
  });
}
