import { describe, expect, it } from "vitest";
import type { RelayAnswer } from "../../../src/core/relay/relay";
import { hour, minute } from "../../../src/core/time/clock";
import { answer } from "./fake-prim-client";
import { primFixture } from "./prim-fixtures";
import { relayHarness } from "./relay-harness";

const abbesses = "STIF:StopArea:SP:42155:";
const chatelet = "STIF:StopArea:SP:417675:";
const abbessesAnswer = primFixture("stop-monitoring-abbesses-stop-area.json");
const chateletAnswer = primFixture("stop-monitoring-chatelet-rer.json");
const nextParisDay = Date.parse("2026-10-02T22:00:00.000Z");

function stop(index: number): string {
  return `STIF:StopArea:SP:${String(100_000 + index)}:`;
}

function times(body: string, primAnsweredAt: number): RelayAnswer {
  return { kind: "times", body, primAnsweredAt };
}

describe("Relay: one shared answer for each stop", () => {
  it("asks PRIM for a stop the first time, and gives its answer as PRIM gave it, with the time when PRIM gave it", async () => {
    const { relay, prim, clock } = relayHarness();

    expect(await relay.departures(abbesses)).toEqual(times(abbessesAnswer, clock.now()));
    expect(prim.calls).toEqual([abbesses]);
  });

  it("gives the same answer with no PRIM call while the answer is younger than 60 s, and asks again at 60 s", async () => {
    const { relay, prim, clock } = relayHarness();
    const firstAt = clock.now();
    await relay.departures(abbesses);

    clock.advance(59_999);
    expect(await relay.departures(abbesses)).toEqual(times(abbessesAnswer, firstAt));
    expect(prim.calls).toHaveLength(1);

    clock.advance(1);
    expect(await relay.departures(abbesses)).toEqual(times(abbessesAnswer, clock.now()));
    expect(prim.calls).toHaveLength(2);
  });

  it("keeps one answer for each stop", async () => {
    const { relay, prim, clock } = relayHarness();
    prim.answerWith((stopRef) => answer(200, stopRef === chatelet ? chateletAnswer : abbessesAnswer));

    expect(await relay.departures(abbesses)).toEqual(times(abbessesAnswer, clock.now()));
    expect(await relay.departures(chatelet)).toEqual(times(chateletAnswer, clock.now()));
    expect(await relay.departures(abbesses)).toEqual(times(abbessesAnswer, clock.now()));
    expect(prim.calls).toEqual([abbesses, chatelet]);
  });

  it("makes the requests for a stop that come while its PRIM call is in flight wait for that one call", async () => {
    const { relay, prim, clock } = relayHarness();
    prim.answerWith(() => "wait");

    const answers = Promise.all(Array.from({ length: 50 }, () => relay.departures(abbesses)));
    const other = relay.departures(chatelet);
    clock.advance(800);
    prim.release(answer(200, abbessesAnswer));

    const expected = times(abbessesAnswer, clock.now());
    expect(await answers).toEqual(Array.from({ length: 50 }, () => expected));
    await other;
    expect(prim.calls).toEqual([abbesses, chatelet]);
  });

  it("asks PRIM again for a stop after its call in flight has ended", async () => {
    const { relay, prim, clock } = relayHarness();
    prim.answerWith(() => "wait");
    const first = relay.departures(abbesses);
    prim.release();
    await first;

    clock.advance(minute);
    const second = relay.departures(abbesses);
    prim.release();
    await second;

    expect(prim.calls).toEqual([abbesses, abbesses]);
  });
});

describe("Relay: the daily cap of PRIM calls", () => {
  it("never passes the cap when many requests for many stops come at the same time", async () => {
    const { relay, prim } = relayHarness();
    prim.answerWith(() => "wait");

    const answers = Array.from({ length: 1200 }, (_, index) => relay.departures(stop(index % 1000)));

    expect(prim.calls).toHaveLength(800);
    expect(new Set(prim.calls).size).toBe(800);
    prim.release();
    const results = await Promise.all(answers);
    expect(results.filter((result) => result.kind === "times")).toHaveLength(1000);
    expect(results.filter((result) => result.kind === "out")).toEqual(
      Array.from({ length: 200 }, () => ({ kind: "out", reason: "budget", retryAt: nextParisDay })),
    );
  });

  it("adds to the count before the PRIM call, so a call in flight already counts", () => {
    const { relay, prim, database } = relayHarness();
    prim.answerWith(() => "wait");

    void relay.departures(abbesses);

    expect(prim.waiting).toBe(1);
    expect(database.all("SELECT paris_day, calls FROM prim_budget")).toEqual([{ paris_day: "2026-10-02", calls: 1 }]);
  });

  it("never passes the cap over a whole day of requests, with failures, 429s and restarts", async () => {
    let harness = relayHarness({ now: "2026-10-01T22:00:00.000Z" });
    let seed = 7;
    const random = () => {
      seed = (seed * 1_103_515_245 + 12_345) % 2 ** 31;
      return seed / 2 ** 31;
    };
    harness.prim.answerWith(() => {
      const draw = random();
      if (draw < 0.1) return answer(500, '{"message":"error"}');
      if (draw < 0.15) return { kind: "unreachable", reason: "TypeError" };
      if (draw < 0.16) return answer(429, "");
      if (draw < 0.2) return answer(200, '{"Siri":{"ServiceDelivery":{"StopMonitoringDelivery":[{"Status":"false","ErrorCondition":{}}]}}}');
      return answer(200, abbessesAnswer);
    });

    const end = Date.parse("2026-10-02T22:00:00.000Z");
    let mostCalls = 0;
    while (harness.clock.now() < end) {
      await Promise.all(Array.from({ length: 1 + Math.floor(random() * 12) }, () => harness.relay.departures(stop(Math.floor(random() * 120)))));
      mostCalls = Math.max(mostCalls, harness.prim.calls.length);
      if (random() < 0.05) {
        harness = harness.restart();
      }
      harness.clock.advance(Math.floor(random() * 120_000));
    }

    expect(mostCalls).toBe(800);
    expect(harness.prim.calls).toHaveLength(800);
    const [budget] = harness.database.all<{ calls: number }>("SELECT calls FROM prim_budget WHERE paris_day = '2026-10-02'");
    expect(budget?.calls).toBe(800);
  }, 20_000);

  it("keeps the count of the day when the server restarts in the middle of the day", async () => {
    const harness = relayHarness();
    for (let index = 0; index < 500; index += 1) {
      await harness.relay.departures(stop(index));
    }

    const restarted = harness.restart();
    for (let index = 500; index < 1000; index += 1) {
      await restarted.relay.departures(stop(index));
    }

    expect(harness.prim.calls).toHaveLength(800);
  });

  it("counts the failed calls too", async () => {
    const { relay, prim } = relayHarness({ dailyCap: "3" });
    prim.answerWith(() => answer(500, "PRIM failed"));

    for (let index = 0; index < 10; index += 1) {
      await relay.departures(stop(index));
    }

    expect(prim.calls).toHaveLength(3);
  });

  it("takes the cap from its setting, and starts a new count at the start of the next Paris day", async () => {
    const { relay, prim, clock } = relayHarness({ now: "2026-10-02T21:59:00.000Z", dailyCap: "2" });

    await relay.departures(stop(1));
    await relay.departures(stop(2));
    expect(await relay.departures(stop(3))).toEqual({ kind: "out", reason: "budget", retryAt: nextParisDay });

    clock.set("2026-10-02T22:00:00.000Z");
    expect((await relay.departures(stop(3))).kind).toBe("times");
    expect(prim.calls).toEqual([stop(1), stop(2), stop(3)]);
  });

  it("counts by the Paris day in winter too", async () => {
    const { relay } = relayHarness({ now: "2026-12-15T22:30:00.000Z", dailyCap: "1" });

    await relay.departures(stop(1));

    expect(await relay.departures(stop(2))).toEqual({
      kind: "out",
      reason: "budget",
      retryAt: Date.parse("2026-12-15T23:00:00.000Z"),
    });
  });
});

describe("Relay: when it cannot ask PRIM", () => {
  it("gives the answer it holds while it is younger than 5 minutes when the cap is reached, then says out until the next Paris day", async () => {
    const { relay, prim, clock } = relayHarness({ dailyCap: "1" });
    const primAnsweredAt = clock.now();
    await relay.departures(abbesses);

    clock.advance(5 * minute - 1);
    expect(await relay.departures(abbesses)).toEqual(times(abbessesAnswer, primAnsweredAt));

    clock.advance(1);
    expect(await relay.departures(abbesses)).toEqual({ kind: "out", reason: "budget", retryAt: nextParisDay });
    expect(prim.calls).toHaveLength(1);
  });

  it("makes no PRIM call for 1 hour after PRIM answers 429, for any stop, and says out until then", async () => {
    const { relay, prim, clock } = relayHarness();
    prim.answerWith(() => answer(429, '{"message":"Too many requests"}'));
    const limitedAt = clock.now();

    expect(await relay.departures(abbesses)).toEqual({ kind: "out", reason: "prim-limit", retryAt: limitedAt + hour });

    clock.advance(hour - 1);
    expect(await relay.departures(chatelet)).toEqual({ kind: "out", reason: "prim-limit", retryAt: limitedAt + hour });
    expect(prim.calls).toEqual([abbesses]);

    prim.answerWith(() => answer(200, chateletAnswer));
    clock.advance(1);
    expect(await relay.departures(chatelet)).toEqual(times(chateletAnswer, clock.now()));
    expect(prim.calls).toEqual([abbesses, chatelet]);
  });

  it("keeps the pause after a 429 when the server restarts", async () => {
    const harness = relayHarness();
    harness.prim.answerWith(() => answer(429, ""));
    await harness.relay.departures(abbesses);

    harness.clock.advance(10 * minute);
    const restarted = harness.restart();

    expect((await restarted.relay.departures(abbesses)).kind).toBe("out");
    expect(harness.prim.calls).toHaveLength(1);
  });

  it("gives the answer it holds after a 429 while it is younger than 5 minutes", async () => {
    const { relay, prim, clock } = relayHarness();
    const primAnsweredAt = clock.now();
    await relay.departures(abbesses);
    prim.answerWith(() => answer(429, ""));

    clock.advance(2 * minute);
    expect(await relay.departures(abbesses)).toEqual(times(abbessesAnswer, primAnsweredAt));
    clock.advance(2 * minute);
    expect(await relay.departures(abbesses)).toEqual(times(abbessesAnswer, primAnsweredAt));
    clock.advance(minute);
    expect(await relay.departures(abbesses)).toEqual({
      kind: "out",
      reason: "prim-limit",
      retryAt: primAnsweredAt + 2 * minute + hour,
    });
    expect(prim.calls).toHaveLength(2);
  });

  it("says out until 60 s after a failure when PRIM does not answer and it holds no young answer", async () => {
    const { relay, prim, clock } = relayHarness();
    prim.answerWith(() => ({ kind: "unreachable", reason: "TimeoutError" }));
    clock.advance(10_000);
    const failedAt = clock.now();

    expect(await relay.departures(abbesses)).toEqual({ kind: "out", reason: "prim-failure", retryAt: failedAt + minute });
  });

  it("gives the later time when the cap is also reached", async () => {
    const { relay, prim } = relayHarness({ dailyCap: "1" });
    prim.answerWith(() => answer(503, ""));

    expect(await relay.departures(abbesses)).toEqual({ kind: "out", reason: "budget", retryAt: nextParisDay });
  });

  it("gives the later time of a 429 pause and of the cap", async () => {
    const { relay, prim, clock } = relayHarness({ now: "2026-10-02T21:30:00.000Z", dailyCap: "1" });
    prim.answerWith(() => answer(429, ""));

    expect(await relay.departures(abbesses)).toEqual({ kind: "out", reason: "prim-limit", retryAt: clock.now() + hour });
  });
});

describe("Relay: a failed PRIM call is never kept as times", () => {
  const failures: [string, () => ReturnType<typeof answer> | { kind: "unreachable"; reason: string }][] = [
    ["an HTTP error with a body", () => answer(500, '{"message":"Internal error"}')],
    ["a refused key", () => answer(401, '{"message":"Invalid key"}')],
    ["a PRIM error body with status 200", () => answer(200, '{"Siri":{"ServiceDelivery":{"StopMonitoringDelivery":[{"Status":"false","ErrorCondition":{"ErrorInformation":{"ErrorText":"Unknown stop"}}}]}}}')],
    ["a body that is not JSON", () => answer(200, "<html>Bad gateway</html>")],
    ["a JSON body that is not a stop monitoring answer", () => answer(200, '{"message":"ok"}')],
    ["no answer", () => ({ kind: "unreachable", reason: "TypeError" })],
  ];

  for (const [name, failure] of failures) {
    it(`keeps the last good answer after ${name}, and asks PRIM again only after 60 s`, async () => {
      const { relay, prim, clock } = relayHarness();
      const goodAt = clock.now();
      await relay.departures(abbesses);

      prim.answerWith(failure);
      clock.advance(minute);
      expect(await relay.departures(abbesses)).toEqual(times(abbessesAnswer, goodAt));
      expect(prim.calls).toHaveLength(2);

      clock.advance(minute - 1);
      expect(await relay.departures(abbesses)).toEqual(times(abbessesAnswer, goodAt));
      expect(prim.calls).toHaveLength(2);

      prim.answerWith(() => answer(200, chateletAnswer));
      clock.advance(1);
      expect(await relay.departures(abbesses)).toEqual(times(chateletAnswer, clock.now()));
      expect(prim.calls).toHaveLength(3);
    });

    it(`says out after ${name} when it holds no answer`, async () => {
      const { relay, prim, clock } = relayHarness();
      prim.answerWith(failure);

      expect(await relay.departures(abbesses)).toEqual({
        kind: "out",
        reason: "prim-failure",
        retryAt: clock.now() + minute,
      });
    });
  }

  it("does not pause the other stops after the failure of one stop", async () => {
    const { relay, prim } = relayHarness();
    prim.answerWith((stopRef) => (stopRef === abbesses ? answer(500, "") : answer(200, chateletAnswer)));

    await relay.departures(abbesses);

    expect((await relay.departures(chatelet)).kind).toBe("times");
  });
});

describe("Relay: what it counts", () => {
  it("counts the app calls, cache hits, held answers, out answers, PRIM calls and errors of the hour, and the PRIM calls of each stop", async () => {
    const { relay, prim, clock } = relayHarness();
    await relay.departures(abbesses);
    await relay.departures(abbesses);
    clock.advance(minute);
    prim.answerWith(() => answer(500, ""));
    await relay.departures(abbesses);
    await relay.departures(chatelet);
    await relay.departures(chatelet);

    const report = relay.counts();

    expect(report.today).toBe("2026-10-02");
    expect(report.dailyCap).toBe(800);
    expect(report.primCallsToday).toBe(3);
    expect(report.days).toEqual([
      {
        day: "2026-10-02",
        appCalls: 5,
        cacheHits: 1,
        heldAnswers: 1,
        outAnswers: 2,
        primCalls: 3,
        errors: 2,
        hours: [
          {
            start: "2026-10-02T08:00:00.000Z",
            parisHour: "10:00",
            appCalls: 5,
            cacheHits: 1,
            heldAnswers: 1,
            outAnswers: 2,
            primCalls: 3,
            errors: 2,
          },
        ],
        stops: [
          { stopRef: abbesses, primCalls: 2 },
          { stopRef: chatelet, primCalls: 1 },
        ],
      },
    ]);
    expect(report.errorLines).toEqual([
      { at: "2026-10-02T08:31:00.000Z", stopRef: chatelet, kind: "prim-http-error", status: 500 },
      { at: "2026-10-02T08:31:00.000Z", stopRef: abbesses, kind: "prim-http-error", status: 500 },
    ]);
  });

  it("reports the pause after a 429", async () => {
    const { relay, prim } = relayHarness();
    prim.answerWith(() => answer(429, ""));
    await relay.departures(abbesses);

    expect(relay.counts().limitPauseUntil).toBe("2026-10-02T09:30:00.000Z");
  });

  it("logs a failed PRIM call with the stop, the kind and the status only", async () => {
    const { relay, prim, logLines } = relayHarness();
    prim.answerWith(() => ({ kind: "unreachable", reason: "TimeoutError" }));

    await relay.departures(abbesses);

    expect(logLines.map((line) => JSON.parse(line) as unknown)).toEqual([
      { level: "error", event: "prim-call-failed", stopRef: abbesses, kind: "prim-timeout", status: null },
    ]);
  });
});
