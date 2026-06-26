import { RouteDef } from '../types/route-config';
import { CallParameter } from '../routing/parameter-mapper';

export class RpgInvocationError extends Error {
  constructor(message: string, public readonly cause?: unknown) {
    super(message);
  }
}

export interface RpgCallRequest {
  route: RouteDef;
  parameters: CallParameter[];
}

export interface RpgCallResult {
  /** Values aligned 1:1 with request.parameters, reflecting OUT/INOUT results. */
  values: unknown[];
}

export interface RpgInvoker {
  call(request: RpgCallRequest): Promise<RpgCallResult>;
}
