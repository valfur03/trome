import { describe, expect, it } from "vitest";
import { hasTheShapeThatBuildsRead } from "../../../src/core/relay/build-shape";
import { everyRecordedPrimAnswer, primFixture } from "./prim-fixtures";

interface Answer {
  Siri: { ServiceDelivery: { StopMonitoringDelivery: { MonitoredStopVisit: Visit[] }[] } };
}

interface Visit {
  MonitoredVehicleJourney: Record<string, unknown> & { MonitoredCall?: Record<string, unknown> };
}

function recordedAnswer(): Answer {
  return JSON.parse(primFixture("stop-monitoring-abbesses-stop-area.json")) as Answer;
}

/** The recorded answer, with each visit changed as PRIM could change its format. */
function withEveryVisit(change: (visit: Visit) => void): Answer {
  const answer = recordedAnswer();
  for (const visit of answer.Siri.ServiceDelivery.StopMonitoringDelivery[0]?.MonitoredStopVisit ?? []) {
    change(visit);
  }
  return answer;
}

describe("hasTheShapeThatBuildsRead", () => {
  it("accepts every recorded PRIM answer, with no train, and with one visit that has no time", () => {
    for (const { name, body } of everyRecordedPrimAnswer()) {
      expect(hasTheShapeThatBuildsRead(JSON.parse(body)), name).toBe(true);
    }
  });

  it("accepts a PRIM error for a stop, which the builds read as no train", () => {
    const error = { Siri: { ServiceDelivery: { StopMonitoringDelivery: [{ Status: "false", ErrorCondition: { ErrorInformation: { ErrorText: "x" } } }] } } };

    expect(hasTheShapeThatBuildsRead(error)).toBe(true);
  });

  it("refuses an answer with no service delivery", () => {
    for (const answer of [null, [], { message: "Invalid key" }, { Siri: {} }, { Siri: { ServiceDelivery: [] } }]) {
      expect(hasTheShapeThatBuildsRead(answer), JSON.stringify(answer)).toBe(false);
    }
  });

  it("refuses an answer whose list of deliveries or of visits is missing, as the builds then show no train at every stop", () => {
    const recorded = primFixture("stop-monitoring-abbesses.json");
    const changes = {
      "renamed visits": recorded.replaceAll('"MonitoredStopVisit"', '"MonitoredStopVisits"'),
      "renamed deliveries": recorded.replaceAll('"StopMonitoringDelivery"', '"StopMonitoringDeliveries"'),
      "no delivery": '{"Siri":{"ServiceDelivery":{"StopMonitoringDelivery":[]}}}',
    };
    for (const [name, body] of Object.entries(changes)) {
      expect(hasTheShapeThatBuildsRead(JSON.parse(body)), name).toBe(false);
    }
  });

  it("refuses an answer whose visits all lack the line, the time or the destination", () => {
    const changes: Record<string, (visit: Visit) => void> = {
      "renamed line": (visit) => {
        visit.MonitoredVehicleJourney.LineReference = visit.MonitoredVehicleJourney.LineRef;
        delete visit.MonitoredVehicleJourney.LineRef;
      },
      "no time": (visit) => {
        for (const field of ["ExpectedDepartureTime", "ExpectedArrivalTime", "AimedDepartureTime", "AimedArrivalTime"]) {
          delete visit.MonitoredVehicleJourney.MonitoredCall?.[field];
        }
      },
      "time in another form": (visit) => {
        visit.MonitoredVehicleJourney.MonitoredCall = { ExpectedDepartureTime: "1759395600", DestinationDisplay: [{ value: "Mairie d'Issy" }] };
      },
      "no destination": (visit) => {
        delete visit.MonitoredVehicleJourney.DestinationName;
        delete visit.MonitoredVehicleJourney.MonitoredCall?.DestinationDisplay;
      },
      "no call": (visit) => {
        delete visit.MonitoredVehicleJourney.MonitoredCall;
      },
    };
    for (const [name, change] of Object.entries(changes)) {
      expect(hasTheShapeThatBuildsRead(withEveryVisit(change)), name).toBe(false);
    }
  });

  it("refuses an answer where a field that the builds read has another type, as the builds then fail on the whole answer", () => {
    const changes: Record<string, (visit: Visit) => void> = {
      "line as a text": (visit) => {
        visit.MonitoredVehicleJourney.LineRef = "STIF:Line::C01382:";
      },
      "destination as a text": (visit) => {
        visit.MonitoredVehicleJourney.DestinationName = "Mairie d'Issy";
      },
      "at stop as a text": (visit) => {
        visit.MonitoredVehicleJourney.MonitoredCall = { ...visit.MonitoredVehicleJourney.MonitoredCall, VehicleAtStop: "true" };
      },
      "time as a number": (visit) => {
        visit.MonitoredVehicleJourney.MonitoredCall = { ...visit.MonitoredVehicleJourney.MonitoredCall, AimedArrivalTime: 1759395600 };
      },
    };
    for (const [name, change] of Object.entries(changes)) {
      expect(hasTheShapeThatBuildsRead(withEveryVisit(change)), name).toBe(false);
    }
    const visitsAsAnObject = recordedAnswer() as unknown as { Siri: { ServiceDelivery: { StopMonitoringDelivery: unknown[] } } };
    visitsAsAnObject.Siri.ServiceDelivery.StopMonitoringDelivery = [{ MonitoredStopVisit: {} }];
    expect(hasTheShapeThatBuildsRead(visitsAsAnObject)).toBe(false);
  });

  it("accepts an answer where only some visits lack a field, as PRIM data often does", () => {
    const answer = recordedAnswer();
    const [first] = answer.Siri.ServiceDelivery.StopMonitoringDelivery[0]?.MonitoredStopVisit ?? [];
    delete first?.MonitoredVehicleJourney.LineRef;

    expect(hasTheShapeThatBuildsRead(answer)).toBe(true);
  });
});
