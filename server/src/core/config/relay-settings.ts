import { hour, minute } from "../time/clock";

export interface RelaySettings {
  dailyCap: number;
  freshAge: number;
  heldAge: number;
  pauseAfterLimit: number;
  pauseAfterFailure: number;
  primTimeout: number;
}

export const primQuota = 1000;

export function relaySettings(vars: { PRIM_DAILY_CAP?: string }): RelaySettings {
  return {
    dailyCap: dailyCap(vars.PRIM_DAILY_CAP),
    freshAge: minute,
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
