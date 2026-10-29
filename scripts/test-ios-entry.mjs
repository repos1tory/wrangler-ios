#!/usr/bin/env node
// test-ios-entry.mjs — load a CLI as if process.platform were "ios" so CI can
// exercise the same workerd/esbuild branches that run on a jailbroken device.
//
//   node scripts/test-ios-entry.mjs <entry.js> [args...]
import path from "node:path";
import { pathToFileURL } from "node:url";

const [, , entry, ...args] = process.argv;
if (!entry) {
  console.error("usage: test-ios-entry.mjs <entry.js> [args...]");
  process.exit(2);
}

Object.defineProperty(process, "platform", { value: "ios" });
process.argv = [process.execPath, entry, ...args];

// Wrangler's entry is CommonJS. import() handles both CJS and ESM.
await import(pathToFileURL(path.resolve(entry)).href);
