import { describe, expect, it } from "vitest";
import { minute } from "../../../src/core/time/clock";
import { tallies } from "../../../src/core/usage/usage-counts";
import { answer } from "./fake-prim-client";
import { primFixture } from "./prim-fixtures";
import { relayHarness, type RelayHarness } from "./relay-harness";

const abbesses = "STIF:StopArea:SP:42155:";
const chatelet = "STIF:StopArea:SP:417675:";
const abbessesAnswer = primFixture("stop-monitoring-abbesses-stop-area.json");
const chateletAnswer = primFixture("stop-monitoring-chatelet-rer.json");

/**
 * Cloudflare puts an idle server object to sleep after about 10 s, and a sleep empties its memory.
 * The object keeps a timer while counts wait to be written or a failed stop is in its pause, and no sleep comes while a timer waits:
 * so the test writes the counts that wait, as that timer does, and sleeps only when no failed stop is in its pause.
 */
function sleepIfIdle(harness: RelayHarness): RelayHarness {
  if (harness.relay.nextFailurePauseEnd() !== undefined) {
    return harness;
  }
  harness.usage.flushWhenDue();
  return harness.restart();
}

describe("Relay: a server that sleeps between requests", () => {
  it("gives the answer that it holds after a sleep, with no new PRIM call, to two requests within 60 s, then asks PRIM again", async () => {
    let harness = relayHarness();
    harness.prim.answerWith(() => answer(200, abbessesAnswer));
    const first = await harness.relay.departures(abbesses);

    harness.clock.advance(30_000);
    harness = sleepIfIdle(harness);
    const afterSleep = await harness.relay.departures(abbesses);
    harness.clock.advance(29_999);
    harness = sleepIfIdle(harness);
    const later = await harness.relay.departures(abbesses);

    expect(afterSleep).toEqual(first);
    expect(later).toEqual(first);
    expect(harness.prim.calls).toEqual([abbesses]);

    harness.clock.advance(1);
    harness = sleepIfIdle(harness);
    await harness.relay.departures(abbesses);
    expect(harness.prim.calls).toEqual([abbesses, abbesses]);
  });

  it("counts the same app calls, cache hits, held answers, out answers, PRIM calls and errors whether it sleeps between the requests or not", async () => {
    async function ride(sleeps: boolean) {
      let harness = relayHarness();
      let primAnswer = (stopRef: string) => answer(200, stopRef === abbesses ? abbessesAnswer : chateletAnswer);
      harness.prim.answerWith((stopRef) => primAnswer(stopRef));
      const plan: { at: number; stopRef: string; then?: () => void }[] = [];
      for (let second = 0; second <= 12 * 60; second += 30) {
        plan.push({ at: second * 1000, stopRef: abbesses });
      }
      for (let second = 45; second <= 12 * 60; second += 30) {
        plan.push({ at: second * 1000, stopRef: chatelet });
      }
      plan.sort((a, b) => a.at - b.at);
      const start = harness.clock.now();
      for (const { at, stopRef } of plan) {
        if (at === 45_000) {
          primAnswer = (asked) => (asked === chatelet ? answer(500, "") : answer(200, abbessesAnswer));
        }
        if (at === 165_000) {
          primAnswer = (asked) => answer(200, asked === abbesses ? abbessesAnswer : chateletAnswer);
        }
        if (at === 390_000) {
          primAnswer = () => answer(429, "");
        }
        harness.clock.advance(start + at - harness.clock.now());
        if (sleeps) {
          harness = sleepIfIdle(harness);
        }
        await harness.relay.departures(stopRef);
      }
      return { days: harness.relay.counts().days, primCalls: harness.prim.calls.length };
    }

    const awake = await ride(false);
    const sleeping = await ride(true);

    expect(sleeping).toEqual(awake);
    const [today] = awake.days;
    for (const tally of tallies.filter((name) => name !== "unreadableAnswers")) {
      expect(today?.[tally], tally).toBeGreaterThan(0);
    }
  });

  it("forgets the failed stops after 1 minute, the copies after 5 and the answers after 10 at a request for totals, for metrics or at its own timers, and these change no total", async () => {
    const { relay, prim, clock, database } = relayHarness();
    const startedAt = clock.now();
    prim.answerWith((stopRef) => (stopRef === chatelet ? answer(500, "") : answer(200, abbessesAnswer)));
    await relay.departures(abbesses);
    await relay.departures(chatelet);
    const copies = () => database.all("SELECT stop_ref FROM shared_answers");
    const totals = JSON.stringify(relay.counts().days);

    expect(relay.nextFailurePauseEnd()).toBe(startedAt + minute);
    expect(relay.nextAnswerForgetAt()).toBe(startedAt + 5 * minute);

    clock.advance(minute);
    relay.metrics();
    expect(relay.stopsInMemory()).toEqual([abbesses]);
    expect(relay.nextFailurePauseEnd()).toBeUndefined();

    clock.advance(4 * minute);
    relay.counts();
    expect(copies()).toEqual([]);
    expect(relay.stopsInMemory()).toEqual([abbesses]);
    expect(relay.nextAnswerForgetAt()).toBe(startedAt + 10 * minute);

    clock.advance(5 * minute);
    relay.forgetPastUse();
    expect(relay.stopsInMemory()).toEqual([]);
    expect(relay.nextAnswerForgetAt()).toBeUndefined();

    expect(JSON.stringify(relay.counts().days)).toBe(totals);
    expect(relay.metrics().today.appCalls).toBe(2);
    expect(prim.calls).toEqual([abbesses, chatelet]);
  });
});
