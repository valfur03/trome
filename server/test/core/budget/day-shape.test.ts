import { describe, expect, it } from "vitest";
import { dayShape } from "../../../src/core/budget/day-shape";

const allHours = (percentOf: (hour: number) => number) => Object.fromEntries(Array.from({ length: 24 }, (_, hour) => [hour, percentOf(hour)]));

describe("dayShape", () => {
  it("gives each Paris hour its share of the day, and shares the rest equally between the hours that it does not name", () => {
    const shape = dayShape({ 7: 15, 8: 20, 9: 8, 16: 6, 17: 15, 18: 18, 19: 6 });

    expect(shape).toHaveLength(24);
    expect(shape[7]).toBe(0.15);
    expect(shape[8]).toBe(0.2);
    expect(shape[18]).toBe(0.18);
    expect(shape[0]).toBeCloseTo(0.12 / 17, 12);
    expect(shape[23]).toBeCloseTo(0.12 / 17, 12);
    expect(shape.reduce((total, share) => total + share, 0)).toBeCloseTo(1, 12);
  });

  it("accepts a shape that names all 24 hours", () => {
    expect(dayShape(allHours((hour) => (hour < 4 ? 1 : 4.8)))).toEqual(Array.from({ length: 24 }, (_, hour) => (hour < 4 ? 0.01 : 0.048)));
  });

  it("refuses a shape above 100%, an hour that is not from 0 to 23, a share below 0, and 24 hours that do not make 100%", () => {
    expect(() => dayShape({ 7: 60, 8: 50 })).toThrow("the hours must share 100%");
    expect(() => dayShape({ 24: 10 })).toThrow("an hour from 0 to 23");
    expect(() => dayShape({ 7.5: 10 })).toThrow("an hour from 0 to 23");
    expect(() => dayShape({ 7: -1 })).toThrow("an hour from 0 to 23");
    expect(() => dayShape(allHours(() => 4))).toThrow("the hours must share 100%");
  });

  it("refuses an hour below 0.5%, also an hour that it does not name, so that a lone rider at night still gets a call", () => {
    const nightAndHour3 = (percent: number) => allHours((hour) => (hour < 2 ? 1 : hour === 3 ? percent : (98 - percent) / 21));
    expect(dayShape(nightAndHour3(0.5))[3]).toBe(0.005);
    expect(() => dayShape(nightAndHour3(0.4))).toThrow(
      "The day shape gives 0.4% to the hour 3: give each hour at least 0.5%",
    );
    expect(() => dayShape({ 7: 50, 8: 45 })).toThrow("give each hour at least 0.5%");
  });

  it("refuses more than 5% for the hours from 00:00 to 02:00 together, so that a PRIM day that starts at 00:00 UTC stays under its quota", () => {
    expect(dayShape(allHours((hour) => (hour < 2 ? 2.5 : 95 / 22)))[1]).toBe(0.025);
    expect(() => dayShape(allHours((hour) => (hour < 2 ? 2.6 : 94.8 / 22)))).toThrow(
      "The day shape gives 5.2% to the hours from 00:00 to 02:00: give them at most 5% together",
    );
  });
});
