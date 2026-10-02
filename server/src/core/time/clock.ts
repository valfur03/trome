export interface Clock {
  now(): number;
}

export const minute = 60_000;
export const hour = 60 * minute;
export const day = 24 * hour;
