import { DatabaseSync } from "node:sqlite";
import type { SqlDatabase, SqlValue } from "../../../src/core/storage/sql-database";

export class NodeSqliteDatabase implements SqlDatabase {
  constructor(private readonly database = new DatabaseSync(":memory:")) {}

  run(query: string, ...params: SqlValue[]): void {
    this.database.prepare(query).run(...params);
  }

  all<Row extends Record<string, SqlValue>>(query: string, ...params: SqlValue[]): Row[] {
    return this.database.prepare(query).all(...params) as Row[];
  }
}
