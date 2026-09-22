# Statistical Detection and Classification of Solar Activity Using Real-Time X-Ray Time-Series Data

**Statistics for Machine Learning (SML) — Problem-Based Learning Project**  
**Department of CSE (AI & ML), Geethanjali College of Engineering and Technology**

## Project team

| Roll No. | Name |
|---|---|
| 24R11A6670 | Metri Naveen Kumar |
| 24R11A6690 | Shaik Zaheer Abbas |
| 24R11A6687 | Sahit Kumar Yadav |
| 25R15A6610 | A. Sai Eshwar |

---

## What this project does

This project studies **GOES soft X-ray time-series data** using classical statistics and
machine learning.

The scientific workflow is:

**GOES X-rays → cleaning → rolling statistics → anomaly detection → event segmentation →
NOAA alignment → event features → leakage-controlled B vs C+ classification → evaluation →
R Shiny presentation GUI**

The project deliberately separates three ideas:

- **Detection:** did statistically unusual flare-like activity occur?
- **Severity nowcasting:** at the observed peak, is the event **B** or **C+**?
- **Forecasting:** will a flare occur in the future?

This repository performs the first two. It is **not a flare-forecasting system**.

### Frozen Stage 8 task

- Prediction time: `t_pred = t_peak`
- Target: `B` versus `C+`
- `C+` combines NOAA `C` and `M`
- Undefined `U` events are excluded
- Independent ML events: **31**
- Class distribution: **13 B / 18 C+**
- Chronological split: **18 train / 6 development / 7 final test**

Primary predictors:

1. `rise_slope`
2. `max_roc`
3. `mean_pos_roc`
4. `rise_duration_min`
5. `bg_flux`

`peak_flux` is **not** a primary predictor because NOAA flare class is defined from peak
0.1–0.8 nm X-ray flux.

---

## Repository structure

```text
solar-activity-sml-final/
├── README.md                       # Repository overview, run/deploy instructions
├── PROJECT_WALKTHROUGH.md          # Detailed viva + file-by-file explanation
├── FINAL_RESULTS.md                # Frozen scientific results and limitations
├── app.R                           # 9-tab presentation-only R Shiny GUI
├── index.html                      # Static portfolio page for Vercel / GitHub Pages
├── styles.css                      # Static-site styling
├── vercel.json                     # Vercel static-site configuration
├── .vercelignore                   # Keeps scientific source/data out of web deployment
├── .nojekyll                       # Lets GitHub Pages serve the static files directly
├── .gitignore
├── requirements.txt                # Python reference-environment dependencies
│
├── R/
│   ├── 01_stats_primitives.R       # First-principles statistical primitives
│   ├── 02_preprocessing.R          # Cleaning and gap provenance
│   ├── 03_rolling_statistics.R     # Rolling mean/median/SD/MAD, ROC, slope
│   ├── 04_event_detection.R        # Anomaly rules, persistence, segmentation
│   ├── 05_noaa_alignment.R         # Official NOAA event matching
│   ├── 06_feature_engineering.R    # Event features + START→PEAK temporal safeguards
│   ├── 07_ml_models.R              # Frozen Stage 8 ML and validation logic
│   ├── 08_evaluation.R             # Classification evaluation helpers
│   ├── 09_visualizations.R         # Scientific plots
│   ├── run_stage8_ml.R             # Authoritative Stage 8 runner
│   └── run_stage8_robustness_audit.R
│
├── src/                            # Python reference / data-preparation implementation
├── tests/                          # Statistical, NOAA-alignment and ML-dataset checks
├── data/
│   ├── raw/README.md               # NOAA provenance; duplicate raw downloads removed
│   └── processed/                  # Frozen processed data used for presentation
└── reports/
    ├── STAGE8_MODEL_COMPARISON.csv
    ├── STAGE8_TRAIN_CORRELATION_CURRENT.csv
    ├── STAGE8_TRAIN_VIF_CURRENT.csv
    ├── STAGE8_FEATURE_DISTRIBUTIONS.csv
    ├── STAGE8_FEATURE_EFFECTS.csv
    └── figures/                    # Final scientific plots used in report/PPT/website
```

Development-only status reports, repeated audit markdowns, Python bytecode caches,
timestamped duplicate raw downloads, old demo wrappers, and duplicate robustness figures
have been removed from this presentation repository.

---

## Mathematics used

The project does not hide the statistical foundation behind a single black-box package.

### Arithmetic mean

`mean = sum(x_i) / n`

Used to describe the local average X-ray background.

### Sample variance and standard deviation

`variance = sum((x_i - mean)^2) / (n - 1)`  
`SD = sqrt(variance)`

Used to describe ordinary background variability.

### Median and Median Absolute Deviation

`MAD_raw = median(|x_i - median(x)|)`  
`MAD_scaled = 1.4826 × MAD_raw`

Used as a robust alternative when flare spikes distort ordinary mean/SD.

### Rolling statistics

At time `t`, the uncontaminated baseline uses observations before `t`, not the current
observation itself. This prevents a flare point from normalizing itself.

### Standard anomaly score

`z = (x - rolling_mean) / rolling_SD`

### Robust anomaly score

`z_robust = (x - rolling_median) / rolling_MAD_scaled`

These are **anomaly scores**, not formal p-value-based hypothesis tests.

### Rate of change

`ROC_t = log10(flux_t) - log10(flux_(t-1))`

Used to detect rapid changes in the X-ray signal.

### Local slope

A short trailing linear fit estimates the direction and steepness of change.

### ML metrics

- Precision = `TP / (TP + FP)`
- Recall = `TP / (TP + FN)`
- F1 = harmonic mean of Precision and Recall
- Balanced Accuracy = `(Sensitivity + Specificity) / 2`
- Macro F1 = average of the B-class and C+-class F1 scores

See `PROJECT_WALKTHROUGH.md` for the full explanation and code mapping.

---

## R implementation: what was actually done

The R implementation **does use functions**, but the statistical primitives are written
transparently rather than delegated to black-box statistical calls.

For example, `R/01_stats_primitives.R` defines our own:

- `calculate_mean()`
- `calculate_median()`
- `calculate_variance()`
- `calculate_std()`
- `calculate_quantile()`
- `calculate_iqr()`
- `calculate_mad_raw()`
- `calculate_mad_scaled()`
- `calculate_cv()`

The functions operate on numeric vectors using loops, sorting, indexing and explicit
arithmetic. They are wrapped as functions so the same verified logic can be reused.

For machine learning, standard R model implementations are appropriate:

- Logistic Regression: base R `glm(..., family = binomial(link="logit"))`
- Decision Tree: `rpart`
- Random Forest: `randomForest`

The scientific contribution is therefore not “reimplementing Random Forest from scratch.”
It is the **leakage-controlled construction of the event dataset, correct prediction-time
boundary, transparent features, chronological evaluation, and honest diagnostics**.

---

## Frozen Stage 8 results

### Development set — 6 events

| Model | Accuracy | Macro F1 | Balanced Accuracy |
|---|---:|---:|---:|
| Logistic Regression | 1.0000 | 1.0000 | 1.0000 |
| Decision Tree | 0.8333 | 0.7778 | 0.9000 |
| Random Forest | 0.8333 | 0.7778 | 0.9000 |

The predefined development procedure froze Logistic Regression for the final test.

### Final chronological test — 7 events

Observed confusion matrix:

| Actual \ Predicted | B | C+ |
|---|---:|---:|
| B | 5 | 0 |
| C+ | 0 | 2 |

Observed result: **7/7 correct in this specific holdout**.

This does **not** establish generalization because the final test contains only seven events.

### Important limitations

- N = 31 independent ML events
- final test N = 7
- ordinary Logistic Regression exhibits complete separation
- Logistic Regression produces convergence / extreme-probability warnings
- strong multicollinearity exists among the three rise-rate predictors
- the detector and NOAA matching process determine the downstream event population
- a target-proxy interpretation concern remains at the observed peak
- no external validation across another interval / instrument / solar-cycle sample

---

## Run the Shiny GUI

Install the required R packages once:

```r
install.packages(c("shiny", "jsonlite", "rpart", "randomForest"))
```

Then, from the repository root:

```bash
Rscript -e "shiny::runApp('.', launch.browser=TRUE)"
```

The GUI is **presentation-only**. It loads frozen CSV artifacts and does not retrain the
models when the app starts.

### GUI tabs

1. Meet the Sun
2. Mathematics Behind It
3. Explore GOES Data
4. What Is "Normal"?
5. Detect an Unusual Event
6. Describe the Event
7. Can We Classify It?
8. Test the Experiment
9. What Did We Learn?

`PROJECT_WALKTHROUGH.md` explains what every screen means.

---

## Re-run the frozen Stage 8 experiment

Only do this when you intentionally want to reproduce the ML stage:

```bash
Rscript R/run_stage8_ml.R
```

Run the robustness audit separately:

```bash
Rscript R/run_stage8_robustness_audit.R
```

Do not use the final-test partition for model selection.

---

## Python reference environment

Python was used as a reference/preparation implementation for ingestion, EDA, preprocessing,
rolling statistics, detector analysis and first-principles cross-checking.

```bash
python -m venv .venv
```

Windows:

```powershell
.venv\Scripts\activate
pip install -r requirements.txt
```

Linux/macOS:

```bash
source .venv/bin/activate
pip install -r requirements.txt
```

---

# GitHub

Create an empty GitHub repository, for example:

`solar-activity-sml`

Then from this folder:

```bash
git init
git add .
git commit -m "Initial release: solar activity SML PBL"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/solar-activity-sml.git
git push -u origin main
```

For later changes:

```bash
git add .
git commit -m "Update documentation"
git push
```

---

# Static project website

The repository includes `index.html` + `styles.css` so the project can be shown as a
professional static portfolio page.

This static page is separate from the R Shiny runtime.

## Vercel

### Git integration

1. Push the repository to GitHub.
2. In Vercel choose **Add New → Project**.
3. Import the GitHub repository.
4. Use **Other** / static-site settings; no build step is required.
5. Deploy.

Or with the CLI:

```bash
npm install -g vercel
vercel
vercel --prod
```

`.vercelignore` ensures that only the static website assets are uploaded to Vercel.

## GitHub Pages

Because `index.html` is at the repository root:

1. GitHub repository → **Settings**
2. **Pages**
3. Source → **Deploy from a branch**
4. Branch → `main`
5. Folder → `/(root)`
6. Save

The `.nojekyll` file tells Pages to serve the static files without Jekyll processing.

---

## Portfolio positioning

This project is best described as a **heliophysics / statistical space-data project** in a
broader astronomy or astrochemistry journey.

It demonstrates:

- working with real space-science telemetry
- physical interpretation of a measured signal
- robust statistics
- time-series reasoning
- event construction
- scientific validation
- leakage-aware ML
- reproducibility and visualization

That is a stronger and more accurate portfolio story than calling this project itself
“astrochemistry.”

---

## Scientific scope

This repository is an undergraduate statistical proof-of-concept. It does not claim:

- operational flare forecasting
- production readiness
- broad population generalization
- causal ML coefficients
- superiority of one algorithm
- external validation across another solar-cycle population
