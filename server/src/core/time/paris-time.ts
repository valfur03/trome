import { hour } from "./clock";

const parisParts = new Intl.DateTimeFormat("en-US", {
  timeZone: "Europe/Paris",
  hourCycle: "h23",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});

interface LocalTime {
  year: number;
  month: number;
  day: number;
  hour: number;
}

// The Paris clock changes only at a whole UTC hour (01:00 UTC by the EU rules), so each UTC hour has one offset.
// Intl is slow (several microseconds a call, many calls a request): ask it once per UTC hour, and keep the last answer.
let offsetUtcHour = Number.NaN;
let offsetOfThatHour = 0;

function parisOffset(at: number): number {
  const utcHour = Math.floor(at / hour);
  if (utcHour !== offsetUtcHour) {
    const start = utcHour * hour;
    const parts = Object.fromEntries(
      parisParts.formatToParts(start).map(({ type, value }) => [type, Number(value)]),
    ) as Partial<Record<Intl.DateTimeFormatPartTypes, number>>;
    offsetOfThatHour =
      Date.UTC(parts.year ?? 0, (parts.month ?? 0) - 1, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0) - start;
    offsetUtcHour = utcHour;
  }
  return offsetOfThatHour;
}

function parisTime(at: number): LocalTime {
  const local = new Date(at + parisOffset(at));
  return {
    year: local.getUTCFullYear(),
    month: local.getUTCMonth() + 1,
    day: local.getUTCDate(),
    hour: local.getUTCHours(),
  };
}

function twoDigits(value: number): string {
  return String(value).padStart(2, "0");
}

export function parisDay(at: number): string {
  const { year, month, day } = parisTime(at);
  return `${String(year)}-${twoDigits(month)}-${twoDigits(day)}`;
}

export function parisHourOfDay(at: number): number {
  return parisTime(at).hour;
}

export function parisHour(at: number): string {
  return `${twoDigits(parisHourOfDay(at))}:00`;
}

export function nextParisDayStart(at: number): number {
  const { year, month, day } = parisTime(at);
  const midnightAsUtc = Date.UTC(year, month - 1, day + 1);
  const guess = midnightAsUtc - parisOffset(midnightAsUtc);
  return midnightAsUtc - parisOffset(guess);
}
