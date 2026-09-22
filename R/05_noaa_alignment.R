# ==============================================================================
# R/05_noaa_alignment.R
# Scientific Alignment Between Detected Solar Events and Official NOAA Flare Records
#
# Academic PBL: Statistical Detection & Classification of Solar Activity
#
# Follows strict scientific validation & reproducibility rules:
# 1. Official NOAA event catalog is ingested without fabrication.
# 2. Configurable alignment tolerances for peak time and interval overlap.
# 3. Explicit tracking of:
#    - Matched events (True Positives) with timing errors |t_peak - t_noaa_peak|.
#    - Unmatched detected events (False Positives).
#    - Unmatched NOAA flare records (False Negatives / Missed events).
#    - Ambiguous matches (multiple candidates overlapping).
#    - Skipped invalid records with explicit diagnostic reasons.
# 4. Official flare class (B, C, M, X) assigned strictly from verified NOAA records.
# 5. Guaranteed pure Boolean comparisons: prevents logical NA evaluation in matching.
# ==============================================================================

# Helper: Robust ISO-8601 UTC Timestamp Parser
parse_utc_timestamp <- function(ts) {
  if (is.null(ts) || length(ts) == 0) return(as.POSIXct(character(0), tz = "UTC"))
  if (inherits(ts, "POSIXct")) {
    return(as.POSIXct(format(ts, "%Y-%m-%d %H:%M:%S", tz = "UTC"), tz = "UTC"))
  }
  if (is.numeric(ts)) {
    # Assume POSIX seconds epoch
    return(as.POSIXct(ts, origin = "1970-01-01", tz = "UTC"))
  }
  ts_chr <- as.character(ts)
  # Standardize formats: replace T with space, strip trailing Z
  ts_clean <- gsub("T", " ", ts_chr)
  ts_clean <- gsub("Z$", "", ts_clean)
  parsed <- as.POSIXct(ts_clean, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
  
  # Fallback for date-only format %Y-%m-%d
  na_mask <- is.na(parsed) & !is.na(ts_chr) & (ts_chr != "")
  if (any(na_mask)) {
    parsed[na_mask] <- as.POSIXct(ts_clean[na_mask], format = "%Y-%m-%d", tz = "UTC")
  }
  return(parsed)
}

# 1. Ingest Official NOAA Flare Reports from Local JSON Archive
ingest_noaa_flares_r <- function(raw_dir = "data/raw") {
  flare_files <- list.files(raw_dir, pattern = "^goes_flare_report_raw_.*\\.json$", full.names = TRUE)
  if (length(flare_files) == 0) {
    warning("No NOAA flare report raw JSON files found in data/raw.")
    return(data.frame())
  }
  
  # Use most recent raw file by timestamp in filename
  latest_file <- sort(flare_files, decreasing = TRUE)[1]
  cat(sprintf("[R NOAA Alignment] Reading official NOAA flare catalog from %s...\n", latest_file))
  
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    flares_raw <- jsonlite::fromJSON(latest_file)
  } else {
    lines <- readLines(latest_file, warn = FALSE)
    flares_raw <- jsonlite::fromJSON(paste(lines, collapse = ""))
  }
  
  df_flares <- as.data.frame(flares_raw, stringsAsFactors = FALSE)
  n_raw_noaa <- nrow(df_flares)
  
  # Parse timestamps to UTC POSIXct
  df_flares$begin_time <- parse_utc_timestamp(df_flares$begin_time)
  df_flares$max_time   <- parse_utc_timestamp(df_flares$max_time)
  df_flares$end_time   <- parse_utc_timestamp(df_flares$end_time)
  
  # Track presence of peak: some official records (e.g. Record 13) are un-peaked enhancements
  df_flares$has_valid_peak <- !is.na(df_flares$max_time)
  
  # Clean flare classification string
  df_flares$max_class <- as.character(df_flares$max_class)
  df_flares$max_class[is.na(df_flares$max_class) | df_flares$max_class == ""] <- "Unspecified"
  
  # Extract primary letter class (A, B, C, M, X, or U for Unspecified)
  df_flares$flare_class_letter <- ifelse(
    df_flares$max_class == "Unspecified",
    "U",
    substr(df_flares$max_class, 1, 1)
  )
  
  df_flares$noaa_event_id <- sprintf("NOAA_%04d", seq_len(n_raw_noaa))
  
  cat(sprintf("  Loaded %d official NOAA flare events (%d with valid peak timestamps).\n",
              n_raw_noaa, sum(df_flares$has_valid_peak)))
  return(df_flares)
}

# 2. Align Detected Events with Official NOAA Records
align_events_with_noaa_r <- function(
    detected_events,
    df_flares,
    overlap_tolerance_mins = 5,
    max_peak_diff_mins = 15,
    matching_strategy = "interval_or_peak"  # options: 'interval_or_peak', 'interval_only', 'peak_proximity'
) {
  cat(sprintf("\n[R NOAA Alignment] Aligning %d detected events with %d NOAA flare records (Strategy: %s, Tol: %d min)...\n",
              length(detected_events), nrow(df_flares), matching_strategy, overlap_tolerance_mins))
  
  tol_secs <- overlap_tolerance_mins * 60
  
  # ----------------------------------------------------------------------------
  # STEP A: Input Validation & Sanitization of Detected Events
  # ----------------------------------------------------------------------------
  n_det_total <- length(detected_events)
  valid_det_events <- list()
  skipped_det_records <- list()
  
  if (n_det_total > 0) {
    for (i in seq_along(detected_events)) {
      ev <- detected_events[[i]]
      ev_id <- if (!is.null(ev$event_id) && !is.na(ev$event_id)) as.character(ev$event_id) else sprintf("EVT_%04d", i)
      
      # Parse timestamps to UTC
      t_start <- parse_utc_timestamp(ev$start_time)
      t_peak  <- parse_utc_timestamp(ev$peak_time)
      t_end   <- parse_utc_timestamp(ev$end_time)
      
      # Check invalid conditions
      skip_reason <- NULL
      if (length(t_start) == 0 || is.na(t_start)) {
        skip_reason <- "Missing or unparseable start_time"
      } else if (length(t_end) == 0 || is.na(t_end)) {
        skip_reason <- "Missing or unparseable end_time"
      } else if (t_start > t_end) {
        skip_reason <- sprintf("Inverted interval bounds: start_time (%s) > end_time (%s)", as.character(t_start), as.character(t_end))
      }
      
      if (!is.null(skip_reason)) {
        skipped_det_records[[length(skipped_det_records) + 1]] <- data.frame(
          event_id = ev_id,
          reason = skip_reason,
          stringsAsFactors = FALSE
        )
      } else {
        # Valid interval
        has_valid_peak <- (length(t_peak) > 0 && !is.na(t_peak) && t_peak >= t_start && t_peak <= t_end)
        
        valid_det_events[[length(valid_det_events) + 1]] <- list(
          event_id = ev_id,
          start_time = t_start,
          peak_time  = if (has_valid_peak) t_peak else as.POSIXct(NA, tz = "UTC"),
          end_time   = t_end,
          has_valid_peak = has_valid_peak,
          peak_flux  = if (!is.null(ev$peak_flux) && !is.na(ev$peak_flux)) as.numeric(ev$peak_flux) else NA_real_,
          duration_min = if (!is.null(ev$duration_min) && !is.na(ev$duration_min)) as.numeric(ev$duration_min) else as.numeric(difftime(t_end, t_start, units = "mins")),
          raw_index = i
        )
      }
    }
  }
  
  n_det_valid <- length(valid_det_events)
  n_det_skipped <- length(skipped_det_records)
  
  # ----------------------------------------------------------------------------
  # STEP B: Input Validation & Sanitization of NOAA Flare Records
  # ----------------------------------------------------------------------------
  n_noaa_total <- nrow(df_flares)
  valid_noaa_rows <- integer(0)
  skipped_noaa_records <- list()
  
  if (n_noaa_total > 0) {
    for (j in seq_len(n_noaa_total)) {
      f_id <- if (!is.null(df_flares$noaa_event_id[j])) as.character(df_flares$noaa_event_id[j]) else sprintf("NOAA_%04d", j)
      t_begin <- parse_utc_timestamp(df_flares$begin_time[j])
      t_max   <- parse_utc_timestamp(df_flares$max_time[j])
      t_end   <- parse_utc_timestamp(df_flares$end_time[j])
      
      skip_reason <- NULL
      if (length(t_begin) == 0 || is.na(t_begin)) {
        skip_reason <- "Missing or unparseable begin_time"
      } else if (length(t_end) == 0 || is.na(t_end)) {
        skip_reason <- "Missing or unparseable end_time"
      } else if (t_begin > t_end) {
        skip_reason <- sprintf("Inverted interval bounds: begin_time (%s) > end_time (%s)", as.character(t_begin), as.character(t_end))
      }
      
      if (!is.null(skip_reason)) {
        skipped_noaa_records[[length(skipped_noaa_records) + 1]] <- data.frame(
          noaa_event_id = f_id,
          reason = skip_reason,
          stringsAsFactors = FALSE
        )
      } else {
        valid_noaa_rows <- c(valid_noaa_rows, j)
      }
    }
  }
  
  n_noaa_valid <- length(valid_noaa_rows)
  n_noaa_skipped <- length(skipped_noaa_records)
  
  # ----------------------------------------------------------------------------
  # STEP C: Matching Algorithm (Guaranteed Pure Boolean Evaluation)
  # ----------------------------------------------------------------------------
  aligned_records <- list()
  matched_noaa_indices <- integer(0)
  
  if (n_det_valid > 0 && n_noaa_valid > 0) {
    for (i in seq_along(valid_det_events)) {
      det <- valid_det_events[[i]]
      det_start_num <- as.numeric(det$start_time)
      det_end_num   <- as.numeric(det$end_time)
      det_peak_num  <- if (det$has_valid_peak) as.numeric(det$peak_time) else NA_real_
      
      best_noaa_idx <- NA_integer_
      best_distance <- Inf
      match_candidates <- integer(0)
      
      for (idx_pos in seq_along(valid_noaa_rows)) {
        j <- valid_noaa_rows[idx_pos]
        flare <- df_flares[j, ]
        
        noaa_start_num <- as.numeric(flare$begin_time)
        noaa_end_num   <- as.numeric(flare$end_time)
        has_noaa_peak  <- !is.na(flare$max_time)
        noaa_peak_num  <- if (has_noaa_peak) as.numeric(flare$max_time) else NA_real_
        
        # 1. Pure Boolean Interval Overlap Check
        # Overlap condition: start1 <= end2 + tol AND end1 >= start2 - tol
        has_overlap <- (det_start_num <= noaa_end_num + tol_secs) && (det_end_num >= noaa_start_num - tol_secs)
        
        # 2. Pure Boolean Peak Proximity Check
        can_eval_peak <- det$has_valid_peak && has_noaa_peak
        peak_diff_mins <- if (can_eval_peak) {
          abs(det_peak_num - noaa_peak_num) / 60
        } else {
          Inf
        }
        peak_close <- can_eval_peak && (peak_diff_mins <= max_peak_diff_mins)
        
        # 3. Strategy Decision (Strictly non-NA Boolean)
        matches <- FALSE
        if (matching_strategy == "interval_or_peak") {
          matches <- has_overlap || peak_close
        } else if (matching_strategy == "interval_only") {
          matches <- has_overlap
        } else if (matching_strategy == "peak_proximity") {
          matches <- peak_close
        }
        
        if (matches) {
          match_candidates <- c(match_candidates, j)
          # Distance metric for selecting best match among multiple candidates:
          # Prioritize peak time proximity; if un-peaked, use interval midpoint distance
          cand_dist <- if (can_eval_peak) {
            peak_diff_mins
          } else {
            max_peak_diff_mins + abs((det_start_num + det_end_num)/2 - (noaa_start_num + noaa_end_num)/2) / 60
          }
          
          if (cand_dist < best_distance) {
            best_distance <- cand_dist
            best_noaa_idx <- j
          }
        }
      }
      
      is_ambiguous <- length(match_candidates) > 1
      
      if (!is.na(best_noaa_idx)) {
        matched_flare <- df_flares[best_noaa_idx, ]
        matched_noaa_indices <- c(matched_noaa_indices, best_noaa_idx)
        
        # Compute timing errors
        start_err_mins <- as.numeric(difftime(det$start_time, matched_flare$begin_time, units = "mins"))
        end_err_mins   <- as.numeric(difftime(det$end_time, matched_flare$end_time, units = "mins"))
        
        peak_err_mins <- if (det$has_valid_peak && !is.na(matched_flare$max_time)) {
          as.numeric(difftime(det$peak_time, matched_flare$max_time, units = "mins"))
        } else {
          NA_real_
        }
        
        # Extract and sanitize flare classification
        raw_mclass <- matched_flare$max_class
        flare_max_class <- if (!is.null(raw_mclass) && !is.na(raw_mclass) && as.character(raw_mclass) != "") {
          as.character(raw_mclass)
        } else {
          "Unspecified"
        }
        
        raw_clet <- matched_flare$flare_class_letter
        flare_class_let <- if (!is.null(raw_clet) && !is.na(raw_clet) && as.character(raw_clet) != "") {
          as.character(raw_clet)
        } else if (flare_max_class != "Unspecified") {
          substr(flare_max_class, 1, 1)
        } else {
          "U"
        }
        
        aligned_records[[length(aligned_records) + 1]] <- data.frame(
          event_id = det$event_id,
          status = "MATCHED",
          is_ambiguous = is_ambiguous,
          detected_start = det$start_time,
          detected_peak  = det$peak_time,
          detected_end   = det$end_time,
          detected_peak_flux = det$peak_flux,
          detected_duration_min = det$duration_min,
          noaa_event_id = matched_flare$noaa_event_id,
          noaa_class = flare_max_class,
          noaa_class_letter = flare_class_let,
          noaa_begin_time = matched_flare$begin_time,
          noaa_max_time   = matched_flare$max_time,
          noaa_end_time   = matched_flare$end_time,
          noaa_max_flux   = matched_flare$max_xrlong,
          start_error_min = start_err_mins,
          peak_error_min  = peak_err_mins,
          end_error_min   = end_err_mins,
          abs_peak_error_min = if (!is.na(peak_err_mins)) abs(peak_err_mins) else NA_real_,
          stringsAsFactors = FALSE
        )
      } else {
        # Valid detection, but unconfirmed in official NOAA records (False Positive)
        aligned_records[[length(aligned_records) + 1]] <- data.frame(
          event_id = det$event_id,
          status = "UNMATCHED_DETECTION",
          is_ambiguous = FALSE,
          detected_start = det$start_time,
          detected_peak  = det$peak_time,
          detected_end   = det$end_time,
          detected_peak_flux = det$peak_flux,
          detected_duration_min = det$duration_min,
          noaa_event_id = NA_character_,
          noaa_class = NA_character_,
          noaa_class_letter = NA_character_,
          noaa_begin_time = as.POSIXct(NA, tz = "UTC"),
          noaa_max_time   = as.POSIXct(NA, tz = "UTC"),
          noaa_end_time   = as.POSIXct(NA, tz = "UTC"),
          noaa_max_flux   = NA_real_,
          start_error_min = NA_real_,
          peak_error_min  = NA_real_,
          end_error_min   = NA_real_,
          abs_peak_error_min = NA_real_,
          stringsAsFactors = FALSE
        )
      }
    }
  } else if (n_det_valid > 0 && n_noaa_valid == 0) {
    # All detections are unmatched
    for (i in seq_along(valid_det_events)) {
      det <- valid_det_events[[i]]
      aligned_records[[length(aligned_records) + 1]] <- data.frame(
        event_id = det$event_id,
        status = "UNMATCHED_DETECTION",
        is_ambiguous = FALSE,
        detected_start = det$start_time,
        detected_peak  = det$peak_time,
        detected_end   = det$end_time,
        detected_peak_flux = det$peak_flux,
        detected_duration_min = det$duration_min,
        noaa_event_id = NA_character_,
        noaa_class = NA_character_,
        noaa_class_letter = NA_character_,
        noaa_begin_time = as.POSIXct(NA, tz = "UTC"),
        noaa_max_time   = as.POSIXct(NA, tz = "UTC"),
        noaa_end_time   = as.POSIXct(NA, tz = "UTC"),
        noaa_max_flux   = NA_real_,
        start_error_min = NA_real_,
        peak_error_min  = NA_real_,
        end_error_min   = NA_real_,
        abs_peak_error_min = NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }
  
  # Append skipped detected records for full audit provenance
  if (n_det_skipped > 0) {
    for (k in seq_along(skipped_det_records)) {
      sk <- skipped_det_records[[k]]
      aligned_records[[length(aligned_records) + 1]] <- data.frame(
        event_id = sk$event_id,
        status = "SKIPPED_INVALID",
        is_ambiguous = FALSE,
        detected_start = as.POSIXct(NA, tz = "UTC"),
        detected_peak  = as.POSIXct(NA, tz = "UTC"),
        detected_end   = as.POSIXct(NA, tz = "UTC"),
        detected_peak_flux = NA_real_,
        detected_duration_min = NA_real_,
        noaa_event_id = NA_character_,
        noaa_class = NA_character_,
        noaa_class_letter = NA_character_,
        noaa_begin_time = as.POSIXct(NA, tz = "UTC"),
        noaa_max_time   = as.POSIXct(NA, tz = "UTC"),
        noaa_end_time   = as.POSIXct(NA, tz = "UTC"),
        noaa_max_flux   = NA_real_,
        start_error_min = NA_real_,
        peak_error_min  = NA_real_,
        end_error_min   = NA_real_,
        abs_peak_error_min = NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }
  
  aligned_df <- if (length(aligned_records) > 0) do.call(rbind, aligned_records) else data.frame()
  
  # ----------------------------------------------------------------------------
  # STEP D: Identify Unmatched NOAA Flares (False Negatives)
  # ----------------------------------------------------------------------------
  unique_matched_noaa <- unique(matched_noaa_indices)
  missed_noaa_indices <- setdiff(valid_noaa_rows, unique_matched_noaa)
  missed_noaa_df <- if (length(missed_noaa_indices) > 0) df_flares[missed_noaa_indices, ] else data.frame()
  
  # Detection Evaluation Metrics
  tp_count <- length(unique_matched_noaa)
  fp_count <- if (nrow(aligned_df) > 0) sum(aligned_df$status == "UNMATCHED_DETECTION") else 0
  fn_count <- length(missed_noaa_indices)
  
  prec <- if ((tp_count + fp_count) > 0) tp_count / (tp_count + fp_count) else 0.0
  rec  <- if ((tp_count + fn_count) > 0) tp_count / (tp_count + fn_count) else 0.0
  f1   <- if ((prec + rec) > 0) 2 * prec * rec / (prec + rec) else 0.0
  
  valid_peak_errors <- if (nrow(aligned_df) > 0) {
    aligned_df$abs_peak_error_min[!is.na(aligned_df$abs_peak_error_min)]
  } else {
    numeric(0)
  }
  mean_peak_err <- if (length(valid_peak_errors) > 0) mean(valid_peak_errors) else NA_real_
  med_peak_err  <- if (length(valid_peak_errors) > 0) median(valid_peak_errors) else NA_real_
  
  # ----------------------------------------------------------------------------
  # STEP E: Mandatory Diagnostic Reporting (Requirement 9)
  # ----------------------------------------------------------------------------
  cat("\n  --- NOAA Alignment Diagnostic Report ---\n")
  cat(sprintf("  Detected Events Total           : %d\n", n_det_total))
  cat(sprintf("  Detected Events with Valid Time : %d\n", n_det_valid))
  cat(sprintf("  NOAA Flare Records Total        : %d\n", n_noaa_total))
  cat(sprintf("  NOAA Records with Valid Time    : %d\n", n_noaa_valid))
  cat(sprintf("  Successful Matches (TP)         : %d\n", tp_count))
  cat(sprintf("  Unmatched Detected Events (FP)  : %d\n", fp_count))
  cat(sprintf("  Unmatched NOAA Flares (FN)      : %d\n", fn_count))
  cat(sprintf("  Records Skipped (Invalid/NA)    : %d (%d det, %d noaa)\n",
              n_det_skipped + n_noaa_skipped, n_det_skipped, n_noaa_skipped))
  
  if (n_det_skipped > 0) {
    cat("  Skipped Detected Events Reasons:\n")
    for (sk in skipped_det_records) {
      cat(sprintf("    - %s: %s\n", sk$event_id, sk$reason))
    }
  }
  if (n_noaa_skipped > 0) {
    cat("  Skipped NOAA Events Reasons:\n")
    for (sk in skipped_noaa_records) {
      cat(sprintf("    - %s: %s\n", sk$noaa_event_id, sk$reason))
    }
  }
  
  cat(sprintf("  Event-Level Precision           : %.4f\n", prec))
  cat(sprintf("  Event-Level Recall              : %.4f\n", rec))
  cat(sprintf("  Event-Level F1-Score            : %.4f\n", f1))
  cat(sprintf("  Mean Peak Timing Error          : %s mins\n", if (is.na(mean_peak_err)) "N/A" else sprintf("%.2f", mean_peak_err)))
  cat(sprintf("  Median Peak Timing Error        : %s mins\n", if (is.na(med_peak_err)) "N/A" else sprintf("%.2f", med_peak_err)))
  cat("  ----------------------------------------\n\n")
  
  return(list(
    aligned_table = aligned_df,
    missed_noaa = missed_noaa_df,
    skipped_detections = skipped_det_records,
    skipped_noaa = skipped_noaa_records,
    diagnostics = list(
      n_detected_total = n_det_total,
      n_detected_valid = n_det_valid,
      n_detected_skipped = n_det_skipped,
      n_noaa_total = n_noaa_total,
      n_noaa_valid = n_noaa_valid,
      n_noaa_skipped = n_noaa_skipped,
      n_matched = tp_count,
      n_unmatched_det = fp_count,
      n_unmatched_noaa = fn_count
    ),
    metrics = list(
      tp = tp_count,
      fp = fp_count,
      fn = fn_count,
      precision = prec,
      recall = rec,
      f1 = f1,
      mean_peak_error_min = mean_peak_err,
      median_peak_error_min = med_peak_err
    )
  ))
}
