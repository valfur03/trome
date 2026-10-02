import { describe, expect, it } from "vitest";
import { retrySpread } from "../../../src/core/relay/retry-spread";
import { hour } from "../../../src/core/time/clock";

const stops = Array.from({ length: 600 }, (_, index) => `STIF:StopArea:SP:${String(index * 7 + 3)}:`);
const elevenInParis = Date.parse("2026-10-02T09:00:00.000Z");

describe("retrySpread", () => {
  it("gives each stop a whole number of seconds from 0 to the spread, the same each time for one retry time", () => {
    const spreads = stops.map((stopRef) => retrySpread(stopRef, elevenInParis, 60_000));

    for (const spread of spreads) {
      expect(spread % 1000).toBe(0);
      expect(spread).toBeGreaterThanOrEqual(0);
      expect(spread).toBeLessThan(60_000);
    }
    expect(new Set(spreads).size).toBe(60);
    expect(stops.map((stopRef) => retrySpread(stopRef, elevenInParis, 60_000))).toEqual(spreads);
  });

  it("changes the order of the stops from one retry time to the next, so that the same stops do not always ask last", () => {
    const lastStops = Array.from({ length: 24 }, (_, index) => {
      const retryFrom = elevenInParis + index * hour;
      const spreads = stops.map((stopRef) => retrySpread(stopRef, retryFrom, 60_000));
      const latest = Math.max(...spreads);
      return new Set(stops.filter((_, stopIndex) => spreads[stopIndex] === latest));
    });
    const alwaysLast = stops.filter((stopRef) => lastStops.every((last) => last.has(stopRef)));

    expect(alwaysLast).toEqual([]);
    expect(new Set(Array.from({ length: 24 }, (_, index) => retrySpread(stops[0] ?? "", elevenInParis + index * hour, 60_000))).size).toBeGreaterThan(10);
  });

  it("gives 0 when the spread is under 1 s", () => {
    expect(stops.map((stopRef) => retrySpread(stopRef, elevenInParis, 999))).toEqual(stops.map(() => 0));
  });
});
