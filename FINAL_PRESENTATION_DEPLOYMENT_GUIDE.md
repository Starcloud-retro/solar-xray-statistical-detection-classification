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

Expected changes include:
- `index.html`
- `styles.css`
- `app.R`
- `.vercelignore`
- `README.md`
- deletion of `requirements.txt`
- addition of `requirements-python.txt`

## Step 6 — Commit
```powershell
git add .
git commit -m "Final presentation polish: guided website and Shiny GUI"
```

## Step 7 — Push
```powershell
git push
```

## Step 8 — Vercel
The GitHub push should trigger a deployment automatically.

Vercel settings:
- Framework Preset: `Other`
- Root Directory: `./`
- Build Command: leave blank/default
- Output Directory: leave blank/default
- Install Command: leave blank/default

The Python dependency file is intentionally named `requirements-python.txt`, not `requirements.txt`, so Vercel does not mis-detect the static site as a Python app.

## Step 9 — Verify the public site
Open the Vercel URL in an incognito/private window and verify:
- page loads
- figures load
- GitHub button works
- no Python entrypoint error

## What changed
### Website
The website now follows the exact scientific sequence of the final PPT:
Sun → GOES → preprocessing → normal → Z/robust Z/ROC → event → NOAA → features → leakage → ML → results → limitations → Shiny.

### Shiny
Only presentation/explanation styling was changed. The frozen scientific methodology, data, predictors, detector, split, models and results were not changed.
