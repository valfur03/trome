import { describe, expect, it } from "vitest";
import { reachableEnds } from "../../../src/core/live-activity/line-directions";
import { searchKey, type Station, type TransitLine } from "../../../src/core/live-activity/station-catalog";
import { stationContent, type StationContent } from "../../../src/core/live-activity/station-content";
import type { Departure } from "../../../src/core/live-activity/station-departures";
import { updateWindow } from "../../../src/core/live-activity/station-updates";
import { startPayload, startSizeLimit } from "../../../src/core/live-activity/start-payload";
import { broadcastSizeLimit, contentSizeLimit, payloadBytes, updatePayload } from "../../../src/core/live-activity/update-payload";
import { second } from "../../../src/core/time/clock";
import { primFixture } from "../relay/prim-fixtures";
import { catalog, contractCase, startHarness } from "./live-activity-harness";

/**
 * An update on a channel must fit Apple's 5,120 bytes, whole body counted, for every station of the list, and its content Apple's 4 KB for the content of a Live Activity.
 * It shows the first page and carries the other pages that fit, in the order of the app, so that each lock screen draws the page that its rider tapped to.
 */
const token = "80a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f80a1b2c3d4e5f607";
const now = Date.parse("2026-10-02T07:00:00Z");

/** A busy line, as the app's size test makes it (`StationActivityContentTests+ForkPages`): 8 trains on each side, to every end that the station reaches, the first two at the platform. */
function busyDepartures(line: TransitLine, station: Station): Departure[] {
  const ends = catalog.ends(line);
  if (ends === undefined) {
    return [];
  }
  const stationKey = searchKey(station.name);
  return [ends.first, ends.second].flatMap((side, sideIndex) => {
    if (side.some((end) => searchKey(end) === stationKey)) {
      return [];
    }
    const destinations = reachableEnds(ends, side, station.name);
    return Array.from({ length: 8 }, (_, index) => {
      const time = now + (30 + sideIndex * 20 + index * 150) * second;
      return { line, destination: destinations[index % destinations.length] ?? "", time, arrivalTime: time - 25 * second, isAtStop: index < 2 };
    });
  });
}

function busiestContent(station: Station): StationContent {
  const stations = catalog.hubStations(station);
  const departures = stations.flatMap((part) => part.lines.flatMap((line) => busyDepartures(line, part)));
  return stationContent(station, stations, { kind: "departures", departures, answeredAt: now, unansweredStops: new Set() }, catalog, now);
}

function firstPageOnly(content: StationContent): StationContent {
  if (content.trains.kind !== "lines") {
    return content;
  }
  const page = { ...content.trains.page };
  delete page.pages;
  return { ...content, trains: { kind: "lines", page } };
}

function busiestUpdate(station: Station): { name: string; bytes: number; firstPageBytes: number; trains: number } {
  const content = busiestContent(station);
  const page = content.trains.kind === "lines" ? content.trains.page : undefined;
  const trains = page?.lines.flatMap((line) => line.directions.flatMap((direction) => direction.trains)).length ?? 0;
  return {
    name: station.name,
    bytes: payloadBytes(updatePayload(content, now, now + updateWindow)),
    firstPageBytes: payloadBytes(updatePayload(firstPageOnly(content), now, now + updateWindow)),
    trains,
  };
}

interface SentPage {
  lines: { line: { mode: string; name: string } }[];
  allLines: { mode: string; name: string }[];
  firstIndex: number;
  pages?: { line: { mode: string; name: string } }[];
}

function sentPage(payload: string): SentPage {
  return (JSON.parse(payload) as { aps: { "content-state": { trains: { lines: { _0: SentPage } } } } }).aps["content-state"].trains.lines._0;
}

/**
 * The bytes of the content that an iPhone gets from the push, on the biggest page that it carries: each lock screen draws its rider's page from it, and the app sends it again on the tapped page.
 * Apple refuses a content over 4 KB, whatever the push, and the lock screen then keeps its old minutes.
 */
function widestSentContentBytes(payload: string): number {
  const content = (JSON.parse(payload) as { aps: { "content-state": { trains: { lines?: { _0: SentPage } } } } }).aps["content-state"];
  const page = content.trains.lines?._0;
  const shown = (page?.pages ?? []).map((line, index) => ({ ...content, trains: { lines: { _0: { ...page, lines: [line], firstIndex: index } } } }));
  return Math.max(...[content, ...shown].map((each) => payloadBytes(JSON.stringify(each))));
}

describe("the size of an update on the channel of a station", () => {
  it("fits Apple's limit for the recorded answers of Châtelet - Les Halles, the biggest place of the list", async () => {
    const harness = await startHarness({ contractCase: "chatelet-les-halles-hub" });
    await harness.starts.start(contractCase("chatelet-les-halles-hub").station, token);
    harness.relay.clock.advance((harness.starts.nextWake() ?? 0) - harness.relay.clock.now());
    await harness.starts.wake();

    const body = harness.apple.broadcasts[0]?.body ?? "";
    const page = sentPage(body);
    expect(page.firstIndex).toBe(0);
    expect(page.allLines).toHaveLength(8);
    expect(page.pages?.map((carried) => carried.line)).toEqual(page.allLines.slice(0, 5));
    expect(page.pages?.[0]).toEqual(page.lines[0]);
    expect(new TextEncoder().encode(body).length).toBeLessThanOrEqual(broadcastSizeLimit);
    expect(widestSentContentBytes(body)).toBeLessThanOrEqual(contentSizeLimit);
  });

  it("fits Apple's limit for every station of the list at its busiest, and its first page alone keeps a fifth of the limit to spare", () => {
    const updates = catalog.stations.map(busiestUpdate);
    const biggest = updates.reduce((largest, update) => (update.bytes > largest.bytes ? update : largest));
    const biggestFirstPage = updates.reduce((largest, update) => (update.firstPageBytes > largest.firstPageBytes ? update : largest));

    expect(updates.filter((update) => update.trains > 0).length).toBeGreaterThan(catalog.stations.length * 0.9);
    expect(biggest.bytes, biggest.name).toBeLessThanOrEqual(broadcastSizeLimit);
    expect(biggestFirstPage.firstPageBytes, biggestFirstPage.name).toBeLessThanOrEqual(broadcastSizeLimit * 0.8);
  });

  it("carries every page of most stations with several lines at their busiest, and the first pages that fit at the others", () => {
    const several = catalog.stations.map(busiestContent).filter((content) => content.trains.kind === "lines" && content.trains.page.allLines.length > 1);
    const payloads = several.map((content) => updatePayload(content, now, now + updateWindow));
    const carried = payloads.map(sentPage);

    for (const page of carried) {
      const pages = page.pages ?? [];
      expect(pages).not.toHaveLength(1);
      expect(pages.map((carriedPage) => carriedPage.line)).toEqual(page.allLines.slice(0, pages.length));
    }
    for (const [index, payload] of payloads.entries()) {
      expect(widestSentContentBytes(payload), several[index]?.stationName).toBeLessThanOrEqual(contentSizeLimit);
    }
    expect(carried.filter((page) => page.pages?.length === page.allLines.length).length).toBeGreaterThan(several.length * 0.5);
  });

  it("leaves out only the pages that would go over the limit", () => {
    const saintLazare = catalog.stations.find((station) => station.name === "Saint-Lazare");
    if (saintLazare === undefined) {
      throw new Error("no Saint-Lazare");
    }
    const content = busiestContent(saintLazare);
    const sent = sentPage(updatePayload(content, now, now + updateWindow));
    const carried = sent.pages?.length ?? 0;
    expect(carried).toBeLessThan(sent.allLines.length);
    if (content.trains.kind !== "lines" || content.trains.page.pages === undefined) {
      throw new Error("no pages");
    }
    const oneMore = { ...content, trains: { kind: "lines" as const, page: { ...content.trains.page, pages: content.trains.page.pages.slice(0, carried + 1) } } };
    const withOneMore = updatePayload(oneMore, now, now + updateWindow);
    expect(sentPage(withOneMore).pages?.length).toBe(carried);
  });

  it("starts a Live Activity with the pages that fit Apple's limit for a push to one iPhone", () => {
    const sizes = catalog.stations.map((station) => {
      const payload = startPayload(station, busiestContent(station), "channel-1", now, now + updateWindow);
      const page = sentPage(payload);
      return {
        name: station.name,
        bytes: payloadBytes(payload),
        contentBytes: widestSentContentBytes(payload),
        pages: page.pages?.map((carried) => carried.line) ?? [],
        allLines: page.allLines,
      };
    });
    const biggest = sizes.reduce((largest, size) => (size.bytes > largest.bytes ? size : largest));
    const biggestContent = sizes.reduce((largest, size) => (size.contentBytes > largest.contentBytes ? size : largest));

    expect(biggest.bytes, biggest.name).toBeLessThanOrEqual(startSizeLimit);
    expect(biggestContent.contentBytes, biggestContent.name).toBeLessThanOrEqual(contentSizeLimit);
    for (const size of sizes) {
      expect(size.pages).toEqual(size.allLines.slice(0, size.pages.length));
      expect(size.pages).not.toHaveLength(1);
    }
  });

  it("sends no update over the limit, and says so in a log line with no station", async () => {
    const harness = await startHarness();
    await harness.starts.start("IDFM:22059", token);
    const longName = "Gare ".repeat(1000);
    harness.relay.prim.answerWith(() => ({
      kind: "answer",
      status: 200,
      body: primFixture("stop-monitoring-abbesses-stop-area.json").replaceAll(`"Mairie d'Issy"`, JSON.stringify(longName)),
    }));
    harness.relay.clock.advance((harness.starts.nextWake() ?? 0) - harness.relay.clock.now());
    await harness.starts.wake();

    expect(harness.apple.broadcasts).toEqual([]);
    const line = JSON.parse(harness.logLines.at(-1) ?? "{}") as { level: string; event: string; result: string; bytes: number };
    expect(line).toMatchObject({ level: "error", event: "live-activity-update", result: "too-large" });
    expect(line.bytes).toBeGreaterThan(broadcastSizeLimit);
    expect(harness.starts.nextWake()).toBeGreaterThan(harness.relay.clock.now());
  });
});
