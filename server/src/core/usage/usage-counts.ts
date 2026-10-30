import type { SqlDatabase } from "../storage/sql-database";
import { day, hour } from "../time/clock";
import { nextParisDayStart, parisDay, parisHour } from "../time/paris-time";
import { startAnswerName, type StartAnswer } from "./start-answers";

export const tallies = ["appCalls", "cacheHits", "heldAnswers", "outAnswers", "primCalls", "errors", "unreadableAnswers"] as const;

export type Tally = (typeof tallies)[number];

export type Tallies = Record<Tally, number>;

export interface ErrorLine {
  at: number;
  kind: string;
  status: number | null;
}

/** The answers of the start of a Live Activity, by name (`startAnswerName`): `{"started": 2, "refused:BadDeviceToken": 1}`. */
export type StartAnswerCounts = Record<string, number>;

export interface HourCounts extends Tallies {
  start: string;
  parisHour: string;
  startAnswers: StartAnswerCounts;
}

export interface DayCounts extends Tallies {
  day: string;
  startAnswers: StartAnswerCounts;
  hours: HourCounts[];
}

export interface UsageReport {
  days: DayCounts[];
  errorLines: (Omit<ErrorLine, "at"> & { at: string })[];
}

export const countsKeptFor = 30 * day;
export const errorLinesKeptFor = 7 * day;
/**
 * The counts of app calls wait in memory at most this long before one write, so that a busy hour writes a row every 10 s, not one for each app call.
 * The server object waits for this write with a timer, which keeps it awake: an object that sleeps loses its memory.
 */
export const flushDelay = 10_000;

const columns: Record<Tally, string> = {
  appCalls: "app_calls",
  cacheHits: "cache_hits",
  heldAnswers: "held_answers",
  outAnswers: "out_answers",
  primCalls: "prim_calls",
  errors: "errors",
  unreadableAnswers: "unreadable_answers",
};

type HourRow = Record<string, number | string>;

export class UsageCounts {
  private readonly pending = new Map<number, Tallies>();
  private flushScheduled = false;

  constructor(
    private readonly database: SqlDatabase,
    private readonly scheduleFlush: (at: number) => void,
    private readonly cancelFlush: () => void = () => undefined,
  ) {
    database.run(
      `CREATE TABLE IF NOT EXISTS usage_hours (hour_start INTEGER PRIMARY KEY, paris_day TEXT NOT NULL, ${tallies
        .map((tally) => `${columns[tally]} INTEGER NOT NULL`)
        .join(", ")})`,
    );
    database.run(
      "CREATE TABLE IF NOT EXISTS error_lines (id INTEGER PRIMARY KEY, at INTEGER NOT NULL, kind TEXT NOT NULL, status INTEGER)",
    );
    // So that `/metrics` reads only the error lines of today, not those of 7 days.
    database.run("CREATE INDEX IF NOT EXISTS error_lines_at ON error_lines (at, kind, status)");
    // One row for each hour and answer: a name of a short list (`startAnswerName`), and no stop, token or time finer than the hour.
    database.run(
      "CREATE TABLE IF NOT EXISTS start_answer_hours (hour_start INTEGER NOT NULL, paris_day TEXT NOT NULL, answer TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (hour_start, answer))",
    );
    forgetTheStopsOfOlderVersions(database);
    addTheTalliesOfNewerVersions(database);
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

  /** Counts an answer of the start route in its hour, written at once: the starts are few, and the count of an ask must outlive a sleep that comes right after it. */
  countStartAnswer(answer: StartAnswer, at: number): void {
    const start = Math.floor(at / hour) * hour;
    this.database.run(
      "INSERT INTO start_answer_hours (hour_start, paris_day, answer, count) VALUES (?, ?, ?, 1) ON CONFLICT (hour_start, answer) DO UPDATE SET count = count + 1",
      start,
      parisDay(start),
      startAnswerName(answer),
    );
  }

  flushWhenDue(): void {
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
    if (this.flushScheduled) {
      this.flushScheduled = false;
      this.cancelFlush();
    }
  }

  forgetOldCounts(now: number): void {
    this.database.run("DELETE FROM usage_hours WHERE hour_start < ?", now - countsKeptFor);
    this.database.run("DELETE FROM start_answer_hours WHERE hour_start < ?", now - countsKeptFor);
    this.database.run("DELETE FROM error_lines WHERE at < ?", now - errorLinesKeptFor);
  }

  metricsTotals(now: number): ReturnType<typeof metricsTotals> {
    return metricsTotals(this.database, now);
  }

  report(): UsageReport {
    this.flush();
    const hours = new Map(
      this.database
        .all<HourRow>(`SELECT hour_start, paris_day, ${tallies.map((tally) => columns[tally]).join(", ")} FROM usage_hours`)
        .map((row) => [Number(row.hour_start), hourCounts(row)]),
    );
    // An hour may have start answers and no app call: a refused ask, or a server with no push key.
    for (const row of this.database.all<{ hour_start: number; paris_day: string; answer: string; count: number }>(
      "SELECT hour_start, paris_day, answer, count FROM start_answer_hours",
    )) {
      const start = row.hour_start;
      const hourOfRow = hours.get(start) ?? hourCounts({ hour_start: start, paris_day: row.paris_day });
      hourOfRow.counts.startAnswers[row.answer] = row.count;
      hours.set(start, hourOfRow);
    }
    const days = new Map<string, DayCounts>();
    for (const { day: parisDayOfHour, counts } of [...hours.entries()].sort(([a], [b]) => b - a).map(([, entry]) => entry)) {
      const dayCounts = days.get(parisDayOfHour) ?? { day: parisDayOfHour, ...emptyTallies(), startAnswers: {}, hours: [] };
      for (const tally of tallies) {
        dayCounts[tally] += counts[tally];
      }
      addAnswers(dayCounts.startAnswers, counts.startAnswers);
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

/**
 * The totals of today and of the previous Paris day, for `/metrics`.
 * It reads only the written hours, never the counts still in memory, and writes nothing: a value that it showed is stored, so the next read is never lower within the day.
 * It reads the hours of the last 50 hours only (a Paris day has 25 hours at most), and the error lines of today only.
 */
export function metricsTotals(database: SqlDatabase, now: number): {
  today: Tallies;
  previousDay: Tallies;
  failuresToday: { kind: string; status: number | null; count: number }[];
  startAnswersToday: StartAnswerCounts;
  startAnswersPreviousDay: StartAnswerCounts;
} {
  const today = parisDay(now);
  const previous = previousParisDay(today);
  const totals = { today: emptyTallies(), previousDay: emptyTallies() };
  const rows = database.all<HourRow>(
    `SELECT paris_day, ${tallies.map((tally) => `SUM(${columns[tally]}) AS ${columns[tally]}`).join(", ")} FROM usage_hours WHERE hour_start >= ? GROUP BY paris_day`,
    Math.floor(now / hour) * hour - 50 * hour,
  );
  for (const row of rows) {
    const target = row.paris_day === today ? totals.today : row.paris_day === previous ? totals.previousDay : undefined;
    for (const tally of tallies) {
      if (target) {
        target[tally] = Number(row[columns[tally]]);
      }
    }
  }
  const failures = new Map<string, { kind: string; status: number | null; count: number }>();
  for (const line of database.all<{ at: number; kind: string; status: number | null }>(
    "SELECT at, kind, status FROM error_lines WHERE at >= ?",
    parisDayStart(now),
  )) {
    const key = `${line.kind} ${String(line.status)}`;
    const failure = failures.get(key) ?? { kind: line.kind, status: line.status, count: 0 };
    failure.count += 1;
    failures.set(key, failure);
  }
  const startAnswers = { today: {} as StartAnswerCounts, previousDay: {} as StartAnswerCounts };
  for (const row of database.all<{ paris_day: string; answer: string; count: number }>(
    "SELECT paris_day, answer, SUM(count) AS count FROM start_answer_hours WHERE hour_start >= ? GROUP BY paris_day, answer",
    Math.floor(now / hour) * hour - 50 * hour,
  )) {
    const target = row.paris_day === today ? startAnswers.today : row.paris_day === previous ? startAnswers.previousDay : undefined;
    if (target) {
      target[row.answer] = row.count;
    }
  }
  return {
    ...totals,
    failuresToday: [...failures.values()],
    startAnswersToday: startAnswers.today,
    startAnswersPreviousDay: startAnswers.previousDay,
  };
}

function parisDayStart(now: number): number {
  let start = nextParisDayStart(now - 26 * hour);
  while (nextParisDayStart(start) <= now) {
    start = nextParisDayStart(start);
  }
  return start;
}

function previousParisDay(parisDayText: string): string {
  const [year = 0, month = 1, date = 1] = parisDayText.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, date - 1)).toISOString().slice(0, 10);
}

function forgetTheStopsOfOlderVersions(database: SqlDatabase): void {
  database.run("DROP TABLE IF EXISTS usage_stops");
  const stopColumn = database.all("SELECT name FROM pragma_table_info('error_lines') WHERE name = 'stop_ref'");
  if (stopColumn.length > 0) {
    database.run("ALTER TABLE error_lines DROP COLUMN stop_ref");
  }
}

/** A table of an older version has no column for a newer tally: its hours get 0 for it, and keep their other counts. */
function addTheTalliesOfNewerVersions(database: SqlDatabase): void {
  const present = new Set(database.all<{ name: string }>("SELECT name FROM pragma_table_info('usage_hours')").map(({ name }) => name));
  for (const tally of tallies) {
    if (!present.has(columns[tally])) {
      database.run(`ALTER TABLE usage_hours ADD COLUMN ${columns[tally]} INTEGER NOT NULL DEFAULT 0`);
    }
  }
}

function emptyTallies(): Tallies {
  return { appCalls: 0, cacheHits: 0, heldAnswers: 0, outAnswers: 0, primCalls: 0, errors: 0, unreadableAnswers: 0 };
}

function addAnswers(total: StartAnswerCounts, added: StartAnswerCounts): void {
  for (const [answer, count] of Object.entries(added)) {
    total[answer] = (total[answer] ?? 0) + count;
  }
}

function hourCounts(row: HourRow): { day: string; counts: HourCounts } {
  const start = Number(row.hour_start);
  const counts: HourCounts = { start: new Date(start).toISOString(), parisHour: parisHour(start), ...emptyTallies(), startAnswers: {} };
  for (const tally of tallies) {
    counts[tally] = Number(row[columns[tally]] ?? 0);
  }
  return { day: String(row.paris_day), counts };
}
