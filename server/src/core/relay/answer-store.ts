import type { SqlDatabase } from "../storage/sql-database";

export interface StoredAnswer {
  body: string;
  primAnsweredAt: number;
}

/**
 * The latest PRIM answer of each stop, shared by every rider of the stop, in memory only.
 * It is never written to storage: Cloudflare keeps every write to the storage of a server object restorable for 30 days, so a stop written with its time, even for a minute, would stay as a history of the stops asked for.
 */
export class AnswerStore {
  private readonly answers = new Map<string, StoredAnswer>();

  constructor(private readonly database: SqlDatabase) {
    database.run("DROP TABLE IF EXISTS answers");
    database.run(
      "CREATE TABLE IF NOT EXISTS relay_pauses (name TEXT PRIMARY KEY, until INTEGER NOT NULL) WITHOUT ROWID",
    );
  }

  answer(stopRef: string): StoredAnswer | undefined {
    return this.answers.get(stopRef);
  }

  keep(stopRef: string, answer: StoredAnswer): void {
    this.answers.set(stopRef, answer);
  }

  stopsHeld(): string[] {
    return [...this.answers.keys()];
  }

  /** When PRIM gave each answer in memory. */
  answeredTimes(): number[] {
    return [...this.answers.values()].map((answer) => answer.primAnsweredAt);
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
}
