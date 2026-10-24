import { readFileSync } from "node:fs";
import ts from "typescript";
import { describe, expect, it } from "vitest";
import { secretNames, secretValues } from "../../../src/core/config/secrets";
import { apnsSecretNames } from "../../../src/core/push/apns-settings";

interface WranglerSecrets {
  secrets?: { required?: string[] };
  env?: { staging?: { secrets?: { required?: string[] } } };
}

function wranglerConfig(): WranglerSecrets {
  const path = new URL("../../../wrangler.jsonc", import.meta.url).pathname;
  return ts.parseConfigFileTextToJson(path, readFileSync(path, "utf8")).config as WranglerSecrets;
}

describe("secrets", () => {
  it("names the PRIM key, the app token and the owner token", () => {
    expect(secretNames).toEqual(["PRIM_API_KEY", "APP_TOKEN", "OWNER_TOKEN"]);
  });

  it("are the required secrets of wrangler.jsonc, for production and for staging", () => {
    const config = wranglerConfig();

    expect(config.secrets?.required).toEqual([...secretNames]);
    expect(config.env?.staging?.secrets?.required).toEqual([...secretNames]);
  });

  it("gives the values of the secrets that are set", () => {
    expect(secretValues({ PRIM_API_KEY: "prim", APP_TOKEN: "token" })).toEqual(["prim", "token"]);
  });

  it("gives each token of a list of app tokens on its own, so that the logs hide each of them", () => {
    expect(secretValues({ APP_TOKEN: "old-token, new-token", OWNER_TOKEN: "owner" })).toEqual(["old-token", "new-token", "owner"]);
  });

  it("leaves out a secret that is missing or empty", () => {
    expect(secretValues({ APP_TOKEN: "" })).toEqual([]);
  });

  it("hides the secrets of Apple's push service, which no deploy requires, so that a deploy before they are set still works", () => {
    const config = wranglerConfig();

    expect(secretValues({ APNS_PRODUCTION_KEY: "production-key", APNS_TEAM_ID: "team" })).toEqual(["team", "production-key"]);
    for (const name of apnsSecretNames) {
      expect(config.secrets?.required).not.toContain(name);
    }
  });
});
