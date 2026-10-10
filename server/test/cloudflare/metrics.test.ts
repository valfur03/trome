import { env, exports } from "cloudflare:workers";
import { abortAllDurableObjects, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { relayObject } from "../../src/cloudflare/relay-object";
import type { SqlDatabase, SqlValue } from "../../src/core/storage/sql-database";
import { hour } from "../../src/core/time/clock";
import { UsageCounts, metricsTotals } from "../../src/core/usage/usage-counts";

afterEach(async () => {
  await runInDurableObject(relayObject(env), (_object, state) => state.storage.deleteAll());
  await abortAllDurableObjects();
});

function metrics(token?: string): Promise<Response> {
  return exports.default.fetch("https://server.test/metrics", token ? { headers: { authorization: `Bearer ${token}` } } : {});
}

describe("/metrics", () => {
  it("gives the totals to the owner token only, and does not count the read as an app call", async () => {
    expect((await metrics()).status).toBe(401);
    expect((await metrics(env.APP_TOKEN)).status).toBe(401);

    const response = await metrics(env.OWNER_TOKEN);

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/plain; version=0.0.4; charset=utf-8");
    const text = await response.text();
    expect(text).toContain("\ntrome_app_calls_total 0\n");
    expect(text).toContain("\ntrome_prim_daily_cap 800\n");
  });

  it("reads few rows with 30 days of hours and a week of failures, and writes none", async () => {
    // Measured in the Cloudflare runtime: the rows that SQLite reads and writes are what the Free plan counts.
    const measure = await runInDurableObject(relayObject(env), (_object, state) => {
      let rowsRead = 0;
      let rowsWritten = 0;
      const database: SqlDatabase = {
        run(query: string, ...params: SqlValue[]) {
          const cursor = state.storage.sql.exec(query, ...params);
          cursor.toArray();
          rowsRead += cursor.rowsRead;
          rowsWritten += cursor.rowsWritten;
        },
        all<Row extends Record<string, SqlValue>>(query: string, ...params: SqlValue[]): Row[] {
          const cursor = state.storage.sql.exec<Row>(query, ...params);
          const rows = cursor.toArray();
          rowsRead += cursor.rowsRead;
          rowsWritten += cursor.rowsWritten;
          return rows;
        },
      };
      const now = Date.parse("2026-10-02T10:30:00.000Z");
      const usage = new UsageCounts(database, () => undefined);
      for (let at = now - 30 * 24 * hour; at <= now; at += hour) {
        usage.count("appCalls", at);
      }
      // The worst day: each of the 800 PRIM calls of the cap failed since Paris midnight (00:00 is 22:00 UTC), after a week of failures.
      for (let at = now - 7 * 24 * hour; at < now - 12.5 * hour; at += 12 * 60_000) {
        usage.recordError({ at, kind: "prim-http-error", status: 500 });
      }
      for (let index = 0; index < 800; index += 1) {
        usage.recordError({ at: Date.parse("2026-10-01T22:00:00.000Z") + index * 50_000, kind: "prim-timeout", status: null });
      }
      usage.flush();
      rowsRead = 0;
      rowsWritten = 0;
      const totals = metricsTotals(database, now);
      return { rowsRead, rowsWritten, today: totals.today.appCalls, failures: totals.failuresToday };
    });

    expect(measure.today).toBeGreaterThan(0);
    expect(measure.failures).toEqual([{ kind: "prim-timeout", status: null, count: 800 }]);
    expect(measure.rowsWritten).toBe(0);
    // The last 50 hours and the 800 failures of today, from the index only, out of 721 hours and about 1,600 failures.
    // Measured: 902. At one scrape every 2 minutes, 720 reads of 1,000 rows are 14% of the 5 million a day of the Free plan.
    expect(measure.rowsRead).toBeLessThanOrEqual(1000);
  });

  it("answers fast enough for one scrape a minute", async () => {
    await metrics(env.OWNER_TOKEN);
    const reads = 50;
    const started = performance.now();
    for (let index = 0; index < reads; index += 1) {
      await (await metrics(env.OWNER_TOKEN)).text();
    }
    const each = (performance.now() - started) / reads;
    // Measured: about 3 ms each in the local runtime.
    expect(each).toBeLessThan(100);
  });
});
