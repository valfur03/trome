import type { RelayAnswer } from "../relay/relay";
import {
  isQuay,
  lineCodeOfLineRef,
  monitoringRefs,
  searchKey,
  type Station,
  type StationCatalog,
  type TransitLine,
} from "./station-catalog";

/**
 * The trains of a station from the answers of the server for each of its stops, as the app gets them from the same answers (`PRIMDeparturesProvider` and `StopMonitoringResponse` of the app).
 * The app parses the PRIM answer that the server passes on; the server parses the same answer here, with the same rules, to build the content of a Live Activity that no app is there to build.
 */
export interface Departure {
  line: TransitLine;
  destination: string;
  time: number;
  quayRef?: string;
  directionRef?: string;
  arrivalTime?: number;
  isAtStop: boolean;
}

export type StationTrains =
  | { kind: "departures"; departures: Departure[]; answeredAt: number | undefined; unansweredStops: Set<string> }
  | { kind: "failed"; serverIsOut: boolean };

export interface StopRequest {
  monitoringRef: string;
  lineCodes: Set<string>;
}

interface MonitoredVisit {
  monitoringRef?: string;
  lineRef: string;
  destinationRef?: string;
  destinationName: string;
  journeyRef?: string;
  time: number;
  quayRef?: string;
  directionRef?: string;
  arrivalTime?: number;
  isAtStop: boolean;
  status?: string;
}

type StopError = "server-out" | "service-failure";

/** The stops to ask for the stations, each with the lines that it is asked for. */
export function stopRequests(stations: readonly Station[], catalog: StationCatalog): StopRequest[] {
  const requests: StopRequest[] = [];
  for (const line of stations.flatMap((station) => station.lines)) {
    const lineCode = catalog.primLineCode(line);
    if (lineCode === undefined) {
      continue;
    }
    for (const ref of monitoringRefs(line)) {
      const request = requests.find((existing) => existing.monitoringRef === ref);
      if (request) {
        request.lineCodes.add(lineCode);
      } else {
        requests.push({ monitoringRef: ref, lineCodes: new Set([lineCode]) });
      }
    }
  }
  return requests;
}

/** The trains of the stations from the answer of each stop, or the failure that the app would show when none is left. */
export function stationTrains(
  stations: readonly Station[],
  catalog: StationCatalog,
  answers: readonly { request: StopRequest; answer: RelayAnswer }[],
): StationTrains {
  const read = answers.map(({ request, answer }) => ({ request, ...readAnswer(answer) }));
  const visits = read.flatMap(({ request, visits: stopVisits }) =>
    (stopVisits ?? []).flatMap((visit) => askedVisit(visit, request) ?? []),
  );
  const departures = keptDepartures(visits, stations, catalog);
  const errors = read.flatMap(({ error }) => error ?? []);
  if (departures.length === 0 && errors.length > 0) {
    return { kind: "failed", serverIsOut: errors.includes("server-out") };
  }
  const answeredTimes = read.flatMap(({ answeredAt }) => answeredAt ?? []);
  return {
    kind: "departures",
    departures,
    answeredAt: answeredTimes.length > 0 ? Math.min(...answeredTimes) : undefined,
    unansweredStops: new Set(read.filter(({ error }) => error !== undefined).map(({ request }) => request.monitoringRef)),
  };
}

function readAnswer(answer: RelayAnswer): { visits?: MonitoredVisit[]; answeredAt?: number; error?: StopError } {
  if (answer.kind === "out") {
    // The app reads `budget` and `prim-limit` as "the server is out" and every other reason as a failure (`ServerOutAnswer`).
    return { error: answer.reason === "prim-failure" ? "service-failure" : "server-out" };
  }
  try {
    // The app reads the time of the answer from `Last-Modified`, which holds whole seconds.
    return { visits: visitsOf(answer.body), answeredAt: Math.floor(answer.primAnsweredAt / 1000) * 1000 };
  } catch {
    return { error: "service-failure" };
  }
}

function askedVisit(visit: MonitoredVisit, request: StopRequest): MonitoredVisit | undefined {
  const lineCode = lineCodeOfLineRef(visit.lineRef);
  if (lineCode === undefined || !request.lineCodes.has(lineCode)) {
    return undefined;
  }
  const asked = { ...visit };
  if (isQuay(request.monitoringRef)) {
    asked.quayRef = request.monitoringRef;
  } else if (asked.quayRef === undefined && asked.monitoringRef !== undefined && isQuay(asked.monitoringRef)) {
    asked.quayRef = asked.monitoringRef;
  }
  return asked;
}

function keptDepartures(visits: readonly MonitoredVisit[], stations: readonly Station[], catalog: StationCatalog): Departure[] {
  const linesByCode = new Map<string, { line: TransitLine; stationKey: string }>();
  for (const station of stations) {
    for (const line of station.lines) {
      const code = catalog.primLineCode(line);
      if (code !== undefined && !linesByCode.has(code)) {
        linesByCode.set(code, { line, stationKey: searchKey(station.name) });
      }
    }
  }
  const seenJourneys = new Set<string>();
  const departures: Departure[] = [];
  for (const visit of visits) {
    if (visit.status === "cancelled") {
      continue;
    }
    const code = lineCodeOfLineRef(visit.lineRef);
    const known = code === undefined ? undefined : linesByCode.get(code);
    if (known === undefined) {
      continue;
    }
    const { line, stationKey } = known;
    const endsHere =
      (visit.destinationRef !== undefined && visit.destinationRef === visit.monitoringRef) ||
      searchKey(visit.destinationName) === stationKey;
    if (endsHere) {
      continue;
    }
    const journeyKey =
      visit.journeyRef === undefined
        ? `${line.mode}-${line.name}-${visit.destinationName}-${String(visit.time)}`
        : `${line.mode}-${line.name}-${visit.journeyRef}`;
    if (seenJourneys.has(journeyKey)) {
      continue;
    }
    seenJourneys.add(journeyKey);
    const departure: Departure = { line, destination: visit.destinationName, time: visit.time, isAtStop: visit.isAtStop };
    if (visit.quayRef !== undefined) {
      departure.quayRef = visit.quayRef;
    }
    if (visit.directionRef !== undefined) {
      departure.directionRef = visit.directionRef;
    }
    if (visit.arrivalTime !== undefined) {
      departure.arrivalTime = visit.arrivalTime;
    }
    departures.push(departure);
  }
  return departures;
}

class UnreadableAnswer extends Error {}

type JsonObject = Record<string, unknown>;

/**
 * The visits of a PRIM answer, read as the app's decoder reads them: each key with its first letter in lower case, a missing or `null` field as nothing, and a field that the app reads with another type as an unreadable answer.
 */
function visitsOf(body: string): MonitoredVisit[] {
  const root = requiredObject(JSON.parse(body) as unknown);
  const delivery = requiredObject(field(requiredObject(field(root, "siri")), "serviceDelivery"));
  return (optionalArray(field(delivery, "stopMonitoringDelivery")) ?? []).flatMap((stopDelivery) =>
    (optionalArray(field(requiredObject(stopDelivery), "monitoredStopVisit")) ?? []).flatMap(
      (stopVisit) => visit(requiredObject(stopVisit)) ?? [],
    ),
  );
}

function visit(stopVisit: JsonObject): MonitoredVisit | undefined {
  const monitoringRef = value(field(stopVisit, "monitoringRef"));
  const journey = optionalObject(field(stopVisit, "monitoredVehicleJourney"));
  if (journey === undefined) {
    return undefined;
  }
  const lineRef = value(field(journey, "lineRef"));
  const destinationRef = value(field(journey, "destinationRef"));
  const destinationNames = values(field(journey, "destinationName"));
  const directionRef = value(field(journey, "directionRef"));
  const framed = optionalObject(field(journey, "framedVehicleJourneyRef"));
  const journeyRef = framed === undefined ? undefined : optionalString(field(framed, "datedVehicleJourneyRef"));
  const call = optionalObject(field(journey, "monitoredCall"));
  if (lineRef === undefined || call === undefined) {
    return undefined;
  }
  const destinationDisplay = values(field(call, "destinationDisplay"));
  const expectedDeparture = optionalString(field(call, "expectedDepartureTime"));
  const expectedArrival = optionalString(field(call, "expectedArrivalTime"));
  const aimedDeparture = optionalString(field(call, "aimedDepartureTime"));
  const aimedArrival = optionalString(field(call, "aimedArrivalTime"));
  const departureStatus = optionalString(field(call, "departureStatus"));
  const arrivalStatus = optionalString(field(call, "arrivalStatus"));
  const vehicleAtStop = optionalBoolean(field(call, "vehicleAtStop"));
  const quayRef = [field(call, "departureStopAssignment"), field(call, "arrivalStopAssignment")]
    .map((assignment) => {
      const object = optionalObject(assignment);
      return object === undefined
        ? undefined
        : (value(field(object, "expectedQuayRef")) ?? value(field(object, "aimedQuayRef")));
    })
    .find((ref) => ref !== undefined && ref.length > 0);

  const time = firstDate([expectedDeparture, expectedArrival, aimedDeparture, aimedArrival]);
  const destinationName = [destinationNames?.[0], destinationDisplay?.[0]]
    .map((name) => name?.trim())
    .find((name) => name !== undefined && name.length > 0);
  if (time === undefined || destinationName === undefined) {
    return undefined;
  }
  const result: MonitoredVisit = { lineRef, destinationName, time, isAtStop: vehicleAtStop ?? false };
  assign(result, "monitoringRef", monitoringRef);
  assign(result, "destinationRef", destinationRef);
  assign(result, "journeyRef", journeyRef);
  assign(result, "quayRef", quayRef);
  assign(result, "directionRef", directionRef);
  assign(result, "arrivalTime", firstDate([expectedArrival, aimedArrival]));
  assign(result, "status", departureStatus ?? arrivalStatus);
  return result;
}

function assign<Key extends keyof MonitoredVisit>(target: MonitoredVisit, key: Key, fieldValue: MonitoredVisit[Key] | undefined): void {
  if (fieldValue !== undefined) {
    target[key] = fieldValue;
  }
}

/** The field of a key, found as the app's decoder finds it: the key of the answer with its first letter in lower case. */
function field(object: JsonObject, name: string): unknown {
  let found: unknown = undefined;
  for (const [key, fieldValue] of Object.entries(object)) {
    if (key.slice(0, 1).toLowerCase() + key.slice(1) === name) {
      found = fieldValue;
    }
  }
  return found;
}

function requiredObject(fieldValue: unknown): JsonObject {
  const object = optionalObject(fieldValue);
  if (object === undefined) {
    throw new UnreadableAnswer();
  }
  return object;
}

function optionalObject(fieldValue: unknown): JsonObject | undefined {
  if (fieldValue === undefined || fieldValue === null) {
    return undefined;
  }
  if (typeof fieldValue !== "object" || Array.isArray(fieldValue)) {
    throw new UnreadableAnswer();
  }
  return fieldValue as JsonObject;
}

function optionalArray(fieldValue: unknown): unknown[] | undefined {
  if (fieldValue === undefined || fieldValue === null) {
    return undefined;
  }
  if (!Array.isArray(fieldValue)) {
    throw new UnreadableAnswer();
  }
  return fieldValue as unknown[];
}

function optionalString(fieldValue: unknown): string | undefined {
  if (fieldValue === undefined || fieldValue === null) {
    return undefined;
  }
  if (typeof fieldValue !== "string") {
    throw new UnreadableAnswer();
  }
  return fieldValue;
}

function optionalBoolean(fieldValue: unknown): boolean | undefined {
  if (fieldValue === undefined || fieldValue === null) {
    return undefined;
  }
  if (typeof fieldValue !== "boolean") {
    throw new UnreadableAnswer();
  }
  return fieldValue;
}

/** A `{"value": "..."}` field of PRIM. */
function value(fieldValue: unknown): string | undefined {
  const object = optionalObject(fieldValue);
  return object === undefined ? undefined : optionalString(field(object, "value"));
}

/** A list of `{"value": "..."}` fields of PRIM; an element that is `null` is unreadable, as for the app. */
function values(fieldValue: unknown): (string | undefined)[] | undefined {
  return optionalArray(fieldValue)?.map((element) => value(requiredObject(element)));
}

const siriDate = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$/;

function firstDate(texts: readonly (string | undefined)[]): number | undefined {
  for (const text of texts) {
    if (text !== undefined && siriDate.test(text)) {
      const time = Date.parse(text);
      if (!Number.isNaN(time)) {
        return time;
      }
    }
  }
  return undefined;
}
