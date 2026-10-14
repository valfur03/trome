import { env, exports } from "cloudflare:workers";
import { abortAllDurableObjects, evictDurableObject, listDurableObjectIds, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { relayObject } from "../../src/cloudflare/relay-object";
import { day, hour, minute } from "../../src/core/time/clock";
import { parisDay } from "../../src/core/time/paris-time";
import { flushDelay } from "../../src/core/usage/usage-counts";
import { everyStoredRow } from "./every-stored-row";
import { fakePrim, recordedAnswer } from "./fake-prim";

const abbesses = "STIF:StopArea:SP:42155:";

afterEach(async () => {
  vi.useRealTimers();
  vi.restoreAllMocks();
  await runInDurableObject(relayObject(env), (_object, state) => state.storage.deleteAll());
  await abortAllDurableObjects();
});

function departures(stopRef: string): Promise<Response> {
  return exports.default.fetch(`https://server.test/v1/stops/${stopRef}/departures`, {
    headers: { authorization: `Bearer ${env.APP_TOKEN}` },
  });
}

function ownerCounts(): Promise<Response> {
  return exports.default.fetch("https://server.test/v1/owner/counts", {
    headers: { authorization: `Bearer ${env.OWNER_TOKEN}` },
  });
}

/** Moves the fake clock on inside the object, so that its timers run there, as they do on Cloudflare. */
async function passTime(milliseconds: number): Promise<void> {
  await runInDurableObject(relayObject(env), () => vi.advanceTimersByTimeAsync(milliseconds));
}

/** Cloudflare puts the object to sleep only when no timer of it waits: so the test runs its timers, then empties its memory, as a sleep does. */
async function sleepWhenIdle(): Promise<void> {
  await runInDurableObject(relayObject(env), () => vi.runAllTimersAsync());
  expect(vi.getTimerCount()).toBe(0);
  await evictDurableObject(relayObject(env));
}

/** A fake clock from half past the hour, a day ahead of the real one, so that the timers of the object run only when the test moves the clock. */
function useFakeTime(): void {
  vi.useFakeTimers({ toFake: ["Date", "setTimeout", "clearTimeout"], now: Math.ceil(Date.now() / hour) * hour + day + 30 * minute });
}

function stop(index: number): string {
  return `STIF:StopArea:SP:${String(100_000 + index)}:`;
}

describe("RelayObject", () => {
  it("asks PRIM with the key for the stop of the request, and gives its answer as PRIM gave it", async () => {
    const prim = fakePrim();

    const response = await departures(abbesses);

    expect(response.status).toBe(200);
    expect(await response.text()).toBe(recordedAnswer("stop-monitoring-abbesses-stop-area.json"));
    expect(response.headers.get("last-modified")).not.toBeNull();
    expect(prim.calls.map((url) => url.searchParams.get("MonitoringRef"))).toEqual([abbesses]);
    expect(prim.keys).toEqual([env.PRIM_API_KEY]);
  });

  it("makes one PRIM call for the requests of a stop that come while its call is in flight, and for the requests after it", async () => {
    const prim = fakePrim(undefined, { wait: true });

    const answers = Array.from({ length: 20 }, () => departures(abbesses));
    await vi.waitUntil(() => prim.calls.length === 1);
    prim.release();
    const responses = await Promise.all(answers);
    const later = await departures(abbesses);

    expect(responses.map((response) => response.status)).toEqual(Array.from({ length: 20 }, () => 200));
    expect(later.status).toBe(200);
    expect(prim.calls).toHaveLength(1);
  });

  it("never passes its cap of 800 with many simultaneous requests for many stops, and keeps its count when it restarts", async () => {
    expect(env.PRIM_DAILY_CAP).toBe("800");
    vi.useFakeTimers({ toFake: ["Date", "setTimeout", "clearTimeout"], now: Date.parse("2026-10-02T21:30:00.000Z") });
    const prim = fakePrim(undefined, { wait: true });

    const answers = Array.from({ length: 900 }, (_, index) => departures(stop(index)));
    await vi.waitUntil(() => prim.calls.length === 800, { timeout: 20_000 });
    prim.release();
    const statuses = (await Promise.all(answers)).map((response) => response.status);
    expect(statuses.filter((status) => status === 200)).toHaveLength(800);
    expect(statuses.filter((status) => status === 503)).toHaveLength(100);

    await sleepWhenIdle();

    const afterRestart = await Promise.all(Array.from({ length: 50 }, (_, index) => departures(stop(1000 + index))));
    expect(afterRestart.map((response) => response.status)).toEqual(Array.from({ length: 50 }, () => 503));
    expect(prim.calls).toHaveLength(800);
    expect(await listDurableObjectIds(env.RELAY)).toHaveLength(1);
  }, 60_000);

  it("keeps its pause after a 429 when it restarts", async () => {
    useFakeTime();
    const prim = fakePrim(() => new Response("Too many requests", { status: 429 }));
    expect((await departures(abbesses)).status).toBe(503);

    await sleepWhenIdle();

    const response = await departures(stop(1));
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ status: "out", reason: "prim-limit" });
    expect(prim.calls).toHaveLength(1);
  });

  it("writes the counts of the app calls and cache hits 10 s after the first one, not at each app call, and loses none when it sleeps", async () => {
    useFakeTime();
    fakePrim();
    await departures(abbesses);
    await departures(abbesses);
    await departures(abbesses);

    const stored = () =>
      runInDurableObject(relayObject(env), (_object, state) =>
        state.storage.sql.exec<{ app_calls: number; cache_hits: number }>("SELECT app_calls, cache_hits FROM usage_hours").toArray(),
      );
    expect(await stored()).toEqual([{ app_calls: 1, cache_hits: 0 }]);
    expect(vi.getTimerCount(), "the timer of the counts, and the one of the answer").toBe(2);

    await passTime(flushDelay);
    expect(await stored()).toEqual([{ app_calls: 3, cache_hits: 2 }]);
    expect(vi.getTimerCount(), "the timer of the answer").toBe(1);

    await sleepWhenIdle();
    expect(await (await ownerCounts()).json()).toMatchObject({ days: [{ appCalls: 3, cacheHits: 2, primCalls: 1 }] });
  });

  it("gives the owner the counts of today with the owner token", async () => {
    fakePrim();
    await departures(abbesses);

    const response = await exports.default.fetch("https://server.test/v1/owner/counts", {
      headers: { authorization: `Bearer ${env.OWNER_TOKEN}` },
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      dailyCap: 800,
      primCallsToday: 1,
      days: [{ appCalls: 1, primCalls: 1 }],
    });
  });

  it("keeps a timer through the 30 s between two refreshes, so that Cloudflare does not put it to sleep, and gives the held answer with no new PRIM call for 60 s, with the same headers", async () => {
    useFakeTime();
    const prim = fakePrim();
    const first = await departures(abbesses);
    const body = await first.text();

    await passTime(30_000);
    expect(vi.getTimerCount(), "the timer of the answer").toBe(1);
    const afterIdle = await departures(abbesses);
    await passTime(29_000);
    expect(vi.getTimerCount(), "the timer of the answer").toBeGreaterThan(0);
    const later = await departures(abbesses);

    expect(prim.calls).toHaveLength(1);
    for (const response of [afterIdle, later]) {
      expect(response.status).toBe(200);
      expect(await response.text()).toBe(body);
      expect(Object.fromEntries(response.headers)).toEqual(Object.fromEntries(first.headers));
    }

    await passTime(1_000);
    expect((await departures(abbesses)).status).toBe(200);
    expect(prim.calls).toHaveLength(2);
  });

  it("has no timer left 5 minutes after its last answer, so that Cloudflare may put it to sleep", async () => {
    useFakeTime();
    fakePrim();
    await departures(abbesses);

    await passTime(5 * minute - 1);
    expect(vi.getTimerCount()).toBe(1);
    await passTime(1);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("loses no app call, cache hit or PRIM call when it sleeps between the requests", async () => {
    useFakeTime();
    fakePrim();

    await departures(abbesses);
    await departures(abbesses);
    await sleepWhenIdle();
    await departures(abbesses);
    await sleepWhenIdle();
    await departures(abbesses);
    await sleepWhenIdle();

    expect(await (await ownerCounts()).json()).toMatchObject({
      days: [{ appCalls: 4, cacheHits: 1, heldAnswers: 0, outAnswers: 0, primCalls: 3, errors: 0 }],
    });
  });

  it("stays awake through the 60 s pause after a failed PRIM call, so that a sleep does not end the pause early, then forgets the stop", async () => {
    useFakeTime();
    const prim = fakePrim(() => new Response("Server error", { status: 500 }));
    expect((await departures(abbesses)).status).toBe(503);

    await passTime(30_000);
    expect(vi.getTimerCount()).toBe(1);
    expect((await departures(abbesses)).status).toBe(503);
    expect(prim.calls).toHaveLength(1);

    await passTime(30_000);
    expect(vi.getTimerCount()).toBe(0);
    const stopsInMemory = await runInDurableObject(relayObject(env), (object) =>
      (object as unknown as { relay: { stopsInMemory(): string[] } }).relay.stopsInMemory(),
    );
    expect(stopsInMemory).toEqual([]);
  });

  it("keeps no stop in storage after an answer and a failed PRIM call, and an alarm of the older version changes nothing", async () => {
    let calls = 0;
    fakePrim(() => {
      calls += 1;
      return calls === 1 ? new Response(recordedAnswer("stop-monitoring-abbesses-stop-area.json")) : new Response("Server error", { status: 500 });
    });
    await departures(abbesses);
    expect((await departures(stop(1))).status).toBe(503);
    await runInDurableObject(relayObject(env), (_object, state) => state.storage.setAlarm(Date.now() + day));
    expect(await runDurableObjectAlarm(relayObject(env))).toBe(true);

    const stored = await everyStoredRow();
    expect(stored).toContain('"kind":"prim-http-error"');
    expect(stored).not.toContain("42155");
    expect(stored).not.toContain(stop(1));
    expect((await departures(abbesses)).status).toBe(200);
    expect(calls).toBe(2);
  });

  it("deletes, when the new version starts, the answers, the PRIM calls of each stop and the stop of each error line that an older version stored", async () => {
    await runInDurableObject(relayObject(env), (_object, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE IF EXISTS error_lines");
      sql.exec("CREATE TABLE answers (stop_ref TEXT PRIMARY KEY, body TEXT NOT NULL, prim_answered_at INTEGER NOT NULL) WITHOUT ROWID");
      sql.exec("INSERT INTO answers VALUES (?, '{}', 1)", abbesses);
      sql.exec("CREATE TABLE usage_stops (paris_day TEXT NOT NULL, stop_ref TEXT NOT NULL, prim_calls INTEGER NOT NULL, PRIMARY KEY (paris_day, stop_ref)) WITHOUT ROWID");
      sql.exec("INSERT INTO usage_stops VALUES ('2026-10-02', ?, 3)", abbesses);
      sql.exec("CREATE TABLE error_lines (id INTEGER PRIMARY KEY, at INTEGER NOT NULL, stop_ref TEXT NOT NULL, kind TEXT NOT NULL, status INTEGER)");
      sql.exec("INSERT INTO error_lines (at, stop_ref, kind, status) VALUES (1790929860000, ?, 'prim-http-error', 500)", abbesses);
    });
    expect(await everyStoredRow()).toContain("42155");

    await evictDurableObject(relayObject(env));
    const response = await exports.default.fetch("https://server.test/v1/owner/counts", {
      headers: { authorization: `Bearer ${env.OWNER_TOKEN}` },
    });

    expect(await response.json()).toMatchObject({
      errorLines: [{ at: "2026-10-02T08:31:00.000Z", kind: "prim-http-error", status: 500 }],
    });
    const stored = await everyStoredRow();
    expect(stored).not.toContain("42155");
    expect(stored).not.toContain('"answers"');
    expect(stored).not.toContain('"usage_stops"');
  });

  it("keeps, when the new version starts, the counts of an older version's table, with 0 for a newer tally, and counts on in it", async () => {
    const hourStart = Math.floor(Date.now() / 3_600_000) * 3_600_000;
    await runInDurableObject(relayObject(env), (_object, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE IF EXISTS usage_hours");
      sql.exec(
        "CREATE TABLE usage_hours (hour_start INTEGER PRIMARY KEY, paris_day TEXT NOT NULL, app_calls INTEGER NOT NULL, cache_hits INTEGER NOT NULL, held_answers INTEGER NOT NULL, out_answers INTEGER NOT NULL, prim_calls INTEGER NOT NULL, errors INTEGER NOT NULL)",
      );
      sql.exec("INSERT INTO usage_hours VALUES (?, ?, 5, 3, 0, 0, 2, 0)", hourStart, parisDay(hourStart));
    });

    await evictDurableObject(relayObject(env));
    fakePrim();
    await departures(abbesses);
    const response = await exports.default.fetch("https://server.test/v1/owner/counts", {
      headers: { authorization: `Bearer ${env.OWNER_TOKEN}` },
    });

    expect(await response.json()).toMatchObject({ days: [{ cacheHits: 3, primCalls: 3, unreadableAnswers: 0 }] });
  });

  it("uses SQLite storage", async () => {
    await departures(abbesses).catch(() => undefined);
    const tables = await runInDurableObject(relayObject(env), (_object, state) =>
      state.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table'").toArray(),
    );

    expect(tables.map(({ name }) => name)).toEqual(
      expect.arrayContaining(["relay_pauses", "prim_budget", "prim_budget_hours", "usage_hours", "error_lines"]),
    );
  });
});
