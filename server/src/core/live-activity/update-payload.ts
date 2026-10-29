import { encodeContent, staleDate, type StationContent } from "./station-content";

/** Apple's limit for the body of a push on a broadcast channel: 5 KB, counted in bytes of UTF-8. */
export const broadcastSizeLimit = 5120;

/**
 * The body of the push that updates the Live Activities of a station on its channel: the new content, with no alert, so that the rider notices nothing but the minutes.
 * The content holds one page, the first line of the station, as at the start: the lock screen shows one page at a time, and the content of every page of Châtelet is over Apple's limit.
 * The stale date is the one of the content, as when the app sends it, but never after the end of the window of updates: see `windowStaleDate`.
 */
export function updatePayload(content: StationContent, now: number, windowEnd: number): string {
  const aps: Record<string, unknown> = {
    timestamp: Math.floor(now / 1000),
    event: "update",
    "content-state": encodeContent(content),
  };
  aps["stale-date"] = Math.floor(windowStaleDate(content, windowEnd) / 1000);
  return JSON.stringify({ aps });
}

/**
 * The stale date of a push that the server sends: the one of the content (kept times that are marked stale keep their date, which is past), and at the latest the end of the window of updates.
 * After the window no update comes, so the lock screen reads old from that moment, never as current: a content with no stale date ("No trains", "Times unavailable") would otherwise stay as it is with no end, and a far train could leave earlier than shown.
 */
export function windowStaleDate(content: StationContent, windowEnd: number): number {
  return Math.min(staleDate(content) ?? Number.POSITIVE_INFINITY, windowEnd);
}

export function payloadBytes(payload: string): number {
  return new TextEncoder().encode(payload).length;
}
