# Frozen Scientific Results

## Project task

**Impulsive-Phase Flare Severity Nowcasting at `t_pred = t_peak`**

Target:

- `B`
- `C+` = NOAA `C` or `M`

Undefined `U` events are excluded from supervised classification.

Primary predictors:

- `rise_slope`
- `max_roc`
- `mean_pos_roc`
- `rise_duration_min`
- `bg_flux`

`peak_flux` is descriptive only and is not used as a primary predictor.

---

## Stage 5 — detector / NOAA alignment

- NOAA records: **35**
- Valid NOAA peaks: **34**
- Detected events: **115**
- Matched detections: **32**
- Unmatched detections: **80**
- Unmatched NOAA events: **3**
- Event precision: **0.2857**
- Event recall: **0.9143**
- Event F1: **0.4354**
- Mean absolute peak timing error: **1.76 min**
- Median absolute peak timing error: **0.00 min**

An unmatched statistical detection is not automatically a confirmed false physical solar
event; it may represent sub-B activity or noise.

---

## Stage 7 — independent event dataset

Deduplicated aligned rows before excluding U: **32**

ML-eligible independent physical events: **31**

- B: **13**
- C+: **18**

Chronological partition:

| Partition | N | B | C+ |
|---|---:|---:|---:|
| Train | 18 | 7 | 11 |
| Development | 6 | 1 | 5 |
| Final test | 7 | 5 | 2 |

---

## Stage 8 — development experiment

| Model | N | Accuracy | Macro F1 | Balanced Accuracy |
|---|---:|---:|---:|---:|
| Logistic Regression | 6 | 1.0000 | 1.0000 | 1.0000 |
| Decision Tree | 6 | 0.833333 | 0.777778 | 0.9000 |
| Random Forest | 6 | 0.833333 | 0.777778 | 0.9000 |

The predefined development procedure froze Logistic Regression for the final test.

No model is re-selected using the final test.

---

## Frozen chronological final test

Final test N: **7**

Confusion matrix:

| Actual \ Predicted | B | C+ |
|---|---:|---:|
| B | 5 | 0 |
| C+ | 0 | 2 |

Observed metrics:

- Accuracy: **1.000**
- Macro F1: **1.000**
- Balanced Accuracy: **1.000**

Interpretation:

> Seven out of seven events in the predefined chronological holdout were classified
> correctly. Because the holdout contains only seven events, this is a descriptive
> small-sample result and does not establish generalization.

---

## LOOCV robustness

| Model | Accuracy | Macro F1 | Balanced Accuracy |
|---|---:|---:|---:|
| Logistic Regression | 0.9677419 | 0.9665 | 0.9615 |
| Decision Tree | 0.80645 | 0.7961 | 0.7906 |
| Random Forest | 0.90323 | 0.89946 | 0.89530 |

LOOCV is supplementary robustness evidence and does not replace the frozen chronological
experiment.

---

## Temporal integrity

Prediction time:

`t_pred = t_peak`

The corrected primary ROC features are computed only over:

`START → PEAK`

Specifically:

- `max_roc`
- `mean_pos_roc`

do not use decay/post-peak observations.

`rise_slope`, `rise_duration_min`, and `bg_flux` are also available by the prediction time.

---

## Multicollinearity

Training correlations:

- rise_slope vs max_roc: **0.9564**
- rise_slope vs mean_pos_roc: **0.9679**
- max_roc vs mean_pos_roc: **0.9128**

Training VIF:

- rise_slope: **35.223262**
- max_roc: **20.393247**
- mean_pos_roc: **19.702162**
- rise_duration_min: **2.463870**
- bg_flux: **1.468969**

This makes individual Logistic Regression coefficients unstable to interpret.

---

## Complete separation

The ordinary Logistic Regression training data exhibit complete separation.

Consequences:

- convergence / fitted-probability warnings are expected
- ordinary maximum-likelihood coefficients are not stable finite effect estimates
- coefficient magnitude, standard error and odds-ratio interpretation should not be
  treated as reliable physical inference

The classification result and coefficient-inference problem are distinct.

---

## Limitations

1. Only **31** ML-eligible independent events.
2. Final chronological test contains only **7** events.
3. Only **2 C+** events occur in the final test.
4. Complete separation affects ordinary Logistic Regression inference.
5. Rise-rate predictors have strong multicollinearity.
6. Detector selection influences which events reach ML.
7. NOAA temporal alignment determines the supervised labels.
8. Prediction occurs at the observed peak, so a target-proxy interpretation concern remains.
9. External validation is absent.
10. This is severity nowcasting, not pre-flare forecasting.

## Scientific status

**Undergraduate statistical proof-of-concept.**

The project demonstrates an auditable path from GOES X-ray measurements to statistical
event detection and leakage-controlled severity nowcasting, while keeping the small-sample
limitations visible.
