# src/detector.py
"""
Statistical anomaly/event detector for GOES XRS 1‑minute flux.
Implements rolling‑mean Z‑score, rolling‑median robust Z‑score, rate‑of‑change,
persistence filtering, event extraction and evaluation against NOAA flare report.
"""

import logging
from pathlib import Path
from typing import List, Dict, Any

import numpy as np
import pandas as pd

from src.config import CHANNEL_LONG, DATA_DIR
from src.rolling_stats import compute_rolling_statistics

logger = logging.getLogger("Detector")

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def ensure_datetime(df: pd.DataFrame, col: str = "time_tag") -> pd.DataFrame:
    """Convert *col* to pandas datetime with UTC timezone if not already.
    Returns a copy with the column converted.
    """
    df = df.copy()
    if not pd.api.types.is_datetime64_any_dtype(df[col]):
        df[col] = pd.to_datetime(df[col], utc=True)
    return df


def z_score_detection(df: pd.DataFrame, window_min: int = 10, uncontaminated: bool = True) -> pd.DataFrame:
    """Add a column ``z_mean`` containing the rolling‑mean Z‑score.

    Z = (log10_flux_t - rolling_mean_{t-1}) / rolling_std_{t-1}
    When uncontaminated=True, baseline statistics are calculated strictly from observations before t.
    """
    df = ensure_datetime(df)
    rs = compute_rolling_statistics(df, window_mins=window_min, uncontaminated=uncontaminated)
    df["z_mean"] = (df["log10_flux_clean"] - rs[f"rolling_mean_{window_min}m"]) / rs[f"rolling_std_{window_min}m"]
    return df


def robust_z_score_detection(df: pd.DataFrame, window_min: int = 10, uncontaminated: bool = True) -> pd.DataFrame:
    """Add a column ``z_mad`` containing the robust Z‑score based on rolling median and MAD.

    Robust Z = (log10_flux_t - rolling_median_{t-1}) / MAD_scaled_{t-1}
    where MAD_scaled = 1.4826 * MAD_raw. The 1.4826 Gaussian consistency factor is applied ONCE ONLY.
    When uncontaminated=True, baseline statistics are calculated strictly from observations before t.
    """
    df = ensure_datetime(df)
    rs = compute_rolling_statistics(df, window_mins=window_min, uncontaminated=uncontaminated)
    mad_scaled = rs[f"rolling_mad_scaled_{window_min}m"]
    df["z_mad"] = (df["log10_flux_clean"] - rs[f"rolling_median_{window_min}m"]) / mad_scaled
    return df


def rate_of_change_detection(df: pd.DataFrame) -> pd.DataFrame:
    """Add a column ``roc`` with the first difference of log10 flux (dex per minute)."""
    df = ensure_datetime(df)
    df["roc"] = df["log10_flux_clean"].diff()
    return df


def apply_persistence(mask: pd.Series, min_len: int) -> pd.Series:
    """Enforce a persistence condition.

    *mask* is a boolean series indicating where a raw condition holds.
    Returns a boolean series that is ``True`` only for points belonging to a
    block of at least *min_len* consecutive ``True`` values.
    """
    if min_len <= 1:
        return mask
    pers = mask.rolling(window=min_len, min_periods=min_len).sum() == min_len
    pers = pers.rolling(window=min_len, min_periods=1).max().fillna(False)
    return pers.astype(bool)


def combine_flags(df: pd.DataFrame, flags: List[pd.Series]) -> pd.Series:
    """Logical OR of a list of boolean series."""
    combined = pd.Series(False, index=df.index)
    for f in flags:
        combined = combined | f
    return combined


def extract_events(df: pd.DataFrame, flag_col: str = "detected") -> List[Dict[str, Any]]:
    """Convert a boolean flag series into a list of event dictionaries.

    Each event dict contains ``start``, ``end``, ``peak_time`` and ``peak_flux``.
    """
    events = []
    flag = df[flag_col].astype(bool)
    in_event = False
    start_idx = None
    for i, val in flag.items():
        if val and not in_event:
            in_event = True
            start_idx = i
        elif not val and in_event:
            end_idx = i - 1
            segment = df.loc[start_idx:end_idx]
            peak_idx = segment["flux_clean"].idxmax()
            events.append({
                "start": df.at[start_idx, "time_tag"],
                "end": df.at[end_idx, "time_tag"],
                "peak_time": df.at[peak_idx, "time_tag"],
                "peak_flux": df.at[peak_idx, "flux_clean"],
                "peak_log_flux": df.at[peak_idx, "log10_flux_clean"],
            })
            in_event = False
    if in_event:
        end_idx = flag.last_valid_index()
        segment = df.loc[start_idx:end_idx]
        peak_idx = segment["flux_clean"].idxmax()
        events.append({
            "start": df.at[start_idx, "time_tag"],
            "end": df.at[end_idx, "time_tag"],
            "peak_time": df.at[peak_idx, "time_tag"],
            "peak_flux": df.at[peak_idx, "flux_clean"],
            "peak_log_flux": df.at[peak_idx, "log10_flux_clean"],
        })
    return events


def merge_overlapping_events(events: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Merge events that overlap in time.

    Events are assumed to be sorted by start time.
    """
    if not events:
        return []
    events_sorted = sorted(events, key=lambda e: e["start"])
    merged = [events_sorted[0].copy()]
    for ev in events_sorted[1:]:
        last = merged[-1]
        if ev["start"] <= last["end"]:
            last["end"] = max(last["end"], ev["end"])
            if ev["peak_log_flux"] > last["peak_log_flux"]:
                last["peak_time"] = ev["peak_time"]
                last["peak_flux"] = ev["peak_flux"]
                last["peak_log_flux"] = ev["peak_log_flux"]
        else:
            merged.append(ev.copy())
    return merged

def _build_ground_truth_series(df: pd.DataFrame, flare_df: pd.DataFrame) -> pd.Series:
    """Return a boolean series aligned with *df* indicating whether each timestamp falls inside any flare interval.
    ``flare_df`` must contain ``begin_time`` and ``end_time`` columns as pandas timestamps.
    """
    gt = pd.Series(False, index=df.index)
    for _, row in flare_df.iterrows():
        mask = (df["time_tag"] >= row["begin_time"]) & (df["time_tag"] <= row["end_time"])
        gt = gt | mask
    return gt

def evaluate_point_level(df: pd.DataFrame, detection_col: str, ground_truth_series: pd.Series) -> Dict[str, float]:
    """Compute TP, FP, TN, FN and derived metrics for point‑wise detection.
    Returns a dict with ``precision``, ``recall``, ``f1``.
    """
    pred = df[detection_col].astype(bool)
    tp = int(((pred == True) & (ground_truth_series == True)).sum())
    fp = int(((pred == True) & (ground_truth_series == False)).sum())
    tn = int(((pred == False) & (ground_truth_series == False)).sum())
    fn = int(((pred == False) & (ground_truth_series == True)).sum())
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
    return {"tp": tp, "fp": fp, "tn": tn, "fn": fn, "precision": precision, "recall": recall, "f1": f1}

def evaluate_event_level(pred_events: List[Dict[str, Any]], flare_df: pd.DataFrame) -> Dict[str, float]:
    """Event‑level evaluation.
    A predicted event is a true positive if its interval overlaps any ground‑truth flare interval.
    Overlapping predictions for the same flare count as a single TP.
    """
    gt_intervals = [(row["begin_time"], row["end_time"]) for _, row in flare_df.iterrows()]
    matched_gt = set()
    tp = 0
    for ev in pred_events:
        matched = False
        for idx, (gt_start, gt_end) in enumerate(gt_intervals):
            if (ev["start"] <= gt_end) and (ev["end"] >= gt_start):
                matched = True
                matched_gt.add(idx)
                break
        if matched:
            tp += 1
    fp = len(pred_events) - tp
    fn = len(gt_intervals) - len(matched_gt)
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0
    return {"tp": tp, "fp": fp, "fn": fn, "precision": precision, "recall": recall, "f1": f1}

# ---------------------------------------------------------------------------
# High‑level detector orchestrator
# ---------------------------------------------------------------------------

def detect_events(
    df: pd.DataFrame,
    z_mean_thr: float = 3.0,
    z_mad_thr: float = 3.0,
    roc_thr: float = 0.05,
    min_len: int = 3,
    window_min: int = 10,
    uncontaminated: bool = True,
) -> pd.DataFrame:
    """Apply all detection cues and return the dataframe with a ``detected`` column.
    Parameters are treated as hyper‑parameters.
    """
    df = ensure_datetime(df)
    df = z_score_detection(df, window_min=window_min, uncontaminated=uncontaminated)
    df = robust_z_score_detection(df, window_min=window_min, uncontaminated=uncontaminated)
    df = rate_of_change_detection(df)

    mask_z_mean = df["z_mean"] > z_mean_thr
    mask_z_mad = df["z_mad"] > z_mad_thr
    mask_roc = df["roc"] > roc_thr

    pers_z_mean = apply_persistence(mask_z_mean, min_len)
    pers_z_mad = apply_persistence(mask_z_mad, min_len)
    pers_roc = apply_persistence(mask_roc, min_len)

    df["detected"] = pers_z_mean | pers_z_mad | pers_roc
    return df

# ---------------------------------------------------------------------------
# Event metric enrichment & NOAA alignment (Single validated definition)
# ---------------------------------------------------------------------------

from datetime import timedelta

def compute_event_metrics(df: pd.DataFrame, events: List[Dict[str, Any]], baseline_window_minutes: int = 30) -> List[Dict[str, Any]]:
    """Add statistical metrics to each detected event.

    Parameters
    ----------
    df: pd.DataFrame
        Cleaned GOES XRS dataframe containing at least the columns
        ``time_tag``, ``flux_clean``, ``z_mean``, ``z_mad`` and ``roc``.
    events: List[Dict]
        List of event dictionaries produced by ``extract_events`` (and merged).
    baseline_window_minutes: int, default 30
        Length of the pre‑event window used to compute a baseline flux.

    Returns
    -------
    List[Dict]
        The same list where each dict is augmented with:
        ``duration_min``, ``baseline_flux``, ``baseline_mad``,
        ``peak_to_baseline_ratio``, ``max_z_mean``, ``max_z_mad``, ``max_roc``.
    """
    # Ensure dataframe is sorted and indexed by time for fast slicing
    df = df.sort_values("time_tag").set_index("time_tag")
    enriched = []
    for ev in events:
        start = ev["start"]
        end = ev["end"]
        # Duration in minutes
        duration_min = (end - start).total_seconds() / 60.0
        # Baseline window: [start - window, start)
        baseline_start = start - timedelta(minutes=baseline_window_minutes)
        if baseline_start < df.index.min():
            baseline_start = df.index.min()
        baseline_series = df.loc[baseline_start:start]["flux_clean"]
        baseline_flux = baseline_series.median()
        baseline_mad = np.median(np.abs(baseline_series - baseline_series.median()))
        peak_to_baseline_ratio = ev["peak_flux"] / baseline_flux if baseline_flux != 0 else np.nan
        # Max statistics within the event window
        window_df = df.loc[start:end]
        max_z_mean = window_df["z_mean"].max() if "z_mean" in window_df.columns else np.nan
        max_z_mad = window_df["z_mad"].max() if "z_mad" in window_df.columns else np.nan
        max_roc = window_df["roc"].max() if "roc" in window_df.columns else np.nan
        enriched_event = ev.copy()
        enriched_event.update({
            "duration_min": duration_min,
            "baseline_flux": baseline_flux,
            "baseline_mad": baseline_mad,
            "peak_to_baseline_ratio": peak_to_baseline_ratio,
            "max_z_mean": max_z_mean,
            "max_z_mad": max_z_mad,
            "max_roc": max_roc,
        })
        enriched.append(enriched_event)
    return enriched

def compare_events(detected_events: List[Dict[str, Any]], flare_df: pd.DataFrame, tolerance_minutes: int = 5) -> Dict[str, Any]:
    """Match detected events to NOAA flare records.

    A detected event is considered a match if its start, peak and end times are each within
    ``tolerance_minutes`` of the corresponding NOAA times *or* if the intervals overlap.
    The function returns counts of matched, missed and false events as well as a list of
    timing errors (absolute difference in minutes between detected and NOAA peak times).
    """
    tol = timedelta(minutes=tolerance_minutes)
    matched = 0
    false = 0
    timing_errors = []
    matched_flares = set()
    for ev in detected_events:
        ev_start = ev["start"]
        ev_end = ev["end"]
        ev_peak = ev["peak_time"]
        best_match = None
        best_error = None
        for idx, row in flare_df.iterrows():
            flare_start = row["begin_time"]
            flare_end = row["end_time"]
            flare_peak = row["max_time"]
            overlap = (ev_start <= flare_end + tol) and (ev_end >= flare_start - tol)
            if overlap:
                err = abs((ev_peak - flare_peak).total_seconds()) / 60.0
                if best_error is None or err < best_error:
                    best_error = err
                    best_match = idx
        if best_match is not None:
            matched += 1
            timing_errors.append(best_error)
            matched_flares.add(best_match)
        else:
            false += 1
    missed = len(flare_df) - len(matched_flares)
    summary = {
        "matched": matched,
        "false": false,
        "missed": missed,
        "timing_errors_min": timing_errors,
    }
    if timing_errors:
        summary.update({
            "mean_error": np.mean(timing_errors),
            "median_error": np.median(timing_errors),
            "max_error": np.max(timing_errors),
        })
    else:
        summary.update({"mean_error": np.nan, "median_error": np.nan, "max_error": np.nan})
    return summary

# ---------------------------------------------------------------------------
# High‑level detector orchestrator (unchanged)
# ---------------------------------------------------------------------------
