# Raw-data provenance

The public/presentation repository intentionally does not include the repeated timestamped
NOAA downloads that accumulated during development.

The frozen processed snapshot in `data/processed/` was produced from NOAA/SWPC GOES
soft-X-ray telemetry and NOAA flare-event records.

Primary sources used by the project:

- GOES X-ray 7-day JSON:
  `https://services.swpc.noaa.gov/json/goes/primary/xrays-7-day.json`
- GOES X-ray flare reports:
  `https://services.swpc.noaa.gov/json/goes/primary/xray-flares-7-day.json`

Use `src/ingestion.py` if you want to create a fresh raw download. A fresh download is
new data and will not reproduce the frozen September 2026 experiment exactly.
