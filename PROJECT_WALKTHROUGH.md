# Project Walkthrough — Code, Mathematics, ML, GUI and Viva Explanation

This file is written for project demonstration and viva preparation. It explains what each
remaining file does, how the mathematics maps to the code, how the models are applied, and
what each GUI screen means.

---

# 1. The project in one sentence

We take a real one-minute GOES soft-X-ray time series, estimate recent solar background
behavior statistically, detect sustained unusual activity, convert detected intervals into
physical events, align them with NOAA flare records, extract five rise-phase predictors
available by the observed peak, and evaluate classical B-vs-C+ classifiers chronologically.

---

# 2. Scientific story from beginning to end

## 2.1 Observation

GOES measures solar X-ray flux repeatedly.

The main channel used for flare severity is the long X-ray channel:

`0.1–0.8 nm`

A time series is therefore:

`time_1 → flux_1, time_2 → flux_2, ...`

## 2.2 Why statistics are needed

The Sun does not have one fixed background flux. The background changes, and flares create
very large spikes.

So the detector asks:

1. What has the Sun been doing recently?
2. What is the center of that recent behavior?
3. How much does it normally vary?
4. Is the current observation unusually high?
5. Is the increase rapid and persistent?

## 2.3 Detection

An anomaly score alone is not treated as a complete physical event.

The detector combines statistical signals and persistence, then contiguous detected points
are grouped into START → PEAK → END event intervals.

## 2.4 NOAA alignment

Detected event intervals are compared with official NOAA flare records.

This gives:

- official event IDs
- official class labels
- timing error
- matched / unmatched status

## 2.5 Feature engineering

For each independent physical event, the final primary ML model uses exactly:

- `rise_slope`
- `max_roc`
- `mean_pos_roc`
- `rise_duration_min`
- `bg_flux`

The prediction time is the observed peak:

`t_pred = t_peak`

The model cannot use information from after that time.

## 2.6 Classification

The target is:

- B
- C+ (`C` or `M`)

The unit of ML is **one physical event**, not one minute.

There are 31 ML-eligible events.

## 2.7 Evaluation

Chronological split:

- first 18 events → training
- next 6 → development
- last 7 → final test

The final test is not used for model selection.

---

# 3. Mathematics — intuition, formula and code mapping

## 3.1 Arithmetic mean

Question:

**Where is the recent X-ray level centered?**

Formula:

`mean = (1/n) × sum(x_i)`

In `R/01_stats_primitives.R`, `calculate_mean()` cleans the vector, loops over its values,
adds them, and divides by `n`.

Why this matters:

A flare spike can pull the mean upward.

---

## 3.2 Sample variance

Question:

**How dispersed are recent values around their mean?**

Formula:

`variance = sum((x_i - mean)^2) / (n - 1)`

`n - 1` is the sample/Bessel correction.

In R:

`calculate_variance(x, ddof = 1)`

The implementation explicitly calculates deviations and squared deviations.

---

## 3.3 Standard deviation

Question:

**What is a typical scale of variation?**

Formula:

`SD = sqrt(variance)`

In R:

`calculate_std()`

Why it matters:

A very large flare can inflate SD and make later observations look less unusual.

---

## 3.4 Median

Question:

**What is the middle recent value?**

The values are sorted. The middle value is returned for odd `n`; the two middle values are
averaged for even `n`.

In R:

`calculate_median()`

Why it matters:

The median is less sensitive to a few extreme flare values.

---

## 3.5 Quantile and IQR

Quantiles describe positions in the ordered data.

`IQR = Q3 - Q1`

In R:

- `calculate_quantile()`
- `calculate_iqr()`

These help describe the central spread without relying entirely on mean/SD.

---

## 3.6 Median Absolute Deviation

Question:

**How spread out is the background without allowing extreme flare points to dominate?**

Formula:

`MAD_raw = median(|x_i - median(x)|)`

For Gaussian-scale comparability:

`MAD_scaled = 1.4826 × MAD_raw`

In R:

- `calculate_mad_raw()`
- `calculate_mad_scaled()`

The factor is applied once.

---

## 3.7 Coefficient of variation

`CV = SD / mean`

Used as a relative measure of spread when the mean is valid and non-zero.

In R:

`calculate_cv()`

---

## 3.8 Rolling statistics

The detector needs **local** normal behavior, not a single average for the whole week.

At each time `t`, a trailing window is used.

Important implementation idea:

The current point can be excluded from its own baseline.

This is called an **uncontaminated** or lagged baseline.

In `R/03_rolling_statistics.R`:

`compute_rolling_statistics_r()`

creates rolling:

- mean
- median
- standard deviation
- scaled MAD
- rate of change
- local slope

Why exclude the current point?

Because if the flare point contributes to the background used to judge itself, it can
artificially reduce its anomaly score.

---

## 3.9 Standard Z anomaly score

Question:

**How far is the current point above recent ordinary behavior?**

Formula:

`z = (x - mean_background) / SD_background`

In the project this is an anomaly score.

It is **not** a formal Z hypothesis test with a p-value.

---

## 3.10 Robust Z anomaly score

Formula:

`z_robust = (x - rolling_median) / rolling_MAD_scaled`

This replaces mean/SD with robust center/spread.

It is useful because flare values are exactly the kind of extreme observations that can
distort ordinary mean/SD.

---

## 3.11 Rate of change

The code works in log10 flux.

Conceptually:

`ROC_t = log10(flux_t) - log10(flux_(t-1))`

Question:

**How suddenly is the signal increasing?**

This is useful for impulsive flare rise behavior.

---

## 3.12 Local slope

A short linear relationship is fitted over recent points:

`y = beta_0 + beta_1 t`

`beta_1` is the local slope.

Question:

**Is the signal showing a sustained direction of growth, not only a single jump?**

---

## 3.13 Event rise slope

For one detected event, `rise_slope` summarizes the START→PEAK rise.

The project uses event-level morphology rather than feeding every one-minute row into ML.

---

## 3.14 Logistic Regression

Logistic Regression models a binary probability:

`P(C+) = 1 / (1 + exp(-(beta_0 + beta_1 x_1 + ... + beta_p x_p)))`

Our five `x` values are the five primary predictors.

Before the Logistic fit, the Stage 8 code learns a scaler from the training set and applies
the same training scaler to development/test data.

This prevents using held-out distribution information during fitting.

The class is predicted as C+ when `P(C+) >= 0.5`, otherwise B.

---

## 3.15 Decision Tree

The tree repeatedly makes feature-based splits.

Example conceptually:

`max_roc < threshold ?`

The `rpart` package searches for useful split rules.

Frozen Stage 8 configuration:

- `maxdepth = 3`
- `minsplit = 4`
- `cp = 0.01`

---

## 3.16 Random Forest

A Random Forest trains many decision trees using randomized feature/data sampling and
combines their votes.

Frozen Stage 8 configuration:

- `ntree = 200`
- `mtry = 2`
- `seed = 42`

It is a comparison model, not evidence that an ensemble is inherently superior.

---

## 3.17 Confusion matrix

For C+ as the positive class:

- TP: C+ correctly predicted C+
- TN: B correctly predicted B
- FP: B incorrectly predicted C+
- FN: C+ incorrectly predicted B

Frozen final-test confusion matrix:

- TN = 5
- FP = 0
- FN = 0
- TP = 2

---

## 3.18 Precision, Recall, F1

C+ Precision:

`TP / (TP + FP)`

C+ Recall / Sensitivity:

`TP / (TP + FN)`

F1:

`2 × Precision × Recall / (Precision + Recall)`

The R implementation also computes class-specific B metrics.

---

## 3.19 Balanced Accuracy

`(Sensitivity + Specificity) / 2`

This gives the two classes equal importance.

---

## 3.20 Macro F1

The project calculates B F1 and C+ F1 separately and averages them.

This prevents one class from completely dominating the headline score.

---

## 3.21 Correlation and VIF

Correlation measures linear association between two predictors.

VIF asks how well one predictor can be explained by the others:

`VIF = 1 / (1 - R^2)`

Large VIF means redundant linear information.

Our three rise-rate predictors have high VIF, so Logistic coefficient interpretation is
unstable.

---

## 3.22 Complete separation

Complete separation means a linear boundary can perfectly separate the training classes.

For ordinary Logistic Regression, this causes maximum-likelihood coefficients to become
numerically unstable or diverge.

Therefore:

- fitted classification may still be deterministic in this sample
- ordinary coefficient magnitude / odds ratio should not be interpreted as a stable physical
  effect

---

# 4. R implementation — what each file does

## `R/01_stats_primitives.R`

Purpose:

Builds the statistical foundation from transparent arithmetic.

Important functions:

- `clean_numeric_vector()` removes invalid numeric values before a statistic is calculated.
- `calculate_mean()` computes the mean from explicit summation.
- `calculate_median()` sorts and selects/averages middle values.
- `calculate_variance()` computes squared deviations and applies `ddof`.
- `calculate_std()` is the square root of variance.
- `calculate_quantile()` implements the project's quantile convention.
- `calculate_iqr()` returns Q3-Q1.
- `calculate_mad_raw()` calculates median absolute deviation.
- `calculate_mad_scaled()` applies 1.4826 exactly once.
- `calculate_cv()` calculates relative dispersion.
- `calculate_standard_zscore()` applies `(x-mean)/SD`.
- `calculate_robust_zscore()` applies `(x-median)/MAD_scaled`.
- `run_stats_primitive_tests()` compares the first-principles calculations with known
  reference behavior.

Viva explanation:

> “We wrapped our calculations in functions for reuse, but the mathematical primitives
> themselves are explicit vector arithmetic. We did not call a single black-box function
> that magically performs the entire analysis.”

---

## `R/02_preprocessing.R`

Purpose:

Produces a scientifically usable time grid while preserving missingness provenance.

Main function:

`preprocess_goes_xrs_r()`

Key behavior:

- selects the requested GOES energy channel
- checks/normalizes timestamps
- handles invalid/non-positive flux values
- operates in log10 flux where appropriate
- only short gaps are interpolated
- long gaps remain missing / separate segments
- creates provenance flags such as missingness/imputation/segment indicators

Why:

Log10 cannot be calculated for non-positive values, and blindly filling long gaps would
invent solar behavior.

---

## `R/03_rolling_statistics.R`

Purpose:

Builds time-local statistical context.

Main function:

`compute_rolling_statistics_r()`

Creates:

- rolling mean
- rolling median
- rolling SD
- rolling scaled MAD
- ROC
- short local slope

Important configuration:

- main window: 30 min
- minimum support: 5 points
- slope window: 5 min
- uncontaminated baseline supported

On-screen meaning:

When the GUI shows rolling mean/median, those lines answer “what is normal recently?”
The SD/MAD panels answer “how much does recent behavior vary?”
Z panels answer “how unusual is this point?”
ROC/slope answer “how quickly is it changing?”

---

## `R/04_event_detection.R`

Purpose:

Converts statistics into candidate events.

Important functions:

### `compute_detection_scores_r()`

Creates standard Z, robust Z and rate-of-change scores.

### `apply_persistence_filter_r()`

Requires a signal to persist for a minimum number of consecutive points.

Why:

One-minute noise should not automatically become an event.

### `detect_anomalies_r()`

Frozen/default parameters represented in the code include:

- `z_mean_thr = 3.0`
- `z_mad_thr = 3.0`
- `roc_thr = 0.05`
- `min_len = 3`
- `window_mins = 30`

### `segment_events_r()`

Turns detected runs into events with START / PEAK / END.

### `merge_overlapping_events_r()`

Combines event segments separated by only a very small allowed gap.

---

## `R/05_noaa_alignment.R`

Purpose:

Compares our detected event timeline with official NOAA flare records.

Important functions:

- `parse_utc_timestamp()`
- `ingest_noaa_flares_r()`
- `align_events_with_noaa_r()`

The alignment logic evaluates temporal agreement rather than inventing labels.

Outputs include:

- NOAA event ID
- NOAA class
- timing relationship
- absolute peak timing error
- match status

Viva explanation:

> “The detector does not create the supervised label. NOAA provides an independent event
> reference, and our event is aligned with that record.”

---

## `R/06_feature_engineering.R`

Purpose:

Converts one aligned physical event into one numerical ML row.

### `calculate_rise_roc_features_r()`

Calculates `max_roc` and `mean_pos_roc` using only the rise interval.

Undefined statistics return `NA`, not an invented zero.

### `run_temporal_roc_scope_tests_r()`

Tests cases including:

- ordinary rise + decay
- a decay with a larger ROC than the rise
- no valid positive rise ROC
- invalid NA/NaN/Inf values

This proves post-peak ROC cannot enter those primary features.

### `extract_event_features_r()`

Creates event-level morphology such as:

- `bg_flux`
- `peak_flux` (descriptive)
- `rise_duration_min`
- `rise_slope`
- `max_roc`
- `mean_pos_roc`
- post-event descriptive features

The fact that a column exists in the event table does **not** mean it is an ML predictor.

### `validate_feature_matrix_r()`

Checks numerical integrity.

---

## `R/07_ml_models.R`

Purpose:

Defines the frozen Stage 8 ML experiment.

### Primary predictor constant

Exactly:

- rise_slope
- max_roc
- mean_pos_roc
- rise_duration_min
- bg_flux

Forbidden primary features include peak-defined/post-event quantities.

### `prepare_ml_dataset_r()`

Maps labels:

- B → B
- C or M → C_plus
- U → excluded

Sorts events chronologically by peak time.

### `validate_ml_dataset_r()`

Checks:

- exactly 31 events
- 13 B
- 18 C+
- no undefined target
- no duplicate event IDs
- no duplicate NOAA event IDs
- no NA/NaN/Inf predictors
- all predictors numeric
- target not included as predictor
- forbidden predictors absent
- exactly five primary predictors

### `split_chronological_r()`

Creates:

- train = 18
- development = 6
- final test = 7

Then explicitly checks that physical/NOAA event IDs do not overlap between partitions.

### Scaling

`fit_scaler_r()` learns mean/SD from training only.

`apply_scaler_r()` reuses those training parameters.

### `fit_logistic_model_r()`

Uses base R:

`glm(..., family = binomial(link="logit"))`

The target is converted to numeric B=0, C+=1.

### `fit_decision_tree_r()`

Uses `rpart`.

### `fit_random_forest_r()`

Uses `randomForest` with a fixed seed.

### `predict_stage8_model_r()`

Creates:

- event ID
- actual class
- predicted class
- probability of C+

### `calculate_binary_metrics_r()`

Builds the confusion matrix and calculates:

- accuracy
- per-class precision/recall/F1
- Macro F1
- sensitivity
- specificity
- balanced accuracy
- TP/FP/TN/FN

### `calculate_vif_r()`

Fits each predictor against the other four using linear regression and calculates VIF.

### `separation_diagnostic_r()`

Checks:

- whether all training labels are classified correctly
- extreme probabilities
- warnings
- large coefficients

This is why the project reports the separation limitation rather than hiding it.

### `loocv_logistic_r()`

Holds out one of the 31 events at a time, refits the scaler/model on the other 30, predicts
the held-out event, then aggregates the metrics.

---

## `R/08_evaluation.R`

Purpose:

Contains general classification-evaluation helpers.

`evaluate_classification_r()` and `compare_models_r()` summarize model output.

For the frozen Stage 8 experiment, the more specific binary evaluation logic in
`07_ml_models.R` is the authoritative path.

---

## `R/09_visualizations.R`

Purpose:

Creates formal project figures from scientific outputs.

Examples:

- rolling baseline / anomaly views
- event segmentation
- NOAA class distributions
- feature distributions
- model comparison visualizations

The report/PPT uses actual project figures rather than decorative fake data.

---

## `R/run_stage8_ml.R`

Purpose:

Authoritative Stage 8 execution script.

It:

1. loads the deduplicated event table
2. creates the B/C+ ML dataset
3. runs validation
4. creates the 18/6/7 split
5. calculates training correlation / VIF
6. fits Logistic, Tree and Forest on training data
7. evaluates each on development data
8. applies the frozen selection procedure
9. evaluates the frozen model on final test
10. calculates LOOCV / diagnostics
11. writes scientific artifacts

This script is **not called by the Shiny app**.

---

## `R/run_stage8_robustness_audit.R`

Purpose:

Supplementary diagnostics after the primary experiment was frozen.

It does not redefine the primary methodology.

It is kept because complete separation, multicollinearity, LOOCV and reproducibility are
important scientific limitations.

---

# 5. Python reference implementation

R is the primary SML pipeline. Python is kept as a transparent reference/preparation
implementation.

## `src/config.py`

Central constants and NOAA source locations.

## `src/ingestion.py`

Downloads NOAA JSON data, validates schemas and can archive a fresh raw snapshot.

Important:

A fresh download is new data. It does not reproduce the frozen September-2026 experiment
unless the historical snapshot is the same.

## `src/preprocessing.py`

Python reference implementation of cleaning, log-space interpolation and provenance flags.

## `src/stats.py`

Python first-principles equivalents of:

- mean
- median
- variance
- SD
- quantile
- IQR
- MAD
- CV

Used to cross-check the underlying mathematics.

## `src/rolling_stats.py`

Reference rolling-baseline implementation and diagnostic plots.

## `src/detector.py`

Reference detector and event-evaluation implementation.

It includes:

- standard Z detection
- robust Z detection
- rate-of-change detection
- persistence
- event extraction
- event merging
- point/event evaluation

## `src/eda.py`

Creates exploratory summaries and figures.

## `src/run_detector_evaluation.py`

Runs the detector evaluation grid for the reference detector.

It is not the Stage 8 ML runner.

---

# 6. Tests

## `tests/test_stats.py`

Validates first-principles Python statistics and important numerical rules.

## `tests/test_noaa_alignment.R`

Exercises NOAA alignment cases and helps prevent accidental many-to-one/mismatched event
logic.

## `tests/test_stage8_ml_dataset.R`

Checks the Stage 8 dataset assumptions, especially the fixed event count / predictor matrix
integrity.

---

# 7. Data files — what every retained file means

## `data/processed/goes_xrs_cleaned.csv`

Rows:

20,156 across the two energy-channel records in the snapshot.

Important columns:

- `time_tag` — UTC timestamp
- `satellite` — GOES satellite identifier
- `flux` — measured flux field
- `observed_flux` — observation before correction context
- `electron_correction` — correction quantity
- `electron_contaminaton` — contamination flag from source
- `energy` — XRS energy/wavelength channel
- `is_missing_raw` — whether input was missing
- `gap_size_mins` — temporal gap information
- `log10_flux` — logarithmic flux
- `log10_flux_clean` — cleaned logarithmic flux
- `flux_clean` — cleaned physical flux
- `segment_id` — contiguous segment ID
- `was_imputed` — whether short-gap interpolation was used
- `is_long_gap` — long gap preserved rather than filled

In the GUI:

This file feeds the GOES Data and read-only statistical-baseline views.

---

## `data/processed/labeled_events_deduplicated.csv`

32 independent aligned event rows before U exclusion.

Each row represents one physical NOAA-aligned event.

Important groups of columns:

Identity/time:
- event_id
- start_time
- peak_time
- end_time
- noaa_event_id

Primary Stage 8 predictors:
- bg_flux
- rise_duration_min
- rise_slope
- max_roc
- mean_pos_roc

Descriptive/event-only quantities:
- peak_flux
- excess_flux
- total duration
- decay information
- mean/median/std/MAD/IQR within event
- persistence count

Labels:
- noaa_class_letter
- noaa_class

Alignment:
- abs_peak_error_min

In the GUI:

This file drives event selection, event morphology and the true NOAA class.

---

## `data/processed/detector_evaluation_grid.csv`

A grid of detector settings and their measured point/event metrics.

Columns include thresholds, persistence length, precision/recall/F1 and TP/FP/FN counts.

It is detector-analysis evidence, not ML model-selection data.

---

## `data/processed/event_segmentation_report.csv`

Event-level output from the segmentation stage.

Used to inspect candidate event boundaries.

---

## `data/processed/event_segmentation_summary.csv`

Compact summary of segmentation output.

---

# 8. Report artifacts

## `reports/STAGE8_MODEL_COMPARISON.csv`

Authoritative frozen development comparison.

The GUI uses it to populate the development-results table and plot.

## `reports/STAGE8_TRAIN_CORRELATION_CURRENT.csv`

Training-only Pearson correlation matrix.

It shows the three rise-rate predictors are strongly correlated.

## `reports/STAGE8_TRAIN_VIF_CURRENT.csv`

Training-only VIF diagnostic.

Large VIF for rise-rate predictors warns against over-interpreting Logistic coefficients.

## `reports/STAGE8_FEATURE_DISTRIBUTIONS.csv`

Class-wise descriptive statistics for the five primary predictors.

Contains:

- N
- minimum
- Q1
- median
- mean
- Q3
- maximum
- SD
- IQR

## `reports/STAGE8_FEATURE_EFFECTS.csv`

Contains Cliff's delta effect-size summaries for B vs C+ morphology.

These are descriptive sample effects, not causal effects.

## `reports/preprocessing_report.json`

Machine-readable preprocessing summary.

---

# 9. Scientific figures

## `fig1_flux_distributions.png`

Shows the X-ray flux distribution and why log transformation / robust statistics matter.

## `fig2_full_timeseries_overview.png`

The full observation-window story figure.

Shows real X-ray behavior over time.

## `fig3_flare_event_profiles.png`

Zoomed event profiles.

Useful for explaining START → RISE → PEAK → DECAY.

## `fig4_window_size_comparison.png`

Shows how different rolling-window sizes change the local baseline.

## `fig5_derivatives_and_slopes.png`

Shows rate-of-change and slope behavior.

## `fig6_detector_evaluation.png`

Detector-evaluation figure.

## `stage8_5_boxplot_*.png`

B vs C+ distribution of each primary predictor.

## `stage8_5_rise_rate_correlation.png`

Shows the strong relationship among the rise-rate predictors.

---

# 10. The Shiny GUI — what every tab means

The GUI is a **presentation layer** over frozen data/artifacts.

It should not be described as “the GUI trains the model.”

## Tab 1 — Meet the Sun

What appears:

A conceptual story from Sun → X-rays → GOES → data → statistics → events → severity.

What it means:

This is the problem framing.

What to say:

> “The project begins with a physical measurement, not with a machine-learning algorithm.”

---

## Tab 2 — Mathematics Behind It

What appears:

Mean, variance, SD, median, MAD, rolling statistics, Z/robust-Z, ROC/slope and classical ML
equations.

What it means:

This maps SML-course mathematics to the project.

What to say:

> “Each equation answers a practical question about the signal. The mathematics is used to
> define local normality, unusual behavior and event shape.”

Do not say the Z-score is a formal Z-test.

---

## Tab 3 — Explore GOES Data

What appears:

- observation count
- time coverage
- cadence
- missing/imputed information
- selected XRS-B time-series plot
- optional B/C/M/X reference lines

Meaning of B/C/M/X lines:

These are NOAA severity reference flux levels in the long X-ray channel.

They provide physical context.

They are not detector thresholds and are not ML features.

---

## Tab 4 — What Is "Normal"?

What appears:

- X-ray signal
- rolling mean / median
- rolling SD / MAD
- standard / robust Z
- ROC / slope
- read-only detector settings

What it means:

This is the statistical heart of the project.

Interpretation:

- mean/median → recent center
- SD/MAD → recent spread
- Z values → unusualness relative to background
- ROC → sudden change
- slope → sustained direction

---

## Tab 5 — Detect an Unusual Event

What appears:

A selected physical event with START, PEAK and END plus NOAA details.

What it means:

Statistics has been converted into an event object, then compared with an independent NOAA
record.

`abs_peak_error_min` means the absolute difference between detected and official peak time.

---

## Tab 6 — Describe the Event

What appears:

- event table
- five primary features
- B/C+ feature boxplots
- rise-rate correlation view

What it means:

The event waveform is turned into numerical morphology.

Important:

`peak_flux` may be displayed descriptively in the event table, but it is not a primary
Stage 8 predictor.

---

## Tab 7 — Can We Classify It?

What appears:

- prediction point `t_pred = t_peak`
- five predictor names
- actual/predicted result if the frozen prediction artifact is available
- probability of C+ if available

What it means:

The classification question is only:

> “Given this event through its observed peak, is its severity B or C+?”

It is not:

> “Will a flare occur tomorrow?”

---

## Tab 8 — Test the Experiment

What appears:

- development-model comparison
- final-test confusion matrix/predictions when saved artifacts exist
- LOOCV/robustness information when available
- VIF
- separation/convergence warning

What the development table means:

It is where the predefined candidate models were compared.

What the final test means:

It is a later chronological holdout used only after the model choice was frozen.

What VIF means:

Predictors overlap strongly; coefficients become hard to interpret independently.

What complete separation means:

Training classes have a perfect linear boundary, so ordinary Logistic coefficient inference
is unstable.

---

## Tab 9 — What Did We Learn?

What appears:

Two categories:

- demonstrated
- cannot claim

This is the scientific conclusion.

The correct final message is:

> “This is an undergraduate statistical proof-of-concept, not an operational flare
> forecasting system.”

---

# 11. What was removed from the presentation repository and why

The source development snapshot contained 134 files.

The cleaned repository removes categories that are useful during development but distracting
in a viva/public GitHub repository:

## Removed: stage/update/audit markdown proliferation

Examples included multiple Stage 6/7/8 status, implementation and audit documents.

Why removed:

Their final scientific conclusions are consolidated into:

- `README.md`
- `FINAL_RESULTS.md`
- `PROJECT_WALKTHROUGH.md`

## Removed: repeated timestamped raw downloads

Multiple copies of nearly the same 7-day JSON payload had accumulated during ingestion
experiments.

Why removed:

They unnecessarily increase repository size and make the repo look like a working scratch
directory.

A provenance README remains, and `src/ingestion.py` can download current data.

## Removed: `__pycache__`

Compiled Python bytecode is machine-generated and should never be committed.

## Removed: old root demo wrappers

Historical helper scripts such as individual `run_*.py` demos were useful during staged
development but are not the final public entry points.

## Removed: duplicate robustness figure copies

The Stage 8.5 feature figures are kept; visually duplicate audit copies are omitted.

## Removed: independent Python Logistic diagnostic CSV

It was a supplementary diagnostic, not the authoritative frozen R Stage 8 artifact.

## Removed: legacy full-pipeline runner

The old `R/run_pipeline.R` had historical Stage 1–7 / legacy-ML behavior and caused the
earlier Shiny auto-source Random-Forest error before startup guards were introduced.

For the presentation repository, the authoritative ML runner is:

`R/run_stage8_ml.R`

---

# 12. What to say if sir asks “Why both R and Python?”

A good answer:

> “R is the primary statistical/ML implementation for the course. Python was used earlier as
> a reference and data-preparation implementation so we could independently verify formulas,
> ingestion and detector behavior. The final Stage 8 methodology and Shiny interface are R.”

Do not say:

> “We used two languages because one could not do the work.”

---

# 13. What to say if sir asks “Did you implement ML from scratch?”

Answer:

> “No. We implemented the statistical foundations transparently, then used standard,
> well-established R implementations for Logistic Regression, Decision Tree and Random
> Forest. The scientific work is in constructing the independent event dataset, enforcing the
> prediction-time boundary, selecting the five legal predictors, avoiding leakage and
> evaluating chronologically.”

---

# 14. What to say if sir asks “Why is 7/7 not perfect accuracy?”

Answer:

> “It is 100% on this seven-event holdout, but seven is far too small to estimate future
> population performance precisely. We report the result exactly and immediately state the
> sample-size limitation.”

---

# 15. What to say if sir asks “Why peak_flux cannot be used?”

Answer:

> “NOAA class is defined from peak long-channel X-ray flux. If peak_flux enters the predictor
> matrix, the model is effectively given the quantity that defines the answer. We therefore
> keep peak flux descriptive and exclude it from the primary feature matrix.”

---

# 16. What to say if sir asks “Why START→PEAK?”

Answer:

> “The task is nowcasting at the observed peak. Anything after the peak belongs to the future
> relative to that prediction time. Stage 8.5 corrected max_roc and mean_pos_roc so they use
> only rise-phase values.”

---

# 17. Git / GitHub workflow

From the cleaned repository folder:

```bash
git init
git status
git add .
git commit -m "Initial release: solar activity SML PBL"
git branch -M main
```

Create an empty GitHub repository, then:

```bash
git remote add origin https://github.com/YOUR_USERNAME/solar-activity-sml.git
git push -u origin main
```

Routine update:

```bash
git add .
git commit -m "Update project documentation"
git push
```

Before pushing tomorrow, always run:

```bash
git status
```

Do not commit:

- `.Rhistory`
- `.RData`
- `.Rproj.user/`
- `.venv/`
- `__pycache__/`
- `.vercel/`
- repeated new raw downloads

The provided `.gitignore` already covers these.

---

# 18. Vercel concept

Vercel is used here for the **static research portfolio page**, not the R Shiny process.

Why:

An R Shiny application requires a running R server/session.

The Vercel deployment therefore presents:

- research question
- scientific pipeline
- actual project figures
- frozen results
- limitations
- GitHub/source-code context

It does not retrain the model.

## Vercel CLI

```bash
npm install -g vercel
vercel
vercel --prod
```

The repository includes `.vercelignore` so the web deployment does not upload the full
scientific code/data tree unnecessarily.

---

# 19. GitHub Pages concept

GitHub Pages is another option for the same static portfolio page.

The repository has:

- `index.html`
- `styles.css`
- `.nojekyll`

On GitHub:

Settings → Pages → Deploy from a branch → `main` → `/(root)` → Save.

GitHub Pages hosts static files; it does not execute the R Shiny server.

---

# 20. Recommended portfolio wording

Use:

> “A Statistics for Machine Learning PBL using NOAA/GOES soft-X-ray telemetry to study
> robust time-series anomaly detection, physical-event construction and leakage-controlled
> solar-flare severity nowcasting.”

For your broader journey:

> “This project is part of my wider exploration of astronomy, astrochemistry and
> data-driven space science. Here the emphasis is heliophysics and statistical analysis of a
> measured solar signal.”

That wording is scientifically stronger than calling the project itself astrochemistry.


---

# 21. Root and deployment files — what each one does

## `README.md`

The public front page of the GitHub repository.

It answers:

- what the project is
- what it is not
- the frozen scientific task
- repository structure
- mathematics used
- how R and Python divide responsibilities
- frozen results
- how to run Shiny
- how to run Stage 8 intentionally
- how to push to GitHub
- how to deploy the static portfolio page

This should be the first document a professor/recruiter sees on GitHub.

---

## `PROJECT_WALKTHROUGH.md`

The detailed viva/implementation companion.

It is intentionally longer than the README and is meant to answer:

- “what does this file do?”
- “what mathematics did you implement?”
- “why did you use that statistic?”
- “how was ML applied?”
- “what does this GUI panel mean?”
- “what should I say if sir asks this?”

---

## `FINAL_RESULTS.md`

The frozen scientific result summary.

It replaces the old development-era result documents that contained obsolete multiclass
results and outdated predictors.

It is the single human-readable source for:

- Stage 5 alignment counts
- Stage 7 event counts
- Stage 8 development metrics
- final seven-event holdout
- LOOCV
- temporal integrity
- VIF/correlation
- complete-separation warning
- final limitations

---

## `app.R`

The R Shiny presentation application.

Important design rule:

The GUI loads processed/frozen artifacts and visualizes the experiment.

It is not the model-training entry point.

The app deliberately sources only the rolling-statistics helper explicitly for read-only
display calculations; Shiny auto-load behavior is kept safe because legacy executable
scripts were removed and remaining standalone Stage 8 runners are startup-guarded.

---

## `index.html`

The static portfolio landing page.

This is what Vercel / GitHub Pages serves.

It does not execute R.

Its purpose is to make the project viewable from any browser without requiring the visitor
to install R.

---

## `styles.css`

Visual styling for `index.html`.

It defines:

- pale scientific-blue page theme
- navy typography
- responsive research cards
- result tables
- mobile layout
- image presentation

It has no scientific logic.

---

## `vercel.json`

Small Vercel configuration.

The site is static, so there is no application build pipeline.

The file only applies simple URL behavior.

---

## `.vercelignore`

Controls what Vercel uploads.

The GitHub repository contains scientific R/Python/data files, but the Vercel showcase only
needs:

- `index.html`
- `styles.css`
- `web-assets/`
- explanatory markdown files
- `vercel.json`

This keeps web deployment small and avoids pretending that Vercel executes the R pipeline.

---

## `.nojekyll`

An empty marker file used by GitHub Pages.

It tells GitHub Pages not to apply Jekyll processing to this plain static site.

---

## `.gitignore`

Prevents machine-generated/local-development files from entering Git history.

It excludes:

- R session history/data
- virtual environments
- Python bytecode
- `.vercel/`
- OS metadata
- logs
- newly downloaded timestamped raw JSON snapshots

---

## `requirements.txt`

Python reference-environment dependencies:

- numpy
- pandas
- scipy
- matplotlib
- seaborn
- requests

The primary final SML/ML experiment remains R; this file only makes the retained Python
reference code reproducible.

---

# 22. `web-assets/` files

These are duplicated intentionally from final scientific figures only for the lightweight
static website.

They are not new scientific results.

## `web-assets/timeseries.png`

Website copy of the full GOES X-ray overview.

## `web-assets/events.png`

Website copy of event-profile visualization.

## `web-assets/rise-slope.png`

Website copy of the B-vs-C+ rise-slope figure.

## `web-assets/correlation.png`

Website copy of the rise-rate correlation figure.

The originals remain in `reports/figures/` because that is the scientific-output location.
