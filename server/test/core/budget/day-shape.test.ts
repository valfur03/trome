import { describe, expect, it } from "vitest";
import { dayShape } from "../../../src/core/budget/day-shape";

describe("dayShape", () => {
  it("gives each Paris hour its share of the day, and shares the rest equally between the hours that it does not name", () => {
    const shape = dayShape({ 7: 15, 8: 24, 9: 8, 16: 6, 17: 17, 18: 18, 19: 7 });

    expect(shape).toHaveLength(24);
    expect(shape[7]).toBe(0.15);
    expect(shape[8]).toBe(0.24);
    expect(shape[18]).toBe(0.18);
    expect(shape[0]).toBeCloseTo(0.05 / 17, 12);
    expect(shape[23]).toBeCloseTo(0.05 / 17, 12);
    expect(shape.reduce((total, share) => total + share, 0)).toBeCloseTo(1, 12);
  });

  it("accepts a shape that names all 24 hours", () => {
    expect(dayShape(Object.fromEntries(Array.from({ length: 24 }, (_, hour) => [hour, hour < 4 ? 25 : 0])))).toEqual(
      Array.from({ length: 24 }, (_, hour) => (hour < 4 ? 0.25 : 0)),
    );
  });

  it("refuses a shape above 100%, an hour that is not from 0 to 23, a share below 0, and 24 hours that do not make 100%", () => {
    expect(() => dayShape({ 7: 60, 8: 50 })).toThrow("the hours must share 100%");
    expect(() => dayShape({ 24: 10 })).toThrow("an hour from 0 to 23");
    expect(() => dayShape({ 7.5: 10 })).toThrow("an hour from 0 to 23");
    expect(() => dayShape({ 7: -1 })).toThrow("an hour from 0 to 23");
    expect(() => dayShape(Object.fromEntries(Array.from({ length: 24 }, (_, hour) => [hour, 4])))).toThrow(
      "the hours must share 100%",
    );
  });
});
