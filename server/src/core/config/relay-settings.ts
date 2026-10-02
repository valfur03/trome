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
  primTimeout: number;
}

export const primQuota = 1000;

export const dayShapePercents: DayShapePercents = { 7: 15, 8: 24, 9: 8, 16: 6, 17: 17, 18: 18, 19: 7 };

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
