import { describe, expect, it } from "vitest";
import { route } from "../../../src/core/http/router";
import { createLogger } from "../../../src/core/logging/logger";

function routeWithLog(request: Request) {
  const lines: string[] = [];
  const response = route(request, { logger: createLogger([], (line) => lines.push(line)) });
  return { lines, response };
}

describe("route", () => {
  it("answers ok at the health address, with no key", async () => {
    const { response } = routeWithLog(new Request("https://server.test/health"));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  it("refuses another method at the health address", () => {
    const { response } = routeWithLog(new Request("https://server.test/health", { method: "POST" }));

    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("GET, HEAD");
  });

  it("answers not found at any other address", async () => {
    const { response } = routeWithLog(new Request("https://server.test/v1/stops/x/departures"));

    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "not found" });
  });

  it("logs the method, the path and the status, and not the query or the headers", () => {
    const { lines } = routeWithLog(
      new Request("https://server.test/health?token=abc", { headers: { authorization: "Bearer abc" } }),
    );

    expect(lines.map((line) => JSON.parse(line) as unknown)).toEqual([
      { level: "info", event: "request", method: "GET", path: "/health", status: 200 },
    ]);
  });
});
