import { describe, expect, it } from "vitest";
import { UsageCounts } from "../../../src/core/usage/usage-counts";
import { day, hour } from "../../../src/core/time/clock";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";

const at = (iso: string) => Date.parse(iso);

function usageCounts() {
  const database = new NodeSqliteDatabase();
  const flushTimes: number[] = [];
  return { database, flushTimes, usage: new UsageCounts(database, (time) => flushTimes.push(time)) };
}

function hoursInStorage(database: NodeSqliteDatabase) {
  return database.all("SELECT hour_start, app_calls, cache_hits FROM usage_hours");
}

describe("UsageCounts", () => {
  it("keeps the counts of app calls in memory, and asks for one flush 30 s after the first one", () => {
    const { database, flushTimes, usage } = usageCounts();

    usage.count("appCalls", at("2026-10-02T08:30:00.000Z"));
    usage.count("cacheHits", at("2026-10-02T08:30:10.000Z"));
    usage.count("appCalls", at("2026-10-02T08:30:20.000Z"));

    expect(hoursInStorage(database)).toEqual([]);
    expect(flushTimes).toEqual([at("2026-10-02T08:30:30.000Z")]);

    usage.flushFromAlarm();
    expect(hoursInStorage(database)).toEqual([{ hour_start: at("2026-10-02T08:00:00.000Z"), app_calls: 2, cache_hits: 1 }]);

    usage.count("appCalls", at("2026-10-02T08:31:00.000Z"));
    expect(flushTimes).toEqual([at("2026-10-02T08:30:30.000Z"), at("2026-10-02T08:31:30.000Z")]);
  });

  it("writes the counts at each PRIM call, and adds them to the counts already written", () => {
    const { database, usage } = usageCounts();
    usage.count("appCalls", at("2026-10-02T08:30:00.000Z"));
    usage.countPrimCall("STIF:StopArea:SP:1:", at("2026-10-02T08:30:00.000Z"));
    usage.count("appCalls", at("2026-10-02T08:59:00.000Z"));
    usage.countPrimCall("STIF:StopArea:SP:1:", at("2026-10-02T08:59:00.000Z"));
    usage.count("appCalls", at("2026-10-02T09:00:00.000Z"));
    usage.countPrimCall("STIF:StopArea:SP:2:", at("2026-10-02T09:00:00.000Z"));

    expect(database.all("SELECT hour_start, app_calls, prim_calls FROM usage_hours ORDER BY hour_start")).toEqual([
      { hour_start: at("2026-10-02T08:00:00.000Z"), app_calls: 2, prim_calls: 2 },
      { hour_start: at("2026-10-02T09:00:00.000Z"), app_calls: 1, prim_calls: 1 },
    ]);
    expect(database.all("SELECT paris_day, stop_ref, prim_calls FROM usage_stops ORDER BY stop_ref")).toEqual([
      { paris_day: "2026-10-02", stop_ref: "STIF:StopArea:SP:1:", prim_calls: 2 },
      { paris_day: "2026-10-02", stop_ref: "STIF:StopArea:SP:2:", prim_calls: 1 },
    ]);
  });

  it("reports each Paris day, newest first, with its hours and the PRIM calls of each stop", () => {
    const { usage } = usageCounts();
    usage.countPrimCall("STIF:StopArea:SP:1:", at("2026-10-01T21:59:00.000Z"));
    usage.countPrimCall("STIF:StopArea:SP:1:", at("2026-10-01T22:00:00.000Z"));
    usage.countPrimCall("STIF:StopArea:SP:2:", at("2026-10-02T08:10:00.000Z"));
    usage.countPrimCall("STIF:StopArea:SP:2:", at("2026-10-02T08:20:00.000Z"));
    usage.count("appCalls", at("2026-10-02T08:20:00.000Z"));

    const { days } = usage.report();

    expect(days.map(({ day: parisDay, appCalls, primCalls }) => ({ parisDay, appCalls, primCalls }))).toEqual([
      { parisDay: "2026-10-02", appCalls: 1, primCalls: 3 },
      { parisDay: "2026-10-01", appCalls: 0, primCalls: 1 },
    ]);
    expect(days[0]?.hours.map(({ start, parisHour, primCalls }) => ({ start, parisHour, primCalls }))).toEqual([
      { start: "2026-10-02T08:00:00.000Z", parisHour: "10:00", primCalls: 2 },
      { start: "2026-10-01T22:00:00.000Z", parisHour: "00:00", primCalls: 1 },
    ]);
    expect(days[0]?.stops).toEqual([
      { stopRef: "STIF:StopArea:SP:2:", primCalls: 2 },
      { stopRef: "STIF:StopArea:SP:1:", primCalls: 1 },
    ]);
  });

  it("keeps the counts 30 days and the error lines 7 days", () => {
    const { database, usage } = usageCounts();
    const now = at("2026-10-31T08:30:00.000Z");
    for (const time of [now - 30 * day - hour, now - 30 * day + hour, now - 7 * day - hour, now - 7 * day + hour]) {
      usage.countPrimCall("STIF:StopArea:SP:1:", time);
      usage.recordError({ at: time, stopRef: "STIF:StopArea:SP:1:", kind: "prim-http-error", status: 500 });
    }

    usage.forgetOldCounts(now);

    expect(database.all("SELECT hour_start FROM usage_hours ORDER BY hour_start")).toEqual([
      { hour_start: now - 30 * day + hour - (now % hour) },
      { hour_start: now - 7 * day - hour - (now % hour) },
      { hour_start: now - 7 * day + hour - (now % hour) },
    ]);
    expect(database.all("SELECT paris_day FROM usage_stops ORDER BY paris_day")).toEqual([
      { paris_day: "2026-10-01" },
      { paris_day: "2026-10-24" },
    ]);
    expect(usage.report().errorLines.map((line) => line.at)).toEqual([new Date(now - 7 * day + hour).toISOString()]);
  });
});
