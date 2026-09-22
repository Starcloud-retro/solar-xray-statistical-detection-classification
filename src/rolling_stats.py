"""
Rolling Time-Series Statistics & Local Slope Analysis Module.

Computes rolling baseline estimators (Mean, Median), rolling dispersion metrics (Std, MAD, IQR),
rolling quantiles, first differences, percentage changes, and local slope (rate of rise)
across multiple scientifically justified window sizes.
"""

import logging
from pathlib import Path
from typing import Dict, Any, List

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

from src.config import BASE_DIR, CHANNEL_LONG, CHANNEL_SHORT

logger = logging.getLogger("RollingStats")
REPORTS_DIR = BASE_DIR / "reports" / "figures"
REPORTS_DIR.mkdir(parents=True, exist_ok=True)


def compute_rolling_statistics(
    df: pd.DataFrame,
    window_mins: int = 30,
    min_periods: int = 5,
    uncontaminated: bool = False,
    lag: int = 0
) -> pd.DataFrame:
    """
    Computes rolling metrics on a 1-minute cadence time series DataFrame for a single channel.

    Assumes DataFrame is indexed or sorted by UTC timestamp `time_tag`.
    Operates primarily in log10(flux) space to maintain Gaussian noise characteristics.

    If `uncontaminated=True` or `lag > 0`, baseline statistics are computed strictly from
    observations prior to time t (lagging by default 1 minute), ensuring that an impulsive
    flare eruption at time t does not contaminate its own baseline reference.
    """
    df_out = df.copy()
    if "time_tag" in df_out.columns:
        df_out = df_out.sort_values("time_tag").reset_index(drop=True)

    # Primary series for statistical rolling operations: log10_flux_clean
    log_flux = df_out["log10_flux_clean"]
    raw_flux = df_out["flux_clean"]

    effective_lag = lag if lag > 0 else (1 if uncontaminated else 0)
    series_for_baseline = log_flux.shift(effective_lag) if effective_lag > 0 else log_flux

    # 1. Rolling Mean & Standard Deviation
    df_out[f"rolling_mean_{window_mins}m"] = series_for_baseline.rolling(window=window_mins, min_periods=min_periods).mean()
    df_out[f"rolling_std_{window_mins}m"] = series_for_baseline.rolling(window=window_mins, min_periods=min_periods).std()

    # 2. Rolling Median
    df_out[f"rolling_median_{window_mins}m"] = series_for_baseline.rolling(window=window_mins, min_periods=min_periods).median()

    # 3. Rolling MAD (Raw and Scaled by 1.4826)
    def _rolling_mad_raw_func(window_slice):
        med = np.median(window_slice)
        return float(np.median(np.abs(window_slice - med)))

    raw_mad_series = series_for_baseline.rolling(window=window_mins, min_periods=min_periods).apply(
        _rolling_mad_raw_func, raw=True
    )
    df_out[f"rolling_mad_raw_{window_mins}m"] = raw_mad_series
    # rolling_mad_scaled is 1.4826 * raw_mad (applied strictly once)
    df_out[f"rolling_mad_scaled_{window_mins}m"] = 1.4826 * raw_mad_series
    # Keep rolling_mad_{window_mins}m as alias to scaled MAD for backward compatibility
    df_out[f"rolling_mad_{window_mins}m"] = df_out[f"rolling_mad_scaled_{window_mins}m"]

    # 4. Rolling Min & Max
    df_out[f"rolling_min_{window_mins}m"] = log_flux.rolling(window=window_mins, min_periods=min_periods).min()
    df_out[f"rolling_max_{window_mins}m"] = log_flux.rolling(window=window_mins, min_periods=min_periods).max()

    # 5. Rolling Quantiles (p05, p25, p75, p95)
    df_out[f"rolling_q05_{window_mins}m"] = log_flux.rolling(window=window_mins, min_periods=min_periods).quantile(0.05)
    df_out[f"rolling_q25_{window_mins}m"] = log_flux.rolling(window=window_mins, min_periods=min_periods).quantile(0.25)
    df_out[f"rolling_q75_{window_mins}m"] = log_flux.rolling(window=window_mins, min_periods=min_periods).quantile(0.75)
    df_out[f"rolling_q95_{window_mins}m"] = log_flux.rolling(window=window_mins, min_periods=min_periods).quantile(0.95)

    # 6. First Difference (Delta log10 Flux per minute)
    # ΔY_t = Y_t - Y_{t-1} = log10(X_t / X_{t-1})
    df_out["first_difference_log"] = log_flux.diff()
    df_out["first_difference_raw"] = raw_flux.diff()

    # 7. Percentage Change on Raw Flux
    # P_t = ((X_t - X_{t-1}) / X_{t-1}) * 100%
    df_out["pct_change_raw"] = raw_flux.pct_change() * 100.0

    # 8. Local Slope / Rate of Rise (5-minute trailing linear regression slope of log10 flux)
    # d/dt log10(Flux) in log10(W/m²)/min
    def _local_slope_5m(slice_vals):
        # x coordinates: 0, 1, 2, 3, 4 minutes
        if len(slice_vals) < 3 or np.isnan(slice_vals).any():
            return np.nan
        t = np.arange(len(slice_vals))
        slope, _ = np.polyfit(t, slice_vals, 1)
        return slope

    df_out["local_slope_5m"] = log_flux.rolling(window=5, min_periods=3).apply(_local_slope_5m, raw=True)

    return df_out


def generate_rolling_diagnostic_plots(
    df_clean: pd.DataFrame,
    df_flares: pd.DataFrame,
    window_sizes: List[int] = [10, 30, 60, 180],
    save_dir: Path = REPORTS_DIR
):
    """
    Generates comprehensive plots demonstrating window size effects,
    rolling baselines, variability bands, and rate-of-rise slopes.
    """
    plt.style.use("seaborn-v0_8-darkgrid" if "seaborn-v0_8-darkgrid" in plt.style.available else "default")

    # Ensure timestamps are proper datetime objects for slicing
    df_long = df_clean[df_clean["energy"] == CHANNEL_LONG].copy()
    df_long["time_tag"] = pd.to_datetime(df_long["time_tag"], utc=True)
    df_long = df_long.sort_values("time_tag").reset_index(drop=True)

    # Precompute rolling stats for all window sizes
    dfs_windowed = {}
    for w in window_sizes:
        dfs_windowed[w] = compute_rolling_statistics(df_long, window_mins=w)

    # -------------------------------------------------------------------------
    # FIGURE 1: Window Size Comparison around a Major Flare Event
    # -------------------------------------------------------------------------
    if not df_flares.empty:
        # Select an active flare (e.g. M-class or largest C-class)
        top_flare = df_flares.sort_values("max_xrlong", ascending=False).iloc[0]
        w_start = top_flare["begin_time"] - pd.Timedelta(minutes=60)
        w_end = top_flare["end_time"] + pd.Timedelta(minutes=120)

        fig, axes = plt.subplots(len(window_sizes), 1, figsize=(15, 3 * len(window_sizes)), sharex=True)

        for i, w in enumerate(window_sizes):
            ax = axes[i]
            w_df = dfs_windowed[w]
            sub = w_df[(w_df["time_tag"] >= w_start) & (w_df["time_tag"] <= w_end)]

            # Raw signal in log space
            ax.plot(sub["time_tag"], sub["log10_flux_clean"], color="black", lw=1.0, label="Log10 Flux (Observed)")

            # Rolling Median Baseline
            ax.plot(sub["time_tag"], sub[f"rolling_median_{w}m"], color="blue", lw=1.8, label=f"Rolling Median (W={w}m)")

            # Rolling Mean Baseline (Non-robust comparison)
            ax.plot(sub["time_tag"], sub[f"rolling_mean_{w}m"], color="red", linestyle="--", lw=1.2, label=f"Rolling Mean (W={w}m)")

            # Rolling MAD 3-sigma Noise Envelope
            upper_mad = sub[f"rolling_median_{w}m"] + 3.0 * sub[f"rolling_mad_{w}m"]
            lower_mad = sub[f"rolling_median_{w}m"] - 3.0 * sub[f"rolling_mad_{w}m"]
            ax.fill_between(sub["time_tag"], lower_mad, upper_mad, color="blue", alpha=0.15, label="±3 MAD Noise Band")

            # Flare Start, Peak, End markers
            ax.axvline(top_flare["begin_time"], color="green", linestyle="--", alpha=0.7)
            ax.axvline(top_flare["max_time"], color="red", linestyle="-.", alpha=0.7)
            ax.axvline(top_flare["end_time"], color="purple", linestyle="--", alpha=0.7)

            ax.set_title(f"Window Size W = {w} minutes (Phase Lag ≈ {w/2:.0f} mins)", fontsize=11, fontweight="bold")
            ax.set_ylabel("Log10(Flux W/m²)")
            ax.legend(loc="upper left", frameon=True, fontsize=8)

        axes[-1].set_xlabel("Time (UTC)")
        axes[-1].xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
        plt.suptitle(f"Comparison of Rolling Window Baselines around {top_flare['max_class']} Flare Event", fontsize=13, fontweight="bold", y=0.99)
        plt.tight_layout()

        fig1_path = save_dir / "fig4_window_size_comparison.png"
        plt.savefig(fig1_path, dpi=300)
        plt.close()
        logger.info(f"Saved Figure 4 to {fig1_path}")

    # -------------------------------------------------------------------------
    # FIGURE 2: Derivatives, First Difference & Local Slope Analysis
    # -------------------------------------------------------------------------
    w30_df = dfs_windowed[30]
    fig, axes = plt.subplots(3, 1, figsize=(15, 10), sharex=True)

    # Panel 1: Log10 Flux & Rolling Median (30m)
    axes[0].plot(w30_df["time_tag"], w30_df["log10_flux_clean"], color="navy", lw=1.0, label="Log10(Flux)")
    axes[0].plot(w30_df["time_tag"], w30_df["rolling_median_30m"], color="crimson", lw=1.5, label="30m Rolling Median Baseline")
    axes[0].set_ylabel("Log10(Flux W/m²)")
    axes[0].set_title("GOES-18 Long Channel Telemetry & 30-Minute Rolling Baseline", fontsize=12, fontweight="bold")
    axes[0].legend(loc="upper right")

    # Panel 2: First Difference (Δ Log10 Flux / min)
    axes[1].plot(w30_df["time_tag"], w30_df["first_difference_log"], color="darkgreen", lw=1.0, label="1-min First Difference (Δ Log10 Flux)")
    axes[1].axhline(0.0, color="black", linestyle="--", alpha=0.5)
    axes[1].axhline(0.05, color="red", linestyle=":", alpha=0.7, label="Rapid Rise Threshold (+0.05 dex/min)")
    axes[1].set_ylabel("Δ Log10(Flux) / min")
    axes[1].set_title("First-Difference Derivative Signal (Impulsive Flare Spike Detector)", fontsize=12, fontweight="bold")
    axes[1].legend(loc="upper right")

    # Panel 3: 5-Minute Local Slope (Rate of Rise)
    axes[2].plot(w30_df["time_tag"], w30_df["local_slope_5m"], color="purple", lw=1.2, label="5-min Local Slope (d/dt Log10 Flux)")
    axes[2].axhline(0.0, color="black", linestyle="--", alpha=0.5)
    axes[2].set_ylabel("Slope (dex/min)")
    axes[2].set_xlabel("Time (UTC)")
    axes[2].set_title("Local Slope / Rate of Rise (Impulsive Heating Phase Metric)", fontsize=12, fontweight="bold")
    axes[2].xaxis.set_major_formatter(mdates.DateFormatter("%b %d %H:%M"))
    axes[2].legend(loc="upper right")

    plt.tight_layout()
    fig2_path = save_dir / "fig5_derivatives_and_slopes.png"
    plt.savefig(fig2_path, dpi=300)
    plt.close()
    logger.info(f"Saved Figure 5 to {fig2_path}")
