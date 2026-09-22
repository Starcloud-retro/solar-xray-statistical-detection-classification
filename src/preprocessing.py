"""
Preprocessing Module for GOES XRS Time-Series Data.

Applies scientifically rigorous preprocessing:
- Chronological sorting & duplicate resolution preserving highest-quality observations.
- Detection and flagging of invalid/sentinel values (NOAA specification).
- Reindexing to a uniform 1-minute time grid and gap duration analysis.
- Short gap interpolation (<= 3 mins) in log10 space to preserve exponential dynamics.
- Partitioning long gaps (> 3 mins) into continuous valid segments without artificial interpolation.
- Preservation of raw flare peak amplitudes (no over-smoothing).
- Detailed audit logging and preprocessing reporting.
"""

import json
import logging
from pathlib import Path
from typing import Tuple, Dict, Any

import numpy as np
import pandas as pd

from src.config import BASE_DIR, DATA_DIR, RAW_DATA_DIR, CHANNEL_LONG, CHANNEL_SHORT

logger = logging.getLogger("Preprocessing")
PROCESSED_DATA_DIR = DATA_DIR / "processed"
REPORTS_DIR = BASE_DIR / "reports"
PROCESSED_DATA_DIR.mkdir(parents=True, exist_ok=True)
REPORTS_DIR.mkdir(parents=True, exist_ok=True)


def preprocess_goes_xrs(
    df_xrs: pd.DataFrame,
    max_interp_gap_mins: int = 3,
    save_dir: Path = PROCESSED_DATA_DIR,
    report_dir: Path = REPORTS_DIR
) -> Tuple[pd.DataFrame, Dict[str, Any]]:
    """
    Executes scientifically sound preprocessing on GOES XRS telemetry.

    Returns:
        (df_cleaned, report_dict)
    """
    original_row_count = len(df_xrs)
    report = {
        "original_rows": original_row_count,
        "duplicates_removed": 0,
        "invalid_sentinel_values_found": 0,
        "missing_flux_values_pre_imputation": 0,
        "short_gaps_interpolated": 0,
        "long_gaps_uninterpolated": 0,
        "rows_removed": 0,
        "rows_retained": 0,
        "retention_rate_pct": 0.0,
        "audit_log": []
    }

    logger.info(f"Starting Stage 3 Preprocessing on {original_row_count} raw XRS observations.")
    report["audit_log"].append(f"Ingested {original_row_count} raw observations.")

    # -------------------------------------------------------------------------
    # STEP 1: Chronological Sorting
    # -------------------------------------------------------------------------
    df_proc = df_xrs.copy()
    df_proc["time_tag"] = pd.to_datetime(df_proc["time_tag"], utc=True)
    df_proc = df_proc.sort_values(by=["energy", "time_tag"]).reset_index(drop=True)
    report["audit_log"].append("Sorted observations chronologically by (energy, time_tag).")

    # -------------------------------------------------------------------------
    # STEP 2: Duplicate Resolution
    # -------------------------------------------------------------------------
    # Check for duplicate timestamps per channel
    duplicate_mask = df_proc.duplicated(subset=["time_tag", "energy"], keep=False)
    num_duplicates = int(duplicate_mask.sum())
    report["duplicates_removed"] = num_duplicates

    if num_duplicates > 0:
        # Sort by quality: valid flux first, electron_contaminaton==False first
        df_proc["is_valid_flux"] = df_proc["flux"].notnull() & (df_proc["flux"] > 0)
        df_proc = df_proc.sort_values(
            by=["energy", "time_tag", "is_valid_flux", "electron_contaminaton"],
            ascending=[True, True, False, True]
        )
        df_proc = df_proc.drop_duplicates(subset=["time_tag", "energy"], keep="first").reset_index(drop=True)
        df_proc = df_proc.drop(columns=["is_valid_flux"])
        report["audit_log"].append(f"Resolved and removed {num_duplicates} duplicate observations.")
    else:
        report["audit_log"].append("Zero duplicate timestamps detected.")

    # -------------------------------------------------------------------------
    # STEP 3: Detect Invalid / Sentinel Flux Values
    # -------------------------------------------------------------------------
    # According to NOAA GOES XRS specs:
    # - Sentinel / missing values: null, NaN, or <= 0.0 W/m² (flux cannot be physically <= 0)
    # - Physical upper bound check: flux > 1.0 W/m² (unphysical saturation artifact)
    invalid_mask = (
        df_proc["flux"].isnull() |
        (df_proc["flux"] <= 0.0) |
        (df_proc["flux"] > 1.0)
    )
    num_invalid = int(invalid_mask.sum())
    report["invalid_sentinel_values_found"] = num_invalid
    report["missing_flux_values_pre_imputation"] = num_invalid

    if num_invalid > 0:
        df_proc.loc[invalid_mask, "flux"] = np.nan
        report["audit_log"].append(f"Flagged {num_invalid} invalid/sentinel flux values as NaN.")
    else:
        report["audit_log"].append("Zero invalid or sentinel flux values detected.")

    # -------------------------------------------------------------------------
    # STEP 4: Uniform Time Grid Reindexing & Gap Analysis per Channel
    # -------------------------------------------------------------------------
    processed_channels = []

    for ch in [CHANNEL_LONG, CHANNEL_SHORT]:
        ch_df = df_proc[df_proc["energy"] == ch].set_index("time_tag")

        # Create continuous 1-minute time grid
        full_grid = pd.date_range(
            start=ch_df.index.min(),
            end=ch_df.index.max(),
            freq="1min",
            tz="UTC",
            name="time_tag"
        )

        ch_reindexed = ch_df.reindex(full_grid)
        ch_reindexed["energy"] = ch
        ch_reindexed["satellite"] = ch_reindexed["satellite"].bfill().ffill()

        # Identify missing gaps
        ch_reindexed["is_missing_raw"] = ch_reindexed["flux"].isnull()

        # Calculate gap block sizes using consecutive NaN grouping
        gap_block_ids = (~ch_reindexed["is_missing_raw"]).cumsum()
        gap_sizes = ch_reindexed.groupby(gap_block_ids)["is_missing_raw"].transform("sum")

        ch_reindexed["gap_size_mins"] = np.where(ch_reindexed["is_missing_raw"], gap_sizes, 0)

        # ---------------------------------------------------------------------
        # STEP 5: Controlled Short-Gap Imputation in Log10 Space
        # ---------------------------------------------------------------------
        # Compute log10 flux for positive values
        ch_reindexed["log10_flux"] = np.where(
            ch_reindexed["flux"] > 0,
            np.log10(ch_reindexed["flux"]),
            np.nan
        )

        # Short gap mask: missing AND gap_size_mins <= max_interp_gap_mins
        short_gap_mask = ch_reindexed["is_missing_raw"] & (ch_reindexed["gap_size_mins"] <= max_interp_gap_mins)
        long_gap_mask = ch_reindexed["is_missing_raw"] & (ch_reindexed["gap_size_mins"] > max_interp_gap_mins)

        num_short = int(short_gap_mask.sum())
        num_long = int(long_gap_mask.sum())

        report["short_gaps_interpolated"] += num_short
        report["long_gaps_uninterpolated"] += num_long

        # Linear interpolation in log10 space ONLY for short gaps
        # First linearly interpolate log10_flux with max limit
        interp_log = ch_reindexed["log10_flux"].interpolate(method="time", limit=max_interp_gap_mins)

        # Apply interpolated values ONLY where short_gap_mask is True
        ch_reindexed["log10_flux_clean"] = ch_reindexed["log10_flux"].copy()
        ch_reindexed.loc[short_gap_mask, "log10_flux_clean"] = interp_log[short_gap_mask]

        # Convert back to raw flux space
        ch_reindexed["flux_clean"] = np.power(10.0, ch_reindexed["log10_flux_clean"])

        # For long gaps, ensure flux_clean remains NaN
        ch_reindexed.loc[long_gap_mask, "flux_clean"] = np.nan
        ch_reindexed.loc[long_gap_mask, "log10_flux_clean"] = np.nan

        # ---------------------------------------------------------------------
        # STEP 6: Segment ID Assignment (Continuous Valid Blocks)
        # ---------------------------------------------------------------------
        # Long gaps split data into distinct valid continuous segments
        ch_reindexed["segment_id"] = long_gap_mask.cumsum()

        # Flags for preprocessing record keeping
        ch_reindexed["was_imputed"] = short_gap_mask
        ch_reindexed["is_long_gap"] = long_gap_mask

        processed_channels.append(ch_reindexed.reset_index())

    df_cleaned = pd.concat(processed_channels, ignore_index=True)
    df_cleaned = df_cleaned.sort_values(by=["energy", "time_tag"]).reset_index(drop=True)

    # -------------------------------------------------------------------------
    # STEP 7: Data Retention Accounting
    # -------------------------------------------------------------------------
    report["rows_retained"] = len(df_cleaned)
    report["rows_removed"] = report["duplicates_removed"]
    report["retention_rate_pct"] = float(round((report["rows_retained"] / original_row_count) * 100.0, 2))

    report["audit_log"].append(
        f"Reindexed data to uniform 1-minute grid. Interpolated {report['short_gaps_interpolated']} short-gap samples (<= {max_interp_gap_mins}m). "
        f"Preserved {report['long_gaps_uninterpolated']} long-gap samples as NaN without interpolation."
    )

    # Save cleaned DataFrame to Parquet & CSV in processed data directory
    csv_path = save_dir / "goes_xrs_cleaned.csv"
    df_cleaned.to_csv(csv_path, index=False)
    logger.info(f"Saved cleaned preprocessed dataset to {csv_path}")

    # Save Preprocessing Report JSON
    report_path = report_dir / "preprocessing_report.json"
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    logger.info(f"Saved preprocessing report to {report_path}")

    return df_cleaned, report
