#!/bin/sh
# build-bundle.sh — build wrangler-ios-bundle.tar.gz, the release asset that
# install.sh downloads. Run on a machine with npm + network access.
#
#   sh scripts/build-bundle.sh
#
# The trick is in package.json: "esbuild" is aliased to "esbuild-wasm", so
# wrangler's bundler works without any native binary.
set -eu
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp package.json package-lock.json "$WORK/"
( cd "$WORK" && npm install --omit=dev --no-audit --no-fund )

mkdir -p build
tar -czf build/wrangler-ios-bundle.tar.gz -C "$WORK" node_modules package.json package-lock.json
echo "built build/wrangler-ios-bundle.tar.gz ($(du -h build/wrangler-ios-bundle.tar.gz | cut -f1))"
