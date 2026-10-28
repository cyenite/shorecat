#!/usr/bin/env bash
set -euo pipefail
image=${1:?Usage: bash tool/smoke-container.sh <image>}
name=shorecat-smoke-$RANDOM-$$
volume=$name-data
temporary=$(mktemp -d)
finish() {
  result=$?
  trap - EXIT
  if [[ $result -ne 0 ]]; then docker logs "$name" >&2 || true; fi
  docker rm -f "$name" > /dev/null 2>&1 || true
  docker volume rm "$volume" > /dev/null 2>&1 || true
  rm -rf "$temporary"
  exit "$result"
}
trap finish EXIT
docker volume create "$volume" > /dev/null
docker run -d --name "$name" -v "$volume:/data" \
  -p 127.0.0.1::8080 "$image" > /dev/null
for attempt in {1..30}; do
  if docker exec "$name" /app/shorecat_server --health-check; then break; fi
  sleep 1
done
docker exec "$name" /app/shorecat_server --health-check
port=$(docker inspect -f '{{(index (index .NetworkSettings.Ports "8080/tcp") 0).HostPort}}' "$name")
curl --fail --silent --show-error "http://127.0.0.1:$port/" > "$temporary/served.html"
docker cp "$name:/app/dashboard/index.html" "$temporary/index.html"
test -s "$temporary/index.html"
cmp "$temporary/index.html" "$temporary/served.html"
curl --fail --silent --show-error --output /dev/null "http://127.0.0.1:$port/main.dart.js"
docker exec "$name" sh -c 'test "$(id -u)" = 10001'
docker exec "$name" cat /data/admin-token > "$temporary/token"
test -s "$temporary/token"
if docker logs "$name" 2>&1 | grep -Fq -f "$temporary/token"; then
  echo 'Admin token leaked into container logs' >&2
  exit 1
fi
docker stop --time 15 "$name" > /dev/null
test "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = 0
docker cp "$name:/data/telemetry.json" "$temporary/telemetry.json"
docker start "$name" > /dev/null
for attempt in {1..30}; do
  if docker exec "$name" /app/shorecat_server --health-check; then break; fi
  sleep 1
done
docker exec "$name" /app/shorecat_server --health-check
docker exec "$name" cat /data/admin-token > "$temporary/restarted-token"
cmp "$temporary/token" "$temporary/restarted-token"
echo 'Container smoke checks passed.'
