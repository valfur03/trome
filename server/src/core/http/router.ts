import { hasBearerToken } from "../auth/bearer-token";
import type { Logger } from "../logging/logger";
import { metricsContentType, metricsText, type MetricsSnapshot } from "../metrics/prometheus-metrics";
import type { CountsReport, RelayAnswer } from "../relay/relay";
import { isStopReference } from "../relay/stop-reference";
import type { Clock } from "../time/clock";
import { departuresResponse, errorResponse } from "./relay-responses";

export interface RelayService {
  departures(stopRef: string): Promise<RelayAnswer>;
  counts(): Promise<CountsReport>;
  metrics(): Promise<MetricsSnapshot>;
}

export interface RouterDependencies {
  logger: Logger;
  clock: Clock;
  tokens: { app: readonly string[]; owner: string };
  relay: RelayService;
}

const departuresPath = /^\/v1\/stops\/([^/]+)\/departures$/;
const countsPath = "/v1/owner/counts";
const metricsPath = "/metrics";

export async function route(request: Request, dependencies: RouterDependencies): Promise<Response> {
  const { pathname } = new URL(request.url);
  const response = await answer(request, pathname, dependencies);
  dependencies.logger.info("request", { method: request.method, route: routeName(pathname), status: response.status });
  return response;
}

async function answer(request: Request, pathname: string, dependencies: RouterDependencies): Promise<Response> {
  const { tokens, relay, clock } = dependencies;
  if (pathname === "/health") {
    return onlyGet(request) ?? Response.json({ status: "ok" });
  }

  const departures = departuresPath.exec(pathname);
  if (departures) {
    const refusal = onlyGet(request) ?? refuseWithout(request, tokens.app);
    if (refusal) {
      return refusal;
    }
    const stopRef = decoded(departures[1] ?? "");
    if (stopRef === undefined || !isStopReference(stopRef)) {
      return errorResponse(400, "bad stop reference");
    }
    return departuresResponse(await relay.departures(stopRef), clock.now());
  }

  if (pathname === countsPath) {
    return (
      onlyGet(request) ??
      refuseWithout(request, tokens.owner) ??
      Response.json(await relay.counts(), { headers: { "cache-control": "no-store" } })
    );
  }

  if (pathname === metricsPath) {
    return (
      onlyGet(request) ??
      refuseWithout(request, tokens.owner) ??
      new Response(metricsText(await relay.metrics()), {
        headers: { "content-type": metricsContentType, "cache-control": "no-store" },
      })
    );
  }

  return errorResponse(404, "not found");
}

function routeName(pathname: string): string {
  if (pathname === "/health" || pathname === countsPath || pathname === metricsPath) {
    return pathname;
  }
  return departuresPath.test(pathname) ? "/v1/stops/{stop}/departures" : "unknown";
}

function onlyGet(request: Request): Response | undefined {
  if (request.method === "GET" || request.method === "HEAD") {
    return undefined;
  }
  return errorResponse(405, "method not allowed", { allow: "GET, HEAD" });
}

function refuseWithout(request: Request, accepted: string | readonly string[]): Response | undefined {
  if (hasBearerToken(request.headers, accepted)) {
    return undefined;
  }
  return errorResponse(401, "unauthorized", { "www-authenticate": "Bearer" });
}

function decoded(segment: string): string | undefined {
  try {
    return decodeURIComponent(segment);
  } catch {
    return undefined;
  }
}
