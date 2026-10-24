import { describe, expect, it } from "vitest";
import { apnsSettings } from "../../../src/core/push/apns-settings";

const both = {
  APNS_TEAM_ID: "TEAMID1234",
  APNS_BUNDLE_ID: "com.example.trains",
  APNS_PRODUCTION_KEY_ID: "PRODKEY123",
  APNS_PRODUCTION_KEY: "production-key",
  APNS_SANDBOX_KEY_ID: "SANDKEY123",
  APNS_SANDBOX_KEY: "sandbox-key",
};

describe("the settings of Apple's push service", () => {
  it("try the production service first, then the development one", () => {
    expect(apnsSettings(both)?.keys.map((key) => key.environment)).toEqual(["production", "sandbox"]);
  });

  it("use only a service whose key and key id are both set", () => {
    expect(apnsSettings({ ...both, APNS_SANDBOX_KEY: " " })?.keys.map((key) => key.environment)).toEqual(["production"]);
    expect(apnsSettings({ ...both, APNS_PRODUCTION_KEY_ID: "" })?.keys.map((key) => key.environment)).toEqual(["sandbox"]);
  });

  it("are not set up with no key, no team or no app", () => {
    expect(apnsSettings({})).toBeUndefined();
    expect(apnsSettings({ ...both, APNS_PRODUCTION_KEY: "", APNS_SANDBOX_KEY: "" })).toBeUndefined();
    expect(apnsSettings({ ...both, APNS_TEAM_ID: "" })).toBeUndefined();
    expect(apnsSettings(Object.fromEntries(Object.entries(both).filter(([name]) => name !== "APNS_BUNDLE_ID")))).toBeUndefined();
  });
});
