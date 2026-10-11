import { describe, expect, it } from "vitest";
import { hasBearerToken } from "../../../src/core/auth/bearer-token";

const headers = (authorization?: string) => new Headers(authorization === undefined ? {} : { authorization });

describe("hasBearerToken", () => {
  it("accepts the expected token in a Bearer header", () => {
    expect(hasBearerToken(headers("Bearer k+/3q="), "k+/3q=")).toBe(true);
    expect(hasBearerToken(headers("Bearer k+/3q="), ["k+/3q="])).toBe(true);
  });

  it("refuses a missing header, another scheme, another token, a longer or a shorter token", () => {
    for (const authorization of [undefined, "", "Bearer", "Bearer ", "Basic k+/3q=", "bearer k+/3q=", "Bearer k+/3q", "Bearer k+/3q==", "Bearer x+/3q="]) {
      expect(hasBearerToken(headers(authorization), "k+/3q="), String(authorization)).toBe(false);
    }
  });

  it("refuses every token when no token is set", () => {
    for (const accepted of ["", [], [""]]) {
      expect(hasBearerToken(headers("Bearer "), accepted)).toBe(false);
      expect(hasBearerToken(headers("Bearer x"), accepted)).toBe(false);
    }
  });

  describe("with a list of tokens", () => {
    const accepted = ["4f1c9aold", "b72e05new"];

    it("accepts each token of the list", () => {
      expect(hasBearerToken(headers("Bearer 4f1c9aold"), accepted)).toBe(true);
      expect(hasBearerToken(headers("Bearer b72e05new"), accepted)).toBe(true);
    });

    it("refuses a wrong token, a token of the list in another case or with a space, and the whole list", () => {
      // Headers drops the spaces at the two ends of a value, so a space shows only inside it, or before the token after "Bearer ".
      for (const authorization of [
        "Bearer c0ffee",
        "Bearer 4F1C9AOLD",
        "Bearer B72e05new",
        "Bearer  4f1c9aold",
        "Bearer b72e05 new",
        "Bearer 4f1c9aold,b72e05new",
        "Bearer 4f1c9aold b72e05new",
      ]) {
        expect(hasBearerToken(headers(authorization), accepted), authorization).toBe(false);
      }
    });
  });
});
