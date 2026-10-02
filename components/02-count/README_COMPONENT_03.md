# Graphic 03 — Dataset Window + 10,078 Observations

This component explains the **scale of the time-series dataset** before the website starts talking about events.

It uses exact metadata derived from the project CSV:

- GOES XRS-B (`0.1–0.8 nm`)
- first timestamp
- last timestamp
- elapsed days
- total XRS-B rows
- per-date row counts

## What it teaches visually

1. The study window is roughly seven elapsed days.
2. It touches eight calendar dates because it begins/ends partway through the first/last date.
3. At roughly one observation per minute, ~7 days naturally means around ten thousand time-series rows.
4. The 10,078 rows are **observations**, not flares.
5. The next conceptual change is from minute-level measurements to event-level units.

## Exact project metadata currently shown

The component derives these directly from the CSV, so you do not need to hardcode them manually.

## Linux test

```bash
rm -rf /tmp/dataset-window
mkdir -p /tmp/dataset-window
unzip ~/Downloads/solar-component-03-dataset-window.zip -d /tmp/dataset-window
cd /tmp/dataset-window
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

## Planned next component

Graphic 04:

```text
10,078 observations
↓
115 statistical detections
↓
32 independent NOAA-linked labelled events
↓
remove U
↓
31 ML-eligible events
```

That next component should animate the **change in statistical unit**, rather than display four equal-looking boxes.
