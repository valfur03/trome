import type { Departure } from "./station-departures";
import { quayRefs, searchKey, type LineEnds, type Station, type StationCatalog, type TransitLine } from "./station-catalog";

/**
 * The directions of a line at a station, with their next trains, as the app's `LineDirections` makes them for the Live Activity.
 * The rules and their reasons are told on the Swift side, in the doc comments of `LineDirections`, `PlatformStatus` and `LineEnds`; this port keeps their order, so that the two read side by side.
 * `contracts/live-activity/` holds the contents that both must build alike.
 */
export type PlatformStatus = "approaching" | "atPlatform";

export interface DirectionTrain {
  time: number;
  destination: string;
  status?: PlatformStatus;
  arrivalTime?: number;
}

export interface BranchEndTrains {
  end: string;
  trains: DirectionTrain[];
  nextTrainIsOverAnHourAway: boolean;
}

export interface LineDirection {
  label: string;
  trains: DirectionTrain[];
  nextTrainIsOverAnHourAway: boolean;
  branchEnds?: string[];
  trainsOfEachEnd?: BranchEndTrains[];
  noAnswer?: true;
}

interface TrainWithStatus {
  train: Departure;
  status: PlatformStatus | undefined;
}

interface Group {
  isOneDirection: boolean;
  isStationQuay: boolean;
  trains: Departure[];
  side: number | undefined;
}

const timesPerDirection = 2;
const maximumDirections = 3;
const minimumMetroHeadway = 60_000;
const approachingTime = 60_000;

export class LineDirections {
  constructor(private readonly catalog: StationCatalog) {}

  /** The directions from the trains within the hour, marked where the next train is over an hour away. */
  directions(line: TransitLine, station: Station, departures: readonly Departure[], later: readonly Departure[], now: number): LineDirection[] {
    const shown = this.directionsFrom(line, station, departures, now);
    if (later.length === 0) {
      return shown;
    }
    const laterTimes = new Set(later.map((departure) => departure.time));
    const withLater = this.directionsFrom(line, station, [...departures, ...later], now);
    const laterOnly = withLater.filter((direction) => {
      const first = direction.trains[0];
      return first !== undefined && laterTimes.has(first.time);
    });
    for (const laterDirection of laterOnly) {
      const index = shown.findIndex((direction) => direction.label === laterDirection.label);
      const existing = shown[index];
      if (existing !== undefined) {
        if (existing.trains.length === 0) {
          existing.nextTrainIsOverAnHourAway = true;
        }
      } else if (shown.length < maximumDirections) {
        const added: LineDirection = { label: laterDirection.label, trains: [], nextTrainIsOverAnHourAway: true };
        if (laterDirection.branchEnds !== undefined) {
          added.branchEnds = laterDirection.branchEnds;
        }
        if (laterDirection.trainsOfEachEnd !== undefined) {
          added.trainsOfEachEnd = laterDirection.trainsOfEachEnd.map(({ end }) => ({ end, trains: [], nextTrainIsOverAnHourAway: false }));
        }
        shown.push(added);
      }
    }
    for (const direction of shown) {
      const laterDirection = withLater.find((candidate) => candidate.label === direction.label);
      if (laterDirection !== undefined) {
        markEndsWhoseNextTrainIsOverAnHourAway(direction, laterDirection);
      }
    }
    return shown;
  }

  /** The directions of a line of which a stop did not answer while another stop of the station did. */
  directionsWithNoAnswer(
    line: TransitLine,
    station: Station,
    answered: readonly LineDirection[],
    earlier: readonly Departure[],
    now: number,
  ): LineDirection[] {
    const kept = this.directionsFrom(line, station, earlier, now).filter((direction) => {
      const first = direction.trains[0];
      return first !== undefined && first.time > now;
    });
    const shown = answered.length === 0 ? this.directionsFrom(line, station, [], now, true) : [...answered];
    for (const [index, direction] of shown.entries()) {
      if (direction.trains.length === 0 && !direction.nextTrainIsOverAnHourAway) {
        const earlierDirection = kept.find((candidate) => candidate.label === direction.label);
        shown[index] = earlierDirection ?? { ...direction, noAnswer: true };
      }
    }
    for (const direction of kept) {
      if (shown.length < maximumDirections && !shown.some((candidate) => candidate.label === direction.label)) {
        shown.push(direction);
      }
    }
    return shown;
  }

  hasADirectionWithTwoEnds(line: TransitLine, station: Station): boolean {
    const ends = this.catalog.ends(line);
    if (ends === undefined) {
      return false;
    }
    const stationKey = searchKey(station.name);
    return [ends.first, ends.second]
      .filter((side) => !side.some((name) => searchKey(name) === stationKey))
      .some((side) => reachableEnds(ends, side, station.name).length > 1);
  }

  private directionsFrom(
    line: TransitLine,
    station: Station,
    departures: readonly Departure[],
    now: number,
    showsEverySide = false,
  ): LineDirection[] {
    const trains = departures
      .filter((departure) => departure.line.mode === line.mode && departure.line.name === line.name)
      .sort((a, b) => a.time - b.time);
    const quays = quayRefs(line);
    const stationKey = searchKey(station.name);
    const ends = this.catalog.endsOrNone(line);
    const sides = [ends.first, ends.second].filter(
      (names) => names.length > 0 && !names.some((name) => searchKey(name) === stationKey),
    );
    const isOnTheRERTrunk =
      line.mode === "rer" &&
      sides.length === 2 &&
      !Object.values(ends.branchStations).some((names) => names.some((name) => searchKey(name) === stationKey));
    const groups = groupsOf(trains, quays).map((group) => ({
      ...group,
      side: sideOf(group, station, sides, ends, isOnTheRERTrunk),
    }));
    inferQuaySides(groups, sides.length);
    inferSidesFromDirectionRefs(groups);

    const hasMetroQuayOfUnknownSide =
      line.mode === "metro" && groups.some((group) => group.isOneDirection && group.side === undefined && group.trains.length > 0);
    const showsEmptySides = showsEverySide || (quays.length !== 1 && !hasMetroQuayOfUnknownSide);
    const sideDirections = sides.flatMap((side, index) => {
      const sideTrains = oneEntryPerTrain(
        groups
          .filter((group) => group.side === index)
          .flatMap((group) => group.trains)
          .sort((a, b) => a.time - b.time),
        line,
      );
      if (!showsEmptySides && sideTrains.length === 0) {
        return [];
      }
      return [this.direction(line, side, station, sideTrains, now)];
    });
    const otherDirections = groups
      .filter((group) => group.side === undefined && group.trains.length > 0 && !isOnTheRERTrunk)
      .sort((a, b) => firstTime(a) - firstTime(b))
      .map((group) => ({
        label: group.trains[0]?.destination ?? "",
        trains: withStatuses(oneEntryPerTrain(group.trains, line), line, now)
          .slice(0, timesPerDirection)
          .map((train) => shown(train)),
        nextTrainIsOverAnHourAway: false,
      }));
    return [...sideDirections, ...otherDirections].slice(0, maximumDirections);
  }

  private direction(line: TransitLine, side: readonly string[], station: Station, sideTrains: readonly Departure[], now: number): LineDirection {
    const ends = this.catalog.endsOrNone(line);
    const reachable = reachableEnds(ends, side, station.name);
    const branchEnds = line.mode === "metro" && reachable.length > 1 ? reachable : undefined;
    const trains = withStatuses(sideTrains, line, now);
    const direction: LineDirection = {
      label: reachable.join(" / "),
      trains: trains.slice(0, timesPerDirection).map((train) => shown(train, endName(train.train.destination, side, ends))),
      nextTrainIsOverAnHourAway: false,
    };
    if (branchEnds !== undefined) {
      direction.branchEnds = branchEnds;
      direction.trainsOfEachEnd = branchEnds.map((end) => ({
        end,
        trains: trains
          .filter((train) => endName(train.train.destination, [end], ends) !== undefined)
          .slice(0, timesPerDirection)
          .map((train) => shown(train, end)),
        nextTrainIsOverAnHourAway: false,
      }));
    }
    return direction;
  }
}

function firstTime(group: Group): number {
  return group.trains[0]?.time ?? 0;
}

function markEndsWhoseNextTrainIsOverAnHourAway(direction: LineDirection, withLaterTrains: LineDirection): void {
  const endTrains = direction.trainsOfEachEnd;
  const laterEndTrains = withLaterTrains.trainsOfEachEnd;
  if (endTrains === undefined || laterEndTrains === undefined) {
    return;
  }
  const laterTrainsTellTheEnds = laterEndTrains.some((later) => later.trains.length > 0);
  direction.trainsOfEachEnd = endTrains.map((trains) => {
    if (trains.trains.length > 0) {
      return trains;
    }
    const laterTrainOfTheEnd = laterEndTrains.some((later) => later.end === trains.end && later.trains.length > 0);
    return {
      ...trains,
      nextTrainIsOverAnHourAway: laterTrainOfTheEnd || (!laterTrainsTellTheEnds && direction.nextTrainIsOverAnHourAway),
    };
  });
}

function oneEntryPerTrain(trains: readonly Departure[], line: TransitLine): Departure[] {
  if (line.mode !== "metro") {
    return [...trains];
  }
  const kept: Departure[] = [];
  for (const train of trains) {
    const last = kept.at(-1);
    if (last !== undefined && train.time - last.time < minimumMetroHeadway) {
      continue;
    }
    kept.push(train);
  }
  return kept;
}

function groupsOf(trains: readonly Departure[], quays: readonly string[]): Group[] {
  const allQuays = [...quays];
  for (const train of trains) {
    if (train.quayRef !== undefined && !allQuays.includes(train.quayRef)) {
      allQuays.push(train.quayRef);
    }
  }
  const quayGroups = allQuays.map((quay) => ({
    isOneDirection: true,
    isStationQuay: quays.includes(quay),
    trains: trains.filter((train) => train.quayRef === quay),
    side: undefined,
  }));
  const destinations: string[] = [];
  for (const train of trains) {
    if (train.quayRef === undefined && !destinations.includes(train.destination)) {
      destinations.push(train.destination);
    }
  }
  const destinationGroups = destinations.map((destination) => ({
    isOneDirection: false,
    isStationQuay: false,
    trains: trains.filter((train) => train.quayRef === undefined && train.destination === destination),
    side: undefined,
  }));
  return [...quayGroups, ...destinationGroups];
}

function inferSidesFromDirectionRefs(groups: Group[]): void {
  const directionRefs = new Set(groups.flatMap((group) => group.trains.flatMap((train) => train.directionRef ?? [])));
  if (directionRefs.size <= 1) {
    return;
  }
  const sidesByDirectionRef = new Map<string, Set<number>>();
  for (const group of groups) {
    if (group.side === undefined) {
      continue;
    }
    for (const train of group.trains) {
      if (train.directionRef !== undefined) {
        const sides = sidesByDirectionRef.get(train.directionRef) ?? new Set<number>();
        sides.add(group.side);
        sidesByDirectionRef.set(train.directionRef, sides);
      }
    }
  }
  for (const group of groups) {
    if (group.side !== undefined) {
      continue;
    }
    const groupSides = group.trains.map((train) =>
      train.directionRef === undefined ? undefined : sidesByDirectionRef.get(train.directionRef),
    );
    const first = groupSides[0];
    if (first?.size !== 1 || !groupSides.every((sides) => sides !== undefined && sameSet(sides, first))) {
      continue;
    }
    group.side = [...first][0];
  }
}

function inferQuaySides(groups: Group[], sideCount: number): void {
  const unknown = groups.filter((group) => group.isOneDirection && group.side === undefined && group.trains.length > 0);
  if (sideCount === 1) {
    for (const group of unknown) {
      group.side = 0;
    }
    return;
  }
  const taken = new Set(groups.flatMap((group) => (group.side === undefined ? [] : [group.side])));
  const freeSides = [...Array(sideCount).keys()].filter((side) => !taken.has(side));
  const [only] = unknown;
  if (unknown.length === 1 && only?.isStationQuay === true && freeSides.length === 1) {
    only.side = freeSides[0];
  }
}

function sideOf(group: Group, station: Station, sides: readonly (readonly string[])[], ends: LineEnds, isOnTheRERTrunk: boolean): number | undefined {
  const destinations = group.trains.map((train) => train.destination);
  for (const destination of destinations) {
    const side = sides.findIndex((names) => endName(destination, names, ends) !== undefined);
    if (side >= 0) {
      return side;
    }
  }
  for (const destination of destinations) {
    const side = sideTowardTheTrunk(destination, station.name, sides, ends);
    if (side !== undefined) {
      return side;
    }
  }
  if (!isOnTheRERTrunk) {
    return undefined;
  }
  for (const destination of destinations) {
    const trunkSide = trunkSideOf(ends, destination, station.name);
    const trunkIndex = trunkSide === undefined ? -1 : sides.findIndex((names) => sameNames(names, trunkSide));
    const side = trunkIndex >= 0 ? trunkIndex : sideOfTheBranches(destination, sides, ends);
    if (side !== undefined) {
      return side;
    }
  }
  return undefined;
}

function sideTowardTheTrunk(destination: string, stationName: string, sides: readonly (readonly string[])[], ends: LineEnds): number | undefined {
  const stationKey = searchKey(stationName);
  const branchHoldsTheStation = (end: string) => (ends.branchStations[end] ?? []).some((name) => searchKey(name) === stationKey);
  const branchHoldsTheDestination = (end: string) => (ends.branchStations[end] ?? []).some((name) => isNamed(destination, name));
  const endSides = [ends.first, ends.second];
  const branchSides = endSides.flatMap((side, index) => (side.some(branchHoldsTheStation) ? [index] : []));
  const [branchSide] = branchSides;
  if (branchSides.length !== 1 || branchSide === undefined) {
    return undefined;
  }
  const sideEnds = endSides[branchSide] ?? [];
  const isOnNoBranch = !Object.keys(ends.branchStations).some(branchHoldsTheDestination);
  const stationEnds = sideEnds.filter(branchHoldsTheStation);
  const otherEnds = sideEnds.filter((end) => !branchHoldsTheStation(end));
  const isBeforeTheForkOfTheStation = stationEnds.some(branchHoldsTheDestination) && otherEnds.some(branchHoldsTheDestination);
  if (!isOnNoBranch && !isBeforeTheForkOfTheStation) {
    return undefined;
  }
  const otherSide = endSides[1 - branchSide] ?? [];
  const index = sides.findIndex((names) => sameNames(names, otherSide));
  return index >= 0 ? index : undefined;
}

function sideOfTheBranches(destination: string, sides: readonly (readonly string[])[], ends: LineEnds): number | undefined {
  const namingSides = sides.flatMap((names, index) =>
    names.some((end) => (ends.branchStations[end] ?? []).some((name) => isNamed(destination, name))) ? [index] : [],
  );
  return namingSides.length === 1 ? namingSides[0] : undefined;
}

function trunkSideOf(ends: LineEnds, destination: string, stationName: string): readonly string[] | undefined {
  const stationKey = searchKey(stationName);
  const stationIndex = ends.trunkStations.findIndex((name) => searchKey(name) === stationKey);
  const destinationIndex = ends.trunkStations.findIndex((name) => isNamed(destination, name));
  if (stationIndex < 0 || destinationIndex < 0 || destinationIndex === stationIndex) {
    return undefined;
  }
  return destinationIndex < stationIndex ? ends.first : ends.second;
}

function reachableEnds(ends: LineEnds, side: readonly string[], stationName: string): string[] {
  const stationKey = searchKey(stationName);
  const branchEnds = side.filter((end) => (ends.branchStations[end] ?? []).some((name) => searchKey(name) === stationKey));
  return branchEnds.length === 0 ? [...side] : branchEnds;
}

function endName(destination: string, names: readonly string[], ends: LineEnds): string | undefined {
  return names.flatMap((name) => [name, ...(ends.otherNames[name] ?? [])]).find((name) => isNamed(destination, name));
}

function isNamed(destination: string, name: string): boolean {
  const key = searchKey(destination);
  const nameKey = searchKey(name);
  return key === nameKey || key.startsWith(`${nameKey} `);
}

function withStatuses(trains: readonly Departure[], line: TransitLine, now: number): TrainWithStatus[] {
  const oneTrainPerPlatform = line.mode === "metro";
  const platformsWithATrainOnTheWay = new Set<string | undefined>();
  return trains.map((train) => {
    const own = platformStatus(train, now);
    if (!oneTrainPerPlatform) {
      return { train, status: own };
    }
    const status = platformsWithATrainOnTheWay.has(train.quayRef) ? undefined : own;
    if (status !== "atPlatform" && train.time > now) {
      platformsWithATrainOnTheWay.add(train.quayRef);
    }
    return { train, status };
  });
}

function platformStatus(departure: Departure, now: number): PlatformStatus | undefined {
  const arrival = departure.arrivalTime ?? departure.time;
  if (departure.isAtStop || (arrival <= now && now < departure.time)) {
    return "atPlatform";
  }
  return arrival - now < approachingTime ? "approaching" : undefined;
}

function shown({ train, status }: TrainWithStatus, destination?: string): DirectionTrain {
  const result: DirectionTrain = { time: train.time, destination: destination ?? train.destination };
  if (status !== undefined) {
    result.status = status;
  }
  if (train.arrivalTime !== undefined) {
    result.arrivalTime = train.arrivalTime;
  }
  return result;
}

function sameNames(first: readonly string[], second: readonly string[]): boolean {
  return first.length === second.length && first.every((name, index) => name === second[index]);
}

function sameSet(first: ReadonlySet<number>, second: ReadonlySet<number>): boolean {
  return first.size === second.size && [...first].every((value) => second.has(value));
}
