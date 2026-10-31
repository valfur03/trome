// Reads a recorded set of promises of contracts/builds/ and judges an answer of the server as the builds of that set read it:
// byte for byte for the PRIM answer that the server passes through, and by status class, header form, key and value for the rest.
// The meaning lives in the recorded set, which never changes; this file only knows a small set of matchers.

export interface Matcher {
  is?: string | number;
  form?: string;
  oneOf?: string[];
  noneOf?: string[];
  type?: "string";
  optional?: boolean;
}

export interface PromisedAnswer {
  when: string;
  askFor: string;
  reads: string;
  prim?: string;
  requestHeaders?: Record<string, string>;
  status: { class?: string; notClass?: string; is?: number };
  headers?: Record<string, Matcher>;
  retryTime?: { header: string; headerForm: string; orBodyKey: string; bodyKeyForm: string };
  body: { primAnswer?: boolean; json?: Record<string, Matcher> };
}

export interface PromiseSet {
  description: string;
  builds: string[];
  app: { waitForOneAnswerSeconds: number; askEverySeconds: number; shortestWaitAfterAnOutAnswerSeconds: number };
  request: { method: string; path: string; headers: Record<string, string> };
  stops: { stop: string; shape: string; prim: string }[];
  answers: PromisedAnswer[];
  /** The start of the Live Activity of a station, from the first build that asks the server for it, 1.0.0 (4). */
  liveActivityStart?: StartPromises;
}

/** What a build sends to start the Live Activity of a station, and how it reads each answer; the answers use the same matchers. */
export interface StartPromises {
  app: { waitForTheAnswerSeconds: number };
  request: { method: string; path: string; headers: Record<string, string>; body: Record<string, string> };
  stations: { station: string; shape: string }[];
  startTokens: { startToken: string; shape: string }[];
  answers: PromisedAnswer[];
}

export interface Answered {
  status: number;
  headers: Headers;
  text: string;
}

const matcherKeys = new Set(["is", "form", "oneOf", "noneOf", "type", "optional"]);
const answerKeys = new Set(["when", "askFor", "reads", "prim", "requestHeaders", "status", "headers", "retryTime", "body"]);

function inClass(status: number, statusClass: string): boolean {
  if (!/^[1-5]xx$/.test(statusClass)) {
    throw new Error(`unknown status class "${statusClass}"`);
  }
  return Math.floor(status / 100) === Number(statusClass[0]);
}

function matches(value: unknown, matcher: Matcher): string | undefined {
  const unknownKeys = Object.keys(matcher).filter((key) => !matcherKeys.has(key));
  if (unknownKeys.length > 0) {
    return `the set has a matcher this check does not know: ${unknownKeys.join(", ")}`;
  }
  if (value === undefined || value === null) {
    return matcher.optional === true ? undefined : "is missing";
  }
  const shown = JSON.stringify(value);
  if (matcher.type === "string" && typeof value !== "string") {
    return `is ${shown}, not a string`;
  }
  if (matcher.is !== undefined && value !== matcher.is) {
    return `is ${shown}, not ${JSON.stringify(matcher.is)}`;
  }
  if (matcher.oneOf !== undefined && !matcher.oneOf.includes(value as string)) {
    return `is ${shown}, not one of ${JSON.stringify(matcher.oneOf)}`;
  }
  if (matcher.noneOf?.includes(value as string) === true) {
    return `is ${shown}, which these builds read another way (${JSON.stringify(matcher.noneOf)})`;
  }
  if (matcher.form !== undefined && (typeof value !== "string" || !new RegExp(matcher.form).test(value))) {
    return `is ${shown}, not in the form ${matcher.form}`;
  }
  return undefined;
}

function jsonObject(text: string): Record<string, unknown> | undefined {
  try {
    const parsed: unknown = JSON.parse(text);
    return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed) ? (parsed as Record<string, unknown>) : undefined;
  } catch {
    return undefined;
  }
}

/** The ways in which the answer differs from the promise, as the builds of the set read it; empty when it keeps it. */
export function brokenPromises(promise: PromisedAnswer, answered: Answered, primAnswer: string): string[] {
  const problems: string[] = [];
  const unknownKeys = Object.keys(promise).filter((key) => !answerKeys.has(key));
  if (unknownKeys.length > 0) {
    problems.push(`the set has a key this check does not know: ${unknownKeys.join(", ")}`);
  }
  const { status } = promise;
  if (status.is !== undefined && answered.status !== status.is) {
    problems.push(`status ${String(answered.status)}, not ${String(status.is)}`);
  }
  if (status.class !== undefined && !inClass(answered.status, status.class)) {
    problems.push(`status ${String(answered.status)}, not a ${status.class}`);
  }
  if (status.notClass !== undefined && inClass(answered.status, status.notClass)) {
    problems.push(`status ${String(answered.status)}, which these builds read as times`);
  }
  for (const [name, matcher] of Object.entries(promise.headers ?? {})) {
    const problem = matches(answered.headers.get(name) ?? undefined, matcher);
    if (problem !== undefined) {
      problems.push(`header ${name} ${problem}`);
    }
  }
  const json = promise.body.json === undefined && promise.retryTime === undefined ? undefined : jsonObject(answered.text);
  if (promise.body.primAnswer === true && answered.text !== primAnswer) {
    problems.push(
      `body is not the PRIM answer as PRIM gave it (${String(answered.text.length)} characters, PRIM gave ${String(primAnswer.length)})`,
    );
  }
  if (promise.body.json !== undefined) {
    if (json === undefined) {
      problems.push(`body is not a JSON object: ${answered.text.slice(0, 200)}`);
    } else {
      for (const [key, matcher] of Object.entries(promise.body.json)) {
        const problem = matches(json[key], matcher);
        if (problem !== undefined) {
          problems.push(`body key ${key} ${problem}`);
        }
      }
    }
  }
  if (promise.retryTime !== undefined) {
    const { header, headerForm, orBodyKey, bodyKeyForm } = promise.retryTime;
    const fromHeader = answered.headers.get(header);
    const fromBody = json?.[orBodyKey];
    const headerGivesIt = fromHeader !== null && new RegExp(headerForm).test(fromHeader);
    const bodyGivesIt = typeof fromBody === "string" && new RegExp(bodyKeyForm).test(fromBody);
    if (!headerGivesIt && !bodyGivesIt) {
      problems.push(
        `no retry time that these builds read: header ${header} is ${JSON.stringify(fromHeader)}, body key ${orBodyKey} is ${JSON.stringify(fromBody)}`,
      );
    }
  }
  return problems;
}
