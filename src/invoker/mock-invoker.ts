import { RpgCallRequest, RpgCallResult, RpgInvoker } from './types';
import { CallParameter } from '../routing/parameter-mapper';

export type MockHandler = (parameters: CallParameter[]) => unknown[] | void;

/**
 * In-memory RpgInvoker for tests and local development without a live IBM i
 * connection. Handlers are keyed by "LIBRARY.PROCEDURE" (procedure falls back
 * to the program name, matching Db2StoredProcInvoker's resolution).
 */
export class MockInvoker implements RpgInvoker {
  private readonly handlers = new Map<string, MockHandler>();

  on(library: string, procedure: string, handler: MockHandler): this {
    this.handlers.set(this.key(library, procedure), handler);
    return this;
  }

  async call(request: RpgCallRequest): Promise<RpgCallResult> {
    const { route, parameters } = request;
    const procedure = route.procedure ?? route.program;
    const handler = this.handlers.get(this.key(route.library, procedure));

    const overrides = handler ? handler(parameters) ?? [] : [];

    const values = parameters.map((param, idx) => {
      if (overrides[idx] !== undefined) return overrides[idx];
      if (param.def.direction === 'IN') return param.value;
      // Unhandled OUT/INOUT params default to a zero-value of the right type.
      return param.def.type === 'CHAR' || param.def.type === 'VARCHAR'
        ? ''
        : param.value ?? 0;
    });

    return { values };
  }

  private key(library: string, procedure: string): string {
    return `${library}.${procedure}`.toUpperCase();
  }
}
