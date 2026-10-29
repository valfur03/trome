import { describe, expect, it } from "vitest";
import { reachableEnds } from "../../../src/core/live-activity/line-directions";
import { searchKey, type Station, type TransitLine } from "../../../src/core/live-activity/station-catalog";
import { stationContent } from "../../../src/core/live-activity/station-content";
import type { Departure } from "../../../src/core/live-activity/station-departures";
import { updateWindow } from "../../../src/core/live-activity/station-updates";
import { broadcastSizeLimit, payloadBytes, updatePayload } from "../../../src/core/live-activity/update-payload";
import { second } from "../../../src/core/time/clock";
import { primFixture } from "../relay/prim-fixtures";
import { catalog, contractCase, startHarness } from "./live-activity-harness";

/**
 * An update on a channel must fit Apple's 5,120 bytes, whole body counted, for every station of the list.
 * It holds one page, as the lock screen shows one page at a time: the content of every page of Châtelet is 5,346 bytes.
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

function busiestUpdate(station: Station): { name: string; bytes: number; trains: number } {
  const stations = catalog.hubStations(station);
  const departures = stations.flatMap((part) => part.lines.flatMap((line) => busyDepartures(line, part)));
  const content = stationContent(station, stations, { kind: "departures", departures, answeredAt: now, unansweredStops: new Set() }, catalog, now);
  const page = content.trains.kind === "lines" ? content.trains.page : undefined;
  const trains = page?.lines.flatMap((line) => line.directions.flatMap((direction) => direction.trains)).length ?? 0;
  return { name: station.name, bytes: payloadBytes(updatePayload(content, now, now + updateWindow)), trains };
}

describe("the size of an update on the channel of a station", () => {
  it("fits Apple's limit for the recorded answers of Châtelet - Les Halles, the biggest place of the list", async () => {
    const harness = await startHarness({ contractCase: "chatelet-les-halles-hub" });
    await harness.starts.start(contractCase("chatelet-les-halles-hub").station, token);
    harness.relay.clock.advance((harness.starts.nextWake() ?? 0) - harness.relay.clock.now());
    await harness.starts.wake();

    const body = harness.apple.broadcasts[0]?.body ?? "";
    expect(JSON.parse(body)).toHaveProperty(["aps", "content-state", "trains", "lines", "_0", "lines"]);
    expect(new TextEncoder().encode(body).length).toBeLessThanOrEqual(broadcastSizeLimit);
  });

  it("fits Apple's limit for every station of the list at its busiest, with a fifth of the limit to spare", () => {
    const updates = catalog.stations.map(busiestUpdate);
    const biggest = updates.reduce((largest, update) => (update.bytes > largest.bytes ? update : largest));

    expect(updates.filter((update) => update.trains > 0).length).toBeGreaterThan(catalog.stations.length * 0.9);
    expect(biggest.bytes, biggest.name).toBeLessThanOrEqual(broadcastSizeLimit * 0.8);
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
