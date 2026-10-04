import { env } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import { relayObject } from "../../src/cloudflare/relay-object";

export async function everyStoredRow(): Promise<string> {
  return runInDurableObject(relayObject(env), (_object, state) => {
    const tables = state.storage.sql
      .exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE '\\_%' ESCAPE '\\'")
      .toArray();
    return JSON.stringify(
      Object.fromEntries(tables.map(({ name }) => [name, state.storage.sql.exec(`SELECT * FROM "${name}"`).toArray()])),
    );
  });
}
