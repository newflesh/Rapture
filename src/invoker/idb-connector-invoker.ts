import { ParameterType } from '../types/route-config';
import { CallParameter } from '../routing/parameter-mapper';
import { RpgCallRequest, RpgCallResult, RpgInvocationError, RpgInvoker } from './types';

// Minimal surface of `idb-pconnector` we rely on, kept local so this module
// compiles even when the package (and its native PASE addon) isn't installed.
interface IdbConnection {
  connect(): Promise<unknown>;
  close(): Promise<unknown>;
}
interface IdbStatement {
  prepare(sql: string): Promise<unknown>;
  bindParameters(params: unknown[][]): Promise<unknown>;
  execute(): Promise<unknown[] | null>;
}
interface IdbModule {
  Connection: new (options?: { url?: string }) => IdbConnection;
  Statement: new (connection: IdbConnection) => IdbStatement;
  IN: unknown;
  OUT: unknown;
  INOUT: unknown;
  CHAR: unknown;
  INT: unknown;
  NUMERIC: unknown;
}

function sqlTypeConstant(idb: IdbModule, type: ParameterType): unknown {
  switch (type) {
    case 'INTEGER':
    case 'SMALLINT':
    case 'BIGINT':
      return idb.INT;
    case 'DECIMAL':
    case 'NUMERIC':
      return idb.NUMERIC;
    // CHAR/VARCHAR/DATE/TIME/TIMESTAMP/INDICATOR all travel as text, matching
    // how parameter-mapper.ts already renders them as strings.
    default:
      return idb.CHAR;
  }
}

function directionConstant(idb: IdbModule, direction: CallParameter['def']['direction']): unknown {
  if (direction === 'IN') return idb.IN;
  if (direction === 'OUT') return idb.OUT;
  return idb.INOUT;
}

/**
 * Invokes an RPG program through a Db2-for-i stored procedure (`CALL
 * LIBRARY/PROGRAM (...)`) using IBM's `idb-pconnector`, which talks to Db2
 * for i natively over PASE without a separate ODBC driver or DSN. Intended
 * to run with the Node process co-located on the IBM i partition (e.g.
 * behind IBM HTTP Server / Apache as a reverse proxy).
 *
 * `idb-pconnector` (and its native addon) only builds/loads inside IBM i
 * PASE, so it's loaded lazily here; routing, validation, and the mock
 * invoker all work without it.
 */
export class IdbConnectorInvoker implements RpgInvoker {
  constructor(private readonly connectionUrl: string = '*LOCAL') {}

  async call(request: RpgCallRequest): Promise<RpgCallResult> {
    const { route, parameters } = request;
    const procedure = route.procedure ?? route.program;
    const idb = await this.loadIdb();

    const connection = new idb.Connection({ url: this.connectionUrl });
    await connection.connect();
    const statement = new idb.Statement(connection);

    try {
      const placeholders = parameters.map(() => '?').join(', ');
      await statement.prepare(`CALL ${route.library}.${procedure} (${placeholders})`);

      const bound = parameters.map((p) => [
        p.value ?? null,
        directionConstant(idb, p.def.direction),
        sqlTypeConstant(idb, p.def.type),
      ]);
      await statement.bindParameters(bound);

      const outputs = await statement.execute();
      return { values: this.mapOutputs(parameters, outputs ?? []) };
    } catch (err) {
      throw new RpgInvocationError(
        `failed to call ${route.library}/${procedure}: ${(err as Error).message}`,
        err,
      );
    } finally {
      await connection.close();
    }
  }

  /**
   * idb-pconnector's execute() resolves to "an array of output params" for a
   * CALL statement; published docs don't pin down whether that array is
   * sized to all bound parameters or only the OUT/INOUT ones. Handle both
   * shapes positionally and fail loudly on anything else rather than risk
   * silently mismapping values - verify this against your installed version
   * with a real call before relying on it in production.
   */
  private mapOutputs(parameters: CallParameter[], outputs: unknown[]): unknown[] {
    const outIndexes = parameters
      .map((p, idx) => (p.def.direction === 'IN' ? -1 : idx))
      .filter((idx) => idx >= 0);

    if (outputs.length === parameters.length) {
      return outputs;
    }
    if (outputs.length === outIndexes.length) {
      const values = parameters.map((p) => p.value);
      outIndexes.forEach((paramIdx, i) => {
        values[paramIdx] = outputs[i];
      });
      return values;
    }
    throw new RpgInvocationError(
      `unexpected output shape from idb-pconnector: got ${outputs.length} values for ` +
        `${parameters.length} parameters (${outIndexes.length} OUT/INOUT)`,
    );
  }

  private async loadIdb(): Promise<IdbModule> {
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      return require('idb-pconnector') as IdbModule;
    } catch (err) {
      throw new RpgInvocationError(
        'the "idb-pconnector" package is not available; it must run inside IBM i PASE ' +
          '(its native addon does not build elsewhere) to call RPG programs against Db2 for i',
        err,
      );
    }
  }
}
