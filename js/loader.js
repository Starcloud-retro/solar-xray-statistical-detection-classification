// One shared data loader. Every numeric figure on the page reads from here.
import { utc, MIN } from "./lib.js";

function parseCSV(text) {
  const lines = text.replace(/\r/g, "").split("\n").filter(Boolean);
  const head = lines[0].split(",");
  return lines.slice(1).map(l => { const c = l.split(","); const o = {}; head.forEach((k, i) => o[k] = c[i]); return o; });
}
const num = v => (v === "" || v === undefined || v === "NA" ? NaN : +v);
const bool = v => v === "True" || v === "TRUE" || v === "true";
const getJSON = u => fetch(u).then(r => { if (!r.ok) throw new Error(u + " " + r.status); return r.json(); });
const getText = u => fetch(u).then(r => { if (!r.ok) throw new Error(u + " " + r.status); return r.text(); });

export const PREDICTORS = ["rise_slope", "max_roc", "mean_pos_roc", "rise_duration_min", "bg_flux"];

export async function loadAll() {
  const [csv, evCsv, truth, noaa, detect, vifT, corrT, cmpT, lrT] = await Promise.all([
    getText("data/goes_xrs_cleaned.csv"), getText("data/labeled_events_deduplicated.csv"),
    getJSON("data/derived/ground_truth.json"), getJSON("data/derived/noaa_alignment.json"), getJSON("data/derived/detection_window.json"),
    getText("data/derived/STAGE8_TRAIN_VIF_CURRENT.csv"), getText("data/derived/STAGE8_TRAIN_CORRELATION_CURRENT.csv"),
    getText("data/derived/STAGE8_MODEL_COMPARISON.csv"), getText("data/derived/STAGE8_LOGISTIC_INDEPENDENT_DIAGNOSTIC.csv")
  ]);

  // ---- stacked CSV: keep the first rows of BOTH channels for the explainer, then FILTER to XRS-B ----
  const all = parseCSV(csv);
  const stackedHead = all.slice(0, 2).concat(all.filter(r => r.time_tag === all[0].time_tag && r.energy !== all[0].energy).slice(0, 1));
  const rows = all.filter(r => r.energy === truth.data.channel);            // energy == "0.1-0.8nm"
  const series = rows.map(r => ({
    t: utc(r.time_tag), tag: r.time_tag, sat: num(r.satellite),
    flux: num(r.flux), fluxClean: num(r.flux_clean), log: num(r.log10_flux), logC: num(r.log10_flux_clean),
    imputed: bool(r.was_imputed), longGap: bool(r.is_long_gap), missingRaw: bool(r.is_missing_raw), seg: num(r.segment_id), energy: r.energy
  }));
  const t0 = series[0].t;
  const idx = ms => Math.round((ms - t0) / MIN);
  const at = ms => series[idx(ms)];

  // ---- events ----
  const evAll = parseCSV(evCsv).map(r => {
    const o = { ...r };
    for (const k of Object.keys(r)) if (!["event_id","start_time","peak_time","end_time","has_interpolated_points","noaa_event_id","noaa_class_letter","noaa_class"].includes(k)) o[k] = num(r[k]);
    o.start = utc(r.start_time); o.peak = utc(r.peak_time); o.end = utc(r.end_time);
    o.group = r.noaa_class_letter === "B" ? "B" : (r.noaa_class_letter === "U" ? "U" : "C+");
    return o;
  }).sort((a, b) => a.peak - b.peak);
  const ml = evAll.filter(e => e.noaa_class_letter !== "U");
  ml.forEach((e, i) => { e.i = i; e.y = e.group === "C+" ? 1 : 0; e.partition = i < 18 ? "Train" : i < 24 ? "Development" : "Final test"; });
  const train = ml.filter(e => e.partition === "Train");
  const stats = {};
  for (const p of PREDICTORS) { const v = train.map(e => e[p]); const m = v.reduce((a, b) => a + b, 0) / v.length; stats[p] = { mean: m, sd: Math.sqrt(v.reduce((a, b) => a + (b - m) ** 2, 0) / (v.length - 1)) }; }

  const vif = parseCSV(vifT).map(r => ({ p: r.Predictor, v: +r.VIF }));
  const corrRows = corrT.replace(/\r/g, "").trim().split("\n"); const ch = corrRows[0].split(",").slice(1);
  const corr = {}; corrRows.slice(1).forEach(l => { const c = l.split(","); corr[c[0]] = {}; ch.forEach((k, i) => corr[c[0]][k] = +c[i + 1]); });
  const models = parseCSV(cmpT);
  const lr = parseCSV(lrT).map(r => ({ term: r.Term, coef: +r.Coefficient, se: +r.Std_Error }));

  return { series, t0, idx, at, stackedHead, evAll, ml, train, stats, truth, noaa, detect, vif, corr, models, lr };
}
