import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it, vi } from "vitest";
import { contentOfStation } from "../../../src/core/live-activity/content-of-station";
import { LiveActivityStarts, startWindow } from "../../../src/core/live-activity/live-activity-starts";
import { StationCatalog } from "../../../src/core/live-activity/station-catalog";
import { encodeContent, staleDate } from "../../../src/core/live-activity/station-content";
import { createLogger } from "../../../src/core/logging/logger";
import { metricsText } from "../../../src/core/metrics/prometheus-metrics";
import { hour, minute } from "../../../src/core/time/clock";
import { testApnsSettings } from "../push/fake-apple";
import { everyStoredRow } from "../storage/every-stored-row";
import { startHarness } from "./live-activity-harness";

const catalog = StationCatalog.bundled();
const abbesses = "IDFM:22059";
const chateletLesHalles = "IDFM:monomodalStopPlace:45102";
const token = "80a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f80a1b2c3d4e5f607";
const otherToken = "11a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f80a1b2c3d4e5f6ff";

interface StartBody {
  aps: Record<string, unknown> & { alert: { title: string; body: string }; "content-state": unknown };
}

function decodeBase64Url(text: string): Uint8Array<ArrayBuffer> {
  const binary = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

/** Every string that the object holds, through its fields, maps and sets: the start token must be none of them. */
function stringsHeldBy(value: unknown, seen = new Set<unknown>()): string[] {
  if (typeof value === "string") {
    return [value];
  }
  if (value === null || typeof value !== "object" || seen.has(value)) {
    return [];
  }
  seen.add(value);
  if (value instanceof Map) {
    return [...value.entries()].flatMap(([key, entry]) => [...stringsHeldBy(key, seen), ...stringsHeldBy(entry, seen)]);
  }
  if (value instanceof Set || Array.isArray(value)) {
    return [...(value as Iterable<unknown>)].flatMap((entry) => stringsHeldBy(entry, seen));
  }
  return Object.values(value).flatMap((entry) => stringsHeldBy(entry, seen));
}

describe("the start of a Live Activity", () => {
  it("answers not set up, and calls neither Apple nor PRIM, without the push key", async () => {
    const { starts, apple, relay } = await startHarness({ settings: "none" });

    expect(await starts.start(abbesses, token)).toEqual({ result: "not-set-up" });
    expect(apple.requests).toEqual([]);
    expect(relay.prim.calls).toEqual([]);
    expect(starts.nextWake()).toBeUndefined();
  });

  it("sends Apple the start of the station, on its channel, with the content that the app would show", async () => {
    const { starts, apple, relay, publicKeys } = await startHarness();

    expect(await starts.start(abbesses, token)).toEqual({ result: "started" });

    const [channel, start] = apple.requests;
    expect(apple.requests).toHaveLength(2);
    expect(channel?.method).toBe("POST");
    expect(channel?.url).toBe("https://api-manage-broadcast.push.apple.com:2196/1/apps/com.example.trains/channels");
    expect(JSON.parse(channel?.body ?? "")).toEqual({ "message-storage-policy": 0, "push-type": "LiveActivity" });
    expect(start?.method).toBe("POST");
    expect(start?.url).toBe(`https://api.push.apple.com/3/device/${token}`);
    expect(start?.headers).toMatchObject({
      "apns-push-type": "liveactivity",
      "apns-topic": "com.example.trains.push-type.liveactivity",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor((relay.clock.now() + 2 * minute) / 1000)),
    });

    const [header, claims, signature] = (start?.headers.authorization ?? "").replace("bearer ", "").split(".");
    expect(JSON.parse(atob(header ?? ""))).toEqual({ alg: "ES256", kid: "KEYPRODUCTION" });
    expect(JSON.parse(atob(claims ?? ""))).toEqual({ iss: "TEAMID1234", iat: Math.floor(relay.clock.now() / 1000) });
    const publicKey = publicKeys.KEYPRODUCTION;
    if (publicKey === undefined) {
      throw new Error("no public key");
    }
    const signed = new TextEncoder().encode(`${header ?? ""}.${claims ?? ""}`);
    expect(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, decodeBase64Url(signature ?? ""), signed)).toBe(true);

    const station = catalog.station(abbesses);
    if (station === undefined) {
      throw new Error("no Abbesses");
    }
    const content = await contentOfStation(station, catalog, (stopRef) => relay.relay.departures(stopRef), () => relay.clock.now());
    const body = JSON.parse(start?.body ?? "") as StartBody;
    expect(body.aps).toMatchObject({
      timestamp: Math.floor(relay.clock.now() / 1000),
      event: "start",
      "attributes-type": "StationActivityAttributes",
      attributes: {},
      alert: { title: "Abbesses", body: "M12" },
      "input-push-channel": "channel-1",
    });
    expect(body.aps["content-state"]).toEqual(encodeContent(content));
    expect(JSON.stringify(body.aps["content-state"])).toContain('"trains":[{');
    expect(body.aps["stale-date"]).toBe(Math.floor((staleDate(content) ?? 0) / 1000));
    expect(body.aps["stale-date"]).toBeGreaterThan(Math.floor(relay.clock.now() / 1000));
    expect(relay.prim.calls).toEqual(["STIF:StopArea:SP:42155:"]);
  });

  it("answers already started to the same token and station within 45 minutes, and sends nothing", async () => {
    const { starts, apple, relay } = await startHarness();
    await starts.start(abbesses, token);
    const sent = apple.requests.length;
    const primCalls = relay.prim.calls.length;

    relay.clock.advance(startWindow - minute);
    expect(await starts.start(abbesses, token)).toEqual({ result: "already-started" });
    expect(apple.requests).toHaveLength(sent);
    expect(relay.prim.calls).toHaveLength(primCalls);

    relay.clock.advance(minute);
    expect(await starts.start(abbesses, token)).toEqual({ result: "started" });
    expect(apple.starts).toHaveLength(2);
  });

  it("sends one start when the same ask comes twice at once", async () => {
    const { starts, apple } = await startHarness();

    const results = await Promise.all([starts.start(abbesses, token), starts.start(abbesses, token)]);

    expect(results.map(({ result }) => result).sort()).toEqual(["already-started", "started"]);
    expect(apple.starts).toHaveLength(1);
  });

  it("starts again for another token or another station, on the one channel of each station", async () => {
    const { starts, apple } = await startHarness();

    await starts.start(abbesses, token);
    expect(await starts.start(abbesses, otherToken)).toEqual({ result: "started" });
    expect(await starts.start(chateletLesHalles, token)).toEqual({ result: "started" });

    expect(apple.starts).toHaveLength(3);
    const channels = apple.starts.map((request) => (JSON.parse(request.body ?? "") as StartBody).aps["input-push-channel"]);
    expect(channels).toEqual(["channel-1", "channel-1", "channel-2"]);
  });

  it("sends to the development service the token that the production one does not know", async () => {
    const { starts, apple, logLines } = await startHarness();
    apple.answerWith((request, reply) =>
      request.url.startsWith("https://api.push.apple.com/3/device/") ? { status: 400, reason: "BadDeviceToken" } : reply,
    );

    expect(await starts.start(abbesses, token)).toEqual({ result: "started" });

    expect(apple.requests.map((request) => `${request.method} ${new URL(request.url).host}`)).toEqual([
      "POST api-manage-broadcast.push.apple.com:2196",
      "POST api.push.apple.com",
      "POST api-manage-broadcast.sandbox.push.apple.com:2195",
      "POST api.sandbox.push.apple.com",
    ]);
    expect(logLines.at(-1)).toBe(JSON.stringify({ level: "info", event: "live-activity-start", result: "started", environment: "sandbox" }));
  });

  it("answers refused with Apple's reason, tries no other service but for a token it does not know, and keeps nothing", async () => {
    const { starts, apple } = await startHarness();
    apple.answerWith((request, reply) => (request.url.includes("/3/device/") ? { status: 410, reason: "Unregistered" } : reply));

    expect(await starts.start(abbesses, token)).toEqual({ result: "refused", reason: "Unregistered" });
    expect(apple.starts).toHaveLength(1);
    expect(starts.nextWake()).toBeDefined();

    expect(await starts.start(abbesses, token)).toEqual({ result: "refused", reason: "Unregistered" });
    expect(apple.starts).toHaveLength(2);
  });

  it("answers refused when no service knows the token, or when Apple does not answer", async () => {
    const unknown = await startHarness();
    unknown.apple.answerWith((request, reply) => (request.url.includes("/3/device/") ? { status: 400, reason: "BadDeviceToken" } : reply));
    expect(await unknown.starts.start(abbesses, token)).toEqual({ result: "refused", reason: "BadDeviceToken" });

    const silent = await startHarness();
    silent.apple.answerWith(() => "no-answer");
    expect(await silent.starts.start(abbesses, token)).toEqual({ result: "refused", reason: "no-answer" });
    expect(silent.apple.starts).toEqual([]);
  });

  it("answers refused on a fault of the server, logs no token, and starts at the next ask", async () => {
    const { starts, apple, relay, logLines } = await startHarness();
    vi.spyOn(relay.relay, "departures").mockRejectedValueOnce(new Error(`fault with ${token}`));

    expect(await starts.start(abbesses, token)).toEqual({ result: "refused", reason: "server-error" });
    expect(apple.starts).toEqual([]);
    expect(logLines.join("\n")).not.toContain(token);

    expect(await starts.start(abbesses, token)).toEqual({ result: "started" });
    expect(apple.starts).toHaveLength(1);
  });

  it("uses only the service of the key that is set", async () => {
    const { settings } = await testApnsSettings(["sandbox"]);
    const { starts, apple } = await startHarness({ settings });

    expect(await starts.start(abbesses, token)).toEqual({ result: "started" });
    expect(apple.requests.map((request) => new URL(request.url).host)).toEqual([
      "api-manage-broadcast.sandbox.push.apple.com:2195",
      "api.sandbox.push.apple.com",
    ]);
  });

  it("keeps the token nowhere: not in storage, not in memory, not in a log line, which holds no station either", async () => {
    const { starts, relay, logLines } = await startHarness();

    await starts.start(abbesses, token);
    await starts.start(abbesses, token);

    expect(JSON.stringify(everyStoredRow(relay.database))).not.toContain(token);
    expect(stringsHeldBy(starts).filter((text) => text.includes(token))).toEqual([]);
    expect(logLines.length).toBeGreaterThan(0);
    for (const line of logLines) {
      expect(line).not.toContain(token);
      expect(line).not.toContain(abbesses);
      expect(line).not.toContain("Abbesses");
    }
  });

  it("counts each answer by its result in the hour, so that the owner tells a wake that never asked from a start that failed", async () => {
    const { starts, apple, relay } = await startHarness();
    await starts.start(abbesses, token);
    await starts.start(abbesses, token);
    await starts.start("IDFM:not-a-station", token);
    starts.badRequest();
    apple.answerWith((request, reply) => (request.url.includes("/3/device/") ? { status: 429, reason: "TooManyRequests" } : reply));
    await starts.start(chateletLesHalles, token);
    apple.answerWith(() => "no-answer");
    await starts.start(chateletLesHalles, otherToken);
    vi.spyOn(relay.relay, "departures").mockRejectedValueOnce(new Error("fault"));
    await starts.start(abbesses, otherToken);
    const notSetUp = await startHarness({ settings: "none" });
    await notSetUp.starts.start(abbesses, token);

    expect(relay.usage.report().days[0]?.startAnswers).toEqual({
      started: 1,
      "already-started": 1,
      "bad-request": 2,
      "refused:TooManyRequests": 1,
      "refused:no-answer": 1,
      "refused:server-error": 1,
    });
    expect(notSetUp.relay.usage.report().days[0]?.startAnswers).toEqual({ "not-set-up": 1 });
  });

  it("counts a fault before the send as a server error, and still answers it as a fault", async () => {
    const { settings } = await testApnsSettings();
    const { relay } = await startHarness();
    const starts = new LiveActivityStarts({
      settings,
      apns: { start: vi.fn(), createChannel: vi.fn(), deleteChannel: vi.fn(), broadcast: vi.fn() },
      catalog,
      departures: (stopRef) => relay.relay.departures(stopRef),
      clock: relay.clock,
      logger: createLogger([], () => undefined),
      startKey: () => Promise.reject(new Error("no key")),
      counts: relay.usage,
    });

    await expect(starts.start(abbesses, token)).rejects.toThrow("no key");
    expect(relay.usage.report().days[0]?.startAnswers).toEqual({ "refused:server-error": 1 });
  });

  it("still answers started when the storage refuses the count, so that the app brings no notification on top of the Live Activity", async () => {
    const { starts, apple, relay, logLines } = await startHarness();
    vi.spyOn(relay.usage, "countStartAnswer").mockImplementation(() => {
      throw new Error("rows written over the daily limit");
    });

    await expect(starts.start(abbesses, token)).resolves.toEqual({ result: "started" });
    expect(() => {
      starts.badRequest();
    }).not.toThrow();
    expect(apple.starts).toHaveLength(1);
    expect(logLines.filter((line) => line.includes("not-counted"))).toHaveLength(2);
  });

  it("counts with no stop, no token, no hash of it and no time finer than the hour, in storage and in the counts", async () => {
    const { starts, relay } = await startHarness();
    await starts.start(abbesses, token);
    await starts.start(abbesses, token);
    await starts.start(chateletLesHalles, otherToken);
    starts.badRequest();

    const rows = relay.database.all("SELECT * FROM start_answer_hours");
    expect(rows.length).toBeGreaterThan(0);
    for (const row of rows) {
      expect(Object.keys(row).sort()).toEqual(["answer", "count", "hour_start", "paris_day"]);
      expect(Number(row.hour_start) % hour).toBe(0);
      expect(String(row.answer)).toMatch(/^(started|already-started|not-set-up|bad-request|other|refused:[A-Za-z-]{1,40}|refused:status-\d{3})$/);
    }
    const counts = JSON.stringify(relay.relay.counts());
    const metrics = metricsText(relay.relay.metrics());
    for (const text of [JSON.stringify(everyStoredRow(relay.database)), counts, metrics]) {
      for (const held of [token, otherToken, abbesses, chateletLesHalles, "22059", "45102", "Abbesses"]) {
        expect(text).not.toContain(held);
      }
      // A keyed hash of a token is 64 hexadecimal characters: no run of 16 is anywhere.
      expect(text).not.toMatch(/[0-9a-f]{16}/);
    }
  });

  it("has work due through the window, then deletes the channel and forgets all", async () => {
    const { starts, apple, relay } = await startHarness();
    const startedAt = relay.clock.now();
    await starts.start(abbesses, token);

    for (let wake = starts.nextWake(); wake !== undefined; wake = starts.nextWake()) {
      expect(wake).toBeGreaterThan(relay.clock.now());
      relay.clock.advance(wake - relay.clock.now());
      await starts.wake();
    }

    expect(relay.clock.now() - startedAt).toBe(startWindow);
    expect(apple.requests.at(-1)).toMatchObject({
      method: "DELETE",
      url: "https://api-manage-broadcast.push.apple.com:2196/1/apps/com.example.trains/channels",
      headers: { "apns-channel-id": "channel-1" },
    });
    expect(await starts.start(abbesses, token)).toEqual({ result: "started" });
  });

  it.each(["chatelet-les-halles-hub", "magenta-hub", "liege-branches"])("fits the start of %s in the size that Apple allows", async (contractCase) => {
    const { starts, apple } = await startHarness({ contractCase });
    const station = JSON.parse(readFileSync(fileURLToPath(new URL(`../../../../contracts/live-activity/cases/${contractCase}.json`, import.meta.url)), "utf8")) as {
      station: string;
    };

    expect(await starts.start(station.station, token)).toEqual({ result: "started" });

    const body = apple.starts[0]?.body ?? "";
    expect(JSON.parse(body)).toHaveProperty(["aps", "content-state", "trains", "lines", "_0", "soonestTrain"]);
    expect(new TextEncoder().encode(body).length).toBeLessThanOrEqual(4096);
  });
});
