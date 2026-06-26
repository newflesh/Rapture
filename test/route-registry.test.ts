import path from 'path';
import { RouteConfigError, RouteRegistry } from '../src/routing/route-registry';

const FIXTURE = path.join(__dirname, 'fixtures/routes.test.yaml');

describe('RouteRegistry', () => {
  it('loads and matches a route with path params', () => {
    const registry = RouteRegistry.fromFile(FIXTURE);
    const found = registry.match('GET', '/api/customers/12345');
    expect(found).not.toBeNull();
    expect(found!.route.program).toBe('CUSTINQ');
    expect(found!.pathParams).toEqual({ id: '12345' });
  });

  it('is case-insensitive on method', () => {
    const registry = RouteRegistry.fromFile(FIXTURE);
    const found = registry.match('get', '/api/customers/1');
    expect(found).not.toBeNull();
  });

  it('returns null when nothing matches', () => {
    const registry = RouteRegistry.fromFile(FIXTURE);
    expect(registry.match('GET', '/nope')).toBeNull();
    expect(registry.match('POST', '/api/customers/1')).toBeNull();
  });

  it('rejects an unknown config file', () => {
    expect(() => RouteRegistry.fromFile('/no/such/file.yaml')).toThrow(RouteConfigError);
  });

  it('rejects invalid config content', () => {
    const tmp = path.join(__dirname, 'fixtures/invalid.test.json');
    require('fs').writeFileSync(tmp, JSON.stringify({ routes: [{ method: 'GET' }] }));
    try {
      expect(() => RouteRegistry.fromFile(tmp)).toThrow(RouteConfigError);
    } finally {
      require('fs').unlinkSync(tmp);
    }
  });
});
