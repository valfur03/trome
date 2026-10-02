import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const folder = fileURLToPath(new URL("../../../../contracts/prim/", import.meta.url));

export function primFixture(name: string): string {
  return readFileSync(`${folder}${name}`, "utf8");
}

export function primFixtureNames(): string[] {
  return readdirSync(folder).filter((name) => name.endsWith(".json")).sort();
}
