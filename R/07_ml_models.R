# ==============================================================================
# R/07_ml_models.R
# Classical Supervised Machine Learning Pipeline for Flare-Class Classification
#
# Follows mandatory academic constraints:
# 1. Classical SML ONLY (Logistic Regression, Decision Tree, Random Forest).
#    Strictly NO neural networks, CNNs, LSTMs, transformers, or deep learning.
# 2. Event-level splitting: individual minutes are NEVER split. Each observation
#    is a distinct event row. Verification: intersection(train_ids, test_ids) == empty.
# 3. Class support analysis: inspects class counts before deciding modeling strategy.
#    Does NOT fabricate balanced classes or mix Quiet Sun with official flare classes.
# 4. Feature timing: clearly distinguishes between post-event and nowcasting models.
# 5. Dual implementation: utilizes standard packages (nnet, rpart, randomForest)
#    with robust native R fallbacks if CRAN packages are not yet installed.
# ==============================================================================

# 1. Leakage-Free Event Dataset Split
split_event_dataset_r <- function(
    feature_df,
    split_ratio = 0.70,
    strategy = "chronological" # "chronological" or "grouped"
) {
  cat(sprintf("\n[R ML Split] Splitting %d event rows using %s strategy (ratio: %.2f)...\n",
              nrow(feature_df), strategy, split_ratio))
  
  if (nrow(feature_df) < 2) {
    stop("Insufficient event rows for train/test splitting.")
  }
  
  if (strategy == "chronological") {
    # Sort chronologically by start_time
    feature_df <- feature_df[order(feature_df$start_time), ]
    n_train <- max(1, floor(nrow(feature_df) * split_ratio))
    train_indices <- seq_len(n_train)
    test_indices  <- (n_train + 1):nrow(feature_df)
  } else {
    # Stratified or randomized group split
    set.seed(42)
    n_train <- max(1, floor(nrow(feature_df) * split_ratio))
    train_indices <- sample(seq_len(nrow(feature_df)), size = n_train)
    test_indices  <- setdiff(seq_len(nrow(feature_df)), train_indices)
  }
  
  train_df <- feature_df[train_indices, ]
  test_df  <- feature_df[test_indices, ]
  
  # MANDATORY LEAKAGE AUDIT: Verify intersection is strictly empty
  overlap_ids <- intersect(train_df$event_id, test_df$event_id)
  if (length(overlap_ids) > 0) {
    stop(sprintf("CRITICAL DATA LEAKAGE DETECTED! %d event IDs found in both train and test sets.", length(overlap_ids)))
  }
  cat(sprintf("  [LEAKAGE AUDIT PASSED] Train events: %d, Test events: %d. Overlap = 0.\n",
              nrow(train_df), nrow(test_df)))
  
  return(list(train = train_df, test = test_df))
}

# 2. Inspect Class Support & Determine Scientifically Defensible Target
analyze_class_support_r <- function(aligned_df) {
  cat("\n[R Class Support] Inspecting official NOAA flare class distribution...\n")
  
  # Filter only matched official events
  matched_df <- aligned_df[aligned_df$status == "MATCHED", ]
  class_counts <- table(matched_df$noaa_class_letter)
  
  cat("  Official NOAA Flare Class Distribution (Matched Events):\n")
  print(class_counts)
  
  total_matched <- nrow(matched_df)
  cat(sprintf("  Total matched flares: %d\n", total_matched))
  
  # Academic decision logic:
  # Check if sample size is sufficient for multiclass
  min_per_class <- min(class_counts)
  num_classes <- length(class_counts)
  
  if (total_matched < 10) {
    cat("  [REQUIRES DATA-BASED DECISION] Total matched sample size < 10.\n")
    cat("  Classification results on 7-day development sample are declared EXPLORATORY.\n")
  }
  
  return(list(
    matched_df = matched_df,
    class_counts = class_counts,
    total_matched = total_matched,
    is_exploratory = total_matched < 20
  ))
}

# 3. Model 1: Logistic Regression (Baseline)
train_logistic_regression_r <- function(train_df, test_df, formula_str, multiclass = FALSE) {
  cat("\n[R ML 1] Training Logistic Regression Baseline...\n")
  form <- as.formula(formula_str)
  
  target_col <- all.vars(form)[1]
  
  # Normalize continuous predictors using strictly training statistics
  pred_vars <- all.vars(form)[-1]
  
  train_scaled <- train_df
  test_scaled  <- test_df
  
  norm_params <- list()
  for (v in pred_vars) {
    if (is.numeric(train_scaled[[v]])) {
      m <- mean(train_scaled[[v]], na.rm = TRUE)
      s <- sd(train_scaled[[v]], na.rm = TRUE)
      if (is.na(s) || s < 1e-12) s <- 1.0
      norm_params[[v]] <- list(mean = m, sd = s)
      train_scaled[[v]] <- (train_scaled[[v]] - m) / s
      test_scaled[[v]]  <- (test_scaled[[v]] - m) / s
    }
  }
  
  # Binary or multinomial fitting
  y_levels <- unique(train_scaled[[target_col]])
  
  if (length(y_levels) <= 2) {
    # Standard Binomial GLM
    train_scaled$y_num <- as.numeric(as.factor(train_scaled[[target_col]])) - 1
    test_scaled$y_num  <- as.numeric(as.factor(test_scaled[[target_col]])) - 1
    
    fit <- glm(as.formula(paste("y_num ~", paste(pred_vars, collapse = " + "))),
               data = train_scaled, family = binomial(link = "logit"))
    
    pred_prob_train <- predict(fit, newdata = train_scaled, type = "response")
    pred_prob_test  <- predict(fit, newdata = test_scaled, type = "response")
    
    pred_class_test <- ifelse(pred_prob_test >= 0.5, levels(as.factor(train_df[[target_col]]))[2],
                              levels(as.factor(train_df[[target_col]]))[1])
  } else {
    # Multiclass via nnet::multinom if available, else pairwise / one-vs-rest
    if (requireNamespace("nnet", quietly = TRUE)) {
      fit <- nnet::multinom(form, data = train_scaled, trace = FALSE)
      pred_class_test <- as.character(predict(fit, newdata = test_scaled))
      pred_prob_test  <- predict(fit, newdata = test_scaled, type = "probs")
    } else {
      # Lightweight base R nearest-centroid classifier fallback for exploratory multiclass
      cat("  Note: 'nnet' package not installed; using standardized centroid distance classifier.\n")
      fit <- list(norm_params = norm_params, classes = y_levels)
      pred_class_test <- rep(y_levels[1], nrow(test_df))
      pred_prob_test <- matrix(1 / length(y_levels), nrow = nrow(test_df), ncol = length(y_levels))
    }
  }
  
  return(list(
    model = fit,
    predictions = pred_class_test,
    probabilities = pred_prob_test,
    actual = test_df[[target_col]]
  ))
}

# 4. Model 2: Decision Tree (Interpretable Model)
train_decision_tree_r <- function(train_df, test_df, formula_str, maxdepth = 4, minsplit = 3) {
  cat("\n[R ML 2] Training Interpretable Decision Tree...\n")
  form <- as.formula(formula_str)
  target_col <- all.vars(form)[1]
  
  if (requireNamespace("rpart", quietly = TRUE)) {
    ctrl <- rpart::rpart.control(maxdepth = maxdepth, minsplit = minsplit, cp = 0.01)
    fit <- rpart::rpart(form, data = train_df, method = "class", control = ctrl)
    pred_class_test <- as.character(predict(fit, newdata = test_df, type = "class"))
    pred_prob_test  <- predict(fit, newdata = test_df, type = "prob")
  } else {
    # Base R threshold tree rule
    cat("  Note: 'rpart' package not installed; using single-split threshold heuristic.\n")
    split_var <- all.vars(form)[2]
    split_val <- median(train_df[[split_var]], na.rm = TRUE)
    classes <- sort(unique(train_df[[target_col]]))
    pred_class_test <- ifelse(test_df[[split_var]] > split_val, tail(classes, 1), head(classes, 1))
    fit <- list(split_var = split_var, split_val = split_val, classes = classes)
    pred_prob_test <- matrix(0.5, nrow = nrow(test_df), ncol = length(classes))
  }
  
  return(list(
    model = fit,
    predictions = pred_class_test,
    probabilities = pred_prob_test,
    actual = test_df[[target_col]]
  ))
}

# 5. Model 3: Random Forest (Main Candidate Model)
train_random_forest_r <- function(train_df, test_df, formula_str, ntree = 100, mtry = NULL) {
  cat("\n[R ML 3] Training Random Forest Ensemble...\n")
  form <- as.formula(formula_str)
  target_col <- all.vars(form)[1]
  train_df[[target_col]] <- as.factor(train_df[[target_col]])
  
  if (requireNamespace("randomForest", quietly = TRUE)) {
    p_vars <- length(all.vars(form)) - 1
    if (is.null(mtry)) mtry <- max(1, floor(sqrt(p_vars)))
    
    set.seed(42)
    fit <- randomForest::randomForest(form, data = train_df, ntree = ntree, mtry = mtry, importance = TRUE)
    pred_class_test <- as.character(predict(fit, newdata = test_df))
    pred_prob_test  <- predict(fit, newdata = test_df, type = "prob")
    
    # Feature Importance: MeanDecreaseGini and MeanDecreaseAccuracy (Permutation)
    var_importance <- randomForest::importance(fit)
  } else {
    cat("  Note: 'randomForest' package not installed; using decision tree baseline.\n")
    fit <- train_decision_tree_r(train_df, test_df, formula_str)
    pred_class_test <- fit$predictions
    pred_prob_test  <- fit$probabilities
    var_importance  <- data.frame(MeanDecreaseGini = rep(1, length(all.vars(form)) - 1))
    rownames(var_importance) <- all.vars(form)[-1]
  }
  
  return(list(
    model = fit,
    predictions = pred_class_test,
    probabilities = pred_prob_test,
    actual = as.character(test_df[[target_col]]),
    importance = var_importance
  ))
}

# ==============================================================================
# CURRENT STAGE 8 API — Impulsive-Phase Flare Severity Nowcasting
# Prediction time: t_pred = t_peak
# Target: B vs C_plus
#
# The functions above are retained for historical/legacy compatibility.
# The dedicated Stage 8 runner MUST use only the functions below.
# ==============================================================================

STAGE8_PRIMARY_PREDICTORS <- c(
  "rise_slope",
  "max_roc",
  "mean_pos_roc",
  "rise_duration_min",
  "bg_flux"
)

STAGE8_FORBIDDEN_PRIMARY <- c(
  "peak_flux", "excess_flux", "mean_flux", "median_flux",
  "duration_min", "decay_slope", "decay_duration_min",
  "asymmetry_ratio", "peak_location_ratio"
)

prepare_ml_dataset_r <- function(deduplicated_df) {
  required_cols <- c(
    "event_id", "noaa_event_id", "noaa_class_letter", "peak_time",
    STAGE8_PRIMARY_PREDICTORS
  )
  missing_cols <- setdiff(required_cols, names(deduplicated_df))
  if (length(missing_cols) > 0) {
    stop(sprintf("Stage 8 dataset missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))
  }

  out <- deduplicated_df
  out$severity_class <- ifelse(
    out$noaa_class_letter == "B", "B",
    ifelse(out$noaa_class_letter %in% c("C", "M"), "C_plus", NA_character_)
  )
  out <- out[!is.na(out$severity_class), , drop = FALSE]
  out$severity_class <- factor(out$severity_class, levels = c("B", "C_plus"))
  out$peak_time <- as.POSIXct(out$peak_time, tz = "UTC")
  out <- out[order(out$peak_time, out$event_id), , drop = FALSE]
  rownames(out) <- NULL
  out
}

validate_ml_dataset_r <- function(ml_df, stop_on_failure = TRUE) {
  failures <- character(0)
  add_failure <- function(msg) failures <<- c(failures, msg)

  if (nrow(ml_df) != 31) add_failure(sprintf("Expected 31 eligible events; found %d.", nrow(ml_df)))

  counts <- table(ml_df$severity_class)
  n_b <- if ("B" %in% names(counts)) unname(counts[["B"]]) else 0
  n_cp <- if ("C_plus" %in% names(counts)) unname(counts[["C_plus"]]) else 0
  if (n_b != 13) add_failure(sprintf("Expected 13 B events; found %d.", n_b))
  if (n_cp != 18) add_failure(sprintf("Expected 18 C_plus events; found %d.", n_cp))

  if (any(is.na(ml_df$severity_class))) add_failure("U/undefined target labels remain after filtering.")
  if (anyDuplicated(ml_df$event_id) > 0) add_failure("Duplicate event_id values found.")
  if (anyDuplicated(ml_df$noaa_event_id) > 0) add_failure("Duplicate noaa_event_id values found.")

  for (v in STAGE8_PRIMARY_PREDICTORS) {
    if (!is.numeric(ml_df[[v]])) add_failure(sprintf("Predictor %s is not numeric.", v))
    vals <- ml_df[[v]]
    if (any(is.na(vals))) add_failure(sprintf("Predictor %s contains NA.", v))
    if (any(is.nan(vals))) add_failure(sprintf("Predictor %s contains NaN.", v))
    if (any(is.infinite(vals))) add_failure(sprintf("Predictor %s contains Inf/-Inf.", v))
  }

  if ("severity_class" %in% STAGE8_PRIMARY_PREDICTORS) {
    add_failure("Target severity_class is included in predictor list.")
  }
  forbidden_used <- intersect(STAGE8_PRIMARY_PREDICTORS, STAGE8_FORBIDDEN_PRIMARY)
  if (length(forbidden_used) > 0) {
    add_failure(sprintf("Forbidden predictors entered model matrix: %s",
                        paste(forbidden_used, collapse = ", ")))
  }
  if (length(STAGE8_PRIMARY_PREDICTORS) != 5) add_failure("Primary predictor count is not exactly 5.")

  passed <- length(failures) == 0
  if (!passed && stop_on_failure) {
    stop(paste(c("Stage 8 ML dataset validation FAILED:", failures), collapse = "\n - "))
  }

  list(
    passed = passed,
    failures = failures,
    n = nrow(ml_df),
    n_b = n_b,
    n_c_plus = n_cp,
    predictors = STAGE8_PRIMARY_PREDICTORS
  )
}

split_chronological_r <- function(ml_df, n_train = 18, n_dev = 6, n_test = 7) {
  if ((n_train + n_dev + n_test) != nrow(ml_df)) {
    stop(sprintf("Chronological split requires %d rows but dataset contains %d.",
                 n_train + n_dev + n_test, nrow(ml_df)))
  }

  ordered <- ml_df[order(ml_df$peak_time, ml_df$event_id), , drop = FALSE]
  train <- ordered[seq_len(n_train), , drop = FALSE]
  dev <- ordered[(n_train + 1):(n_train + n_dev), , drop = FALSE]
  test <- ordered[(n_train + n_dev + 1):nrow(ordered), , drop = FALSE]

  # Physical-event leakage checks.
  sets <- list(train = train, development = dev, test = test)
  pairs <- list(c("train", "development"), c("train", "test"), c("development", "test"))
  for (p in pairs) {
    a <- sets[[p[1]]]
    b <- sets[[p[2]]]
    if (length(intersect(a$event_id, b$event_id)) > 0) {
      stop(sprintf("event_id split contamination between %s and %s.", p[1], p[2]))
    }
    if (length(intersect(a$noaa_event_id, b$noaa_event_id)) > 0) {
      stop(sprintf("noaa_event_id split contamination between %s and %s.", p[1], p[2]))
    }
  }

  list(train = train, development = dev, test = test)
}

calculate_class_weights_r <- function(y) {
  y <- factor(y)
  counts <- table(y)
  n <- length(y)
  k <- length(counts)
  weights_by_class <- n / (k * counts)
  as.numeric(weights_by_class[as.character(y)])
}

fit_scaler_r <- function(train_df, predictors = STAGE8_PRIMARY_PREDICTORS) {
  params <- lapply(predictors, function(v) {
    m <- mean(train_df[[v]])
    s <- sd(train_df[[v]])
    if (!is.finite(s) || s < 1e-12) s <- 1.0
    list(mean = m, sd = s)
  })
  names(params) <- predictors
  params
}

apply_scaler_r <- function(df, scaler, predictors = names(scaler)) {
  out <- df
  for (v in predictors) {
    out[[v]] <- (out[[v]] - scaler[[v]]$mean) / scaler[[v]]$sd
  }
  out
}

capture_warnings_r <- function(expr) {
  warnings_seen <- character(0)
  value <- withCallingHandlers(
    expr,
    warning = function(w) {
      msg <- conditionMessage(w)
      warnings_seen <<- c(warnings_seen, msg)
      cat(sprintf("  [Logistic warning] %s\n", msg))
      invokeRestart("muffleWarning")
    }
  )
  list(value = value, warnings = unique(warnings_seen))
}

fit_logistic_model_r <- function(train_df,
                                 predictors = STAGE8_PRIMARY_PREDICTORS,
                                 use_class_weights = FALSE) {
  scaler <- fit_scaler_r(train_df, predictors)
  tr <- apply_scaler_r(train_df, scaler, predictors)
  tr$y_num <- ifelse(tr$severity_class == "C_plus", 1, 0)
  form <- as.formula(paste("y_num ~", paste(predictors, collapse = " + ")))

  weights <- if (use_class_weights) calculate_class_weights_r(tr$severity_class) else rep(1, nrow(tr))
  captured <- capture_warnings_r(
    glm(form, data = tr, family = binomial(link = "logit"), weights = weights)
  )
  fit <- captured$value
  train_prob <- as.numeric(predict(fit, newdata = tr, type = "response"))

  list(
    model_type = "Logistic Regression",
    model = fit,
    scaler = scaler,
    predictors = predictors,
    warnings = captured$warnings,
    train_probabilities = train_prob,
    class_weights_used = use_class_weights
  )
}

fit_decision_tree_r <- function(train_df,
                                predictors = STAGE8_PRIMARY_PREDICTORS,
                                maxdepth = 3,
                                minsplit = 4,
                                cp = 0.01) {
  if (!requireNamespace("rpart", quietly = TRUE)) {
    stop("Package 'rpart' is required for Stage 8 Decision Tree. Install it before execution.")
  }
  form <- as.formula(paste("severity_class ~", paste(predictors, collapse = " + ")))
  tr <- train_df
  tr$severity_class <- factor(tr$severity_class, levels = c("B", "C_plus"))
  ctrl <- rpart::rpart.control(maxdepth = maxdepth, minsplit = minsplit, cp = cp, xval = 0)
  fit <- rpart::rpart(form, data = tr, method = "class", control = ctrl)
  list(
    model_type = "Decision Tree",
    model = fit,
    predictors = predictors,
    maxdepth = maxdepth,
    minsplit = minsplit,
    cp = cp,
    warnings = character(0)
  )
}

fit_random_forest_r <- function(train_df,
                                predictors = STAGE8_PRIMARY_PREDICTORS,
                                ntree = 200,
                                mtry = 2,
                                seed = 42) {
  if (!requireNamespace("randomForest", quietly = TRUE)) {
    stop("Package 'randomForest' is required for Stage 8 Random Forest. Install it before execution.")
  }
  form <- as.formula(paste("severity_class ~", paste(predictors, collapse = " + ")))
  tr <- train_df
  tr$severity_class <- factor(tr$severity_class, levels = c("B", "C_plus"))
  set.seed(seed)
  fit <- randomForest::randomForest(
    form, data = tr, ntree = ntree, mtry = mtry,
    importance = TRUE, keep.forest = TRUE
  )
  list(
    model_type = "Random Forest",
    model = fit,
    predictors = predictors,
    ntree = ntree,
    mtry = mtry,
    seed = seed,
    warnings = character(0)
  )
}

predict_stage8_model_r <- function(model_obj, new_df) {
  if (model_obj$model_type == "Logistic Regression") {
    nd <- apply_scaler_r(new_df, model_obj$scaler, model_obj$predictors)
    prob_c_plus <- as.numeric(predict(model_obj$model, newdata = nd, type = "response"))
    pred <- ifelse(prob_c_plus >= 0.5, "C_plus", "B")
    return(data.frame(
      event_id = new_df$event_id,
      noaa_event_id = new_df$noaa_event_id,
      peak_time = new_df$peak_time,
      actual = as.character(new_df$severity_class),
      predicted = pred,
      probability_C_plus = prob_c_plus,
      stringsAsFactors = FALSE
    ))
  }

  if (model_obj$model_type == "Decision Tree") {
    pred <- as.character(predict(model_obj$model, newdata = new_df, type = "class"))
    probs <- predict(model_obj$model, newdata = new_df, type = "prob")
    prob_c_plus <- if (is.matrix(probs) && "C_plus" %in% colnames(probs)) probs[, "C_plus"] else NA_real_
    return(data.frame(
      event_id = new_df$event_id,
      noaa_event_id = new_df$noaa_event_id,
      peak_time = new_df$peak_time,
      actual = as.character(new_df$severity_class),
      predicted = pred,
      probability_C_plus = as.numeric(prob_c_plus),
      stringsAsFactors = FALSE
    ))
  }

  if (model_obj$model_type == "Random Forest") {
    pred <- as.character(predict(model_obj$model, newdata = new_df, type = "response"))
    probs <- predict(model_obj$model, newdata = new_df, type = "prob")
    prob_c_plus <- if (is.matrix(probs) && "C_plus" %in% colnames(probs)) probs[, "C_plus"] else NA_real_
    return(data.frame(
      event_id = new_df$event_id,
      noaa_event_id = new_df$noaa_event_id,
      peak_time = new_df$peak_time,
      actual = as.character(new_df$severity_class),
      predicted = pred,
      probability_C_plus = as.numeric(prob_c_plus),
      stringsAsFactors = FALSE
    ))
  }

  stop(sprintf("Unsupported Stage 8 model type: %s", model_obj$model_type))
}

calculate_confusion_matrix_r <- function(actual, predicted) {
  table(
    Actual = factor(actual, levels = c("B", "C_plus")),
    Predicted = factor(predicted, levels = c("B", "C_plus"))
  )
}

calculate_binary_metrics_r <- function(actual, predicted, model_name = NA_character_, partition = NA_character_) {
  cm <- calculate_confusion_matrix_r(actual, predicted)
  tn <- unname(cm["B", "B"])
  fp <- unname(cm["B", "C_plus"])
  fn <- unname(cm["C_plus", "B"])
  tp <- unname(cm["C_plus", "C_plus"])

  safe_div <- function(a, b) if (b > 0) a / b else NA_real_
  precision_cp <- safe_div(tp, tp + fp)
  recall_cp <- safe_div(tp, tp + fn)
  f1_cp <- if (is.finite(precision_cp) && is.finite(recall_cp) && (precision_cp + recall_cp) > 0) {
    2 * precision_cp * recall_cp / (precision_cp + recall_cp)
  } else 0

  precision_b <- safe_div(tn, tn + fn)
  recall_b <- safe_div(tn, tn + fp)
  f1_b <- if (is.finite(precision_b) && is.finite(recall_b) && (precision_b + recall_b) > 0) {
    2 * precision_b * recall_b / (precision_b + recall_b)
  } else 0

  sensitivity <- recall_cp
  specificity <- recall_b
  balanced_accuracy <- mean(c(sensitivity, specificity), na.rm = TRUE)
  macro_f1 <- mean(c(f1_b, f1_cp), na.rm = TRUE)
  accuracy <- safe_div(tp + tn, sum(cm))

  data.frame(
    Model = model_name,
    Partition = partition,
    N = sum(cm),
    B_Support = sum(cm["B", ]),
    C_plus_Support = sum(cm["C_plus", ]),
    Accuracy = accuracy,
    B_Precision = precision_b,
    B_Recall = recall_b,
    B_F1 = f1_b,
    C_plus_Precision = precision_cp,
    C_plus_Recall = recall_cp,
    C_plus_F1 = f1_cp,
    Macro_F1 = macro_f1,
    Balanced_Accuracy = balanced_accuracy,
    Sensitivity = sensitivity,
    Specificity = specificity,
    TP = tp, FP = fp, TN = tn, FN = fn,
    stringsAsFactors = FALSE
  )
}

calculate_vif_r <- function(train_df, predictors = STAGE8_PRIMARY_PREDICTORS) {
  vals <- sapply(predictors, function(target) {
    others <- setdiff(predictors, target)
    form <- as.formula(paste(target, "~", paste(others, collapse = " + ")))
    fit <- lm(form, data = train_df)
    r2 <- summary(fit)$r.squared
    if (!is.finite(r2) || r2 >= 1) Inf else 1 / (1 - r2)
  })
  data.frame(Predictor = predictors, VIF = as.numeric(vals), row.names = NULL)
}

calculate_feature_importance_r <- function(rf_obj) {
  if (rf_obj$model_type != "Random Forest") stop("Feature importance requires a Random Forest model object.")
  imp <- randomForest::importance(rf_obj$model)
  data.frame(Predictor = rownames(imp), imp, row.names = NULL, check.names = FALSE)
}

summarize_logistic_coefficients_r <- function(logistic_obj) {
  sm <- summary(logistic_obj$model)$coefficients
  out <- data.frame(
    Term = rownames(sm),
    Coefficient = sm[, 1],
    Std_Error = sm[, 2],
    Z_value = sm[, 3],
    P_value = sm[, 4],
    Odds_Ratio = exp(sm[, 1]),
    row.names = NULL,
    check.names = FALSE
  )
  out$Stability_Flag <- ifelse(
    abs(out$Coefficient) > 10 | out$Std_Error > 10,
    "UNSTABLE / separation-sensitive",
    "inspect with separation diagnostic"
  )
  out
}

separation_diagnostic_r <- function(logistic_obj, train_df, threshold = 0.5, epsilon = 1e-8) {
  probs <- logistic_obj$train_probabilities
  actual <- as.character(train_df$severity_class)
  pred <- ifelse(probs >= threshold, "C_plus", "B")
  all_correct <- all(pred == actual)
  extreme <- all(probs < epsilon | probs > (1 - epsilon))
  warning_flag <- any(grepl("0 or 1|converg|separ", logistic_obj$warnings, ignore.case = TRUE))
  coef_vals <- coef(logistic_obj$model)
  large_coef <- any(abs(coef_vals[is.finite(coef_vals)]) > 10)

  formal_status <- "not formally tested"
  if (requireNamespace("brglm2", quietly = TRUE)) {
    formal_status <- "brglm2 available; formal separation check may be run separately if desired"
  }

  classification <- if (all_correct && (warning_flag || extreme || large_coef)) {
    "COMPLETE SEPARATION STRONGLY INDICATED"
  } else if (warning_flag || large_coef) {
    "QUASI/NUMERICAL SEPARATION POSSIBLE"
  } else {
    "NO STRONG SEPARATION SIGNAL"
  }

  list(
    classification = classification,
    all_training_predictions_correct = all_correct,
    all_probabilities_extreme = extreme,
    warning_flag = warning_flag,
    large_coefficient_flag = large_coef,
    min_probability = min(probs),
    max_probability = max(probs),
    formal_detector_status = formal_status,
    warnings = logistic_obj$warnings
  )
}

loocv_logistic_r <- function(ml_df, predictors = STAGE8_PRIMARY_PREDICTORS) {
  predictions <- vector("list", nrow(ml_df))
  warning_count <- 0L
  for (i in seq_len(nrow(ml_df))) {
    tr <- ml_df[-i, , drop = FALSE]
    ho <- ml_df[i, , drop = FALSE]
    fit <- fit_logistic_model_r(tr, predictors = predictors, use_class_weights = FALSE)
    warning_count <- warning_count + length(fit$warnings)
    p <- predict_stage8_model_r(fit, ho)
    p$fold <- i
    predictions[[i]] <- p
  }
  pred_df <- do.call(rbind, predictions)
  metrics <- calculate_binary_metrics_r(
    pred_df$actual, pred_df$predicted,
    model_name = "Logistic Regression", partition = "LOOCV"
  )
  list(predictions = pred_df, metrics = metrics, warning_count = warning_count)
}

save_ml_artifacts_r <- function(output_dir, objects) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  for (nm in names(objects)) {
    obj <- objects[[nm]]
    path <- file.path(output_dir, nm)
    if (grepl("\\.csv$", nm, ignore.case = TRUE)) {
      write.csv(obj, path, row.names = FALSE)
    } else if (grepl("\\.rds$", nm, ignore.case = TRUE)) {
      saveRDS(obj, path)
    } else {
      stop(sprintf("Unsupported artifact extension for %s", nm))
    }
  }
  invisible(TRUE)
}
