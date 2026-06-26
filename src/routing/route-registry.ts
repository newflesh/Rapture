import fs from 'fs';
import path from 'path';
import yaml from 'js-yaml';
import { match as compileMatcher, MatchFunction } from 'path-to-regexp';
import { RouteConfigSchema, RouteDef } from '../types/route-config';

export class RouteConfigError extends Error {}

interface CompiledRoute {
  route: RouteDef;
  matcher: MatchFunction<Record<string, string>>;
}

export interface RouteMatch {
  route: RouteDef;
  pathParams: Record<string, string>;
}

function loadRawConfig(filePath: string): unknown {
  const contents = fs.readFileSync(filePath, 'utf-8');
  const ext = path.extname(filePath).toLowerCase();
  if (ext === '.json') {
    return JSON.parse(contents);
  }
  return yaml.load(contents);
}

export class RouteRegistry {
  private readonly compiled: CompiledRoute[];

  constructor(routes: RouteDef[]) {
    this.compiled = routes.map((route) => ({
      route,
      matcher: compileMatcher(route.path, { decode: decodeURIComponent }),
    }));
  }

  static fromFile(filePath: string): RouteRegistry {
    let raw: unknown;
    try {
      raw = loadRawConfig(filePath);
    } catch (err) {
      throw new RouteConfigError(
        `failed to read route config at "${filePath}": ${(err as Error).message}`,
      );
    }

    const parsed = RouteConfigSchema.safeParse(raw);
    if (!parsed.success) {
      const details = parsed.error.issues
        .map((issue) => `${issue.path.join('.')}: ${issue.message}`)
        .join('; ');
      throw new RouteConfigError(`invalid route config at "${filePath}": ${details}`);
    }

    const seen = new Set<string>();
    for (const route of parsed.data.routes) {
      const key = `${route.method} ${route.path}`;
      if (seen.has(key)) {
        throw new RouteConfigError(`duplicate route definition: ${key}`);
      }
      seen.add(key);
    }

    return new RouteRegistry(parsed.data.routes);
  }

  list(): RouteDef[] {
    return this.compiled.map((c) => c.route);
  }

  match(method: string, requestPath: string): RouteMatch | null {
    const upperMethod = method.toUpperCase();
    for (const { route, matcher } of this.compiled) {
      if (route.method !== upperMethod) continue;
      const result = matcher(requestPath);
      if (result) {
        return { route, pathParams: result.params as Record<string, string> };
      }
    }
    return null;
  }
}
