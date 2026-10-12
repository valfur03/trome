import { hasTheShapeThatBuildsRead } from "./build-shape";

interface Delivery {
  Status?: unknown;
  ErrorCondition?: unknown;
  MonitoredStopVisit?: unknown;
}

interface StopMonitoringAnswer {
  Siri?: { ServiceDelivery?: { StopMonitoringDelivery?: unknown } };
}

export interface PrimAnswerReading {
  /** The server gives it to the app as times. */
  isTimes: boolean;
  /** It has the shape that the builds in the field read ([`hasTheShapeThatBuildsRead`](./build-shape.ts)). */
  hasBuildShape: boolean;
}

/** Reads a PRIM answer with a `2xx` status once, for both questions of the server. */
export function readPrimAnswer(body: string): PrimAnswerReading {
  let answer: unknown;
  try {
    answer = JSON.parse(body);
  } catch {
    return { isTimes: false, hasBuildShape: false };
  }
  return { isTimes: isTimes(answer), hasBuildShape: hasTheShapeThatBuildsRead(answer) };
}

export function isTimesAnswer(body: string): boolean {
  return readPrimAnswer(body).isTimes;
}

function isTimes(answer: unknown): boolean {
  const deliveries = (answer as StopMonitoringAnswer | null)?.Siri?.ServiceDelivery?.StopMonitoringDelivery;
  return Array.isArray(deliveries) && deliveries.length > 0 && deliveries.every(isTimesDelivery);
}

function isTimesDelivery(delivery: unknown): boolean {
  if (typeof delivery !== "object" || delivery === null) {
    return false;
  }
  const { Status, ErrorCondition, MonitoredStopVisit } = delivery as Delivery;
  return (
    Status !== "false" &&
    Status !== false &&
    ErrorCondition === undefined &&
    (MonitoredStopVisit === undefined || Array.isArray(MonitoredStopVisit))
  );
}
