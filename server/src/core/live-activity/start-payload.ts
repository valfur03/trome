import { stationListOrder, type Station } from "./station-catalog";
import { encodeContent, type StationContent } from "./station-content";
import { windowStaleDate, withThePagesThatFit } from "./update-payload";

/**
 * The body of the push that starts the Live Activity of a station on an iPhone (ActivityKit's push to start).
 * iOS shows a start as one alert, so it holds one: the name of the station and its lines, with no sound and no word to translate.
 * The started Live Activity listens to the channel of the station, on which its updates come until `windowEnd`, its latest stale date.
 * Like an update, it carries the other pages that fit, so that a tap before the first update shows the next line.
 */
export const attributesType = "StationActivityAttributes";

/** Apple's limit for the body of a push to one iPhone, the start included: 4 KB, counted in bytes of UTF-8. */
export const startSizeLimit = 4096;

export function startPayload(station: Station, content: StationContent, channelId: string, now: number, windowEnd: number): string {
  return withThePagesThatFit(content, startSizeLimit, (fitting) => {
    const aps: Record<string, unknown> = {
      timestamp: Math.floor(now / 1000),
      event: "start",
      "content-state": encodeContent(fitting),
      "attributes-type": attributesType,
      attributes: {},
      alert: { title: station.name, body: lineNames(station) },
      "input-push-channel": channelId,
      "stale-date": Math.floor(windowStaleDate(fitting, windowEnd) / 1000),
    };
    return JSON.stringify({ aps });
  });
}

/** The lines of the station, as their signs read: "M4 · RER A". */
function lineNames(station: Station): string {
  return [...station.lines]
    .sort(stationListOrder)
    .map((line) => (line.mode === "metro" ? `M${line.name}` : `RER ${line.name}`))
    .join(" · ");
}
