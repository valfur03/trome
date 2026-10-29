import type { RelayAnswer } from "../relay/relay";
import { stationContent, type StationContent } from "./station-content";
import { stationTrains, stopRequests, type StationTrains } from "./station-departures";
import type { Station, StationCatalog } from "./station-catalog";

/** The trains of a station and of the other stations of its place, and, when the server is out for every stop, the latest time at which it asks PRIM again. */
export interface StationReading {
  stations: Station[];
  trains: StationTrains;
  retryAt?: number;
}

/**
 * Asks the relay for each stop of the station and of the other stations of its place, as the app asks the departures route, so that a start or an update uses the same held answers and the same quota as an app on screen.
 */
export async function readStation(
  station: Station,
  catalog: StationCatalog,
  departures: (stopRef: string) => Promise<RelayAnswer>,
): Promise<StationReading> {
  const stations = catalog.hubStations(station);
  const requests = stopRequests(stations, catalog);
  const answers = await Promise.all(requests.map(async (request) => ({ request, answer: await departures(request.monitoringRef) })));
  const trains = stationTrains(stations, catalog, answers);
  const reading: StationReading = { stations, trains };
  if (trains.kind === "failed" && trains.serverIsOut) {
    // The app waits for the latest time of the stops that are out, and asks them all then (`serverRetryAt`).
    const retryTimes = answers.flatMap(({ answer }) => (answer.kind === "out" && answer.reason !== "prim-failure" ? [answer.retryAt] : []));
    if (retryTimes.length > 0) {
      reading.retryAt = Math.max(...retryTimes);
    }
  }
  return reading;
}

/** The first content of a Live Activity of a station: the content that the app would show from the same answers. */
export async function contentOfStation(
  station: Station,
  catalog: StationCatalog,
  departures: (stopRef: string) => Promise<RelayAnswer>,
  now: () => number,
): Promise<StationContent> {
  const reading = await readStation(station, catalog, departures);
  return stationContent(station, reading.stations, reading.trains, catalog, now());
}
