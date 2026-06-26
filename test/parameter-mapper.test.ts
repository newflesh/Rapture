import path from 'path';
import { RouteRegistry } from '../src/routing/route-registry';
import { buildCallParameters, IncomingRequest, ValidationError } from '../src/routing/parameter-mapper';

const FIXTURE = path.join(__dirname, 'fixtures/routes.test.yaml');

function req(overrides: Partial<IncomingRequest> = {}): IncomingRequest {
  return {
    pathParams: {},
    query: {},
    body: {},
    headers: {},
    ...overrides,
  };
}

describe('buildCallParameters', () => {
  const registry = RouteRegistry.fromFile(FIXTURE);
  const getCustomer = registry.list().find((r) => r.name === 'getCustomer')!;
  const createOrder = registry.list().find((r) => r.name === 'createOrder')!;

  it('casts a path param to a padded/typed value and leaves OUT params unset', () => {
    const params = buildCallParameters(getCustomer, req({ pathParams: { id: '12345' } }));
    expect(params[0].value).toBe(12345);
    expect(params[1].def.direction).toBe('OUT');
    expect(params[1].value).toBeUndefined();
  });

  it('reads body fields for IN parameters', () => {
    const params = buildCallParameters(
      createOrder,
      req({ body: { customerId: 99, qty: 3 } }),
    );
    expect(params[0].value).toBe(99);
    expect(params[1].value).toBe(3);
  });

  it('throws ValidationError listing all missing required params', () => {
    expect.assertions(2);
    try {
      buildCallParameters(createOrder, req({ body: {} }));
    } catch (err) {
      expect(err).toBeInstanceOf(ValidationError);
      expect((err as ValidationError).issues).toEqual([
        'missing required parameter "customerId" (expected in body)',
        'missing required parameter "qty" (expected in body)',
      ]);
    }
  });

  it('rejects non-numeric values for numeric types', () => {
    expect(() =>
      buildCallParameters(createOrder, req({ body: { customerId: 'abc', qty: 1 } })),
    ).toThrow(ValidationError);
  });
});
