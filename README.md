# Solar activity from X-ray data: research website

A static, single-page research story. No build step, no iframes, no CDN: fonts are bundled.

    cd solar-xray-statistical-detection-classification
    python3 -m http.server 8000      # then open http://localhost:8000

(Opening index.html straight from disk will not work: the page loads its data with fetch().)

## Vercel deployment

Deploy this repository's `main` branch with Root Directory left empty (repository
root) and Framework Preset `Other`. Use an empty Build Command and Install Command,
and Output Directory `.`. `vercel.json` pins these settings; no build or dependency
installation is needed. Do not select `components/`, `public/`, or `dist/` as the root
or output directory.

Keep `data/` and `assets/` in the deployment: the browser fetches the CSV/JSON and
loads the slides and fonts directly. `.gitignore` only excludes raw JSON under
`data/raw/`; `.vercelignore` must not exclude the runtime data. Recreating a Vercel
project does not repair an exclusion in the source repository.

Run `node tests/validate.mjs` and `node tests/deployment.mjs` before deploying.
After deployment, check `/`, `/data/goes_xrs_cleaned.csv`,
`/data/derived/ground_truth.json`, `/assets/presentation/`,
`/assets/presentation/slide-01.jpg`, `/assets/presentation/Solar_Activity.pptx`,
and `/assets/fonts/fraunces-latin-opsz-normal.woff2`. Follow redirects when checking
the presentation directory: `trailingSlash: false` normalizes its URL. Its static
index links to the existing gallery and downloads without needing directory listing.
These files use standard static MIME types (`text/csv`, `application/json`,
`image/jpeg`, `application/vnd.openxmlformats-officedocument.presentationml.presentation`,
and `font/woff2`; `font/woff` for any future WOFF files). No catch-all rewrite or
custom MIME headers are needed.

Use the current production domain shown under Vercel Project Settings → Domains.
A URL returning `DEPLOYMENT_NOT_FOUND` is obsolete; redeploying the source will
not restore that URL automatically. Deployment-specific URLs may redirect to
Vercel authentication. A final HTTP 200 from the login page is not a successful
asset check: verify the final URL, MIME type, and response body. For a public
research website, ensure the production domain is accessible without login.

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
