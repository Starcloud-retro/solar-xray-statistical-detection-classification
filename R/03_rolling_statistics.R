# ==============================================================================
# R/03_rolling_statistics.R
# Rolling Baseline Estimators, Robust Scale, and Local Slope Analysis
#
# Implements:
# 1. Trailing rolling mean (local background)
# 2. Trailing rolling standard deviation (local variability)
# 3. Trailing rolling median (robust baseline)
# 4. Trailing rolling MAD (raw and 1.4826 scaled)
# 5. Rate of change: ROC_t = (x_t - x_{t-1}) / Delta t
# 6. Local linear slope (beta_1 over trailing window)
#
# UNCONTAMINATED BASELINE RULE:
# When `uncontaminated = TRUE`, baseline at time t uses observations [t-W, ..., t-1].
# This prevents an impulsive flare eruption at time t from corrupting its own background reference.
# ==============================================================================

source("R/01_stats_primitives.R")

# Efficient rolling window calculation without requiring heavy external packages
# Supports NA handling, min_periods, and lag shift for uncontaminated baselines
compute_rolling_statistics_r <- function(
    df,
    window_mins = 30,
    min_periods = 5,
    uncontaminated = TRUE,
    slope_window_mins = 5
) {
  cat(sprintf("\n[R Rolling Stats] Computing rolling measures (W = %d mins, uncontaminated = %s)...\n",
              window_mins, as.character(uncontaminated)))
  
  df_out <- df
  n <- nrow(df_out)
  log_flux <- df_out$log10_flux_clean
  raw_flux <- df_out$flux_clean
  
  # Lag input vector by 1 if uncontaminated
  if (uncontaminated) {
    base_log_flux <- c(NA_real_, log_flux[1:(n - 1)])
  } else {
    base_log_flux <- log_flux
  }
  
  # Pre-allocate output vectors
  roll_mean <- rep(NA_real_, n)
  roll_std  <- rep(NA_real_, n)
  roll_med  <- rep(NA_real_, n)
  roll_mad_raw <- rep(NA_real_, n)
  roll_mad_scaled <- rep(NA_real_, n)
  roll_q05  <- rep(NA_real_, n)
  roll_q95  <- rep(NA_real_, n)
  
  # Compute rolling statistics
  # Window at index i covers indices max(1, i - window_mins + 1) : i
  for (i in seq_len(n)) {
    start_idx <- max(1, i - window_mins + 1)
    win_vals <- base_log_flux[start_idx:i]
    valid_vals <- win_vals[!is.na(win_vals) & !is.nan(win_vals) & !is.infinite(win_vals)]
    
    if (length(valid_vals) >= min_periods) {
      m_val <- calculate_mean(valid_vals)
      roll_mean[i] <- m_val
      if (length(valid_vals) > 1) {
        roll_std[i] <- calculate_std(valid_vals, ddof = 1)
      }
      med_val <- calculate_median(valid_vals)
      roll_med[i] <- med_val
      
      # Single-scaled MAD
      raw_mad <- calculate_mad_raw(valid_vals)
      roll_mad_raw[i] <- raw_mad
      roll_mad_scaled[i] <- 1.4826 * raw_mad
      
      roll_q05[i] <- calculate_quantile(valid_vals, 0.05)
      roll_q95[i] <- calculate_quantile(valid_vals, 0.95)
    }
  }
  
  # Assign to dataframe with explicit window naming
  w_str <- sprintf("%dm", window_mins)
  df_out[[paste0("rolling_mean_", w_str)]] <- roll_mean
  df_out[[paste0("rolling_std_", w_str)]]  <- roll_std
  df_out[[paste0("rolling_median_", w_str)]] <- roll_med
  df_out[[paste0("rolling_mad_raw_", w_str)]] <- roll_mad_raw
  df_out[[paste0("rolling_mad_scaled_", w_str)]] <- roll_mad_scaled
  df_out[[paste0("rolling_q05_", w_str)]]  <- roll_q05
  df_out[[paste0("rolling_q95_", w_str)]]  <- roll_q95
  
  # Rate of change: first differences in log10 and raw flux
  df_out$roc_log <- c(NA_real_, diff(log_flux))
  df_out$roc_raw <- c(NA_real_, diff(raw_flux))
  
  # Percentage change on raw flux
  pct_chg <- rep(NA_real_, n)
  valid_lag <- raw_flux[1:(n - 1)]
  non_zero <- !is.na(valid_lag) & valid_lag > 0
  pct_chg[-1][non_zero] <- ((raw_flux[-1][non_zero] - valid_lag[non_zero]) / valid_lag[non_zero]) * 100
  df_out$pct_change_raw <- pct_chg
  
  # Local linear slope (beta_1 over slope_window_mins trailing points)
  cat(sprintf("  Computing local linear slope over %d-min trailing window...\n", slope_window_mins))
  local_slope <- rep(NA_real_, n)
  t_vec <- seq_len(slope_window_mins) - 1  # 0, 1, ..., W-1
  t_mean <- mean(t_vec)
  t_var <- sum((t_vec - t_mean)^2)
  
  for (i in slope_window_mins:n) {
    y_win <- log_flux[(i - slope_window_mins + 1):i]
    if (!any(is.na(y_win))) {
      # Analytical ordinary least squares slope: beta_1 = sum((t - t_bar)(y - y_bar)) / sum((t - t_bar)^2)
      slope_val <- sum((t_vec - t_mean) * (y_win - mean(y_win))) / t_var
      local_slope[i] <- slope_val
    }
  }
  df_out[[sprintf("local_slope_%dm", slope_window_mins)]] <- local_slope
  
  cat("  Rolling calculations completed.\n")
  return(df_out)
}
