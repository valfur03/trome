import { readFileSync } from "node:fs";
import ts from "typescript";
import { describe, expect, it } from "vitest";
import { relaySettings } from "../../../src/core/config/relay-settings";

interface WranglerVars {
  vars?: { PRIM_DAILY_CAP?: string };
  env?: { staging?: { vars?: { PRIM_DAILY_CAP?: string } } };
}

function wranglerConfig(): WranglerVars {
  const path = new URL("../../../wrangler.jsonc", import.meta.url).pathname;
  return ts.parseConfigFileTextToJson(path, readFileSync(path, "utf8")).config as WranglerVars;
}

describe("relaySettings", () => {
  it("reads the daily cap, and gives the day shape, the ages and pauses of the relay", () => {
    const shape = relaySettings({ PRIM_DAILY_CAP: "800" }).dayShape;
    expect(shape.map((share) => Math.round(share * 10_000) / 100)).toEqual([
      0.6, 0.5, 0.5, 0.5, 0.5, 1.7, 4.3, 9.2, 10.2, 6.1, 4.6, 4.6, 5.1, 4.9, 4.9, 5.5, 7, 8.5, 7.5, 5.1, 3.2, 2.1, 1.7, 1.2,
    ]);
    expect(relaySettings({ PRIM_DAILY_CAP: "800" })).toEqual({
      dailyCap: 800,
      dayShape: shape,
      freshAge: 60_000,
      agedAnswers: [
        { spentOver: 0.7, age: 120_000 },
        { spentOver: 0.9, age: 300_000 },
      ],
      startAge: 600_000,
      startReserve: 0.05,
      heldAge: 300_000,
      pauseAfterLimit: 3_600_000,
      pauseAfterFailure: 60_000,
      retrySpread: 60_000,
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

  it("accepts a cap from 1 to 990, and refuses a cap that the calls from 00:00 to 02:00 of the next Paris day could take above the PRIM quota of a day that starts at 00:00 UTC", () => {
    expect(relaySettings({ PRIM_DAILY_CAP: "1" }).dailyCap).toBe(1);
    expect(relaySettings({ PRIM_DAILY_CAP: "990" }).dailyCap).toBe(990);
    expect(() => relaySettings({ PRIM_DAILY_CAP: "991" })).toThrow(
      "PRIM_DAILY_CAP 991 and the 10 calls from 00:00 to 02:00 of the next Paris day could make 1001 calls in a PRIM day that starts at 00:00 UTC: give a cap of 990 or less.",
    );
    expect(() => relaySettings({ PRIM_DAILY_CAP: "1000" })).toThrow("give a cap of 990 or less");
  });

  it("accepts the caps of wrangler.jsonc, for production and for staging, so that a deploy cannot give the Worker a cap that it refuses", () => {
    const config = wranglerConfig();

    expect(() => relaySettings(config.vars ?? {})).not.toThrow();
    expect(() => relaySettings(config.env?.staging?.vars ?? {})).not.toThrow();
  });
});
