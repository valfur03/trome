import { describe, expect, it } from "vitest";
import { hasBearerToken } from "../../../src/core/auth/bearer-token";

const headers = (authorization?: string) => new Headers(authorization === undefined ? {} : { authorization });

describe("hasBearerToken", () => {
  it("accepts the expected token in a Bearer header", () => {
    expect(hasBearerToken(headers("Bearer k+/3q="), "k+/3q=")).toBe(true);
  });

  it("refuses a missing header, another scheme, another token, a longer or a shorter token", () => {
    for (const authorization of [undefined, "", "Bearer", "Bearer ", "Basic k+/3q=", "bearer k+/3q=", "Bearer k+/3q", "Bearer k+/3q==", "Bearer x+/3q="]) {
      expect(hasBearerToken(headers(authorization), "k+/3q="), String(authorization)).toBe(false);
    }
  });

  it("refuses every token when no token is set", () => {
    expect(hasBearerToken(headers("Bearer "), "")).toBe(false);
    expect(hasBearerToken(headers("Bearer x"), "")).toBe(false);
  });
});
