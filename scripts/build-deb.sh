#!/bin/sh
# build-deb.sh — build the rootless iphoneos-arm64 Wrangler package.
#
#   sh scripts/build-deb.sh [wrangler-npm-version]
#
# Produces:
#   dist/wrangler-ios_<version>-<revision>_iphoneos-arm64.deb
#   dist/wrangler-ios-bundle.tar.gz        (for install.sh / release asset)
#
# Runs on Linux, macOS, or the jailbroken device. Needs node, npm, tar and
# dpkg-deb. It does not need sudo and never writes outside this checkout.
set -eu
umask 022

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
VERSION="${1:-4.151.0}"
REVISION="${PACKAGE_REVISION:-2}"
WORK="$ROOT/build"
PKG="$WORK/pkg"
DIST="$ROOT/dist"
LIB="$PKG/var/jb/usr/lib/wrangler"

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

for tool in node npm tar dpkg-deb; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool: $tool"
done

rm -rf "$PKG"
mkdir -p "$LIB" \
         "$PKG/DEBIAN" \
         "$PKG/var/jb/usr/bin" \
         "$PKG/var/jb/usr/share/doc/wrangler-ios" \
         "$DIST"

say "==> installing npm dependencies into the package payload"
cp "$ROOT/package.json" "$ROOT/package-lock.json" "$LIB/"
( cd "$LIB" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund )

say "==> applying iOS runtime patches"
node "$ROOT/scripts/patch-ios.mjs" "$LIB/node_modules"
node "$ROOT/scripts/patch-ios.mjs" --check "$LIB/node_modules"

say "==> staging launcher and docs"
cp "$ROOT/scripts/wrangler-wrapper.sh" "$PKG/var/jb/usr/bin/wrangler"
cp "$ROOT/scripts/workerd-ios-unavailable" "$PKG/var/jb/usr/bin/workerd-ios-unavailable"
cp "$ROOT/README.md" "$ROOT/LICENSE" "$PKG/var/jb/usr/share/doc/wrangler-ios/"
chmod 755 "$PKG/var/jb/usr/bin/wrangler" "$PKG/var/jb/usr/bin/workerd-ios-unavailable"
chmod 644 "$LIB/package.json" "$LIB/package-lock.json" \
          "$PKG/var/jb/usr/share/doc/wrangler-ios/README.md" \
          "$PKG/var/jb/usr/share/doc/wrangler-ios/LICENSE"

SIZE="$(du -sk "$PKG/var" | cut -f1)"
cat > "$PKG/DEBIAN/control" <<EOF
Package: wrangler-ios
Version: ${VERSION}-${REVISION}
Architecture: iphoneos-arm64
Maintainer: Alsinas Labs
Section: Development
Priority: optional
Depends: firmware (>= 15.0), nodejs (>= 22.19.0)
Homepage: https://github.com/repos1tory/wrangler-ios
Description: Cloudflare Wrangler CLI for jailbroken iOS arm64
 API, authentication, and deployment CLI. Bundles esbuild-wasm (no native
 esbuild binary needed) and defers workerd's unsupported-platform error so
 deploy commands run on iOS. The esbuild-wasm child is launched through the
 real Node executable with iOS-safe wasm flags, so it works on both palera1n
 and Dopamine rootless jailbreaks. Authenticate with "wrangler login --device";
 local "wrangler dev" is unavailable because Cloudflare workerd has no iOS
 runtime build.
EOF

say "==> writing .deb"
DEB="$DIST/wrangler-ios_${VERSION}-${REVISION}_iphoneos-arm64.deb"
if ! dpkg-deb --build --root-owner-group "$PKG" "$DEB" 2>/dev/null; then
  dpkg-deb --build "$PKG" "$DEB"
fi

say "==> writing install.sh bundle"
tar -cf "$WORK/wrangler-ios-bundle.tar" -C "$LIB" node_modules package.json package-lock.json
node "$ROOT/scripts/gzip.mjs" "$WORK/wrangler-ios-bundle.tar" \
  "$DIST/wrangler-ios-bundle.tar.gz"

say ""
say "deb:    $DEB"
say "bundle: $DIST/wrangler-ios-bundle.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then
  say "sha256: $(sha256sum "$DEB" | cut -d' ' -f1)"
else
  say "sha256: $(shasum -a 256 "$DEB" | cut -d' ' -f1)"
fi
