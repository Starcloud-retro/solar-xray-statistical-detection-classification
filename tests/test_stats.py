"""
Unit Tests for First-Principles Statistics Module (src/stats.py).

Verifies mathematical exactness against manually verifiable small test datasets
and standard NumPy / SciPy library implementations.
"""

import unittest
import numpy as np
from scipy import stats as scipy_stats

from src.stats import (
    calculate_mean,
    calculate_median,
    calculate_variance,
    calculate_std,
    calculate_quantile,
    calculate_iqr,
    calculate_mad,
    calculate_cv
)


class TestFirstPrinciplesStats(unittest.TestCase):

    def setUp(self):
        # Small manually verifiable dataset
        # Data: [1.0, 2.0, 3.0, 4.0, 5.0]
        # Sum = 15.0, Mean = 3.0, Median = 3.0
        # Squared Diff Sum = (4 + 1 + 0 + 1 + 4) = 10.0
        # Sample Var (ddof=1) = 10.0 / 4 = 2.5
        # Sample Std = sqrt(2.5) ≈ 1.58113883
        self.small_odd = [1.0, 2.0, 3.0, 4.0, 5.0]

        # Even dataset with outlier: [10.0, 12.0, 15.0, 18.0, 20.0, 100.0]
        # Median = (15 + 18)/2 = 16.5
        self.even_outlier = [10.0, 12.0, 15.0, 18.0, 20.0, 100.0]

    def test_mean(self):
        # Manual check
        self.assertAlmostEqual(calculate_mean(self.small_odd), 3.0, places=7)
        # NumPy check
        np_res = np.mean(self.even_outlier)
        self.assertAlmostEqual(calculate_mean(self.even_outlier), float(np_res), places=7)

    def test_median(self):
        # Manual check (odd)
        self.assertEqual(calculate_median(self.small_odd), 3.0)
        # Manual check (even)
        self.assertEqual(calculate_median(self.even_outlier), 16.5)
        # NumPy check
        self.assertEqual(calculate_median(self.even_outlier), float(np.median(self.even_outlier)))

    def test_variance(self):
        # Manual check sample variance (ddof=1)
        self.assertAlmostEqual(calculate_variance(self.small_odd, ddof=1), 2.5, places=7)
        # NumPy check
        np_var = np.var(self.even_outlier, ddof=1)
        self.assertAlmostEqual(calculate_variance(self.even_outlier, ddof=1), float(np_var), places=7)

    def test_std(self):
        # Manual check
        expected_std = np.sqrt(2.5)
        self.assertAlmostEqual(calculate_std(self.small_odd, ddof=1), float(expected_std), places=7)
        # NumPy check
        np_std = np.std(self.even_outlier, ddof=1)
        self.assertAlmostEqual(calculate_std(self.even_outlier, ddof=1), float(np_std), places=7)

    def test_quantiles(self):
        # NumPy default quantile linear interpolation
        for q in [0.0, 0.25, 0.50, 0.75, 1.0]:
            custom_q = calculate_quantile(self.even_outlier, q)
            np_q = np.quantile(self.even_outlier, q)
            self.assertAlmostEqual(custom_q, float(np_q), places=7)

    def test_iqr(self):
        # SciPy check
        custom_iqr = calculate_iqr(self.even_outlier)
        scipy_iqr = scipy_stats.iqr(self.even_outlier)
        self.assertAlmostEqual(custom_iqr, float(scipy_iqr), places=7)

    def test_mad(self):
        # Data: [10, 12, 15, 18, 20, 100]
        # Median = 16.5
        # Absolute deviations: [6.5, 4.5, 1.5, 1.5, 3.5, 83.5]
        # Sorted deviations: [1.5, 1.5, 3.5, 4.5, 6.5, 83.5]
        # Median of deviations = (3.5 + 4.5) / 2 = 4.0
        # Scaled MAD = 4.0 * 1.4826 = 5.9304
        custom_mad = calculate_mad(self.even_outlier, scale_factor=1.4826)
        self.assertAlmostEqual(custom_mad, 5.9304, places=7)

    def test_cv(self):
        # Manual check
        mean_val = 3.0
        std_val = np.sqrt(2.5)
        expected_cv = std_val / mean_val
        self.assertAlmostEqual(calculate_cv(self.small_odd), float(expected_cv), places=7)

    def test_mad_single_scaling_no_double_scaling(self):
        """Specifically verify MAD scaling factor 1.4826 is applied ONCE ONLY, preventing double scaling."""
        raw_mad = calculate_mad(self.even_outlier, scale_factor=1.0)
        self.assertEqual(raw_mad, 4.0)

        scaled_mad = calculate_mad(self.even_outlier, scale_factor=1.4826)
        self.assertAlmostEqual(scaled_mad, 4.0 * 1.4826, places=7)

        double_scaled_mad = scaled_mad * 1.4826
        # Ensure scaled_mad is NOT double-scaled
        self.assertNotAlmostEqual(scaled_mad, double_scaled_mad, places=3)
        self.assertAlmostEqual(double_scaled_mad, 4.0 * (1.4826 ** 2), places=7)

    def test_robust_z_score(self):
        """Verify robust Z-score using single-scaled MAD against an extreme outlier."""
        med = calculate_median(self.even_outlier)  # 16.5
        scaled_mad = calculate_mad(self.even_outlier, scale_factor=1.4826)  # 5.9304
        x_outlier = 100.0
        robust_z = (x_outlier - med) / scaled_mad
        expected_z = (100.0 - 16.5) / 5.9304
        self.assertAlmostEqual(robust_z, expected_z, places=7)

    def test_uncontaminated_rolling_baseline(self):
        """Verify that uncontaminated baseline at time t uses strictly observations before t."""
        import pandas as pd
        from src.rolling_stats import compute_rolling_statistics

        # Construct a synthetic time series with a sudden eruption at t=5
        df = pd.DataFrame({
            "time_tag": pd.date_range("2026-01-01", periods=10, freq="min", tz="UTC"),
            "log10_flux_clean": [-7.0, -7.0, -7.0, -7.0, -7.0, -4.0, -4.0, -4.0, -4.0, -4.0],
            "flux_clean": [1e-7, 1e-7, 1e-7, 1e-7, 1e-7, 1e-4, 1e-4, 1e-4, 1e-4, 1e-4]
        })

        # Contaminated rolling baseline (default lag=0)
        df_contam = compute_rolling_statistics(df, window_mins=5, min_periods=1, uncontaminated=False)
        # Uncontaminated rolling baseline (lag=1)
        df_uncontam = compute_rolling_statistics(df, window_mins=5, min_periods=1, uncontaminated=True)

        # At t=5 (the sudden eruption to -4.0):
        # Contaminated baseline includes -4.0, so mean is pulled up immediately
        self.assertGreater(df_contam.loc[5, "rolling_mean_5m"], -7.0)
        # Uncontaminated baseline uses only [0..4] (all -7.0), so mean remains strictly -7.0
        self.assertEqual(df_uncontam.loc[5, "rolling_mean_5m"], -7.0)


if __name__ == "__main__":
    unittest.main()
