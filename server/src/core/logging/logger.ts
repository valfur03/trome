export type LogFields = Record<string, unknown>;

export interface Logger {
  info(event: string, fields?: LogFields): void;
  error(event: string, fields?: LogFields): void;
}

export const redacted = "[secret]";

export function createLogger(secrets: string[], write: (line: string) => void): Logger {
  const forms = [...new Set(secrets.flatMap(printedForms))].sort((a, b) => b.length - a.length);
  const redact = (line: string) =>
    forms.reduce((text, form) => text.split(form).join(redacted), line);
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

function printedForms(secret: string): string[] {
  return [secret, JSON.stringify(secret).slice(1, -1), encodeURIComponent(secret)];
}

function errorsAsText(_key: string, value: unknown): unknown {
  return value instanceof Error ? `${value.name}: ${value.message}` : value;
}
