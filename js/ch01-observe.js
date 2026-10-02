import { el, h, svgRoot, lin, axisX, axisY, annot, hhmm, stamp, fmtSci, linePath, tip, MIN, sup } from "./lib.js";

export function init(ctx) {
  const root = document.getElementById("fig-observe");
  const WIN0 = Date.UTC(2026, 8, 5, 11, 40), N = 40;
  const rows = Array.from({ length: N }, (_, i) => ctx.at(WIN0 + i * MIN));

  const wrap = h("div", { class: "obs" }); root.append(wrap);
  // ---- left: actual CSV rows (XRS-B only) ----
  const left = h("div", {});
  left.append(h("p", { class: "colnote", html: "<b>time_tag</b> = when (UTC) &nbsp; <b>energy</b> = which band &nbsp; <b>flux</b> = how much, W/m²" }));
  const tbl = h("div", { class: "tbl", tabindex: "0", "aria-label": "CSV rows, XRS-B channel" });
  const table = h("table", { class: "t" }, h("thead", {}, h("tr", {}, h("th", {}, "time_tag"), h("th", {}, "energy"), h("th", { class: "n" }, "flux"))));
  const tb = h("tbody"); table.append(tb); tbl.append(table); left.append(tbl); wrap.append(left);
  const trs = rows.map((p, i) => {
    const tr = h("tr", { tabindex: "0", "data-i": i }, h("td", {}, p.tag.replace("+00:00", "")), h("td", {}, p.energy), h("td", { class: "n" }, fmtSci(p.flux, 3)));
    tr.addEventListener("mouseenter", () => focusPt(i, false)); tr.addEventListener("focus", () => focusPt(i, false));
    tb.append(tr); return tr;
  });

  // ---- right: the same minutes as a graph, plus the full week as a minimap ----
  const right = h("div", {}); wrap.append(right);
  const W = 860, H = 400, m = { l: 74, r: 24, t: 20, b: 44 };
  const svg = svgRoot(right, W, H, "svgfig", "Flux over 40 minutes on 5 September; each dot is one CSV row");
  const x = lin(WIN0, WIN0 + (N - 1) * MIN, m.l, W - m.r);
  const y = lin(-6.55, -5.75, H - m.b, m.t);
  const gy = el("g", {}, svg);
  axisY(gy, y, m.l, [3e-7, 5e-7, 1e-6, 1.5e-6].map(Math.log10), v => (10 ** v).toExponential(1).replace("e-", "e−"), { grid: W - m.r });
  axisX(gy, x, H - m.b, [0, 10, 20, 30, 39].map(i => WIN0 + i * MIN), hhmm, { grid: [m.t, H - m.b] });
  el("text", { x: m.l, y: 13, class: "t3", text: "flux, W/m² (log scale)" }, gy);
  el("text", { x: W - m.r, y: H - 6, "text-anchor": "end", class: "t3", text: "5 Sep 2026, UTC" }, gy);
  const yc = y(-6);
  el("line", { x1: m.l, x2: W - m.r, y1: yc, y2: yc, stroke: "var(--gold)", "stroke-dasharray": "5 5", opacity: 0.7 }, gy);
  el("text", { x: m.l + 8, y: yc - 8, class: "c-gold", text: "C-class flares start at 1e−6" }, gy);
  const pts = rows.map((p, i) => ({ x: p.t, y: p.logC, i }));
  el("path", { d: linePath(pts, x, y), fill: "none", stroke: "var(--cyan)", "stroke-width": 1.5, opacity: 0.8 }, svg);
  const dots = pts.map(p => { const c = el("circle", { cx: x(p.x), cy: y(p.y), r: 4, class: "c-cyan", tabindex: "-1" }, svg); c.addEventListener("mouseenter", e => focusPt(p.i, true, e)); c.addEventListener("mouseleave", () => tip(null)); return c; });
  const ring = el("circle", { r: 9, fill: "none", stroke: "var(--gold)", "stroke-width": 2, opacity: 0 }, svg);
  const vline = el("line", { y1: m.t, y2: H - m.b, stroke: "var(--gold)", "stroke-width": 1, opacity: 0 }, svg);
  annot(svg, x(rows[24].t), y(rows[24].logC) - 2, x(rows[24].t) - 190, m.t + 40, "this row is one minute,\nnot one flare", "t1");
  let cur = -1;
  function focusPt(i, scroll, ev) {
    if (cur >= 0) { trs[cur].classList.remove("hl"); dots[cur].setAttribute("r", 4); }
    cur = i; trs[i].classList.add("hl"); dots[i].setAttribute("r", 5.5);
    const cx = +dots[i].getAttribute("cx"), cy = +dots[i].getAttribute("cy");
    ring.setAttribute("cx", cx); ring.setAttribute("cy", cy); ring.setAttribute("opacity", 1);
    vline.setAttribute("x1", cx); vline.setAttribute("x2", cx); vline.setAttribute("opacity", 0.5);
    if (scroll) { tbl.scrollTop = Math.max(0, trs[i].offsetTop - tbl.clientHeight / 2); if (ev) tip(`${hhmm(rows[i].t)} UTC<br>flux ${fmtSci(rows[i].flux, 3)} W/m²`, ev); }
  }
  focusPt(22, false);

  // minimap: the whole week, window marked
  const mh = 120, mm = svgRoot(right, W, mh, "svgfig", "Whole week of flux with the 40-minute window marked");
  mm.style.marginTop = "18px";
  const t0 = ctx.series[0].t, t1 = ctx.series[ctx.series.length - 1].t;
  const lv = ctx.series.map(p => p.logC).filter(isFinite); const ymin = Math.min(...lv), ymax = Math.max(...lv);
  const X = lin(t0, t1, m.l, W - m.r), Y = lin(ymin, ymax, mh - 28, 14);
  el("path", { d: linePath(ctx.series.map(p => ({ x: p.t, y: p.logC })), X, Y), fill: "none", stroke: "var(--cyan)", "stroke-width": 0.8, opacity: 0.85 }, mm);
  for (let d = 0; d < 8; d++) { const t = Date.UTC(2026, 8, 5 + d - 1); if (t < t0 || t > t1) continue; el("line", { class: "ax", x1: X(t), x2: X(t), y1: mh - 28, y2: mh - 22 }, mm); el("text", { x: X(t), y: mh - 8, "text-anchor": "middle", class: "t3", text: `${new Date(t).getUTCDate()} Sep` }, mm); }
  el("rect", { x: X(WIN0) - 3, y: 8, width: Math.max(6, X(WIN0 + N * MIN) - X(WIN0)) + 6, height: mh - 38, fill: "none", stroke: "var(--gold)" }, mm);
  el("text", { x: m.l, y: 12, class: "t3", text: "the whole week: 10,078 rows" }, mm);

  root.append(h("figcaption", { class: "cap", html: "<b>Left:</b> real rows from the project file (XRS-B channel only). <b>Right:</b> the same 40 minutes plotted. Hover a row or a dot and watch the other follow." }));

  // stacked-file explainer (real first rows of the raw table)
  const demo = document.getElementById("stacked-demo");
  const trow = r => h("tr", {}, h("td", {}, r.time_tag.replace("+00:00", "")), h("td", {}, r.energy), h("td", { class: "n" }, fmtSci(+r.flux, 3)));
  const t = h("table", { class: "t", style: "max-width:560px" }, h("thead", {}, h("tr", {}, h("th", {}, "time_tag"), h("th", {}, "energy"), h("th", { class: "n" }, "flux"))), h("tbody", {}, ctx.stackedHead.map(trow)));
  demo.append(t, h("p", { class: "note", style: "margin-top:12px", text: "The first two rows are the shorter-wavelength band (0.05–0.4 nm). The third is the same first minute in the band we use. The file lists one band’s 10,078 rows, then the other’s." }));
}
