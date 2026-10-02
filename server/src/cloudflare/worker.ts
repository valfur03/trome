import { secretValues } from "../core/config/secrets";
import { route } from "../core/http/router";
import { createLogger } from "../core/logging/logger";

export { RelayObject } from "./relay-object";

export default {
  fetch(request, env) {
    const logger = createLogger(secretValues(env), (line) => {
      console.log(line);
    });
    return route(request, { logger });
  },
} satisfies ExportedHandler<Env>;
