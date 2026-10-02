# Solar activity from X-ray data: research website

A static, single-page research story. No build step, no iframes, no CDN: fonts are bundled.

    cd solar-site
    python3 -m http.server 8000      # then open http://localhost:8000

(Opening index.html straight from disk will not work: the page loads its data with fetch().)

## Layout
- `index.html`: the single page and all chapter copy
- `css/tokens.css` (colours, type, spacing) → `base.css` (components) → `chapters.css` (chapter-specific)
- `js/loader.js`: the one shared data loader. It filters the stacked CSV to `energy == "0.1-0.8nm"`
- `js/lib.js`: SVG/scale/tooltip helpers. `js/ch00…ch10-*.js`: one module per chapter. `js/presentation.js`: slide gallery hook
- `data/`: `goes_xrs_cleaned.csv`, `labeled_events_deduplicated.csv`, `derived/` (see below)
- `tests/validate.mjs` (static checks, no dependencies) and `tests/smoke.mjs` (needs `npm i jsdom`; runs every chapter against the data)

## Where every number comes from
| Figure | Source |
|---|---|
| Observe, Count, Prepare, Normal, features curves, hero trace | `goes_xrs_cleaned.csv`, computed in the browser |
| Event table, split, scatterplots, r values | `labeled_events_deduplicated.csv` (r recomputed from the 18 training events) |
| NOAA aggregate and matched list | `derived/noaa_alignment.json` (from the v5 reference; one bare `NaN` replaced with `null` so it is valid JSON) |
| Detector minute-by-minute values 18:58–19:12 | `derived/detection_window.json` (v5 reference) |
| Dev/LOOCV metrics, correlations, VIF, counts | `derived/ground_truth.json` (hand-transcribed from SCIENTIFIC_GROUND_TRUTH.md) and the `STAGE8_*.csv` copies |
| Logistic weights (mechanics demo only) | `derived/STAGE8_LOGISTIC_INDEPENDENT_DIAGNOSTIC.csv` |

## Known limits
- The 115 detector intervals are not in the supplied data, so the 80 unmatched detections and 3 missed NOAA records appear as counts only, and the week timeline shows the 32 matched events.
- Decision Tree and Random Forest panels are live illustrations built from the 18 training events, labelled as such; the project's fitted trees/forest were not supplied.
- Per-event LOOCV predictions were not supplied; only the aggregate is shown.
- Presentation: `assets/presentation/` holds the 20 slides of Solar_Activity.pptx as JPGs (rendered with LibreOffice, so fonts and the left-edge banner can differ slightly from PowerPoint), 520px thumbnails, and the original .pptx for download (it includes the presenter notes). Slide titles live in `js/presentation.js`; to update, re-render the deck to `slide-NN.jpg`.
