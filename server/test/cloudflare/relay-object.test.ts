import { env } from "cloudflare:workers";
import { evictDurableObject, listDurableObjectIds, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { relayObject } from "../../src/cloudflare/relay-object";

describe("RelayObject", () => {
  it("gets two requests in the same named object, and keeps its value in its storage between them", async () => {
    expect(await relayObject(env).addToCounter("visits")).toBe(1);

    await evictDurableObject(relayObject(env));

    expect(await relayObject(env).addToCounter("visits")).toBe(2);
    expect(await listDurableObjectIds(env.RELAY)).toHaveLength(1);
    const stored = await runInDurableObject(relayObject(env), (_object, state) =>
      state.storage.sql.exec<{ value: number }>("SELECT value FROM counters WHERE name = ?", "visits").one(),
    );
    expect(stored.value).toBe(2);
  });

  it("uses SQLite storage", async () => {
    const tables = await runInDurableObject(relayObject(env), (_object, state) =>
      state.storage.sql.exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table'").toArray(),
    );

    expect(tables.map(({ name }) => name)).toContain("counters");
  });
});
