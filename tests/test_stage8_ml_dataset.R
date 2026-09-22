# Stage 8 dataset and temporal-integrity gate.
source("R/01_stats_primitives.R")
source("R/06_feature_engineering.R")
source("R/07_ml_models.R")

run_temporal_roc_scope_tests_r(verbose = TRUE)

d <- read.csv("data/processed/labeled_events_deduplicated.csv", stringsAsFactors = FALSE, check.names = FALSE)
stopifnot(nrow(d) == 32)
stopifnot(sum(d$noaa_class_letter == "U", na.rm = TRUE) == 1)

ml <- prepare_ml_dataset_r(d)
v <- validate_ml_dataset_r(ml, stop_on_failure = TRUE)
stopifnot(v$passed)
stopifnot(v$n == 31, v$n_b == 13, v$n_c_plus == 18)

s <- split_chronological_r(ml, 18, 6, 7)
stopifnot(nrow(s$train) == 18, nrow(s$development) == 6, nrow(s$test) == 7)
stopifnot(length(intersect(s$train$event_id, s$development$event_id)) == 0)
stopifnot(length(intersect(s$train$event_id, s$test$event_id)) == 0)
stopifnot(length(intersect(s$development$event_id, s$test$event_id)) == 0)

cat("STAGE 8 DATASET GATE: PASS\n")
