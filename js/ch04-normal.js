import { el, h, svgRoot, lin, axisX, axisY, annot, hhmm, f3, linePath, mean, sd, median, mad, tabs, MIN, PRM } from "./lib.js";

export const SCALE = 1.4826;

export function init(ctx) {
  const ui = document.getElementById("normal-ui"), root = document.getElementById("fig-normal");
  const C0 = Date.UTC(2026, 8, 4, 19, 4), CMIN = Date.UTC(2026, 8, 4, 18, 34), CMAX = Date.UTC(2026, 8, 4, 19, 40);
  let c = C0, step = 0, timer = null;
  const showMM = () => true, showSpread = () => step >= 1;

  const stepsBar = h("div", {}); ui.append(stepsBar);
  const ctl = h("div", { class: "ctl" });
  const slider = h("input", { type: "range", min: 0, max: (CMAX - CMIN) / MIN, value: (C0 - CMIN) / MIN, "aria-label": "Move the 30-minute window along the signal" });
  const play = h("button", { class: "btn", type: "button" }, "Play");
  const reset = h("button", { class: "btn", type: "button" }, "Back to 19:04");
  ctl.append(h("span", {}, "Move the window:"), slider, play, reset); ui.append(ctl);
  const read = h("div", { class: "readout" }); ui.append(read);

  const W = 1320, H = 440, m = { l: 96, r: 30, t: 28, b: 48 };
  const svg = svgRoot(root, W, H, "svgfig", "A 30-minute baseline window with mean, median, SD and MAD");
  const g = el("g", {}, svg);
  root.append(h("div", { class: "legend", html: `<span style="color:var(--cyan)"><i class="sw"></i>mean</span><span style="color:var(--teal)"><i class="sw dash"></i>median</span><span style="color:var(--cyan)"><i class="sw dot"></i>last 30 minutes</span><span style="color:var(--orange)"><i class="sw ring"></i>current minute (kept out of its own baseline)</span>` }));
  root.append(h("figcaption", { class: "cap", html: "<b>Real XRS-B data, 4 September.</b> The vertical axis re-zooms to the window so the small spreads are visible; read the numbers above the figure." }));

  function stats(cc) {
    const i = ctx.idx(cc), win = [];
    for (let k = i - 30; k < i; k++) win.push(ctx.series[k].logC);
    const mu = mean(win), s = sd(win), med = median(win), md = mad(win);
    return { win, mu, s, med, md, mds: md * SCALE, cur: ctx.series[i].logC, i };
  }
  function render() {
    g.replaceChildren();
    const st = stats(c), x0 = c - 34 * MIN, x1 = c + 6 * MIN;
    const view = []; for (let t = x0; t <= x1; t += MIN) view.push(ctx.at(t));
    const vals = [...st.win, st.cur, ...view.filter(p => p.t <= c).map(p => p.logC)];
    const spreadLo = Math.min(st.mu - st.s, st.med - st.mds), spreadHi = Math.max(st.mu + st.s, st.med + st.mds);
    let lo = Math.min(...vals, step >= 1 ? spreadLo : 1e9), hi = Math.max(...vals, step >= 1 ? spreadHi : -1e9);
    const pad = Math.max((hi - lo) * 0.18, 0.004); lo -= pad; hi += pad;
    const x = lin(x0, x1, m.l, W - m.r), y = lin(lo, hi, H - m.b, m.t);
    const tickStep = (hi - lo) > 0.4 ? 0.2 : (hi - lo) > 0.1 ? 0.05 : (hi - lo) > 0.04 ? 0.01 : 0.005;
    const yt = []; for (let v = Math.ceil(lo / tickStep) * tickStep; v <= hi; v += tickStep) yt.push(+v.toFixed(4));
    axisY(g, y, m.l, yt, v => f3(v), { grid: W - m.r });
    const xt = []; for (let t = Math.ceil(x0 / (5 * MIN)) * 5 * MIN; t <= x1; t += 5 * MIN) xt.push(t);
    axisX(g, x, H - m.b, xt, hhmm);
    el("text", { x: m.l, y: 16, class: "t3", text: "log10 flux" }, g);
    // window shading
    const wa = c - 30 * MIN, wb = c - MIN;
    el("rect", { x: x(wa) - 6, y: m.t, width: x(wb) - x(wa) + 12, height: H - m.b - m.t, fill: "var(--cyan)", opacity: 0.045 }, g);
    el("text", { x: x(wa) - 2, y: m.t + 14, class: "t3", text: "trailing 30 minutes" }, g);
    // spread bands
    if (showSpread()) {
      el("rect", { x: x(wa) - 6, y: y(st.mu + st.s), width: x(wb) - x(wa) + 12, height: Math.max(1, y(st.mu - st.s) - y(st.mu + st.s)), fill: "var(--cyan)", opacity: 0.16 }, g);
      el("rect", { x: x(wa) - 6, y: y(st.med + st.mds), width: x(wb) - x(wa) + 12, height: Math.max(1, y(st.med - st.mds) - y(st.med + st.mds)), fill: "none", stroke: "var(--teal)", "stroke-dasharray": "5 4", "stroke-width": 1.4 }, g);
    }
    // series
    el("path", { d: linePath(view.map(p => ({ x: p.t, y: p.t <= c ? p.logC : NaN })), x, y), fill: "none", stroke: "var(--cyan)", "stroke-width": 1.2, opacity: 0.55 }, g);
    view.forEach(p => { if (p.t > c) return; const inW = p.t >= wa && p.t <= wb; if (p.t === c) return; el("circle", { cx: x(p.t), cy: y(p.logC), r: inW ? 4 : 2.8, class: "c-cyan", opacity: inW ? 1 : 0.4 }, g); });
    el("circle", { cx: x(c), cy: y(st.cur), r: 7, fill: "none", stroke: "var(--orange)", "stroke-width": 2.2, class: "glow" }, g);
    // mean + median
    const xa = x(wa) - 6, xb = x(wb) + 6;
    el("line", { x1: xa, x2: xb, y1: y(st.mu), y2: y(st.mu), stroke: "var(--cyan)", "stroke-width": 2.4 }, g);
    el("line", { x1: xa, x2: xb, y1: y(st.med), y2: y(st.med), stroke: "var(--teal)", "stroke-width": 2.4, "stroke-dasharray": "7 5" }, g);
    const sep = Math.abs(y(st.mu) - y(st.med));
    el("text", { x: xb + 10, y: y(st.mu) + (st.mu >= st.med ? -4 : 14), class: "c-cyan", text: "mean" }, g);
    el("text", { x: xb + 10, y: y(st.med) + (st.mu >= st.med ? 14 : -4), class: "c-teal", text: "median" }, g);
    el("text", { x: x(c) + 12, y: y(st.cur) - 10, class: "c-orange", text: `${hhmm(c)} current` }, g);
    // readout
    read.replaceChildren(
      h("div", { class: "cy" }, "mean", h("b", {}, f3(st.mu))), h("div", { class: "tl" }, "median", h("b", {}, f3(st.med))),
      ...(showSpread() ? [h("div", { class: "cy" }, "SD", h("b", {}, st.s.toFixed(4))), h("div", { class: "tl" }, "MAD", h("b", {}, st.md.toFixed(4))), h("div", { class: "tl" }, "MAD × 1.4826", h("b", {}, st.mds.toFixed(4)))] : []),
      h("div", {}, "mean − median", h("b", {}, (st.mu - st.med >= 0 ? "+" : "−") + Math.abs(st.mu - st.med).toFixed(4))));
  }

  const setStep = i => {
    step = i; ctl.style.display = i === 2 ? "" : "none";
    if (i < 2) { stop(); c = C0; slider.value = (C0 - CMIN) / MIN; }
    ui.querySelector(".qline")?.remove();
    const q = ["Where is the recent background centered?", "How much does it normally vary?", "Does the baseline hold still when a flare arrives?"][i];
    stepsBar.querySelector(".tabs").after(h("p", { class: "ch-q qline", style: "margin:12px 0 8px;font-size:24px" }, q));
    render();
  };
  tabs(stepsBar, ["1  Center", "2  Spread", "3  Move the window"], setStep, 0);

  slider.addEventListener("input", () => { stop(); c = CMIN + slider.value * MIN; render(); });
  function stop() { if (timer) { clearInterval(timer); timer = null; play.textContent = "Play"; } }
  play.addEventListener("click", () => {
    if (timer) return stop();
    play.textContent = "Pause"; if (c >= CMAX) c = CMIN;
    timer = setInterval(() => { c += MIN; if (c > CMAX) { c = CMAX; stop(); } slider.value = (c - CMIN) / MIN; render(); }, PRM ? 50 : 260);
  });
  reset.addEventListener("click", () => { stop(); c = C0; slider.value = (C0 - CMIN) / MIN; render(); });
}
