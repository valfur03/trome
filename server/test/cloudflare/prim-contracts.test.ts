import { describe, expect, it } from "vitest";

const answers = import.meta.glob<{ Siri?: { ServiceDelivery?: { StopMonitoringDelivery?: unknown } } }>(
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
});
