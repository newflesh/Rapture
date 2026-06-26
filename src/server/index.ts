import path from 'path';
import { createApp } from './app';
import { RouteRegistry } from '../routing/route-registry';
import { RpgInvoker } from '../invoker/types';
import { Db2StoredProcInvoker } from '../invoker/db2-stored-proc-invoker';
import { MockInvoker } from '../invoker/mock-invoker';

function buildInvoker(): RpgInvoker {
  const mode = process.env.INVOKER_MODE ?? 'db2';
  if (mode === 'mock') {
    return new MockInvoker();
  }

  const connectionString = process.env.DB2_CONNECTION_STRING;
  if (!connectionString) {
    throw new Error(
      'DB2_CONNECTION_STRING is required when INVOKER_MODE=db2 ' +
        '(e.g. "DSN=IBMI;UID=user;PWD=secret" or a full ODBC connection string)',
    );
  }
  return new Db2StoredProcInvoker({ connectionString });
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
