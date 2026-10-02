import { describe, expect, it } from "vitest";
import { isStopReference } from "../../../src/core/relay/stop-reference";

describe("isStopReference", () => {
  it("accepts a PRIM stop area or quay reference, as the app asks PRIM", () => {
    expect(isStopReference("STIF:StopArea:SP:462374:")).toBe(true);
    expect(isStopReference("STIF:StopPoint:Q:463116:")).toBe(true);
  });

  it("refuses anything else", () => {
    for (const value of ["", "STIF:StopArea:SP:462374", "STIF:StopArea:SP::", "STIF:StopArea:SP:12a:", "IDFM:22059", "STIF:StopArea:SP:1:&apikey=x", "STIF:Line::C01383:", "STIF:StopArea:SP:1234567890123:"]) {
      expect(isStopReference(value), value).toBe(false);
    }
  });
});
