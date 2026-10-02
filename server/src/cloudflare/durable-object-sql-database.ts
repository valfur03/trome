import type { SqlDatabase, SqlValue } from "../core/storage/sql-database";

export class DurableObjectSqlDatabase implements SqlDatabase {
  constructor(private readonly sql: SqlStorage) {}

  run(query: string, ...params: SqlValue[]): void {
    this.sql.exec(query, ...params);
  }

  all<Row extends Record<string, SqlValue>>(query: string, ...params: SqlValue[]): Row[] {
    return this.sql.exec<Row>(query, ...params).toArray();
  }
}
