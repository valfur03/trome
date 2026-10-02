import { env, exports } from "cloudflare:workers";
import { abortAllDurableObjects, evictDurableObject, listDurableObjectIds, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { relayObject } from "../../src/cloudflare/relay-object";
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
    vi.useFakeTimers({ toFake: ["Date"], now: Date.parse("2026-10-02T21:30:00.000Z") });
    const prim = fakePrim(undefined, { wait: true });

    const answers = Array.from({ length: 900 }, (_, index) => departures(stop(index)));
    await vi.waitUntil(() => prim.calls.length === 800, { timeout: 20_000 });
    prim.release();
    const statuses = (await Promise.all(answers)).map((response) => response.status);
    expect(statuses.filter((status) => status === 200)).toHaveLength(800);
    expect(statuses.filter((status) => status === 503)).toHaveLength(100);

    await evictDurableObject(relayObject(env));

    const afterRestart = await Promise.all(Array.from({ length: 50 }, (_, index) => departures(stop(1000 + index))));
    expect(afterRestart.map((response) => response.status)).toEqual(Array.from({ length: 50 }, () => 503));
    expect(prim.calls).toHaveLength(800);
    expect(await listDurableObjectIds(env.RELAY)).toHaveLength(1);
  }, 60_000);

  it("keeps its pause after a 429 when it restarts", async () => {
    const prim = fakePrim(() => new Response("Too many requests", { status: 429 }));
    expect((await departures(abbesses)).status).toBe(503);

    await evictDurableObject(relayObject(env));

    const response = await departures(stop(1));
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ status: "out", reason: "prim-limit" });
    expect(prim.calls).toHaveLength(1);
  });

  it("writes the counts of the app calls and cache hits at its alarm, not at each app call", async () => {
    fakePrim();
    await departures(abbesses);
    await departures(abbesses);
    await departures(abbesses);

    const stored = () =>
      runInDurableObject(relayObject(env), (_object, state) =>
        state.storage.sql.exec<{ app_calls: number; cache_hits: number }>("SELECT app_calls, cache_hits FROM usage_hours").toArray(),
      );
    expect(await stored()).toEqual([{ app_calls: 1, cache_hits: 0 }]);
    expect(await runInDurableObject(relayObject(env), (_object, state) => state.storage.getAlarm())).not.toBeNull();

    expect(await runDurableObjectAlarm(relayObject(env))).toBe(true);
    expect(await stored()).toEqual([{ app_calls: 3, cache_hits: 2 }]);
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
      days: [{ appCalls: 1, primCalls: 1, stops: [{ stopRef: abbesses, primCalls: 1 }] }],
    });
  });

  it("uses SQLite storage", async () => {
    await departures(abbesses).catch(() => undefined);
    const tables = await runInDurableObject(relayObject(env), (_object, state) =>
      state.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table'").toArray(),
    );

    expect(tables.map(({ name }) => name)).toEqual(
      expect.arrayContaining(["answers", "relay_pauses", "prim_budget", "prim_budget_hours", "usage_hours", "usage_stops", "error_lines"]),
    );
  });
});
