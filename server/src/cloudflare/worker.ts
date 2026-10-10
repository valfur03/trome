import { secretValues } from "../core/config/secrets";
import { route } from "../core/http/router";
import { createLogger } from "../core/logging/logger";
import { relayObject } from "./relay-object";

export { RelayObject } from "./relay-object";

export default {
  fetch(request, env) {
    const logger = createLogger(secretValues(env), (line) => {
      console.log(line);
    });
    const relay = relayObject(env);
    return route(request, {
      logger,
      clock: { now: () => Date.now() },
      tokens: { app: env.APP_TOKEN, owner: env.OWNER_TOKEN },
      relay: {
        departures: (stopRef) => relay.departures(stopRef),
        counts: () => relay.counts(),
        metrics: () => relay.metrics(),
      },
    });
  },
} satisfies ExportedHandler<Env>;
