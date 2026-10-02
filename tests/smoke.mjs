// Node smoke test: runs every chapter module against the real data inside jsdom and reports errors.
import { JSDOM } from "jsdom"; import fs from "fs"; import path from "path"; import { pathToFileURL } from "url";
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const dom = new JSDOM(fs.readFileSync(path.join(root, "index.html"), "utf8").replace(/<script[^>]*><\/script>/g, ""), { pretendToBeVisual: true });
const { window } = dom; global.window = window; global.document = window.document;
Object.defineProperty(global,"navigator",{value:window.navigator,configurable:true}); global.matchMedia = () => ({ matches: false }); global.addEventListener = () => {}; global.innerHeight = 900; global.innerWidth = 1440; global.scrollY = 0;
global.requestAnimationFrame = f => setTimeout(() => f(performance.now()), 0);
global.fetch = async u => { const p = path.join(root, u); if (!fs.existsSync(p)) return { ok: false, status: 404 }; const b = fs.readFileSync(p, "utf8"); return { ok: true, status: 200, text: async () => b, json: async () => JSON.parse(b) }; };
const errs = []; const oe = console.error; console.error = (...a) => { errs.push(a.join(" ")); oe(...a); };
window.HTMLElement.prototype.getTotalLength = () => 1000;
const { loadAll } = await import(pathToFileURL(path.join(root, "js/loader.js")));
const ctx = await loadAll();
const names = ["ch00-hero","ch01-observe","ch02-count","ch03-prepare","ch04-normal","ch05-detect","ch06-noaa","ch07-dataset","ch08-features","ch09-model","ch10-audit","presentation"];
for (const n of names) { try { const m = await import(pathToFileURL(path.join(root, `js/${n}.js`))); m.init(ctx); console.log("ok  ", n); } catch (e) { console.log("FAIL", n, e.stack.split("\n").slice(0, 3).join(" | ")); errs.push(n); } }
fs.writeFileSync("/tmp/rendered.html", document.documentElement.outerHTML);
console.log("series", ctx.series.length, "ml", ctx.ml.length, "train", ctx.train.length, "errors", errs.length);
process.exit(errs.length ? 1 : 0);
