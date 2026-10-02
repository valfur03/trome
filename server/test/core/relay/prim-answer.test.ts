import { describe, expect, it } from "vitest";
import { isTimesAnswer } from "../../../src/core/relay/prim-answer";
import { primFixture, primFixtureNames } from "./prim-fixtures";

describe("isTimesAnswer", () => {
  it("accepts each recorded PRIM answer of contracts/prim/, also the one with no train", () => {
    expect(primFixtureNames().length).toBeGreaterThanOrEqual(8);
    for (const name of primFixtureNames()) {
      expect(isTimesAnswer(primFixture(name)), name).toBe(true);
    }
  });

  it("refuses a PRIM error body or anything that is not a stop monitoring answer", () => {
    const bodies = [
      "",
      "<html>Bad gateway</html>",
      "null",
      "[]",
      '{"message":"Invalid key"}',
      '{"Siri":{}}',
      '{"Siri":{"ServiceDelivery":{}}}',
      '{"Siri":{"ServiceDelivery":{"StopMonitoringDelivery":[]}}}',
      '{"Siri":{"ServiceDelivery":{"StopMonitoringDelivery":[null]}}}',
      '{"Siri":{"ServiceDelivery":{"StopMonitoringDelivery":[{"Status":"false"}]}}}',
      '{"Siri":{"ServiceDelivery":{"StopMonitoringDelivery":[{"Status":false}]}}}',
      '{"Siri":{"ServiceDelivery":{"StopMonitoringDelivery":[{"Status":"true","ErrorCondition":{"ErrorInformation":{"ErrorText":"x"}}}]}}}',
      '{"Siri":{"ServiceDelivery":{"StopMonitoringDelivery":[{"Status":"true","MonitoredStopVisit":{}}]}}}',
    ];
    for (const body of bodies) {
      expect(isTimesAnswer(body), body).toBe(false);
    }
  });
});
