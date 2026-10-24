import type { RelayAnswer } from "../relay/relay";
import { stationContent, type StationContent } from "./station-content";
import { stationTrains, stopRequests } from "./station-departures";
import type { Station, StationCatalog } from "./station-catalog";

/**
 * The first content of a Live Activity of a station: the trains of the station and of the other stations of its place, from the answers that the relay gives the app for each stop.
 * It asks the relay as the app asks the departures route, so a start uses the same held answers and the same quota as an app on screen.
 */
export async function contentOfStation(
  station: Station,
  catalog: StationCatalog,
  departures: (stopRef: string) => Promise<RelayAnswer>,
  now: () => number,
): Promise<StationContent> {
  const stations = catalog.hubStations(station);
  const requests = stopRequests(stations, catalog);
  const answers = await Promise.all(requests.map(async (request) => ({ request, answer: await departures(request.monitoringRef) })));
  return stationContent(station, stations, stationTrains(stations, catalog, answers), catalog, now());
}
