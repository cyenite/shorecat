#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

package=${1:?Usage: bash tool/stage-package.sh <package> <new-absolute-directory>}
target=${2:?Supply a new absolute staging directory}
case "$package" in
  shorecat_core|shorecat_server|shorecat_updater|shorecat_cli|shorecat_code_push) ;;
  *) echo "Unknown distributable package: $package" >&2; exit 64 ;;
esac
if [[ "$target" != /* || -e "$target" ]]; then
  echo 'Staging directory must be absolute and must not exist.' >&2
  exit 64
fi
mkdir -p "$target"
tar -C "packages/$package" --exclude=.dart_tool --exclude=build \
  --exclude=.gradle --exclude=.idea --exclude=pubspec.lock \
  --exclude=pubspec_overrides.yaml --exclude=local.properties \
  -cf - . | tar -xf - -C "$target"
sed -i '/^resolution: workspace$/d' "$target/pubspec.yaml"
echo "Staged $package in $target"
