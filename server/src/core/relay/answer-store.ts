import type { SqlDatabase } from "../storage/sql-database";

export interface StoredAnswer {
  body: string;
  primAnsweredAt: number;
}

export class AnswerStore {
  constructor(private readonly database: SqlDatabase) {
    database.run(
      "CREATE TABLE IF NOT EXISTS answers (stop_ref TEXT PRIMARY KEY, body TEXT NOT NULL, prim_answered_at INTEGER NOT NULL) WITHOUT ROWID",
    );
    database.run(
      "CREATE TABLE IF NOT EXISTS relay_pauses (name TEXT PRIMARY KEY, until INTEGER NOT NULL) WITHOUT ROWID",
    );
  }

  answer(stopRef: string): StoredAnswer | undefined {
    const [row] = this.database.all<{ body: string; prim_answered_at: number }>(
      "SELECT body, prim_answered_at FROM answers WHERE stop_ref = ?",
      stopRef,
    );
    return row && { body: row.body, primAnsweredAt: row.prim_answered_at };
  }

  keep(stopRef: string, answer: StoredAnswer): void {
    this.database.run(
      "INSERT INTO answers (stop_ref, body, prim_answered_at) VALUES (?, ?, ?) ON CONFLICT (stop_ref) DO UPDATE SET body = excluded.body, prim_answered_at = excluded.prim_answered_at",
      stopRef,
      answer.body,
      answer.primAnsweredAt,
    );
  }

  limitPauseUntil(): number {
    const [row] = this.database.all<{ until: number }>(
      "SELECT until FROM relay_pauses WHERE name = 'prim-limit'",
    );
    return row?.until ?? 0;
  }

  pauseForLimitUntil(until: number): void {
    this.database.run(
      "INSERT INTO relay_pauses (name, until) VALUES ('prim-limit', ?) ON CONFLICT (name) DO UPDATE SET until = excluded.until",
      until,
    );
  }

  forgetAnswersBefore(at: number): void {
    this.database.run("DELETE FROM answers WHERE prim_answered_at < ?", at);
  }
}
