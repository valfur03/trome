import { describe, expect, it } from "vitest";
import { secretNames, secretValues } from "../../../src/core/config/secrets";

describe("secrets", () => {
  it("names the PRIM key and the app token", () => {
    expect(secretNames).toEqual(["PRIM_API_KEY", "APP_TOKEN"]);
  });

  it("gives the values of the secrets that are set", () => {
    expect(secretValues({ PRIM_API_KEY: "prim", APP_TOKEN: "token" })).toEqual(["prim", "token"]);
  });

  it("leaves out a secret that is missing or empty", () => {
    expect(secretValues({ APP_TOKEN: "" })).toEqual([]);
  });
});
