import { h, tip, MIN, hhmm, dmon, fmtSci, fmtInt, onVisible, PRM } from "./lib.js";

const COL = { measured: "#5BC8F0", recon: "#2EC4A5", missing: "#FF6B57", ghost: "#8E8A82", text: "#8E8A82" };

export function init(ctx) {
  const root = document.getElementById("fig-count");
  const S = ctx.series, N = S.length;
  const status = p => !isFinite(p.fluxClean) ? "missing" : p.imputed ? "recon" : "measured";

  // ---- build one cell per minute slot, laid out as eight UTC-day plates (rows = hours, columns = minutes) ----
  const W = 1320, perRow = 4, gapX = 46, pw = (W - gapX * (perRow - 1)) / perRow, lab = 24, pitch = (pw - lab) / 60, ph = pitch * 24, rowH = ph + 64;
  const H = Math.ceil(8 / perRow) * rowH + 8;
  const plates = [], cells = [];
  for (let d = 0; d < 8; d++) {
    const ox = (d % perRow) * (pw + gapX) + lab, oy = Math.floor(d / perRow) * rowH + 34, day0 = Date.UTC(2026, 8, 4 + d), pc = new Array(1440).fill(null);
    for (let m = 0; m < 1440; m++) {
      const t = day0 + m * MIN, i = ctx.idx(t);
      let st = null;
      if (i >= 0 && i < N) st = status(S[i]); else if (i === N || i === N + 1) st = "ghost";
      if (!st) continue;
      const c = { x: ox + (m % 60) * pitch + pitch / 2, y: oy + Math.floor(m / 60) * pitch + pitch / 2, st, t, i }; pc[m] = c; cells.push(c);
    }
    plates.push({ ox, oy, day0, pc });
  }
  const tot = { measured: 0, recon: 0, missing: 0 }; cells.forEach(c => { if (tot[c.st] !== undefined) tot[c.st]++; });

  // ---- counters (live while the dots fill in) ----
  const mk = (cls, label) => { const n = h("div", { class: "n" }, "0"); return [h("div", { class: "stat " + cls }, n, h("div", { class: "l" }, label)), n]; };
  const [sRows, nRows] = mk("", "timestamp rows in the file"), [sM, nM] = mk("c-cyan", "direct measurements"), [sR, nR] = mk("c-teal", "reconstructed value"), [sX, nX] = mk("c-coral", "minutes with no value");
  root.append(h("div", { class: "counts" }, sRows, sM, sR, sX));
  const eq = h("p", { class: "note", style: "margin:0 0 16px" }); root.append(eq);

  const canvas = h("canvas", { role: "img", "aria-label": "One dot for every minute of the week, grouped by day" }); root.append(canvas);
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = W * dpr; canvas.height = H * dpr; canvas.style.aspectRatio = `${W} / ${H}`;
  const g = canvas.getContext ? canvas.getContext("2d") : null;
  if (g) g.scale(dpr, dpr);

  const dot = c => {
    if (!g) return;
    g.beginPath();
    if (c.st === "measured") { g.fillStyle = COL.measured; g.globalAlpha = 0.85; g.arc(c.x, c.y, pitch * 0.34, 0, 6.2832); g.fill(); }
    else if (c.st === "recon") { g.globalAlpha = 1; g.fillStyle = COL.recon; g.arc(c.x, c.y, pitch * 0.62, 0, 6.2832); g.fill(); g.beginPath(); g.strokeStyle = COL.recon; g.lineWidth = 1.2; g.arc(c.x, c.y, pitch * 1.5, 0, 6.2832); g.stroke(); }
    else if (c.st === "missing") { g.globalAlpha = 1; g.strokeStyle = COL.missing; g.lineWidth = 0.9; g.arc(c.x, c.y, pitch * 0.34, 0, 6.2832); g.stroke(); }
    else { g.globalAlpha = 0.9; g.setLineDash && g.setLineDash([1.5, 1.5]); g.strokeStyle = COL.ghost; g.lineWidth = 0.9; g.arc(c.x, c.y, pitch * 0.34, 0, 6.2832); g.stroke(); g.setLineDash && g.setLineDash([]); }
    g.globalAlpha = 1;
  };
  const frame = () => {
    if (!g) return;
    g.clearRect(0, 0, W, H); g.font = '12.5px "IBM Plex Mono", monospace'; g.textBaseline = "alphabetic";
    plates.forEach(p => {
      g.fillStyle = "#F3EDE2"; g.font = '19px "Fraunces", Georgia, serif'; g.textAlign = "left";
      g.fillText(`${new Date(p.day0).toLocaleDateString("en-US", { weekday: "short", timeZone: "UTC" })} ${dmon(p.day0)}`, p.ox - lab, p.oy - 12);
      g.font = '12px "IBM Plex Mono", monospace'; g.fillStyle = COL.text; g.textAlign = "right";
      [0, 6, 12, 18].forEach(hr => g.fillText(String(hr).padStart(2, "0"), p.ox - 6, p.oy + hr * pitch + pitch * 0.9));
      g.textAlign = "left";
    });
  };
  frame(); g && g.save();

  let shown = 0;
  const setCounts = n => {
    const c = { measured: 0, recon: 0, missing: 0 };
    for (let i = 0; i < n; i++) if (c[cells[i].st] !== undefined) c[cells[i].st]++;
    const rows = c.measured + c.recon + c.missing;
    nRows.textContent = fmtInt(rows); nM.textContent = fmtInt(c.measured); nR.textContent = fmtInt(c.recon); nX.textContent = fmtInt(c.missing);
    eq.innerHTML = n >= cells.length ? `${fmtInt(c.measured)} measured + ${c.recon} reconstructed + ${fmtInt(c.missing)} empty = <b>${fmtInt(rows)}</b> rows. Usable values: ${fmtInt(c.measured + c.recon)}. A full seven days would be 7 × 24 × 60 = 10,080 slots; the two dashed dots at the end are the slots the file stops short of.` : "";
  };
  const draw = n => { for (; shown < n; shown++) dot(cells[shown]); setCounts(shown); };
  const replay = () => { shown = 0; frame(); const t0 = performance.now(), dur = PRM ? 1 : 3400; const step = now => { const f = Math.min(1, (now - t0) / dur); draw(Math.floor(f * cells.length)); if (f < 1) requestAnimationFrame(step); else draw(cells.length); }; requestAnimationFrame(step); };
  onVisible(canvas, () => (g && typeof requestAnimationFrame !== "undefined") ? replay() : (shown = 0, draw(cells.length)), { threshold: 0.25 });
  if (!g) draw(cells.length);

  root.append(h("div", { class: "legend" },
    h("span", { style: "color:var(--cyan)" }, h("i", { class: "sw dot" }), "measured minute"),
    h("span", { style: "color:var(--teal)" }, h("i", { class: "sw dot" }), "reconstructed (short gap)"),
    h("span", { style: "color:var(--coral)" }, h("i", { class: "sw ring" }), "no value (long gap)"),
    h("span", { style: "color:var(--text-3)" }, h("i", { class: "sw ring" }), "slot beyond the last row"),
    h("button", { class: "btn", type: "button", onclick: replay }, "Replay")));
  root.append(h("figcaption", { class: "cap", html: "<b>One dot per minute.</b> Each plate is one UTC day: rows are hours (top = 00:00), columns are minutes within the hour. The first and last days are partial because the file starts at 13:40 and ends at 13:37." }));

  canvas.addEventListener("mousemove", e => {
    const r = canvas.getBoundingClientRect(), sx = W / r.width, x = (e.clientX - r.left) * sx, y = (e.clientY - r.top) * sx;
    for (const p of plates) {
      const col = Math.floor((x - p.ox) / pitch), row = Math.floor((y - p.oy) / pitch);
      if (col >= 0 && col < 60 && row >= 0 && row < 24) {
        const c = p.pc[row * 60 + col]; if (!c || c.i === undefined) break;
        const txt = { measured: "measured", recon: "reconstructed (was_imputed = TRUE)", missing: "no value, left empty", ghost: "slot past the last row of the file" }[c.st];
        const f = c.i >= 0 && c.i < N && isFinite(S[c.i].fluxClean) ? `<br>flux ${fmtSci(S[c.i].fluxClean, 3)} W/m²` : "";
        return tip(`${dmon(c.t)} ${hhmm(c.t)} UTC<br>${txt}${f}`, e);
      }
    }
    tip(null);
  });
  canvas.addEventListener("mouseleave", () => tip(null));
}
