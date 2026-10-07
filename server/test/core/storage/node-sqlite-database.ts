import { DatabaseSync, type StatementSync } from "node:sqlite";
import type { SqlDatabase, SqlValue } from "../../../src/core/storage/sql-database";

// Keeps the prepared statement of each query, as the SQL storage of a Durable Object does.
// A new statement on each call took most of the time of the tests of a whole day.
export class NodeSqliteDatabase implements SqlDatabase {
  private readonly statements = new Map<string, StatementSync>();

  constructor(private readonly database = new DatabaseSync(":memory:")) {}

  run(query: string, ...params: SqlValue[]): void {
    this.statement(query).run(...params);
  }

  all<Row extends Record<string, SqlValue>>(query: string, ...params: SqlValue[]): Row[] {
    return this.statement(query).all(...params) as Row[];
  }

  private statement(query: string): StatementSync {
    let statement = this.statements.get(query);
    if (!statement) {
      statement = this.database.prepare(query);
      this.statements.set(query, statement);
    }
    return statement;
  }
}
