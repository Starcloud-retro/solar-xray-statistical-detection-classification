import { el, h, svgRoot, lin, axisX, axisY, annot, hhmm, f3, linePath, tabs, utc, MIN, mean, sd, median, mad, stamp } from "./lib.js";

export function init(ctx) {
  const ui = document.getElementById("detect-ui"), root = document.getElementById("fig-detect");
  const T = ctx.truth.detector, rows = ctx.detect.rows.map(r => ({ ...r, t: utc(r.time_tag) }));
  const ev = ctx.evAll.find(e => e.event_id === "EVT_0003");
  const W = 1320, H = 640;
  const svg = svgRoot(root, W, H, "svgfig", "Detector measures for the minutes around 19:04 on 4 September");
  const g = el("g", {}, svg);
  const info = h("div", { class: "prose", style: "margin:0 0 24px" }); ui.append(info);
  const m = { l: 96, r: 70 };

  // worked example for 19:04, recomputed from the CSV (trailing 30 values, current minute excluded)
  const i = ctx.idx(utc("2026-09-04 19:04")), win = []; for (let k = i - 30; k < i; k++) win.push(ctx.series[k].logC);
  const cur = ctx.series[i].logC, prev = ctx.series[i - 1].logC;
  const ex = { mu: mean(win), s: sd(win), med: median(win), mds: mad(win) * T.mad_scale, cur, roc: cur - prev };
  ex.z = (cur - ex.mu) / ex.s; ex.zm = (cur - ex.med) / ex.mds;

  const copy = [
    { n: "Z-score", q: "How many local spreads above recent normal is this minute?", p: `At 19:04 the signal is ${f3(ex.cur)}, the recent mean is ${f3(ex.mu)} and the recent SD is ${ex.s.toFixed(4)}. The minute sits ${ex.z.toFixed(2)} spreads above normal.`, f: "Z-score = (value − mean) ÷ SD, using the previous 30 minutes.", thr: 3.0, key: "z_mean", tr: "z_mean_trigger", cap: 30 },
    { n: "Robust Z", q: "Same question, but measured from the median in scaled-MAD units.", p: `The median-based spread is smaller than the SD when the background is calm, so the same minute scores ${ex.zm.toFixed(2)}. It grows far larger as the flare climbs because MAD is not dragged upward by the flare.`, f: "Robust Z = (value − median) ÷ (1.4826 × MAD).", thr: 3.0, key: "z_mad", tr: "z_mad_trigger", cap: 30 },
    { n: "ROC", q: "How fast did the log10 flux change since the last minute?", p: `From 19:04 to 19:05 the log10 flux rose from ${f3(rows[6].log10_flux)} to ${f3(rows[7].log10_flux)}, a change of ${rows[7].roc.toFixed(4)} per minute, just above the 0.05 limit (about 12% more flux each minute).`, f: "ROC (rate of change) = log10(flux now) − log10(flux a minute ago).", thr: 0.05, key: "roc", tr: "roc_trigger", cap: 0.25 },
    { n: "Persistence", q: "Does the unusual behaviour last?", p: `Z and robust Z are both above 3.0 from 19:04 through 19:11, eight minutes in a row. One strange minute may be noise; three in a row is an event. The event table records START 19:04, PEAK 19:21 and END 19:21. The frozen detector also uses a 5-minute slope, which this strip does not show.`, f: "Persistence ≥ 3 consecutive flagged minutes.", thr: null, key: null, tr: null }
  ];

  function draw(k) {
    g.replaceChildren(); const c = copy[k];
    info.replaceChildren(h("p", {}, h("strong", {}, c.q)), h("p", {}, c.p), h("p", { class: "note" }, "Formal name: ", c.f));
    const tEnd = k === 3 ? utc("2026-09-04 19:22") : rows[rows.length - 1].t;
    const t0 = rows[0].t, flux = []; for (let t = t0; t <= tEnd; t += MIN) flux.push(ctx.at(t));
    const x = lin(t0, tEnd, m.l, W - m.r), yT = lin(-6.3, Math.max(...flux.map(p => p.logC)) + 0.05, 290, 30);
    const trig = {}; rows.forEach(r => trig[r.t] = r.z_mean_trigger && r.z_mad_trigger);
    // top: flux
    axisY(g, yT, m.l, [-6.2, -6.0, -5.8, -5.6, -5.4].filter(v => v > -6.3 && v < yT.invert(30)), v => v.toFixed(1), { grid: W - m.r });
    el("text", { x: m.l, y: 16, class: "t3", text: "log10 flux" }, g);
    el("path", { d: linePath(flux.map(p => ({ x: p.t, y: p.logC })), x, yT), fill: "none", stroke: "var(--cyan)", "stroke-width": 1.4, opacity: 0.6 }, g);
    flux.forEach(p => { const fl = trig[p.t]; el("circle", { cx: x(p.t), cy: yT(p.logC), r: fl ? 5 : 3.5, class: fl ? "c-orange" : "c-cyan" }, g); });
    // bottom: measure bars
    const by0 = 590, bh = 200, bx = (tEnd - t0) / MIN + 1, bw = Math.min(30, (W - m.l - m.r) / bx * 0.62);
    axisX(g, x, by0, [0, 4, 8, 12, 16, 20].map(d => t0 + d * MIN).filter(t => t <= tEnd), hhmm);
    if (c.key) {
      const yB = lin(0, c.cap, by0, by0 - bh);
      axisY(g, yB, m.l, c.key === "roc" ? [0, 0.1, 0.2] : [0, 10, 20, 30], v => String(v), {});
      rows.forEach(r => {
        const v = r[c.key], hit = r[c.tr], vv = Math.max(0, Math.min(c.cap, v)), top = yB(vv);
        el("rect", { x: x(r.t) - bw / 2, y: top, width: bw, height: Math.max(0.5, by0 - top), class: hit ? "c-orange" : "c-cyan", opacity: hit ? 0.9 : 0.5 }, g);
        const lab = c.key === "roc" ? v.toFixed(3) : v.toFixed(1);
        if (v > 0 || Math.abs(v) < 1) el("text", { x: x(r.t), y: Math.min(top, by0) - 7, "text-anchor": "middle", class: hit ? "c-orange" : "t3", "font-size": 11.5, text: (v > c.cap ? "▲ " : "") + lab }, g);
      });
      const yt = yB(c.thr); el("line", { x1: m.l, x2: W - m.r, y1: yt, y2: yt, stroke: "var(--gold)", "stroke-dasharray": "6 5" }, g);
      el("text", { x: m.l + 8, y: yt - 8, class: "c-gold", text: `limit ${c.thr}` }, g);
      el("text", { x: m.l, y: by0 - bh - 16, class: "t1", text: c.n }, g);
      if (v_cap()) el("text", { x: W - m.r, y: by0 - bh - 16, "text-anchor": "end", class: "t3", text: "bars above the axis are cut off; ▲ marks the real value" }, g);
      function v_cap() { return rows.some(r => r[c.key] > c.cap); }
    } else {
      // persistence: strip of flagged minutes, then the merge into one event
      const flagged = rows.filter(r => r.z_mean_trigger && r.z_mad_trigger);
      const sy = 470;
      el("text", { x: m.l, y: sy - 52, class: "t1", text: "Flagged minutes (Z and robust Z both above 3.0)" }, g);
      rows.forEach(r => { const f = r.z_mean_trigger && r.z_mad_trigger; el("rect", { x: x(r.t) - 13, y: sy - 18, width: 26, height: 26, class: f ? "c-orange" : "nofill", stroke: f ? "none" : "var(--hair-2)", opacity: f ? 0.9 : 1, fill: f ? "var(--orange)" : "none" }, g); });
      const fa = flagged[0].t, fb = flagged[2].t;
      el("path", { d: `M ${x(fa) - 13} ${sy + 20} v 8 H ${x(fb) + 13} v -8`, class: "nofill", stroke: "var(--gold)", "stroke-width": 1.6 }, g);
      el("text", { x: (x(fa) + x(fb)) / 2, y: sy + 48, "text-anchor": "middle", class: "c-gold", text: "3 in a row: it is an event" }, g);
      // event bracket on the flux curve
      const xs = x(ev.start), xp = x(ev.peak);
      [["START", ev.start, 0], ["PEAK", ev.peak, 1], ["END", ev.end, 2]].forEach(([lb, t, j]) => {
        el("line", { x1: x(t), x2: x(t), y1: 28, y2: 296, stroke: "var(--gold)", "stroke-width": 1.4, "stroke-dasharray": j === 2 ? "2 4" : "" }, g);
        el("text", { x: x(t) + (j === 0 ? -8 : 8), y: 44 + j * 18, "text-anchor": j === 0 ? "end" : "start", class: "c-gold", text: `${lb} ${hhmm(t)}` }, g);
      });
      el("text", { x: m.l, y: by0 - 60, class: "t3", text: "Flagged-minute values come from the project’s detector output for 18:58–19:12; the START, PEAK and END times come from the event table." }, g);
    }
  }
  tabs(ui, copy.map(c => c.n), draw, 0);
  root.append(h("figcaption", { class: "cap", html: "<b>One real event: EVT_0003, 4 September.</b> Orange = minutes the detector flagged. The grey-blue bars are minutes inside the normal range." }));
}
