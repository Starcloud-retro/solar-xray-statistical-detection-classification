# ==============================================================================
# R/08_evaluation.R
# Decoupled Evaluation Module: Detector vs Classifier Validation
#
# Follows mandatory PBL requirements:
# 1. Evaluates detection (Problem A) separately from classification (Problem B).
# 2. Computes per-class Precision, Recall, F1, Macro F1, Overall Accuracy, and Confusion Matrix.
# 3. Formats results into publication-ready faculty tables.
# ==============================================================================

# 1. Classifier Evaluation Metrics
evaluate_classification_r <- function(actual, predicted, model_name = "Model") {
  cat(sprintf("\n[R Classifier Eval] Evaluating %s...\n", model_name))
  
  classes <- sort(unique(c(as.character(actual), as.character(predicted))))
  n_classes <- length(classes)
  
  # Confusion Matrix
  cm <- table(Factor_Actual = factor(actual, levels = classes),
              Factor_Predicted = factor(predicted, levels = classes))
  
  # Per-Class Metrics
  per_class <- list()
  precisions <- numeric(n_classes)
  recalls    <- numeric(n_classes)
  f1s        <- numeric(n_classes)
  supports   <- numeric(n_classes)
  
  for (k in seq_along(classes)) {
    cls <- classes[k]
    tp <- cm[cls, cls]
    fp <- sum(cm[, cls]) - tp
    fn <- sum(cm[cls, ]) - tp
    tn <- sum(cm) - tp - fp - fn
    
    prec <- if ((tp + fp) > 0) tp / (tp + fp) else 0.0
    rec  <- if ((tp + fn) > 0) tp / (tp + fn) else 0.0
    f1   <- if ((prec + rec) > 0) 2 * prec * rec / (prec + rec) else 0.0
    supp <- sum(actual == cls)
    
    precisions[k] <- prec
    recalls[k]    <- rec
    f1s[k]        <- f1
    supports[k]   <- supp
    
    per_class[[cls]] <- data.frame(
      Class = cls,
      TP = tp,
      FP = fp,
      FN = fn,
      TN = tn,
      Precision = prec,
      Recall = rec,
      F1_Score = f1,
      Support = supp,
      stringsAsFactors = FALSE
    )
  }
  
  per_class_df <- do.call(rbind, per_class)
  
  # Macro Metrics (Unweighted average across classes)
  macro_precision <- mean(precisions)
  macro_recall    <- mean(recalls)
  macro_f1        <- mean(f1s)
  
  # Overall Accuracy
  total_correct <- sum(diag(cm))
  total_samples <- length(actual)
  accuracy <- if (total_samples > 0) total_correct / total_samples else 0.0
  
  cat(sprintf("  Accuracy       : %.4f (%d / %d correct)\n", accuracy, total_correct, total_samples))
  cat(sprintf("  Macro Precision: %.4f\n", macro_precision))
  cat(sprintf("  Macro Recall   : %.4f\n", macro_recall))
  cat(sprintf("  Macro F1-Score : %.4f\n", macro_f1))
  
  return(list(
    model_name = model_name,
    confusion_matrix = cm,
    per_class = per_class_df,
    summary = data.frame(
      Model = model_name,
      Accuracy = accuracy,
      Macro_Precision = macro_precision,
      Macro_Recall = macro_recall,
      Macro_F1 = macro_f1,
      N_Test = total_samples,
      stringsAsFactors = FALSE
    )
  ))
}

# 2. Multi-Model Comparison Table
compare_models_r <- function(eval_results_list) {
  cat("\n[R Evaluation] Aggregating Supervised Classifier Comparison Table...\n")
  summaries <- lapply(eval_results_list, function(res) res$summary)
  comp_df <- do.call(rbind, summaries)
  
  cat("\n=========================================================================================\n")
  cat("  MODEL COMPARISON SUMMARY TABLE (Event-Level Leak-Free Evaluation)\n")
  cat("=========================================================================================\n")
  print(comp_df, row.names = FALSE)
  cat("=========================================================================================\n")
  return(comp_df)
}
