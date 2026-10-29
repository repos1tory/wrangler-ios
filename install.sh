#!/bin/sh
# install.sh — install Cloudflare Wrangler on a jailbroken (rootless) iOS device.
#
# Run ON the device (iPhone/iPad, arm64, iOS 15+, palera1n rootless or Dopamine):
#
#   curl -fsSL https://raw.githubusercontent.com/repos1tory/wrangler-ios/main/install.sh | sh
#
# or from a checkout:
#
#   sh install.sh
#
# What it does:
#   1. makes sure node-ios (the patched Node build) is installed — bootstraps it if missing
#   2. downloads the pre-built wrangler dependency bundle from this repo's release
#   3. installs it to $PREFIX/usr/lib/wrangler (NOT npm's global prefix)
#   4. writes a $PREFIX/usr/bin/wrangler launcher
#   5. verifies with `wrangler --version` and `wrangler --help`
#
# Requires: sudo (rootless bootstrap is root-owned), curl, tar. gzip is not
# required: the bundle is decompressed with the Node that is already needed.
#
# Env overrides: PREFIX (default /var/jb), SUDO (default "sudo"),
#                WRANGLER_VERSION (default 4.151.0-2), BUNDLE_FILE (use a local
#                tarball instead of downloading), NODE_REPO, REPO.
set -eu
umask 022

PREFIX="${PREFIX:-/var/jb}"
SUDO="${SUDO:-sudo}"
WRANGLER_VERSION="${WRANGLER_VERSION:-4.151.0-2}"
REPO="${REPO:-repos1tory/wrangler-ios}"
NODE_REPO="${NODE_REPO:-repos1tory/node-ios}"
BUNDLE_FILE="${BUNDLE_FILE:-}"
export PREFIX SUDO

BUNDLE_URL="https://github.com/${REPO}/releases/download/v${WRANGLER_VERSION}/wrangler-ios-bundle.tar.gz"

say()  { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- sanity checks -----------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || fail "this installer is for iOS (Darwin), got: $(uname -s)"

if [ ! -d "$PREFIX" ]; then
  fail "no $PREFIX found — this looks like a rootful or non-jailbroken setup.
     Rootless jailbreaks (palera1n rootless, Dopamine) mount the bootstrap at /var/jb."
fi

command -v curl >/dev/null 2>&1 || fail "curl not found."
command -v tar  >/dev/null 2>&1 || fail "tar not found (install 'tar' from Sileo/Zebra)."

TMP="$(mktemp -d "${TMPDIR:-/tmp}/wrangler-ios-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# --- node-ios (bootstrap if missing) ----------------------------------------
if [ -x "$PREFIX/usr/bin/node" ] || [ -x "$PREFIX/usr/lib/nodejs/node" ] ||
   command -v node >/dev/null 2>&1; then
  say "==> node-ios present: $(node --version 2>/dev/null || echo '(via PATH)')"
else
  say "==> node-ios not found — installing it first (see ${NODE_REPO})"
  curl -fsSL -o "$TMP/node-install.sh" \
    "https://raw.githubusercontent.com/${NODE_REPO}/main/scripts/install-on-device.sh"
  sh "$TMP/node-install.sh"
fi

# Resolve the Node launcher at install time for the decompression step. The
# installed wrapper resolves it again at runtime, so moving Node does not break
# the package.
NODE_EXEC=""
for candidate in "$PREFIX/usr/bin/node" "$PREFIX/usr/lib/nodejs/node"; do
  if [ -x "$candidate" ]; then NODE_EXEC="$candidate"; break; fi
done
if [ -z "$NODE_EXEC" ] && command -v node >/dev/null 2>&1; then
  NODE_EXEC="$(command -v node)"
fi
[ -n "$NODE_EXEC" ] || fail "Node.js 22.19+ not found after node-ios setup."

# --- download the wrangler bundle -------------------------------------------
if [ -n "$BUNDLE_FILE" ]; then
  say "==> using local bundle: $BUNDLE_FILE"
  cp "$BUNDLE_FILE" "$TMP/wrangler-ios-bundle.tar.gz"
else
  say "==> downloading wrangler ${WRANGLER_VERSION} bundle"
  curl -fL --progress-bar -o "$TMP/wrangler-ios-bundle.tar.gz" "$BUNDLE_URL"
fi

# gzip(1) is not guaranteed on a rootless bootstrap; Node already is.
"$NODE_EXEC" -e '
  const fs = require("fs"), zlib = require("zlib");
  fs.writeFileSync(process.argv[2], zlib.gunzipSync(fs.readFileSync(process.argv[1])));
' "$TMP/wrangler-ios-bundle.tar.gz" "$TMP/wrangler-ios-bundle.tar"

# --- install -----------------------------------------------------------------
say "==> installing to $PREFIX/usr/lib/wrangler/"
$SUDO mkdir -p "$PREFIX/usr/lib/wrangler" "$PREFIX/usr/bin"
$SUDO chmod 755 "$PREFIX/usr/lib/wrangler" "$PREFIX/usr/bin"
$SUDO tar -xf "$TMP/wrangler-ios-bundle.tar" -C "$PREFIX/usr/lib/wrangler"
$SUDO chmod -R a+rX "$PREFIX/usr/lib/wrangler"

say "==> writing $PREFIX/usr/bin/wrangler launcher"
# NOTE: shebang is /var/jb/bin/sh, not /bin/sh -- rootless jailbreaks have no /bin/sh.
$SUDO tee "$PREFIX/usr/bin/wrangler" >/dev/null <<'SHIM'
#!/var/jb/bin/sh
set -eu
PREFIX="${PREFIX:-/var/jb}"
DIR="${WRANGLER_IOS_DIR:-$PREFIX/usr/lib/wrangler}"
ENTRY="$DIR/node_modules/wrangler/bin/wrangler.js"
[ -f "$ENTRY" ] || { echo "wrangler: runtime not found at $ENTRY" >&2; exit 127; }
NODE="${WRANGLER_IOS_NODE:-}"
if [ -z "$NODE" ]; then
  for candidate in "$PREFIX/usr/bin/node" "$PREFIX/usr/lib/nodejs/node" \
                   "$PREFIX/usr/lib/opencode-ios/node"; do
    if [ -x "$candidate" ]; then NODE="$candidate"; break; fi
  done
fi
if [ -z "$NODE" ]; then NODE="$(command -v node 2>/dev/null || true)"; fi
[ -n "$NODE" ] || { echo "wrangler: Node.js 22.19+ is required" >&2; exit 127; }
export PATH="$PREFIX/usr/bin:${PATH:-/usr/bin:/bin}"
export WRANGLER_IOS_WORKERD="${WRANGLER_IOS_WORKERD:-$PREFIX/usr/bin/workerd-ios-unavailable}"
exec "$NODE" --predictable --single-threaded --disable-wasm-trap-handler "$ENTRY" "$@"
SHIM
$SUDO chmod 755 "$PREFIX/usr/bin/wrangler"

# --- verify ------------------------------------------------------------------
say "==> verifying"
"$PREFIX/usr/bin/wrangler" --version
"$PREFIX/usr/bin/wrangler" --help >/dev/null

say ""
say "Done."
say "Authenticate with the device-code flow (works from any browser):"
say "    wrangler login --device --browser=false"
say "or export a CLOUDFLARE_API_TOKEN. Then, in your project:"
say "    wrangler deploy --dry-run   # bundle locally"
say "    wrangler deploy             # ship it"
