import { el, h, svgRoot, lin, axisX, annot, hhmm, stamp, dmon, linePath, utc, MIN, f3, fmtInt } from "./lib.js";

export function init(ctx) {
  const root = document.getElementById("fig-noaa"), N = ctx.noaa, T = ctx.truth.noaa;
  const matched = N.matched_events.filter(e => e.peak_time);
  const sub = t => h("p", { style: "font-family:var(--serif);font-size:24px;margin:48px 0 8px;color:var(--text-1)" }, t);

  // ===== 1. the week: our detections above, NOAA records below =====
  root.append(sub("Across the week: events we detected that line up with a NOAA record"));
  const W = 1320, H = 250, m = { l: 150, r: 30 };
  const svg = svgRoot(root, W, H, "svgfig", "Matched detected events and NOAA records across the week");
  const t0 = ctx.series[0].t, t1 = ctx.series[ctx.series.length - 1].t, x = lin(t0, t1, m.l, W - m.r);
  const ties = [Date.UTC(2026, 8, 5), Date.UTC(2026, 8, 6), Date.UTC(2026, 8, 7), Date.UTC(2026, 8, 8), Date.UTC(2026, 8, 9), Date.UTC(2026, 8, 10), Date.UTC(2026, 8, 11)];
  axisX(svg, x, 210, ties, t => dmon(t), { grid: [50, 210] });
  const yTop = 78, yBot = 170;
  el("text", { x: 0, y: yTop + 4, class: "c-orange", text: "our detected events" }, svg);
  el("text", { x: 0, y: yBot + 4, class: "c-gold", text: "NOAA records" }, svg);
  const rad = c => ({ B: 5, C: 7.5, M: 11, U: 5 })[c] || 5;
  matched.forEach(e => {
    const px = x(utc(e.peak_time)), L = (e.noaa_class || "U")[0];
    el("line", { x1: px, x2: px, y1: yTop, y2: yBot, stroke: "var(--text-3)", "stroke-width": 1, opacity: 0.8 }, svg);
    el("circle", { cx: px, cy: yTop, r: rad(L), class: "c-orange" }, svg);
    el("rect", { x: px - rad(L), y: yBot - rad(L), width: rad(L) * 2, height: rad(L) * 2, transform: `rotate(45 ${px} ${yBot})`, class: "c-gold" }, svg);
  });
  root.append(h("figcaption", { class: "cap", html: `Marker size follows flare class (B small, C medium, M large). Timing errors are at most 11 minutes, too small to see on a week-long axis, so each pair is drawn vertically; the NOAA marker is placed at the detected peak time at this scale. <b>${matched.length} detected events</b> are linked to a NOAA record. The 80 detections with no NOAA record and the 3 NOAA records we did not detect have no matched pair to draw, so they appear in the counts below.` }));

  // ===== 2. one pair, zoomed =====
  const ex = N.example, evx = ctx.evAll.find(e => e.event_id === ex.event_id);
  root.append(sub("One real pair, zoomed: EVT_0003 and NOAA record NOAA_0001"));
  const W2 = 1320, H2 = 330, a0 = utc("2026-09-04 18:55"), a1 = utc("2026-09-04 19:48");
  const s2 = svgRoot(root, W2, H2, "svgfig", "Detected interval and NOAA record for one event"), x2 = lin(a0, a1, 110, W2 - 40);
  const fl = []; for (let t = a0; t <= a1; t += MIN) fl.push(ctx.at(t));
  const ys = lin(Math.min(...fl.map(p => p.logC)), Math.max(...fl.map(p => p.logC)), 215, 108);
  axisX(s2, x2, 290, [0, 10, 20, 30, 40, 50].map(d => a0 + d * MIN), hhmm, { grid: [96, 290] });
  el("path", { d: linePath(fl.map(p => ({ x: p.t, y: p.logC })), x2, ys), fill: "none", stroke: "var(--cyan)", "stroke-width": 1.5 }, s2);
  const bn = utc(ex.noaa_begin), pk = utc(ex.noaa_peak), en = utc(ex.noaa_end);
  // lanes
  el("text", { x: 0, y: 40, class: "c-orange", text: "detected" }, s2); el("text", { x: 0, y: 70, class: "c-gold", text: "NOAA" }, s2);
  el("line", { x1: x2(evx.start), x2: x2(evx.end), y1: 36, y2: 36, stroke: "var(--orange)", "stroke-width": 3 }, s2);
  [[evx.start, "start"], [evx.peak, "peak"]].forEach(([t, l]) => { el("circle", { cx: x2(t), cy: 36, r: l === "peak" ? 6 : 4, class: "c-orange" }, s2); });
  el("text", { x: x2(evx.peak) + 10, y: 28, class: "c-orange", text: `peak ${hhmm(evx.peak)}` }, s2);
  el("text", { x: x2(evx.start) - 10, y: 28, "text-anchor": "end", class: "c-orange", text: `start ${hhmm(evx.start)}` }, s2);
  el("line", { x1: x2(bn), x2: x2(en), y1: 70, y2: 70, stroke: "var(--gold)", "stroke-width": 3 }, s2);
  [[bn, 4], [pk, 6], [en, 4]].forEach(([t, r]) => el("rect", { x: x2(t) - r, y: 70 - r, width: 2 * r, height: 2 * r, transform: `rotate(45 ${x2(t)} 70)`, class: "c-gold" }, s2));
  el("text", { x: x2(pk) + 12, y: 92, class: "c-gold", text: `NOAA peak ${hhmm(pk)} (C6.7)` }, s2);
  el("text", { x: x2(bn) - 10, y: 92, "text-anchor": "end", class: "c-gold", text: `begin ${hhmm(bn)}` }, s2);
  el("text", { x: x2(en) + 10, y: 74, class: "c-gold", text: `end ${hhmm(en)}` }, s2);
  el("line", { x1: x2(evx.peak), x2: x2(pk), y1: 52, y2: 52, stroke: "var(--text-1)", "stroke-width": 1 }, s2);
  el("text", { x: (x2(evx.peak) + x2(pk)) / 2, y: 49, "text-anchor": "middle", class: "t1", text: `${ex.abs_peak_error_min} min` }, s2);
  root.append(h("figcaption", { class: "cap", html: "<b>Real times.</b> The detector caught the climb and its interval stops at our peak, 9 minutes before NOAA’s peak. Most events line up much more closely: in the 31 events that reach machine learning, 27 have the same peak minute as NOAA." }));

  // ===== 3. precision, recall side by side =====
  root.append(sub("Aggregate results, with both numbers side by side"));
  root.append(h("div", { class: "stats" },
    h("div", { class: "stat c-gold" }, h("div", { class: "n" }, T.recall.toFixed(4)), h("div", { class: "l" }, "recall: of 35 NOAA records, we detected 32")),
    h("div", { class: "stat c-orange" }, h("div", { class: "n" }, T.precision.toFixed(4)), h("div", { class: "l" }, "precision: of 112 detections, 32 match a NOAA record")),
    h("div", { class: "stat" }, h("div", { class: "n" }, T.f1.toFixed(4)), h("div", { class: "l" }, "F1, the balance of the two")),
    h("div", { class: "stat" }, h("div", { class: "n" }, `${T.median_abs_err.toFixed(2)} / ${T.mean_abs_err.toFixed(2)}`), h("div", { class: "l" }, "median / mean absolute peak timing error, minutes"))));
  // unit charts
  const W3 = 1320, H3 = 230, s3 = svgRoot(root, W3, H3, "svgfig", "Unit charts for precision and recall");
  const unit = (n, matchedN, x0, y0, perRow, pitch, kind) => {
    for (let i = 0; i < n; i++) {
      const cx = x0 + (i % perRow) * pitch, cy = y0 + Math.floor(i / perRow) * pitch, ok = i < matchedN;
      if (kind === "det") el("circle", { cx, cy, r: 6, fill: ok ? "var(--orange)" : "none", stroke: ok ? "var(--orange)" : "var(--text-2)", "stroke-width": 1.3, "stroke-dasharray": ok ? "" : "2.5 2.5" }, s3);
      else el("rect", { x: cx - 5, y: cy - 5, width: 10, height: 10, transform: `rotate(45 ${cx} ${cy})`, fill: ok ? "var(--gold)" : "none", stroke: "var(--gold)", "stroke-width": 1.3, "stroke-dasharray": ok ? "" : "2.5 2.5" }, s3);
    }
  };
  el("text", { x: 0, y: 18, class: "t1", text: "Precision: 112 detections" }, s3); unit(112, 32, 10, 46, 28, 17, "det");
  el("text", { x: 0, y: 160, class: "c-orange", text: "32 filled: linked to a NOAA record" }, s3);
  el("text", { x: 0, y: 182, class: "t1", text: "80 dashed: no NOAA record (not “false flares”)" }, s3);
  el("text", { x: 700, y: 18, class: "t1", text: "Recall: 35 NOAA records" }, s3); unit(35, 32, 710, 46, 12, 24, "noaa");
  el("text", { x: 700, y: 160, class: "c-gold", text: "32 filled: we detected it" }, s3);
  el("text", { x: 700, y: 182, class: "t1", text: "3 hollow: we did not detect it" }, s3);
  root.append(h("figcaption", { class: "cap", html: `<b>Precision = 32 ÷ (32 + 80) = 0.2857.  Recall = 32 ÷ (32 + 3) = 0.9143.</b> 115 detector intervals in total; three NOAA flares were each picked up as two intervals, so the 35 linked intervals describe 32 flares. The times of the 80 unlinked detections are shown only as a count.` }));
  root.append(h("div", { class: "callout warn" }, h("span", { class: "k" }, "Read this before trusting the detector"), h("p", {}, "About 7 in 10 of our detections have no NOAA match. That is a limit of this simple detector and of what the NOAA list contains, not a verdict on each event.")));
}
