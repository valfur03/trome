import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { route } from "../../../src/core/http/router";
import type { StartResult } from "../../../src/core/live-activity/live-activity-starts";
import { createLogger } from "../../../src/core/logging/logger";
import { minute } from "../../../src/core/time/clock";
import { answer } from "../relay/fake-prim-client";
import { primFixture } from "../relay/prim-fixtures";
import { relayHarness, type RelayHarness } from "../relay/relay-harness";

interface Example {
  request: { method: string; path: string; headers: Record<string, string>; body?: { startToken: string } };
  response: {
    status: number;
    headers: Record<string, string>;
    body?: unknown;
    bodyIsPrimAnswer?: string;
  };
}

const folder = fileURLToPath(new URL("../../../../contracts/api/", import.meta.url));
const appToken = "app-token-of-the-test";
const requestTime = "2026-10-02T08:30:00.000Z";
const abbesses = "STIF:StopArea:SP:42155:";

const scenarios: Record<string, (harness: RelayHarness) => Promise<unknown>> = {
  "departures-times.json": () => Promise.resolve(),
  "departures-times-held.json": async (harness) => {
    harness.clock.advance(-3 * minute);
    await harness.relay.departures(abbesses);
    harness.clock.advance(3 * minute);
    for (let index = 1; index < 394; index += 1) {
      await harness.relay.departures(`STIF:StopArea:SP:${String(index)}:`);
    }
  },
  "departures-out-budget.json": async (harness) => {
    for (let index = 1; index <= 394; index += 1) {
      await harness.relay.departures(`STIF:StopArea:SP:${String(index)}:`);
    }
  },
  "departures-out-prim-limit.json": (harness) => {
    harness.prim.answerWith(() => answer(429, '{"message":"Too many requests"}'));
    return Promise.resolve();
  },
  "departures-out-prim-failure.json": (harness) => {
    harness.prim.answerWith(() => answer(500, '{"message":"Internal error"}'));
    return Promise.resolve();
  },
  "departures-unauthorized.json": () => Promise.resolve(),
  "departures-bad-stop.json": () => Promise.resolve(),
};

/** The answers of the start of a Live Activity: the route says what the start gave, whatever Apple did. */
const starts: Record<string, StartResult> = {
  "live-activity-started.json": { result: "started" },
  "live-activity-already-started.json": { result: "already-started" },
  "live-activity-refused.json": { result: "refused", reason: "BadDeviceToken" },
  "live-activity-refused-no-answer.json": { result: "refused", reason: "no-answer" },
  "live-activity-not-set-up.json": { result: "not-set-up" },
};

function example(name: string): Example {
  return JSON.parse(readFileSync(`${folder}${name}`, "utf8")) as Example;
}

describe("the API examples of contracts/api/", () => {
  it("each have a scenario here", () => {
    expect(readdirSync(folder).filter((name) => name.endsWith(".json")).sort()).toEqual(
      [...Object.keys(scenarios), ...Object.keys(starts)].sort(),
    );
  });

  for (const [name, setUp] of Object.entries(scenarios)) {
    it(`are what the server answers: ${name}`, async () => {
      const { request, response } = example(name);
      const harness = relayHarness({ now: requestTime });
      await setUp(harness);
      const callsBefore = harness.prim.calls.length;

      const headers = Object.fromEntries(
        Object.entries(request.headers).map(([key, value]) => [key, value.replace("<APP_TOKEN>", appToken)]),
      );
      const answered = await route(new Request(`https://server.test${request.path}`, { method: request.method, headers }), {
        logger: createLogger([], () => undefined),
        clock: harness.clock,
        tokens: { app: [appToken], owner: "owner-token-of-the-test" },
        relay: { departures: (stopRef) => harness.relay.departures(stopRef), counts: () => Promise.resolve(harness.relay.counts()),
          metrics: () => Promise.resolve(harness.relay.metrics()),
        },
        liveActivities: { start: () => Promise.reject(new Error("no start in this test")) },
      });

      expect(answered.status).toBe(response.status);
      expect(Object.fromEntries(answered.headers)).toEqual(response.headers);
      if (response.bodyIsPrimAnswer !== undefined) {
        expect(await answered.text()).toBe(primFixture(response.bodyIsPrimAnswer));
      } else {
        expect(await answered.json()).toEqual(response.body);
      }
      if (response.status === 401 || response.status === 400) {
        expect(harness.prim.calls.length).toBe(callsBefore);
        expect(harness.relay.counts().days).toEqual([]);
      }
    });
  }

  for (const [name, result] of Object.entries(starts)) {
    it(`are what the server answers: ${name}`, async () => {
      const { request, response } = example(name);
      const asked: [string, string][] = [];
      const headers = Object.fromEntries(
        Object.entries(request.headers).map(([key, value]) => [key, value.replace("<APP_TOKEN>", appToken)]),
      );
      const harness = relayHarness({ now: requestTime });

      const answered = await route(
        new Request(`https://server.test${request.path}`, { method: request.method, headers, body: JSON.stringify(request.body) }),
        {
          logger: createLogger([], () => undefined),
          clock: harness.clock,
          tokens: { app: [appToken], owner: "owner-token-of-the-test" },
          relay: { departures: () => Promise.reject(new Error("no departures in this test")),
            counts: () => Promise.resolve(harness.relay.counts()), metrics: () => Promise.resolve(harness.relay.metrics()),
          },
          liveActivities: {
            start: (stationId, startToken) => {
              asked.push([stationId, startToken]);
              return Promise.resolve(result);
            },
          },
        },
      );

      expect(asked).toEqual([["IDFM:monomodalStopPlace:43234", request.body?.startToken]]);
      expect(answered.status).toBe(response.status);
      expect(Object.fromEntries(answered.headers)).toEqual(response.headers);
      expect(await answered.json()).toEqual(response.body);
    });
  }
});
