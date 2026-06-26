import path from 'path';
import { createApp } from './app';
import { RouteRegistry } from '../routing/route-registry';
import { RpgInvoker } from '../invoker/types';
import { IdbConnectorInvoker } from '../invoker/idb-connector-invoker';
import { MockInvoker } from '../invoker/mock-invoker';

function buildInvoker(): RpgInvoker {
  const mode = process.env.INVOKER_MODE ?? 'db2';
  if (mode === 'mock') {
    return new MockInvoker();
  }

  // '*LOCAL' connects to the Db2 for i database on the same IBM i partition
  // this process is running on (the expected deployment: Node in PASE,
  // fronted by IBM HTTP Server / Apache as a reverse proxy).
  const connectionUrl = process.env.IDB_CONNECTION_URL ?? '*LOCAL';
  return new IdbConnectorInvoker(connectionUrl);
}

function main(): void {
  const configPath = process.env.ROUTES_CONFIG_PATH ?? path.join(__dirname, '../../config/routes.yaml');
  const registry = RouteRegistry.fromFile(configPath);
  const invoker = buildInvoker();
  const app = createApp(registry, invoker);

  const port = Number(process.env.PORT ?? 3000);
  app.listen(port, () => {
    // eslint-disable-next-line no-console
    console.log(`Rapture listening on port ${port} (routes: ${configPath})`);
  });
}

main();
