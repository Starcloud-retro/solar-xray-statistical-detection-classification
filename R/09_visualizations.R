# ==============================================================================
# R/09_visualizations.R
# Scientific Visualization Suite for Solar Activity Statistical Pipeline
#
# Generates publication-ready diagnostic figures answering key scientific questions:
# 1. Raw vs Cleaned X-ray time-series behavior & dynamic range.
# 2. Uncontaminated rolling baseline vs impulsive flare spikes.
# 3. Standard Z-score vs Robust Z-score behavior.
# 4. Sequential anomaly detections and segmented flare event bounds.
# 5. Alignment against official NOAA ground-truth records.
# 6. Flare class distribution & class imbalance.
# 7. Event-level physical feature distributions.
# 8. Decision Tree structure / decision boundaries.
# 9. Random Forest feature importance rankings.
# 10. Supervised classifier confusion matrices and performance comparisons.
# ==============================================================================

plot_pipeline_figures_r <- function(
    df_det,
    events,
    aligned_res,
    features_df,
    ml_eval_results,
    out_dir = "reports/figures"
) {
  cat(sprintf("\n[R Visualizations] Generating scientific diagnostic plots in %s...\n", out_dir))
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  
  # ----------------------------------------------------------------------------
  # FIG 1: Time Series & Uncontaminated Rolling Baseline
  # ----------------------------------------------------------------------------
  fig1_path <- file.path(out_dir, "r_fig1_rolling_baseline.png")
  png(fig1_path, width = 2400, height = 1400, res = 200)
  par(mfrow = c(2, 1), mar = c(4, 4.5, 3, 1), bg = "white")
  
  # Sample zoom window: first 1440 points (1 day) or active flare region
  sample_n <- min(nrow(df_det), 1440)
  sub_df <- df_det[1:sample_n, ]
  
  # Subplot A: Raw Flux vs Rolling Median Baseline
  plot(sub_df$time_tag, sub_df$flux_clean, type = "l", col = "black", lwd = 1.2,
       log = "y", xlab = "Time (UTC)", ylab = "Flux (W/m^2) [log-scale]",
       main = "GOES-18 0.1-0.8 nm Soft X-Ray Irradiance & Robust Rolling Baseline")
  grid()
  if ("rolling_median_30m" %in% names(sub_df)) {
    lines(sub_df$time_tag, 10^(sub_df$rolling_median_30m), col = "#0072B2", lwd = 2, lty = 2)
  }
  # Add NOAA Flare Severity Class Thresholds
  abline(h = 1e-6, col = "#E69F00", lty = 3, lwd = 1.5) # C-Class
  abline(h = 1e-5, col = "#D55E00", lty = 3, lwd = 1.5) # M-Class
  abline(h = 1e-4, col = "#CC79A7", lty = 3, lwd = 1.5) # X-Class
  legend("topright", legend = c("Cleaned Flux", "Rolling Median (30m)", "C-Class (1e-6)", "M-Class (1e-5)"),
         col = c("black", "#0072B2", "#E69F00", "#D55E00"), lty = c(1, 2, 3, 3), lwd = c(1.2, 2, 1.5, 1.5), bty = "n")
  
  # Subplot B: Robust Z-Score vs Standard Z-Score
  plot(sub_df$time_tag, sub_df$z_mad, type = "l", col = "#009E73", lwd = 1.5,
       xlab = "Time (UTC)", ylab = "Statistical Score (z)",
       main = "Statistical Anomaly Scores: Robust Z (MAD) vs Standard Z (SD)")
  grid()
  lines(sub_df$time_tag, sub_df$z_mean, col = "#D55E00", lwd = 1.2, lty = 2)
  abline(h = 3.0, col = "red", lty = 2, lwd = 1.5)
  legend("topleft", legend = c("Robust Z-Score (Single Scaled MAD)", "Standard Z-Score (Mean/SD)", "Detection Threshold (z=3)"),
         col = c("#009E73", "#D55E00", "red"), lty = c(1, 2, 2), lwd = c(1.5, 1.2, 1.5), bty = "n")
  
  dev.off()
  cat(sprintf("  Saved %s\n", fig1_path))
  
  # ----------------------------------------------------------------------------
  # FIG 2: Segmented Events & Ground-Truth NOAA Flares
  # ----------------------------------------------------------------------------
  fig2_path <- file.path(out_dir, "r_fig2_event_segmentation.png")
  png(fig2_path, width = 2400, height = 1200, res = 200)
  par(mar = c(4, 4.5, 3, 1), bg = "white")
  
  plot(df_det$time_tag, df_det$flux_clean, type = "l", col = "gray50", lwd = 1,
       log = "y", xlab = "Time (UTC)", ylab = "Flux (W/m^2) [log-scale]",
       main = "Detected & Segmented Solar Flare Events with Peak Markers")
  grid()
  
  # Overlay detected event intervals
  if (length(events) > 0) {
    for (ev in events) {
      rect(xleft = ev$start_time, ybottom = 1e-8, xright = ev$end_time, ytop = 1e-3,
           col = rgb(1, 0.8, 0, 0.25), border = "#E69F00", lty = 2)
      points(ev$peak_time, ev$peak_flux, pch = 17, col = "#D55E00", cex = 1.2)
    }
  }
  legend("topright", legend = c("Flux Time Series", "Segmented Flare Duration", "Detected Peak"),
         col = c("gray50", "#E69F00", "#D55E00"), pch = c(NA, 15, 17), lty = c(1, NA, NA), bty = "n")
  dev.off()
  cat(sprintf("  Saved %s\n", fig2_path))
  
  # ----------------------------------------------------------------------------
  # FIG 3: Official NOAA Flare Class Distribution & Imbalance
  # ----------------------------------------------------------------------------
  fig3_path <- file.path(out_dir, "r_fig3_class_distribution.png")
  png(fig3_path, width = 1800, height = 1200, res = 200)
  par(mar = c(4.5, 4.5, 3, 1), bg = "white")
  
  if ("noaa_class_letter" %in% names(aligned_res$aligned_table)) {
    matched_sub <- aligned_res$aligned_table[aligned_res$aligned_table$status == "MATCHED", ]
    class_tbl <- table(factor(matched_sub$noaa_class_letter, levels = c("B", "C", "M", "X")))
    bp <- barplot(class_tbl, col = c("#56B4E9", "#009E73", "#E69F00", "#D55E00"),
                  ylim = c(0, max(class_tbl, 1) * 1.3),
                  xlab = "Official NOAA Flare Class", ylab = "Number of Matched Events",
                  main = "Sample Support & Severe Class Imbalance (7-Day Sample)")
    text(bp, class_tbl + max(class_tbl, 1) * 0.05, labels = as.character(class_tbl), font = 2)
  }
  dev.off()
  cat(sprintf("  Saved %s\n", fig3_path))
  
  # ----------------------------------------------------------------------------
  # FIG 4: Feature Correlation & Association
  # ----------------------------------------------------------------------------
  fig4_path <- file.path(out_dir, "r_fig4_feature_distributions.png")
  png(fig4_path, width = 2200, height = 1400, res = 200)
  par(mfrow = c(2, 2), mar = c(4, 4.5, 3, 1), bg = "white")
  
  if (nrow(features_df) > 0) {
    # 1. Peak Flux vs Rise Slope
    plot(features_df$rise_slope, log10(features_df$peak_flux), pch = 19, col = "#0072B2",
         xlab = "Rise Slope (beta_1)", ylab = "Peak Flux [log10 W/m^2]",
         main = "Peak Flux vs Rate of Rise")
    grid()
    
    # 2. Duration Distribution
    hist(features_df$duration_min, col = "#F0E442", border = "gray30",
         xlab = "Event Duration (minutes)", main = "Distribution of Event Durations")
    
    # 3. Peak-to-Background Ratio vs Max Robust Z
    plot(features_df$max_z_mad, features_df$peak_to_bg_ratio, pch = 19, col = "#D55E00",
         xlab = "Max Robust Z-Score", ylab = "Peak / Background Flux Ratio",
         main = "Signal-to-Noise vs Robust Anomaly Statistic")
    grid()
    
    # 4. Rise vs Decay Duration (Asymmetry)
    plot(features_df$rise_duration_min, features_df$decay_duration_min, pch = 19, col = "#009E73",
         xlab = "Rise Duration (min)", ylab = "Decay Duration (min)",
         main = "Solar Flare Temporal Asymmetry")
    abline(0, 1, lty = 2, col = "red")
    grid()
  }
  dev.off()
  cat(sprintf("  Saved %s\n", fig4_path))
  
  # ----------------------------------------------------------------------------
  # FIG 5: Model Comparison & Metric Evaluation
  # ----------------------------------------------------------------------------
  if (!is.null(ml_eval_results) && length(ml_eval_results) > 0) {
    fig5_path <- file.path(out_dir, "r_fig5_classifier_comparison.png")
    png(fig5_path, width = 2000, height = 1200, res = 200)
    par(mar = c(5, 5, 3, 1), bg = "white")
    
    models <- sapply(ml_eval_results, function(r) r$model_name)
    accs   <- sapply(ml_eval_results, function(r) r$summary$Accuracy)
    mf1s   <- sapply(ml_eval_results, function(r) r$summary$Macro_F1)
    
    mat <- rbind(Accuracy = accs, Macro_F1 = mf1s)
    bp <- barplot(mat, beside = TRUE, col = c("#0072B2", "#D55E00"),
                  ylim = c(0, 1.2), names.arg = models,
                  ylab = "Metric Value", main = "Supervised Classifier Comparison (Event-Level Test Set)")
    legend("topright", legend = c("Overall Accuracy", "Macro F1-Score"),
           fill = c("#0072B2", "#D55E00"), bty = "n")
    grid(nx = NA, ny = NULL)
    dev.off()
    cat(sprintf("  Saved %s\n", fig5_path))
  }
  
  cat("All scientific figures generated successfully.\n")
  return(TRUE)
}
