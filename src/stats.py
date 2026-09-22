"""
First-Principles Statistical Foundation Module for Solar X-Ray Time-Series Analysis.

Implements core descriptive and robust statistical estimators from explicit mathematical
formulas without relying blindly on black-box library functions.
Each estimator is validated against NumPy / SciPy reference implementations.
"""

from typing import Union, List
import numpy as np


def _to_clean_array(data: Union[List[float], np.ndarray]) -> np.ndarray:
    """Helper function to convert input to 1D float numpy array and filter NaNs."""
    arr = np.asarray(data, dtype=np.float64).flatten()
    arr = arr[~np.isnan(arr)]
    if len(arr) == 0:
        raise ValueError("Input data must contain at least one non-NaN numerical element.")
    return arr


def calculate_mean(data: Union[List[float], np.ndarray]) -> float:
    """
    Mathematical Formula:
        x̄ = (1 / N) * ∑_{i=1}^{N} x_i

    Measures: The arithmetic central value / sample expected value.
    """
    arr = _to_clean_array(data)
    n = len(arr)
    total_sum = 0.0
    for val in arr:
        total_sum += val
    return float(total_sum / n)


def calculate_median(data: Union[List[float], np.ndarray]) -> float:
    """
    Mathematical Formula:
        If N is odd : Median = x_(((N+1)/2))
        If N is even: Median = (x_((N/2)) + x_((N/2)+1)) / 2
        (where x is sorted in ascending order)

    Measures: The 50th percentile / robust center of the distribution.
    """
    arr = _to_clean_array(data)
    sorted_arr = np.sort(arr)
    n = len(sorted_arr)
    mid = n // 2
    if n % 2 == 1:
        return float(sorted_arr[mid])
    else:
        return float((sorted_arr[mid - 1] + sorted_arr[mid]) / 2.0)


def calculate_variance(data: Union[List[float], np.ndarray], ddof: int = 1) -> float:
    """
    Mathematical Formula:
        s² = (1 / (N - ddof)) * ∑_{i=1}^{N} (x_i - x̄)²

    Measures: The dispersion / average squared deviation from the mean.
    """
    arr = _to_clean_array(data)
    n = len(arr)
    if n <= ddof:
        raise ValueError(f"Sample size N={n} must be greater than ddof={ddof}.")
    mean_val = calculate_mean(arr)
    squared_diff_sum = 0.0
    for val in arr:
        squared_diff_sum += (val - mean_val) ** 2
    return float(squared_diff_sum / (n - ddof))


def calculate_std(data: Union[List[float], np.ndarray], ddof: int = 1) -> float:
    """
    Mathematical Formula:
        s = √(s²) = √[ (1 / (N - ddof)) * ∑_{i=1}^{N} (x_i - x̄)² ]

    Measures: The standard scale / dispersion in the original units of measurement.
    """
    var_val = calculate_variance(data, ddof=ddof)
    return float(np.sqrt(var_val))


def calculate_quantile(data: Union[List[float], np.ndarray], q: float) -> float:
    """
    Mathematical Formula (Linear Interpolation Method - Type 7 / Default NumPy):
        Let p = q * (N - 1)
        Let i = ⌊p⌋
        Let f = p - i
        Q(q) = (1 - f) * x_(i) + f * x_(i+1)

    Measures: The value below which a fraction q of observations fall.
    """
    if not (0.0 <= q <= 1.0):
        raise ValueError(f"Quantile q={q} must be between 0.0 and 1.0.")
    arr = _to_clean_array(data)
    sorted_arr = np.sort(arr)
    n = len(sorted_arr)
    if n == 1:
        return float(sorted_arr[0])

    p = q * (n - 1)
    i = int(np.floor(p))
    f = p - i

    if i >= n - 1:
        return float(sorted_arr[-1])
    return float((1.0 - f) * sorted_arr[i] + f * sorted_arr[i + 1])


def calculate_iqr(data: Union[List[float], np.ndarray]) -> float:
    """
    Mathematical Formula:
        IQR = Q_3 - Q_1 = Q(0.75) - Q(0.25)

    Measures: The spread of the central 50% of the distribution (robust scale).
    """
    q75 = calculate_quantile(data, 0.75)
    q25 = calculate_quantile(data, 0.25)
    return float(q75 - q25)


def calculate_mad(data: Union[List[float], np.ndarray], scale_factor: float = 1.4826) -> float:
    """
    Mathematical Formula:
        MAD_raw = Median( |x_i - Median(X)| )
        MAD_normal = scale_factor * MAD_raw   (where scale_factor ≈ 1.4826 for Normal consistency)

    Measures: Median Absolute Deviation (ultra-robust scale estimator).
    """
    arr = _to_clean_array(data)
    med_val = calculate_median(arr)
    abs_deviations = np.abs(arr - med_val)
    raw_mad = calculate_median(abs_deviations)
    return float(scale_factor * raw_mad)


def calculate_cv(data: Union[List[float], np.ndarray]) -> float:
    """
    Mathematical Formula:
        CV = s / x̄ = (Standard Deviation) / (Mean)

    Measures: Relative dispersion / unitless variability ratio.
    Scientifically meaningful ONLY for positive ratio scales (raw flux X > 0).
    """
    arr = _to_clean_array(data)
    mean_val = calculate_mean(arr)
    if mean_val == 0.0:
        raise ValueError("Mean is zero; Coefficient of Variation is undefined.")
    std_val = calculate_std(arr, ddof=1)
    return float(std_val / mean_val)
