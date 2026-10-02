import type { Logger } from "../logging/logger";

export interface RouterDependencies {
  logger: Logger;
}

export function route(request: Request, { logger }: RouterDependencies): Response {
  const { pathname } = new URL(request.url);
  const response = answer(request.method, pathname);
  logger.info("request", { method: request.method, path: pathname, status: response.status });
  return response;
}

function answer(method: string, pathname: string): Response {
  if (pathname !== "/health") {
    return Response.json({ error: "not found" }, { status: 404 });
  }
  if (method !== "GET" && method !== "HEAD") {
    return Response.json({ error: "method not allowed" }, { status: 405, headers: { allow: "GET, HEAD" } });
  }
  return Response.json({ status: "ok" });
}
