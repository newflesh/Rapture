import { RpgCallRequest, RpgCallResult, RpgInvocationError, RpgInvoker } from './types';

export interface Db2StoredProcInvokerOptions {
  /** Full ODBC connection string, e.g. "DSN=IBMI;UID=user;PWD=secret". */
  connectionString: string;
  /** Pool size bounds, passed through to the odbc pool. */
  initialSize?: number;
  maxSize?: number;
}

// Minimal surface of the `odbc` package types we rely on, kept local so this
// module compiles even when @types for `odbc` aren't installed.
interface OdbcConnection {
  callProcedure(
    catalog: string | null,
    schema: string | null,
    name: string,
    parameters: unknown[],
  ): Promise<{ parameters: unknown[] }>;
  close(): Promise<void>;
}
interface OdbcPool {
  connect(): Promise<OdbcConnection>;
}
interface OdbcModule {
  pool(connectionString: string, poolOptions?: Record<string, unknown>): Promise<OdbcPool>;
}

/**
 * Invokes an RPG program indirectly through a Db2-for-i SQL stored procedure
 * that wraps `CALL LIBRARY/PROGRAM (...)`. Requires the IBM i Access ODBC
 * driver and the `odbc` npm package to be installed and able to compile
 * against unixODBC; both are loaded lazily so the rest of this engine works
 * (routing, validation, tests) without a live IBM i connection.
 */
export class Db2StoredProcInvoker implements RpgInvoker {
  private poolPromise: Promise<OdbcPool> | null = null;

  constructor(private readonly options: Db2StoredProcInvokerOptions) {}

  async call(request: RpgCallRequest): Promise<RpgCallResult> {
    const { route, parameters } = request;
    const procedure = route.procedure ?? route.program;
    const pool = await this.getPool();
    const connection = await pool.connect();

    try {
      const inputValues = parameters.map((p) => p.value ?? null);
      const result = await connection.callProcedure(
        null,
        route.library,
        procedure,
        inputValues,
      );
      return { values: result.parameters };
    } catch (err) {
      throw new RpgInvocationError(
        `failed to call ${route.library}/${procedure}: ${(err as Error).message}`,
        err,
      );
    } finally {
      await connection.close();
    }
  }

  private getPool(): Promise<OdbcPool> {
    if (!this.poolPromise) {
      this.poolPromise = this.loadOdbc().then((odbc) =>
        odbc.pool(this.options.connectionString, {
          initialSize: this.options.initialSize ?? 2,
          maxSize: this.options.maxSize ?? 10,
        }),
      );
    }
    return this.poolPromise;
  }

  private async loadOdbc(): Promise<OdbcModule> {
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      return require('odbc') as OdbcModule;
    } catch (err) {
      throw new RpgInvocationError(
        'the "odbc" package is not available; install it along with the IBM i Access ' +
          'ODBC driver to call RPG programs against a real Db2-for-i connection',
        err,
      );
    }
  }
}
