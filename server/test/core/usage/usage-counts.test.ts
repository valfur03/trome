import { describe, expect, it } from "vitest";
import { tallies, UsageCounts } from "../../../src/core/usage/usage-counts";
import { day, hour } from "../../../src/core/time/clock";
import { NodeSqliteDatabase } from "../storage/node-sqlite-database";
import { everyStoredRow } from "../storage/every-stored-row";

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
    usage.countPrimCall(at("2026-10-02T08:30:00.000Z"));
    usage.count("appCalls", at("2026-10-02T08:59:00.000Z"));
    usage.countPrimCall(at("2026-10-02T08:59:00.000Z"));
    usage.count("appCalls", at("2026-10-02T09:00:00.000Z"));
    usage.countPrimCall(at("2026-10-02T09:00:00.000Z"));

    expect(database.all("SELECT hour_start, app_calls, prim_calls FROM usage_hours ORDER BY hour_start")).toEqual([
      { hour_start: at("2026-10-02T08:00:00.000Z"), app_calls: 2, prim_calls: 2 },
      { hour_start: at("2026-10-02T09:00:00.000Z"), app_calls: 1, prim_calls: 1 },
    ]);
  });

  it("reports each Paris day, newest first, with its hours, and no stop", () => {
    const { usage } = usageCounts();
    usage.countPrimCall(at("2026-10-01T21:59:00.000Z"));
    usage.countPrimCall(at("2026-10-01T22:00:00.000Z"));
    usage.countPrimCall(at("2026-10-02T08:10:00.000Z"));
    usage.countPrimCall(at("2026-10-02T08:20:00.000Z"));
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
    expect(Object.keys(days[0] ?? {}).sort()).toEqual([...tallies, "day", "hours"].sort());
  });

  it("keeps the counts 30 days and the error lines 7 days", () => {
    const { database, usage } = usageCounts();
    const now = at("2026-10-31T08:30:00.000Z");
    for (const time of [now - 30 * day - hour, now - 30 * day + hour, now - 7 * day - hour, now - 7 * day + hour]) {
      usage.countPrimCall(time);
      usage.recordError({ at: time, kind: "prim-http-error", status: 500 });
    }

    usage.forgetOldCounts(now);

    expect(database.all("SELECT hour_start FROM usage_hours ORDER BY hour_start")).toEqual([
      { hour_start: now - 30 * day + hour - (now % hour) },
      { hour_start: now - 7 * day - hour - (now % hour) },
      { hour_start: now - 7 * day + hour - (now % hour) },
    ]);
    expect(usage.report().errorLines).toEqual([
      { at: new Date(now - 7 * day + hour).toISOString(), kind: "prim-http-error", status: 500 },
    ]);
  });

  it("adds the tallies of a newer version to the hours that an older version wrote, at 0, and keeps their counts", () => {
    const database = new NodeSqliteDatabase();
    const start = at("2026-10-02T08:00:00.000Z");
    database.run(
      "CREATE TABLE usage_hours (hour_start INTEGER PRIMARY KEY, paris_day TEXT NOT NULL, app_calls INTEGER NOT NULL, cache_hits INTEGER NOT NULL, held_answers INTEGER NOT NULL, out_answers INTEGER NOT NULL, prim_calls INTEGER NOT NULL, errors INTEGER NOT NULL)",
    );
    database.run("INSERT INTO usage_hours VALUES (?, '2026-10-02', 5, 1, 1, 2, 3, 2)", start);

    const usage = new UsageCounts(database, () => undefined);
    new UsageCounts(database, () => undefined);
    usage.count("unreadableAnswers", start + 10 * 60_000);

    const [today] = usage.report().days;
    expect(today).toMatchObject({ appCalls: 5, primCalls: 3, errors: 2, unreadableAnswers: 1 });
    expect(usage.metricsTotals(start + hour).today).toMatchObject({ appCalls: 5, unreadableAnswers: 1 });
  });

  it("deletes the PRIM calls of each stop and the stop of each error line that an older version stored, and keeps the rest", () => {
    const database = new NodeSqliteDatabase();
    const failedAt = at("2026-10-02T08:31:00.000Z");
    database.run(
      "CREATE TABLE usage_stops (paris_day TEXT NOT NULL, stop_ref TEXT NOT NULL, prim_calls INTEGER NOT NULL, PRIMARY KEY (paris_day, stop_ref)) WITHOUT ROWID",
    );
    database.run("INSERT INTO usage_stops VALUES ('2026-10-02', 'STIF:StopArea:SP:42155:', 3)");
    database.run(
      "CREATE TABLE error_lines (id INTEGER PRIMARY KEY, at INTEGER NOT NULL, stop_ref TEXT NOT NULL, kind TEXT NOT NULL, status INTEGER)",
    );
    database.run("INSERT INTO error_lines (at, stop_ref, kind, status) VALUES (?, 'STIF:StopArea:SP:42155:', 'prim-http-error', 500)", failedAt);

    const usage = new UsageCounts(database, () => undefined);
    new UsageCounts(database, () => undefined);

    expect(database.all("SELECT name FROM sqlite_master WHERE name = 'usage_stops'")).toEqual([]);
    expect(database.all("SELECT * FROM error_lines")).toEqual([{ id: 1, at: failedAt, kind: "prim-http-error", status: 500 }]);
    expect(JSON.stringify(everyStoredRow(database))).not.toContain("42155");
    expect(usage.report().errorLines).toEqual([{ at: "2026-10-02T08:31:00.000Z", kind: "prim-http-error", status: 500 }]);
  });
});
