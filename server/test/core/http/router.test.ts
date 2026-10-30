import { describe, expect, it } from "vitest";
import { route, type LiveActivityService, type RelayService } from "../../../src/core/http/router";
import type { StartResult } from "../../../src/core/live-activity/live-activity-starts";
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
const snapshot: MetricsSnapshot = { today: { ...zero, appCalls: 3 }, previousDay: zero, dailyCap: 800, failuresToday: [], startAnswersToday: {}, startAnswersPreviousDay: {} };

function server(
  answer: RelayAnswer = { kind: "times", body: '{"Siri":{}}', primAnsweredAt: Date.parse("2026-10-02T08:29:30.000Z") },
  appTokens: readonly string[] = [appToken],
  startResult: StartResult = { result: "started" },
) {
  const lines: string[] = [];
  const asked: string[] = [];
  const starts: { stationId: string; startToken: string }[] = [];
  let badRequests = 0;
  const liveActivities: LiveActivityService = {
    start: (stationId, startToken) => {
      starts.push({ stationId, startToken });
      return Promise.resolve(startResult);
    },
    badRequest: () => {
      badRequests += 1;
      return Promise.resolve();
    },
  };
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
      liveActivities,
    });
  return { send, lines, asked, starts, countsRead: () => countsRead, badRequests: () => badRequests };
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

describe("route: start of a Live Activity", () => {
  const startToken = "80a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f";
  const startUrl = `https://server.test/v1/stations/${encodeURIComponent("IDFM:22059")}/live-activity`;
  const ask = (body: string = JSON.stringify({ startToken }), token = appToken, method = "POST") =>
    withToken(startUrl, token, { method, body: method === "GET" ? null : body });

  it.each<[StartResult, number, unknown]>([
    [{ result: "started" }, 200, { result: "started" }],
    [{ result: "already-started" }, 200, { result: "already-started" }],
    [{ result: "refused", reason: "BadDeviceToken" }, 502, { result: "refused", reason: "BadDeviceToken" }],
    [{ result: "not-set-up" }, 503, { result: "not-set-up" }],
    [{ result: "unknown-station" }, 400, { error: "unknown station" }],
  ])("answers %j with its status and its words", async (result, status, body) => {
    const { send, starts, badRequests } = server(undefined, undefined, result);

    const response = await send(ask());

    expect(response.status).toBe(status);
    expect(await response.json()).toEqual(body);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(starts).toEqual([{ stationId: "IDFM:22059", startToken }]);
    // The start counts its own answers, an unknown station included.
    expect(badRequests()).toBe(0);
  });

  it("logs the route with no station and no token", async () => {
    const { send, lines } = server();

    await send(ask());

    expect(lines).toEqual([JSON.stringify({ level: "info", event: "request", method: "POST", route: "/v1/stations/{station}/live-activity", status: 200 })]);
  });

  it("refuses a wrong app token and another method, and starts nothing", async () => {
    for (const [request, status] of [
      [ask(undefined, "wrong"), 401],
      [ask(undefined, appToken, "GET"), 405],
      [ask(undefined, appToken, "PUT"), 405],
    ] as const) {
      const { send, starts, badRequests } = server();

      const response = await send(request);

      expect(response.status).toBe(status);
      expect(starts).toEqual([]);
      // Only an ask with the app token is counted, so that a stranger cannot fill the counts.
      expect(badRequests()).toBe(0);
    }
  });

  it("refuses a body that is not a start token, starts nothing, and counts it as a bad request", async () => {
    for (const body of [
      "",
      "not json",
      "{}",
      JSON.stringify({ startToken: 12 }),
      JSON.stringify({ startToken: "not-hex" }),
      JSON.stringify({ startToken: "ab" }),
      JSON.stringify({ startToken: "a".repeat(5000) }),
    ]) {
      const { send, starts, badRequests } = server();

      const response = await send(ask(body));

      expect(response.status, body.slice(0, 20)).toBe(400);
      expect(starts).toEqual([]);
      expect(badRequests(), body.slice(0, 20)).toBe(1);
    }
  });

  it("refuses a station id that is not one, and counts it as a bad request", async () => {
    const { send, starts, badRequests } = server();

    const response = await send(
      withToken(`https://server.test/v1/stations/${encodeURIComponent("a b")}/live-activity`, appToken, {
        method: "POST",
        body: JSON.stringify({ startToken }),
      }),
    );

    expect(response.status).toBe(400);
    expect(starts).toEqual([]);
    expect(badRequests()).toBe(1);
  });
});
