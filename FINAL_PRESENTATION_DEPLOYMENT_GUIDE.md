# Final Presentation + Deployment Instructions

## Presentation order
1. PowerPoint = main academic presentation.
2. R Shiny = 60–120 second live demo after the conclusion.
3. Vercel = public project page; show the link/QR, do not re-present all sections.
4. GitHub = source code and frozen artifacts.

## Recommended Shiny live-demo path
Explore GOES Data → What Is Normal? → Detect an Unusual Event → Describe the Event → Can We Classify It? → Test the Experiment.

Use this sentence:
“The slides explained the reasoning; this Shiny interface lets us inspect the same frozen pipeline on the actual project data.”

## Step 1 — Backup
```powershell
Copy-Item -Recurse C:\Users\zahee\Documents\SML C:\Users\zahee\Documents\SML_BACKUP_FINAL
```

## Step 2 — Extract the supplied ZIP
Extract `solar-activity-sml-presentation-final.zip`, then copy all extracted contents into:
`C:\Users\zahee\Documents\SML`

Choose **Replace files in the destination**.

## Step 3 — Test the website
```powershell
cd C:\Users\zahee\Documents\SML
python -m http.server 8000
```
Open `http://localhost:8000`.
Stop with `Ctrl+C`.

## Step 4 — Test Shiny
```powershell
Rscript -e "shiny::runApp('.', launch.browser=TRUE)"
```

If required, install R packages once:
```r
install.packages(c("shiny","jsonlite","rpart","randomForest"))
```

## Step 5 — Check Git
```powershell
git status
```

For the static deployment fix, expected changes are:
- `.vercelignore`
- `vercel.json`
- `README.md`
- `FINAL_PRESENTATION_DEPLOYMENT_GUIDE.md`
- addition of `assets/presentation/index.html`
- addition of `tests/deployment.mjs`

## Step 6 — Commit
```powershell
git add .vercelignore vercel.json README.md FINAL_PRESENTATION_DEPLOYMENT_GUIDE.md assets/presentation/index.html tests/deployment.mjs
git commit -m "Fix root static deployment and include runtime data"
```

## Step 7 — Push
```powershell
git push origin main
```

## Step 8 — Vercel
The GitHub push should trigger a deployment automatically.

Vercel settings:
- Framework Preset: `Other`
- Root Directory: leave empty (repository root)
- Production Branch: `main`
- Build Command: override with an empty value
- Output Directory: `.`
- Install Command: override with an empty value

`vercel.json` pins the framework, build, install, and output settings for this
static website. Python and R files are research sources; no server runtime or
dependency installation is needed. Keep `data/` and `assets/` in the deployment;
excluding `data/` in `.vercelignore` breaks the browser's CSV/JSON requests even
when those files are committed to Git.

## Step 9 — Verify the public site
Open the Vercel URL in an incognito/private window and verify:
- page loads
- figures load
- GitHub button works
- no Python entrypoint error
- `/data/goes_xrs_cleaned.csv` and `/data/derived/ground_truth.json` return HTTP 200
- `/assets/presentation/` returns HTTP 200 after following redirects
- `/assets/presentation/slide-01.jpg` and `/assets/presentation/Solar_Activity.pptx` return HTTP 200
- `/assets/fonts/fraunces-latin-opsz-normal.woff2` returns HTTP 200

Before pushing, run `node tests/validate.mjs` and `node tests/deployment.mjs`.

## What changed
### Website
The website now follows the exact scientific sequence of the final PPT:
Sun → GOES → preprocessing → normal → Z/robust Z/ROC → event → NOAA → features → leakage → ML → results → limitations → Shiny.

### Shiny
Only presentation/explanation styling was changed. The frozen scientific methodology, data, predictors, detector, split, models and results were not changed.
