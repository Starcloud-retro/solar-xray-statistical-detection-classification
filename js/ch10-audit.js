import { el, h, svgRoot, lin, axisX, axisY, annot, f3, fmtSci, fmtInt, onVisible, PRM } from "./lib.js";
import { PREDICTORS } from "./loader.js";

const pearson = (a, b) => { const n = a.length, ma = a.reduce((s, v) => s + v, 0) / n, mb = b.reduce((s, v) => s + v, 0) / n; let sab = 0, sa = 0, sb = 0; for (let i = 0; i < n; i++) { sab += (a[i] - ma) * (b[i] - mb); sa += (a[i] - ma) ** 2; sb += (b[i] - mb) ** 2; } return sab / Math.sqrt(sa * sb); };

export function init(ctx) {
  const T = ctx.truth;
  // ===== LOOCV =====
  const r1 = document.getElementById("fig-loocv"), W = 1320, H = 230, s1 = svgRoot(r1, W, H, "svgfig", "Leave-one-out: one event removed at a time"), x = lin(0, 31, 40, W - 40);
  const dots = ctx.ml.map(e => { const cx = x(e.i + .5); const c = e.y ? el("circle", { cx, cy: 90, r: 14, class: "c-orange" }, s1) : el("circle", { cx, cy: 90, r: 14, fill: "none", stroke: "var(--cyan)", "stroke-width": 2 }, s1); return c; });
  const lbl = ctx.ml.map(e => el("text", { x: x(e.i + .5), y: 94.5, "text-anchor": "middle", "font-size": 11.5, fill: e.y ? "#05070F" : "var(--cyan)", text: e.y ? "C+" : "B" }, s1));
  const hold = el("rect", { y: 62, width: 36, height: 56, fill: "none", stroke: "var(--gold)", "stroke-width": 2, opacity: 0 }, s1);
  const say = el("text", { x: 40, y: 175, class: "t1", text: "Press play: each event is removed in turn, the model is refit on the other 30, and the removed event is predicted once." }, s1);
  el("text", { x: 40, y: 200, class: "t3", text: "Per-event LOOCV predictions are not part of this site’s data; only the aggregate is shown." }, s1);
  let i = -1, timer = null; const ctl = h("div", { class: "ctl" }), play = h("button", { class: "btn", type: "button" }, "Play"); ctl.append(play); r1.prepend(ctl);
  const at = k => { dots.forEach((d, j) => d.setAttribute("opacity", j === k ? 0.25 : 1)); lbl.forEach((d, j) => d.setAttribute("opacity", j === k ? 0.4 : 1)); hold.setAttribute("x", x(k + .5) - 18); hold.setAttribute("opacity", 1); say.textContent = `Held out: ${ctx.ml[k].event_id}. Train on the other 30 events, predict this one.`; };
  const stop = () => { clearInterval(timer); timer = null; play.textContent = "Play"; };
  play.addEventListener("click", () => { if (timer) return stop(); i = -1; play.textContent = "Pause"; timer = setInterval(() => { i++; if (i > 30) { stop(); dots.forEach(d => d.setAttribute("opacity", 1)); lbl.forEach(d => d.setAttribute("opacity", 1)); hold.setAttribute("opacity", 0); say.textContent = "Done: 31 folds, each event predicted once."; return; } at(i); }, PRM ? 30 : 300); });
  const L = T.loocv, lr = L["Logistic Regression"];
  r1.append(h("table", { class: "mtable" }, h("thead", {}, h("tr", {}, ["LOOCV, 31 events", "Accuracy", "Macro-F1", "Balanced accuracy"].map(t => h("th", {}, t)))),
    h("tbody", {}, Object.entries(L).map(([n, v]) => h("tr", {}, h("td", {}, n), h("td", {}, v.acc.toFixed(4)), h("td", {}, v.macro_f1.toFixed(4)), h("td", {}, v.bal_acc.toFixed(4)))))),
    h("p", { class: "note", html: `Logistic Regression: ${lr.TP} C+ found of 18, ${lr.TN} B correct of 13, ${lr.FP} B called C+, ${lr.FN} C+ missed. Listed in a fixed order, not ranked.` }));

  // ===== scatterplots first, then numbers =====
  const r2 = document.getElementById("fig-corr"), tr = ctx.train;
  const pairs = [["rise_slope", "max_roc"], ["rise_slope", "mean_pos_roc"], ["max_roc", "mean_pos_roc"]];
  const w = 420, hh = 380, s2 = svgRoot(r2, 3 * w + 60, hh + 30, "svgfig", "Scatterplots of the three rise-rate features");
  pairs.forEach(([a, b], k) => {
    const ox = k * (w + 30), xv = tr.map(e => e[a]), yv = tr.map(e => e[b]);
    const sx = lin(0, Math.max(...xv) * 1.08, ox + 62, ox + w - 10), sy = lin(0, Math.max(...yv) * 1.08, hh - 56, 30);
    const g = el("g", {}, s2); const tk = d => d > 0.3 ? [0, .1, .2, .3] : [0, .05, .1, .15, .2]; axisX(g, sx, hh - 56, tk(sx.domain[1]).filter(v => v < sx.domain[1]), v => v.toFixed(2)); axisY(g, sy, ox + 62, tk(sy.domain[1]).filter(v => v < sy.domain[1]), v => v.toFixed(2), { grid: ox + w - 10 });
    tr.forEach(e => e.y ? el("circle", { cx: sx(e[a]), cy: sy(e[b]), r: 5.5, class: "c-orange", opacity: .9 }, g) : el("circle", { cx: sx(e[a]), cy: sy(e[b]), r: 5.5, fill: "none", stroke: "var(--cyan)", "stroke-width": 1.8 }, g));
    el("text", { x: ox + 62, y: 18, class: "t1", text: `${b} vs ${a}` }, g); el("text", { x: ox + w - 10, y: hh - 8, "text-anchor": "end", class: "t3", text: a }, g);
    const r = pearson(xv, yv); el("text", { x: ox + 76, y: 56, class: "serif", text: `r = ${r.toFixed(3)}` }, g);
  });
  r2.append(h("figcaption", { class: "cap", html: "<b>18 training events.</b> Orange = C+, hollow cyan = B. The points hug a line: the three features carry almost the same information." }));
  const vif = ctx.vif, vmax = Math.max(...vif.map(v => v.v)), vw = 1320, vh = 260, s3 = svgRoot(r2, vw, vh, "svgfig", "VIF bars"), vx = lin(0, 40, 290, vw - 120);
  el("text", { x: 0, y: 18, class: "t1", text: "Variance inflation factor (VIF), training set" }, s3);
  [10].forEach(t => { el("line", { x1: vx(t), x2: vx(t), y1: 30, y2: vh - 28, stroke: "var(--gold)", "stroke-dasharray": "4 5" }, s3); el("text", { x: vx(t) + 6, y: vh - 10, class: "c-gold", text: "10: a common warning level" }, s3); });
  vif.forEach((v, j) => { const y = 54 + j * 40; el("text", { x: 270, y: y + 5, "text-anchor": "end", class: "t1", text: v.p }, s3); el("rect", { x: 290, y: y - 11, width: vx(v.v) - 290, height: 22, class: v.v > 10 ? "c-coral" : "c-teal", opacity: .9 }, s3); el("text", { x: vx(v.v) + 10, y: y + 5, text: v.v.toFixed(2) }, s3); });
  r2.append(h("p", { class: "note", style: "margin-top:16px", html: `Correlations: rise_slope–max_roc <span class="code">${T.corr["rise_slope|max_roc"].toFixed(3)}</span>, rise_slope–mean_pos_roc <span class="code">${T.corr["rise_slope|mean_pos_roc"].toFixed(3)}</span>, max_roc–mean_pos_roc <span class="code">${T.corr["max_roc|mean_pos_roc"].toFixed(3)}</span>.` }));

  // ===== separation =====
  const r3 = document.getElementById("fig-sep");
  r3.append(h("div", { class: "prose" }, h("p", { html: "On the 18 training events a straight boundary separates B from C+ <em>perfectly</em>. That sounds good but it breaks ordinary Logistic Regression: the weights can keep growing without limit, so the fitted numbers are arbitrary and their uncertainty is enormous." })),
    h("table", { class: "mtable" }, h("thead", {}, h("tr", {}, ["Term", "Coefficient", "Standard error"].map(t => h("th", {}, t)))),
      h("tbody", {}, ctx.lr.map(r => h("tr", {}, h("td", {}, r.term), h("td", {}, r.coef.toFixed(1)), h("td", {}, fmtInt(Math.round(r.se))))))),
    h("p", { class: "note", text: "Standard errors in the tens or hundreds of thousands against coefficients of a few tens: the weights are not trustworthy effect sizes, and the model’s predictions are the only thing it offers." }));

  // ===== limitations =====
  const LIM = [["N = 31 events overall", "One week of data from one satellite."], ["Final test N = 7", "Only 2 are C+. 7/7 does not establish generalization."], ["Development split has only one B event", "Model comparison there is very coarse."], ["Complete separation", "Ordinary Logistic Regression is unstable; coefficients are not effect estimates."], ["Strong multicollinearity", "The three rise-rate predictors overlap (r 0.91–0.97, VIF 20–35)."], ["Detector and matching choices shape the dataset", "They decide which events reach machine learning."], ["Nowcasting, not forecasting", "t_pred = t_peak classifies an event at its observed peak."], ["No external validation", "A proof of concept, not production-ready or broadly generalizable."]];
  const ul = document.getElementById("limits"); LIM.forEach(([a, b]) => ul.append(h("li", {}, a, h("span", {}, b))));
}
