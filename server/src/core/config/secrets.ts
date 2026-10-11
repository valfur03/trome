import { appTokens } from "../auth/app-tokens";

export const secretNames = ["PRIM_API_KEY", "APP_TOKEN", "OWNER_TOKEN"] as const;

export type SecretName = (typeof secretNames)[number];

export type Secrets = Record<SecretName, string>;

/** The values to keep out of the logs: each secret, and each token of the list of app tokens on its own. */
export function secretValues(secrets: Partial<Secrets>): string[] {
  return secretNames.flatMap((name) => {
    const value = secrets[name];
    if (typeof value !== "string" || value.length === 0) {
      return [];
    }
    return name === "APP_TOKEN" ? appTokens(value) : [value];
  });
}
