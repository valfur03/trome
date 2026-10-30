import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { secretValues } from "../../../src/core/config/secrets";
import { createStartKeys, LiveActivityStarts } from "../../../src/core/live-activity/live-activity-starts";
import { StationCatalog } from "../../../src/core/live-activity/station-catalog";
import { createLogger } from "../../../src/core/logging/logger";
import { createApnsClient } from "../../../src/core/push/apns-client";
import type { ApnsSettings } from "../../../src/core/push/apns-settings";
import { ProviderTokens } from "../../../src/core/push/provider-token";
import { FakeApple, testApnsSettings } from "../push/fake-apple";
import { primFixture } from "../relay/prim-fixtures";
import { relayHarness } from "../relay/relay-harness";

export const catalog = StationCatalog.bundled();

export interface ContractCase {
  station: string;
  now: string;
  answers: Record<string, { prim?: string }>;
}

export function contractCase(name: string): ContractCase {
  return JSON.parse(readFileSync(fileURLToPath(new URL(`../../../../contracts/live-activity/cases/${name}.json`, import.meta.url)), "utf8")) as ContractCase;
}

/** PRIM answers each stop as a case of `contracts/live-activity/cases/` says, at the time of the case, so that the content holds real trains. */
export function answerAsCase(relay: ReturnType<typeof relayHarness>, name: string): void {
  const recorded = contractCase(name);
  relay.clock.set(recorded.now);
  relay.prim.answerWith((stopRef) => {
    const prim = recorded.answers[stopRef]?.prim;
    return prim === undefined ? { kind: "unreachable", reason: "test" } : { kind: "answer", status: 200, body: primFixture(`${prim}.json`) };
  });
}

export async function startHarness(options: { settings?: ApnsSettings | "none"; contractCase?: string } = {}) {
  const relay = relayHarness();
  answerAsCase(relay, options.contractCase ?? "abbesses");
  const apple = new FakeApple();
  const generated = await testApnsSettings();
  const settings = options.settings === "none" ? undefined : (options.settings ?? generated.settings);
  const logLines: string[] = [];
  const logger = createLogger(
    secretValues({
      APNS_PRODUCTION_KEY: generated.settings.keys[0]?.key ?? "",
      APNS_SANDBOX_KEY: generated.settings.keys[1]?.key ?? "",
    }),
    (line) => logLines.push(line),
  );
  const starts = new LiveActivityStarts({
    settings,
    apns: createApnsClient({
      fetch: apple.fetch,
      tokens: new ProviderTokens(settings?.teamId ?? "", relay.clock),
      bundleId: settings?.bundleId ?? "",
    }),
    catalog,
    departures: (stopRef) => relay.relay.departures(stopRef),
    clock: relay.clock,
    logger,
    startKey: createStartKeys(),
    counts: relay.usage,
  });
  return { relay, apple, starts, logLines, publicKeys: generated.publicKeys, settings: generated.settings };
}

