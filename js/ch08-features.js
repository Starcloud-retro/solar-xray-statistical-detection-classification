import { el, h, svgRoot, lin, axisX, axisY, annot, hhmm, f3, fmtSci, linePath, MIN, PRM } from "./lib.js";

export function init(ctx) {
  const ev = ctx.evAll.find(e => e.event_id === "EVT_0017");
  const a0 = ev.start - 8 * MIN, a1 = ev.end + 4 * MIN;
  const pts = []; for (let t = a0; t <= a1; t += MIN) pts.push(ctx.at(t));
  const rise = pts.filter(p => p.t >= ev.start && p.t <= ev.peak);
  const roc = rise.map((p, i) => ({ t: p.t, v: i ? p.logC - rise[i - 1].logC : NaN }));
  const bgLog = Math.log10(ev.bg_flux), W = 1320, H = 470, m = { l: 96, r: 40, t: 34, b: 50 };
  const x = lin(a0, a1, m.l, W - m.r), y = lin(-6.40, -5.76, H - m.b, m.t);
  const yAx = [-6.4, -6.3, -6.2, -6.1, -6.0, -5.9, -5.8];

  // ---- features: one at a time ----
  const ui = document.getElementById("feat-ui"), root = document.getElementById("fig-features");
  const FEAT = [
    { k: "bg_flux", n: "Background flux", q: "How bright was it before the event?", v: ev.bg_flux, fmt: v => fmtSci(v, 2) + " W/m²" },
    { k: "rise_duration_min", n: "Rise duration", q: "How long did the climb take?", v: ev.rise_duration_min, fmt: v => v + " min" },
    { k: "rise_slope", n: "Rise slope", q: "How steep was the climb overall?", v: ev.rise_slope, fmt: v => v.toFixed(4) + " log10/min" },
    { k: "max_roc", n: "Max ROC", q: "What was the steepest single minute?", v: ev.max_roc, fmt: v => v.toFixed(4) },
    { k: "mean_pos_roc", n: "Mean positive ROC", q: "On average, how fast did it rise in the minutes it rose?", v: ev.mean_pos_roc, fmt: v => v.toFixed(4) }
  ];
  let k = 0;
  const q = h("p", { class: "ch-q qline", style: "margin:0 0 8px;font-size:24px" }), tbl = h("div", { class: "readout" });
  const next = h("button", { class: "btn", type: "button" }, "Show next feature"), rst = h("button", { class: "btn", type: "button" }, "Restart");
  ui.append(q, h("div", { class: "ctl" }, next, rst), tbl);
  const svg = svgRoot(root, W, H, "svgfig", "Event EVT_0017 with five features drawn on its curve"); const g = el("g", {}, svg);

  function base(gg, dim = {}) {
    axisY(gg, y, m.l, yAx, v => v.toFixed(1), { grid: W - m.r }); axisX(gg, x, H - m.b, [-5, 0, 5, 10, 15, 20].map(d => ev.start + d * MIN).filter(t => t >= a0 && t <= a1), hhmm);
    el("text", { x: m.l, y: 20, class: "t3", text: "log10 flux" }, gg);
    el("text", { x: W - m.r, y: H - 8, "text-anchor": "end", class: "t3", text: "5 Sep 2026, UTC" }, gg);
    const after = t => dim.after && t > ev.peak;
    el("path", { d: linePath(pts.filter(p => p.t <= ev.peak).map(p => ({ x: p.t, y: p.logC })), x, y), fill: "none", stroke: "var(--cyan)", "stroke-width": 2 }, gg);
    el("path", { d: linePath(pts.filter(p => p.t >= ev.peak).map(p => ({ x: p.t, y: p.logC })), x, y), fill: "none", stroke: "var(--cyan)", "stroke-width": 2, opacity: dim.after ? 0.16 : 1, class: "post" }, gg);
    pts.forEach(p => el("circle", { cx: x(p.t), cy: y(p.logC), r: 3.4, class: "c-cyan", opacity: after(p.t) ? 0.16 : 1 }, gg));
    [["START", ev.start], ["PEAK", ev.peak]].forEach(([l, t], i) => { el("line", { x1: x(t), x2: x(t), y1: m.t, y2: H - m.b, stroke: "var(--gold)", "stroke-dasharray": "3 5", opacity: 0.6 }, gg); el("text", { x: x(t) + (i ? 8 : -8), y: m.t + 4, "text-anchor": i ? "start" : "end", class: "c-gold", text: `${l} ${hhmm(t)}` }, gg); });
  }
  function draw() {
    g.replaceChildren(); base(g, { after: false });
    const f = FEAT.slice(0, k + 1);
    q.textContent = f[k].q;
    f.forEach((F, i) => {
      const cur = i === k, o = cur ? 1 : 0.55;
      if (F.k === "bg_flux") { el("line", { x1: m.l, x2: x(ev.start), y1: y(bgLog), y2: y(bgLog), stroke: "var(--teal)", "stroke-width": 2, "stroke-dasharray": "6 4", opacity: o }, g); annot(g, x(a0 + 2 * MIN), y(bgLog) - 2, x(a0 + 2 * MIN) + 10, y(bgLog) - 70, `background flux\n${fmtSci(ev.bg_flux, 2)} W/m²`, "c-teal"); }
      if (F.k === "rise_duration_min") { const yy = H - m.b - 26; el("line", { x1: x(ev.start), x2: x(ev.peak), y1: yy, y2: yy, stroke: "var(--gold)", "stroke-width": 2.4, opacity: o }, g); [ev.start, ev.peak].forEach(t => el("line", { x1: x(t), x2: x(t), y1: yy - 7, y2: yy + 7, stroke: "var(--gold)", "stroke-width": 2, opacity: o }, g)); el("text", { x: (x(ev.start) + x(ev.peak)) / 2, y: yy - 12, "text-anchor": "middle", class: "c-gold", text: `rise duration ${ev.rise_duration_min} min` }, g); }
      if (F.k === "rise_slope") { const a = rise[0], b = rise[rise.length - 1], n = rise.length, xs = rise.map((_, j) => j), my = rise.reduce((s, p) => s + p.logC, 0) / n, mx = (n - 1) / 2; const sl = xs.reduce((s, j) => s + (j - mx) * (rise[j].logC - my), 0) / xs.reduce((s, j) => s + (j - mx) ** 2, 0); const yy = j => my + sl * (j - mx); el("line", { x1: x(a.t), y1: y(yy(0)), x2: x(b.t), y2: y(yy(n - 1)), stroke: "var(--orange)", "stroke-width": 2.6, opacity: o, class: cur ? "glow" : "" }, g); annot(g, x(rise[1].t) + 2, y(yy(1)) + 2, x(ev.start) - 60, y(yy(1)) + 22, `rise slope\n${ev.rise_slope.toFixed(4)} per min`, "c-orange", "end"); }
      if (F.k === "max_roc") { let j = 1; roc.forEach((r, i) => { if (i && r.v > roc[j].v) j = i; }); const a = rise[j - 1], b = rise[j]; el("line", { x1: x(a.t), y1: y(a.logC), x2: x(b.t), y2: y(b.logC), stroke: "var(--coral)", "stroke-width": 10, opacity: o * 0.85, "stroke-linecap": "round" }, g); annot(g, x(b.t), y(b.logC) + 4, x(b.t) + 40, y(b.logC) + 40, `steepest minute: ${hhmm(b.t)}\nmax ROC ${ev.max_roc.toFixed(4)}`, "c-coral", "start"); }
      if (F.k === "mean_pos_roc") { roc.forEach((r, i) => { if (i && r.v > 0) { const a = rise[i - 1], b = rise[i]; el("line", { x1: x(a.t), y1: y(a.logC), x2: x(b.t), y2: y(b.logC), stroke: "var(--gold)", "stroke-width": 2.4, opacity: cur ? 0.95 : 0.5 }, g); } }); annot(g, x(rise[3].t) + 4, y(rise[3].logC) + 2, x(ev.peak) + 90, y(-6.12), `average of the rising minutes\nmean positive ROC ${ev.mean_pos_roc.toFixed(4)}`, "c-gold", "start"); }
    });
    tbl.replaceChildren(...f.map(F => h("div", {}, F.n, h("b", {}, F.fmt(F.v)))), ...(k === 4 ? [h("div", { class: "go" }, "These five numbers are", h("b", {}, "one row in the ML table"))] : []));
    next.disabled = k === 4;
  }
  next.addEventListener("click", () => { k = Math.min(4, k + 1); draw(); }); rst.addEventListener("click", () => { k = 0; draw(); });
  draw();
  root.append(h("figcaption", { class: "cap", html: "<b>Real event EVT_0017</b> (C1.5, 5 Sep 2026). Values are the stored feature values; the overlays are drawn from the same CSV minutes." }));

  // ---- leakage figure: same curve ----
  const r2 = document.getElementById("fig-leak"), s2 = svgRoot(r2, W, H, "svgfig", "Same event with everything after the peak faded"), g2 = el("g", {}, s2);
  const lc = h("div", { class: "ctl" }); const lab = h("label", { class: "toggle" }, h("input", { type: "checkbox", checked: "" }), "Fade what the model may not see");
  r2.prepend(lc); lc.append(lab);
  function drawL(on) {
    g2.replaceChildren(); base(g2, { after: on });
    el("line", { x1: x(ev.peak), x2: x(ev.peak), y1: m.t, y2: H - m.b, stroke: "var(--coral)", "stroke-width": 2 }, g2);
    el("text", { x: x(ev.peak) + 10, y: H - m.b - 12, class: "c-coral", text: "t_pred = t_peak" }, g2);
    el("text", { x: x(a0 + 1 * MIN), y: m.t + 60, class: "t1", text: "known at the peak: used" }, g2);
    el("text", { x: x(ev.peak) + 10, y: y(-6.2), class: on ? "t3" : "t1", text: "not yet happened: excluded" }, g2);
    const px = x(ev.peak), py = y(Math.log10(ev.peak_flux));
    el("circle", { cx: px, cy: py, r: 8, fill: "none", stroke: "var(--coral)", "stroke-width": 2 }, g2);
    el("line", { x1: px - 6, y1: py - 6, x2: px + 6, y2: py + 6, stroke: "var(--coral)", "stroke-width": 2 }, g2);
    annot(g2, px + 7, py + 6, px + 110, y(-6.05), `peak_flux ${fmtSci(ev.peak_flux, 2)}\nexcluded: NOAA’s class is defined by it`, "c-coral", "start");
  }
  lab.querySelector("input").addEventListener("change", e => drawL(e.target.checked)); drawL(true);
  r2.append(h("figcaption", { class: "cap", html: "<b>Same real event.</b> At the peak the model has the bright part. The decay (faded) has not happened yet. peak_flux is crossed out because it would hand the classifier the answer." }));
}
