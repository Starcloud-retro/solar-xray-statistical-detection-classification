import { el, h, svgRoot, lin, axisX, axisY, annot, f3, fmtSci, tabs, rng, PRM } from "./lib.js";
import { PREDICTORS } from "./loader.js";

const sig = z => 1 / (1 + Math.exp(-z));
function bestStump(rows, feats) {   // one threshold question, chosen by Gini on the given rows
  let best = null;
  for (const f of feats) { const vs = [...new Set(rows.map(r => r[f]))].sort((a, b) => a - b); for (let i = 0; i < vs.length - 1; i++) { const th = (vs[i] + vs[i + 1]) / 2; const L = rows.filter(r => r[f] <= th), R = rows.filter(r => r[f] > th); const gi = a => { if (!a.length) return 0; const p = a.filter(r => r.y).length / a.length; return 2 * p * (1 - p) * a.length; }; const s = gi(L) + gi(R); if (!best || s < best.s) best = { f, th, s, L, R }; } }
  const maj = a => a.filter(r => r.y).length * 2 >= a.length ? 1 : 0; best.lc = maj(best.L); best.rc = maj(best.R); return best;
}

export function init(ctx) {
  const ev = ctx.ml.find(e => e.event_id === "EVT_0017"), P = PREDICTORS, st = ctx.stats, T = ctx.truth;
  const coef = Object.fromEntries(ctx.lr.map(r => [r.term, r.coef]));
  const z = Object.fromEntries(P.map(p => [p, (ev[p] - st[p].mean) / st[p].sd]));
  const score = coef.const + P.reduce((s, p) => s + coef[p] * z[p], 0), prob = sig(score);

  const root = document.getElementById("fig-model");
  const box = h("div", {}); root.append(box);
  const NAME = { rise_slope: "rise_slope", max_roc: "max_roc", mean_pos_roc: "mean_pos_roc", rise_duration_min: "rise_duration_min", bg_flux: "bg_flux" };
  const show = i => {
    box.querySelectorAll(".pane").forEach((n, j) => n.style.display = i === j ? "" : "none");
  };
  const lrPane = h("div", { class: "pane" }), dtPane = h("div", { class: "pane" }), rfPane = h("div", { class: "pane" });
  box.append(lrPane, dtPane, rfPane);
  tabs(box, ["Logistic Regression", "Decision Tree", "Random Forest"], show, 0);

  // ---------- Logistic Regression ----------
  lrPane.append(h("p", { class: "prose", html: `<strong>Start with one event row.</strong> EVT_0017 (C1.5, so the true label is C+). The model is never shown that label when it predicts.` }));
  lrPane.append(h("div", { class: "mrow" }, ...P.map(p => h("div", {}, h("div", { class: "k" }, NAME[p]), h("div", { class: "v" }, p === "bg_flux" ? fmtSci(ev[p], 2) : (+ev[p].toFixed(4)).toString()), h("div", { class: "z" }, `z = ${z[p] >= 0 ? "+" : "−"}${Math.abs(z[p]).toFixed(2)}`), h("div", { class: "w" }, `weight ${coef[p] >= 0 ? "+" : "−"}${Math.abs(coef[p]).toFixed(1)}`)))));
  lrPane.append(h("p", { class: "prose", html: `<strong>1. Standardize.</strong> Each value is re-expressed as “how many spreads from the typical training event”, using only the 18 training events (the z line). <strong>2. Weighted sum.</strong> Multiply each z by its weight, add them up, add a baseline: the score is <span class="code">${score.toFixed(1)}</span>. <strong>3. Sigmoid.</strong> Squash any score into a probability between 0 and 1. <strong>4. Threshold.</strong> If P(C+) ≥ 0.5 the model says C+.` }));
  const W = 1320, H = 340, m = { l: 90, r: 40, t: 26, b: 56 };
  const sv = svgRoot(lrPane, W, H, "svgfig", "Sigmoid curve with this event's score"), g = el("g", {}, sv);
  const x = lin(-25, 25, m.l, W - m.r), y = lin(0, 1, H - m.b, m.t);
  axisX(g, x, H - m.b, [-20, -10, 0, 10, 20], v => v, { grid: [m.t, H - m.b] }); axisY(g, y, m.l, [0, 0.5, 1], v => v.toFixed(1), { grid: W - m.r });
  el("text", { x: m.l, y: 14, class: "t3", text: "P(C+)" }, g); el("text", { x: W - m.r, y: H - 10, "text-anchor": "end", class: "t3", text: "weighted score" }, g);
  let d = ""; for (let s = -25; s <= 25; s += .25) d += (s === -25 ? "M" : "L") + x(s).toFixed(1) + " " + y(sig(s)).toFixed(1);
  el("path", { d, fill: "none", stroke: "var(--teal)", "stroke-width": 2.4 }, g);
  el("line", { x1: m.l, x2: W - m.r, y1: y(.5), y2: y(.5), stroke: "var(--gold)", "stroke-dasharray": "5 5" }, g); el("text", { x: W - m.r, y: y(.5) - 8, "text-anchor": "end", class: "c-gold", text: "threshold 0.5" }, g);
  const sx = Math.min(24.5, score);
  el("circle", { cx: x(sx), cy: y(prob), r: 8, class: "c-orange glow" }, g);
  annot(g, x(sx) - 9, y(prob) + 3, x(sx) - 130, y(prob) + 70, `EVT_0017: score ${score.toFixed(1)}\nP(C+) ≈ ${prob > 0.9999 ? ">0.9999" : prob.toFixed(3)} → C+`, "c-orange", "end");
  lrPane.append(h("div", { class: "callout warn" }, h("span", { class: "k" }, "Read the weights with care"), h("p", {}, "The training classes are completely separable, so these weights are not stable estimates and should not be read as how much each feature “matters”. They only show the mechanics. See the Audit.")));

  // ---------- Decision Tree ----------
  const tr = ctx.train, stump = bestStump(tr, P);
  dtPane.append(h("p", { class: "prose", html: `<strong>A decision tree asks threshold questions.</strong> It picks the single question that best separates B from C+ and then asks more questions inside each branch. Here is the first question, found live from the 18 training events as an illustration of the mechanism (<em>not the project’s fitted tree</em>).` }));
  const cnt = a => `${a.filter(r => !r.y).length} B, ${a.filter(r => r.y).length} C+`;
  const sd = svgRoot(dtPane, W, 300, "svgfig", "A one-question decision stump"), gd = el("g", {}, sd);
  const th = stump.th, fmtT = v => stump.f === "bg_flux" ? fmtSci(v, 2) : (+v.toFixed(4));
  el("text", { x: 660, y: 40, "text-anchor": "middle", class: "serif", text: `Is ${stump.f} ≤ ${fmtT(th)} ?` }, gd);
  el("line", { class: "leader", x1: 600, y1: 60, x2: 380, y2: 130 }, gd); el("line", { class: "leader", x1: 720, y1: 60, x2: 940, y2: 130 }, gd);
  el("text", { x: 470, y: 100, class: "t3", text: "yes" }, gd); el("text", { x: 850, y: 100, class: "t3", text: "no" }, gd);
  [[380, stump.L, stump.lc], [940, stump.R, stump.rc]].forEach(([cx, a, c]) => { el("text", { x: cx, y: 165, "text-anchor": "middle", class: "big", text: c ? "C+" : "B" }, gd); gd.lastChild.style.fill = c ? "var(--orange)" : "var(--cyan)"; el("text", { x: cx, y: 200, "text-anchor": "middle", text: `training events here: ${cnt(a)}` }, gd); });
  el("text", { x: 660, y: 270, "text-anchor": "middle", class: "t3", text: `EVT_0017 has ${stump.f} = ${fmtT(ev[stump.f])}, so it goes ${ev[stump.f] <= th ? "left" : "right"}.` }, gd);
  dtPane.append(h("p", { class: "note", text: "The real tree is small and uses a predefined, modest configuration; no broad search was run because the dataset is tiny." }));

  // ---------- Random Forest ----------
  rfPane.append(h("p", { class: "prose", html: `<strong>A random forest asks many trees and lets them vote.</strong> Each tree sees a random resample of the training events, so each asks slightly different questions. Below, seven one-question trees are built live from resampled training events (a seeded illustration, <em>not the project’s forest</em>, which used seed 42 and its own settings).` }));
  const rnd = rng(42), votes = [];
  for (let i = 0; i < 7; i++) { const bs = Array.from({ length: tr.length }, () => tr[Math.floor(rnd() * tr.length)]); if (!bs.some(r => r.y) || bs.every(r => r.y)) { i--; continue; } const feats = P.filter(() => rnd() < 0.6); const s = bestStump(bs, feats.length ? feats : P); votes.push({ s, v: ev[s.f] <= s.th ? s.lc : s.rc }); }
  const sr = svgRoot(rfPane, W, 280, "svgfig", "Seven trees voting"), gr = el("g", {}, sr);
  votes.forEach((o, i) => { const cx = 90 + i * 190; el("rect", { x: cx - 74, y: 40, width: 148, height: 110, fill: "none", stroke: "var(--hair-2)" }, gr); el("text", { x: cx, y: 66, "text-anchor": "middle", class: "t3", text: `tree ${i + 1}` }, gr); el("text", { x: cx, y: 90, "text-anchor": "middle", class: "t1", "font-size": 12, text: o.s.f.length > 14 ? o.s.f.slice(0, 13) + "…" : o.s.f }, gr); el("text", { x: cx, y: 128, "text-anchor": "middle", class: "serif", text: o.v ? "C+" : "B" }, gr); gr.lastChild.style.fill = o.v ? "var(--orange)" : "var(--cyan)"; });
  const nC = votes.filter(v => v.v).length;
  el("text", { x: 660, y: 215, "text-anchor": "middle", class: "big", text: `${nC} of 7 vote C+  →  ${nC >= 4 ? "C+" : "B"}` }, gr);
  rfPane.append(h("p", { class: "note", text: "The majority wins. Because each tree sees different data, one odd training event rarely decides the outcome." }));
  show(0);

  // ======== chronological split + results ========
  const r2 = document.getElementById("fig-split");
  const Ws = 1320, Hs = 250, s2 = svgRoot(r2, Ws, Hs, "svgfig", "31 events in time order split into train, development and final test");
  const ex = lin(0, 31, 40, Ws - 40), colors = { Train: "var(--text-2)", Development: "var(--teal)", "Final test": "var(--gold)" };
  const parts = [["Train", 0, 18, "18 events: 7 B, 11 C+"], ["Development", 18, 24, "6 events: 1 B, 5 C+"], ["Final test", 24, 31, "7 events: 5 B, 2 C+"]];
  parts.forEach(([n, a, b, t]) => { el("line", { x1: ex(a) + 3, x2: ex(b) - 3, y1: 56, y2: 56, stroke: colors[n], "stroke-width": 2 }, s2); el("text", { x: ex(a) + 3, y: 38, class: "serif", text: n }, s2); s2.lastChild.style.fill = colors[n]; el("text", { x: ex(a) + 3, y: 80, class: "t3", text: t }, s2); });
  ctx.ml.forEach(e => { const cx = ex(e.i + 0.5), y0 = 150; if (e.y) el("circle", { cx, cy: y0, r: 14, class: "c-orange", opacity: 0.9 }, s2); else el("circle", { cx, cy: y0, r: 14, fill: "none", stroke: "var(--cyan)", "stroke-width": 2 }, s2); el("text", { x: cx, y: y0 + 4.5, "text-anchor": "middle", "font-size": 11.5, fill: e.y ? "#05070F" : "var(--cyan)", text: e.y ? "C+" : "B" }, s2); });
  el("text", { x: 40, y: 220, class: "t3", text: `earliest: ${ctx.ml[0].peak_time.slice(5, 10)}` }, s2); el("text", { x: Ws - 40, y: 220, "text-anchor": "end", class: "t3", text: `latest: ${ctx.ml[30].peak_time.slice(5, 10)}` }, s2);
  el("text", { x: Ws / 2, y: 220, "text-anchor": "middle", class: "t3", text: "time order (by peak time) →" }, s2);
  const wrap = h("div", {}); r2.after(wrap);
  const dm = T.dev_metrics;
  wrap.append(h("h3", {}, "Development scores"), h("table", { class: "mtable" }, h("thead", {}, h("tr", {}, ["Model (6 development events, 1 B)", "Accuracy", "Macro-F1", "Balanced accuracy"].map(t => h("th", {}, t)))),
    h("tbody", {}, Object.entries(dm).map(([n, v]) => h("tr", {}, h("td", {}, n), h("td", {}, v.acc.toFixed(3)), h("td", {}, v.macro_f1.toFixed(3)), h("td", {}, v.bal_acc.toFixed(3)))))));
  wrap.append(h("p", { class: "note", text: "With one B event in six, a single mistake moves these numbers a lot. The list is not a ranking." }));
  wrap.append(h("h3", {}, "The frozen final test"));
  const reveal = h("button", { class: "btn fill", type: "button" }, "Reveal the final test"), out = h("div", { style: "margin-top:24px" });
  wrap.append(h("p", { class: "note", text: "The model was frozen before this step. The final test was never used to choose features or models." }), reveal, out);
  reveal.addEventListener("click", () => {
    reveal.remove(); const f = T.final_test;
    out.append(h("div", { class: "verdict" },
      h("div", { class: "stat c-teal" }, h("div", { class: "n" }, `${f.correct}/${f.n}`), h("div", { class: "l" }, "events classified correctly")),
      h("div", { class: "stat c-coral" }, h("div", { class: "n" }, `N = ${f.n}`), h("div", { class: "l" }, "events in the test set"))),
      h("div", { class: "callout warn" }, h("span", { class: "k" }, "Not proof of generalization"), h("p", {}, "This is an observed result on a tiny test set, and N = 7 does not establish generalization. Only 2 of the 7 events are C+; a model that guessed B for everything would still get 5 right.")),
      h("table", { class: "cm" }, h("thead", {}, h("tr", {}, h("th", {}), h("th", {}, "predicted B"), h("th", {}, "predicted C+"))), h("tbody", {}, h("tr", {}, h("th", {}, "true B"), h("td", {}, f.BB), h("td", { class: "z" }, f.BC)), h("tr", {}, h("th", {}, "true C+"), h("td", { class: "z" }, f.CB), h("td", {}, f.CC)))),
      h("p", { class: "note", text: "Accuracy, Macro-F1 and balanced accuracy are all 1.0, but each rests on 7 events." }));
  });
}
