# wrangler-ios

### Cloudflare Wrangler 4.x running natively on jailbroken iOS (arm64)

Bundle, dry-run and **deploy Cloudflare Workers directly from an iPhone or
iPad** — no Mac, no PC, no SSH session into another machine. Wrangler runs as
plain Node.js on-device, with its bundler swapped to the pure-WebAssembly
esbuild so no native binary is needed.

Verified on an **iPad7,5 (A10), iPadOS 17.7.8, Dopamine rootless**, with
[`nodejs`](https://github.com/repos1tory/node-ios) 22.19.0-3. The same layout
is used by **palera1n rootless**: both jailbreaks mount the bootstrap at
`/var/jb`, and nothing in the package depends on a preboot UUID or on the
jailbreak's name.

```
$ wrangler --version
4.151.0

$ wrangler deploy --dry-run
Total Upload: 0.15 KiB / gzip: 0.14 KiB
--dry-run: exiting now.
```

## Requirements

- Jailbroken **rootless** iOS 15+ device (arm64) — palera1n rootless or
  Dopamine.
- [`nodejs`](https://github.com/repos1tory/node-ios) 22.19.0 or newer
  (`node` on `PATH`, installed under `/var/jb`).
- `sudo` for the standalone installer. Installing from Sileo/APT does not need
  a shell password.

## Install

From the repos1tory (recommended):

```
https://repos1tory.github.io/
```

Install **Wrangler** from Sileo/Zebra. The repository is signed; see the
[repository key instructions](https://repos1tory.github.io/#repository-key) if
your client still says “unauthenticated”.

Or use the standalone installer:

```sh
curl -fsSL https://raw.githubusercontent.com/repos1tory/wrangler-ios/main/install.sh | sh
```

The installer:

1. checks (or installs) node-ios — the patched Node build;
2. downloads the pre-built Wrangler dependency bundle from this repo's release;
3. installs it to `/var/jb/usr/lib/wrangler/` (not npm's global prefix);
4. writes a `/var/jb/usr/bin/wrangler` launcher;
5. verifies with `wrangler --version` and `wrangler --help`.

Manual install from a checkout:

```sh
sh scripts/build-deb.sh
sudo dpkg -i dist/wrangler-ios_4.151.0-2_iphoneos-arm64.deb
wrangler --version
```

Uninstall:

```sh
sudo dpkg -r wrangler-ios
# or, for the standalone installer:
sudo rm -rf /var/jb/usr/lib/wrangler /var/jb/usr/bin/wrangler
```

## Authenticate

The browser-redirect flow (`wrangler login`) does not work reliably on iOS —
the OAuth callback (`http://localhost:8976/...`) requires the browser to reach
a server running on the device. Use the **device-code flow** instead:

```sh
wrangler login --device --browser=false
```

Wrangler prints a link (`https://dash.cloudflare.com/oauth2/device/verify`) and
an 8-character code. Open the link anywhere, enter the code, approve — the
token lands in `~/.config/.wrangler/config/default.toml`.

Alternatively, skip OAuth entirely with an API token:

```sh
export CLOUDFLARE_API_TOKEN=...
```

Check the restored session with:

```sh
wrangler whoami
```

### Switched jailbreaks and lost your login?

The Wrangler token lives in the *user home* of the bootstrap, not on the
rootfs. When you move from palera1n to Dopamine (or back), the old bootstrap
usually remains under `/private/preboot/<device-uuid>/jb-*` while `/var/jb`
points at the new one. Copy the config from the old home — do not paste the
token into a chat or commit it:

```sh
OLD=/private/preboot/<device-uuid>/jb-<id>/procursus/var/mobile
mkdir -p ~/.config/.wrangler/config
cp -p "$OLD/.config/.wrangler/config/default.toml" \
      ~/.config/.wrangler/config/default.toml
chmod 600 ~/.config/.wrangler/config/default.toml
wrangler whoami
```

The same applies to `~/.npmrc`, `~/.gitconfig`, and `~/.config/gh/` if you use
them. Keep those files at mode `600`; they contain credentials.

## What works / what doesn't

| | |
|---|---|
| `wrangler deploy` (Workers) | ✅ verified on-device, end-to-end |
| `wrangler deploy --dry-run` / bundling (esbuild-wasm) | ✅ verified on-device |
| `wrangler --version`, `wrangler --help` | ✅ verified on-device |
| `wrangler whoami`, `wrangler login --device` | ✅ verified on-device |
| KV / R2 / D1 / secrets commands (API-based) | ✅ in principle — plain HTTP + JS |
| `wrangler dev` **local** | ❌ requires `workerd`, which has no iOS build |
| `wrangler dev --remote` | ⚠️ untested (HTTP-only, should work) |
| `wrangler pages ...` | ⚠️ untested |

## How it works

- **esbuild → esbuild-wasm alias.** Wrangler bundles your worker with esbuild.
  The native esbuild binary cannot run on iOS, so this install uses the npm
  alias trick in `package.json`:

  ```json
  { "dependencies": { "esbuild": "npm:esbuild-wasm@^0.28.2", "wrangler": "^4.151.0" } }
  ```

- **esbuild’s child process is launched explicitly.** Upstream
  `esbuild-wasm` runs the literal command `node` from `PATH`. On iOS that is
  normally the node-ios shell shim, and Dopamine refuses to `posix_spawn` a
  script (`EPERM`). `scripts/patch-ios.mjs` changes the spawn to
  `process.execPath` — the real Mach-O — and passes the node-ios flags,
  including `--no-wasm-lazy-compilation` and `--liftoff-only`. Those two flags
  avoid a V8 wasm tier-up crash against the iOS W^X patch. This is the
  difference between “wrangler --version works” and “wrangler can actually
  bundle”.

- **The wasm-memory flag matters.** Wrangler's dependency `blake3-wasm`
  allocates a `WebAssembly.Memory` at startup. On the iOS VA cap, V8's default
  10GB guarded reservation makes that fail — that's why Node is run with
  `--disable-wasm-trap-handler`.

- **workerd is deferred, not shipped.** Wrangler imports its local runtime
  eagerly. The patch returns a placeholder path on iOS so API/deploy commands
  start; `wrangler dev` then gets a clear “no iOS port” error instead of
  crashing at startup.

- **No npm global prefix.** The package lives entirely under
  `/var/jb/usr/lib/wrangler` and the launcher calls the entry point by
  absolute path. It does not run `npm -g`, does not use
  `$PREFIX/usr/lib/lib/node_modules`, and is unaffected by npm's Procursus
  prefix quirks. If you also use npm, put a user-writable prefix in
  `~/.npmrc`:

  ```sh
  echo 'prefix=/var/jb/var/mobile/.local/npm-global' >> ~/.npmrc
  ```

## Build and test

The deb is reproducible from this checkout:

```sh
sh scripts/build-deb.sh                 # -> dist/wrangler-ios_4.151.0-2_iphoneos-arm64.deb
sh scripts/test-package.sh dist/*.deb   # extracts it, runs version/help/dry-run
sh scripts/check-jailbreak.sh           # rejects preboot/Dopamine-specific paths
```

`test-package.sh` runs the launcher from a temporary root, so it does not need
root and does not touch `/var/jb`. CI runs the same commands on Node 22.19.

On-device tests used for the 4.151.0-2 release:

```sh
wrangler --version
wrangler --help
wrangler deploy --dry-run --outdir /tmp/wrangler-out
wrangler whoami
```

`wrangler whoami` and `wrangler deploy` require a Cloudflare login; the
dry-run bundle and the first two commands are offline. Named-tunnel and
account-changing tests are intentionally not automated.

## License

MIT — see [LICENSE](LICENSE). Wrangler is MIT-licensed by Cloudflare; this repo
only repackages it with iOS-compatible runtime patches.
