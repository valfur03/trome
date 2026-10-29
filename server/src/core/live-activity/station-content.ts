import { DepartureBoard } from "./departure-board";
import { LineDirections, type DirectionTrain, type LineDirection } from "./line-directions";
import type { Departure, StationTrains } from "./station-departures";
import { stationListOrder, type LineColor, type Station, type StationCatalog, type TransitLine } from "./station-catalog";

/**
 * The content of a Live Activity of a station, as the app's `StationActivityAttributes.ContentState` holds it, with its times in milliseconds.
 * `encodeContent` writes it as the app's `JSONEncoder` does, so that the widget decodes it with no app to help.
 */
export interface ShownLine {
  mode: TransitLine["mode"];
  name: string;
  color?: LineColor;
}

export interface LineTrains {
  line: ShownLine;
  directions: LineDirection[];
  stationName?: string;
  hasADirectionWithTwoEnds: boolean;
}

export interface SoonestTrain {
  line: ShownLine;
  time: number;
  train: DirectionTrain;
}

export interface LinesPage {
  lines: LineTrains[];
  allLines: ShownLine[];
  firstIndex: number;
  soonestTrain?: SoonestTrain;
  nextTrainIsOverAnHourAway: boolean;
  nextTrainComesWithinTheHourAt?: number;
  lineOfTheTrainOverAnHourAway?: ShownLine;
  lineWithNoAnswer?: ShownLine;
}

export type ContentTrains = { kind: "lines"; page: LinesPage } | { kind: "noData" };

export interface StationContent {
  stationName: string;
  trains: ContentTrains;
  updatedAt: number;
  serverIsOut: boolean;
  /** Times kept after a failed call, once their first train has left: the widget hides the waits at once (`isMarkedStale` of the app). */
  isMarkedStale?: boolean;
}

const maximumRowsWithTwoTrains = 2;
const farthestTime = 60 * 60_000;
/** The seconds between 1970 and 2001: the app's `JSONEncoder` writes a date as seconds since 2001. */
const referenceDateSeconds = 978_307_200;

/** `earlier` holds the trains that an earlier answer gave for the stops that did not answer this time (`departuresToKeep`). */
export function stationContent(
  station: Station,
  stations: readonly Station[],
  trains: StationTrains,
  catalog: StationCatalog,
  now: number,
  earlier: readonly Departure[] = [],
): StationContent {
  const lineDirections = new LineDirections(catalog);
  if (trains.kind === "failed") {
    return { stationName: station.name, trains: { kind: "noData" }, updatedAt: now, serverIsOut: trains.serverIsOut };
  }
  const answeredAt = Math.min(trains.answeredAt ?? now, now);
  const board = new DepartureBoard(trains.departures, stations, answeredAt, trains.unansweredStops, earlier);
  const knowsThereIsNoTrain = board.isEmpty && board.unansweredStops.size === 0;
  const lines = knowsThereIsNoTrain
    ? [...station.lines].sort(stationListOrder).map((line) => ({
        line: shownLine(line),
        directions: [],
        hasADirectionWithTwoEnds: lineDirections.hasADirectionWithTwoEnds(line, station),
      }))
    : boardLines(board, station, lineDirections, now);
  const page = linesPage(lines, 0, knowsThereIsNoTrain ? undefined : board.laterDepartures[0]);
  return { stationName: station.name, trains: { kind: "lines", page }, updatedAt: now, serverIsOut: false };
}

/** The date after which the content is old: the soonest train, or the time when the next train comes within the hour (`staleDate` of the app). */
export function staleDate(content: StationContent): number | undefined {
  if (content.trains.kind === "noData") {
    return undefined;
  }
  return content.trains.page.soonestTrain?.time ?? content.trains.page.nextTrainComesWithinTheHourAt;
}

function boardLines(board: DepartureBoard, station: Station, lineDirections: LineDirections, now: number): LineTrains[] {
  const upcoming = board.departures.filter((departure) => departure.time > now);
  return board.lines.map((line) => {
    const servingStation = board.station(line);
    let directions: LineDirection[] = [];
    if (servingStation !== undefined) {
      const answered = lineDirections.directions(line, servingStation, upcoming, board.laterDepartures, now);
      directions = board.hasNoAnswer(line)
        ? lineDirections.directionsWithNoAnswer(line, servingStation, answered, board.earlierDepartures(line), now)
        : answered;
    }
    const lineTrains: LineTrains = {
      line: shownLine(line),
      directions,
      hasADirectionWithTwoEnds: lineDirections.hasADirectionWithTwoEnds(line, servingStation ?? station),
    };
    const stationName = board.otherStationName(line);
    if (stationName !== undefined) {
      lineTrains.stationName = stationName;
    }
    return lineTrains;
  });
}

function linesPage(lines: readonly LineTrains[], index: number, laterTrain: Departure | undefined): LinesPage {
  const firstIndex = index >= 0 && index < lines.length ? index : 0;
  let shown = lines.slice(firstIndex, firstIndex + 1);
  if (shown.flatMap((line) => line.directions).length > maximumRowsWithTwoTrains) {
    shown = shown.map(keepingOnlyTheNextTrains);
  }
  let soonestTrain: SoonestTrain | undefined;
  for (const line of lines) {
    for (const direction of line.directions) {
      const train = direction.trains[0];
      if (train !== undefined && (soonestTrain === undefined || train.time < soonestTrain.time)) {
        soonestTrain = { line: line.line, time: train.time, train };
      }
    }
  }
  const nextTrainIsOverAnHourAway =
    soonestTrain === undefined && lines.some((line) => line.directions.some((direction) => direction.nextTrainIsOverAnHourAway));
  const page: LinesPage = { lines: shown, allLines: lines.map((line) => line.line), firstIndex, nextTrainIsOverAnHourAway };
  if (soonestTrain !== undefined) {
    page.soonestTrain = soonestTrain;
  }
  const lineWithNoAnswer = lines.find((line) => line.directions.some((direction) => direction.noAnswer === true))?.line;
  if (lineWithNoAnswer !== undefined) {
    page.lineWithNoAnswer = lineWithNoAnswer;
  }
  if (nextTrainIsOverAnHourAway && laterTrain !== undefined) {
    page.nextTrainComesWithinTheHourAt = laterTrain.time - farthestTime;
    const line = lines.find((candidate) => candidate.line.mode === laterTrain.line.mode && candidate.line.name === laterTrain.line.name)?.line;
    if (line !== undefined) {
      page.lineOfTheTrainOverAnHourAway = line;
    }
  }
  return page;
}

function keepingOnlyTheNextTrains(line: LineTrains): LineTrains {
  return {
    ...line,
    directions: line.directions.map((direction) => {
      const kept: LineDirection = { ...direction, trains: direction.trains.slice(0, 1) };
      if (direction.trainsOfEachEnd !== undefined) {
        kept.trainsOfEachEnd = direction.trainsOfEachEnd.map((end) => ({ ...end, trains: end.trains.slice(0, 1) }));
      }
      return kept;
    }),
  };
}

function shownLine(line: TransitLine): ShownLine {
  const shown: ShownLine = { mode: line.mode, name: line.name };
  if (line.color !== undefined) {
    shown.color = line.color;
  }
  return shown;
}

/** The content as the JSON that the widget decodes: dates in seconds since 2001, an enum case as an object named after it, no key for a missing value. */
export function encodeContent(content: StationContent): Record<string, unknown> {
  return {
    appNeedsUpdate: false,
    isMarkedStale: content.isMarkedStale ?? false,
    serverIsOut: content.serverIsOut,
    stationName: content.stationName,
    trains: content.trains.kind === "noData" ? { noData: {} } : { lines: { _0: encodePage(content.trains.page) } },
    updatedAt: swiftDate(content.updatedAt),
  };
}

function encodePage(page: LinesPage): Record<string, unknown> {
  return withoutUndefined({
    lines: page.lines.map((line) =>
      withoutUndefined({
        line: line.line,
        directions: line.directions.map(encodeDirection),
        stationName: line.stationName,
        hasADirectionWithTwoEnds: line.hasADirectionWithTwoEnds,
      }),
    ),
    allLines: page.allLines,
    firstIndex: page.firstIndex,
    soonestTrain:
      page.soonestTrain === undefined
        ? undefined
        : { line: page.soonestTrain.line, time: swiftDate(page.soonestTrain.time), train: encodeTrain(page.soonestTrain.train) },
    nextTrainIsOverAnHourAway: page.nextTrainIsOverAnHourAway,
    nextTrainComesWithinTheHourAt: optionalSwiftDate(page.nextTrainComesWithinTheHourAt),
    lineOfTheTrainOverAnHourAway: page.lineOfTheTrainOverAnHourAway,
    lineWithNoAnswer: page.lineWithNoAnswer,
  });
}

function encodeDirection(direction: LineDirection): Record<string, unknown> {
  return withoutUndefined({
    label: direction.label,
    trains: direction.trains.map(encodeTrain),
    nextTrainIsOverAnHourAway: direction.nextTrainIsOverAnHourAway,
    branchEnds: direction.branchEnds,
    trainsOfEachEnd: direction.trainsOfEachEnd?.map((end) => ({
      end: end.end,
      trains: end.trains.map(encodeTrain),
      nextTrainIsOverAnHourAway: end.nextTrainIsOverAnHourAway,
    })),
    noAnswer: direction.noAnswer,
  });
}

function encodeTrain(train: DirectionTrain): Record<string, unknown> {
  return withoutUndefined({
    time: swiftDate(train.time),
    destination: train.destination,
    status: train.status,
    arrivalTime: optionalSwiftDate(train.arrivalTime),
  });
}

export function swiftDate(milliseconds: number): number {
  return milliseconds / 1000 - referenceDateSeconds;
}

function optionalSwiftDate(milliseconds: number | undefined): number | undefined {
  return milliseconds === undefined ? undefined : swiftDate(milliseconds);
}

function withoutUndefined(object: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(object).filter(([, entry]) => entry !== undefined));
}
