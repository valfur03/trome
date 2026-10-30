import { encodeContent, staleDate, type StationContent } from "./station-content";

/** Apple's limit for the body of a push on a broadcast channel: 5 KB, counted in bytes of UTF-8. */
export const broadcastSizeLimit = 5120;

/**
 * Apple's limit for the content of a Live Activity, in every push and every update of the app: 4 KB, whatever the limit of the push that brings it.
 * An iPhone refuses a bigger content and keeps the old one, so the lock screen goes stale.
 * The limit here keeps 64 bytes of it for what the iPhone's own encoding may add: the longer digits of a date in fractions of a second.
 */
export const contentSizeLimit = 4096 - 64;

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
 * The body that `payloadOf` makes from the content with the most pages that keep it within `limit` bytes, and its content within `contentSizeLimit` whichever carried page it shows: all of them, or the first ones in the order of the app.
 * One push goes to every rider of the station, and each lock screen draws the page that its rider tapped to when the push carries it, and the first page when it does not.
 * After a tap with no trains of its own, the app sends the content of the push on the tapped page, so that content must fit Apple's limit too.
 * At the busiest hour, the pages of the biggest places do not all fit, so a rider there can reach only the first ones until the app has trains of its own.
 * When even the first page alone is over the limit, the body is still over it, and the caller does not send it.
 */
export function withThePagesThatFit(content: StationContent, limit: number, payloadOf: (content: StationContent) => string): string {
  let fitting = content;
  let payload = payloadOf(fitting);
  while (
    (payloadBytes(payload) > limit || widestContentBytes(fitting) > contentSizeLimit) &&
    fitting.trains.kind === "lines" &&
    fitting.trains.page.pages !== undefined
  ) {
    const { pages, ...page } = fitting.trains.page;
    const fewer = pages.slice(0, -1);
    fitting = { ...fitting, trains: { kind: "lines", page: fewer.length > 1 ? { ...page, pages: fewer } : page } };
    payload = payloadOf(fitting);
  }
  return payload;
}

/** The bytes of the content as an iPhone receives it, on the biggest of the pages that it carries: the page that a tap may show in place of the first. */
export function widestContentBytes(content: StationContent): number {
  const bytes = (shown: StationContent) => payloadBytes(JSON.stringify(encodeContent(shown)));
  const page = content.trains.kind === "lines" ? content.trains.page : undefined;
  if (page?.pages === undefined) {
    return bytes(content);
  }
  return Math.max(...page.pages.map((line, index) => bytes({ ...content, trains: { kind: "lines", page: { ...page, lines: [line], firstIndex: index } } })));
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
