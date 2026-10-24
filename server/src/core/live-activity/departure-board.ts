import type { Departure } from "./station-departures";
import { monitoringRefs, sameLine, stationListOrder, type Station, type TransitLine } from "./station-catalog";

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

