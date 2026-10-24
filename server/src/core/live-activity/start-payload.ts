import { stationListOrder, type Station } from "./station-catalog";
import { encodeContent, staleDate, type StationContent } from "./station-content";

/**
 * The body of the push that starts the Live Activity of a station on an iPhone (ActivityKit's push to start).
 * iOS shows a start as one alert, so it holds one: the name of the station and its lines, with no sound and no word to translate.
 * The started Live Activity listens to the channel of the station, on which its updates come.
 */
export const attributesType = "StationActivityAttributes";

export function startPayload(station: Station, content: StationContent, channelId: string, now: number): string {
  const aps: Record<string, unknown> = {
    timestamp: Math.floor(now / 1000),
    event: "start",
    "content-state": encodeContent(content),
    "attributes-type": attributesType,
    attributes: {},
    alert: { title: station.name, body: lineNames(station) },
    "input-push-channel": channelId,
  };
  const stale = staleDate(content);
  if (stale !== undefined) {
    aps["stale-date"] = Math.floor(stale / 1000);
  }
  return JSON.stringify({ aps });
}

/** The lines of the station, as their signs read: "M4 · RER A". */
function lineNames(station: Station): string {
  return [...station.lines]
    .sort(stationListOrder)
    .map((line) => (line.mode === "metro" ? `M${line.name}` : `RER ${line.name}`))
    .join(" · ");
}
