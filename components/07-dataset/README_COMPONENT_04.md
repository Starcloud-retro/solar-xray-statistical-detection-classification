# Graphic 04 — From 10,078 Rows to 31 ML Events

This component resolves the biggest dataset-size confusion in the project.

## Important scientific nuance

The website should **not** present this as a simplistic direct funnel:

```text
10,078 → 115 → 32 → 31
```

because two different “32” concepts occur in the frozen workflow.

### Detector / NOAA alignment results
- 10,078 XRS-B minute-level observations
- 115 statistical detections
- 32 matched detections
- 80 unmatched detections
- 3 unmatched NOAA events

### Supervised event-table construction
- 35 labeled detector rows
- three physical NOAA flares had duplicate detector segments
- deduplication → 32 independent physical events
- class counts: 13 B, 17 C, 1 M, 1 U
- exclude U and combine C/M into C+
- final ML dataset: 31 events = 13 B + 18 C+

This distinction is explicitly animated in the component.

## Why the graphic is coded rather than generated

The scientific meaning comes from the change of unit:

```text
minute observation
→ detected interval
→ physical event
→ ML row
```

That needs motion and exact labels, not a static poster.

## Linux test

```bash
rm -rf /tmp/data-reduction
mkdir -p /tmp/data-reduction
unzip ~/Downloads/solar-component-04-data-reduction.zip -d /tmp/data-reduction
cd /tmp/data-reduction
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

Component 05 will use the actual preprocessing examples:

- the real one-minute missing observation
- the actual interpolated cleaned value
- the real six-minute long gap
- why long gaps stay missing
- why `segment_id` exists
