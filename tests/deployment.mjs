// Deployment regression: verify the runtime files survive both ignore filters.
// Run from any directory with node tests/deployment.mjs; no dependencies.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { SLIDES } from "../js/presentation.js";

const root = fileURLToPath(new URL("../", import.meta.url));
const read = p => fs.readFileSync(path.join(root, p), "utf8");
const git = args => new Promise((resolve, reject) => {
  const child = spawn("git", args, { cwd: root });
  let stdout = "", stderr = "";
  child.stdout.setEncoding("utf8"); child.stderr.setEncoding("utf8");
  child.stdout.on("data", chunk => { stdout += chunk; });
  child.stderr.on("data", chunk => { stderr += chunk; });
  child.on("error", reject);
  child.on("close", status => resolve({ status, stdout, stderr }));
});
const config = JSON.parse(read("vercel.json"));
assert.equal(config.framework, null);
assert.equal(config.buildCommand, "");
assert.equal(config.installCommand, "");
assert.equal(config.outputDirectory, ".");
assert.equal(config.rewrites, undefined, "Static files must not become the HTML page");

const files = new Set(["index.html", "assets/presentation/Solar_Activity.pptx"]);
for (const m of read("js/loader.js").matchAll(/get(?:Text|JSON)\("([^"]+)"\)/g)) files.add(m[1]);
for (const m of read("index.html").matchAll(/(?:href|src)="([^"]+)"/g)) {
  if (!/^(?:#|data:|https?:)/.test(m[1])) files.add(m[1]);
}
for (const f of fs.readdirSync(path.join(root, "js"))) {
  files.add("js/" + f);
  for (const m of read("js/" + f).matchAll(/from\s+"(\.[^"]+)"/g)) files.add(path.posix.join("js", m[1]));
}
for (const f of fs.readdirSync(path.join(root, "css"))) {
  files.add("css/" + f);
  for (const m of read("css/" + f).matchAll(/url\("([^"]+)"\)/g)) files.add(path.posix.join("css", m[1]));
}
for (const slide of SLIDES) { files.add(slide.src); files.add(slide.thumb); }
const listing = await git(["ls-files", "-z"]);
assert.equal(listing.status, 0, listing.stderr);
const tracked = new Set(listing.stdout.split("\0"));
for (const f of files) {
  assert(fs.statSync(path.join(root, f)).isFile(), `Missing file: ${f}`);
  assert(tracked.has(f), `Runtime file is not tracked: ${f}`);
  if (f.endsWith(".json")) JSON.parse(read(f));
}
// check-ignore --no-index also checks files that are already tracked. Treat the
// Vercel patterns as a Git excludes file, using the same ignore-pattern syntax.
files.add("assets/presentation/index.html");
assert(fs.statSync(path.join(root, "assets/presentation/index.html")).isFile());
for (const args of [[], ["-c", "core.excludesFile=.vercelignore"]]) {
  const result = await git([...args, "check-ignore", "--no-index", ...files]);
  assert.equal(result.status, 1, `Runtime files excluded: ${result.stdout}${result.stderr}`);
}
assert(read("index.html").includes('id="presentation"'));
console.log(`PASS root static configuration and ${files.size} runtime files, including all slides, thumbnails, fonts and loader data`);
