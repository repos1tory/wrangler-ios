#!/usr/bin/env node
// gzip.mjs <input> <output> — used by the build so it does not depend on a
// standalone gzip binary (some rootless iOS bootstraps do not ship one).
import fs from "node:fs";
import zlib from "node:zlib";

const [, , input, output] = process.argv;
if (!input || !output) {
  console.error("usage: gzip.mjs <input> <output>");
  process.exit(2);
}
fs.writeFileSync(output, zlib.gzipSync(fs.readFileSync(input), { level: 9 }));
