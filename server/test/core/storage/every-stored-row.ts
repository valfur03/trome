import type { SqlDatabase } from "../../../src/core/storage/sql-database";

export function everyStoredRow(database: SqlDatabase): Record<string, unknown[]> {
  const tables = database.all<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table'");
  return Object.fromEntries(tables.map(({ name }) => [name, database.all(`SELECT * FROM "${name}"`)]));
}
