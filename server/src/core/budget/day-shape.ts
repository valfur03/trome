export type DayShapePercents = Readonly<Partial<Record<number, number>>>;

export const hoursOfADay = 24;
export const smallestHourPercent = 0.5;
export const nightHours: readonly number[] = [0, 1];
export const largestNightPercent = 5;

export function dayShape(percents: DayShapePercents): number[] {
  const named = Object.entries(percents).map(([hour, percent]) => [Number(hour), percent ?? Number.NaN] as const);
  for (const [hour, percent] of named) {
    if (!Number.isInteger(hour) || hour < 0 || hour >= hoursOfADay || !(percent >= 0)) {
      throw new Error(`The day shape gives ${String(percent)}% to the hour ${String(hour)}: give 0% or more to an hour from 0 to 23.`);
    }
  }
  const namedTotal = named.reduce((total, [, percent]) => total + percent, 0);
  const others = hoursOfADay - named.length;
  const rest = others === 0 ? 0 : (100 - namedTotal) / others;
  if (namedTotal > 100 + 1e-9 || (others === 0 && Math.abs(namedTotal - 100) > 1e-9)) {
    throw new Error(`The day shape gives ${String(namedTotal)}% of the day: the hours must share 100%.`);
  }
  const shape = Array.from({ length: hoursOfADay }, (_, hour) => percents[hour] ?? rest);
  shape.forEach((percent, hour) => {
    if (percent < smallestHourPercent - 1e-9) {
      throw new Error(
        `The day shape gives ${String(percent)}% to the hour ${String(hour)}: give each hour at least ${String(smallestHourPercent)}%, so that a lone rider still gets a call.`,
      );
    }
  });
  const night = nightHours.reduce((total, hour) => total + (shape[hour] ?? 0), 0);
  if (night > largestNightPercent + 1e-9) {
    throw new Error(
      `The day shape gives ${String(night)}% to the hours from 00:00 to 02:00: give them at most ${String(largestNightPercent)}% together, so that a PRIM day that starts at 00:00 UTC stays under its quota.`,
    );
  }
  return shape.map((percent) => percent / 100);
}
