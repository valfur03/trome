export const secretNames = ["PRIM_API_KEY", "APP_TOKEN"] as const;

export type SecretName = (typeof secretNames)[number];

export type Secrets = Record<SecretName, string>;

export function secretValues(secrets: Partial<Secrets>): string[] {
  return secretNames
    .map((name) => secrets[name])
    .filter((value): value is string => typeof value === "string" && value.length > 0);
}
