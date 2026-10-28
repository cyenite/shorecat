#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

dart pub get
for package in packages/shorecat_code_push packages/shorecat_code_push/example; do
  if [[ "$package" == */example ]]; then
    prefix=../..
  else
    prefix=..
  fi
  cat > "$package/pubspec_overrides.yaml" <<EOF
dependency_overrides:
  shorecat_core:
    path: $prefix/shorecat_core
  shorecat_updater:
    path: $prefix/shorecat_updater
EOF
done
(cd packages/shorecat_code_push && flutter pub get)
(cd packages/shorecat_dashboard && flutter pub get)
