import { hour, minute } from "../../../src/core/time/clock";

export interface RiderRequest {
  at: number;
  liveActivity: number;
  stopRefs: readonly string[];
}

const stationCount = 551;
const stopAreasOfTheBusiestStations = [...Array<number>(6).fill(6), ...Array<number>(3).fill(4), ...Array<number>(6).fill(3), ...Array<number>(19).fill(2)];
const trafficSlope = 0.43;

const stations = Array.from({ length: stationCount }, (_, index) => ({
  weight: 1 / (index + 1) ** trafficSlope,
  stopRefs: Array.from(
    { length: stopAreasOfTheBusiestStations[index] ?? 1 },
    (_, area) => `STIF:StopArea:SP:${String((index + 1) * 10 + area)}:`,
  ),
}));
const totalWeight = stations.reduce((total, station) => total + station.weight, 0);
const lastStation = { weight: 0, stopRefs: [`STIF:StopArea:SP:${String(stationCount * 10)}:`] };

function seededRandom(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let mixed = Math.imul(state ^ (state >>> 15), 1 | state);
    mixed = (mixed + Math.imul(mixed ^ (mixed >>> 7), 61 | mixed)) ^ mixed;
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 2 ** 32;
  };
}

export function riderDay({ riders, parisMidnight, seed = 1 }: { riders: number; parisMidnight: number; seed?: number }): RiderRequest[] {
  const random = seededRandom(seed);
  const uniform = (low: number, high: number) => low + random() * (high - low);
  const gauss = (mean: number, deviation: number) =>
    mean + deviation * Math.sqrt(-2 * Math.log(1 - random())) * Math.cos(2 * Math.PI * random());
  const station = () => {
    let draw = random() * totalWeight;
    return stations.find((candidate) => (draw -= candidate.weight) < 0) ?? lastStation;
  };
  const startOfDay = (mean: number, deviation: number) => Math.min(Math.max(gauss(mean, deviation), 5.5 * hour), 23.5 * hour);

  const liveActivities = Array.from({ length: riders }, () => {
    const home = station();
    const work = station();
    return [
      { start: startOfDay(8.25 * hour, 45 * minute), station: home },
      { start: startOfDay(18 * hour, 60 * minute), station: work },
    ];
  }).flat();

  const requests: RiderRequest[] = [];
  liveActivities.forEach(({ start, station: { stopRefs } }, liveActivity) => {
    const end = start + uniform(6 * minute, 14 * minute);
    for (let at = start; at < end; at += uniform(minute, 2 * minute)) {
      requests.push({ at: parisMidnight + Math.round(at), liveActivity, stopRefs });
    }
  });
  return requests.sort((first, second) => first.at - second.at);
}
