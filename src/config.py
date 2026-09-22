"""
Configuration constants and official data schema definitions for NOAA GOES XRS pipeline.
"""
from pathlib import Path

# Base directories
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
RAW_DATA_DIR = DATA_DIR / "raw"
LOG_DIR = BASE_DIR / "logs"

# Ensure directories exist
RAW_DATA_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

# Official NOAA SWPC Real-time / Near-Real-Time JSON Endpoints
NOAA_SWPC_BASE = "https://services.swpc.noaa.gov/json/goes/primary"
GOES_XRS_1DAY_URL = f"{NOAA_SWPC_BASE}/xrays-1-day.json"
GOES_XRS_7DAY_URL = f"{NOAA_SWPC_BASE}/xrays-7-day.json"
GOES_FLARE_REPORT_7DAY_URL = f"{NOAA_SWPC_BASE}/xray-flares-7-day.json"

# Official NOAA NCEI Historical Science Quality L2 Directory
NOAA_NCEI_L2_BASE = "https://data.ngdc.noaa.gov/platforms/solar-space-observing-satellites/goes/goes16/l2/data/xrsf-l2-avg1m_science/"

# X-Ray Channels
CHANNEL_SHORT = "0.05-0.4nm"  # XRS-A: 0.5 - 4.0 Å (High temperature flare plasma)
CHANNEL_LONG = "0.1-0.8nm"   # XRS-B: 1.0 - 8.0 Å (Standard GOES solar flare classification channel)

# Official Expected Data Schemas
XRS_REQUIRED_COLUMNS = [
    "time_tag",
    "satellite",
    "flux",
    "observed_flux",
    "electron_correction",
    "electron_contaminaton",
    "energy"
]

FLARE_REPORT_REQUIRED_COLUMNS = [
    "time_tag",
    "begin_time",
    "begin_class",
    "max_time",
    "max_class",
    "max_xrlong",
    "end_time",
    "end_class",
    "satellite"
]
