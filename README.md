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

The engine is meant to run in IBM i PASE, on the same partition as Db2 for i,
fronted by IBM HTTP Server (Apache) acting as a reverse proxy — see
[Deploying behind IBM HTTP Server on IBM i 7.5](#deploying-behind-ibm-http-server-on-ibm-i-75).

## Project layout

```
src/
  types/route-config.ts        zod schema for routes.yaml
  routing/route-registry.ts    loads config, matches method+path -> route
  routing/parameter-mapper.ts  REST request -> typed RPG call parameters
  invoker/types.ts             RpgInvoker interface
  invoker/idb-connector-invoker.ts  real invoker (idb-pconnector -> Db2-for-i stored proc)
  invoker/mock-invoker.ts      in-memory invoker for tests/dev
  server/app.ts                express app wiring + error handling
  server/index.ts              entrypoint (env config, starts the server)
config/routes.yaml             example routing table
deploy/                        Apache reverse-proxy config + PASE start script
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

# Real mode: must run inside IBM i PASE so idb-pconnector's native addon is
# available; connects to the local Db2 for i database via *LOCAL.
npm start
```

Environment variables:

| Variable               | Default                     | Purpose                                       |
|-------------------------|------------------------------|------------------------------------------------|
| `PORT`                 | `3000`                      | HTTP listen port                              |
| `ROUTES_CONFIG_PATH`   | `config/routes.yaml`        | Path to the routing table                     |
| `INVOKER_MODE`         | `db2`                       | `db2` or `mock`                                |
| `IDB_CONNECTION_URL`   | `*LOCAL`                    | idb-pconnector connection URL (required for `db2`)|

### Wiring a real IBM i connection

`IdbConnectorInvoker` (`src/invoker/idb-connector-invoker.ts`) uses IBM's
[`idb-pconnector`](https://www.npmjs.com/package/idb-pconnector) to call Db2
for i natively over PASE — no ODBC driver or DSN setup, since Node runs on
the same partition as the database (`*LOCAL`). For each call it:

1. Prepares `CALL LIBRARY.PROCEDURE (?, ?, ...)` with one marker per
   declared parameter.
2. Binds each parameter as `[value, direction, sqlType]` using the package's
   `IN`/`OUT`/`INOUT` and `CHAR`/`INT`/`NUMERIC` constants (`DATE`/`TIME`/
   `TIMESTAMP`/`INDICATOR` all bind as `CHAR`, matching how `parameter-mapper.ts`
   already renders them as strings).
3. Executes and maps the resolved output array back onto the `OUT`/`INOUT`
   parameters.

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

`idb-pconnector` is an `optionalDependency` and is loaded lazily, so the rest
of the engine (routing, validation, the mock invoker, and all tests) works
without it on a non-IBM-i machine. **Caveat:** IBM's published docs for
`execute()` say it "resolves to an array of output params" but don't pin
down whether that array covers all bound parameters or only the `OUT`/
`INOUT` ones — `mapOutputs()` handles both shapes positionally and throws a
clear error on anything else, but this should be smoke-tested against your
installed `idb-pconnector` version with a real stored procedure call before
relying on it in production.

## Deploying behind IBM HTTP Server on IBM i 7.5

Run the Node engine in PASE on the same IBM i partition as Db2 for i, and
let IBM HTTP Server (Apache) be the public front door — it already handles
SSL/virtual hosts/ACLs, so Rapture only needs to listen on localhost.

1. Get Node.js into PASE if it isn't already (IBM i 7.5's Open Source
   environment, e.g. `yum install nodejs18` via ACS/`yum`).
2. Copy this project to the IFS (e.g. `/home/rapture`), then `npm install`
   and `npm run build` from a PASE shell (`QP2TERM` or SSH).
3. Start it as a submitted job so it outlives the shell session:
   ```
   SBMJOB CMD(QSH CMD('/home/rapture/deploy/start-rapture.sh')) JOB(RAPTURE)
   ```
   `deploy/start-rapture.sh` sets `PORT`/`INVOKER_MODE`/`ROUTES_CONFIG_PATH`
   and execs `node dist/server/index.js`; adjust the env vars at the top of
   that script as needed.
4. Add the reverse-proxy directives in `deploy/httpd-rapture.conf` to your
   HTTP server instance's `httpd.conf` (via ADMIN2's HTTP Server
   Administration GUI, or directly in the IFS), then restart the instance:
   ```
   ENDTCPSVR SERVER(*HTTP) HTTPSVR(<instance>)
   STRTCPSVR SERVER(*HTTP) HTTPSVR(<instance>)
   ```

After that, requests to `https://<your-ibmi-host>/api/...` are proxied to
the Rapture engine on port 3000, which routes them to the right RPG program.

## Testing

```sh
npm test
```

Tests exercise the route matcher, parameter casting/validation rules, and a
full HTTP request → route match → parameter mapping → RPG call → JSON
response flow using `MockInvoker`, with no IBM i dependency.
