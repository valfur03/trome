import { vi } from "vitest";
import { primEndpoint } from "../../src/core/relay/prim-client";

const recorded = import.meta.glob<string>("../../../contracts/prim/*.json", {
  eager: true,
  query: "?raw",
  import: "default",
});

export function recordedAnswer(name: string): string {
  const answer = recorded[`../../../contracts/prim/${name}`];
  if (answer === undefined) {
    throw new Error(`No recorded PRIM answer ${name}`);
  }
  return answer;
}

export interface FakePrim {
  calls: URL[];
  keys: (string | null)[];
  release(): void;
}

export function fakePrim(reply: () => Response = () => new Response(recordedAnswer("stop-monitoring-abbesses-stop-area.json")), { wait = false } = {}): FakePrim {
  const calls: URL[] = [];
  const keys: (string | null)[] = [];
  let open: () => void = () => undefined;
  let gate = new Promise<void>((resolve) => {
    open = resolve;
  });
  vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    if (`${url.origin}${url.pathname}` !== primEndpoint) {
      return Promise.reject(new Error(`No network in the tests: ${url.origin}`));
    }
    calls.push(url);
    keys.push(new Headers(init?.headers).get("apikey"));
    if (!wait) {
      return Promise.resolve(reply());
    }
    return gate.then(reply);
  });
  return {
    calls,
    keys,
    release: () => {
      open();
      gate = Promise.resolve();
    },
  };
}
