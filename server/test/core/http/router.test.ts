import { describe, expect, it } from "vitest";
import { route, type RelayService } from "../../../src/core/http/router";
import { createLogger } from "../../../src/core/logging/logger";
import type { MetricsSnapshot } from "../../../src/core/metrics/prometheus-metrics";
import type { CountsReport, RelayAnswer } from "../../../src/core/relay/relay";
import { FakeClock } from "../time/fake-clock";

const appToken = "app-token-1";
const ownerToken = "owner-token-2";
const stopRef = "STIF:StopArea:SP:42155:";
const departuresUrl = `https://server.test/v1/stops/${stopRef}/departures`;

const report: CountsReport = {
  today: "2026-10-02",
  dailyCap: 800,
  primCallsToday: 0,
  limitPauseUntil: null,
  days: [],
  errorLines: [],
};

const zero = { appCalls: 0, cacheHits: 0, heldAnswers: 0, outAnswers: 0, primCalls: 0, errors: 0, unreadableAnswers: 0 };
const snapshot: MetricsSnapshot = { today: { ...zero, appCalls: 3 }, previousDay: zero, dailyCap: 800, failuresToday: [] };

function server(
  answer: RelayAnswer = { kind: "times", body: '{"Siri":{}}', primAnsweredAt: Date.parse("2026-10-02T08:29:30.000Z") },
  appTokens: readonly string[] = [appToken],
) {
  const lines: string[] = [];
  const asked: string[] = [];
  let countsRead = 0;
  const relay: RelayService = {
    departures: (stop) => {
      asked.push(stop);
      return Promise.resolve(answer);
    },
    counts: () => {
      countsRead += 1;
      return Promise.resolve(report);
    },
    metrics: () => {
      countsRead += 1;
      return Promise.resolve(snapshot);
    },
  };
  const send = (request: Request) =>
    route(request, {
      logger: createLogger([...appTokens, ownerToken], (line) => lines.push(line)),
      clock: FakeClock.at("2026-10-02T08:30:00.000Z"),
      tokens: { app: appTokens, owner: ownerToken },
      relay,
    });
  return { send, lines, asked, countsRead: () => countsRead };
}

const withToken = (url: string, token: string, init: RequestInit = {}) =>
  new Request(url, { ...init, headers: { authorization: `Bearer ${token}` } });

describe("route: health", () => {
  it("answers ok at the health address, with no key", async () => {
    const response = await server().send(new Request("https://server.test/health"));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  it("refuses another method at the health address", async () => {
    const response = await server().send(new Request("https://server.test/health", { method: "POST" }));

    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("GET, HEAD");
  });

  it("answers not found at any other address", async () => {
    const response = await server().send(new Request("https://server.test/v1/stops"));

    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "not found" });
  });
});

describe("route: departures", () => {
  it("gives the answer of the relay for the stop of the path, with the time when PRIM gave it", async () => {
    const { send, asked } = server();

    const response = await send(withToken(departuresUrl, appToken));

    expect(asked).toEqual([stopRef]);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/json");
    expect(response.headers.get("last-modified")).toBe("Fri, 02 Oct 2026 08:29:30 GMT");
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.text()).toBe('{"Siri":{}}');
  });

  it("reads a stop reference that the app encodes in the path", async () => {
    const { send, asked } = server();

    await send(withToken(`https://server.test/v1/stops/${encodeURIComponent(stopRef)}/departures`, appToken));

    expect(asked).toEqual([stopRef]);
  });

  it("answers out with the time when the server tries again", async () => {
    const { send } = server({ kind: "out", reason: "budget", retryAt: Date.parse("2026-10-02T22:00:00.000Z") });

    const response = await send(withToken(departuresUrl, appToken));

    expect(response.status).toBe(503);
    expect(response.headers.get("retry-after")).toBe("48600");
    expect(await response.json()).toEqual({ status: "out", reason: "budget", retryAt: "2026-10-02T22:00:00.000Z" });
  });

  it("refuses a missing or wrong token, with no call to the relay", async () => {
    for (const request of [
      new Request(departuresUrl),
      withToken(departuresUrl, "wrong"),
      withToken(departuresUrl, ownerToken),
      new Request(departuresUrl, { headers: { authorization: appToken } }),
    ]) {
      const { send, asked } = server();
      const response = await send(request);

      expect(response.status).toBe(401);
      expect(response.headers.get("www-authenticate")).toBe("Bearer");
      expect(await response.json()).toEqual({ error: "unauthorized" });
      expect(asked).toEqual([]);
    }
  });

  it("answers each token of a list of two, so a new token is added while the builds with the old one keep their times", async () => {
    for (const token of ["old-app-token", "new-app-token"]) {
      const { send, asked } = server(undefined, ["old-app-token", "new-app-token"]);
      const response = await send(withToken(departuresUrl, token));

      expect(response.status, token).toBe(200);
      expect(asked).toEqual([stopRef]);
    }
  });

  it("refuses a token once it leaves the list, a wrong one and the owner token, with no call to the relay", async () => {
    for (const token of ["old-app-token", "wrong", ownerToken]) {
      const { send, asked } = server(undefined, ["new-app-token"]);
      const response = await send(withToken(departuresUrl, token));

      expect(response.status, token).toBe(401);
      expect(await response.json()).toEqual({ error: "unauthorized" });
      expect(asked).toEqual([]);
    }
  });

  it("refuses every request when the list is empty", async () => {
    const { send, asked } = server(undefined, []);
    const response = await send(withToken(departuresUrl, appToken));

    expect(response.status).toBe(401);
    expect(asked).toEqual([]);
  });

  it("refuses a bad stop reference, with no call to the relay", async () => {
    for (const stop of ["IDFM:22059", "STIF:StopArea:SP:1:%26apikey=x", "%E0%A4%A"]) {
      const { send, asked } = server();
      const response = await send(withToken(`https://server.test/v1/stops/${stop}/departures`, appToken));

      expect(response.status, stop).toBe(400);
      expect(await response.json()).toEqual({ error: "bad stop reference" });
      expect(asked).toEqual([]);
    }
  });

  it("refuses another method, with no call to the relay", async () => {
    const { send, asked } = server();

    const response = await send(withToken(departuresUrl, appToken, { method: "POST", body: '{"latitude":48.88}' }));

    expect(response.status).toBe(405);
    expect(asked).toEqual([]);
  });

  it("logs the method, the route and the status, and not the stop, the query or the headers", async () => {
    const { send, lines } = server();

    await send(
      new Request(`${departuresUrl}?latitude=48.884&device=abc`, {
        headers: { authorization: `Bearer ${appToken}`, "user-agent": "TROME/1.0 iOS/26.0", "x-device-id": "abc" },
      }),
    );

    expect(lines.map((line) => JSON.parse(line) as unknown)).toEqual([
      { level: "info", event: "request", method: "GET", route: "/v1/stops/{stop}/departures", status: 200 },
    ]);
  });

  it("logs any other address as an unknown route", async () => {
    const { send, lines } = server();

    await send(withToken(`https://server.test/v1/stops/${stopRef}/departures/`, appToken));
    await send(new Request("https://server.test/health"));
    await send(withToken("https://server.test/v1/owner/counts", ownerToken));

    expect(lines.map((line) => (JSON.parse(line) as { route: string }).route)).toEqual(["unknown", "/health", "/v1/owner/counts"]);
  });
});

describe("route: counts of the owner", () => {
  it("gives the counts with the owner token", async () => {
    const { send } = server();

    const response = await send(withToken("https://server.test/v1/owner/counts", ownerToken));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(report);
  });

  it("refuses the app token and a missing token, with no read of the counts", async () => {
    for (const request of [withToken("https://server.test/v1/owner/counts", appToken), new Request("https://server.test/v1/owner/counts")]) {
      const { send, countsRead } = server();

      expect((await send(request)).status).toBe(401);
      expect(countsRead()).toBe(0);
    }
  });
});

describe("route: metrics of the owner", () => {
  it("gives the totals in the Prometheus text format with the owner token", async () => {
    const { send, lines } = server();

    const response = await send(withToken("https://server.test/metrics", ownerToken));

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/plain; version=0.0.4; charset=utf-8");
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.text()).toContain("\ntrome_app_calls_total 3\n");
    expect(lines.map((line) => (JSON.parse(line) as { route: string }).route)).toEqual(["/metrics"]);
  });

  it("gives the refusal of the owner route to the app token, a wrong token and no token, with no number", async () => {
    const refusal = await server().send(new Request("https://server.test/v1/owner/counts"));
    const refusalBody = await refusal.text();
    for (const request of [
      withToken("https://server.test/metrics", appToken),
      withToken("https://server.test/metrics", "wrong"),
      new Request("https://server.test/metrics"),
    ]) {
      const { send, countsRead } = server();

      const response = await send(request);

      expect(response.status).toBe(401);
      expect(response.headers.get("www-authenticate")).toBe("Bearer");
      expect(await response.text()).toBe(refusalBody);
      expect(countsRead()).toBe(0);
    }
  });

  it("refuses another method", async () => {
    const response = await server().send(withToken("https://server.test/metrics", ownerToken, { method: "POST" }));

    expect(response.status).toBe(405);
  });
});
