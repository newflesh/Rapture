import express, { Application, NextFunction, Request, Response } from 'express';
import { RouteRegistry } from '../routing/route-registry';
import { buildCallParameters, IncomingRequest, ValidationError } from '../routing/parameter-mapper';
import { RpgInvocationError, RpgInvoker } from '../invoker/types';

function toIncomingRequest(req: Request): IncomingRequest {
  return {
    pathParams: req.params as Record<string, string>,
    query: req.query as Record<string, unknown>,
    body: req.body,
    headers: req.headers as Record<string, string | string[] | undefined>,
  };
}

function trimIfChar(type: string, value: unknown): unknown {
  return type === 'CHAR' && typeof value === 'string' ? value.trimEnd() : value;
}

export function createApp(registry: RouteRegistry, invoker: RpgInvoker): Application {
  const app = express();
  app.use(express.json());

  app.use(async (req: Request, res: Response, next: NextFunction) => {
    try {
      const found = registry.match(req.method, req.path);
      if (!found) {
        res.status(404).json({
          error: { code: 'ROUTE_NOT_FOUND', message: `no route matches ${req.method} ${req.path}` },
        });
        return;
      }

      const { route, pathParams } = found;
      const parameters = buildCallParameters(route, { ...toIncomingRequest(req), pathParams });
      const result = await invoker.call({ route, parameters });

      const output: Record<string, unknown> = {};
      parameters.forEach((param, idx) => {
        if (param.def.direction === 'IN') return;
        const key = param.def.as ?? param.def.name;
        output[key] = trimIfChar(param.def.type, result.values[idx]);
      });

      res.status(route.successStatus).json(output);
    } catch (err) {
      next(err);
    }
  });

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof ValidationError) {
      res.status(400).json({ error: { code: 'VALIDATION_ERROR', message: err.message, issues: err.issues } });
      return;
    }
    if (err instanceof RpgInvocationError) {
      res.status(502).json({ error: { code: 'RPG_INVOCATION_ERROR', message: err.message } });
      return;
    }
    // eslint-disable-next-line no-console
    console.error(err);
    res.status(500).json({ error: { code: 'INTERNAL_ERROR', message: 'unexpected server error' } });
  });

  return app;
}
