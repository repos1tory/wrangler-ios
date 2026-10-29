#!/bin/sh
# check-jailbreak.sh — guard against jailbreak-specific absolute paths in the
# runtime files. Both palera1n rootless and Dopamine rootless mount the
# bootstrap at /var/jb; nothing here may depend on a preboot UUID or on the
# name of the jailbreak.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bad=0
for f in install.sh scripts/*.sh scripts/*.mjs shims/*; do
  [ -f "$f" ] || continue
  [ "$f" = "scripts/check-jailbreak.sh" ] && continue
  if grep -nE '/private/preboot|dopamine-[A-Za-z0-9]|jb-[A-Za-z0-9]{4,}' "$f"; then
    echo "FAIL: jailbreak-specific path in $f" >&2
    bad=1
  fi
done

grep -q 'PREFIX="${PREFIX:-/var/jb}"' scripts/wrangler-wrapper.sh || {
  echo "FAIL: launcher does not default to /var/jb" >&2
  bad=1
}
grep -q 'WRANGLER_IOS_DIR' scripts/wrangler-wrapper.sh || {
  echo "FAIL: launcher lacks WRANGLER_IOS_DIR override" >&2
  bad=1
}

[ "$bad" -eq 0 ] || exit 1
echo "PASS: runtime files are jailbreak-neutral (palera1n/Dopamine rootless)"
