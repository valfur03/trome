import { describe, expect, it } from "vitest";
import { relaySettings } from "../../../src/core/config/relay-settings";

describe("relaySettings", () => {
  it("reads the daily cap, and gives the ages and pauses of the relay", () => {
    expect(relaySettings({ PRIM_DAILY_CAP: "800" })).toEqual({
      dailyCap: 800,
      freshAge: 60_000,
      heldAge: 300_000,
      pauseAfterLimit: 3_600_000,
      pauseAfterFailure: 60_000,
      primTimeout: 10_000,
    });
  });

  it("refuses a cap that is missing, not a whole number, 0, or above the PRIM quota of 1,000", () => {
    for (const value of [undefined, "", "abc", "0", "-1", "800.5", "8e2", " 800", "1001"]) {
      expect(() => relaySettings(value === undefined ? {} : { PRIM_DAILY_CAP: value }), String(value)).toThrow(
        "PRIM_DAILY_CAP must be a whole number from 1 to 1000",
      );
    }
  });

  it("accepts a cap from 1 to 1,000", () => {
    expect(relaySettings({ PRIM_DAILY_CAP: "1" }).dailyCap).toBe(1);
    expect(relaySettings({ PRIM_DAILY_CAP: "1000" }).dailyCap).toBe(1000);
  });
});
