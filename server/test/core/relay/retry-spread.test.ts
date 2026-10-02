import { describe, expect, it } from "vitest";
import { retrySpread } from "../../../src/core/relay/retry-spread";

const stops = Array.from({ length: 600 }, (_, index) => `STIF:StopArea:SP:${String(index * 7 + 3)}:`);

describe("retrySpread", () => {
  it("gives each stop a whole number of seconds from 0 to the spread, the same each time", () => {
    const spreads = stops.map((stopRef) => retrySpread(stopRef, 60_000));

    for (const spread of spreads) {
      expect(spread % 1000).toBe(0);
      expect(spread).toBeGreaterThanOrEqual(0);
      expect(spread).toBeLessThan(60_000);
    }
    expect(new Set(spreads).size).toBe(60);
    expect(stops.map((stopRef) => retrySpread(stopRef, 60_000))).toEqual(spreads);
  });

  it("gives 0 when the spread is under 1 s", () => {
    expect(stops.map((stopRef) => retrySpread(stopRef, 999))).toEqual(stops.map(() => 0));
  });
});
