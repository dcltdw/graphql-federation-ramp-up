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

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }

step "Building"
./gradlew -q assemble
# The Hive CLI is a local devDependency. Without it, `npx hive` would fetch an
# unrelated npm package that happens to be called "hive".
[ -d gateway/node_modules ] || (cd gateway && npm ci)

step "Starting subgraphs"
java -jar catalog/build/libs/catalog-0.1.0.jar >gateway/catalog.log 2>&1 &
java -jar personalization/build/libs/personalization-0.1.0.jar >gateway/personalization.log 2>&1 &
trap 'kill $(jobs -p) 2>/dev/null; docker compose -f gateway/docker-compose.yml down >/dev/null 2>&1' EXIT

wait_for() {
  for _ in $(seq 1 60); do
    curl -sf "$1" -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' >/dev/null 2>&1 && return 0
    sleep 1
  done
  fail "$1 did not come up in 60s — see gateway/*.log"
}
wait_for "$CATALOG"; wait_for "$PERSONALIZATION"

step "Fetching federated SDL"
mkdir -p gateway/sdl
sdl() {
  curl -sf "$1" -H 'Content-Type: application/json' -d '{"query":"{ _service { sdl } }"}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["_service"]["sdl"])'
}
sdl "$CATALOG" > gateway/sdl/catalog.graphql
sdl "$PERSONALIZATION" > gateway/sdl/personalization.graphql

step "Composing the supergraph"
(cd gateway && npx hive dev \
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
