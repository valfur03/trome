import type { Departure } from "./station-departures";
import { isQuay, monitoringRefs, sameLine, stationListOrder, type Station, type TransitLine } from "./station-catalog";

const departedGrace = 30_000;
const farthestTime = 60 * 60_000;

/**
 * The trains of a station at one time, as the app's `DepartureBoard` keeps them for the Live Activity: the trains within the hour, the later ones, and the lines of the stations in the order of the station list.
 */
export class DepartureBoard {
  readonly departures: Departure[];
  readonly laterDepartures: Departure[];
  readonly lines: TransitLine[];

  constructor(
    departures: readonly Departure[],
    readonly stations: readonly Station[],
    now: number,
    readonly unansweredStops: ReadonlySet<string> = new Set(),
    private readonly earlier: readonly Departure[] = [],
  ) {
    const headerName = stations[0]?.name;
    this.lines = [
      ...stations.filter((station) => station.name === headerName),
      ...stations.filter((station) => station.name !== headerName),
    ].flatMap((station) => [...station.lines].sort(stationListOrder));
    const notDeparted = departures.filter((departure) => departure.time > now - departedGrace).sort((a, b) => a.time - b.time);
    this.departures = notDeparted.filter((departure) => departure.time <= now + farthestTime);
    this.laterDepartures = notDeparted.filter((departure) => departure.time > now + farthestTime);
  }

  get isEmpty(): boolean {
    return this.departures.length === 0 && this.laterDepartures.length === 0;
  }

  station(serving: TransitLine): Station | undefined {
    return this.stations.find((station) => station.lines.some((line) => sameLine(line, serving)));
  }

  otherStationName(serving: TransitLine): string | undefined {
    const station = this.station(serving);
    return station === undefined || station.name === this.stations[0]?.name ? undefined : station.name;
  }

  hasNoAnswer(line: TransitLine): boolean {
    return monitoringRefs(line).some((ref) => this.unansweredStops.has(ref));
  }

  earlierDepartures(line: TransitLine): Departure[] {
    return this.earlier.filter((departure) => departure.line.mode === line.mode && departure.line.name === line.name);
  }
}

/** The trains of the last answer of a station, which the next one may keep for its stops that do not answer. */
export interface LastTrains {
  departures: readonly Departure[];
  unansweredStops: ReadonlySet<string>;
  earlier: readonly Departure[];
}

/**
 * The trains to keep for the stops that did not answer this time (`departuresToKeep(forUnanswered:now:)` of the app):
 * the trains that the last answer got from these stops and that have not left yet, or, for a stop that did not answer then either, the trains that it kept itself.
 */
export function departuresToKeep(last: LastTrains, stops: ReadonlySet<string>, now: number): Departure[] {
  const answeredThen = new Set([...stops].filter((stop) => !last.unansweredStops.has(stop)));
  const stillUnanswered = new Set([...stops].filter((stop) => last.unansweredStops.has(stop)));
  const fresh = last.departures.filter((departure) => departure.time > now && isFromOneOf(departure, answeredThen));
  const kept = last.earlier.filter((departure) => isFromOneOf(departure, stillUnanswered));
  return [...fresh, ...kept];
}

function isFromOneOf(departure: Departure, stops: ReadonlySet<string>): boolean {
  return monitoringRefs(departure.line).some((stop) => stops.has(stop) && (!isQuay(stop) || departure.quayRef === stop));
}
