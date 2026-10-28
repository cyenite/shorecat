#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
image=${1:?Usage: bash tool/smoke-deployment.sh <image>}
project=shorecat-backup-smoke-$RANDOM-$$
temporary=$(mktemp -d)
cp compose.yaml "$temporary/"
mkdir "$temporary/tool"
cp tool/backup.sh tool/restore.sh "$temporary/tool/"
cat > "$temporary/.env" <<EOF
SHORECAT_IMAGE=$image
SHORECAT_PUBLIC_URL=http://localhost:8787
SHORECAT_PORT=0
EOF
cd "$temporary"
export COMPOSE_PROJECT_NAME="$project"
finish() {
  result=$?
  trap - EXIT
  if [[ $result -ne 0 ]]; then docker compose logs >&2 || true; fi
  docker compose down --volumes > /dev/null 2>&1 || true
  rm -rf "$temporary"
  exit "$result"
}
trap finish EXIT
docker compose up -d --wait --wait-timeout 60
address=$(docker compose port shorecat 8080)
token=$(docker compose exec -T shorecat cat /data/admin-token)
curl --fail --silent --show-error -X POST "http://$address/api/v1/apps" \
  -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
  -d '{"id":"backup-smoke","name":"Before backup","public_keys":["ed25519:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="]}' > /dev/null
bash tool/backup.sh backup.tar.gz
address=$(docker compose port shorecat 8080)
curl --fail --silent --show-error -X PATCH "http://$address/api/v1/apps/backup-smoke" \
  -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
  -d '{"name":"After backup"}' > /dev/null
bash tool/restore.sh backup.tar.gz --replace-data
docker compose up -d --wait --wait-timeout 60
address=$(docker compose port shorecat 8080)
curl --fail --silent --show-error "http://$address/api/v1/apps/backup-smoke" \
  -H "Authorization: Bearer $token" > restored.json
grep -q 'Before backup' restored.json
if grep -q 'After backup' restored.json; then exit 1; fi
echo 'Deployment backup and restore checks passed.'
