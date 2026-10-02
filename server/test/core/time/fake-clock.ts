import type { Clock } from "../../../src/core/time/clock";

export class FakeClock implements Clock {
  constructor(private time: number) {}

  static at(iso: string): FakeClock {
    return new FakeClock(Date.parse(iso));
  }

  now(): number {
    return this.time;
  }

  advance(milliseconds: number): void {
    this.time += milliseconds;
  }

  set(iso: string): void {
    this.time = Date.parse(iso);
  }
}
