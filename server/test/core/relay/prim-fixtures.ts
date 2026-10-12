import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const folder = fileURLToPath(new URL("../../../../contracts/prim/", import.meta.url));

export function primFixture(name: string): string {
  return readFileSync(`${folder}${name}`, "utf8");
}

export function primFixtureNames(): string[] {
  return readdirSync(folder).filter((name) => name.endsWith(".json")).sort();
}

const buildsFolder = fileURLToPath(new URL("../../../../contracts/builds/", import.meta.url));

/** Every recorded PRIM answer: those of `contracts/prim/`, and the copies that each set of promises of `contracts/builds/` keeps. */
export function everyRecordedPrimAnswer(): { name: string; body: string }[] {
  const sets = readdirSync(buildsFolder, { withFileTypes: true }).filter((entry) => entry.isDirectory());
  return [
    ...primFixtureNames().map((name) => ({ name, body: primFixture(name) })),
    ...sets.flatMap(({ name: set }) =>
      readdirSync(`${buildsFolder}${set}/prim/`)
        .filter((name) => name.endsWith(".json"))
        .sort()
        .map((name) => ({ name: `${set}/prim/${name}`, body: readFileSync(`${buildsFolder}${set}/prim/${name}`, "utf8") })),
    ),
  ];
}
