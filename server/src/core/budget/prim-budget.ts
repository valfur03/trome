import type { RelaySettings } from "../config/relay-settings";
import type { SqlDatabase } from "../storage/sql-database";
import { hour } from "../time/clock";
import { nextParisDayStart, parisDay, parisHourOfDay } from "../time/paris-time";
import { hoursOfADay } from "./day-shape";

export type CallKind = "start" | "refresh";

export type BudgetSettings = Pick<RelaySettings, "dailyCap" | "dayShape" | "freshAge" | "agedAnswers" | "startReserve">;

interface HourSpending {
  parisDay: string;
  start: number;
  usedToday: number;
  spentThisHour: number;
  allowedByHourEnd: number;
  share: number;
}

export class PrimBudget {
  readonly dailyCap: number;
  private readonly allowedByEndOf: readonly number[];

  constructor(
    private readonly database: SqlDatabase,
    private readonly settings: BudgetSettings,
  ) {
    this.dailyCap = settings.dailyCap;
    let shareSoFar = 0;
    this.allowedByEndOf = settings.dayShape.map((share, parisHour) => {
      shareSoFar += share;
      return parisHour === hoursOfADay - 1 ? this.dailyCap : Math.min(this.dailyCap, Math.floor(this.dailyCap * shareSoFar + 1e-9));
    });
    database.run(
      "CREATE TABLE IF NOT EXISTS prim_budget (paris_day TEXT PRIMARY KEY, calls INTEGER NOT NULL) WITHOUT ROWID",
    );
    database.run(
      "CREATE TABLE IF NOT EXISTS prim_budget_hours (hour_start INTEGER PRIMARY KEY, paris_day TEXT NOT NULL, calls INTEGER NOT NULL)",
    );
  }

  answerAge(now: number): number {
    const spending = this.spending(now);
    const spentShare = spending.share > 0 ? spending.spentThisHour / spending.share : 1;
    return this.settings.agedAnswers
      .filter((step) => spentShare > step.spentOver)
      .reduce((age, step) => Math.max(age, step.age), this.settings.freshAge);
  }

  claim(now: number, kind: CallKind): boolean {
    const spending = this.spending(now);
    const reserve = kind === "start" ? 0 : Math.ceil(Math.max(spending.share, 0) * this.settings.startReserve);
    const limit = Math.min(this.dailyCap, spending.allowedByHourEnd - reserve);
    if (spending.usedToday >= limit) {
      return false;
    }
    const claimed = this.database.all<{ calls: number }>(
      "INSERT INTO prim_budget (paris_day, calls) VALUES (?, 1) ON CONFLICT (paris_day) DO UPDATE SET calls = calls + 1 WHERE calls < ? RETURNING calls",
      spending.parisDay,
      limit,
    );
    if (claimed.length !== 1) {
      return false;
    }
    this.database.run(
      "INSERT INTO prim_budget_hours (hour_start, paris_day, calls) VALUES (?, ?, 1) ON CONFLICT (hour_start) DO UPDATE SET calls = calls + 1",
      spending.start,
      spending.parisDay,
    );
    return true;
  }

  hasNoCallLeft(now: number): boolean {
    const spending = this.spending(now);
    return spending.usedToday >= spending.allowedByHourEnd;
  }

  retryAt(now: number): number {
    const usedOn = new Map<string, number>();
    for (let start = hourStart(now) + hour; start <= now + 2 * 24 * hour; start += hour) {
      const day = parisDay(start);
      const used = usedOn.get(day) ?? this.used(day);
      usedOn.set(day, used);
      if (used < this.allowedBy(start)) {
        return start;
      }
    }
    return nextParisDayStart(now);
  }

  used(parisDay: string): number {
    const [row] = this.database.all<{ calls: number }>(
      "SELECT calls FROM prim_budget WHERE paris_day = ?",
      parisDay,
    );
    return row?.calls ?? 0;
  }

  forgetDaysBefore(parisDay: string): void {
    this.database.run("DELETE FROM prim_budget WHERE paris_day < ?", parisDay);
    this.database.run("DELETE FROM prim_budget_hours WHERE paris_day < ?", parisDay);
  }

  private spending(now: number): HourSpending {
    const day = parisDay(now);
    const start = hourStart(now);
    const usedToday = this.used(day);
    const [row] = this.database.all<{ calls: number }>(
      "SELECT calls FROM prim_budget_hours WHERE hour_start = ?",
      start,
    );
    const spentThisHour = Math.min(row?.calls ?? 0, usedToday);
    const allowedByHourEnd = this.allowedBy(now);
    return {
      parisDay: day,
      start,
      usedToday,
      spentThisHour,
      allowedByHourEnd,
      share: allowedByHourEnd - (usedToday - spentThisHour),
    };
  }

  private allowedBy(at: number): number {
    return this.allowedByEndOf[parisHourOfDay(at)] ?? this.dailyCap;
  }
}

function hourStart(at: number): number {
  return Math.floor(at / hour) * hour;
}
