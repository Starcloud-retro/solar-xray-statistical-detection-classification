# ==============================================================================
# R/01_stats_primitives.R
# First-Principles Statistical Foundation Module for Solar X-Ray Time-Series
#
# Implements core descriptive, robust, and anomaly statistical measures from
# explicit mathematical definitions without relying blindly on external libraries.
#
# Academic PBL: Statistical Detection & Classification of Solar Activity
# ==============================================================================

# Helper: clean numeric vector, remove NA / NaN / Inf
clean_numeric_vector <- function(x) {
  if (!is.numeric(x)) {
    stop("Input must be a numeric vector.")
  }
  x_clean <- x[!is.na(x) & !is.nan(x) & !is.infinite(x)]
  if (length(x_clean) == 0) {
    stop("Input data must contain at least one valid finite numeric element.")
  }
  return(x_clean)
}

# 1. Arithmetic Mean: mu = (1/n) * sum(x_i)
calculate_mean <- function(x) {
  v <- clean_numeric_vector(x)
  total <- 0.0
  n <- length(v)
  for (i in seq_len(n)) {
    total <- total + v[i]
  }
  return(total / n)
}

# 2. Sample Median: middle value of sorted array
calculate_median <- function(x) {
  v <- sort(clean_numeric_vector(x))
  n <- length(v)
  mid <- n %/% 2
  if (n %% 2 == 1) {
    return(as.numeric(v[mid + 1]))
  } else {
    return(as.numeric((v[mid] + v[mid + 1]) / 2.0))
  }
}

# 3. Sample Variance: s^2 = [1 / (n - ddof)] * sum((x_i - mean)^2)
calculate_variance <- function(x, ddof = 1) {
  v <- clean_numeric_vector(x)
  n <- length(v)
  if (n <= ddof) {
    stop(sprintf("Sample size n=%d must be strictly greater than ddof=%d.", n, ddof))
  }
  m <- calculate_mean(v)
  sq_sum <- 0.0
  for (i in seq_len(n)) {
    sq_sum <- sq_sum + (v[i] - m)^2
  }
  return(sq_sum / (n - ddof))
}

# 4. Sample Standard Deviation: s = sqrt(s^2)
calculate_std <- function(x, ddof = 1) {
  return(sqrt(calculate_variance(x, ddof = ddof)))
}

# 5. Quantiles: Type 7 linear interpolation
# p = q * (n - 1); i = floor(p); f = p - i; Q(q) = (1 - f) * x_(i+1) + f * x_(i+2) (1-indexed)
calculate_quantile <- function(x, q) {
  if (q < 0.0 || q > 1.0) {
    stop("Quantile probability q must be between 0.0 and 1.0.")
  }
  v <- sort(clean_numeric_vector(x))
  n <- length(v)
  if (n == 1) {
    return(as.numeric(v[1]))
  }
  p <- q * (n - 1)
  i <- floor(p)
  f <- p - i
  idx1 <- i + 1
  idx2 <- min(idx1 + 1, n)
  return((1.0 - f) * v[idx1] + f * v[idx2])
}

# 6. Interquartile Range (IQR): IQR = Q(0.75) - Q(0.25)
calculate_iqr <- function(x) {
  q75 <- calculate_quantile(x, 0.75)
  q25 <- calculate_quantile(x, 0.25)
  return(q75 - q25)
}

# 7. Median Absolute Deviation (Raw): MAD_raw = median(|x_i - median(x)|)
calculate_mad_raw <- function(x) {
  v <- clean_numeric_vector(x)
  med <- calculate_median(v)
  abs_devs <- abs(v - med)
  return(calculate_median(abs_devs))
}

# 8. Median Absolute Deviation (Normal Scaled): MAD_scaled = 1.4826 * MAD_raw
# Scale factor 1.4826 is applied ONCE ONLY for Gaussian consistency.
calculate_mad_scaled <- function(x, scale_factor = 1.4826) {
  raw_mad <- calculate_mad_raw(x)
  return(scale_factor * raw_mad)
}

# 9. Coefficient of Variation (CV): CV = s / mean
calculate_cv <- function(x) {
  v <- clean_numeric_vector(x)
  m <- calculate_mean(v)
  if (abs(m) < 1e-18) {
    stop("Mean is zero; Coefficient of Variation is undefined.")
  }
  s <- calculate_std(v, ddof = 1)
  return(s / m)
}

# 10. Standard Z-score: z = (x - mu) / sigma
calculate_standard_zscore <- function(x, mean_val, std_val) {
  if (is.na(std_val) || std_val <= 1e-18) {
    return(NA_real_)
  }
  return((x - mean_val) / std_val)
}

# 11. Robust Z-score: z_robust = (x - median) / MAD_scaled
# Uses single-scaled MAD in denominator.
calculate_robust_zscore <- function(x, median_val, mad_scaled_val) {
  if (is.na(mad_scaled_val) || mad_scaled_val <= 1e-18) {
    return(NA_real_)
  }
  return((x - median_val) / mad_scaled_val)
}

# ==============================================================================
# Self-Test Verification Suite
# ==============================================================================
run_stats_primitive_tests <- function() {
  cat("Running R First-Principles Statistics Unit Tests...\n")
  
  # Test dataset: [10, 12, 15, 18, 20, 100]
  test_data <- c(10.0, 12.0, 15.0, 18.0, 20.0, 100.0)
  
  # 1. Mean
  m <- calculate_mean(test_data)
  stopifnot(abs(m - mean(test_data)) < 1e-10)
  cat("  [PASS] calculate_mean\n")
  
  # 2. Median
  med <- calculate_median(test_data)
  stopifnot(abs(med - 16.5) < 1e-10)
  cat("  [PASS] calculate_median\n")
  
  # 3. Variance & Std
  s2 <- calculate_variance(test_data, ddof = 1)
  stopifnot(abs(s2 - var(test_data)) < 1e-10)
  s <- calculate_std(test_data, ddof = 1)
  stopifnot(abs(s - sd(test_data)) < 1e-10)
  cat("  [PASS] calculate_variance & calculate_std\n")
  
  # 4. Quantiles & IQR
  q50 <- calculate_quantile(test_data, 0.50)
  stopifnot(abs(q50 - 16.5) < 1e-10)
  iqr_val <- calculate_iqr(test_data)
  stopifnot(abs(iqr_val - IQR(test_data, type = 7)) < 1e-10)
  cat("  [PASS] calculate_quantile & calculate_iqr\n")
  
  # 5. MAD Single-Scaling Verification (Prevent Double-Scaling)
  raw_mad <- calculate_mad_raw(test_data)
  stopifnot(abs(raw_mad - 4.0) < 1e-10)
  scaled_mad <- calculate_mad_scaled(test_data, scale_factor = 1.4826)
  stopifnot(abs(scaled_mad - 5.9304) < 1e-10)
  double_scaled <- scaled_mad * 1.4826
  # Ensure scaled_mad is NOT double scaled
  stopifnot(abs(scaled_mad - double_scaled) > 1.0)
  cat("  [PASS] calculate_mad (Single-scaled 1.4826, double-scaling prevented)\n")
  
  # 6. Robust Z-score
  z_rob <- calculate_robust_zscore(100.0, med, scaled_mad)
  expected_z_rob <- (100.0 - 16.5) / 5.9304
  stopifnot(abs(z_rob - expected_z_rob) < 1e-10)
  cat("  [PASS] calculate_robust_zscore\n")
  
  cat("All R statistical primitive unit tests passed successfully!\n")
  return(TRUE)
}
