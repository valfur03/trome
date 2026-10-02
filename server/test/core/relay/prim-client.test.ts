import { describe, expect, it } from "vitest";
import { createPrimClient, primEndpoint } from "../../../src/core/relay/prim-client";

describe("createPrimClient", () => {
  it("asks the stop monitoring of PRIM for one stop, with the key in its header, and gives the status and the body", async () => {
    const asked: { url: string; init: RequestInit }[] = [];
    const client = createPrimClient({
      apiKey: "prim-key",
      timeout: 10_000,
      fetch: (url, init) => {
        asked.push({ url, init });
        return Promise.resolve(new Response('{"Siri":{}}', { status: 200 }));
      },
    });

    expect(await client.stopMonitoring("STIF:StopArea:SP:42155:")).toEqual({ kind: "answer", status: 200, body: '{"Siri":{}}' });
    expect(asked).toHaveLength(1);
    expect(asked[0]?.url).toBe(`${primEndpoint}?MonitoringRef=STIF%3AStopArea%3ASP%3A42155%3A`);
    expect(asked[0]?.init.headers).toEqual({ apikey: "prim-key", accept: "application/json" });
    expect(asked[0]?.init.signal).toBeInstanceOf(AbortSignal);
  });

  it("gives the status and the body of an error answer", async () => {
    const client = createPrimClient({
      apiKey: "k",
      timeout: 10_000,
      fetch: () => Promise.resolve(new Response("Too many", { status: 429 })),
    });

    expect(await client.stopMonitoring("STIF:StopArea:SP:1:")).toEqual({ kind: "answer", status: 429, body: "Too many" });
  });

  it("says unreachable when PRIM does not answer, and gives the name of the error", async () => {
    const client = createPrimClient({
      apiKey: "k",
      timeout: 10_000,
      fetch: () => Promise.reject(new TypeError("network")),
    });

    expect(await client.stopMonitoring("STIF:StopArea:SP:1:")).toEqual({ kind: "unreachable", reason: "TypeError" });
  });

  it("stops waiting for PRIM after its timeout", async () => {
    const client = createPrimClient({
      apiKey: "k",
      timeout: 5,
      fetch: (_url, init) =>
        new Promise((_resolve, reject) => {
          init.signal?.addEventListener("abort", () => {
            reject(init.signal?.reason as Error);
          });
        }),
    });

    expect(await client.stopMonitoring("STIF:StopArea:SP:1:")).toEqual({ kind: "unreachable", reason: "TimeoutError" });
  });
});
