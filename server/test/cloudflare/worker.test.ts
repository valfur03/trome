import { env, exports } from "cloudflare:workers";
import { abortAllDurableObjects, runDurableObjectAlarm } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { relayObject } from "../../src/cloudflare/relay-object";
import worker from "../../src/cloudflare/worker";
import { everyStoredRow } from "./every-stored-row";
import { secretNames } from "../../src/core/config/secrets";
import { fakePrim } from "./fake-prim";
import { forgetEverything } from "./forget-everything";

const departuresUrl = "https://server.test/v1/stops/STIF:StopArea:SP:42155:/departures";

afterEach(forgetEverything);

const oldAppToken = "0a1b2c3d4e5f60718293a4b5c6d7e8f9";
const newAppToken = "f9e8d7c6b5a4938271605f4e3d2c1b0a";

function fetchWithAppTokens(secret: string, authorization: string): Promise<Response> {
  const request = new Request<unknown, IncomingRequestCfProperties>(departuresUrl, { headers: { authorization } });
  return Promise.resolve(worker.fetch(request, { ...env, APP_TOKEN: secret }));
}

function captureLogLines(): string[] {
  const lines: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...parts: unknown[]) => {
    lines.push(parts.map(String).join(" "));
  });
  return lines;
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

    await exports.default.fetch("https://server.test/health");
    const counts = await exports.default.fetch("https://server.test/v1/owner/counts", {
      headers: { authorization: `Bearer ${env.OWNER_TOKEN}` },
    });
    const report: { days: { appCalls: number }[] } = await counts.json();
    expect(report.days.map((day) => day.appCalls)).toEqual(report.days.map(() => 0));
  });

  it("adds a token and retires the old one as two steps of the secret, with no build cut off at the add", async () => {
    const prim = fakePrim();
    const lines = captureLogLines();

    for (const token of [oldAppToken, newAppToken]) {
      const added = await fetchWithAppTokens(`${oldAppToken},${newAppToken}`, `Bearer ${token}`);
      expect(added.status, token).toBe(200);
    }
    const retired = await fetchWithAppTokens(newAppToken, `Bearer ${oldAppToken}`);
    const kept = await fetchWithAppTokens(newAppToken, `Bearer ${newAppToken}`);
    const upperCase = await fetchWithAppTokens(`${oldAppToken},${newAppToken}`, `Bearer ${newAppToken.toUpperCase()}`);

    expect(retired.status).toBe(401);
    expect(await retired.json()).toEqual({ error: "unauthorized" });
    expect(kept.status).toBe(200);
    expect(upperCase.status).toBe(401);
    expect(prim.calls).toHaveLength(1);
    expect(lines.length).toBeGreaterThanOrEqual(5);
    for (const line of lines) {
      expect(line).not.toContain(oldAppToken);
      expect(line).not.toContain(newAppToken);
    }
  });

  it("stores and logs nothing of a rider: no stop, position, device, account, push token, IP, user agent or body", async () => {
    const prim = fakePrim();
    const lines = captureLogLines();
    const rider = {
      ip: "203.0.113.42",
      forwarded: "198.51.100.7",
      userAgent: "TROME/1.4 (iPhone15,2; iOS 26.0) rider-agent",
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
    expect(stored).toContain('"app_calls":1');
    for (const value of [...Object.values(rider), env.APP_TOKEN, "42155"]) {
      expect(stored, value).not.toContain(value);
      for (const line of lines) {
        expect(line, value).not.toContain(value);
      }
    }
  });
});

describe("the start of a Live Activity, before the push key is set", () => {
  const startToken = "80a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f";

  it("answers not set up, calls no one, and keeps neither the token nor the station", async () => {
    const prim = fakePrim();
    const lines = captureLogLines();

    const response = await exports.default.fetch("https://server.test/v1/stations/IDFM%3A22059/live-activity", {
      method: "POST",
      headers: { authorization: `Bearer ${env.APP_TOKEN}` },
      body: JSON.stringify({ startToken }),
    });

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ result: "not-set-up" });
    expect(prim.calls).toEqual([]);
    expect(vi.mocked(fetch)).not.toHaveBeenCalled();
    const stored = await everyStoredRow();
    expect(stored).not.toContain(startToken);
    expect(stored).not.toContain("22059");
    expect(lines.join("\n")).not.toContain(startToken);
    expect(lines.join("\n")).not.toContain("22059");
  });
  it("counts the answer and a bad ask by result, keeps them through a restart, and gives them to the owner with no token and no station", async () => {
    fakePrim();
    const ask = (body: string) =>
      exports.default.fetch("https://server.test/v1/stations/IDFM%3A22059/live-activity", {
        method: "POST",
        headers: { authorization: `Bearer ${env.APP_TOKEN}` },
        body,
      });
    expect((await ask(JSON.stringify({ startToken }))).status).toBe(503);
    expect((await ask("{}")).status).toBe(400);
    await abortAllDurableObjects();
    const owner = { headers: { authorization: `Bearer ${env.OWNER_TOKEN}` } };

    const counts = await (await exports.default.fetch("https://server.test/v1/owner/counts", owner)).text();
    const metrics = await (await exports.default.fetch("https://server.test/metrics", owner)).text();

    expect((JSON.parse(counts) as { days: { startAnswers: unknown }[] }).days[0]?.startAnswers).toEqual({ "not-set-up": 1, "bad-request": 1 });
    expect(metrics).toContain('trome_live_activity_starts_total{answer="not-set-up"} 1');
    expect(metrics).toContain('trome_live_activity_starts_total{answer="bad-request"} 1');
    for (const text of [counts, metrics, await everyStoredRow()]) {
      expect(text).not.toContain(startToken);
      expect(text).not.toContain("22059");
    }
  });
});
