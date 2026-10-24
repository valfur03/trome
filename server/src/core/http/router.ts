import { hasBearerToken } from "../auth/bearer-token";
import type { StartResult } from "../live-activity/live-activity-starts";
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

export interface LiveActivityService {
  start(stationId: string, startToken: string): Promise<StartResult>;
}

export interface RouterDependencies {
  logger: Logger;
  clock: Clock;
  tokens: { app: readonly string[]; owner: string };
  relay: RelayService;
  liveActivities: LiveActivityService;
}

const departuresPath = /^\/v1\/stops\/([^/]+)\/departures$/;
const liveActivityPath = /^\/v1\/stations\/([^/]+)\/live-activity$/;
const countsPath = "/v1/owner/counts";
const metricsPath = "/metrics";

export async function route(request: Request, dependencies: RouterDependencies): Promise<Response> {
  const { pathname } = new URL(request.url);
  const response = await answer(request, pathname, dependencies);
  dependencies.logger.info("request", { method: request.method, route: routeName(pathname), status: response.status });
  return response;
}

async function answer(request: Request, pathname: string, dependencies: RouterDependencies): Promise<Response> {
  const { tokens, relay, clock, liveActivities } = dependencies;
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

  const liveActivity = liveActivityPath.exec(pathname);
  if (liveActivity) {
    const refusal = onlyPost(request) ?? refuseWithout(request, tokens.app);
    if (refusal) {
      return refusal;
    }
    const stationId = decoded(liveActivity[1] ?? "");
    const startToken = await startTokenOf(request);
    if (stationId === undefined || !stationIdShape.test(stationId) || startToken === undefined) {
      return errorResponse(400, "bad request");
    }
    return startResponse(await liveActivities.start(stationId, startToken));
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
  if (liveActivityPath.test(pathname)) {
    return "/v1/stations/{station}/live-activity";
  }
  return departuresPath.test(pathname) ? "/v1/stops/{stop}/departures" : "unknown";
}

/** A station id of the app's list, such as `IDFM:22059` or `IDFM:monomodalStopPlace:45102`. */
const stationIdShape = /^[A-Za-z0-9:._-]{1,100}$/;
/** A push token of ActivityKit: hexadecimal, much shorter than this limit. */
const startTokenShape = /^[0-9a-fA-F]{16,1024}$/;
const largestStartBody = 4096;

/** The start token of the body, `{"startToken": "<hex>"}`, read only when the body is small. */
async function startTokenOf(request: Request): Promise<string | undefined> {
  let text: string;
  try {
    text = await request.text();
  } catch {
    return undefined;
  }
  if (text.length > largestStartBody) {
    return undefined;
  }
  try {
    const body: unknown = JSON.parse(text);
    if (typeof body === "object" && body !== null && "startToken" in body && typeof body.startToken === "string") {
      return startTokenShape.test(body.startToken) ? body.startToken : undefined;
    }
  } catch {
    return undefined;
  }
  return undefined;
}

/**
 * The answer of a start, in a few words that the app reads: "started" and "already-started" end its work, and the app falls back from the others.
 * Each status says the same for a reader that does not read the body: 200 done, 502 refused by Apple, 503 not set up.
 */
function startResponse(result: StartResult): Response {
  const headers = { "cache-control": "no-store" };
  switch (result.result) {
    case "started":
    case "already-started":
      return Response.json({ result: result.result }, { headers });
    case "refused":
      return Response.json({ result: "refused", reason: result.reason }, { status: 502, headers });
    case "not-set-up":
      return Response.json({ result: "not-set-up" }, { status: 503, headers });
    case "unknown-station":
      return errorResponse(400, "unknown station");
  }
}

function onlyPost(request: Request): Response | undefined {
  if (request.method === "POST") {
    return undefined;
  }
  return errorResponse(405, "method not allowed", { allow: "POST" });
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
