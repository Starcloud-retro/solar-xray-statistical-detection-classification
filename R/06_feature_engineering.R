# ==============================================================================
# R/06_feature_engineering.R
# Event-Level Feature Engineering with Explicit Temporal Availability Tagging
#
# Prevents data leakage and ensures physical interpretability.
# Supports two distinct operational ML problem definitions:
# 1. POST-EVENT CLASSIFICATION: Utilizes complete event profile (rise, peak, decay, full duration).
# 2. IN-PROGRESS NOWCASTING: Utilizes strictly features available at peak time t_peak (rise phase only).
#
# Each feature row represents exactly ONE discrete event candidate.
# Target-derived features are strictly excluded to prevent label contamination.
# ==============================================================================

source("R/01_stats_primitives.R")

# ------------------------------------------------------------------------------
# Peak-time ROC helpers
# Primary nowcasting ROC features MUST use only observations in [t_start, t_peak].
# Undefined statistics remain NA_real_; they are never silently replaced by zero.
# ------------------------------------------------------------------------------
calculate_rise_roc_features_r <- function(rise_df) {
  if (!"roc_log" %in% names(rise_df)) {
    stop("rise_df must contain a 'roc_log' column.")
  }

  valid_roc <- rise_df$roc_log[
    !is.na(rise_df$roc_log) &
    !is.nan(rise_df$roc_log) &
    !is.infinite(rise_df$roc_log)
  ]

  max_roc <- if (length(valid_roc) > 0) max(valid_roc) else NA_real_

  positive_roc <- valid_roc[valid_roc > 0]
  mean_pos_roc <- if (length(positive_roc) > 0) mean(positive_roc) else NA_real_

  list(
    max_roc = max_roc,
    mean_pos_roc = mean_pos_roc
  )
}

# Deterministic unit-style diagnostics proving that post-peak ROC values cannot
# influence the two primary ROC predictors. These tests do not use project data.
run_temporal_roc_scope_tests_r <- function(verbose = TRUE) {
  assert_equal_num <- function(actual, expected, label, tol = 1e-12) {
    ok <- if (is.na(expected)) is.na(actual) else isTRUE(all.equal(actual, expected, tolerance = tol))
    if (!ok) {
      stop(sprintf("Temporal ROC scope test FAILED [%s]: actual=%s expected=%s",
                   label, as.character(actual), as.character(expected)))
    }
    if (verbose) cat(sprintf("  [PASS] %s\n", label))
  }

  if (verbose) cat("\n[Temporal ROC Scope Tests] START -> PEAK only\n")

  # 1. Normal event with rise and decay.
  rise_1 <- data.frame(roc_log = c(NA, 0.10, 0.20, 0.05))
  full_1 <- data.frame(roc_log = c(rise_1$roc_log, -0.04, -0.02))
  r1 <- calculate_rise_roc_features_r(rise_1)
  assert_equal_num(r1$max_roc, 0.20, "normal event max_roc")
  assert_equal_num(r1$mean_pos_roc, mean(c(0.10, 0.20, 0.05)), "normal event mean_pos_roc")

  # 2. Decay contains a larger positive ROC. It MUST NOT alter either feature.
  rise_2 <- data.frame(roc_log = c(NA, 0.08, 0.12, 0.04))
  post_peak_2 <- c(-0.03, 0.90, 0.40)
  full_2 <- data.frame(roc_log = c(rise_2$roc_log, post_peak_2))
  r2 <- calculate_rise_roc_features_r(rise_2)
  assert_equal_num(r2$max_roc, 0.12, "decay maximum cannot affect max_roc")
  assert_equal_num(r2$mean_pos_roc, mean(c(0.08, 0.12, 0.04)), "post-peak positives cannot affect mean_pos_roc")
  if (max(full_2$roc_log, na.rm = TRUE) == r2$max_roc) {
    stop("Temporal ROC scope test FAILED: decay contamination test was not discriminative.")
  }

  # 3. No valid positive rise ROC: max remains mathematically defined, mean positive is undefined.
  rise_3 <- data.frame(roc_log = c(NA, -0.10, 0.00, -0.02))
  r3 <- calculate_rise_roc_features_r(rise_3)
  assert_equal_num(r3$max_roc, 0.00, "non-positive rise max_roc")
  assert_equal_num(r3$mean_pos_roc, NA_real_, "no positive rise ROC -> mean_pos_roc NA")

  # 4. NA/NaN/Inf values are excluded; finite rise values alone define the features.
  rise_4 <- data.frame(roc_log = c(NA_real_, NaN, Inf, -Inf, 0.03, 0.09))
  r4 <- calculate_rise_roc_features_r(rise_4)
  assert_equal_num(r4$max_roc, 0.09, "NA/NaN/Inf filtered for max_roc")
  assert_equal_num(r4$mean_pos_roc, 0.06, "NA/NaN/Inf filtered for mean_pos_roc")

  # Additional empty/fully invalid guard: both statistics are undefined.
  rise_5 <- data.frame(roc_log = c(NA_real_, NaN, Inf, -Inf))
  r5 <- calculate_rise_roc_features_r(rise_5)
  assert_equal_num(r5$max_roc, NA_real_, "no finite rise ROC -> max_roc NA")
  assert_equal_num(r5$mean_pos_roc, NA_real_, "no finite positive rise ROC -> mean_pos_roc NA")

  if (verbose) cat("  [PASS] Post-peak ROC cannot influence primary ROC predictors.\n")
  invisible(TRUE)
}

extract_event_features_r <- function(
    df_det,
    events,
    baseline_window_mins = 30
) {
  cat(sprintf("\n[R Feature Engineering] Extracting physical & statistical features for %d events...\n", length(events)))
  
  if (length(events) == 0) {
    return(data.frame())
  }

  # Prove the peak-time ROC temporal contract before extracting project features.
  run_temporal_roc_scope_tests_r(verbose = TRUE)
  
  feature_rows <- list()
  
  for (i in seq_along(events)) {
    ev <- events[[i]]
    s_idx <- ev$start_idx
    p_idx <- ev$peak_idx
    e_idx <- ev$end_idx
    
    # Event slice
    ev_df <- df_det[s_idx:e_idx, ]
    rise_df <- df_det[s_idx:p_idx, ]
    decay_df <- if (p_idx < e_idx) df_det[(p_idx + 1):e_idx, ] else data.frame()
    
    # Pre-event background baseline: strictly prior to start_idx (uncontaminated)
    base_start_idx <- max(1, s_idx - baseline_window_mins)
    base_end_idx   <- max(1, s_idx - 1)
    
    if (base_end_idx >= base_start_idx) {
      base_fluxes <- df_det$flux_clean[base_start_idx:base_end_idx]
      base_fluxes <- base_fluxes[!is.na(base_fluxes)]
      bg_flux <- if (length(base_fluxes) > 0) calculate_median(base_fluxes) else df_det$flux_clean[s_idx]
      bg_mad  <- if (length(base_fluxes) > 0) calculate_mad_scaled(base_fluxes) else 1e-9
    } else {
      bg_flux <- df_det$flux_clean[s_idx]
      bg_mad  <- 1e-9
    }
    
    # Check if any interpolated data points exist in this event
    has_interp <- FALSE
    if ("is_interpolated" %in% names(ev_df)) {
      has_interp <- any(ev_df$is_interpolated, na.rm = TRUE)
    }
    
    # --- 1. MAGNITUDE FEATURES ---
    peak_flux   <- ev$peak_flux
    mean_flux   <- calculate_mean(ev_df$flux_clean)
    median_flux <- calculate_median(ev_df$flux_clean)
    excess_flux <- max(0, peak_flux - bg_flux)
    peak_to_bg_ratio <- if (bg_flux > 0) peak_flux / bg_flux else NA_real_
    
    # --- 2. DISPERSION FEATURES ---
    std_flux <- if (nrow(ev_df) > 1) calculate_std(ev_df$flux_clean, ddof = 1) else 0.0
    var_flux <- if (nrow(ev_df) > 1) calculate_variance(ev_df$flux_clean, ddof = 1) else 0.0
    mad_flux <- calculate_mad_scaled(ev_df$flux_clean)
    iqr_flux <- calculate_iqr(ev_df$flux_clean)
    
    # --- 3. TEMPORAL / MORPHOLOGY FEATURES ---
    duration_min <- ev$duration_min
    rise_duration_min <- as.numeric(difftime(ev$peak_time, ev$start_time, units = "mins"))
    decay_duration_min <- as.numeric(difftime(ev$end_time, ev$peak_time, units = "mins"))
    # Peak location ratio: 0.0 = peak at start, 1.0 = peak at end
    peak_location_ratio <- if (duration_min > 0) rise_duration_min / duration_min else 0.5
    # Asymmetry ratio: rise / decay
    asymmetry_ratio <- if (decay_duration_min > 0) rise_duration_min / decay_duration_min else NA_real_
    
    # --- 4. RATE OF CHANGE & LOCAL SLOPE FEATURES ---
    # CRITICAL TEMPORAL CONTRACT for primary nowcasting at t_pred = t_peak:
    # max_roc and mean_pos_roc use ONLY the rise interval [start_idx, peak_idx].
    # Post-peak observations (peak_idx + 1 : end_idx) are excluded by construction.
    rise_roc_features <- calculate_rise_roc_features_r(rise_df)
    max_roc <- rise_roc_features$max_roc
    mean_pos_roc <- rise_roc_features$mean_pos_roc
    
    # Rise slope (OLS slope during rise phase)
    rise_slope <- if (nrow(rise_df) >= 2) {
      t_r <- seq_len(nrow(rise_df)) - 1
      cov(t_r, rise_df$log10_flux_clean) / var(t_r)
    } else 0.0
    
    # Decay slope (OLS slope during decay phase)
    decay_slope <- if (nrow(decay_df) >= 2) {
      t_d <- seq_len(nrow(decay_df)) - 1
      cov(t_d, decay_df$log10_flux_clean) / var(t_d)
    } else 0.0
    
    # --- 5. STATISTICAL ANOMALY FEATURES ---
    # Safe extraction: if all points in slice lack valid rolling baseline (e.g. eclipse dropouts),
    # statistic is mathematically undefined (NA_real_), NOT -Inf.
    valid_z_mean <- ev_df$z_mean[!is.na(ev_df$z_mean) & !is.nan(ev_df$z_mean) & !is.infinite(ev_df$z_mean)]
    max_z_mean <- if (length(valid_z_mean) > 0) max(valid_z_mean) else NA_real_
    
    valid_z_mad <- ev_df$z_mad[!is.na(ev_df$z_mad) & !is.nan(ev_df$z_mad) & !is.infinite(ev_df$z_mad)]
    max_z_mad <- if (length(valid_z_mad) > 0) max(valid_z_mad) else NA_real_
    
    persistence_points <- ev$n_points
    
    feature_rows[[i]] <- data.frame(
      event_id = ev$event_id,
      start_time = ev$start_time,
      peak_time = ev$peak_time,
      end_time = ev$end_time,
      has_interpolated_points = has_interp,
      
      # Nowcasting Features (Available strictly at or before t_peak):
      bg_flux = bg_flux,
      peak_flux = peak_flux,
      peak_to_bg_ratio = peak_to_bg_ratio,
      excess_flux = excess_flux,
      rise_duration_min = rise_duration_min,
      rise_slope = rise_slope,
      max_roc = max_roc,
      mean_pos_roc = mean_pos_roc,
      max_z_mean = max_z_mean,
      max_z_mad = max_z_mad,
      
      # Post-Event Features (Available strictly after event termination t_end):
      duration_min = duration_min,
      decay_duration_min = decay_duration_min,
      decay_slope = decay_slope,
      peak_location_ratio = peak_location_ratio,
      asymmetry_ratio = asymmetry_ratio,
      mean_flux = mean_flux,
      median_flux = median_flux,
      std_flux = std_flux,
      mad_flux = mad_flux,
      iqr_flux = iqr_flux,
      persistence_points = persistence_points,
      
      stringsAsFactors = FALSE
    )
  }
  
  feature_df <- do.call(rbind, feature_rows)
  cat(sprintf("  Extracted %d feature columns across %d event candidates.\n", ncol(feature_df), nrow(feature_df)))
  
  # Execute automated numerical integrity validation
  validate_feature_matrix_r(feature_df)
  
  return(feature_df)
}

# Automated Validation of Feature Matrix Numerical Integrity (Phase 7A)
validate_feature_matrix_r <- function(df) {
  cat("\n[Feature Validation] Auditing numerical integrity of feature matrix...\n")
  has_inf <- FALSE
  has_nan <- FALSE
  
  for (col in names(df)) {
    vals <- df[[col]]
    if (is.numeric(vals)) {
      n_inf <- sum(is.infinite(vals))
      n_nan <- sum(is.nan(vals))
      n_na  <- sum(is.na(vals) & !is.nan(vals))
      
      if (n_inf > 0) {
        cat(sprintf("  [ERROR] Column '%s' contains %d infinite (-Inf/Inf) values!\n", col, n_inf))
        has_inf <- TRUE
      }
      if (n_nan > 0) {
        cat(sprintf("  [ERROR] Column '%s' contains %d NaN values!\n", col, n_nan))
        has_nan <- TRUE
      }
      if (n_na > 0) {
        cat(sprintf("  [DOCUMENTED NA] Column '%s': %d NA values (mathematically undefined, e.g. decay=0).\n", col, n_na))
      }
    }
  }
  
  if (has_inf || has_nan) {
    stop("Feature matrix numerical integrity validation FAILED: contains Inf or NaN.")
  }
  cat("  [PASS] Feature matrix numerical integrity: zero Inf, zero NaN.\n")
  return(TRUE)
}
