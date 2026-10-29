import { encodeContent, staleDate, type StationContent } from "./station-content";

/** Apple's limit for the body of a push on a broadcast channel: 5 KB, counted in bytes of UTF-8. */
export const broadcastSizeLimit = 5120;

/**
 * The body of the push that updates the Live Activities of a station on its channel: the new content, with no alert, so that the rider notices nothing but the minutes.
 * The content holds one page, the first line of the station, as at the start: the lock screen shows one page at a time, and the content of every page of Châtelet is over Apple's limit.
 * The stale date is the one of the content, as when the app sends it; kept times that are marked stale keep their date, which is past.
 */
export function updatePayload(content: StationContent, now: number): string {
  const aps: Record<string, unknown> = {
    timestamp: Math.floor(now / 1000),
    event: "update",
    "content-state": encodeContent(content),
  };
  const stale = staleDate(content);
  if (stale !== undefined) {
    aps["stale-date"] = Math.floor(stale / 1000);
  }
  return JSON.stringify({ aps });
}

export function payloadBytes(payload: string): number {
  return new TextEncoder().encode(payload).length;
}
