interface Delivery {
  Status?: unknown;
  ErrorCondition?: unknown;
  MonitoredStopVisit?: unknown;
}

interface StopMonitoringAnswer {
  Siri?: { ServiceDelivery?: { StopMonitoringDelivery?: unknown } };
}

export function isTimesAnswer(body: string): boolean {
  let answer: unknown;
  try {
    answer = JSON.parse(body);
  } catch {
    return false;
  }
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
