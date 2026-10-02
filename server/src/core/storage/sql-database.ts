export type SqlValue = string | number | null;

export interface SqlDatabase {
  run(query: string, ...params: SqlValue[]): void;
  all<Row extends Record<string, SqlValue>>(query: string, ...params: SqlValue[]): Row[];
}
