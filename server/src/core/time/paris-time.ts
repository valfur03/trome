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
  minute: number;
  second: number;
}

function parisTime(at: number): LocalTime {
  const parts = Object.fromEntries(
    parisParts.formatToParts(at).map(({ type, value }) => [type, Number(value)]),
  ) as Partial<Record<Intl.DateTimeFormatPartTypes, number>>;
  return {
    year: parts.year ?? 0,
    month: parts.month ?? 0,
    day: parts.day ?? 0,
    hour: parts.hour ?? 0,
    minute: parts.minute ?? 0,
    second: parts.second ?? 0,
  };
}

function twoDigits(value: number): string {
  return String(value).padStart(2, "0");
}

function parisOffset(at: number): number {
  const local = parisTime(at);
  const wholeSecond = at - (((at % 1000) + 1000) % 1000);
  return (
    Date.UTC(local.year, local.month - 1, local.day, local.hour, local.minute, local.second) -
    wholeSecond
  );
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
