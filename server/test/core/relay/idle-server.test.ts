import { describe, expect, it } from "vitest";
import type { Relay } from "../../../src/core/relay/relay";
import { minute } from "../../../src/core/time/clock";
import { flushDelay, tallies } from "../../../src/core/usage/usage-counts";
import type { PrimReply } from "../../../src/core/relay/prim-client";
import { answer } from "./fake-prim-client";
import { primFixture } from "./prim-fixtures";
import { relayHarness, type RelayHarness } from "./relay-harness";

const abbesses = "STIF:StopArea:SP:42155:";
const chatelet = "STIF:StopArea:SP:417675:";
const abbessesAnswer = primFixture("stop-monitoring-abbesses-stop-area.json");
const chateletAnswer = primFixture("stop-monitoring-chatelet-rer.json");

/** Cloudflare's lifecycle page: an idle object with no timer sleeps 10 s after its last request, and one that a timer keeps awake ends 70 s or more after its last request. */
const sleepAfterNoTimer = 10_000;
const endAfterNoRequest = 70_000;

/**
 * Waits, then sleeps if Cloudflare may have put the object to sleep by then: the object keeps a timer to the next use end of the relay and, for 10 s, one to write the counts.
 * The timers run before the sleep, so the counts that wait are written first.
 */
function waitAndSleepIfIdle(harness: RelayHarness, milliseconds: number): { harness: RelayHarness; slept: boolean } {
  const lastRequest = harness.clock.now();
  const useEnd = harness.relay.nextUseEnd() ?? lastRequest;
  harness.clock.advance(milliseconds);
  const sleepsAt = Math.min(lastRequest + endAfterNoRequest, Math.max(lastRequest + flushDelay, useEnd) + sleepAfterNoTimer);
  if (harness.clock.now() < sleepsAt) {
    return { harness, slept: false };
  }
  harness.usage.flushWhenDue();
  return { harness: harness.restart(), slept: true };
}

interface Visit {
  at: number;
  stopRef: string;
}

function every(stopRef: string, from: number, step: number, to: number): Visit[] {
  const visits: Visit[] = [];
  for (let at = from; at <= to; at += step) {
    visits.push({ at, stopRef });
  }
  return visits;
}

async function ride(visits: Visit[], reply: (at: number, stopRef: string) => PrimReply, sleeps: boolean) {
  let harness = relayHarness();
  const start = harness.clock.now();
  harness.prim.answerWith((stopRef) => reply(harness.clock.now() - start, stopRef));
  let sleepCount = 0;
  for (const { at, stopRef } of [...visits].sort((a, b) => a.at - b.at)) {
    const wait = start + at - harness.clock.now();
    if (sleeps) {
      const waited = waitAndSleepIfIdle(harness, wait);
      harness = waited.harness;
      sleepCount += waited.slept ? 1 : 0;
    } else {
      harness.clock.advance(wait);
    }
    await harness.relay.departures(stopRef);
  }
  harness.usage.flushWhenDue();
  return { totals: { days: harness.restart().relay.counts().days, primCalls: harness.prim.calls.length }, sleepCount };
}

describe("Relay: a server that Cloudflare may put to sleep between requests", () => {
  it("keeps a timer while it holds an answer, so that it does not sleep between refreshes 30 s apart, and gives the held answer with no new PRIM call for 60 s", async () => {
    let harness = relayHarness();
    harness.prim.answerWith(() => answer(200, abbessesAnswer));
    const answeredAt = harness.clock.now();
    const first = await harness.relay.departures(abbesses);
    expect(harness.relay.nextUseEnd()).toBe(answeredAt + 5 * minute);

    let waited = waitAndSleepIfIdle(harness, 30_000);
    expect(waited.slept).toBe(false);
    harness = waited.harness;
    const afterIdle = await harness.relay.departures(abbesses);
    waited = waitAndSleepIfIdle(harness, 29_999);
    expect(waited.slept).toBe(false);
    harness = waited.harness;
    const later = await harness.relay.departures(abbesses);

    expect(afterIdle).toEqual(first);
    expect(later).toEqual(first);
    expect(harness.prim.calls).toEqual([abbesses]);

    harness.clock.advance(1);
    await harness.relay.departures(abbesses);
    expect(harness.prim.calls).toEqual([abbesses, abbesses]);
  });

  it("has no timer once its answers are 5 minutes old and no failed stop is in its pause, so that Cloudflare may put it to sleep", async () => {
    const { relay, prim, clock } = relayHarness();
    prim.answerWith(() => answer(200, abbessesAnswer));
    await relay.departures(abbesses);

    clock.advance(5 * minute - 1);
    expect(relay.nextUseEnd()).toBe(clock.now() + 1);
    clock.advance(1);
    expect(relay.nextUseEnd()).toBeUndefined();
  });

  it("counts the same app calls, cache hits, held answers, out answers, PRIM calls and errors for 2 riders who refresh every 30 s, through a 500 and a 429, as a server that never sleeps", async () => {
    const visits = [...every(abbesses, 0, 30_000, 12 * minute), ...every(chatelet, 45_000, 30_000, 12 * minute)];
    const reply = (at: number, stopRef: string) => {
      if (at >= 390_000) {
        return answer(429, "");
      }
      if (stopRef === chatelet && at < 165_000) {
        return answer(500, "");
      }
      return answer(200, stopRef === abbesses ? abbessesAnswer : chateletAnswer);
    };

    const awake = await ride(visits, reply, false);
    const sleeping = await ride(visits, reply, true);

    expect(sleeping.sleepCount).toBe(0);
    expect(sleeping.totals).toEqual(awake.totals);
    const [today] = awake.totals.days;
    for (const tally of tallies.filter((name) => name !== "unreadableAnswers")) {
      expect(today?.[tally], tally).toBeGreaterThan(0);
    }
  });

  it("loses no count when it sleeps between riders who come every 90 s", async () => {
    const visits = [...every(abbesses, 0, 90_000, 30 * minute), ...every(chatelet, 10_000, 90_000, 30 * minute)];
    const reply = (_at: number, stopRef: string) => answer(200, stopRef === abbesses ? abbessesAnswer : chateletAnswer);

    const awake = await ride(visits, reply, false);
    const sleeping = await ride(visits, reply, true);

    expect(sleeping.sleepCount, "a sleep before each visit that comes 80 s after the one before it").toBe(20);
    expect(sleeping.totals).toEqual(awake.totals);
    expect(awake.totals.days[0]).toMatchObject({ appCalls: visits.length, primCalls: visits.length });
  });

  const forgetters: [string, (relay: Relay) => void][] = [
    [
      "its own timer",
      (relay) => {
        relay.forgetPastUse();
      },
    ],
    ["a request for totals", (relay) => relay.counts()],
    ["a request for metrics", (relay) => relay.metrics()],
  ];
  for (const [name, forget] of forgetters) {
    it(`forgets the failed stops after 1 minute and the answers after 10 at ${name}, and this changes no total`, async () => {
      const { relay, prim, clock } = relayHarness();
      const startedAt = clock.now();
      prim.answerWith((stopRef) => (stopRef === chatelet ? answer(500, "") : answer(200, abbessesAnswer)));
      await relay.departures(abbesses);
      await relay.departures(chatelet);
      const totals = JSON.stringify(relay.counts().days);
      expect(relay.nextUseEnd()).toBe(startedAt + minute);

      clock.advance(minute);
      forget(relay);
      expect(relay.stopsInMemory()).toEqual([abbesses]);
      expect(relay.nextUseEnd()).toBe(startedAt + 5 * minute);

      clock.advance(9 * minute - 1);
      forget(relay);
      expect(relay.stopsInMemory()).toEqual([abbesses]);
      clock.advance(1);
      forget(relay);
      expect(relay.stopsInMemory()).toEqual([]);
      expect(relay.nextUseEnd()).toBeUndefined();

      expect(JSON.stringify(relay.counts().days)).toBe(totals);
      expect(relay.metrics().today.appCalls).toBe(2);
      expect(prim.calls).toEqual([abbesses, chatelet]);
    });
  }
});
