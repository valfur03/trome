import { env, exports } from "cloudflare:workers";
import { abortAllDurableObjects, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { relayObject } from "../../src/cloudflare/relay-object";
import { secretNames } from "../../src/core/config/secrets";
import { fakePrim } from "./fake-prim";

const departuresUrl = "https://server.test/v1/stops/STIF:StopArea:SP:42155:/departures";

afterEach(async () => {
  vi.restoreAllMocks();
  await runInDurableObject(relayObject(env), (_object, state) => state.storage.deleteAll());
  await abortAllDurableObjects();
});

function captureLogLines(): string[] {
  const lines: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...parts: unknown[]) => {
    lines.push(parts.map(String).join(" "));
  });
  return lines;
}

async function everyStoredRow(): Promise<string> {
  return runInDurableObject(relayObject(env), (_object, state) => {
    const tables = state.storage.sql
      .exec<{ name: string }>("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE '\\_%' ESCAPE '\\'")
      .toArray();
    return JSON.stringify(
      Object.fromEntries(tables.map(({ name }) => [name, state.storage.sql.exec(`SELECT * FROM "${name}"`).toArray()])),
    );
  });
}

describe("the Worker", () => {
  it("answers at the health address with no key", async () => {
    const response = await exports.default.fetch("https://server.test/health");

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  it("never prints a secret in its log lines", async () => {
    fakePrim();
    const secrets = secretNames.map((name) => env[name]);
    expect(secrets.every((secret) => secret.length > 0)).toBe(true);
    const lines = captureLogLines();

    for (const secret of secrets) {
      await exports.default.fetch(`https://server.test/${secret}?key=${secret}`, {
        headers: { authorization: `Bearer ${secret}` },
      });
      await exports.default.fetch(`https://server.test/v1/stops/${secret}/departures`, {
        headers: { authorization: `Bearer ${secret}` },
      });
    }
    await exports.default.fetch(departuresUrl, { headers: { authorization: `Bearer ${env.APP_TOKEN}` } });

    expect(lines.length).toBeGreaterThanOrEqual(2 * secrets.length + 1);
    for (const line of lines) {
      for (const secret of secrets) {
        expect(line).not.toContain(secret);
      }
    }
  });

  it("refuses a missing or wrong app token with no PRIM call and no count", async () => {
    const prim = fakePrim();

    for (const authorization of [undefined, "Bearer wrong", `Bearer ${env.OWNER_TOKEN}`, env.APP_TOKEN]) {
      const response = await exports.default.fetch(departuresUrl, {
        headers: authorization === undefined ? {} : { authorization },
      });
      expect(response.status).toBe(401);
    }

    expect(prim.calls).toEqual([]);
    expect(await everyStoredRow()).not.toContain("42155");
  });

  it("stores and logs nothing of a rider: no position, device, account, push token, IP, user agent or body", async () => {
    const prim = fakePrim();
    const lines = captureLogLines();
    const rider = {
      ip: "203.0.113.42",
      forwarded: "198.51.100.7",
      userAgent: "RATPActivity/1.4 (iPhone15,2; iOS 26.0) rider-agent",
      device: "6F1C2A90-DEVICE-ID",
      account: "rider@example.test",
      pushToken: "a1b2c3d4e5f6push",
      latitude: "48.884388",
      longitude: "2.338381",
      cookie: "session=cookie-value-77",
    };
    const headers = {
      authorization: `Bearer ${env.APP_TOKEN}`,
      "cf-connecting-ip": rider.ip,
      "x-forwarded-for": rider.forwarded,
      "x-real-ip": rider.ip,
      "user-agent": rider.userAgent,
      "x-device-id": rider.device,
      "x-account": rider.account,
      "x-push-token": rider.pushToken,
      cookie: rider.cookie,
    };
    const query = new URLSearchParams({ lat: rider.latitude, lon: rider.longitude, device: rider.device });

    const answered = await exports.default.fetch(`${departuresUrl}?${query.toString()}`, { headers });
    const withBody = await exports.default.fetch(departuresUrl, { method: "POST", headers, body: JSON.stringify(rider) });
    await runDurableObjectAlarm(relayObject(env));

    expect(answered.status).toBe(200);
    expect(withBody.status).toBe(405);
    expect(prim.calls).toHaveLength(1);
    expect([...(prim.calls[0]?.searchParams.keys() ?? [])]).toEqual(["MonitoringRef"]);
    const stored = await everyStoredRow();
    expect(stored).toContain("STIF:StopArea:SP:42155:");
    for (const value of [...Object.values(rider), env.APP_TOKEN]) {
      expect(stored, value).not.toContain(value);
      for (const line of lines) {
        expect(line, value).not.toContain(value);
      }
    }
  });
});
