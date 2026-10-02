export type LogFields = Record<string, unknown>;

export interface Logger {
  info(event: string, fields?: LogFields): void;
  error(event: string, fields?: LogFields): void;
}

export const redacted = "[secret]";

export function createLogger(secrets: string[], write: (line: string) => void): Logger {
  const redact = (line: string) =>
    secrets.reduce((text, secret) => text.split(secret).join(redacted), line);
  const log = (level: string, event: string, fields: LogFields) => {
    write(redact(JSON.stringify({ level, event, ...fields }, errorsAsText)));
  };
  return {
    info: (event, fields = {}) => {
      log("info", event, fields);
    },
    error: (event, fields = {}) => {
      log("error", event, fields);
    },
  };
}

function errorsAsText(_key: string, value: unknown): unknown {
  return value instanceof Error ? `${value.name}: ${value.message}` : value;
}
