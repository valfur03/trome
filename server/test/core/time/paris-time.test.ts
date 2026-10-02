import { describe, expect, it } from "vitest";
import { nextParisDayStart, parisDay, parisHour } from "../../../src/core/time/paris-time";

const at = (iso: string) => Date.parse(iso);

describe("Paris time", () => {
  it("gives the Paris day, which starts at 22:00 UTC in summer and 23:00 UTC in winter", () => {
    expect(parisDay(at("2026-10-02T21:59:59.999Z"))).toBe("2026-10-02");
    expect(parisDay(at("2026-10-02T22:00:00.000Z"))).toBe("2026-10-03");
    expect(parisDay(at("2026-12-31T22:59:59.999Z"))).toBe("2026-12-31");
    expect(parisDay(at("2026-12-31T23:00:00.000Z"))).toBe("2027-01-01");
  });

  it("gives the Paris hour", () => {
    expect(parisHour(at("2026-10-02T06:15:00.000Z"))).toBe("08:00");
    expect(parisHour(at("2026-12-02T06:15:00.000Z"))).toBe("07:00");
    expect(parisHour(at("2026-10-02T22:00:00.000Z"))).toBe("00:00");
  });

  it("gives the start of the next Paris day", () => {
    expect(nextParisDayStart(at("2026-10-02T08:30:00.000Z"))).toBe(at("2026-10-02T22:00:00.000Z"));
    expect(nextParisDayStart(at("2026-10-02T22:00:00.000Z"))).toBe(at("2026-10-03T22:00:00.000Z"));
    expect(nextParisDayStart(at("2026-10-02T21:59:59.999Z"))).toBe(at("2026-10-02T22:00:00.000Z"));
    expect(nextParisDayStart(at("2026-12-15T12:00:00.000Z"))).toBe(at("2026-12-15T23:00:00.000Z"));
    expect(nextParisDayStart(at("2026-12-31T23:30:00.000Z"))).toBe(at("2027-01-01T23:00:00.000Z"));
  });

  it("gives the start of the next Paris day around the changes of the clock", () => {
    expect(nextParisDayStart(at("2026-10-24T12:00:00.000Z"))).toBe(at("2026-10-24T22:00:00.000Z"));
    expect(nextParisDayStart(at("2026-10-25T12:00:00.000Z"))).toBe(at("2026-10-25T23:00:00.000Z"));
    expect(nextParisDayStart(at("2027-03-27T12:00:00.000Z"))).toBe(at("2027-03-27T23:00:00.000Z"));
    expect(nextParisDayStart(at("2027-03-28T12:00:00.000Z"))).toBe(at("2027-03-28T22:00:00.000Z"));
  });
});
