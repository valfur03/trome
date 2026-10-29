import { hour, minute } from "../../../src/core/time/clock";

export interface RiderRequest {
  at: number;
  liveActivity: number;
  stopRefs: readonly string[];
}

export const measuredStartShares: readonly number[] = [
  0.6, 0.1, 0, 0, 0.2, 1.7, 4.4, 9.4, 10.3, 6.3, 4.7, 4.7, 5.2, 5, 5, 5.6, 7.1, 8.7, 7.6, 5.2, 3.2, 2.1, 1.7, 1.3,
].map((percent) => percent / 100);

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

/** How long a Live Activity asks for times, and the wait between two asks: by default, an app on screen for 6 to 14 minutes that asks every 1 to 2 minutes. */
export interface Outing {
  length: { from: number; to: number };
  wait: { from: number; to: number };
}

const appOuting: Outing = { length: { from: 6 * minute, to: 14 * minute }, wait: { from: minute, to: 2 * minute } };

export function riderDay({
  riders,
  parisMidnight,
  startShares,
  seed = 1,
  outing = appOuting,
}: {
  riders: number;
  parisMidnight: number;
  startShares: readonly number[];
  seed?: number;
  outing?: Outing;
}): RiderRequest[] {
  const random = seededRandom(seed);
  const uniform = (low: number, high: number) => low + random() * (high - low);
  const station = () => {
    let draw = random() * totalWeight;
    return stations.find((candidate) => (draw -= candidate.weight) < 0) ?? lastStation;
  };
  const sharesTotal = startShares.reduce((total, share) => total + share, 0);
  const start = () => {
    let draw = random() * sharesTotal;
    const parisHour = startShares.findIndex((share) => (draw -= share) < 0);
    return (parisHour === -1 ? startShares.length - 1 : parisHour) * hour + random() * hour;
  };

  const liveActivities = Array.from({ length: riders }, () => [
    { start: start(), station: station() },
    { start: start(), station: station() },
  ]).flat();

  const requests: RiderRequest[] = [];
  liveActivities.forEach(({ start: startAt, station: { stopRefs } }, liveActivity) => {
    const end = Math.min(startAt + uniform(outing.length.from, outing.length.to), 24 * hour);
    for (let at = startAt; at < end; at += uniform(outing.wait.from, outing.wait.to)) {
      requests.push({ at: parisMidnight + Math.floor(at), liveActivity, stopRefs });
    }
  });
  return requests.sort((first, second) => first.at - second.at);
}
