import { encodeContent, staleDate, type StationContent } from "./station-content";

/** Apple's limit for the body of a push on a broadcast channel: 5 KB, counted in bytes of UTF-8. */
export const broadcastSizeLimit = 5120;

/**
 * The body of the push that updates the Live Activities of a station on its channel: the new content, with no alert, so that the rider notices nothing but the minutes.
 * The content shows the first page, as at the start, and carries the other pages that fit Apple's limit, so that a rider who tapped to another line keeps it (`withThePagesThatFit`).
 * The stale date is the one of the content, as when the app sends it, but never after the end of the window of updates: see `windowStaleDate`.
 */
export function updatePayload(content: StationContent, now: number, windowEnd: number): string {
  return withThePagesThatFit(content, broadcastSizeLimit, (fitting) => {
    const aps: Record<string, unknown> = {
      timestamp: Math.floor(now / 1000),
      event: "update",
      "content-state": encodeContent(fitting),
    };
    aps["stale-date"] = Math.floor(windowStaleDate(fitting, windowEnd) / 1000);
    return JSON.stringify({ aps });
  });
}

/**
 * The body that `payloadOf` makes from the content with the most pages that keep it within `limit` bytes: all of them, or the first ones in the order of the app.
 * One push goes to every rider of the station, and each lock screen draws the page that its rider tapped to when the push carries it, and the first page when it does not.
 * At the busiest hour, the pages of the biggest places (Saint-Lazare, Châtelet, Gare du Nord) do not all fit, so a rider there can reach only the first ones until the app has trains of its own.
 * When even the first page alone is over the limit, the body is still over it, and the caller does not send it.
 */
export function withThePagesThatFit(content: StationContent, limit: number, payloadOf: (content: StationContent) => string): string {
  let fitting = content;
  let payload = payloadOf(fitting);
  while (payloadBytes(payload) > limit && fitting.trains.kind === "lines" && fitting.trains.page.pages !== undefined) {
    const { pages, ...page } = fitting.trains.page;
    const fewer = pages.slice(0, -1);
    fitting = { ...fitting, trains: { kind: "lines", page: fewer.length > 1 ? { ...page, pages: fewer } : page } };
    payload = payloadOf(fitting);
  }
  return payload;
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
