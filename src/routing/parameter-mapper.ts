import { ParameterDef, RouteDef } from '../types/route-config';

export class ValidationError extends Error {
  constructor(public readonly issues: string[]) {
    super(`parameter validation failed: ${issues.join('; ')}`);
  }
}

export interface IncomingRequest {
  pathParams: Record<string, string>;
  query: Record<string, unknown>;
  body: unknown;
  headers: Record<string, string | string[] | undefined>;
}

export interface CallParameter {
  def: ParameterDef;
  /** Input value to send for IN/INOUT parameters; undefined for OUT-only parameters. */
  value: unknown;
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_RE = /^\d{2}:\d{2}:\d{2}$/;
const TIMESTAMP_RE = /^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(\.\d+)?$/;

function readRawValue(def: ParameterDef, req: IncomingRequest): unknown {
  const field = def.field ?? def.name;
  switch (def.source) {
    case 'path':
      return req.pathParams[field];
    case 'query':
      return req.query[field];
    case 'header':
      return req.headers[field.toLowerCase()];
    case 'body':
      return req.body && typeof req.body === 'object'
        ? (req.body as Record<string, unknown>)[field]
        : undefined;
    default:
      return undefined;
  }
}

function castValue(def: ParameterDef, raw: unknown, issues: string[]): unknown {
  if (raw === undefined || raw === null || raw === '') {
    return undefined;
  }

  switch (def.type) {
    case 'CHAR': {
      const str = String(raw);
      const len = def.length as number;
      if (str.length > len) return str.slice(0, len);
      return str.padEnd(len, ' ');
    }
    case 'VARCHAR': {
      const str = String(raw);
      const len = def.length as number;
      return str.length > len ? str.slice(0, len) : str;
    }
    case 'DECIMAL':
    case 'NUMERIC': {
      const num = typeof raw === 'number' ? raw : Number(raw);
      if (Number.isNaN(num)) {
        issues.push(`parameter "${def.name}" must be a valid decimal number, got "${raw}"`);
        return undefined;
      }
      const decimals = def.decimals ?? 0;
      return Number(num.toFixed(decimals));
    }
    case 'INTEGER':
    case 'SMALLINT':
    case 'BIGINT': {
      const num = typeof raw === 'number' ? raw : Number(raw);
      if (Number.isNaN(num) || !Number.isInteger(num)) {
        issues.push(`parameter "${def.name}" must be a valid integer, got "${raw}"`);
        return undefined;
      }
      return num;
    }
    case 'DATE': {
      const str = String(raw);
      if (!DATE_RE.test(str)) {
        issues.push(`parameter "${def.name}" must be a date in YYYY-MM-DD format, got "${raw}"`);
        return undefined;
      }
      return str;
    }
    case 'TIME': {
      const str = String(raw);
      if (!TIME_RE.test(str)) {
        issues.push(`parameter "${def.name}" must be a time in HH:MM:SS format, got "${raw}"`);
        return undefined;
      }
      return str;
    }
    case 'TIMESTAMP': {
      const str = String(raw);
      if (!TIMESTAMP_RE.test(str)) {
        issues.push(`parameter "${def.name}" must be a timestamp, got "${raw}"`);
        return undefined;
      }
      return str;
    }
    case 'INDICATOR': {
      const truthy = raw === true || raw === '1' || raw === 1 || raw === 'true';
      return truthy ? '1' : '0';
    }
    default:
      return raw;
  }
}

export function buildCallParameters(route: RouteDef, req: IncomingRequest): CallParameter[] {
  const issues: string[] = [];
  const result: CallParameter[] = [];

  for (const def of route.parameters) {
    if (def.direction === 'OUT') {
      result.push({ def, value: undefined });
      continue;
    }

    const raw = readRawValue(def, req);
    const effectiveRaw = raw === undefined && def.default !== undefined ? def.default : raw;
    const cast = castValue(def, effectiveRaw, issues);

    if (cast === undefined && def.required) {
      issues.push(`missing required parameter "${def.name}" (expected in ${def.source})`);
    }

    result.push({ def, value: cast });
  }

  if (issues.length > 0) {
    throw new ValidationError(issues);
  }

  return result;
}
