# ==============================================================================
# R/run_stage8_ml.R
# Authoritative Stage 8 entry point
# Impulsive-Phase Flare Severity Nowcasting at t_pred = t_peak
# ==============================================================================

# GUI STARTUP GUARD: execute this standalone script only when run directly.
# Shiny automatically sources every .R file under R/.  Direct Rscript execution
# has sys.nframe() == 0; sourcing (including Shiny support loading) does not.
if (sys.nframe() == 0L) {
  options(stringsAsFactors = FALSE)
  set.seed(42)

  find_project_root <- function() {
    args <- commandArgs(trailingOnly = FALSE)
    file_arg <- grep("^--file=", args, value = TRUE)
    candidates <- c(
      if (length(file_arg) > 0) dirname(dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = FALSE))) else character(0),
      normalizePath(getwd(), winslash = "/", mustWork = FALSE),
      normalizePath(file.path(getwd(), ".."), winslash = "/", mustWork = FALSE)
    )
    for (p in unique(candidates)) {
      if (file.exists(file.path(p, "R", "06_feature_engineering.R")) &&
          file.exists(file.path(p, "data", "processed", "labeled_events_deduplicated.csv"))) {
        return(p)
      }
    }
    stop("Unable to locate project root containing R/ and data/processed/.")
  }

  PROJECT_ROOT <- find_project_root()
  setwd(PROJECT_ROOT)

  cat("\n========================================\n")
  cat("STAGE 8 — FLARE SEVERITY NOWCASTING\n")
  cat("========================================\n")
  cat("Prediction time: t_peak\n")
  cat("Task: B vs C+\n\n")

  # Required modules. Do not source legacy R/run_pipeline.R.
  source("R/01_stats_primitives.R")
  source("R/06_feature_engineering.R")
  source("R/07_ml_models.R")
  source("R/08_evaluation.R")

  # ------------------------------------------------------------------------------
  # Prerequisite tests
  # ------------------------------------------------------------------------------
  cat("Prerequisite validation\n-----------------------\n")
  run_stats_primitive_tests()
  run_temporal_roc_scope_tests_r(verbose = TRUE)
  cat("Temporal validation: PASS\n")
  cat("ROC scope: START -> PEAK\n")
  cat("Post-peak information: NONE\n\n")

  # ------------------------------------------------------------------------------
  # Dataset construction and validation
  # ------------------------------------------------------------------------------
  source_file <- "data/processed/labeled_events_deduplicated.csv"
  raw_df <- read.csv(source_file, stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(raw_df) != 32) {
    stop(sprintf("Expected 32 deduplicated physical-event rows before U exclusion; found %d.", nrow(raw_df)))
  }
  if (sum(raw_df$noaa_class_letter == "U", na.rm = TRUE) != 1) {
    stop("Expected exactly one U event before supervised eligibility filtering.")
  }

  ml_df <- prepare_ml_dataset_r(raw_df)
  validation <- validate_ml_dataset_r(ml_df, stop_on_failure = TRUE)

  cat("Dataset validation\n------------------\n")
  cat(sprintf("Independent events: %d\n", validation$n))
  cat(sprintf("B: %d\n", validation$n_b))
  cat(sprintf("C+: %d\n", validation$n_c_plus))
  cat("U excluded: 1\n\n")

  cat("Primary predictors\n------------------\n")
  cat(paste0(STAGE8_PRIMARY_PREDICTORS, collapse = "\n"), "\n\n")

  # ------------------------------------------------------------------------------
  # Chronological split
  # ------------------------------------------------------------------------------
  splits <- split_chronological_r(ml_df, n_train = 18, n_dev = 6, n_test = 7)
  train_df <- splits$train
  dev_df <- splits$development
  test_df <- splits$test

  cat("Chronological split\n-------------------\n")
  cat(sprintf("Train: %d (%s)\n", nrow(train_df), paste(names(table(train_df$severity_class)), table(train_df$severity_class), collapse = ", ")))
  cat(sprintf("Development: %d (%s)\n", nrow(dev_df), paste(names(table(dev_df$severity_class)), table(dev_df$severity_class), collapse = ", ")))
  cat(sprintf("Final test: %d (%s)\n\n", nrow(test_df), paste(names(table(test_df$severity_class)), table(test_df$severity_class), collapse = ", ")))

  # Persist exact split before any model fitting.
  dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
  write.csv(train_df, "data/processed/stage8_train.csv", row.names = FALSE)
  write.csv(dev_df, "data/processed/stage8_development.csv", row.names = FALSE)
  write.csv(test_df, "data/processed/stage8_final_test.csv", row.names = FALSE)

  # ------------------------------------------------------------------------------
  # Multicollinearity diagnostics — training data only
  # ------------------------------------------------------------------------------
  cor_matrix <- cor(train_df[, STAGE8_PRIMARY_PREDICTORS], use = "complete.obs", method = "pearson")
  vif_table <- calculate_vif_r(train_df, STAGE8_PRIMARY_PREDICTORS)
  write.csv(cor_matrix, "reports/STAGE8_TRAIN_CORRELATION.csv", row.names = TRUE)
  write.csv(vif_table, "reports/STAGE8_TRAIN_VIF.csv", row.names = FALSE)

  cat("Multicollinearity diagnostics (training only)\n--------------------------------------------\n")
  print(round(cor_matrix, 4))
  print(vif_table)
  cat("\n")

  # ------------------------------------------------------------------------------
  # Train candidate models on TRAIN only. Predefined modest configurations.
  # No final-test access here.
  # ------------------------------------------------------------------------------
  cat("Models\n------\n")
  cat("Logistic Regression\nDecision Tree\nRandom Forest\n\n")

  logistic <- fit_logistic_model_r(train_df, use_class_weights = FALSE)
  decision_tree <- fit_decision_tree_r(train_df, maxdepth = 3, minsplit = 4, cp = 0.01)
  random_forest <- fit_random_forest_r(train_df, ntree = 200, mtry = 2, seed = 42)

  sep <- separation_diagnostic_r(logistic, train_df)
  coef_table <- summarize_logistic_coefficients_r(logistic)
  rf_importance <- calculate_feature_importance_r(random_forest)

  # ------------------------------------------------------------------------------
  # Development evaluation — used for model specification freeze.
  # ------------------------------------------------------------------------------
  dev_preds <- list(
    Logistic_Regression = predict_stage8_model_r(logistic, dev_df),
    Decision_Tree = predict_stage8_model_r(decision_tree, dev_df),
    Random_Forest = predict_stage8_model_r(random_forest, dev_df)
  )

  dev_metrics <- do.call(rbind, lapply(names(dev_preds), function(nm) {
    p <- dev_preds[[nm]]
    calculate_binary_metrics_r(p$actual, p$predicted,
                               model_name = gsub("_", " ", nm), partition = "Development")
  }))
  rownames(dev_metrics) <- NULL

  cat("Development results\n-------------------\n")
  print(dev_metrics)

  # Freeze by predefined primary criterion only; test set has not been inspected.
  # Tie-breaks: Balanced Accuracy, then fixed model order (Logistic, Tree, RF).
  model_order <- c("Logistic Regression", "Decision Tree", "Random Forest")
  dev_metrics$Model_Order <- match(dev_metrics$Model, model_order)
  ord <- order(-dev_metrics$Macro_F1, -dev_metrics$Balanced_Accuracy, dev_metrics$Model_Order)
  selected_name <- dev_metrics$Model[ord[1]]
  cat(sprintf("\nFrozen model after development evaluation: %s\n", selected_name))
  cat("Primary selection metric: Macro F1; secondary: Balanced Accuracy.\n")

  selected_obj <- switch(
    selected_name,
    "Logistic Regression" = logistic,
    "Decision Tree" = decision_tree,
    "Random Forest" = random_forest,
    stop("Unexpected selected model name.")
  )

  # ------------------------------------------------------------------------------
  # Final test — exactly one evaluation after model freeze.
  # ------------------------------------------------------------------------------
  final_pred <- predict_stage8_model_r(selected_obj, test_df)
  final_metrics <- calculate_binary_metrics_r(
    final_pred$actual, final_pred$predicted,
    model_name = selected_name, partition = "Final Test"
  )
  final_cm <- calculate_confusion_matrix_r(final_pred$actual, final_pred$predicted)

  cat("\nFinal test\n----------\n")
  print(final_cm)
  print(final_metrics)

  # ------------------------------------------------------------------------------
  # Robustness — supplementary; does not replace chronological final test.
  # ------------------------------------------------------------------------------
  cat("\nRobustness\n----------\n")
  cat(sprintf("Separation diagnostic: %s\n", sep$classification))
  if (length(logistic$warnings) > 0) {
    cat("Logistic warnings:\n")
    cat(paste0(" - ", logistic$warnings, collapse = "\n"), "\n")
  } else {
    cat("Logistic warnings: none captured\n")
  }

  loocv <- loocv_logistic_r(ml_df, STAGE8_PRIMARY_PREDICTORS)
  cat("LOOCV Logistic Regression metrics:\n")
  print(loocv$metrics)
  cat(sprintf("LOOCV folds with captured warning messages (aggregate count): %d\n", loocv$warning_count))

  # ------------------------------------------------------------------------------
  # Save reproducible artifacts
  # ------------------------------------------------------------------------------
  dir.create("reports", recursive = TRUE, showWarnings = FALSE)
  write.csv(dev_metrics[, setdiff(names(dev_metrics), "Model_Order")], "reports/STAGE8_MODEL_COMPARISON.csv", row.names = FALSE)
  write.csv(final_metrics, "reports/STAGE8_ML_RESULTS.csv", row.names = FALSE)
  write.csv(final_pred, "reports/STAGE8_FINAL_TEST_PREDICTIONS.csv", row.names = FALSE)
  write.csv(as.data.frame.matrix(final_cm), "reports/STAGE8_CONFUSION_MATRICES.csv", row.names = TRUE)
  write.csv(loocv$metrics, "reports/STAGE8_ROBUSTNESS.csv", row.names = FALSE)
  write.csv(loocv$predictions, "reports/STAGE8_LOOCV_PREDICTIONS.csv", row.names = FALSE)
  write.csv(coef_table, "reports/STAGE8_LOGISTIC_COEFFICIENTS.csv", row.names = FALSE)
  write.csv(rf_importance, "reports/STAGE8_RANDOM_FOREST_IMPORTANCE.csv", row.names = FALSE)

  # Save development predictions for transparent model-selection provenance.
  for (nm in names(dev_preds)) {
    write.csv(dev_preds[[nm]], file.path("reports", paste0("STAGE8_DEV_PREDICTIONS_", toupper(nm), ".csv")), row.names = FALSE)
  }

  saveRDS(logistic, "reports/STAGE8_LOGISTIC_MODEL.rds")
  saveRDS(decision_tree, "reports/STAGE8_DECISION_TREE_MODEL.rds")
  saveRDS(random_forest, "reports/STAGE8_RANDOM_FOREST_MODEL.rds")
  saveRDS(selected_obj, "reports/STAGE8_SELECTED_MODEL.rds")

  # Machine-readable separation summary.
  sep_df <- data.frame(
    Classification = sep$classification,
    All_Training_Predictions_Correct = sep$all_training_predictions_correct,
    All_Probabilities_Extreme = sep$all_probabilities_extreme,
    Warning_Flag = sep$warning_flag,
    Large_Coefficient_Flag = sep$large_coefficient_flag,
    Min_Probability = sep$min_probability,
    Max_Probability = sep$max_probability,
    Formal_Detector_Status = sep$formal_detector_status,
    stringsAsFactors = FALSE
  )
  write.csv(sep_df, "reports/STAGE8_SEPARATION_DIAGNOSTIC.csv", row.names = FALSE)

  cat("\n========================================\n")
  cat("STAGE 8 COMPLETE\n")
  cat("========================================\n")
  cat(sprintf("Independent events: %d\n", nrow(ml_df)))
  cat(sprintf("B: %d\n", sum(ml_df$severity_class == "B")))
  cat(sprintf("C+: %d\n", sum(ml_df$severity_class == "C_plus")))
  cat("Predictors: 5\n")
  cat(sprintf("Train / Development / Test: %d / %d / %d\n", nrow(train_df), nrow(dev_df), nrow(test_df)))
  cat(sprintf("Frozen model: %s\n", selected_name))
  cat(sprintf("Final test Macro F1: %.4f\n", final_metrics$Macro_F1))
  cat(sprintf("Final test Balanced Accuracy: %.4f\n", final_metrics$Balanced_Accuracy))
  cat(sprintf("Leakage checks: %s\n", ifelse(validation$passed, "PASS", "FAIL")))
  cat("Temporal ROC scope tests: PASS\n")
  cat("Reproducibility seed: 42\n")
}
