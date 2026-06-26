import path from 'path';
import request from 'supertest';
import { createApp } from '../src/server/app';
import { RouteRegistry } from '../src/routing/route-registry';
import { MockInvoker } from '../src/invoker/mock-invoker';

const FIXTURE = path.join(__dirname, 'fixtures/routes.test.yaml');

describe('app', () => {
  function buildApp() {
    const registry = RouteRegistry.fromFile(FIXTURE);
    const invoker = new MockInvoker();
    invoker.on('CUSTLIB', 'CUSTINQ', () => [undefined, 'ACME CORP', 1500.5]);
    invoker.on('ORDLIB', 'ORDCRT', () => [undefined, undefined, 555, 'CREATED']);
    return createApp(registry, invoker);
  }

  it('routes a GET request through to the RPG program and maps OUT params to JSON', async () => {
    const app = buildApp();
    const res = await request(app).get('/api/customers/12345');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ name: 'ACME CORP', balance: 1500.5 });
  });

  it('routes a POST request with a body and custom success status', async () => {
    const app = buildApp();
    const res = await request(app).post('/api/orders').send({ customerId: 7, qty: 2 });
    expect(res.status).toBe(201);
    expect(res.body).toEqual({ orderId: 555, status: 'CREATED' });
  });

  it('returns 404 for an unmatched route', async () => {
    const app = buildApp();
    const res = await request(app).get('/api/unknown');
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('ROUTE_NOT_FOUND');
  });

  it('returns 400 with validation issues for missing required params', async () => {
    const app = buildApp();
    const res = await request(app).post('/api/orders').send({});
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(res.body.error.issues.length).toBeGreaterThan(0);
  });
});
