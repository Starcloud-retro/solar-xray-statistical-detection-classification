# ==============================================================================
# R/04_event_detection.R
# Sequential Statistical Anomaly Detection & Deterministic Event Segmentation
#
# Implements:
# 1. Standard Z-score: z_t = (x_t - mu_{t-1}) / sigma_{t-1}
# 2. Robust Z-score: z_robust = (x_t - median_{t-1}) / MAD_scaled_{t-1}
# 3. Rate of change (ROC) & local slope thresholding
# 4. Multi-condition voting & persistence filtering
# 5. Deterministic event segmentation and boundary extraction (start, peak, end)
# 6. Deterministic event merging for contiguous / overlapping triggers
# ==============================================================================

source("R/01_stats_primitives.R")

# 1. Point-wise Statistical Anomaly Scoring
compute_detection_scores_r <- function(
    df,
    window_mins = 30,
    uncontaminated = TRUE
) {
  df_det <- df
  w_str <- sprintf("%dm", window_mins)
  
  # Ensure rolling stats are present
  mean_col <- paste0("rolling_mean_", w_str)
  std_col  <- paste0("rolling_std_", w_str)
  med_col  <- paste0("rolling_median_", w_str)
  mad_col  <- paste0("rolling_mad_scaled_", w_str)
  
  if (!mean_col %in% names(df_det)) {
    source("R/03_rolling_statistics.R")
    df_det <- compute_rolling_statistics_r(df_det, window_mins = window_mins, uncontaminated = uncontaminated)
  }
  
  # Standard Z-score
  df_det$z_mean <- (df_det$log10_flux_clean - df_det[[mean_col]]) / df_det[[std_col]]
  
  # Robust Z-score (Single 1.4826 scaled MAD)
  df_det$z_mad <- (df_det$log10_flux_clean - df_det[[med_col]]) / df_det[[mad_col]]
  
  # Rate of change
  if (!"roc_log" %in% names(df_det)) {
    df_det$roc_log <- c(NA_real_, diff(df_det$log10_flux_clean))
  }
  
  return(df_det)
}

# 2. Apply Persistence Filter
# A point is detected only if it belongs to a run of at least `min_len` consecutive True points
apply_persistence_filter_r <- function(mask, min_len = 3) {
  n <- length(mask)
  if (min_len <= 1) return(mask)
  
  # Convert NA to FALSE
  mask_clean <- mask
  mask_clean[is.na(mask_clean)] <- FALSE
  
  pers_mask <- rep(FALSE, n)
  rle_res <- rle(mask_clean)
  
  idx <- 1
  for (k in seq_along(rle_res$lengths)) {
    run_len <- rle_res$lengths[k]
    run_val <- rle_res$values[k]
    end_idx <- idx + run_len - 1
    if (run_val && run_len >= min_len) {
      pers_mask[idx:end_idx] <- TRUE
    }
    idx <- end_idx + 1
  }
  return(pers_mask)
}

# 3. Detect Anomalies (Multi-Cue Sequential Decision)
detect_anomalies_r <- function(
    df,
    z_mean_thr = 3.0,
    z_mad_thr = 3.0,
    roc_thr = 0.05,
    min_len = 3,
    window_mins = 30,
    uncontaminated = TRUE
) {
  df_det <- compute_detection_scores_r(df, window_mins = window_mins, uncontaminated = uncontaminated)
  
  # Raw individual triggers
  mask_z_mean <- !is.na(df_det$z_mean) & (df_det$z_mean > z_mean_thr)
  mask_z_mad  <- !is.na(df_det$z_mad)  & (df_det$z_mad  > z_mad_thr)
  mask_roc    <- !is.na(df_det$roc_log) & (df_det$roc_log > roc_thr)
  
  # Apply persistence to each cue
  pers_z_mean <- apply_persistence_filter_r(mask_z_mean, min_len = min_len)
  pers_z_mad  <- apply_persistence_filter_r(mask_z_mad, min_len = min_len)
  pers_roc    <- apply_persistence_filter_r(mask_roc, min_len = min_len)
  
  # Multi-cue OR combination
  df_det$detected <- pers_z_mean | pers_z_mad | pers_roc
  
  # Store configuration metadata
  attr(df_det, "detector_config") <- list(
    z_mean_thr = z_mean_thr,
    z_mad_thr = z_mad_thr,
    roc_thr = roc_thr,
    min_len = min_len,
    window_mins = window_mins,
    uncontaminated = uncontaminated
  )
  
  return(df_det)
}

# 4. Event Segmentation: Convert point-wise boolean series into discrete event candidates
segment_events_r <- function(df_det, max_allowed_gap_mins = 2) {
  cat("[R Event Segmentation] Extracting discrete solar event candidates...\n")
  flag <- df_det$detected
  n <- nrow(df_det)
  
  events <- list()
  in_event <- FALSE
  start_idx <- NA_integer_
  
  for (i in seq_len(n)) {
    val <- flag[i]
    if (!is.na(val) && val && !in_event) {
      in_event <- TRUE
      start_idx <- i
    } else if ((is.na(val) || !val) && in_event) {
      end_idx <- i - 1
      # Extract candidate segment
      seg <- df_det[start_idx:end_idx, ]
      peak_rel_idx <- which.max(seg$flux_clean)
      peak_idx <- start_idx + peak_rel_idx - 1
      
      start_time <- df_det$time_tag[start_idx]
      end_time   <- df_det$time_tag[end_idx]
      peak_time  <- df_det$time_tag[peak_idx]
      duration_min <- as.numeric(difftime(end_time, start_time, units = "mins"))
      
      events[[length(events) + 1]] <- list(
        start_idx = start_idx,
        end_idx = end_idx,
        peak_idx = peak_idx,
        start_time = start_time,
        peak_time = peak_time,
        end_time = end_time,
        duration_min = duration_min,
        peak_flux = df_det$flux_clean[peak_idx],
        peak_log_flux = df_det$log10_flux_clean[peak_idx],
        n_points = end_idx - start_idx + 1
      )
      in_event <- FALSE
    }
  }
  
  # If trailing event reaches end of dataset
  if (in_event) {
    end_idx <- n
    seg <- df_det[start_idx:end_idx, ]
    peak_rel_idx <- which.max(seg$flux_clean)
    peak_idx <- start_idx + peak_rel_idx - 1
    
    events[[length(events) + 1]] <- list(
      start_idx = start_idx,
      end_idx = end_idx,
      peak_idx = peak_idx,
      start_time = df_det$time_tag[start_idx],
      peak_time = df_det$time_tag[peak_idx],
      end_time = df_det$time_tag[end_idx],
      duration_min = as.numeric(difftime(df_det$time_tag[end_idx], df_det$time_tag[start_idx], units = "mins")),
      peak_flux = df_det$flux_clean[peak_idx],
      peak_log_flux = df_det$log10_flux_clean[peak_idx],
      n_points = end_idx - start_idx + 1
    )
  }
  
  cat(sprintf("  Extracted %d initial segmented event candidates.\n", length(events)))
  return(events)
}

# 5. Merge Overlapping or Closely Spaced Events
merge_overlapping_events_r <- function(events, max_gap_mins = 2) {
  if (length(events) <= 1) return(events)
  
  # Sort events by start time
  start_times <- sapply(events, function(e) as.numeric(e$start_time))
  events <- events[order(start_times)]
  
  merged <- list(events[[1]])
  
  for (i in 2:length(events)) {
    curr <- events[[i]]
    last <- merged[[length(merged)]]
    
    gap_mins <- as.numeric(difftime(curr$start_time, last$end_time, units = "mins"))
    
    # Overlap or gap <= max_gap_mins
    if (curr$start_time <= last$end_time || gap_mins <= max_gap_mins) {
      # Merge: update end time and check if peak is higher
      new_end_time <- max(last$end_time, curr$end_time)
      new_end_idx <- max(last$end_idx, curr$end_idx)
      
      if (curr$peak_flux > last$peak_flux) {
        new_peak_time <- curr$peak_time
        new_peak_flux <- curr$peak_flux
        new_peak_log_flux <- curr$peak_log_flux
        new_peak_idx <- curr$peak_idx
      } else {
        new_peak_time <- last$peak_time
        new_peak_flux <- last$peak_flux
        new_peak_log_flux <- last$peak_log_flux
        new_peak_idx <- last$peak_idx
      }
      
      merged[[length(merged)]] <- list(
        start_idx = last$start_idx,
        end_idx = new_end_idx,
        peak_idx = new_peak_idx,
        start_time = last$start_time,
        peak_time = new_peak_time,
        end_time = new_end_time,
        duration_min = as.numeric(difftime(new_end_time, last$start_time, units = "mins")),
        peak_flux = new_peak_flux,
        peak_log_flux = new_peak_log_flux,
        n_points = new_end_idx - last$start_idx + 1
      )
    } else {
      merged[[length(merged) + 1]] <- curr
    }
  }
  
  # Assign unique event_id to each merged event
  for (k in seq_along(merged)) {
    merged[[k]]$event_id <- sprintf("EVT_%04d", k)
  }
  
  cat(sprintf("  Merged into %d consolidated event candidates.\n", length(merged)))
  return(merged)
}
