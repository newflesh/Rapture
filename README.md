Rapture
=======

An HTTP REST process engine that routes incoming requests to the correct
IBM i RPG program based on the request's method, path, and parameters.

Each route is declared in a config file (`config/routes.yaml`) that maps an
HTTP method + path pattern to a `library`/`program` (optionally an explicit
`procedure` name) and an ordered list of parameters with their REST source,
RPG type, and direction (`IN`/`OUT`/`INOUT`). At request time the engine:

1. Matches the incoming request against the routing table.
2. Extracts and casts each parameter from the path, query string, body, or
   headers into the declared RPG type (padding `CHAR` fields, validating
   `DECIMAL`/`DATE`/etc).
3. Calls the RPG program via a Db2-for-i stored procedure that wraps
   `CALL LIBRARY/PROGRAM (...)`.
4. Maps the program's `OUT`/`INOUT` parameters back into a JSON response.

## Project layout

```
src/
  types/route-config.ts        zod schema for routes.yaml
  routing/route-registry.ts    loads config, matches method+path -> route
  routing/parameter-mapper.ts  REST request -> typed RPG call parameters
  invoker/types.ts             RpgInvoker interface
  invoker/db2-stored-proc-invoker.ts  real invoker (odbc -> Db2-for-i stored proc)
  invoker/mock-invoker.ts      in-memory invoker for tests/dev
  server/app.ts                express app wiring + error handling
  server/index.ts              entrypoint (env config, starts the server)
config/routes.yaml             example routing table
test/                          jest + supertest tests (run against MockInvoker)
```

## Configuring routes

```yaml
routes:
  - name: getCustomer
    method: GET
    path: /api/customers/:id
    library: CUSTLIB
    program: CUSTINQ        # procedure: CUSTLIB.CUSTINQ unless `procedure:` overrides it
    parameters:
      - name: customerId
        source: path        # path | query | body | header
        field: id           # field name in that source; defaults to `name`
        type: DECIMAL
        length: 9
        decimals: 0
        direction: IN        # IN | OUT | INOUT (default IN)
      - name: customerName
        type: CHAR
        length: 50
        direction: OUT
        as: name             # JSON response key; defaults to `name`
      - name: balance
        type: DECIMAL
        length: 11
        decimals: 2
        direction: OUT
```

Supported `type`s: `CHAR`, `VARCHAR`, `DECIMAL`, `NUMERIC`, `INTEGER`,
`SMALLINT`, `BIGINT`, `DATE`, `TIME`, `TIMESTAMP`, `INDICATOR`.

`IN`/`INOUT` parameters are validated and cast; missing required values or
type mismatches produce a single `400 VALIDATION_ERROR` response listing
every issue. `OUT`/`INOUT` parameters are returned as JSON fields named by
`as` (or `name`), with trailing spaces trimmed from `CHAR` values.

## Running

```sh
npm install
npm run build

# Mock mode: routes requests through MockInvoker, no IBM i connection needed.
INVOKER_MODE=mock npm start

# Real mode: requires the `odbc` package's native module to be built against
# unixODBC, plus the IBM i Access ODBC driver and a DSN/connection string.
DB2_CONNECTION_STRING="DSN=IBMI;UID=user;PWD=secret" npm start
```

Environment variables:

| Variable               | Default                     | Purpose                                   |
|-------------------------|------------------------------|--------------------------------------------|
| `PORT`                 | `3000`                      | HTTP listen port                          |
| `ROUTES_CONFIG_PATH`   | `config/routes.yaml`        | Path to the routing table                 |
| `INVOKER_MODE`         | `db2`                       | `db2` or `mock`                            |
| `DB2_CONNECTION_STRING`| —                            | ODBC connection string (required for `db2`)|

### Wiring a real IBM i connection

`Db2StoredProcInvoker` calls `connection.callProcedure(catalog, schema, procedure, values)`
from the [`odbc`](https://www.npmjs.com/package/odbc) package, with
`schema` = `library` and `procedure` = `procedure ?? program`. The Db2-for-i
driver introspects the procedure's parameter directions automatically and
returns updated `OUT`/`INOUT` values in `result.parameters`, in the same
order they were declared.

This means each RPG program you want to expose needs a matching SQL
stored procedure registered on the IBM i system, e.g.:

```sql
CREATE PROCEDURE CUSTLIB.CUSTINQ (
  IN  CUSTOMER_ID DECIMAL(9, 0),
  OUT CUSTOMER_NAME CHAR(50),
  OUT BALANCE DECIMAL(11, 2)
)
LANGUAGE RPGLE
EXTERNAL NAME 'CUSTLIB/CUSTINQ'
PARAMETER STYLE GENERAL;
```

The `odbc` package's native module must be built against `unixODBC` and the
IBM i Access ODBC driver on the host that runs the engine; it is loaded
lazily by `Db2StoredProcInvoker` so the rest of the engine (routing,
validation, the mock invoker, and all tests) works without it.

## Testing

```sh
npm test
```

Tests exercise the route matcher, parameter casting/validation rules, and a
full HTTP request → route match → parameter mapping → RPG call → JSON
response flow using `MockInvoker`, with no IBM i dependency.
