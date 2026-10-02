export const primEndpoint = "https://prim.iledefrance-mobilites.fr/marketplace/stop-monitoring";

export type PrimReply =
  | { kind: "answer"; status: number; body: string }
  | { kind: "unreachable"; reason: string };

export interface PrimClient {
  stopMonitoring(stopRef: string): Promise<PrimReply>;
}

export interface PrimClientOptions {
  apiKey: string;
  timeout: number;
  fetch: (url: string, init: RequestInit) => Promise<Response>;
}

export function createPrimClient({ apiKey, timeout, fetch }: PrimClientOptions): PrimClient {
  return {
    async stopMonitoring(stopRef) {
      const url = `${primEndpoint}?${new URLSearchParams({ MonitoringRef: stopRef }).toString()}`;
      const controller = new AbortController();
      const timer = setTimeout(() => {
        controller.abort(new DOMException("PRIM did not answer in time", "TimeoutError"));
      }, timeout);
      try {
        const response = await fetch(url, {
          headers: { apikey: apiKey, accept: "application/json" },
          signal: controller.signal,
        });
        return { kind: "answer", status: response.status, body: await response.text() };
      } catch (error) {
        return { kind: "unreachable", reason: error instanceof Error ? error.name : "unknown" };
      } finally {
        clearTimeout(timer);
      }
    },
  };
}
