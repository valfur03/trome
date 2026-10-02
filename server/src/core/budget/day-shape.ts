export type DayShapePercents = Readonly<Partial<Record<number, number>>>;

export const hoursOfADay = 24;

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
  return Array.from({ length: hoursOfADay }, (_, hour) => (percents[hour] ?? rest) / 100);
}
