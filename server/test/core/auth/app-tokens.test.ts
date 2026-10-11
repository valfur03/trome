import { describe, expect, it } from "vitest";
import { appTokens } from "../../../src/core/auth/app-tokens";

describe("appTokens", () => {
  it("reads a secret of one token as a list of one, as the secret was before the list", () => {
    expect(appTokens("4f1c9a")).toEqual(["4f1c9a"]);
  });

  it("reads tokens separated by commas, with or without spaces around them", () => {
    for (const secret of ["4f1c9a,b72e05", "4f1c9a, b72e05", " 4f1c9a ,b72e05 ", "4f1c9a b72e05", "4f1c9a,,b72e05,"]) {
      expect(appTokens(secret), secret).toEqual(["4f1c9a", "b72e05"]);
    }
  });

  it("gives no token for a missing, empty or blank secret", () => {
    for (const secret of [undefined, "", " ", ",", " , "]) {
      expect(appTokens(secret), String(secret)).toEqual([]);
    }
  });
});
