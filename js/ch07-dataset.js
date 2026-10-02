import { el, h, svgRoot, PRM } from "./lib.js";

export function init(ctx) {
  const ui = document.getElementById("dataset-ui"), root = document.getElementById("fig-dataset");
  const T = ctx.truth, D = T.dataset;
  const cnt = { B: 0, C: 0, M: 0, U: 0 }; ctx.evAll.forEach(e => cnt[e.noaa_class_letter]++);
  const classes = [...Array(cnt.B).fill("B"), ...Array(cnt.C).fill("C"), ...Array(cnt.M).fill("M"), ...Array(cnt.U).fill("U")];   // real counts; schematic assignment
  const W = 1320, H = 470;
  const svg = svgRoot(root, W, H, "svgfig", "115 detected intervals reduced to 31 machine-learning events");
  svg.style.overflow = "visible";
  const R = 11, col = { B: "var(--cyan)", C: "var(--orange)", M: "var(--gold)", U: "var(--text-3)", det: "var(--orange)", link: "var(--gold)", none: "var(--text-3)" };

  // tokens: 80 unlinked, 32 physical, 3 duplicate extras (35 linked rows = 32 + 3)
  const toks = [];
  for (let i = 0; i < 115; i++) toks.push(i < 80 ? { k: "none" } : i < 112 ? { k: "phys", j: i - 80 } : { k: "dup", partner: i - 112 });
  toks.forEach((t, i) => {
    t.g = el("g", { class: "tok" }, svg); t.g.style.transition = PRM ? "none" : "transform .9s cubic-bezier(.2,.7,.2,1), opacity .7s";
    t.c = el("circle", { r: R, "stroke-width": 1.6 }, t.g); t.c.style.transition = PRM ? "none" : "fill .6s, stroke .6s";
    t.t = el("text", { y: 4.5, "text-anchor": "middle", "font-size": 12, fill: "#05070F", opacity: 0, text: "" }, t.g); t.t.style.fontWeight = "600"; t.t.style.transition = "opacity .6s";
  });
  const physClass = j => classes[j];
  const gridPos = (n, x0, y0, cols, pitch) => ({ x: x0 + (n % cols) * pitch, y: y0 + Math.floor(n / cols) * pitch });
  const groups = {};
  function layout(s) {
    const pos = new Array(115);
    toks.forEach((t, i) => {
      let p, o = 1, fill = "none", stroke = col.det, txt = "", s2 = 1;
      if (s === 0) { p = gridPos(i, 176, 120, 23, 44); fill = "none"; stroke = col.det; }
      else if (s === 1) {
        if (t.k === "none") { p = gridPos(i, 70, 150, 12, 27); o = 0.28; stroke = col.none; }
        else { const n = i - 80; p = gridPos(n, 640, 140, 7, 48); fill = col.link; stroke = col.link; }
      } else if (s === 2) {
        if (t.k === "none") { p = gridPos(i, 70, 150, 12, 27); o = 0.1; stroke = col.none; }
        else if (t.k === "dup") { const q = gridPos(t.partner, 640, 140, 7, 48); p = q; o = 0; fill = col.link; stroke = col.link; }
        else { p = gridPos(t.j, 640, 140, 7, 48); fill = col.link; stroke = col.link; }
      } else {
        if (t.k === "none") { p = gridPos(i, 70, 150, 12, 27); o = 0; stroke = col.none; }
        else if (t.k === "dup") { p = gridPos(t.partner, 640, 140, 7, 48); o = 0; }
        else {
          const c = physClass(t.j); const idx = classes.slice(0, t.j).filter(x => x === c).length;
          if (s >= 5 && (c === "C" || c === "M")) { const n = classes.slice(0, t.j).filter(x => x === "C" || x === "M").length; p = gridPos(n, 640, 150, 6, 48); fill = col.C; stroke = col.C; txt = "C+"; }
          else { const gx = { B: 130, C: 470, M: 960, U: 1120 }[c], cols = c === "B" ? 5 : c === "C" ? 6 : 1; p = gridPos(idx, s >= 5 && c === "B" ? 190 : gx, 150, cols, 48); fill = col[c]; stroke = col[c]; txt = c; }
          if (s === 4 && c === "U") { o = 0; s2 = 0.2; }
          if (s >= 4 && c === "U") { o = 0; s2 = 0.2; }
        }
      }
      pos[i] = { p, o, fill, stroke, txt, s2 };
    });
    return pos;
  }
  const labels = el("g", {}, svg);
  const LAB = [
    [{ x: 176, y: 70, big: "115", txt: "detected intervals" }],
    [{ x: 70, y: 110, big: "80", txt: "no NOAA record: no known class" }, { x: 640, y: 110, big: "35", txt: "NOAA-linked rows" }],
    [{ x: 70, y: 110, big: "80", txt: "set aside (no label)", dim: 1 }, { x: 640, y: 110, big: "32", txt: "independent physical events" }],
    [{ x: 130, y: 110, big: "13", txt: "B", c: "cyan" }, { x: 470, y: 110, big: "17", txt: "C", c: "orange" }, { x: 960, y: 110, big: "1", txt: "M", c: "gold" }, { x: 1120, y: 110, big: "1", txt: "U (unspecified)", c: "t3" }],
    [{ x: 130, y: 110, big: "13", txt: "B", c: "cyan" }, { x: 470, y: 110, big: "17", txt: "C", c: "orange" }, { x: 960, y: 110, big: "1", txt: "M", c: "gold" }, { x: 1120, y: 110, big: "—", txt: "U removed", c: "t3" }, { x: 640, y: 400, big: "31", txt: "events with a usable label", c: "t1" }],
    [{ x: 190, y: 110, big: "13", txt: "B", c: "cyan" }, { x: 640, y: 110, big: "18", txt: "C+  (C or M)", c: "orange" }, { x: 640, y: 420, big: "31", txt: "events: 13 B + 18 C+", c: "t1" }]
  ];
  const CAP = [
    "Every dot is one interval the detector reported over the week.",
    "Only intervals linked to a NOAA record can carry a class label. 35 rows are linked; the 80 others set aside.",
    "Three NOAA flares appear twice, as two detector intervals each. One physical flare counts once: 35 rows become 32 independent physical events.",
    "NOAA’s class decides each label: B 13, C 17, M 1, and one event with an unspecified class, U.",
    "U cannot be used as a B or C+ example, so it is removed.",
    "The target is B versus C+. C and M are combined as C+ (17 + 1 = 18)."
  ];
  const cap = h("p", { class: "note", style: "min-height:3.2em;margin-top:8px" }); const step = h("span", { class: "k", style: "font-family:var(--mono);font-size:13px;color:var(--text-3)" });
  let s = 0, timer = null;
  function apply(first) {
    const pos = layout(s);
    toks.forEach((t, i) => {
      const q = pos[i];
      t.g.style.transform = `translate(${q.p.x}px,${q.p.y}px) scale(${q.s2})`; t.g.style.opacity = q.o;
      t.c.style.fill = q.fill; t.c.style.stroke = q.stroke; t.t.textContent = q.txt; t.t.style.opacity = q.txt ? 1 : 0;
      t.t.setAttribute("font-size", q.txt === "C+" ? 11 : 12);
    });
    labels.replaceChildren();
    LAB[s].forEach(L => { el("text", { x: L.x, y: L.y, class: "big " + (L.c ? "c-" + L.c : ""), style: "stroke:none", text: L.big }, labels); labels.lastChild.style.fill = L.c === "cyan" ? "var(--cyan)" : L.c === "orange" ? "var(--orange)" : L.c === "gold" ? "var(--gold)" : L.c === "t3" ? "var(--text-3)" : "var(--text-1)"; if (L.dim) labels.lastChild.setAttribute("opacity", 0.5); el("text", { x: L.x + (String(L.big).length * 26 + 12), y: L.y - 4, class: L.dim ? "t3" : "t1", text: L.txt }, labels); });
    cap.textContent = CAP[s]; step.textContent = `Step ${s + 1} of 6`;
    back.disabled = s === 0; next.disabled = s === 5;
  }
  const back = h("button", { class: "btn", type: "button", onclick: () => { stop(); s = Math.max(0, s - 1); apply(); } }, "Back");
  const next = h("button", { class: "btn", type: "button", onclick: () => { stop(); s = Math.min(5, s + 1); apply(); } }, "Next step");
  const auto = h("button", { class: "btn", type: "button", onclick: () => { if (timer) return stop(); s = 0; apply(); auto.textContent = "Pause"; timer = setInterval(() => { if (s >= 5) return stop(); s++; apply(); }, PRM ? 300 : 2600); } }, "Play");
  function stop() { if (timer) { clearInterval(timer); timer = null; } auto.textContent = "Play"; }
  ui.append(h("div", { class: "ctl" }, back, next, auto, step), cap);
  apply();
  root.append(h("figcaption", { class: "cap", html: "<b>Counts are real</b> (115 intervals, 35 NOAA-linked rows, 32 physical events, B 13 / C 17 / M 1 / U 1, final 13 B + 18 C+). Dot positions are schematic." }));
  if (!root.__dsInit) root.__dsInit = true;
}
