import { describe, expect, it } from "vitest";
import type { RelayAnswer } from "../../../src/core/relay/relay";
import { hour, minute } from "../../../src/core/time/clock";
import { parisHourOfDay } from "../../../src/core/time/paris-time";
import { answer } from "./fake-prim-client";
import { primFixture } from "./prim-fixtures";
import { relayHarness } from "./relay-harness";
import { riderDay, type RiderRequest } from "./rider-day";

const parisMidnight = Date.parse("2026-10-05T22:00:00.000Z");
const allowedByTheEndOf = [2, 4, 7, 9, 11, 14, 16, 136, 328, 392, 394, 397, 399, 401, 404, 406, 454, 590, 734, 790, 792, 795, 797, 800];

interface DayResult {
  callsByParisHour: number[];
  outAnswers: number;
  timesAnswers: number;
  liveActivities: number;
  liveActivitiesWithNoTimes: number;
  firstRequestsOut: number;
  callsWithNoBudget: number;
}

async function runTheDay(requests: readonly RiderRequest[]): Promise<DayResult> {
  const { relay, prim, clock } = relayHarness({ now: new Date(parisMidnight).toISOString() });
  const callsByParisHour = Array<number>(24).fill(0);
  const body = primFixture("stop-monitoring-abbesses-stop-area.json");
  prim.answerWith(() => {
    const parisHour = parisHourOfDay(clock.now());
    callsByParisHour[parisHour] = (callsByParisHour[parisHour] ?? 0) + 1;
    return answer(200, body);
  });

  const answersOf = new Map<number, RelayAnswer[]>();
  let firstRequestsOut = 0;
  for (const request of requests) {
    clock.set(new Date(request.at).toISOString());
    const answers = await Promise.all(request.stopRefs.map((stopRef) => relay.departures(stopRef)));
    if (!answersOf.has(request.liveActivity) && answers.every((answered) => answered.kind === "out")) {
      firstRequestsOut += 1;
    }
    answersOf.set(request.liveActivity, [...(answersOf.get(request.liveActivity) ?? []), ...answers]);
  }

  const all = [...answersOf.values()].flat();
  return {
    callsByParisHour,
    outAnswers: all.filter((answered) => answered.kind === "out").length,
    timesAnswers: all.filter((answered) => answered.kind === "times").length,
    liveActivities: answersOf.size,
    liveActivitiesWithNoTimes: [...answersOf.values()].filter((answers) => answers.every((answered) => answered.kind === "out")).length,
    firstRequestsOut,
    callsWithNoBudget: callsWithASharedAnswerOf60s(requests),
  };
}

function callsWithASharedAnswerOf60s(requests: readonly RiderRequest[]): number {
  const answeredAt = new Map<string, number>();
  let calls = 0;
  for (const { at, stopRefs } of requests) {
    for (const stopRef of stopRefs) {
      const last = answeredAt.get(stopRef);
      if (last === undefined || at - last >= minute) {
        answeredAt.set(stopRef, at);
        calls += 1;
      }
    }
  }
  return calls;
}

function report(riders: number, result: DayResult): void {
  if (process.env.RIDER_DAY_REPORT === "1") {
    console.log(JSON.stringify({ riders, ...result }));
  }
}

describe("Relay: a whole Paris day of riders of the model of the server spike (2 Live Activities a rider, at 08:15 and 18:00)", () => {
  for (const riders of [50, 100]) {
    it(`never passes the cap or the share of an hour for ${String(riders)} riders, and still gives 17:00 and 18:00 at least their own share after the morning peak`, async () => {
      const requests = riderDay({ riders, parisMidnight });
      expect(requests.at(-1)?.at ?? 0).toBeLessThan(parisMidnight + 24 * hour);

      const result = await runTheDay(requests);
      report(riders, result);

      let spent = 0;
      result.callsByParisHour.forEach((calls, parisHour) => {
        spent += calls;
        expect(spent, `calls by the end of ${String(parisHour)}:00`).toBeLessThanOrEqual(allowedByTheEndOf[parisHour] ?? 0);
      });
      expect(spent).toBeLessThanOrEqual(800);
      expect(result.callsWithNoBudget).toBeGreaterThan(800);
      expect(result.callsByParisHour[17]).toBeGreaterThanOrEqual(0.17 * 800);
      expect(result.callsByParisHour[18]).toBeGreaterThanOrEqual(0.18 * 800);
    });
  }
});
