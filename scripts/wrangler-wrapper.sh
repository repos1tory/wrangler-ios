#!/var/jb/bin/sh
# wrangler-ios launcher.
#
# The package is self-contained under $PREFIX/usr/lib/wrangler and does not use
# npm's global prefix. PREFIX and WRANGLER_IOS_DIR exist so the same payload can
# be exercised from a staged/isolated root during tests.
set -eu

PREFIX="${PREFIX:-/var/jb}"
DIR="${WRANGLER_IOS_DIR:-$PREFIX/usr/lib/wrangler}"
ENTRY="$DIR/node_modules/wrangler/bin/wrangler.js"

if [ ! -f "$ENTRY" ]; then
  echo "wrangler: runtime not found at $ENTRY" >&2
  echo "wrangler: reinstall the wrangler-ios package (or set WRANGLER_IOS_DIR)" >&2
  exit 127
fi

# Prefer the packaged node-ios shim; fall back to a real binary or PATH. The
# shim execs the real Mach-O, so child processes see process.execPath as the
# real binary rather than a shell script.
NODE="${WRANGLER_IOS_NODE:-}"
if [ -z "$NODE" ]; then
  for candidate in \
    "$PREFIX/usr/bin/node" \
    "$PREFIX/usr/lib/nodejs/node" \
    "$PREFIX/usr/lib/opencode-ios/node"
  do
    if [ -x "$candidate" ]; then
      NODE="$candidate"
      break
    fi
  done
fi
if [ -z "$NODE" ]; then
  NODE="$(command -v node 2>/dev/null || true)"
fi
if [ -z "$NODE" ]; then
  echo "wrangler: Node.js 22.19+ is required (install the nodejs package)" >&2
  exit 127
fi

# esbuild's child process and any helper that looks for "node" should see the
# bootstrap tools first, regardless of the caller's login shell.
export PATH="$PREFIX/usr/bin:${PATH:-/usr/bin:/bin}"
export WRANGLER_IOS_WORKERD="${WRANGLER_IOS_WORKERD:-$PREFIX/usr/bin/workerd-ios-unavailable}"

exec "$NODE" \
  --predictable --single-threaded --disable-wasm-trap-handler \
  "$ENTRY" "$@"
