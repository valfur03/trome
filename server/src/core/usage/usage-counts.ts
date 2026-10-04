import type { SqlDatabase } from "../storage/sql-database";
import { day, hour } from "../time/clock";
import { parisDay, parisHour } from "../time/paris-time";

export const tallies = ["appCalls", "cacheHits", "heldAnswers", "outAnswers", "primCalls", "errors"] as const;

export type Tally = (typeof tallies)[number];

export type Tallies = Record<Tally, number>;

export interface ErrorLine {
  at: number;
  kind: string;
  status: number | null;
}

export interface HourCounts extends Tallies {
  start: string;
  parisHour: string;
}

export interface DayCounts extends Tallies {
  day: string;
  hours: HourCounts[];
}

export interface UsageReport {
  days: DayCounts[];
  errorLines: (Omit<ErrorLine, "at"> & { at: string })[];
}

export const countsKeptFor = 30 * day;
export const errorLinesKeptFor = 7 * day;
export const flushDelay = 30_000;

const columns: Record<Tally, string> = {
  appCalls: "app_calls",
  cacheHits: "cache_hits",
  heldAnswers: "held_answers",
  outAnswers: "out_answers",
  primCalls: "prim_calls",
  errors: "errors",
};

type HourRow = Record<string, number | string>;

export class UsageCounts {
  private readonly pending = new Map<number, Tallies>();
  private flushScheduled = false;

  constructor(
    private readonly database: SqlDatabase,
    private readonly scheduleFlush: (at: number) => void,
  ) {
    database.run(
      `CREATE TABLE IF NOT EXISTS usage_hours (hour_start INTEGER PRIMARY KEY, paris_day TEXT NOT NULL, ${tallies
        .map((tally) => `${columns[tally]} INTEGER NOT NULL`)
        .join(", ")})`,
    );
    database.run(
      "CREATE TABLE IF NOT EXISTS error_lines (id INTEGER PRIMARY KEY, at INTEGER NOT NULL, kind TEXT NOT NULL, status INTEGER)",
    );
    forgetTheStopsOfOlderVersions(database);
  }

  count(tally: Tally, at: number): void {
    const start = Math.floor(at / hour) * hour;
    const counts = this.pending.get(start) ?? emptyTallies();
    counts[tally] += 1;
    this.pending.set(start, counts);
    if (!this.flushScheduled) {
      this.flushScheduled = true;
      this.scheduleFlush(at + flushDelay);
    }
  }

  countPrimCall(at: number): void {
    this.count("primCalls", at);
    this.flush();
  }

  recordError(line: ErrorLine): void {
    this.database.run(
      "INSERT INTO error_lines (at, kind, status) VALUES (?, ?, ?)",
      line.at,
      line.kind,
      line.status,
    );
    this.count("errors", line.at);
    this.flush();
  }

  flushFromAlarm(): void {
    this.flushScheduled = false;
    this.flush();
  }

  flush(): void {
    for (const [start, counts] of this.pending) {
      this.database.run(
        `INSERT INTO usage_hours (hour_start, paris_day, ${tallies.map((tally) => columns[tally]).join(", ")}) VALUES (?, ?, ${tallies
          .map(() => "?")
          .join(", ")}) ON CONFLICT (hour_start) DO UPDATE SET ${tallies
          .map((tally) => `${columns[tally]} = ${columns[tally]} + excluded.${columns[tally]}`)
          .join(", ")}`,
        start,
        parisDay(start),
        ...tallies.map((tally) => counts[tally]),
      );
    }
    this.pending.clear();
  }

  forgetOldCounts(now: number): void {
    this.database.run("DELETE FROM usage_hours WHERE hour_start < ?", now - countsKeptFor);
    this.database.run("DELETE FROM error_lines WHERE at < ?", now - errorLinesKeptFor);
  }

  report(): UsageReport {
    this.flush();
    const hours = this.database
      .all<HourRow>(
        `SELECT hour_start, paris_day, ${tallies.map((tally) => columns[tally]).join(", ")} FROM usage_hours ORDER BY hour_start DESC`,
      )
      .map(hourCounts);
    const days = new Map<string, DayCounts>();
    for (const { day: parisDayOfHour, counts } of hours) {
      const dayCounts = days.get(parisDayOfHour) ?? { day: parisDayOfHour, ...emptyTallies(), hours: [] };
      for (const tally of tallies) {
        dayCounts[tally] += counts[tally];
      }
      dayCounts.hours.push(counts);
      days.set(parisDayOfHour, dayCounts);
    }
    const errorLines = this.database
      .all<{ at: number; kind: string; status: number | null }>(
        "SELECT at, kind, status FROM error_lines ORDER BY at DESC, id DESC",
      )
      .map((row) => ({ at: new Date(row.at).toISOString(), kind: row.kind, status: row.status }));
    return { days: [...days.values()], errorLines };
  }
}

function forgetTheStopsOfOlderVersions(database: SqlDatabase): void {
  database.run("DROP TABLE IF EXISTS usage_stops");
  const stopColumn = database.all("SELECT name FROM pragma_table_info('error_lines') WHERE name = 'stop_ref'");
  if (stopColumn.length > 0) {
    database.run("ALTER TABLE error_lines DROP COLUMN stop_ref");
  }
}

function emptyTallies(): Tallies {
  return { appCalls: 0, cacheHits: 0, heldAnswers: 0, outAnswers: 0, primCalls: 0, errors: 0 };
}

function hourCounts(row: HourRow): { day: string; counts: HourCounts } {
  const start = Number(row.hour_start);
  const counts: HourCounts = { start: new Date(start).toISOString(), parisHour: parisHour(start), ...emptyTallies() };
  for (const tally of tallies) {
    counts[tally] = Number(row[columns[tally]]);
  }
  return { day: String(row.paris_day), counts };
}
