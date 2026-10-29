#!/bin/sh
# test-package.sh — exercise a built wrangler-ios .deb without installing it.
#
#   sh scripts/test-package.sh dist/wrangler-ios_*.deb
#
# On Linux this drives the package through an "iOS platform" shim so the same
# code paths used on-device are tested in CI. On iOS it runs the launcher
# directly.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DEB="${1:-}"
[ -n "$DEB" ] && [ -f "$DEB" ] || {
  echo "usage: test-package.sh <wrangler-ios .deb>" >&2
  exit 2
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wrangler-ios-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

dpkg-deb -x "$DEB" "$TMP/root"
PREFIX="$TMP/root/var/jb"
WRANGLER="$PREFIX/usr/bin/wrangler"
ENTRY="$PREFIX/usr/lib/wrangler/node_modules/wrangler/bin/wrangler.js"

[ -x "$WRANGLER" ] || { echo "FAIL: launcher missing" >&2; exit 1; }
[ -f "$ENTRY" ] || { echo "FAIL: wrangler entry missing" >&2; exit 1; }
[ -x "$PREFIX/usr/bin/workerd-ios-unavailable" ] || {
  echo "FAIL: workerd placeholder missing" >&2
  exit 1
}
[ -f "$PREFIX/usr/lib/wrangler/node_modules/esbuild/lib/main.js" ] || {
  echo "FAIL: esbuild-wasm missing" >&2
  exit 1
}

export WRANGLER_SEND_METRICS=false
export CI=1
export NO_UPDATE_NOTIFIER=1

echo "==> wrangler --version"
VERSION_OUT="$(PREFIX="$PREFIX" sh "$WRANGLER" --version 2>&1)"
printf '%s\n' "$VERSION_OUT"
printf '%s\n' "$VERSION_OUT" | grep -q '4\.151\.' || {
  echo "FAIL: unexpected version output" >&2
  exit 1
}

echo "==> wrangler --help"
HELP_OUT="$(PREFIX="$PREFIX" sh "$WRANGLER" --help 2>&1)"
printf '%s\n' "$HELP_OUT" | grep -q 'COMMANDS' || {
  echo "FAIL: help output missing COMMANDS" >&2
  exit 1
}

echo "==> wrangler deploy --dry-run (esbuild-wasm)"
FIXTURE="$TMP/fixture"
OUTDIR="$TMP/out"
mkdir -p "$FIXTURE"
cat > "$FIXTURE/wrangler.toml" <<'EOF'
name = "ios-port-smoke"
main = "index.js"
compatibility_date = "2026-10-12"
EOF
cat > "$FIXTURE/index.js" <<'EOF'
export default { fetch() { return new Response("ok"); } };
EOF

if [ -d /var/jb ] && [ "$(uname -s)" = "Darwin" ]; then
  # On iOS the launcher already sees process.platform === "ios".
  ( cd "$FIXTURE" && PREFIX="$PREFIX" sh "$WRANGLER" deploy --dry-run --outdir "$OUTDIR" )
else
  # Use the same iOS branch on Linux/macOS CI runners. --require keeps the
  # Wrangler entry as the main module, which its bin wrapper checks.
  ( cd "$FIXTURE" && WRANGLER_IOS_WORKERD="$PREFIX/usr/bin/workerd-ios-unavailable" \
      node --predictable --single-threaded --disable-wasm-trap-handler \
        --require "$ROOT/scripts/ios-preload.cjs" "$ENTRY" deploy --dry-run --outdir "$OUTDIR" )
fi

[ -s "$OUTDIR/index.js" ] || { echo "FAIL: dry-run produced no index.js" >&2; exit 1; }
grep -q 'fetch' "$OUTDIR/index.js" || { echo "FAIL: dry-run bundle looks wrong" >&2; exit 1; }

echo "PASS: wrangler package smoke test"
