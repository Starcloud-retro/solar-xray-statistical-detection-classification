import { el, rng, lin, linePath, PRM } from "./lib.js";

// Atmospheric artwork (gradients + seeded stars). The one data element is the thin signal trace: real XRS-B flux for 5 Sep.
export function init(ctx) {
  const host = document.getElementById("hero-art");
  const W = 1440, H = 900;
  const s = el("svg", { viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: "xMidYMid slice", "aria-hidden": "true" }, host);
  const defs = el("defs", {}, s);
  const rg = (id, stops, attrs = {}) => { const g = el("radialGradient", { id, ...attrs }, defs); stops.forEach(([o, c, a]) => el("stop", { offset: o, "stop-color": c, "stop-opacity": a ?? 1 }, g)); };
  const lg = (id, stops, attrs = {}) => { const g = el("linearGradient", { id, ...attrs }, defs); stops.forEach(([o, c, a]) => el("stop", { offset: o, "stop-color": c, "stop-opacity": a ?? 1 }, g)); };
  lg("sky", [[0, "#04060D"], [1, "#0A1226"]], { x1: 0, y1: 0, x2: 0, y2: 1 });
  rg("corona", [[0.62, "#F28A2E", 0.34], [0.78, "#C8501A", 0.12], [1, "#C8501A", 0]], { gradientUnits: "userSpaceOnUse", cx: -80, cy: 470, r: 700 });
  rg("sun", [[0, "#FFD98A"], [0.55, "#F6A23A"], [0.86, "#E26A1B"], [1, "#8C2D0A"]], { gradientUnits: "userSpaceOnUse", cx: -230, cy: 470, r: 590 });
  rg("earth", [[0, "#0B1C3E"], [0.9, "#060D22"], [1, "#04070F"]], { gradientUnits: "userSpaceOnUse", cx: 1180, cy: 1500, r: 820 });
  lg("rim", [[0, "#F6A23A", 0.95], [0.35, "#5BC8F0", 0.7], [1, "#5BC8F0", 0.05]], { gradientUnits: "userSpaceOnUse", x1: 700, y1: 900, x2: 1440, y2: 720 });
  lg("beam", [[0, "#F28A2E", 0.0], [0.3, "#F28A2E", 0.55], [1, "#5BC8F0", 0.8]], { gradientUnits: "userSpaceOnUse", x1: 330, y1: 450, x2: 1080, y2: 345 });
  const blur = el("filter", { id: "blur", x: "-20%", y: "-20%", width: "140%", height: "140%" }, defs); el("feGaussianBlur", { stdDeviation: 14 }, blur);
  const blur2 = el("filter", { id: "blur2", x: "-20%", y: "-20%", width: "140%", height: "140%" }, defs); el("feGaussianBlur", { stdDeviation: 3 }, blur2);

  el("rect", { width: W, height: H, fill: "url(#sky)" }, s);
  // stars
  const r = rng(7); const g = el("g", {}, s);
  for (let i = 0; i < 190; i++) { const x = r() * W, y = r() * H * 0.92; if (x < 330 && Math.hypot(x + 80, y - 470) < 560) continue; el("circle", { cx: x.toFixed(1), cy: y.toFixed(1), r: (0.35 + r() * 0.95).toFixed(2), fill: "#F3EDE2", opacity: (0.25 + r() * 0.6).toFixed(2) }, g); }
  // Sun limb, corona, prominences
  el("circle", { cx: -80, cy: 470, r: 700, fill: "url(#corona)" }, s);
  el("circle", { cx: -80, cy: 470, r: 436, fill: "#F28A2E", opacity: 0.35, filter: "url(#blur)" }, s);
  el("circle", { cx: -80, cy: 470, r: 430, fill: "url(#sun)" }, s);
  const prom = [["M 318 250 C 372 270 392 330 350 392", 3], ["M 340 600 C 398 610 420 548 384 498", 2.4], ["M 224 120 C 300 150 318 214 286 262", 2]];
  prom.forEach(([d, w]) => { el("path", { d, fill: "none", stroke: "#FFB347", "stroke-width": w + 5, opacity: 0.35, filter: "url(#blur2)" }, s); el("path", { d, fill: "none", stroke: "#FFC76B", "stroke-width": w, opacity: 0.8, "stroke-linecap": "round" }, s); });
  // Earth horizon
  el("circle", { cx: 1180, cy: 1500, r: 812, fill: "none", stroke: "#5BC8F0", "stroke-width": 14, opacity: 0.18, filter: "url(#blur)" }, s);
  el("circle", { cx: 1180, cy: 1500, r: 800, fill: "url(#earth)" }, s);
  el("circle", { cx: 1180, cy: 1500, r: 800, fill: "none", stroke: "url(#rim)", "stroke-width": 2 }, s);
  // GOES-18 silhouette (schematic): bus, solar array, antenna
  const sat = el("g", { transform: "translate(1090 330) rotate(-14)" }, s);
  el("rect", { x: -26, y: -20, width: 52, height: 40, fill: "#0E1630", stroke: "#F28A2E", "stroke-width": 1, opacity: 0.95 }, sat);
  el("rect", { x: 26, y: -9, width: 150, height: 18, fill: "#0A1128", stroke: "#2c3a63", "stroke-width": 1 }, sat);
  for (let i = 1; i < 6; i++) el("line", { x1: 26 + i * 25, y1: -9, x2: 26 + i * 25, y2: 9, stroke: "#2c3a63" }, sat);
  el("line", { x1: -26, y1: 0, x2: -52, y2: 0, stroke: "#4a5a86", "stroke-width": 1.4 }, sat);
  el("ellipse", { cx: -62, cy: 0, rx: 5, ry: 17, fill: "#0E1630", stroke: "#F28A2E", "stroke-width": 1 }, sat);
  el("line", { x1: 0, y1: -20, x2: 0, y2: -36, stroke: "#4a5a86" }, sat);
  el("circle", { cx: 0, cy: -38, r: 3, fill: "#F6C453" }, sat);
  // beam: Sun → satellite → down to signal
  el("path", { d: "M 330 452 Q 700 360 1060 346", fill: "none", stroke: "url(#beam)", "stroke-width": 1.2, "stroke-dasharray": "2 7" }, s);
  el("path", { d: "M 1096 372 L 1096 566", fill: "none", stroke: "#5BC8F0", "stroke-width": 1, "stroke-dasharray": "2 6", opacity: 0.7 }, s);

  // real data trace: GOES-18 XRS-B, 5 Sep 2026 (every 5th minute; gaps are not bridged)
  const d0 = Date.UTC(2026, 8, 5), pts = [];
  for (let m = 0; m < 1440; m += 5) { const p = ctx.at(d0 + m * 60000); pts.push({ x: m, y: p ? p.logC : NaN }); }
  const ys = pts.map(p => p.y).filter(isFinite).sort((a, b) => a - b);
  const lo = ys[Math.floor(ys.length * 0.01)];   // scale to the day's typical range; rare low outliers are clamped
  pts.forEach(p => { if (isFinite(p.y)) p.y = Math.max(p.y, lo); });
  const X = lin(0, 1440, 1096, 1410), Y = lin(lo, ys[ys.length - 1], 650, 566);
  const path = el("path", { d: linePath(pts, X, Y), class: PRM ? "" : "trace", fill: "none", stroke: "#5BC8F0", "stroke-width": 1.5, "stroke-linejoin": "round" }, s);
  el("circle", { cx: 1096, cy: 566, r: 3.5, fill: "#5BC8F0" }, s);
  el("text", { x: 1096, y: 676, fill: "#8E8A82", "font-family": "IBM Plex Mono, monospace", "font-size": 12 }, s).textContent = "GOES-18 XRS-B, 5 Sep 2026 (real data, scaled to the day)";
  if (!PRM && path.getTotalLength) { try { path.style.setProperty("--len", Math.ceil(path.getTotalLength())); } catch (e) { /* jsdom */ } }
}
