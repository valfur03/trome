import { dayShape, type DayShapePercents } from "../budget/day-shape";
import { hour, minute } from "../time/clock";

export interface AgedAnswerStep {
  spentOver: number;
  age: number;
}

export interface RelaySettings {
  dailyCap: number;
  dayShape: readonly number[];
  freshAge: number;
  agedAnswers: readonly AgedAnswerStep[];
  startAge: number;
  startReserve: number;
  heldAge: number;
  pauseAfterLimit: number;
  pauseAfterFailure: number;
  retrySpread: number;
  primTimeout: number;
}

export const primQuota = 1000;

export const dayShapePercents: DayShapePercents = {
  0: 0.6, 1: 0.5, 2: 0.5, 3: 0.5, 4: 0.5, 5: 1.7, 6: 4.3, 7: 9.2, 8: 10.2, 9: 6.1, 10: 4.6, 11: 4.6,
  12: 5.1, 13: 4.9, 14: 4.9, 15: 5.5, 16: 7, 17: 8.5, 18: 7.5, 19: 5.1, 20: 3.2, 21: 2.1, 22: 1.7, 23: 1.2,
};

export function relaySettings(vars: { PRIM_DAILY_CAP?: string }): RelaySettings {
  return {
    dailyCap: dailyCap(vars.PRIM_DAILY_CAP),
    dayShape: dayShape(dayShapePercents),
    freshAge: minute,
    agedAnswers: [
      { spentOver: 0.7, age: 2 * minute },
      { spentOver: 0.9, age: 5 * minute },
    ],
    startAge: 10 * minute,
    startReserve: 0.05,
    heldAge: 5 * minute,
    pauseAfterLimit: hour,
    pauseAfterFailure: minute,
    retrySpread: minute,
    primTimeout: 10_000,
  };
}

function dailyCap(value: string | undefined): number {
  const cap = Number(value);
  if (!/^\d+$/.test(value ?? "") || cap < 1 || cap > primQuota) {
    throw new Error(
      `PRIM_DAILY_CAP must be a whole number from 1 to ${String(primQuota)}, the PRIM quota of a day.`,
    );
  }
  return cap;
}
