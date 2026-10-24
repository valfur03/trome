import lineData from "../../../../contracts/live-activity/line-data.json";
import stationFile from "../../../../ios/Packages/TROMECore/Sources/TROMECore/Resources/stations.json";

/**
 * The stations and the lines of the app, read from the files that the app itself reads: `stations.json` of its package, and `line-data.json`, which a test of the app writes from its own line rules (`LiveActivityContentContractTests`).
 * So the server builds the content of a Live Activity from the same data as the app, with no copy to keep in step by hand.
 */
export type TransitMode = "metro" | "rer";

export interface LineColor {
  background: string;
  text: string;
}

export interface TransitLine {
  mode: TransitMode;
  name: string;
  stopIds: readonly string[];
  stopAreaIds: readonly string[];
  color?: LineColor;
}

export interface Station {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  lines: readonly TransitLine[];
  hubId?: string;
}

export interface LineEnds {
  first: readonly string[];
  second: readonly string[];
  branchStations: Readonly<Record<string, readonly string[]>>;
  trunkStations: readonly string[];
  otherNames: Readonly<Record<string, readonly string[]>>;
}

interface RawLine {
  mode: string;
  name: string;
  stopIds?: string[];
  stopAreaIds?: string[];
  color?: LineColor;
}

interface RawStation {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  lines: RawLine[];
  hubId?: string;
}

interface RawLineData {
  lines: Record<string, { primLineCode?: string; ends?: LineEnds }>;
}

const noEnds: LineEnds = { first: [], second: [], branchStations: {}, trunkStations: [], otherNames: {} };
const earthRadiusMeters = 6_371_000;

export class StationCatalog {
  private readonly byId: Map<string, Station>;

  constructor(
    readonly stations: readonly Station[],
    private readonly lines: RawLineData["lines"],
  ) {
    this.byId = new Map(stations.map((station) => [station.id, station]));
  }

  static bundled(): StationCatalog {
    const stations = (stationFile as { stations: RawStation[] }).stations.map(readStation);
    return new StationCatalog(stations, (lineData as RawLineData).lines);
  }

  station(id: string): Station | undefined {
    return this.byId.get(id);
  }

  /** The station and the other stations of its place, nearest first, each with only the lines that no station before it serves (`StationCatalog.hubStations(of:)` of the app). */
  hubStations(station: Station): Station[] {
    const { hubId } = station;
    if (hubId === undefined) {
      return [station];
    }
    const linked = this.stations
      .filter((other) => other.hubId === hubId && other.id !== station.id)
      .map((other) => ({ other, distance: distance(station, other) }))
      .sort((a, b) => a.distance - b.distance)
      .map(({ other }) => other);
    const served = new Set(station.lines.map(lineKey));
    const hub = [station];
    for (const other of linked) {
      const lines = other.lines.filter((line) => {
        const key = lineKey(line);
        if (served.has(key)) {
          return false;
        }
        served.add(key);
        return true;
      });
      if (lines.length > 0) {
        hub.push({ ...other, lines });
      }
    }
    return hub;
  }

  primLineCode(line: TransitLine): string | undefined {
    return this.lines[lineKey(line)]?.primLineCode;
  }

  ends(line: TransitLine): LineEnds | undefined {
    return this.lines[lineKey(line)]?.ends;
  }

  endsOrNone(line: TransitLine): LineEnds {
    return this.ends(line) ?? noEnds;
  }
}

export function lineKey(line: Pick<TransitLine, "mode" | "name">): string {
  return `${line.mode}-${line.name}`;
}

/** The same line, as Swift compares two `TransitLine` values: every field. */
export function sameLine(first: TransitLine, second: TransitLine): boolean {
  return (
    first.mode === second.mode &&
    first.name === second.name &&
    sameList(first.stopIds, second.stopIds) &&
    sameList(first.stopAreaIds, second.stopAreaIds) &&
    first.color?.background === second.color?.background &&
    first.color?.text === second.color?.text
  );
}

export function sameList(first: readonly string[], second: readonly string[]): boolean {
  return first.length === second.length && first.every((value, index) => value === second[index]);
}

/** The order of the lines in the station list: metro before RER, then by number, then by name. */
export function stationListOrder(first: TransitLine, second: TransitLine): number {
  const rank = (line: TransitLine) => (line.mode === "metro" ? 0 : 1);
  const number = (line: TransitLine) => Number.parseInt(line.name.replace(/\D/g, ""), 10) || 0;
  return rank(first) - rank(second) || number(first) - number(second) || compareText(first.name, second.name);
}

function compareText(first: string, second: string): number {
  if (first === second) {
    return 0;
  }
  return first < second ? -1 : 1;
}

/** The search key of a name, as the app makes it: no case, no accent, words of letters and digits only. */
export function searchKey(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}+/gu, "")
    .split(/[^\p{L}\p{M}\p{N}]+/u)
    .filter((word) => word.length > 0)
    .join(" ");
}

const stopAreaPrefix = "IDFM:monomodalStopPlace:";
const stopPointPrefix = "IDFM:";
const quayPrefix = "STIF:StopPoint:Q:";

/** The `MonitoringRef` that PRIM asks for a stop id of the station list (`PRIMStopReference` of the app). */
export function monitoringRef(stopId: string): string | undefined {
  if (stopId.startsWith(stopAreaPrefix)) {
    const code = stopId.slice(stopAreaPrefix.length);
    return code.length === 0 ? undefined : `STIF:StopArea:SP:${code}:`;
  }
  if (stopId.startsWith(stopPointPrefix)) {
    const code = stopId.slice(stopPointPrefix.length);
    return code.length === 0 || code.includes(":") ? undefined : `${quayPrefix}${code}:`;
  }
  return undefined;
}

export function monitoringRefs(line: TransitLine): string[] {
  return (line.stopAreaIds.length === 0 ? line.stopIds : line.stopAreaIds).flatMap((id) => monitoringRef(id) ?? []);
}

export function isQuay(ref: string): boolean {
  return ref.startsWith(quayPrefix);
}

export function quayRefs(line: TransitLine): string[] {
  return [...new Set(line.stopIds.flatMap((id) => monitoringRef(id) ?? []).filter(isQuay))];
}

export function lineCodeOfLineRef(lineRef: string): string | undefined {
  return lineRef.split(":").filter((part) => part.length > 0).at(-1);
}

function readStation(raw: RawStation): Station {
  const station: Station = {
    id: raw.id,
    name: raw.name,
    latitude: raw.latitude,
    longitude: raw.longitude,
    lines: raw.lines.map(readLine),
  };
  if (raw.hubId !== undefined) {
    station.hubId = raw.hubId;
  }
  return station;
}

function readLine(raw: RawLine): TransitLine {
  const line: TransitLine = {
    mode: raw.mode === "rer" ? "rer" : "metro",
    name: raw.name,
    stopIds: raw.stopIds ?? [],
    stopAreaIds: raw.stopAreaIds ?? [],
  };
  if (raw.color !== undefined) {
    line.color = { background: raw.color.background, text: raw.color.text };
  }
  return line;
}

function distance(from: Station, to: Station): number {
  const lat1 = (from.latitude * Math.PI) / 180;
  const lat2 = (to.latitude * Math.PI) / 180;
  const deltaLatitude = lat2 - lat1;
  const deltaLongitude = ((to.longitude - from.longitude) * Math.PI) / 180;
  const haversine =
    Math.sin(deltaLatitude / 2) * Math.sin(deltaLatitude / 2) +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLongitude / 2) * Math.sin(deltaLongitude / 2);
  return 2 * earthRadiusMeters * Math.asin(Math.min(1, Math.sqrt(haversine)));
}
