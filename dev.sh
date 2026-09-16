#!/usr/bin/env bash
# Bring the whole local loop up: both subgraphs, composition, the gateway.
#
# Composition needs each subgraph's SDL (fetched from localhost, where the
# subgraphs actually are) but must write ROUTING urls the gateway container
# can reach (host.docker.internal). Hence: fetch SDL to a file, then compose
# with --schema for the SDL and --url for routing.
set -euo pipefail
cd "$(dirname "$0")"

CATALOG=http://localhost:8081/graphql
PERSONALIZATION=http://localhost:8082/graphql
ROUTE_CATALOG=http://host.docker.internal:8081/graphql
ROUTE_PERSONALIZATION=http://host.docker.internal:8082/graphql
# The local devDependency, by path: `npx hive` could fall through to an
# unrelated npm package that happens to be called "hive".
HIVE=./node_modules/.bin/hive
# The Hive CLI's oclif update hook runs before every command. It self-updates
# in the background (wrong for a local-only loop) and, on Node 26, can crash
# the command when its 14-day marker is missing or stale — which would read as
# a composition failure below.
export HIVE_DISABLE_AUTOUPDATE=1

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }

step "Checking prerequisites"
docker info >/dev/null 2>&1 || fail "Docker is not running — start Docker Desktop"
command -v npm >/dev/null 2>&1 || fail "npm is not installed — install Node 20 or newer (the gateway's devDependencies need it)"
# Without python3 the SDL step below fails as "the response carried no
# _service.sdl", which points at federation when the problem is the PATH.
command -v python3 >/dev/null 2>&1 || fail "python3 is not installed — install Python 3 (the SDL and smoke steps parse JSON with it)"
# A leftover listener (a bootRun open for GraphiQL, an orphaned JVM from an
# earlier dev.sh) would make the new JVM fail to bind while wait_for happily
# talks to the OLD process, so the whole loop would run stale code.
# curl exit 7 means "connection refused": nothing is listening.
for port in 8081 8082 4000; do
  rc=0; curl -s -o /dev/null --max-time 2 "http://localhost:$port/" || rc=$?
  [ "$rc" -eq 7 ] || fail "port $port is already in use — stop whatever holds it (see: lsof -nP -iTCP:$port -sTCP:LISTEN), e.g. a bootRun or a JVM left over from an earlier dev.sh"
done

step "Building"
./gradlew -q assemble
[ -x "gateway/$HIVE" ] || (cd gateway && npm ci)

step "Starting subgraphs"
# The trap goes in only now, just before anything is started: set before the
# port check, a failed start would `compose down` the gateway of a dev.sh that
# is already running.
cleanup() {
  local pids
  pids=$(jobs -p)
  [ -z "$pids" ] || kill $pids 2>/dev/null || true
  docker compose -f gateway/docker-compose.yml down >/dev/null 2>&1 || true
}
trap cleanup EXIT
java -jar catalog/build/libs/catalog-0.1.0.jar >gateway/catalog.log 2>&1 &
CATALOG_PID=$!
java -jar personalization/build/libs/personalization-0.1.0.jar >gateway/personalization.log 2>&1 &
PERSONALIZATION_PID=$!

wait_for() {
  for _ in $(seq 1 60); do
    curl -sf --max-time 2 "$1" -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' >/dev/null 2>&1 && return 0
    sleep 1
  done
  fail "$1 did not come up in 60s — see gateway/*.log"
}
wait_for "$CATALOG"; wait_for "$PERSONALIZATION"
kill -0 "$CATALOG_PID" 2>/dev/null || fail "catalog exited during startup — see gateway/catalog.log"
kill -0 "$PERSONALIZATION_PID" 2>/dev/null || fail "personalization exited during startup — see gateway/personalization.log"

step "Fetching federated SDL"
mkdir -p gateway/sdl
# Each failure is named explicitly: `||` suspends set -e inside the
# assignment, and the here-string replaces a pipe that pipefail would report
# as a bare Python traceback. The SDL is held in a variable and printed only
# once it is known to be a non-empty string: a null one would otherwise reach
# the file as the literal "None" and surface later as a composition failure,
# blaming the schemas.
sdl() {
  local body text
  body=$(curl -sf --max-time 10 "$1" -H 'Content-Type: application/json' -d '{"query":"{ _service { sdl } }"}') \
    || fail "could not fetch SDL from $1"
  text=$(python3 -c 'import json, sys
d = json.load(sys.stdin)
s = (((d or {}).get("data") or {}).get("_service") or {}).get("sdl")
if not isinstance(s, str) or not s.strip():
    sys.exit(1)
print(s)' <<<"$body" 2>/dev/null) \
    || fail "could not fetch SDL from $1 — the response carried no _service.sdl"
  printf '%s\n' "$text"
}
sdl "$CATALOG" > gateway/sdl/catalog.graphql
sdl "$PERSONALIZATION" > gateway/sdl/personalization.graphql

step "Composing the supergraph"
(cd gateway && "$HIVE" dev \
  --service catalog --url "$ROUTE_CATALOG" --schema sdl/catalog.graphql \
  --service personalization --url "$ROUTE_PERSONALIZATION" --schema sdl/personalization.graphql \
  --write supergraph.graphql) || fail "composition failed — the two schemas do not compose"

step "Starting the gateway"
docker compose -f gateway/docker-compose.yml up -d
wait_for http://localhost:4000/graphql

step "Up"
echo "  gateway          http://localhost:4000/graphql"
echo "  catalog          $CATALOG"
echo "  personalization  $PERSONALIZATION"
echo "Ctrl-C to stop everything."
wait
