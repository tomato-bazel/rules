#!/usr/bin/env node
// @generated-into-bundle by rules_nextjs `next_standalone`.
//
// A deterministic entry for the assembled standalone bundle. Next.js nests the
// standalone `server.js` under the app's path *relative to
// `outputFileTracingRoot`* — which varies per app (`<app>/server.js` for a
// monorepo subdir, `server.js` at the root for a flattened app, or a
// build-dir-derived prefix). So consumers (an `oci_image` `cmd`, a launcher)
// can't hardcode the entry. This shim, copied to a FIXED bundle-root path,
// discovers the real `server.js` and runs it with cwd at the bundle root — so
// the standalone server serves `/_next/static/*` from `./.next/static`, exactly
// the layout the production Dockerfile used.
//
// It's `.cjs` so `require()` works even when the bundle's package.json declares
// `"type": "module"`.
'use strict';

const fs = require('fs');
const path = require('path');

const root = __dirname;

// Collect every server.js outside node_modules (Next ships exactly one for the
// app; anything under node_modules is a library file we must ignore).
const found = [];
(function walk(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (_e) {
    return;
  }
  for (const e of entries) {
    if (e.name === 'node_modules') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      walk(p);
    } else if (e.name === 'server.js') {
      found.push(p);
    }
  }
})(root);

if (found.length === 0) {
  console.error('next_standalone: no server.js found under ' + root);
  process.exit(1);
}

// Shallowest path wins — the app entry sits above any incidental nested copy.
found.sort((a, b) => a.split(path.sep).length - b.split(path.sep).length);
const server = found[0];

process.chdir(root);

(async () => {
  try {
    require(server);
  } catch (err) {
    if (err && err.code === 'ERR_REQUIRE_ESM') {
      await import(require('url').pathToFileURL(server).href);
    } else {
      throw err;
    }
  }
})();
