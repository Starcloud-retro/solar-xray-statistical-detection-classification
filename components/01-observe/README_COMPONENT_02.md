# Graphic 02 — Real CSV → Time-Series Interactive Component

This is **not an infographic image**.

It is a coded website graphic using the project's real:

```text
data/processed/goes_xrs_cleaned.csv
```

The component demonstrates one key idea visually:

> a time-series graph is simply the CSV measurements placed in chronological order.

## What the component does

- loads the exact project CSV
- filters to GOES XRS-B (`0.1–0.8 nm`)
- reports the full 10,078-row XRS-B dataset window
- uses the first 180 real rows for the animation
- highlights one CSV row at a time
- highlights the exact matching point on the graph
- shows the physical flux and log10 flux for that row
- lets the visitor drag through rows with a scrubber
- explicitly states that 10,078 observations are **not** 10,078 flares

## Why this comes immediately after the hero

The visual sequence becomes:

```text
Sun
↓
GOES satellite
↓
CSV measurement
↓
point on graph
↓
time series
```

So the artistic hero hands off directly to real scientific data.

## Linux test

Extract:

```bash
rm -rf /tmp/csv-timeseries
mkdir -p /tmp/csv-timeseries
unzip ~/Downloads/solar-component-02-csv-timeseries.zip -d /tmp/csv-timeseries
cd /tmp/csv-timeseries
```

Run:

```bash
python3 -m http.server 8000
```

Open:

```bash
xdg-open http://localhost:8000
```

Stop:

```text
Ctrl+C
```

## Future website integration

Later, copy:

```bash
index.html
component.css
component.js
assets/data/goes_xrs_cleaned.csv
```

into the main website structure, or extract just the `story-frame` HTML/CSS/JS into the Research Journey.

Do not convert this scientific graphic into a generated image. Keeping it coded means the values remain tied to the real CSV.
