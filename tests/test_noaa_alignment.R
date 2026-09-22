# ==============================================================================
# tests/test_noaa_alignment.R
# Regression and Robustness Tests for NOAA Flare Alignment (Stage 5)
#
# Tests specific failure classes mandated by academic specifications:
# 1. NA detected-event timestamp
# 2. NA NOAA timestamp (including un-peaked flares like Record 13)
# 3. Missing interval boundary
# 4. Malformed timestamp string
# 5. Empty event list / empty NOAA dataframe
# 6. Normal valid event match
# 7. Events exactly at the 5-minute tolerance boundary
# ==============================================================================

# Helper for test assertions
assert_true <- function(cond, msg) {
  if (!isTRUE(cond)) {
    stop(paste("ASSERTION FAILED:", msg))
  }
  cat(paste("  [PASS]", msg, "\n"))
}

test_alignment_suite <- function(alignment_fn, ingest_fn) {
  cat("\n====================================================================\n")
  cat("RUNNING NOAA ALIGNMENT REGRESSION TEST SUITE\n")
  cat("====================================================================\n\n")
  
  t0 <- as.POSIXct("2026-09-05 12:00:00", tz = "UTC")
  
  # Standard valid NOAA reference flare
  valid_noaa <- data.frame(
    noaa_event_id = "NOAA_TEST_01",
    begin_time = t0,
    max_time = t0 + 10 * 60,
    end_time = t0 + 30 * 60,
    max_class = "M1.0",
    flare_class_letter = "M",
    max_xrlong = 1e-5,
    stringsAsFactors = FALSE
  )
  
  # --------------------------------------------------------------------------
  # Test 1: Normal Valid Match
  # --------------------------------------------------------------------------
  cat("--- Test 1: Normal Valid Event Match ---\n")
  ev_normal <- list(list(
    event_id = "EVT_0001",
    start_time = t0 + 2 * 60,
    peak_time  = t0 + 10 * 60,
    end_time   = t0 + 28 * 60,
    peak_flux  = 1.05e-5,
    duration_min = 26
  ))
  res1 <- alignment_fn(ev_normal, valid_noaa, overlap_tolerance_mins = 5)
  assert_true(nrow(res1$aligned_table) == 1, "Single aligned record generated")
  assert_true(res1$aligned_table$status[1] == "MATCHED", "Normal event correctly matched")
  assert_true(res1$aligned_table$peak_error_min[1] == 0, "Zero peak error for identical peak")
  assert_true(res1$metrics$tp == 1, "TP count is 1")
  
  # --------------------------------------------------------------------------
  # Test 2: NA Detected-Event Timestamp
  # --------------------------------------------------------------------------
  cat("\n--- Test 2: NA Detected-Event Timestamps ---\n")
  ev_na_start <- list(list(
    event_id = "EVT_NA_START",
    start_time = as.POSIXct(NA),
    peak_time  = t0 + 10 * 60,
    end_time   = t0 + 28 * 60,
    peak_flux  = 1e-5,
    duration_min = 26
  ))
  res2a <- alignment_fn(ev_na_start, valid_noaa, overlap_tolerance_mins = 5)
  assert_true(nrow(res2a$aligned_table) == 1, "Handled NA start_time gracefully")
  assert_true(res2a$aligned_table$status[1] == "SKIPPED_INVALID", "Marked invalid start as skipped")
  
  ev_na_peak <- list(list(
    event_id = "EVT_NA_PEAK",
    start_time = t0,
    peak_time  = as.POSIXct(NA),
    end_time   = t0 + 30 * 60,
    peak_flux  = 1e-5,
    duration_min = 30
  ))
  res2b <- alignment_fn(ev_na_peak, valid_noaa, overlap_tolerance_mins = 5)
  assert_true(nrow(res2b$aligned_table) == 1, "Handled NA peak_time without error")
  # Under interval matching, it can still match interval with NA peak error
  assert_true(res2b$aligned_table$status[1] == "MATCHED", "Matched on interval even when detected peak is NA")
  assert_true(is.na(res2b$aligned_table$peak_error_min[1]), "Peak error is NA when detected peak is NA")
  
  # --------------------------------------------------------------------------
  # Test 3: NA NOAA Timestamp (e.g. Un-peaked Record 13)
  # --------------------------------------------------------------------------
  cat("\n--- Test 3: NA NOAA Timestamp (Un-peaked Flare like Record 13) ---\n")
  noaa_na_peak <- data.frame(
    noaa_event_id = "NOAA_UNPEAKED",
    begin_time = t0,
    max_time = as.POSIXct(NA),
    end_time = t0 + 60 * 60,
    max_class = as.character(NA),
    flare_class_letter = as.character(NA),
    max_xrlong = as.numeric(NA),
    stringsAsFactors = FALSE
  )
  res3 <- alignment_fn(ev_normal, noaa_na_peak, overlap_tolerance_mins = 5)
  assert_true(nrow(res3$aligned_table) == 1, "Handled NA NOAA max_time without error")
  assert_true(res3$aligned_table$status[1] == "MATCHED", "Matched via interval overlap despite missing NOAA peak")
  assert_true(is.na(res3$aligned_table$peak_error_min[1]), "Peak error is NA when NOAA peak is NA")
  assert_true(res3$aligned_table$noaa_class[1] == "Unspecified", "Missing NOAA class labeled Unspecified")
  
  # --------------------------------------------------------------------------
  # Test 4: Missing Interval Boundary / Inverted Interval
  # --------------------------------------------------------------------------
  cat("\n--- Test 4: Missing Boundary & Inverted Interval ---\n")
  ev_inverted <- list(list(
    event_id = "EVT_INVERTED",
    start_time = t0 + 30 * 60,
    peak_time  = t0 + 10 * 60,
    end_time   = t0,  # start > end
    peak_flux  = 1e-5,
    duration_min = -30
  ))
  res4 <- alignment_fn(ev_inverted, valid_noaa, overlap_tolerance_mins = 5)
  assert_true(res4$aligned_table$status[1] == "SKIPPED_INVALID", "Inverted interval safely marked SKIPPED_INVALID")
  
  # --------------------------------------------------------------------------
  # Test 5: Malformed Timestamp String
  # --------------------------------------------------------------------------
  cat("\n--- Test 5: Malformed Timestamps ---\n")
  ev_malformed <- list(list(
    event_id = "EVT_MALFORMED",
    start_time = "NOT_A_DATE",
    peak_time  = "CORRUPTED",
    end_time   = "2026-99-99 99:99:99",
    peak_flux  = 1e-5,
    duration_min = 10
  ))
  res5 <- alignment_fn(ev_malformed, valid_noaa, overlap_tolerance_mins = 5)
  assert_true(res5$aligned_table$status[1] == "SKIPPED_INVALID", "Malformed timestamp string safely intercepted")
  
  # --------------------------------------------------------------------------
  # Test 6: Empty Event List & Empty NOAA Catalog
  # --------------------------------------------------------------------------
  cat("\n--- Test 6: Empty Inputs ---\n")
  res6a <- alignment_fn(list(), valid_noaa, overlap_tolerance_mins = 5)
  assert_true(nrow(res6a$aligned_table) == 0, "Empty detected events handled safely")
  assert_true(res6a$metrics$tp == 0, "TP is 0 for empty detections")
  
  res6b <- alignment_fn(ev_normal, data.frame(), overlap_tolerance_mins = 5)
  assert_true(nrow(res6b$aligned_table) == 1, "Empty NOAA records handled safely")
  assert_true(res6b$aligned_table$status[1] == "UNMATCHED_DETECTION", "All detections unmatched when NOAA is empty")
  
  # --------------------------------------------------------------------------
  # Test 7: Events Exactly at 5-Minute Tolerance Boundary
  # --------------------------------------------------------------------------
  cat("\n--- Test 7: Exact 5-Minute Tolerance Boundary ---\n")
  # Event start is exactly 5 minutes after NOAA end:
  # noaa_end = t0 + 30 min. Event start = t0 + 35 min (diff = 5 min = 300s)
  ev_boundary_in <- list(list(
    event_id = "EVT_BOUND_IN",
    start_time = t0 + 35 * 60,
    peak_time  = t0 + 37 * 60,
    end_time   = t0 + 45 * 60,
    peak_flux  = 1e-5,
    duration_min = 10
  ))
  res7a <- alignment_fn(ev_boundary_in, valid_noaa, overlap_tolerance_mins = 5, matching_strategy = "interval_only")
  assert_true(res7a$aligned_table$status[1] == "MATCHED", "Event at exact +5 min boundary matches")
  
  # Event start is 5.01 minutes (301s) after NOAA end:
  ev_boundary_out <- list(list(
    event_id = "EVT_BOUND_OUT",
    start_time = t0 + 35 * 60 + 5, # 5 seconds past tolerance
    peak_time  = t0 + 38 * 60,
    end_time   = t0 + 45 * 60,
    peak_flux  = 1e-5,
    duration_min = 10
  ))
  res7b <- alignment_fn(ev_boundary_out, valid_noaa, overlap_tolerance_mins = 5, matching_strategy = "interval_only")
  assert_true(res7b$aligned_table$status[1] == "UNMATCHED_DETECTION", "Event past 5 min tolerance boundary does NOT match")
  
  cat("\n====================================================================\n")
  cat("ALL 7 NOAA ALIGNMENT REGRESSION TESTS PASSED SUCCESSFULLY!\n")
  cat("====================================================================\n\n")
  return(TRUE)
}
