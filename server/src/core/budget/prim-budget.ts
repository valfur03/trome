import type { SqlDatabase } from "../storage/sql-database";

export class PrimBudget {
  constructor(
    private readonly database: SqlDatabase,
    readonly dailyCap: number,
  ) {
    database.run(
      "CREATE TABLE IF NOT EXISTS prim_budget (paris_day TEXT PRIMARY KEY, calls INTEGER NOT NULL) WITHOUT ROWID",
    );
  }

  claim(parisDay: string): boolean {
    const claimed = this.database.all<{ calls: number }>(
      "INSERT INTO prim_budget (paris_day, calls) VALUES (?, 1) ON CONFLICT (paris_day) DO UPDATE SET calls = calls + 1 WHERE calls < ? RETURNING calls",
      parisDay,
      this.dailyCap,
    );
    return claimed.length === 1;
  }

  used(parisDay: string): number {
    const [row] = this.database.all<{ calls: number }>(
      "SELECT calls FROM prim_budget WHERE paris_day = ?",
      parisDay,
    );
    return row?.calls ?? 0;
  }

  isSpent(parisDay: string): boolean {
    return this.used(parisDay) >= this.dailyCap;
  }

  forgetDaysBefore(parisDay: string): void {
    this.database.run("DELETE FROM prim_budget WHERE paris_day < ?", parisDay);
  }
}
