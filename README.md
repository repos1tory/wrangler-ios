# wrangler-ios

### Cloudflare Wrangler 4.x running natively on a jailbroken iPhone/iPad

Bundle, dry-run and **deploy Cloudflare Workers directly from an iPhone** — no Mac, no PC, no SSH
session into another machine. Wrangler runs as plain Node.js on-device, with its bundler swapped to
the pure-WebAssembly esbuild so no native binary is needed.

Proven on an **iPhone 6s Plus (A9), iOS 15.8.5, Dopamine (rootless)** together with
[**node-ios**](https://github.com/repos1tory/node-ios) (Node.js 22.19 with full JIT + WebAssembly).

```
$ wrangler deploy
Total Upload: 0.22 KiB / gzip: 0.17 KiB
Uploaded ios-demo (1.62 sec)
Deployed ios-demo triggers (0.65 sec)
  https://ios-demo.<account>.workers.dev
Current Version ID: 76cf8d5d-c34c-4ce3-8ebc-6cab27293a94
```

## Requirements

- Jailbroken **rootless** iOS 15+ device (arm64) — Dopamine, palera1n rootless, etc.
- [`node-ios`](https://github.com/repos1tory/node-ios) installed (`node` on `PATH` via its shim).
  The installer below can bootstrap it automatically if it's missing.
- `sudo` (the rootless bootstrap lives in `/var/jb`, owned by root).

## Install

On the device:

```sh
curl -fsSL https://raw.githubusercontent.com/repos1tory/wrangler-ios/main/install.sh | sh
```

The installer:

1. checks (or installs) node-ios — the patched Node build;
2. downloads the pre-built `wrangler` dependency bundle from this repo's release;
3. installs it to `/var/jb/usr/lib/wrangler/`;
4. writes a `/var/jb/usr/bin/wrangler` shim;
5. verifies with `wrangler --version`.

Then, in any project directory:

```sh
wrangler --version        # 4.151.0
wrangler deploy --dry-run # bundles locally (esbuild-wasm)
wrangler deploy           # ships it to Cloudflare
```

## Authenticating on iOS

The browser-redirect flow (`wrangler login`) does **not** work reliably on iOS — the OAuth callback
(`http://localhost:8976/...`) requires the browser to reach a server running on the device, which
Safari doesn't always do. Use the **device-code flow** instead; it works from any browser:

```sh
wrangler login --device --browser=false
```

Wrangler prints a link (`https://dash.cloudflare.com/oauth2/device/verify`) and an 8-character code.
Open the link anywhere, enter the code, approve — the token lands in
`~/.config/.wrangler/config/default.toml`.

Alternatively, skip OAuth entirely with an API token:

```sh
export CLOUDFLARE_API_TOKEN=...
```

## What works / what doesn't

| | |
|---|---|
| `wrangler deploy` (Workers) | ✅ verified on-device, end-to-end |
| `wrangler deploy --dry-run` / bundling (esbuild-wasm) | ✅ |
| `wrangler whoami`, `wrangler login --device` | ✅ |
| KV / R2 / D1 / secrets commands (API-based) | ✅ in principle — all plain HTTP + JS |
| `wrangler dev` **local** | ❌ requires `workerd`, a native macOS/Linux binary that can't exec on iOS |
| `wrangler dev --remote` | ⚠️ untested (request proxying is HTTP-only, so it should work) |
| `wrangler pages ...` | ⚠️ untested |

## How it works

- **esbuild → esbuild-wasm alias.** Wrangler bundles your worker with esbuild. The native esbuild
  binary can't run on iOS, so this install uses the standard npm alias trick in `package.json`:

  ```json
  { "dependencies": { "esbuild": "npm:esbuild-wasm@^0.28.2", "wrangler": "^4.151.0" } }
  ```

  Everything then runs through the WebAssembly build of esbuild, which the node-ios build can JIT.

- **The wasm-memory flag matters.** Wrangler's dependency `blake3-wasm` allocates a
  `WebAssembly.Memory` at startup. On the iOS VA cap, V8's default 10GB guarded reservation makes
  that fail — that's why node-ios is run with `--disable-wasm-trap-handler` (the shim does this
  automatically). The node-ios `entitlements.plist` also requests
  `com.apple.developer.kernel.extended-virtual-addressing` for headroom.

- **esbuild spawns `node` from `PATH`** to run its wasm service. The node-ios shim (with the
  required flags) is what makes those children work.

- **No shell needed.** esbuild's child processes are spawned directly (no `/bin/sh`), which matters
  because rootless iOS has no `/bin/sh` — but note that *other* tools using `execSync` defaults may
  need `{ shell: "/var/jb/bin/sh" }`.

## Manual install / uninstall

```sh
# manual: extract the release bundle yourself
curl -fL -o /tmp/wrangler.tar.gz https://github.com/repos1tory/wrangler-ios/releases/download/v4.151.0/wrangler-ios-bundle.tar.gz
sudo mkdir -p /var/jb/usr/lib/wrangler
sudo tar -xzf /tmp/wrangler.tar.gz -C /var/jb/usr/lib/wrangler

# uninstall
sudo rm -rf /var/jb/usr/lib/wrangler /var/jb/usr/bin/wrangler
```

## Rebuilding the dependency bundle (maintainers)

`package.json` + `package-lock.json` are the manifest. On any machine with npm and network:

```sh
sh scripts/build-bundle.sh   # produces wrangler-ios-bundle.tar.gz
```

Attach the tarball to a release tagged for the wrangler version (e.g. `v4.151.0`).

## License

MIT — see [LICENSE](LICENSE). Wrangler is MIT-licensed by Cloudflare; this repo only repackages it
with an iOS-compatible bundler.
