import { env } from "cloudflare:workers";
import { appTokens } from "../../src/core/auth/app-tokens";
import type { PromiseSet } from "./build-promises";

// The recorded sets of promises of contracts/builds/, each with its folder and a reader of its own files.

const files = import.meta.glob<string>("../../../contracts/builds/*/**/*.json", { eager: true, query: "?raw", import: "default" });
const setFolder = /^\.\.\/\.\.\/\.\.\/contracts\/builds\/([^/]+)\//;

export interface RecordedSet {
  folder: string;
  set: PromiseSet;
  file: (path: string) => string;
}

export function recordedSets(): RecordedSet[] {
  const folders = [...new Set(Object.keys(files).map((path) => setFolder.exec(path)?.[1] ?? ""))].filter(Boolean).sort();
  return folders.map((folder) => {
    const file = (path: string): string => {
      const text = files[`../../../contracts/builds/${folder}/${path}`];
      if (text === undefined) {
        throw new Error(`contracts/builds/${folder}/ has no ${path}`);
      }
      return text;
    };
    return { folder, set: JSON.parse(file("promises.json")) as PromiseSet, file };
  });
}

const placeholders: Record<string, string> = {
  "<APP_TOKEN>": appTokens(env.APP_TOKEN)[0] ?? "",
  "<A_TOKEN_THAT_THE_SERVER_DOES_NOT_ACCEPT>": "0f0e0d0c0b0a09080706050403020100",
};

/** A text of a set with each of its placeholders filled with the value of the test server. */
export function filled(text: string): string {
  return text.replace(/<[A-Z_]+>/g, (placeholder) => {
    const value = placeholders[placeholder];
    if (value === undefined) {
      throw new Error(`the set has a placeholder this check does not know: ${placeholder}`);
    }
    return value;
  });
}
