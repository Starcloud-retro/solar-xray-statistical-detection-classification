# src/run_detector_evaluation.py
"""
Execute the statistical anomaly/event detector over a grid of hyper‑parameters and evaluate against the NOAA flare report.
Generates a CSV of metrics and a precision‑recall surface figure.
"""

import itertools
import logging
from pathlib import Path
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

from .config import DATA_DIR, CHANNEL_LONG
from .ingestion import ingest_flare_report, ingest_goes_xrs, align_xrs_and_flares
from .detector import (
    detect_events,
    evaluate_point_level,
    evaluate_event_level,
    extract_events,
    merge_overlapping_events,
    _build_ground_truth_series,
    compute_event_metrics,
    compare_events,
)

logger = logging.getLogger("RunDetectorEval")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s", encoding="utf-8")

def main():
    # Load data
    logger.info("Loading cleaned XRS data and flare report")
    df_xrs = pd.read_csv(DATA_DIR / "processed" / "goes_xrs_cleaned.csv", parse_dates=["time_tag"])
    df_flares = ingest_flare_report()
    df_aligned = align_xrs_and_flares(df_xrs, df_flares)
    df_long = df_aligned[df_aligned["energy"] == CHANNEL_LONG].copy()
    df_long = df_long.sort_values("time_tag").reset_index(drop=True)

    # Ground‑truth series for point‑wise evaluation
    gt_series = _build_ground_truth_series(df_long, df_flares)

    # Hyper‑parameter grids
    z_mean_grid = [2.5, 3.0, 3.5, 4.0]
    z_mad_grid = [2.5, 3.0, 3.5, 4.0]
    roc_grid = [0.03, 0.05, 0.07]  # dex per minute
    min_len_grid = [2, 3, 5]        # persistence minutes

    results = []
    total = len(z_mean_grid) * len(z_mad_grid) * len(roc_grid) * len(min_len_grid)
    logger.info(f"Evaluating {total} hyper-parameter combinations")

    # Split dataset chronologically into dev (first 70%) and test (remaining 30%)
    # to avoid data leakage when exploring detector hyperparameters
    split_idx = int(len(df_long) * 0.70)
    split_time = df_long.loc[split_idx, "time_tag"]
    logger.info(f"Chronological split at {split_time} UTC (Dev: {split_idx} rows, Test: {len(df_long)-split_idx} rows)")

    df_dev = df_long.iloc[:split_idx].copy().reset_index(drop=True)
    df_flares_dev = df_flares[df_flares["end_time"] <= split_time].copy().reset_index(drop=True)
    gt_series_dev = _build_ground_truth_series(df_dev, df_flares_dev)

    for z_mean_thr, z_mad_thr, roc_thr, min_len in itertools.product(
        z_mean_grid, z_mad_grid, roc_grid, min_len_grid
    ):
        # Detection on development partition
        df_det_dev = detect_events(
            df_dev,
            z_mean_thr=z_mean_thr,
            z_mad_thr=z_mad_thr,
            roc_thr=roc_thr,
            min_len=min_len,
            window_min=10,
            uncontaminated=True,
        )
        # Point‑level metrics
        point_metrics = evaluate_point_level(df_det_dev, "detected", gt_series_dev)
        # Event extraction & merging
        pred_events_dev = extract_events(df_det_dev, flag_col="detected")
        pred_events_dev = merge_overlapping_events(pred_events_dev)
        # Event‑level metrics on dev
        event_metrics = evaluate_event_level(pred_events_dev, df_flares_dev)
        # Record results
        results.append({
            "z_mean_thr": z_mean_thr,
            "z_mad_thr": z_mad_thr,
            "roc_thr": roc_thr,
            "min_len": min_len,
            "point_precision": point_metrics["precision"],
            "point_recall": point_metrics["recall"],
            "point_f1": point_metrics["f1"],
            "event_precision": event_metrics["precision"],
            "event_recall": event_metrics["recall"],
            "event_f1": event_metrics["f1"],
            "tp_events": event_metrics["tp"],
            "fp_events": event_metrics["fp"],
            "fn_events": event_metrics["fn"],
        })

    # Save CSV
    results_df = pd.DataFrame(results)
    out_dir = DATA_DIR / "processed"
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "detector_evaluation_grid.csv"
    results_df.to_csv(csv_path, index=False)
    logger.info(f"Saved evaluation grid to {csv_path}")

    # Explicit Model Selection Rule:
    # Select parameter configuration theta* maximizing event_f1, using event_precision as tie-breaker.
    best_config_row = results_df.sort_values(
        by=["event_f1", "event_precision", "event_recall"],
        ascending=[False, False, False]
    ).iloc[0]

    best_z_mean = float(best_config_row["z_mean_thr"])
    best_z_mad = float(best_config_row["z_mad_thr"])
    best_roc = float(best_config_row["roc_thr"])
    best_min_len = int(best_config_row["min_len"])

    logger.info(
        f"Selected optimal detector configuration theta*: "
        f"z_mean={best_z_mean}, z_mad={best_z_mad}, roc={best_roc}, min_len={best_min_len} "
        f"(Dev Event F1={best_config_row['event_f1']:.4f}, Precision={best_config_row['event_precision']:.4f}, Recall={best_config_row['event_recall']:.4f})"
    )

    # Run detection on full series using the selected optimal configuration theta*
    df_det_optimal = detect_events(
        df_long,
        z_mean_thr=best_z_mean,
        z_mad_thr=best_z_mad,
        roc_thr=best_roc,
        min_len=best_min_len,
        window_min=10,
        uncontaminated=True,
    )
    pred_events_optimal = extract_events(df_det_optimal, flag_col="detected")
    pred_events_optimal = merge_overlapping_events(pred_events_optimal)

    # Enrich detected events with detailed metrics using the annotated df_det_optimal
    # so that max_z_mean, max_z_mad, and max_roc are properly extracted
    enriched_events = compute_event_metrics(df_det_optimal, pred_events_optimal)
    enriched_path = out_dir / "event_segmentation_report.csv"
    pd.DataFrame(enriched_events).to_csv(enriched_path, index=False)
    logger.info(f"Saved event segmentation report for optimal configuration theta* to {enriched_path}")

    # Compare to NOAA flare catalog
    comparison = compare_events(enriched_events, df_flares)
    summary_path = out_dir / "event_segmentation_summary.csv"
    pd.DataFrame([comparison]).to_csv(summary_path, index=False)
    logger.info(f"Saved event segmentation summary to {summary_path}")
    # Plot precision‑recall surface (fixing min_len=3 for illustration)
    subset = results_df[results_df["min_len"] == 3]
    fig, ax = plt.subplots(figsize=(8, 6))
    sns.scatterplot(
        data=subset,
        x="event_recall",
        y="event_precision",
        hue="z_mean_thr",
        style="z_mad_thr",
        size="roc_thr",
        sizes=(40, 200),
        ax=ax,
    )
    ax.set_title("Event‑level Precision vs Recall (min_len=3 min)")
    ax.set_xlabel("Recall")
    ax.set_ylabel("Precision")
    ax.grid(True)
    fig_path = Path("reports/figures/fig6_detector_evaluation.png")
    fig_path.parent.mkdir(parents=True, exist_ok=True)
    plt.tight_layout()
    plt.savefig(fig_path, dpi=300)
    plt.close()
    logger.info(f"Saved evaluation figure to {fig_path}")

if __name__ == "__main__":
    main()
