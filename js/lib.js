// Shared helpers: SVG building, scales, formatting, scroll/visibility, tooltip.
export const NS = "http://www.w3.org/2000/svg";
export const PRM = typeof matchMedia !== "undefined" && matchMedia("(prefers-reduced-motion: reduce)").matches;

export function el(tag, attrs = {}, parent) {
  const n = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null) continue;
    if (k === "text") n.textContent = v;
    else if (k === "class") n.setAttribute("class", v);
    else n.setAttribute(k, v);
  }
  if (tag === "text" && attrs.fill) n.style.fill = attrs.fill;
  if (parent) parent.appendChild(n);
  return n;
}
export function h(tag, attrs = {}, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null) continue;
    if (k === "class") n.className = v;
    else if (k === "html") n.innerHTML = v;
    else if (k === "text") n.textContent = v;
    else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
    else n.setAttribute(k, v);
  }
  for (const c of kids.flat()) if (c != null) n.append(c.nodeType ? c : document.createTextNode(c));
  return n;
}
export function svgRoot(parent, w, h_, cls = "svgfig", label = "") {
  const s = el("svg", { viewBox: `0 0 ${w} ${h_}`, class: cls, role: "img", "aria-label": label, preserveAspectRatio: "xMidYMid meet" }, parent);
  return s;
}
export const lin = (d0, d1, r0, r1) => { const k = (r1 - r0) / (d1 - d0); const f = v => r0 + (v - d0) * k; f.invert = y => d0 + (y - r0) / k; f.domain = [d0, d1]; f.range = [r0, r1]; return f; };
export const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
export const mean = a => a.reduce((s, v) => s + v, 0) / a.length;
export const sd = a => { const m = mean(a); return Math.sqrt(a.reduce((s, v) => s + (v - m) ** 2, 0) / (a.length - 1)); };
export const median = a => { const b = [...a].sort((x, y) => x - y); const n = b.length; return n % 2 ? b[(n - 1) / 2] : (b[n / 2 - 1] + b[n / 2]) / 2; };
export const mad = a => { const m = median(a); return median(a.map(v => Math.abs(v - m))); };
export const pad2 = n => String(n).padStart(2, "0");
export const hhmm = ms => { const d = new Date(ms); return `${pad2(d.getUTCHours())}:${pad2(d.getUTCMinutes())}`; };
export const MON = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
export const dmon = ms => { const d = new Date(ms); return `${d.getUTCDate()} ${MON[d.getUTCMonth()]}`; };
export const stamp = ms => `${dmon(ms)} ${hhmm(ms)} UTC`;
export const MIN = 60000;
export const utc = s => { let x = String(s).trim().replace(" ", "T").replace(/(Z|\+00:00)$/, ""); if (x.length === 16) x += ":00"; return Date.parse(x + "Z"); };
export function fmtSci(v, d = 2) {
  if (!isFinite(v)) return "—";
  const e = Math.floor(Math.log10(Math.abs(v)));
  const m = v / 10 ** e;
  return `${m.toFixed(d)}e${e < 0 ? "−" : ""}${Math.abs(e)}`;
}
export const sup = n => `10${String(n).replace("-", "⁻").replace(/\d/g, d => "⁰¹²³⁴⁵⁶⁷⁸⁹"[d])}`;
export const f3 = v => (v < 0 ? "−" : "") + Math.abs(v).toFixed(3);
export const fmtInt = n => n.toLocaleString("en-US");

// path with breaks where a point is not defined (gaps are NEVER bridged)
export function linePath(pts, X, Y, defined = p => isFinite(p.y)) {
  let d = "", pen = false;
  for (const p of pts) {
    if (!defined(p)) { pen = false; continue; }
    d += (pen ? "L" : "M") + X(p.x).toFixed(1) + " " + Y(p.y).toFixed(1);
    pen = true;
  }
  return d;
}
export function axisX(g, scale, y, ticks, fmt, opts = {}) {
  el("line", { class: "ax", x1: scale.range[0], x2: scale.range[1], y1: y, y2: y }, g);
  for (const t of ticks) {
    const x = scale(t);
    el("line", { class: "ax", x1: x, x2: x, y1: y, y2: y + 6 }, g);
    if (opts.grid) el("line", { class: "grid", x1: x, x2: x, y1: opts.grid[0], y2: opts.grid[1] }, g);
    el("text", { x, y: y + 22, "text-anchor": "middle", class: "t3", text: fmt(t) }, g);
  }
}
export function axisY(g, scale, x, ticks, fmt, opts = {}) {
  el("line", { class: "ax", x1: x, x2: x, y1: scale.range[0], y2: scale.range[1] }, g);
  for (const t of ticks) {
    const y = scale(t);
    if (opts.grid) el("line", { class: "grid", x1: x, x2: opts.grid, y1: y, y2: y }, g);
    el("text", { x: x - 10, y: y + 4.5, "text-anchor": "end", class: "t3", text: fmt(t) }, g);
  }
}
// annotation: hairline leader + mono label (the only callout style on the page)
export function annot(g, x1, y1, x2, y2, text, cls = "", anchor) {
  el("line", { class: "leader", x1, y1, x2, y2 }, g);
  el("circle", { cx: x1, cy: y1, r: 2.5, class: "t3", fill: "var(--text-3)" }, g);
  const a = anchor || (x2 >= x1 ? "start" : "end");
  const lines = String(text).split("\n");
  lines.forEach((ln, i) => el("text", { x: x2 + (a === "start" ? 6 : a === "end" ? -6 : 0), y: y2 + 4 + i * 17, "text-anchor": a, class: cls, text: ln }, g));
}
export function onVisible(node, cb, opts = { threshold: 0.35 }) {
  if (typeof IntersectionObserver === "undefined") { cb(); return; }
  const io = new IntersectionObserver(es => { for (const e of es) if (e.isIntersecting) { cb(e); io.disconnect(); break; } }, opts);
  io.observe(node);
}
let tipEl;
export function tip(html, ev) {
  if (!tipEl) { tipEl = h("div", { class: "tip", role: "tooltip" }); document.body.appendChild(tipEl); }
  if (html == null) { tipEl.classList.remove("on"); return; }
  tipEl.innerHTML = html; tipEl.classList.add("on");
  const w = tipEl.offsetWidth; let x = ev.clientX + 14, y = ev.clientY + 14;
  if (x + w > innerWidth - 8) x = ev.clientX - w - 14;
  tipEl.style.left = x + "px"; tipEl.style.top = y + "px";
}
export function tabs(container, items, onSelect, initial = 0) {
  const bar = h("div", { class: "tabs", role: "tablist" });
  const btns = items.map((it, i) => h("button", { role: "tab", "aria-selected": String(i === initial), type: "button", onclick: () => select(i) }, it));
  btns.forEach(b => bar.appendChild(b));
  container.prepend(bar);
  function select(i) { btns.forEach((b, j) => b.setAttribute("aria-selected", String(i === j))); onSelect(i); }
  select(initial);
  return select;
}
// simple seeded PRNG (mulberry32) — used only for the decorative star field and the labelled forest demo
export function rng(seed) { let a = seed >>> 0; return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
