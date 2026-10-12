/**
 * Whether a PRIM answer has the shape that the builds in the field read, so that a change of PRIM's own format is seen in the totals.
 * The server passes the answer as PRIM gave it, and each build parses it itself (`StopMonitoringResponse` of the app, the same in every build up to 1.0.0 (2)).
 * Such a build fails on the whole answer when a field that it reads has another type, and it drops each visit with no line, time or destination:
 * so an answer lacks the shape when it has no service delivery, when a field that the build reads has the wrong type, or when it has visits and none of them gives a line, a time and a destination.
 * A build reads a missing list of deliveries or of visits as no train, so a renamed list would show no train at every stop: PRIM always sends both lists, empty when no train comes, so a missing one counts.
 * Only a delivery that PRIM marks as an error for the stop (`Status` false, or an `ErrorCondition`) may come with no list of visits.
 * One visit with no time is normal PRIM data (a recorded answer has one), so it does not count.
 * When a new build reads a new field, this check grows; it never drops what an older build in the field reads.
 */
export function hasTheShapeThatBuildsRead(answer: unknown): boolean {
  if (!isObject(answer) || !isObject(answer.Siri) || !isObject(answer.Siri.ServiceDelivery)) {
    return false;
  }
  const deliveries = answer.Siri.ServiceDelivery.StopMonitoringDelivery;
  if (!isArrayOf(deliveries, isDelivery) || deliveries.length === 0 || !deliveries.every(hasItsVisitList)) {
    return false;
  }
  const visits = deliveries.flatMap((delivery) => (delivery.MonitoredStopVisit ?? []) as Visit[]);
  if (!visits.every(hasTheTypesThatBuildsRead)) {
    return false;
  }
  return visits.length === 0 || visits.some(isReadable);
}

type Fields = Record<string, unknown>;

interface Delivery extends Fields {
  MonitoredStopVisit?: unknown[] | null;
}

interface Visit extends Fields {
  MonitoredVehicleJourney?: Journey | null;
}

interface Journey extends Fields {
  LineRef?: Value | null;
  DestinationName?: Value[] | null;
  MonitoredCall?: Call | null;
}

interface Call extends Fields {
  DestinationDisplay?: Value[] | null;
}

interface Value extends Fields {
  value?: string | null;
}

const timeFields = ["ExpectedDepartureTime", "ExpectedArrivalTime", "AimedDepartureTime", "AimedArrivalTime"] as const;

/** The ISO 8601 forms that the builds parse: with or without fractions of a second, and always with a time zone. */
const timeForm = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$/;

function isDelivery(delivery: unknown): delivery is Delivery {
  return isObject(delivery) && (isAbsent(delivery.MonitoredStopVisit) || isArrayOf(delivery.MonitoredStopVisit, isObject));
}

function hasItsVisitList(delivery: Delivery): boolean {
  const isError = delivery.Status === "false" || delivery.Status === false || delivery.ErrorCondition !== undefined;
  return isError || Array.isArray(delivery.MonitoredStopVisit);
}

function hasTheTypesThatBuildsRead(visit: Visit): boolean {
  const journey = visit.MonitoredVehicleJourney;
  if (!isOptional(visit.MonitoringRef, isValue) || !isOptional(journey, isObject)) {
    return false;
  }
  if (!journey) {
    return true;
  }
  const call = journey.MonitoredCall;
  return (
    ["LineRef", "DestinationRef", "DirectionRef"].every((field) => isOptional(journey[field], isValue)) &&
    isOptional(journey.DestinationName, (names) => isArrayOf(names, isValue)) &&
    isOptional(journey.FramedVehicleJourneyRef, (ref) => isObject(ref) && isOptional(ref.DatedVehicleJourneyRef, isString)) &&
    isOptional(call, (monitoredCall) => isObject(monitoredCall) && callHasTheTypesThatBuildsRead(monitoredCall))
  );
}

function callHasTheTypesThatBuildsRead(call: Fields): boolean {
  return (
    isOptional(call.DestinationDisplay, (names) => isArrayOf(names, isValue)) &&
    ["DepartureStopAssignment", "ArrivalStopAssignment"].every((field) =>
      isOptional(call[field], (assignment) => isObject(assignment) && isOptional(assignment.ExpectedQuayRef, isValue) && isOptional(assignment.AimedQuayRef, isValue)),
    ) &&
    [...timeFields, "DepartureStatus", "ArrivalStatus"].every((field) => isOptional(call[field], isString)) &&
    isOptional(call.VehicleAtStop, (atStop) => typeof atStop === "boolean")
  );
}

function isReadable(visit: Visit): boolean {
  const journey = visit.MonitoredVehicleJourney;
  const call = journey?.MonitoredCall;
  const destination = [journey?.DestinationName?.[0]?.value, call?.DestinationDisplay?.[0]?.value].some(
    (name) => typeof name === "string" && name.trim() !== "",
  );
  const time = timeFields.some((field) => {
    const text = call?.[field];
    return typeof text === "string" && timeForm.test(text) && !Number.isNaN(Date.parse(text));
  });
  return typeof journey?.LineRef?.value === "string" && time && destination;
}

function isValue(value: unknown): value is Value {
  return isObject(value) && isOptional(value.value, isString);
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

function isObject(value: unknown): value is Fields {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isArrayOf<T>(value: unknown, isItem: (item: unknown) => item is T): value is T[] {
  return Array.isArray(value) && value.every(isItem);
}

function isAbsent(value: unknown): value is null | undefined {
  return value === null || value === undefined;
}

function isOptional(value: unknown, isPresent: (present: unknown) => boolean): boolean {
  return isAbsent(value) || isPresent(value);
}
