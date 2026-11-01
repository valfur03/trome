import { describe, expect, it } from "vitest";

const answers = import.meta.glob<{ Source?: unknown; Siri?: { ServiceDelivery?: { StopMonitoringDelivery?: unknown } } }>(
  "../../../contracts/prim/*.json",
  { eager: true, import: "default" },
);

describe("the recorded PRIM answers of contracts/prim/", () => {
  it("are read by the server tests", () => {
    expect(Object.keys(answers).length).toBeGreaterThanOrEqual(8);
  });

  it("are each a stop monitoring delivery", () => {
    for (const [file, answer] of Object.entries(answers)) {
      expect(Array.isArray(answer.Siri?.ServiceDelivery?.StopMonitoringDelivery), file).toBe(true);
    }
  });

  // A rule of PRIM data proven only on a hand-made answer may fail on real trains, so each answer says if it is real.
  it("each say in a Source field where they come from", () => {
    for (const [file, answer] of Object.entries(answers)) {
      expect(typeof answer.Source === "string" && answer.Source.trim() !== "", file).toBe(true);
    }
  });
});
