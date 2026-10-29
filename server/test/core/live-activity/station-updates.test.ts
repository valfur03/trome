import { describe, expect, it, vi } from "vitest";
import { contentOfStation } from "../../../src/core/live-activity/content-of-station";
import { startWindow } from "../../../src/core/live-activity/live-activity-starts";
import { encodeContent } from "../../../src/core/live-activity/station-content";
import type { RelayAnswer } from "../../../src/core/relay/relay";
import type { PrimReply } from "../../../src/core/relay/prim-client";
import { minute, second } from "../../../src/core/time/clock";
import type { AppleRequest } from "../push/fake-apple";
import { primFixture } from "../relay/prim-fixtures";
import { catalog, startHarness } from "./live-activity-harness";

/**
 * The updates on the channel of a station whose Live Activity the server started: the minutes move with no app, by the app's own rules.
 * Apple and PRIM are fakes; the clock is a fake that the test moves to each time at which the server object would wake.
 */
const token = "80a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f80a1b2c3d4e5f607";
const otherToken = "11a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f80a1b2c3d4e5f6ff";
const abbesses = "IDFM:22059";
const liege = "IDFM:22225";
const chateletLesHalles = "IDFM:monomodalStopPlace:45102";

type Harness = Awaited<ReturnType<typeof startHarness>>;

interface Aps {
  timestamp: number;
  event: string;
  "content-state": ContentState;
  "stale-date"?: number;
  alert?: unknown;
}

interface ContentState {
  serverIsOut: boolean;
  isMarkedStale: boolean;
  updatedAt: number;
  trains: { noData?: object; lines?: { _0: Page } };
}

interface Page {
  lines: { line: { name: string }; directions: { label: string; trains: { time: number }[]; noAnswer?: boolean }[] }[];
  soonestTrain?: { time: number };
}

interface Sent {
  at: number;
  request: AppleRequest;
  aps: Aps;
}

/** Records the time of each update that the fake Apple gets. */
function recordUpdates(harness: Harness): Sent[] {
  const sent: Sent[] = [];
  harness.apple.answerWith((request, reply) => {
    if (request.url.includes("/4/broadcasts/")) {
      sent.push({ at: harness.relay.clock.now(), request, aps: (JSON.parse(request.body ?? "") as { aps: Aps }).aps });
    }
    return reply;
  });
  return sent;
}

/** Wakes the server as its timer would, until the given time. */
async function wakeUntil(harness: Harness, end: number): Promise<void> {
  const { starts, relay } = harness;
  let wakes = 0;
  for (let wake = starts.nextWake(); wake !== undefined && wake <= end; wake = starts.nextWake()) {
    // A wake that plans no later one would loop for ever on the fake clock, where no timer of the test runner can stop it.
    wakes += 1;
    if (wakes > 10_000) {
      throw new Error("the server wakes again and again at the same time");
    }
    relay.clock.advance(Math.max(0, wake - relay.clock.now()));
    await starts.wake();
  }
  relay.clock.advance(Math.max(0, end - relay.clock.now()));
}

const swiftSeconds = (milliseconds: number) => milliseconds / 1000 - 978_307_200;

/** PRIM answers the stop of Liège with the recording made last before the time of the call, and the test keeps each call. */
function liegeOverTime(harness: Harness): { at: number; name: string }[] {
  const recordings = [
    { from: Date.parse("2026-10-02T15:00:43Z"), name: "stop-monitoring-liege-170043.json" },
    { from: Date.parse("2026-10-02T15:05:58Z"), name: "stop-monitoring-liege-170558.json" },
    { from: Date.parse("2026-10-02T15:10:32Z"), name: "stop-monitoring-liege-171032.json" },
  ];
  const calls: { at: number; name: string }[] = [];
  harness.relay.clock.set("2026-10-02T15:01:00Z");
  harness.relay.prim.answerWith(() => {
    const now = harness.relay.clock.now();
    const name = recordings.filter((recording) => recording.from <= now).at(-1)?.name ?? "stop-monitoring-liege-170043.json";
    calls.push({ at: now, name });
    return { kind: "answer", status: 200, body: primFixture(name) };
  });
  return calls;
}

function page(sent: Sent | undefined): Page {
  const lines = sent?.aps["content-state"].trains.lines;
  if (lines === undefined) {
    throw new Error("no page in the update");
  }
  return lines._0;
}

describe("the updates of a Live Activity that the server started", () => {
  it("sends the minutes that the app would show on the channel of the station, as fresh as the departures route gives them, with no alert", async () => {
    const harness = await startHarness();
    const calls = liegeOverTime(harness);
    const sent = recordUpdates(harness);
    expect(await harness.starts.start(liege, token)).toEqual({ result: "started" });

    await wakeUntil(harness, Date.parse("2026-10-02T15:16:00Z"));

    expect(sent.length).toBeGreaterThan(7);
    const station = catalog.station(liege);
    if (station === undefined) {
      throw new Error("no Liège");
    }
    for (const update of sent) {
      expect(update.request).toMatchObject({
        method: "POST",
        url: "https://api.push.apple.com/4/broadcasts/apps/com.example.trains",
        headers: { "apns-channel-id": "channel-1", "apns-push-type": "liveactivity", "apns-priority": "5", "apns-expiration": "0" },
      });
      expect(update.aps.event).toBe("update");
      expect(update.aps.alert).toBeUndefined();
      expect(update.aps.timestamp).toBe(Math.floor(update.at / 1000));
      // The content that the app builds from the answer that the relay held at that time.
      const call = calls.filter(({ at }) => at <= update.at).at(-1);
      if (call === undefined) {
        throw new Error("no PRIM call before the update");
      }
      const held: RelayAnswer = { kind: "times", body: primFixture(call.name), primAnsweredAt: call.at };
      const content = await contentOfStation(station, catalog, () => Promise.resolve(held), () => update.at);
      expect(update.aps["content-state"]).toEqual(encodeContent(content));
      expect(update.at - call.at).toBeLessThan(minute);
    }
    // Each of the three recordings reached the lock screen.
    const shown = new Set(sent.map((update) => calls.filter(({ at }) => at <= update.at).at(-1)?.name));
    expect(shown.size).toBe(3);
  });

  it("asks as the app in the background: 5 s after the first train of the content leaves, at least 30 s and at most 2 minutes after the last ask", async () => {
    const harness = await startHarness();
    liegeOverTime(harness);
    const sent = recordUpdates(harness);
    const startedAt = harness.relay.clock.now();
    await harness.starts.start(liege, token);
    const startStale = (JSON.parse(harness.apple.starts[0]?.body ?? "") as { aps: { "stale-date": number } }).aps["stale-date"] * 1000;

    await wakeUntil(harness, Date.parse("2026-10-02T15:16:00Z"));

    const expectedAfter = (at: number, stale: number | undefined) =>
      stale === undefined ? at + 2 * minute : Math.min(Math.max(stale + 5 * second, at + 30 * second), at + 2 * minute);
    let last = { at: startedAt, stale: startStale as number | undefined };
    for (const update of sent) {
      // The stale date of a payload holds whole seconds.
      expect(Math.abs(update.at - expectedAfter(last.at, last.stale))).toBeLessThan(second);
      const stale = update.aps["stale-date"];
      last = { at: update.at, stale: stale === undefined ? undefined : stale * 1000 };
    }
    expect(new Set(sent.map((update, index) => update.at - (sent[index - 1]?.at ?? startedAt))).size).toBeGreaterThan(1);
  });

  it("asks PRIM at most once a minute for a stop, as the departures route does", async () => {
    const harness = await startHarness();
    const calls = liegeOverTime(harness);
    await harness.starts.start(liege, token);

    await wakeUntil(harness, harness.relay.clock.now() + startWindow);

    for (let index = 1; index < calls.length; index += 1) {
      expect((calls[index]?.at ?? 0) - (calls[index - 1]?.at ?? 0)).toBeGreaterThanOrEqual(minute);
    }
  });

  it("sends updates for 45 minutes after the last start at the station only, then deletes its channel and asks PRIM no more", async () => {
    const harness = await startHarness();
    const sent = recordUpdates(harness);
    const first = harness.relay.clock.now();
    await harness.starts.start(abbesses, token);
    await wakeUntil(harness, first + 20 * minute);
    expect(await harness.starts.start(abbesses, otherToken)).toEqual({ result: "started" });
    const last = harness.relay.clock.now();

    await wakeUntil(harness, last + startWindow - second);
    expect(sent.at(-1)?.at).toBeGreaterThan(last + startWindow - 2 * minute - second);
    const primCalls = harness.relay.prim.calls.length;
    const updates = sent.length;

    await wakeUntil(harness, last + 3 * startWindow);
    expect(sent).toHaveLength(updates);
    expect(harness.relay.prim.calls).toHaveLength(primCalls);
    expect(harness.apple.requests.at(-1)).toMatchObject({ method: "DELETE", headers: { "apns-channel-id": "channel-1" } });
    expect(harness.starts.nextWake()).toBeUndefined();
  });

  it("sends no update for a station whose start Apple refused", async () => {
    const harness = await startHarness();
    harness.apple.answerWith((request, reply) => (request.url.includes("/3/device/") ? { status: 410, reason: "Unregistered" } : reply));
    await harness.starts.start(abbesses, token);
    const primCalls = harness.relay.prim.calls.length;

    await wakeUntil(harness, harness.relay.clock.now() + startWindow + minute);

    expect(harness.apple.broadcasts).toEqual([]);
    expect(harness.relay.prim.calls).toHaveLength(primCalls);
  });

  it("logs the result of each update with its service, and never the station or the token", async () => {
    const harness = await startHarness();
    await harness.starts.start(abbesses, token);
    await wakeUntil(harness, harness.relay.clock.now() + 5 * minute);

    const updates = harness.logLines.filter((line) => line.includes("live-activity-update"));
    expect(updates.length).toBeGreaterThan(1);
    expect(new Set(updates)).toEqual(new Set([JSON.stringify({ level: "info", event: "live-activity-update", result: "sent", environment: "production" })]));
    for (const line of harness.logLines) {
      expect(line).not.toContain(token);
      expect(line).not.toContain(abbesses);
      expect(line).not.toContain("Abbesses");
    }
  });
});

describe("the updates when a stop has no train or does not answer, as the lock screen shows it today", () => {
  const failure: PrimReply = { kind: "unreachable", reason: "test" };

  it("keeps the times shown when PRIM fails, then marks them stale once their first train has left, never empty", async () => {
    const harness = await startHarness();
    const sent = recordUpdates(harness);
    await harness.starts.start(abbesses, token);
    const start = (JSON.parse(harness.apple.starts[0]?.body ?? "") as { aps: Aps }).aps;
    harness.relay.prim.answerWith(() => failure);

    // The relay gives its held answer for 5 minutes, as to an app; then the stop is out.
    await wakeUntil(harness, harness.relay.clock.now() + 30 * minute);

    const kept = sent.filter((update) => update.aps["content-state"].isMarkedStale);
    expect(kept).toHaveLength(1);
    const marked = kept[0];
    if (marked === undefined) {
      throw new Error("no times marked stale");
    }
    const before = sent[sent.indexOf(marked) - 1]?.aps ?? start;
    expect(marked.aps["content-state"]).toEqual({ ...before["content-state"], isMarkedStale: true });
    expect(marked.at).toBeGreaterThanOrEqual((before["stale-date"] ?? 0) * 1000);
    expect(marked.at).toBeLessThan((before["stale-date"] ?? 0) * 1000 + second);
    expect(sent.at(-1)).toBe(marked);
    for (const update of sent) {
      expect(update.aps["content-state"].trains.noData).toBeUndefined();
    }
  });

  it("says that the server is out when its budget is used up, and keeps the times until their first train has left", async () => {
    const harness = await startHarness();
    const sent = recordUpdates(harness);
    await harness.starts.start(abbesses, token);
    harness.relay.clock.advance(minute);
    harness.relay.prim.answerWith(() => ({ kind: "answer", status: 429, body: "" }));
    const callsBefore = harness.relay.prim.calls.length;
    const asks: number[] = [];
    const departures = harness.relay.relay.departures.bind(harness.relay.relay);
    vi.spyOn(harness.relay.relay, "departures").mockImplementation((stopRef) => {
      asks.push(harness.relay.clock.now());
      return departures(stopRef);
    });

    await wakeUntil(harness, harness.relay.clock.now() + 30 * minute);

    const out = sent.filter((update) => update.aps["content-state"].serverIsOut);
    expect(out.length).toBeGreaterThanOrEqual(1);
    expect(out[0]?.aps["content-state"].isMarkedStale).toBe(false);
    expect(page(out[0]).soonestTrain).toBeDefined();
    expect(out.at(-1)?.aps["content-state"].isMarkedStale).toBe(true);
    // After the 429, the relay asks PRIM again only after its pause of an hour.
    expect(harness.relay.prim.calls.length - callsBefore).toBe(1);
    // As the app, the server asks the relay again only at the time when it asks PRIM again, an hour after the 429.
    expect(asks.filter((at) => at > (out.at(-1)?.at ?? 0))).toEqual([]);
  });

  it("shows Times unavailable when PRIM fails after No trains, which never gets old", async () => {
    const harness = await startHarness({ contractCase: "abbesses-no-train" });
    const sent = recordUpdates(harness);
    await harness.starts.start(abbesses, token);
    const start = (JSON.parse(harness.apple.starts[0]?.body ?? "") as { aps: Aps }).aps;
    expect(start["content-state"].trains.lines?._0.lines[0]?.directions).toEqual([]);
    harness.relay.prim.answerWith(() => failure);

    await wakeUntil(harness, harness.relay.clock.now() + 10 * minute);

    const last = sent.at(-1)?.aps["content-state"];
    expect(last?.trains).toEqual({ noData: {} });
    expect(last?.serverIsOut).toBe(false);
  });

  it("keeps the trains of a stop that does not answer while another stop of the place does, then shows an empty box, never No trains", async () => {
    const harness = await startHarness();
    harness.relay.clock.set("2026-10-01T19:48:10Z");
    // The stop of metro 4 answers with trains, so that the place has times while its RER stop is out: the RER A recording, read as metro 4.
    const metroTrains = primFixture("stop-monitoring-chatelet-rer-a-2148.json").replaceAll("C01742", "C01374");
    let rerFails = false;
    harness.relay.prim.answerWith((stopRef) => {
      if (stopRef === "STIF:StopArea:SP:45102:") {
        return rerFails ? failure : { kind: "answer", status: 200, body: primFixture("stop-monitoring-chatelet-rer-a-2148.json") };
      }
      return { kind: "answer", status: 200, body: stopRef === "STIF:StopArea:SP:417675:" ? metroTrains : primFixture("stop-monitoring-empty.json") };
    });
    const sent = recordUpdates(harness);
    await harness.starts.start(chateletLesHalles, token);
    const startPage = (JSON.parse(harness.apple.starts[0]?.body ?? "") as { aps: Aps }).aps["content-state"].trains.lines?._0;
    expect(startPage?.lines[0]?.line.name).toBe("A");
    expect(startPage?.lines[0]?.directions.some((direction) => direction.trains.length > 0)).toBe(true);
    // The RER A trains of the recording, which the RER stop gave before it stopped answering.
    const recordedTimes = new Set(["19:48:30", "19:54:30", "19:56:30", "20:00:30"].map((time) => swiftSeconds(Date.parse(`2026-10-01T${time}Z`))));
    rerFails = true;

    await wakeUntil(harness, Date.parse("2026-10-01T20:10:00Z"));

    const afterTheHeldAnswer = sent.filter((update) => update.at > Date.parse("2026-10-01T19:53:10Z"));
    expect(afterTheHeldAnswer.some((update) => page(update).lines[0]?.directions.some((direction) => direction.trains.length > 0))).toBe(true);
    for (const update of afterTheHeldAnswer) {
      const directions = page(update).lines[0]?.directions ?? [];
      expect(directions.length).toBeGreaterThan(0);
      for (const direction of directions) {
        for (const train of direction.trains) {
          expect(recordedTimes).toContain(train.time);
          expect(train.time).toBeGreaterThan(swiftSeconds(update.at));
        }
        expect(direction.trains.length > 0 || direction.noAnswer === true).toBe(true);
      }
    }
    expect(page(sent.at(-1)).lines[0]?.directions.every((direction) => direction.noAnswer === true)).toBe(true);
  });
});
