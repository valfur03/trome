import type { SqlDatabase } from "../storage/sql-database";

export class Counters {
  constructor(private readonly database: SqlDatabase) {
    database.run(
      "CREATE TABLE IF NOT EXISTS counters (name TEXT PRIMARY KEY, value INTEGER NOT NULL)",
    );
  }

  add(name: string, amount = 1): number {
    this.database.run(
      "INSERT INTO counters (name, value) VALUES (?, ?) ON CONFLICT (name) DO UPDATE SET value = value + excluded.value",
      name,
      amount,
    );
    return this.read(name);
  }

  read(name: string): number {
    const [row] = this.database.all<{ value: number }>(
      "SELECT value FROM counters WHERE name = ?",
      name,
    );
    return row?.value ?? 0;
  }
}
