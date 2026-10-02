import { loadAll } from "./loader.js";
import { fmtInt } from "./lib.js";
import * as hero from "./ch00-hero.js";
import * as observe from "./ch01-observe.js";
import * as count from "./ch02-count.js";
import * as prepare from "./ch03-prepare.js";
import * as normal from "./ch04-normal.js";
import * as detect from "./ch05-detect.js";
import * as noaa from "./ch06-noaa.js";
import * as dataset from "./ch07-dataset.js";
import * as features from "./ch08-features.js";
import * as model from "./ch09-model.js";
import * as audit from "./ch10-audit.js";
import * as presentation from "./presentation.js";

const chapters = [["hero", hero], ["observe", observe], ["count", count], ["prepare", prepare], ["normal", normal], ["detect", detect],
  ["noaa", noaa], ["dataset", dataset], ["features", features], ["model", model], ["audit", audit], ["presentation", presentation]];

function tracker() {
  const links = [...document.querySelectorAll(".tracker a")];
  const ids = links.map(a => a.getAttribute("href").slice(1));
  const secs = ids.map(id => document.getElementById(id));
  const bar = document.getElementById("trackbar");
  const nav = document.getElementById("topnav");
  const update = () => {
    nav.classList.toggle("solid", scrollY > 40);
    const probe = innerHeight * 0.4;
    let cur = -1;
    secs.forEach((s, i) => { if (s && s.getBoundingClientRect().top < probe) cur = i; });
    links.forEach((a, i) => a.classList.toggle("on", i === cur));
    const first = secs[0].offsetTop, last = document.getElementById("conclusion").offsetTop;
    const f = Math.max(0, Math.min(1, (scrollY + probe - first) / (last - first)));
    bar.style.width = (f * 100).toFixed(1) + "%";
  };
  addEventListener("scroll", update, { passive: true }); addEventListener("resize", update); update();
}

function bindTruth(truth) {
  document.querySelectorAll("[data-truth]").forEach(n => {
    const v = n.dataset.truth.split(".").reduce((o, k) => o?.[k], truth);
    if (v !== undefined) n.textContent = typeof v === "number" ? fmtInt(v) : v;
  });
}

async function boot() {
  tracker();
  let ctx;
  try { ctx = await loadAll(); }
  catch (e) {
    console.error(e);
    document.querySelectorAll(".fig").forEach(f => { f.innerHTML = `<p class="note" style="color:var(--coral)">The figures could not load the project data (${e.message}). Serve this folder over HTTP, for example <span class="code">python3 -m http.server 8000</span>, and open http://localhost:8000.</p>`; });
    return;
  }
  bindTruth(ctx.truth);
  window.__SOLAR = ctx;
  for (const [name, mod] of chapters) {
    try { mod.init(ctx); }
    catch (e) { console.error("chapter failed:", name, e); const t = document.getElementById("fig-" + name) || document.getElementById(name); if (t) t.insertAdjacentHTML("beforeend", `<p class="note" style="color:var(--coral)">This figure failed to draw (${e.message}).</p>`); }
  }
}
boot();
