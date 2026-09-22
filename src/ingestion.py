"""
Data Ingestion Module for NOAA GOES XRS Time-Series Data & Solar Flare Reports.

This module acquires, logs, validates, and locally stores real GOES X-ray flux
telemetry and official solar event reports directly from NOAA SWPC services.
"""

import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Tuple, Dict, Any

import pandas as pd
import requests

from src.config import (
    GOES_XRS_7DAY_URL,
    GOES_FLARE_REPORT_7DAY_URL,
    RAW_DATA_DIR,
    LOG_DIR,
    XRS_REQUIRED_COLUMNS,
    FLARE_REPORT_REQUIRED_COLUMNS,
    CHANNEL_LONG,
    CHANNEL_SHORT
)

# Configure module logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.FileHandler(LOG_DIR / "data_ingestion.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("DataIngestion")


def download_and_save_raw(url: str, prefix: str, save_dir: Path = RAW_DATA_DIR) -> Tuple[list, Path, Dict[str, Any]]:
    """
    Downloads raw JSON payload from an official NOAA URL, logs metadata,
    and stores an un-modified local copy for strict scientific reproducibility.

    Returns:
        (raw_json_data, saved_file_path, metadata_dict)
    """
    retrieval_time = datetime.now(timezone.utc)
    logger.info(f"Initiating raw data fetch from NOAA endpoint: {url}")

    response = requests.get(url, timeout=15)
    response.raise_for_status()

    raw_data = response.json()
    timestamp_str = retrieval_time.strftime("%Y%m%d_%H%M%S")
    filename = f"{prefix}_raw_{timestamp_str}.json"
    file_path = save_dir / filename

    # Store exact un-modified raw JSON payload
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(raw_data, f, indent=2)

    metadata = {
        "source_url": url,
        "retrieval_timestamp_utc": retrieval_time.isoformat(),
        "local_file_path": str(file_path),
        "record_count": len(raw_data),
        "status_code": response.status_code
    }

    # Save metadata sidecar log
    meta_path = save_dir / f"{prefix}_metadata_{timestamp_str}.json"
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)

    logger.info(f"Successfully saved un-modified raw data ({len(raw_data)} records) to {file_path}")
    return raw_data, file_path, metadata


def validate_schema(df: pd.DataFrame, expected_columns: list, dataset_name: str) -> bool:
    """
    Validates that the ingested DataFrame contains all expected NOAA fields.
    """
    missing = [col for col in expected_columns if col not in df.columns]
    if missing:
        err_msg = f"Schema validation failed for {dataset_name}. Missing columns: {missing}"
        logger.error(err_msg)
        raise ValueError(err_msg)
    
    logger.info(f"Schema validation passed for {dataset_name}. All {len(expected_columns)} columns present.")
    return True


def ingest_goes_xrs(url: str = GOES_XRS_7DAY_URL, save_dir: Path = RAW_DATA_DIR) -> pd.DataFrame:
    """
    Ingests GOES XRS 1-minute time-series telemetry.

    - Downloads and saves raw payload for reproducibility.
    - Parses timestamps into UTC-aware datetime objects.
    - Validates columns against official NOAA schema.
    """
    raw_data, file_path, metadata = download_and_save_raw(url, prefix="goes_xrs", save_dir=save_dir)
    df = pd.DataFrame(raw_data)

    # Schema Validation
    validate_schema(df, XRS_REQUIRED_COLUMNS, "GOES XRS Time-Series")

    # Timestamp conversion to UTC-aware datetime
    df["time_tag"] = pd.to_datetime(df["time_tag"], utc=True)

    # Sort chronologically by time_tag and channel
    df = df.sort_values(by=["time_tag", "energy"]).reset_index(drop=True)

    logger.info(
        f"Ingested XRS time-series from {df['time_tag'].min()} to {df['time_tag'].max()} UTC "
        f"({len(df)} total rows across channels)."
    )
    return df


def ingest_flare_report(url: str = GOES_FLARE_REPORT_7DAY_URL, save_dir: Path = RAW_DATA_DIR) -> pd.DataFrame:
    """
    Ingests official NOAA GOES Solar Flare Event Reports.

    - Downloads and saves raw payload for reproducibility.
    - Converts event timestamps (begin_time, max_time, end_time) to UTC-aware datetimes.
    - Validates columns against official NOAA schema.
    """
    raw_data, file_path, metadata = download_and_save_raw(url, prefix="goes_flare_report", save_dir=save_dir)
    df = pd.DataFrame(raw_data)

    if df.empty:
        logger.warning("Ingested flare report is empty (no flares recorded in timeframe).")
        return df

    # Schema Validation
    validate_schema(df, FLARE_REPORT_REQUIRED_COLUMNS, "GOES Flare Report")

    # Timestamp conversions to UTC-aware datetimes
    time_cols = ["time_tag", "begin_time", "max_time", "end_time"]
    if "max_ratio_time" in df.columns:
        time_cols.append("max_ratio_time")

    for col in time_cols:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], utc=True)

    df = df.sort_values(by="begin_time").reset_index(drop=True)
    logger.info(f"Ingested {len(df)} flare events spanning {df['begin_time'].min()} to {df['begin_time'].max()} UTC.")
    return df


def align_xrs_and_flares(df_xrs: pd.DataFrame, df_flares: pd.DataFrame) -> pd.DataFrame:
    """
    Aligns continuous 1-minute GOES XRS long-channel (0.1-0.8 nm) time-series data
    with official solar flare event reports using UTC timestamp interval matching.

    Adds event annotations to XRS time-series samples:
    - `is_flare_event`: boolean flag indicating whether sample falls within [begin_time, end_time] of a flare.
    - `associated_flare_class`: official peak flare classification (e.g., 'C2.1', 'M1.5') if active.
    - `associated_flare_id`: unique event index.
    """
    # Select primary classification channel (0.1 - 0.8 nm)
    df_long = df_xrs[df_xrs["energy"] == CHANNEL_LONG].copy()
    df_long = df_long.sort_values("time_tag").reset_index(drop=True)

    df_long["is_flare_event"] = False
    df_long["associated_flare_class"] = None
    df_long["associated_flare_id"] = None

    if df_flares.empty:
        logger.info("No flare events available for alignment.")
        return df_long

    aligned_count = 0
    for idx, flare in df_flares.iterrows():
        mask = (df_long["time_tag"] >= flare["begin_time"]) & (df_long["time_tag"] <= flare["end_time"])
        matched_samples = mask.sum()

        if matched_samples > 0:
            aligned_count += 1
            df_long.loc[mask, "is_flare_event"] = True
            df_long.loc[mask, "associated_flare_class"] = flare["max_class"]
            df_long.loc[mask, "associated_flare_id"] = idx

    logger.info(
        f"Aligned {aligned_count} / {len(df_flares)} flare events with XRS time-series data. "
        f"Tagged {df_long['is_flare_event'].sum()} XRS 1-minute samples as active flare duration."
    )
    return df_long
