import { readFileSync } from "node:fs";
import ts from "typescript";

interface SecretsConfig {
  secrets?: { required?: string[] };
  env?: Record<string, SecretsConfig>;
}

const [command, target = "production"] = process.argv.slice(2);
const configPath = new URL("../wrangler.jsonc", import.meta.url).pathname;

function requiredSecrets(): string[] {
  const parsed = ts.parseConfigFileTextToJson(configPath, readFileSync(configPath, "utf8"));
  if (parsed.error) {
    throw new Error(`Cannot read ${configPath}`);
  }
  const config = parsed.config as SecretsConfig;
  const environment = target === "staging" ? config.env?.staging : config;
  return environment?.secrets?.required ?? [];
}

function listedNames(text: string): unknown[] {
  try {
    const listed: unknown = JSON.parse(text);
    return Array.isArray(listed)
      ? listed.map((secret: unknown) =>
          typeof secret === "object" && secret !== null && "name" in secret ? secret.name : null,
        )
      : [];
  } catch {
    return [];
  }
}

if (command === "required") {
  console.log(requiredSecrets().join("\n"));
} else if (command === "missing") {
  const listed = listedNames(readFileSync(0, "utf8"));
  console.log(requiredSecrets().filter((name) => !listed.includes(name)).join("\n"));
} else {
  console.error("Usage: node scripts/secrets.ts required|missing [production|staging]");
  process.exit(1);
}
