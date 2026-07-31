import { existsSync, mkdirSync, appendFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { inspect } from "node:util";

type LogLevel = "debug" | "info" | "warn" | "error" | "fatal";

type LogFields = Record<string, unknown>;

const LOG_DIR = resolve(process.env.LOG_DIR ?? (process.env.VERCEL === "1" ? "/tmp/logs" : "logs"));
const ACCESS_LOG_FILE = join(LOG_DIR, "backend-access.log");
const ERROR_LOG_FILE = join(LOG_DIR, "backend-error.log");
const APP_LOG_FILE = join(LOG_DIR, "backend-app.log");

ensureLogDir();

export function logInfo(message: string, fields: LogFields = {}) {
  writeLog("info", message, fields, APP_LOG_FILE);
}

export function logWarning(message: string, fields: LogFields = {}) {
  writeLog("warn", message, fields, ERROR_LOG_FILE);
}

export function logError(message: string, error: unknown, fields: LogFields = {}) {
  writeLog("error", message, {
    ...fields,
    error: serializeError(error),
  }, ERROR_LOG_FILE);
}

export function logFatal(message: string, error: unknown, fields: LogFields = {}) {
  writeLog("fatal", message, {
    ...fields,
    error: serializeError(error),
  }, ERROR_LOG_FILE);
}

export function logAccess(fields: LogFields) {
  writeLog("info", "http_request", fields, ACCESS_LOG_FILE);
}

function writeLog(
  level: LogLevel,
  message: string,
  fields: LogFields,
  filePath: string,
) {
  const entry = `${JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    message,
    ...sanitizeLogFields(fields),
  })}\n`;

  try {
    appendFileSync(filePath, entry, "utf8");
  } catch {
    // En entornos serverless el filesystem puede ser de solo lectura.
  }

  if (level === "error" || level === "fatal") {
    process.stderr.write(entry);
    return;
  }

  process.stdout.write(entry);
}

function ensureLogDir() {
  if (!existsSync(LOG_DIR)) {
    mkdirSync(LOG_DIR, { recursive: true });
  }
}

function serializeError(error: unknown) {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      stack: error.stack,
      cause: serializeCause(error.cause),
    };
  }

  return {
    name: typeof error,
    message: inspect(error, { depth: 4 }),
  };
}

function serializeCause(cause: unknown): unknown {
  if (cause == null) {
    return undefined;
  }

  if (cause instanceof Error) {
    return {
      name: cause.name,
      message: cause.message,
      stack: cause.stack,
      cause: serializeCause(cause.cause),
    };
  }

  return inspect(cause, { depth: 3 });
}

function sanitizeLogFields(fields: LogFields) {
  return Object.fromEntries(
    Object.entries(fields)
      .filter(([, value]) => value !== undefined)
      .map(([key, value]) => [key, sanitizeLogValue(key, value)]),
  );
}

function sanitizeLogValue(key: string, value: unknown): unknown {
  if (value == null) {
    return value;
  }

  if (typeof value === "string") {
    if (isSensitiveKey(key)) {
      return "[redacted]";
    }

    return value.length > 500 ? `${value.slice(0, 500)}...` : value;
  }

  if (Array.isArray(value)) {
    return value.map((item) => sanitizeLogValue(key, item));
  }

  if (typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([childKey, childValue]) => [
        childKey,
        sanitizeLogValue(childKey, childValue),
      ]),
    );
  }

  return value;
}

function isSensitiveKey(key: string) {
  return /password|token|authorization|secret|key|cookie|firma|payload/i.test(key);
}
