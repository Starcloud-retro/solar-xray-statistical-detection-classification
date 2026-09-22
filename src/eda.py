"""
Exploratory Data Analysis (EDA) Module for GOES XRS Time-Series & Solar Flare Data.

Performs comprehensive statistical, temporal, and morphological signal characterization.
Computes non-parametric & parametric distribution metrics, checks data integrity,
and generates scientific diagnostic figures.
"""

import logging
from pathlib import Path
from typing import Dict, Any

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")  # Non-interactive headless backend
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

from src.config import BASE_DIR, CHANNEL_LONG, CHANNEL_SHORT

logger = logging.getLogger("EDA")
REPORTS_DIR = BASE_DIR / "reports" / "figures"
REPORTS_DIR.mkdir(parents=True, exist_ok=True)


def analyze_dataset_properties(df_xrs: pd.DataFrame, df_flares: pd.DataFrame) -> Dict[str, Any]:
    """
    Computes dataset dimensions, time coverage, sampling cadence, gaps,
    duplicates, and missing/invalid values.
    """
    results = {}

    # 1. Dataset Dimensions & Memory
    results["total_rows"] = len(df_xrs)
    results["memory_kb"] = float(df_xrs.memory_usage(deep=True).sum() / 1024.0)

    # 2. Time Coverage
    min_time = df_xrs["time_tag"].min()
    max_time = df_xrs["time_tag"].max()
    duration = max_time - min_time
    results["min_timestamp"] = str(min_time)
    results["max_timestamp"] = str(max_time)
    results["duration_hours"] = float(duration.total_seconds() / 3600.0)
    results["duration_days"] = float(duration.total_seconds() / 86400.0)

    # 3. Sampling Interval per channel
    cadence_stats = {}
    for ch in [CHANNEL_LONG, CHANNEL_SHORT]:
        ch_df = df_xrs[df_xrs["energy"] == ch].sort_values("time_tag")
        time_diffs = ch_df["time_tag"].diff().dropna().dt.total_seconds()
        cadence_stats[ch] = {
            "median_seconds": float(time_diffs.median()),
            "mean_seconds": float(time_diffs.mean()),
            "std_seconds": float(time_diffs.std()),
            "min_seconds": float(time_diffs.min()) if not time_diffs.empty else 0.0,
            "max_seconds": float(time_diffs.max()) if not time_diffs.empty else 0.0,
            "gap_count_gt_60s": int((time_diffs > 65.0).sum())  # Gaps greater than standard 1-min cadence
        }
    results["cadence"] = cadence_stats

    # 4. Duplicates & Missing Values
    results["duplicate_timestamps"] = int(df_xrs.duplicated(subset=["time_tag", "energy"]).sum())
    results["null_flux_count"] = int(df_xrs["flux"].isnull().sum())
    results["zero_flux_count"] = int((df_xrs["flux"] == 0.0).sum())
    results["negative_flux_count"] = int((df_xrs["flux"] < 0.0).sum())
    results["electron_contamination_count"] = int((df_xrs["electron_contaminaton"] == True).sum())

    # 5. Flare Event Class Distribution
    if not df_flares.empty:
        # Extract primary letter class (A, B, C, M, X)
        df_flares["class_letter"] = df_flares["max_class"].str[0]
        results["flare_class_counts"] = df_flares["class_letter"].value_counts().to_dict()
        results["total_flares"] = len(df_flares)
    else:
        results["flare_class_counts"] = {}
        results["total_flares"] = 0

    return results


def compute_flux_statistics(df_xrs: pd.DataFrame) -> Dict[str, Any]:
    """
    Computes parametric (mean, std, skew, kurtosis) and non-parametric (quantiles)
    statistics for raw X-ray flux and log10-transformed X-ray flux.
    """
    stats_out = {}
    quantiles_list = [0.001, 0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99, 0.999]

    for ch in [CHANNEL_LONG, CHANNEL_SHORT]:
        ch_flux = df_xrs[df_xrs["energy"] == ch]["flux"].dropna()
        # Ensure positive values for log10 transform
        pos_flux = ch_flux[ch_flux > 0.0]
        log_flux = np.log10(pos_flux)

        raw_stats = {
            "min": float(ch_flux.min()),
            "max": float(ch_flux.max()),
            "mean": float(ch_flux.mean()),
            "median": float(ch_flux.median()),
            "std": float(ch_flux.std()),
            "skewness": float(ch_flux.skew()),
            "kurtosis": float(ch_flux.kurtosis()),
            "quantiles": {f"p_{int(q*1000)/10}": float(val) for q, val in zip(quantiles_list, ch_flux.quantile(quantiles_list))}
        }

        log_stats = {
            "min": float(log_flux.min()),
            "max": float(log_flux.max()),
            "mean": float(log_flux.mean()),
            "median": float(log_flux.median()),
            "std": float(log_flux.std()),
            "skewness": float(log_flux.skew()),
            "kurtosis": float(log_flux.kurtosis()),
            "quantiles": {f"p_{int(q*1000)/10}": float(val) for q, val in zip(quantiles_list, log_flux.quantile(quantiles_list))}
        }

        stats_out[ch] = {"raw_flux": raw_stats, "log10_flux": log_stats}

    return stats_out


def generate_eda_figures(df_xrs: pd.DataFrame, df_flares: pd.DataFrame, save_dir: Path = REPORTS_DIR):
    """
    Generates publication-quality diagnostic plots for signal distribution
    and flare event cases.
    """
    plt.style.use("seaborn-v0_8-darkgrid" if "seaborn-v0_8-darkgrid" in plt.style.available else "default")

    # -------------------------------------------------------------------------
    # FIGURE 1: Raw vs Log10 Flux Distributions
    # -------------------------------------------------------------------------
    fig, axes = plt.subplots(2, 2, figsize=(14, 10))

    df_long = df_xrs[df_xrs["energy"] == CHANNEL_LONG]["flux"].dropna()
    df_short = df_xrs[df_xrs["energy"] == CHANNEL_SHORT]["flux"].dropna()

    # Raw Distributions (Extreme Right-Skew)
    axes[0, 0].hist(df_long, bins=50, color="navy", alpha=0.7, edgecolor="black")
    axes[0, 0].set_title(f"Raw Flux Distribution ({CHANNEL_LONG})\n[Highly Skewed]", fontsize=12, fontweight="bold")
    axes[0, 0].set_xlabel("X-Ray Irradiance (W/m²)")
    axes[0, 0].set_ylabel("Frequency")

    axes[0, 1].hist(df_short, bins=50, color="crimson", alpha=0.7, edgecolor="black")
    axes[0, 1].set_title(f"Raw Flux Distribution ({CHANNEL_SHORT})\n[Highly Skewed]", fontsize=12, fontweight="bold")
    axes[0, 1].set_xlabel("X-Ray Irradiance (W/m²)")
    axes[0, 1].set_ylabel("Frequency")

    # Log10 Distributions (Near Log-Normal / Multimodal)
    axes[1, 0].hist(np.log10(df_long[df_long > 0]), bins=50, color="navy", alpha=0.7, edgecolor="black")
    axes[1, 0].set_title(f"Log10(Flux) Distribution ({CHANNEL_LONG})\n[Symmetric / Near Log-Normal]", fontsize=12, fontweight="bold")
    axes[1, 0].set_xlabel("Log10(X-Ray Irradiance W/m²)")
    axes[1, 0].set_ylabel("Frequency")

    axes[1, 1].hist(np.log10(df_short[df_short > 0]), bins=50, color="crimson", alpha=0.7, edgecolor="black")
    axes[1, 1].set_title(f"Log10(Flux) Distribution ({CHANNEL_SHORT})\n[Symmetric / Near Log-Normal]", fontsize=12, fontweight="bold")
    axes[1, 1].set_xlabel("Log10(X-Ray Irradiance W/m²)")
    axes[1, 1].set_ylabel("Frequency")

    plt.tight_layout()
    fig1_path = save_dir / "fig1_flux_distributions.png"
    plt.savefig(fig1_path, dpi=300)
    plt.close()
    logger.info(f"Saved Figure 1 to {fig1_path}")

    # -------------------------------------------------------------------------
    # FIGURE 2: Complete 7-Day GOES XRS Time Series Overview
    # -------------------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(15, 6))

    df_l_ts = df_xrs[df_xrs["energy"] == CHANNEL_LONG].sort_values("time_tag")
    df_s_ts = df_xrs[df_xrs["energy"] == CHANNEL_SHORT].sort_values("time_tag")

    ax.plot(df_l_ts["time_tag"], df_l_ts["flux"], label=f"Long Channel ({CHANNEL_LONG})", color="navy", lw=1.2)
    ax.plot(df_s_ts["time_tag"], df_s_ts["flux"], label=f"Short Channel ({CHANNEL_SHORT})", color="crimson", lw=1.0, alpha=0.8)

    # Threshold horizontal reference lines for GOES Flare Classes
    flare_levels = {
        "B-Class": 1e-7,
        "C-Class": 1e-6,
        "M-Class": 1e-5,
        "X-Class": 1e-4
    }
    colors = ["gray", "goldenrod", "orange", "red"]
    for (label, lvl), c in zip(flare_levels.items(), colors):
        ax.axhline(lvl, color=c, linestyle="--", alpha=0.6, label=f"{label} (10^{int(np.log10(lvl))})")

    ax.set_yscale("log")
    ax.set_title("GOES-18 Primary X-Ray Flux Telemetry (7-Day Overview)", fontsize=14, fontweight="bold")
    ax.set_xlabel("Timestamp (UTC)")
    ax.set_ylabel("X-Ray Irradiance (W/m²) [Log Scale]")
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %d %H:%M"))
    ax.legend(loc="upper right", frameon=True)

    plt.tight_layout()
    fig2_path = save_dir / "fig2_full_timeseries_overview.png"
    plt.savefig(fig2_path, dpi=300)
    plt.close()
    logger.info(f"Saved Figure 2 to {fig2_path}")

    # -------------------------------------------------------------------------
    # FIGURE 3: Representative Flare Event Window Profiles
    # -------------------------------------------------------------------------
    if not df_flares.empty:
        # Select representative flares (up to 3 distinct flares)
        sample_flares = df_flares.head(3)

        fig, axes = plt.subplots(len(sample_flares), 1, figsize=(14, 4 * len(sample_flares)), sharex=False)
        if len(sample_flares) == 1:
            axes = [axes]

        for i, (_, flare) in enumerate(sample_flares.iterrows()):
            ax = axes[i]
            # Define window: 30 mins before begin_time to 30 mins after end_time
            w_start = flare["begin_time"] - pd.Timedelta(minutes=30)
            w_end = flare["end_time"] + pd.Timedelta(minutes=30)

            sub_xrs = df_l_ts[(df_l_ts["time_tag"] >= w_start) & (df_l_ts["time_tag"] <= w_end)]

            ax.plot(sub_xrs["time_tag"], sub_xrs["flux"], color="navy", lw=1.8, label="XRS-B (0.1-0.8 nm)")

            # Mark Start, Peak, End times
            ax.axvline(flare["begin_time"], color="green", linestyle="--", lw=1.5, label=f"Start: {flare['begin_time'].strftime('%H:%M')}")
            ax.axvline(flare["max_time"], color="red", linestyle="-.", lw=1.5, label=f"Peak ({flare['max_class']}): {flare['max_time'].strftime('%H:%M')}")
            ax.axvline(flare["end_time"], color="purple", linestyle="--", lw=1.5, label=f"End: {flare['end_time'].strftime('%H:%M')}")

            # Highlight active flare window
            ax.axvspan(flare["begin_time"], flare["end_time"], color="yellow", alpha=0.2, label="Active Flare Window")

            ax.set_yscale("log")
            ax.set_title(f"Flare Event Profile: {flare['max_class']} (Satellite GOES-{flare['satellite']})", fontsize=12, fontweight="bold")
            ax.set_ylabel("Flux (W/m²)")
            ax.set_xlabel("Time (UTC)")
            ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
            ax.legend(loc="upper left", frameon=True, fontsize=9)

        plt.tight_layout()
        fig3_path = save_dir / "fig3_flare_event_profiles.png"
        plt.savefig(fig3_path, dpi=300)
        plt.close()
        logger.info(f"Saved Figure 3 to {fig3_path}")
