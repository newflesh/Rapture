#!/QOpenSys/usr/bin/sh
# Starts the Rapture engine inside IBM i PASE, bound to Db2 for i via
# idb-pconnector's *LOCAL connection. Intended to run as a submitted batch
# job so it survives after the starting interactive session ends, e.g.:
#
#   SBMJOB CMD(QSH CMD('/home/rapture/deploy/start-rapture.sh')) JOB(RAPTURE)
#
# Adjust APP_DIR, PORT, and ROUTES_CONFIG_PATH as needed.

set -e

APP_DIR="${APP_DIR:-/home/rapture}"
export PORT="${PORT:-3000}"
export INVOKER_MODE="${INVOKER_MODE:-db2}"
export ROUTES_CONFIG_PATH="${ROUTES_CONFIG_PATH:-$APP_DIR/config/routes.yaml}"

cd "$APP_DIR"
exec node dist/server/index.js
