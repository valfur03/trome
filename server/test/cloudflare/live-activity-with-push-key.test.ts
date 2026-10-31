import { env, exports } from "cloudflare:workers";
import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { relayObject } from "../../src/cloudflare/relay-object";
import { primEndpoint } from "../../src/core/relay/prim-client";
import { day, hour, minute } from "../../src/core/time/clock";
import { recordedAnswer } from "./fake-prim";
import { forgetEverything } from "./forget-everything";

/**
 * The updates of a started Live Activity run in the storage alarm of the object, each one a new invocation with its own limit of subrequests, and never in the timer that keeps the object awake.
 * Apple and PRIM are faked: the push key is one made for the run (`vitest.config.ts`).
 */
const startToken = "80a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f";

afterEach(forgetEverything);

/** The recorded answer of Abbesses, as if PRIM gave it now: its trains leave 2 to 10 minutes from now. */
function recordedNow(): string {
  const shift = Date.now() - Date.parse("2026-09-26T10:00:00.412Z");
  return recordedAnswer("stop-monitoring-abbesses-stop-area.json").replace(/"(\d{4}-\d\d-\d\dT[\d:.]+Z)"/g, (_match, time: string) => JSON.stringify(new Date(Date.parse(time) + shift).toISOString()));
}

function fakeNetwork(startStatus = 200): { broadcasts: () => number; deletes: () => number; primCalls: () => number } {
  const requests: { method: string; url: string }[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
    const url = input instanceof Request ? input.url : String(input);
    const method = init?.method ?? "GET";
    requests.push({ method, url });
    if (url.startsWith(primEndpoint)) {
      return Promise.resolve(new Response(recordedNow()));
    }
    if (url.startsWith("https://api-manage-broadcast.sandbox.push.apple.com:2195/") && method === "POST") {
      return Promise.resolve(new Response(null, { status: 201, headers: { "apns-channel-id": "channel-1" } }));
    }
    if (url.includes("/3/device/") && startStatus !== 200) {
      return Promise.resolve(new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: startStatus }));
    }
    if (url.startsWith("https://api") && url.includes("push.apple.com")) {
      return Promise.resolve(new Response(null, { status: 200 }));
    }
    return Promise.reject(new Error(`No network in the tests: ${url}`));
  });
  const count = (match: (request: { method: string; url: string }) => boolean) => () => requests.filter(match).length;
  return {
    broadcasts: count((request) => request.url.startsWith("https://api.sandbox.push.apple.com/4/broadcasts/apps/com.example.trains")),
    deletes: count((request) => request.method === "DELETE"),
    primCalls: count((request) => request.url.startsWith(primEndpoint)),
  };
}

function plannedAlarm(): Promise<number | null> {
  return runInDurableObject(relayObject(env), (_object, state) => state.storage.getAlarm());
}

/** Moves the fake clock on inside the object, so that its timers run there, as they do on Cloudflare. */
async function passTime(milliseconds: number): Promise<void> {
  await runInDurableObject(relayObject(env), () => vi.advanceTimersByTimeAsync(milliseconds));
}

function start(): Promise<Response> {
  return exports.default.fetch("https://server.test/v1/stations/IDFM%3A22059/live-activity", {
    method: "POST",
    headers: { authorization: `Bearer ${env.APP_TOKEN}` },
    body: JSON.stringify({ startToken }),
  });
}

function useFakeTime(): void {
  vi.useFakeTimers({ toFake: ["Date", "setTimeout", "clearTimeout"], now: Math.ceil(Date.now() / hour) * hour + day + 30 * minute });
}

function timerCount(): Promise<number> {
  return runInDurableObject(relayObject(env), () => vi.getTimerCount());
}

describe("the updates of a started Live Activity on Cloudflare", () => {
  it("run in the alarm for 20 minutes, while a timer keeps the object awake, then the channel goes at 45 minutes and nothing is left", async () => {
    useFakeTime();
    const network = fakeNetwork();
    const startedAt = Date.now();

    expect(await (await start()).json()).toEqual({ result: "started" });

    let wakes = 0;
    for (let alarm = await plannedAlarm(); alarm !== null && wakes < 100; alarm = await plannedAlarm()) {
      const broadcasts = network.broadcasts();
      await passTime(alarm - Date.now());
      expect(network.broadcasts(), "no update from a timer").toBe(broadcasts);
      expect(await timerCount(), "a timer keeps the object awake").toBeGreaterThan(0);
      expect(await runDurableObjectAlarm(relayObject(env))).toBe(true);
      wakes += 1;
    }

    expect(Date.now() - startedAt).toBe(45 * minute);
    expect(network.broadcasts()).toBeGreaterThanOrEqual(8);
    expect(network.primCalls()).toBeLessThanOrEqual(21);
    expect(network.deletes()).toBe(1);
    await runInDurableObject(relayObject(env), () => vi.runAllTimersAsync());
    expect(await timerCount()).toBe(0);
  });

  it("fail the test that runs their alarm when it throws, as when storage cannot plan the next update", async () => {
    useFakeTime();
    fakeNetwork();
    expect(await (await start()).json()).toEqual({ result: "started" });
    await passTime(((await plannedAlarm()) ?? Date.now()) - Date.now());
    await runInDurableObject(relayObject(env), (_object, state) => {
      vi.spyOn(state.storage, "setAlarm").mockRejectedValueOnce(new Error("storage fault"));
    });

    await expect(runDurableObjectAlarm(relayObject(env))).rejects.toThrow("storage fault");
  });

  it("keeps the object awake while it holds a refused start, with no answer of PRIM left in memory", async () => {
    useFakeTime();
    const network = fakeNetwork(400);

    expect(await (await start()).json()).toMatchObject({ result: "refused" });
    await passTime(10 * minute);

    expect(await timerCount(), "a timer keeps the object awake").toBeGreaterThan(0);
    expect(network.broadcasts()).toBe(0);
  });
});
