#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."

target=${1:-backups/shorecat-$(date +%Y%m%d-%H%M%S).tar.gz}
if [[ -e "$target" ]]; then
  echo "Refusing to overwrite $target" >&2
  exit 1
fi
mkdir -p "$(dirname "$target")"
temporary=$(mktemp "$target.XXXXXX")
is_running=$(docker compose ps --status running -q shorecat)
finish() {
  result=$?
  trap - EXIT
  rm -f "$temporary"
  if [[ -n "$is_running" ]]; then
    docker compose start --wait --wait-timeout 60 shorecat || result=1
  fi
  exit "$result"
}
trap finish EXIT
docker compose stop shorecat
docker compose run --rm --no-deps -T --user 0 --entrypoint tar \
  shorecat -czf - -C /data . > "$temporary"
mv "$temporary" "$target"
echo "Backup saved to $target"
