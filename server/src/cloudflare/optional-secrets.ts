import { apnsSecretNames, type ApnsSecretName } from "../core/push/apns-settings";

/** The secrets of Apple's push service, which a deploy may not have yet: `wrangler.jsonc` does not require them, so `Env` does not name them. */
export function optionalSecrets(env: Env): Partial<Record<ApnsSecretName, string>> {
  const values = env as unknown as Record<string, unknown>;
  const secrets: Partial<Record<ApnsSecretName, string>> = {};
  for (const name of apnsSecretNames) {
    const value = values[name];
    if (typeof value === "string") {
      secrets[name] = value;
    }
  }
  return secrets;
}
