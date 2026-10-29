import { describe, expect, it } from "vitest";
import type { RelayAnswer } from "../../../src/core/relay/relay";
import { updateWindow } from "../../../src/core/live-activity/station-updates";
import { minute } from "../../../src/core/time/clock";
import { parisHourOfDay } from "../../../src/core/time/paris-time";
import { peakDayShape } from "../budget/peak-day-shape";
import { answer } from "./fake-prim-client";
import { primFixture } from "./prim-fixtures";
import { relayHarness } from "./relay-harness";
import { measuredStartShares, riderDay, type RiderRequest } from "./rider-day";

const parisMidnight = Date.parse("2026-10-05T22:00:00.000Z");
const allowedByTheEndOf = [4, 8, 12, 16, 20, 34, 68, 142, 224, 272, 309, 346, 387, 426, 465, 509, 565, 633, 693, 734, 760, 776, 790, 800];
const earlyHours = { from: 5, to: 7 };
const serverUpdates = { length: { from: updateWindow, to: updateWindow }, wait: { from: 30_000, to: 2 * minute } };

interface Figures {
  calls: number;
  outAnswers: number;
  answers: number;
  liveActivities: number;
  liveActivitiesWithNoTimes: number;
}

interface DayResult {
  callsByParisHour: number[];
  callsWithNoBudget: number;
  day: Figures;
  early: Figures;
}

interface LiveActivityAnswers {
  start: number;
  answers: { at: number; answer: RelayAnswer }[];
}

const isEarly = (at: number) => {
  const parisHour = parisHourOfDay(at);
  return parisHour >= earlyHours.from && parisHour < earlyHours.to;
};

function figures(liveActivities: readonly LiveActivityAnswers[], calls: number, inWindow: (at: number) => boolean): Figures {
  const answers = liveActivities.flatMap((liveActivity) => liveActivity.answers).filter(({ at }) => inWindow(at));
  const started = liveActivities.filter(({ start }) => inWindow(start));
  return {
    calls,
    outAnswers: answers.filter(({ answer: answered }) => answered.kind === "out").length,
    answers: answers.length,
    liveActivities: started.length,
    liveActivitiesWithNoTimes: started.filter((liveActivity) => liveActivity.answers.every(({ answer: answered }) => answered.kind === "out")).length,
  };
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

  const liveActivities = new Map<number, LiveActivityAnswers>();
  for (const request of requests) {
    clock.set(new Date(request.at).toISOString());
    const answers = await Promise.all(request.stopRefs.map((stopRef) => relay.departures(stopRef)));
    const liveActivity = liveActivities.get(request.liveActivity) ?? { start: request.at, answers: [] };
    liveActivity.answers.push(...answers.map((answered) => ({ at: request.at, answer: answered })));
    liveActivities.set(request.liveActivity, liveActivity);
  }

  const all = [...liveActivities.values()];
  const sum = (hours: readonly number[]) => hours.reduce((total, calls) => total + calls, 0);
  return {
    callsByParisHour,
    callsWithNoBudget: callsWithASharedAnswerOf60s(requests),
    day: figures(all, sum(callsByParisHour), () => true),
    early: figures(all, sum(callsByParisHour.slice(earlyHours.from, earlyHours.to)), isEarly),
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

function report(run: Record<string, unknown>): void {
  if (process.env.RIDER_DAY_REPORT === "1") {
    console.log(JSON.stringify(run));
  }
}

function expectWithinTheShares(result: DayResult): void {
  let spent = 0;
  result.callsByParisHour.forEach((calls, parisHour) => {
    spent += calls;
    expect(spent, `calls by the end of ${String(parisHour)}:00`).toBeLessThanOrEqual(allowedByTheEndOf[parisHour] ?? 0);
  });
  expect(spent).toBeLessThanOrEqual(800);
  expect(result.callsWithNoBudget).toBeGreaterThan(800);
}

// Nothing in these tests waits: the clock and PRIM are fakes, so their time is only CPU (about 0.1 s each on an idle Mac).
// On a busy Mac, a CPU test gets a small share of a core, and the default limit of 5 s measures the Mac, not the relay.
// So their limit is far above their time on a very busy Mac, and only catches a loop that never ends.
const onlyCpuTimeout = 30_000;

describe("Relay: a whole Paris day of riders of the model of the server spike (2 Live Activities a rider, 6 to 14 minutes each)", { timeout: onlyCpuTimeout }, () => {
  describe("riders who start by the measured hourly profile of the Paris rail validations", () => {
    it("serves 50 riders within the cap and the shares of the hours, with times for more than 95 in 100 Live Activities and for every Live Activity that starts from 05:00 to 07:00, over 4 days", async () => {
      let liveActivities = 0;
      let withNoTimes = 0;
      let earlyLiveActivities = 0;
      let earlyWithNoTimes = 0;
      for (const seed of [1, 2, 3, 4]) {
        const result = await runTheDay(riderDay({ riders: 50, parisMidnight, startShares: measuredStartShares, seed }));
        report({ starts: "measured", riders: 50, seed, ...result });

        expectWithinTheShares(result);
        liveActivities += result.day.liveActivities;
        withNoTimes += result.day.liveActivitiesWithNoTimes;
        earlyLiveActivities += result.early.liveActivities;
        earlyWithNoTimes += result.early.liveActivitiesWithNoTimes;
      }

      expect(withNoTimes / liveActivities).toBeLessThan(0.05);
      expect(earlyLiveActivities).toBeGreaterThan(5);
      expect(earlyWithNoTimes).toBe(0);
    });

    it("never passes the cap or the shares of the hours for 100 riders", async () => {
      const result = await runTheDay(riderDay({ riders: 100, parisMidnight, startShares: measuredStartShares }));
      report({ starts: "measured", riders: 100, ...result });

      expectWithinTheShares(result);
    });
  });

  describe("riders whose Live Activities the server starts, and updates for 20 minutes every 30 s to 2 minutes, as the app in the background asks", () => {
    // RIDER_DAY_REPORT=1 prints the day: on 2026-10-29, 15 riders made 522 to 633 PRIM calls with no cap, and at most 2 in 100 answers were "out".
    // With updates for 45 minutes, they would make 1,130 to 1,400 calls with no cap, and 15 to 30 in 100 answers would be "out" under the cap of 800.
    it("keeps 15 riders within the cap and the shares of the hours, with almost every answer in time", async () => {
      for (const seed of [1, 2, 3, 4]) {
        const requests = riderDay({ riders: 15, parisMidnight, startShares: measuredStartShares, seed, outing: serverUpdates });
        const result = await runTheDay(requests);
        report({ starts: "server", riders: 15, seed, ...result });
        expect(result.day.outAnswers / result.day.answers, "answers out").toBeLessThan(0.02);

        let spent = 0;
        result.callsByParisHour.forEach((calls, parisHour) => {
          spent += calls;
          expect(spent, `calls by the end of ${String(parisHour)}:00`).toBeLessThanOrEqual(allowedByTheEndOf[parisHour] ?? 0);
        });
      }
    });
  });

  describe("riders who start more at the peaks than all riders, by the old guessed day shape", () => {
    for (const riders of [50, 100]) {
      it(`never passes the cap or the shares of the hours for ${String(riders)} riders`, async () => {
        const result = await runTheDay(riderDay({ riders, parisMidnight, startShares: peakDayShape }));
        report({ starts: "peak-heavy", riders, ...result });

        expectWithinTheShares(result);
      });
    }
  });
});
