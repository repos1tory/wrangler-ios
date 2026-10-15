#!/bin/sh
# install.sh — install Cloudflare Wrangler on a jailbroken (rootless) iOS device.
#
# Run ON the device (iPhone/iPad, arm64, iOS 15+, Dopamine-style rootless jb):
#
#   curl -fsSL https://raw.githubusercontent.com/al5ina5/wrangler-ios/main/install.sh | sh
#
# or from a checkout:
#
#   sh install.sh
#
# What it does:
#   1. makes sure node-ios (the patched Node build) is installed — bootstraps it if missing
#   2. downloads the pre-built wrangler dependency bundle from this repo's release
#   3. installs it to $PREFIX/usr/lib/wrangler
#   4. writes a $PREFIX/usr/bin/wrangler shim
#   5. verifies with `wrangler --version`
#
# Requires: sudo (device is rootless; /var/jb is root-owned), curl, tar.
#
# Env overrides: PREFIX (default /var/jb), SUDO (default "sudo"),
#                WRANGLER_VERSION (default 4.151.0), BUNDLE_FILE (use a local tarball
#                instead of downloading — handy for testing), NODE_REPO, REPO.
set -eu
umask 022

PREFIX="${PREFIX:-/var/jb}"
SUDO="${SUDO:-sudo}"
WRANGLER_VERSION="${WRANGLER_VERSION:-4.151.0}"
REPO="${REPO:-al5ina5/wrangler-ios}"
NODE_REPO="${NODE_REPO:-al5ina5/node-ios}"
BUNDLE_FILE="${BUNDLE_FILE:-}"
export PREFIX SUDO

BUNDLE_URL="https://github.com/${REPO}/releases/download/v${WRANGLER_VERSION}/wrangler-ios-bundle.tar.gz"

say()  { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- sanity checks -----------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || fail "this installer is for iOS (Darwin), got: $(uname -s)"

if [ ! -d "$PREFIX" ]; then
  fail "no $PREFIX found — this looks like a rootful or non-jailbroken setup.
     Rootless jailbreaks (Dopamine, palera1n rootless) mount the bootstrap at /var/jb."
fi

command -v curl >/dev/null 2>&1 || fail "curl not found."
command -v tar  >/dev/null 2>&1 || fail "tar not found (install 'tar' from Sileo/Zebra)."

# --- node-ios (bootstrap if missing) ----------------------------------------
if [ -x "$PREFIX/usr/bin/node" ] || command -v node >/dev/null 2>&1; then
  say "==> node-ios present: $(node --version 2>/dev/null || echo '(via PATH)')"
else
  say "==> node-ios not found — installing it first (see ${NODE_REPO})"
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT
  curl -fsSL -o "$TMPD/node-install.sh" \
    "https://raw.githubusercontent.com/${NODE_REPO}/main/scripts/install-on-device.sh"
  sh "$TMPD/node-install.sh"
fi

# pick the node used by the wrangler shim
if [ -x "$PREFIX/usr/bin/node" ]; then
  NODE_EXEC="$PREFIX/usr/bin/node"
else
  NODE_EXEC="node"
fi

# --- download the wrangler bundle -------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "$BUNDLE_FILE" ]; then
  say "==> using local bundle: $BUNDLE_FILE"
  cp "$BUNDLE_FILE" "$TMP/wrangler-ios-bundle.tar.gz"
else
  say "==> downloading wrangler ${WRANGLER_VERSION} bundle"
  curl -fL --progress-bar -o "$TMP/wrangler-ios-bundle.tar.gz" "$BUNDLE_URL"
fi

# --- install -----------------------------------------------------------------
say "==> installing to $PREFIX/usr/lib/wrangler/"
$SUDO mkdir -p "$PREFIX/usr/lib/wrangler" "$PREFIX/usr/bin"
$SUDO chmod 755 "$PREFIX/usr/lib/wrangler" "$PREFIX/usr/bin"
$SUDO tar -xzf "$TMP/wrangler-ios-bundle.tar.gz" -C "$PREFIX/usr/lib/wrangler"
$SUDO chmod -R a+rX "$PREFIX/usr/lib/wrangler"

say "==> writing $PREFIX/usr/bin/wrangler shim"
# NOTE: shebang is /var/jb/bin/sh, not /bin/sh -- rootless jailbreaks have no /bin/sh.
$SUDO tee "$PREFIX/usr/bin/wrangler" >/dev/null <<SHIM
#!/var/jb/bin/sh
# wrangler-ios shim — runs the wrangler CLI through node-ios, whose shim adds the
# flags the W^X JIT patch and wasm memory need (--predictable --single-threaded
# --disable-wasm-trap-handler).
exec "$NODE_EXEC" "$PREFIX/usr/lib/wrangler/node_modules/wrangler/bin/wrangler.js" "\$@"
SHIM
$SUDO chmod 755 "$PREFIX/usr/bin/wrangler"

# --- verify ------------------------------------------------------------------
say "==> verifying"
"$PREFIX/usr/bin/wrangler" --version

say ""
say "Done."
say "Authenticate with the device-code flow (works from any browser):"
say "    wrangler login --device --browser=false"
say "or export a CLOUDFLARE_API_TOKEN. Then, in your project:"
say "    wrangler deploy --dry-run   # bundle locally"
say "    wrangler deploy             # ship it"
