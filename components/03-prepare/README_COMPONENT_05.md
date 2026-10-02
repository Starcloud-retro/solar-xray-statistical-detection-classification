# Graphic 05 — Real Short-Gap vs Long-Gap Preprocessing

This component uses exact rows from the project's GOES XRS-B cleaned CSV.

## Real short-gap example

Missing raw observation:

```text
2026-09-06 19:34 UTC
```

Gap size:

```text
1 minute
```

The frozen rule allows interpolation for gaps of at most 3 minutes.

Actual cleaned value:

```text
3.872302e-07 W/m²
```

Audit field:

```text
was_imputed = TRUE
```

## Real long-gap example

The first six-minute long gap is:

```text
2026-09-04 16:31 UTC
through
2026-09-04 16:36 UTC
```

Those values remain missing.

The line is deliberately broken in the component so the visual itself communicates that no solar behavior was invented across those six minutes.

## Scientific point

Short and long gaps receive different treatment because they create different levels of uncertainty.

- short gap: restore very local continuity while preserving an imputation flag
- long gap: preserve missingness and prevent fake rates, slopes, peaks, or event durations

## Linux terminal prompts

```bash
rm -rf /tmp/gap-preprocessing
mkdir -p /tmp/gap-preprocessing
unzip ~/Downloads/solar-component-05-gap-preprocessing.zip -d /tmp/gap-preprocessing
cd /tmp/gap-preprocessing
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

## Next component

The next component should begin the statistics chapter as one coherent interaction:

```text
clean signal
→ previous 30 minutes
→ where is the center?
→ mean / median
→ how much does it vary?
→ SD / MAD
→ why 1.4826?
→ rolling local baseline
```
