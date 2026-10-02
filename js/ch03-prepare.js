import { el, h, svgRoot, lin, axisX, axisY, annot, hhmm, fmtSci, linePath, tabs, MIN, stamp, f3 } from "./lib.js";

function gapRuns(S) { const runs = []; let a = -1; S.forEach((p, i) => { if (!isFinite(p.fluxClean)) { if (a < 0) a = i; } else if (a >= 0) { runs.push([a, i - 1]); a = -1; } }); if (a >= 0) runs.push([a, S.length - 1]); return runs; }

export function init(ctx) {
  const S = ctx.series;
  const runs = gapRuns(S), longest = Math.max(...runs.map(r => r[1] - r[0] + 1)), totalMissing = runs.reduce((s, r) => s + r[1] - r[0] + 1, 0);
  const note = document.getElementById("gap-stat");
  if (note) note.innerHTML = `Across the week there is <strong>1 reconstructed minute</strong> and <strong>${runs.length} long gaps</strong> (${totalMissing} minutes, the longest ${longest}) that stay empty. Short gap: keep continuity. Long gap: keep the uncertainty.`;

  // ================= gap toggle =================
  const root = document.getElementById("fig-gaps");
  const W = 1320, H = 380, m = { l: 90, r: 380, t: 24, b: 46 };
  const holder = h("div", {}); root.append(holder);
  const svg = svgRoot(holder, W, H, "svgfig", "Short and long gap examples"); const g = el("g", {}, svg);
  const side = h("div", { style: "margin-top:12px" }); holder.append(side);

  const cfg = [
    { name: "Short gap: one minute", t0: Date.UTC(2026, 8, 6, 19, 29), n: 12, key: Date.UTC(2026, 8, 6, 19, 34) },
    { name: "Long gap: six minutes", t0: Date.UTC(2026, 8, 4, 16, 26), n: 17, key: Date.UTC(2026, 8, 4, 16, 31) }
  ];
  function draw(k) {
    g.replaceChildren(); side.replaceChildren();
    const c = cfg[k], win = Array.from({ length: c.n }, (_, i) => ({ i, p: ctx.at(c.t0 + i * MIN) }));
    const vals = win.map(w => w.p.logC).filter(isFinite), lo = Math.min(...vals), hi = Math.max(...vals), pad = (hi - lo) * 0.35 || 0.01;
    const x = lin(c.t0, c.t0 + (c.n - 1) * MIN, m.l, W - m.r), y = lin(lo - pad, hi + pad, H - m.b - (k ? 34 : 0), m.t);
    axisX(g, x, H - m.b, win.filter((_, i) => i % 2 === 0).map(w => c.t0 + w.i * MIN), hhmm, { grid: [m.t, H - m.b] });
    axisY(g, y, m.l, [lo, (lo + hi) / 2, hi], v => v.toFixed(3));
    el("text", { x: m.l, y: 14, class: "t3", text: "log10 flux" }, g);
    const pts = win.map(w => ({ x: c.t0 + w.i * MIN, y: w.p.logC }));
    el("path", { d: linePath(pts, x, y), fill: "none", stroke: "var(--cyan)", "stroke-width": 1.8 }, g);   // gaps are never bridged
    win.forEach(w => {
      const px = x(c.t0 + w.i * MIN);
      if (!isFinite(w.p.fluxClean)) { el("circle", { cx: px, cy: H - m.b - 14, r: 5, fill: "none", stroke: "var(--coral)", "stroke-width": 1.6 }, g); return; }
      if (w.p.imputed) { el("circle", { cx: px, cy: y(w.p.logC), r: 11, fill: "none", stroke: "var(--teal)", "stroke-width": 1.5 }, g); el("circle", { cx: px, cy: y(w.p.logC), r: 5.5, class: "c-teal glow" }, g); }
      else el("circle", { cx: px, cy: y(w.p.logC), r: 4, class: "c-cyan" }, g);
    });
    if (k === 0) {
      const a = ctx.at(c.key - MIN), b = ctx.at(c.key), d = ctx.at(c.key + MIN);
      annot(g, x(a.t), y(a.logC) - 8, x(a.t) - 40, m.t + 36, "19:33 observed", "c-cyan", "end");
      annot(g, x(b.t), y(b.logC) - 14, x(b.t), m.t + 14, "19:34 missing, reconstructed", "c-teal", "middle");
      annot(g, x(d.t), y(d.logC) - 8, x(d.t) + 40, m.t + 36, "19:35 observed", "c-cyan", "start");
      el("text", { x: W - m.r + 30, y: 60, class: "serif", text: "Short gap" }, g);
      el("text", { x: W - m.r + 30, y: 90, text: "keep continuity" }, g);
      el("text", { x: W - m.r + 30, y: 114, class: "t3", text: "line stays unbroken; the" }, g);
      el("text", { x: W - m.r + 30, y: 134, class: "t3", text: "teal point carries a flag" }, g);
      const ro = [a, b, d];
      side.append(h("table", { class: "t", style: "max-width:760px" }, h("thead", {}, h("tr", {}, ["time_tag", "flux (W/m²)", "log10", "was_imputed"].map(t => h("th", {}, t)))),
        h("tbody", {}, ro.map(p => h("tr", { class: p.imputed ? "hl" : "" }, h("td", {}, p.tag.replace("+00:00", "")), h("td", {}, fmtSci(p.fluxClean, 3)), h("td", {}, f3(p.logC)), h("td", {}, p.imputed ? "TRUE" : "FALSE"))))));
    } else {
      const i0 = ctx.idx(c.key), gap = [i0, i0 + 5];
      el("rect", { x: x(S[gap[0]].t) - 12, y: m.t, width: x(S[gap[1]].t) - x(S[gap[0]].t) + 24, height: H - m.b - m.t, fill: "var(--coral)", opacity: 0.08 }, g);
      el("text", { x: (x(S[gap[0]].t) + x(S[gap[1]].t)) / 2, y: m.t + 22, "text-anchor": "middle", class: "c-coral", text: "6 minutes with no value" }, g);
      el("text", { x: (x(S[gap[0]].t) + x(S[gap[1]].t)) / 2, y: m.t + 42, "text-anchor": "middle", class: "t3", text: "no line drawn across it" }, g);
      el("text", { x: W - m.r + 30, y: 60, class: "serif", text: "Long gap" }, g);
      el("text", { x: W - m.r + 30, y: 90, text: "keep uncertainty" }, g);
      el("text", { x: W - m.r + 30, y: 114, class: "t3", text: "we cannot know what the" }, g);
      el("text", { x: W - m.r + 30, y: 134, class: "t3", text: "Sun did, so we leave it empty" }, g);
      const r = [ctx.at(c.key - MIN), S[gap[0]], S[gap[1]], ctx.at(c.key + 6 * MIN)];
      side.append(h("table", { class: "t", style: "max-width:760px" }, h("thead", {}, h("tr", {}, ["time_tag", "flux (W/m²)", "log10", "is_long_gap"].map(t => h("th", {}, t)))),
        h("tbody", {}, r.map((p, i) => h("tr", { class: i === 1 || i === 2 ? "hl" : "" }, h("td", {}, p.tag.replace("+00:00", "")), h("td", {}, isFinite(p.fluxClean) ? fmtSci(p.fluxClean, 3) : "missing"), h("td", {}, isFinite(p.logC) ? f3(p.logC) : "missing"), h("td", {}, p.longGap ? "TRUE" : "FALSE"))))));
    }
  }
  tabs(holder, cfg.map(c => c.name), draw, 0);
  root.append(h("figcaption", { class: "cap", html: "<b>Real minutes from the file.</b> Cyan = measured. Teal = reconstructed. Coral rings = minutes with no value." }));

  // ================= why log10: same day, two axes =================
  const r2 = document.getElementById("fig-log");
  const D0 = Date.UTC(2026, 8, 5), day = Array.from({ length: 1440 }, (_, i) => ctx.at(D0 + i * MIN));
  const W2 = 1320, Hh = 150, mm = { l: 90, r: 24 };
  const sv = svgRoot(r2, W2, 2 * Hh + 80, "svgfig", "The same day of flux drawn on a linear and a logarithmic axis");
  const fx = lin(D0, D0 + 1439 * MIN, mm.l, W2 - mm.r);
  const fmax = Math.max(...day.map(p => p.fluxClean).filter(isFinite));
  const yl = lin(0, fmax, Hh + 10, 24), yg = lin(Math.min(...day.map(p => p.logC).filter(isFinite)), Math.max(...day.map(p => p.logC).filter(isFinite)), 2 * Hh + 56, Hh + 80);
  const gl = el("g", {}, sv);
  axisY(gl, yl, mm.l, [0, 5e-6, 1e-5], v => v === 0 ? "0" : v.toExponential(0).replace("e-", "e−"), { grid: W2 - mm.r });
  el("path", { d: linePath(day.map(p => ({ x: p.t, y: p.fluxClean })), fx, yl), fill: "none", stroke: "var(--cyan)", "stroke-width": 1.3 }, gl);
  el("text", { x: mm.l, y: 14, class: "t1", text: "Ordinary axis: flux in W/m²" }, gl);
  const ymaxLine = yl(1e-5);
  annot(gl, fx(D0 + 12 * 60 * MIN), yl(5e-7), fx(D0 + 14 * 60 * MIN), yl(5e-7) + 40, "the quiet background is squashed\nagainst zero", "t1");
  axisY(gl, yg, mm.l, [-7, -6, -5].map(v => v), v => `1e${v < 0 ? "−" : ""}${Math.abs(v)}`, { grid: W2 - mm.r });
  el("path", { d: linePath(day.map(p => ({ x: p.t, y: p.logC })), fx, yg), fill: "none", stroke: "var(--cyan)", "stroke-width": 1.3 }, gl);
  el("text", { x: mm.l, y: Hh + 70, class: "t1", text: "log10 axis: equal steps are equal ratios" }, gl);
  axisX(gl, fx, 2 * Hh + 56, [0, 6, 12, 18, 24].map(hr => D0 + Math.min(hr, 23.98) * 60 * MIN), hhmm, {});
  el("text", { x: W2 - mm.r, y: 2 * Hh + 78, "text-anchor": "end", class: "t3", text: "5 Sep 2026, UTC" }, gl);
  annot(gl, fx(D0 + 8 * 60 * MIN), yg(-6.45), fx(D0 + 9.4 * 60 * MIN), yg(-6.45) + 34, "same minutes: background and flares both readable", "t1");
  r2.append(h("figcaption", { class: "cap", html: "<b>Same 1,440 minutes, two axes.</b> Real data for 5 September." }));
}
