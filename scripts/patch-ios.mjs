#!/usr/bin/env node
// patch-ios.mjs — apply the two downstream runtime patches Wrangler needs on
// jailbroken iOS.
//
//   1. workerd: its npm package throws while being imported on an unsupported
//      platform, which also breaks API/deploy commands. Defer that error until
//      a command actually needs the local Worker runtime.
//   2. esbuild-wasm: upstream spawns the literal command "node" from PATH. On
//      iOS that is usually the node-ios shell shim, and Dopamine refuses to
//      posix_spawn a script (EPERM). It also starts a second V8 isolate that
//      needs the node-ios flags. Spawn process.execPath with explicit flags.
//
// Usage:
//   node scripts/patch-ios.mjs <node_modules>
//   node scripts/patch-ios.mjs --check <node_modules>
import fs from "node:fs";
import path from "node:path";

const checkOnly = process.argv[2] === "--check";
const installRoot = checkOnly ? process.argv[3] : process.argv[2];
if (!installRoot) {
  console.error("usage: patch-ios.mjs [--check] <node_modules>");
  process.exit(2);
}

function read(rel) {
  return fs.readFileSync(path.join(installRoot, rel), "utf8");
}
function write(rel, text) {
  fs.writeFileSync(path.join(installRoot, rel), text);
}
function fail(message) {
  console.error(`patch-ios: ${message}`);
  process.exit(1);
}

// --- workerd ---------------------------------------------------------------
const workerdRel = "workerd/lib/main.js";
const workerdAnchor = "function generateBinPath() {";
let workerd = read(workerdRel);
const oldWorkerdPatch =
  '  if (process.platform === "ios") {\n' +
  '    return { binPath: "/var/jb/usr/bin/workerd-ios-unavailable" };\n' +
  "  }\n";
const newWorkerdPatch =
  '  if (process.platform === "ios") {\n' +
  "    return { binPath: process.env.WRANGLER_IOS_WORKERD || " +
  '"/var/jb/usr/bin/workerd-ios-unavailable" };\n' +
  "  }\n";

if (workerd.includes("WRANGLER_IOS_WORKERD")) {
  // Already patched.
} else if (workerd.includes(oldWorkerdPatch)) {
  workerd = workerd.replace(oldWorkerdPatch, newWorkerdPatch);
  if (!checkOnly) write(workerdRel, workerd);
} else {
  if (workerd.split(workerdAnchor).length !== 2) {
    fail("workerd entry point changed; refusing an unreviewed patch");
  }
  workerd = workerd.replace(workerdAnchor, workerdAnchor + "\n" + newWorkerdPatch);
  if (!checkOnly) write(workerdRel, workerd);
}

// --- esbuild-wasm ----------------------------------------------------------
const esbuildRel = "esbuild/lib/main.js";
const esbuildAnchor =
  'return ["node", [path2.join(__dirname, "..", "bin", "esbuild")]];';
const esbuildPatched = [
  'const iosFlags = process.platform === "ios"',
  '  ? ["--predictable", "--single-threaded", "--disable-wasm-trap-handler",',
  '     "--no-wasm-lazy-compilation", "--liftoff-only"]',
  "  : [];",
  "return [process.execPath, iosFlags.concat([path2.join(__dirname, \"..\", \"bin\", \"esbuild\")])];",
].join("\n");
let esbuild = read(esbuildRel);

if (esbuild.includes("process.execPath, iosFlags")) {
  // Already patched.
} else {
  if (esbuild.split(esbuildAnchor).length !== 2) {
    fail("esbuild-wasm spawn point changed; refusing an unreviewed patch");
  }
  esbuild = esbuild.replace(esbuildAnchor, esbuildPatched);
  if (!checkOnly) write(esbuildRel, esbuild);
}

if (checkOnly) {
  const ok =
    read(workerdRel).includes("WRANGLER_IOS_WORKERD") &&
    read(esbuildRel).includes("--no-wasm-lazy-compilation") &&
    read(esbuildRel).includes("--liftoff-only");
  if (!ok) fail("patches are incomplete");
  console.log("patch-ios: esbuild-wasm and workerd patches are present");
} else {
  console.log("patch-ios: patched esbuild-wasm and workerd");
}
