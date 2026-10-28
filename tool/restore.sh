#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 2 || "$2" != --replace-data || ! -f "$1" ]]; then
  echo "Usage: bash tool/restore.sh <backup.tar.gz> --replace-data" >&2
  echo "Replaces the current data volume. Make a backup first." >&2
  exit 64
fi
tar -tzf "$1" > /dev/null
docker compose stop shorecat
docker compose run --rm --no-deps -T --user 0 --entrypoint sh shorecat -ec \
  'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; tar -xzf - -C /data; chown -R 10001:10001 /data' < "$1"
docker compose up -d --wait --wait-timeout 60 shorecat
echo "Restore complete. Check docker compose ps and the dashboard."
