import type { SqlDatabase } from "../storage/sql-database";

export interface StoredAnswer {
  body: string;
  primAnsweredAt: number;
}

/**
 * The latest PRIM answer of each stop, shared by every rider of the stop.
 * Memory holds it first.
 * Storage holds a copy too, so that the answer outlives the sleep of an idle server object:
 * the copy has the stop, the body and the time of the PRIM answer only, the next answer of the stop replaces it, and the relay deletes it once it is too old to be given.
 */
export class AnswerStore {
  private readonly answers = new Map<string, StoredAnswer>();

  constructor(private readonly database: SqlDatabase) {
    database.run("DROP TABLE IF EXISTS answers");
    database.run(
      "CREATE TABLE IF NOT EXISTS shared_answers (stop_ref TEXT PRIMARY KEY, body TEXT NOT NULL, prim_answered_at INTEGER NOT NULL) WITHOUT ROWID",
    );
    // So that the delete of each request reads only the copies that it deletes.
    database.run("CREATE INDEX IF NOT EXISTS shared_answers_age ON shared_answers (prim_answered_at)");
    database.run(
      "CREATE TABLE IF NOT EXISTS relay_pauses (name TEXT PRIMARY KEY, until INTEGER NOT NULL) WITHOUT ROWID",
    );
  }

  answer(stopRef: string): StoredAnswer | undefined {
    const inMemory = this.answers.get(stopRef);
    if (inMemory) {
      return inMemory;
    }
    const [row] = this.database.all<{ body: string; prim_answered_at: number }>(
      "SELECT body, prim_answered_at FROM shared_answers WHERE stop_ref = ?",
      stopRef,
    );
    if (!row) {
      return undefined;
    }
    const copy = { body: row.body, primAnsweredAt: row.prim_answered_at };
    this.answers.set(stopRef, copy);
    return copy;
  }

  keep(stopRef: string, answer: StoredAnswer): void {
    this.answers.set(stopRef, answer);
    this.database.run(
      "INSERT INTO shared_answers (stop_ref, body, prim_answered_at) VALUES (?, ?, ?) ON CONFLICT (stop_ref) DO UPDATE SET body = excluded.body, prim_answered_at = excluded.prim_answered_at",
      stopRef,
      answer.body,
      answer.primAnsweredAt,
    );
  }

  stopsHeld(): string[] {
    return [...this.answers.keys()];
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

  forgetAnswersGivenBy(at: number): void {
    for (const [stopRef, answer] of this.answers) {
      if (answer.primAnsweredAt <= at) {
        this.answers.delete(stopRef);
      }
    }
  }

  forgetCopiesGivenBy(at: number): void {
    this.database.run("DELETE FROM shared_answers WHERE prim_answered_at <= ?", at);
  }

  /** When PRIM gave the oldest answer in memory, and the oldest copy in storage. */
  oldestAnswers(): { inMemory: number | undefined; copy: number | undefined } {
    let inMemory: number | undefined;
    for (const answer of this.answers.values()) {
      inMemory = Math.min(inMemory ?? answer.primAnsweredAt, answer.primAnsweredAt);
    }
    const [row] = this.database.all<{ oldest: number | null }>("SELECT MIN(prim_answered_at) AS oldest FROM shared_answers");
    return { inMemory, copy: row?.oldest ?? undefined };
  }
}
