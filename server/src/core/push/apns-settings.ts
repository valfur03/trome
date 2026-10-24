/**
 * The settings of Apple's push service, from optional secrets: with none of them, the server runs as before and the start route answers that it is not set up.
 * Apple gives a token of an iPhone to one of its two push services: the production one for a TestFlight or App Store build, the development one ("sandbox") for a build that Xcode installs.
 * Since 2025, a new key works with one of them only, so each has its own key; an older key that works with both may be set for both.
 */
export const apnsSecretNames = [
  "APNS_TEAM_ID",
  "APNS_BUNDLE_ID",
  "APNS_PRODUCTION_KEY_ID",
  "APNS_PRODUCTION_KEY",
  "APNS_SANDBOX_KEY_ID",
  "APNS_SANDBOX_KEY",
] as const;

export type ApnsSecretName = (typeof apnsSecretNames)[number];

export type ApnsEnvironment = "production" | "sandbox";

export interface ApnsKey {
  environment: ApnsEnvironment;
  keyId: string;
  /** The private key of the `.p8` file of Apple: its PEM text, or only the base64 between its two lines. */
  key: string;
}

export interface ApnsSettings {
  teamId: string;
  bundleId: string;
  /** The keys to try for a token, production first: most riders hold a TestFlight or App Store build. */
  keys: ApnsKey[];
}

export const apnsHosts: Record<ApnsEnvironment, { device: string; channels: string }> = {
  production: { device: "https://api.push.apple.com", channels: "https://api-manage-broadcast.push.apple.com:2196" },
  sandbox: { device: "https://api.sandbox.push.apple.com", channels: "https://api-manage-broadcast.sandbox.push.apple.com:2195" },
};

export function apnsSettings(secrets: Partial<Record<ApnsSecretName, string>>): ApnsSettings | undefined {
  const value = (name: ApnsSecretName) => {
    const text = secrets[name]?.trim();
    return text === undefined || text.length === 0 ? undefined : text;
  };
  const teamId = value("APNS_TEAM_ID");
  const bundleId = value("APNS_BUNDLE_ID");
  const keys: ApnsKey[] = [];
  const productionKeyId = value("APNS_PRODUCTION_KEY_ID");
  const productionKey = value("APNS_PRODUCTION_KEY");
  if (productionKeyId !== undefined && productionKey !== undefined) {
    keys.push({ environment: "production", keyId: productionKeyId, key: productionKey });
  }
  const sandboxKeyId = value("APNS_SANDBOX_KEY_ID");
  const sandboxKey = value("APNS_SANDBOX_KEY");
  if (sandboxKeyId !== undefined && sandboxKey !== undefined) {
    keys.push({ environment: "sandbox", keyId: sandboxKeyId, key: sandboxKey });
  }
  if (teamId === undefined || bundleId === undefined || keys.length === 0) {
    return undefined;
  }
  return { teamId, bundleId, keys };
}
