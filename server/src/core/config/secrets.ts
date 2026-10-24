import { appTokens } from "../auth/app-tokens";
import { apnsSecretNames, type ApnsSecretName } from "../push/apns-settings";

export const secretNames = ["PRIM_API_KEY", "APP_TOKEN", "OWNER_TOKEN"] as const;

export type SecretName = (typeof secretNames)[number];

export type Secrets = Record<SecretName, string>;

/** The values to keep out of the logs: each secret, each token of the list of app tokens on its own, and each secret of Apple's push service that is set. */
export function secretValues(secrets: Partial<Secrets> & Partial<Record<ApnsSecretName, string>>): string[] {
  return [...secretNames, ...apnsSecretNames].flatMap((name) => {
    const value = secrets[name];
    if (typeof value !== "string" || value.length === 0) {
      return [];
    }
    return name === "APP_TOKEN" ? appTokens(value) : [value];
  });
}
