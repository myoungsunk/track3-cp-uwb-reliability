from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.metrics import brier_score_loss


def compute_uniform_bin_calibration(
    labels: np.ndarray,
    scores: np.ndarray,
    n_bins: int = 5,
) -> tuple[pd.DataFrame, float]:
    edges = np.linspace(0.0, 1.0, n_bins + 1)
    bin_ids = np.digitize(scores, edges[1:-1], right=True)
    rows: list[dict[str, float | int]] = []
    ece = 0.0

    for idx in range(n_bins):
        mask = bin_ids == idx
        n_samples = int(mask.sum())
        if n_samples == 0:
            rows.append(
                {
                    "bin_id": idx + 1,
                    "bin_lower": float(edges[idx]),
                    "bin_upper": float(edges[idx + 1]),
                    "n_samples": 0,
                    "sample_fraction": 0.0,
                    "mean_pred": np.nan,
                    "observed_freq": np.nan,
                    "gap_observed_minus_pred": np.nan,
                    "abs_gap": np.nan,
                }
            )
            continue

        mean_pred = float(scores[mask].mean())
        observed_freq = float(labels[mask].mean())
        gap = observed_freq - mean_pred
        sample_fraction = n_samples / len(labels)
        ece += sample_fraction * abs(gap)
        rows.append(
            {
                "bin_id": idx + 1,
                "bin_lower": float(edges[idx]),
                "bin_upper": float(edges[idx + 1]),
                "n_samples": n_samples,
                "sample_fraction": sample_fraction,
                "mean_pred": mean_pred,
                "observed_freq": observed_freq,
                "gap_observed_minus_pred": gap,
                "abs_gap": abs(gap),
            }
        )

    return pd.DataFrame(rows), float(ece)


def add_curve(ax: plt.Axes, bin_df: pd.DataFrame, label: str, color: str) -> None:
    valid = bin_df["n_samples"] > 0
    ax.plot(
        bin_df.loc[valid, "mean_pred"],
        bin_df.loc[valid, "observed_freq"],
        marker="o",
        linewidth=2,
        color=color,
        label=label,
    )


def main() -> None:
    project_root = Path(__file__).resolve().parent
    bundle_root = project_root / "results" / "geometric_l1_support_bundle_20260413"
    source_csv = bundle_root / "01_reviewer_rerun" / "geometric" / "oof_predictions_bc.csv"
    results_dir = bundle_root / "08_calibration_check"
    results_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(source_csv)
    labels = df["label"].astype(int).to_numpy()

    baseline_scores = df["baseline_score"].to_numpy(float)
    proposed_scores = df["proposed_score"].to_numpy(float)

    baseline_bins, baseline_ece = compute_uniform_bin_calibration(labels, baseline_scores, n_bins=5)
    proposed_bins, proposed_ece = compute_uniform_bin_calibration(labels, proposed_scores, n_bins=5)

    baseline_bins.insert(0, "model_name", "baseline")
    proposed_bins.insert(0, "model_name", "proposed")
    curve_df = pd.concat([baseline_bins, proposed_bins], ignore_index=True)
    curve_df.to_csv(results_dir / "calibration_curve_points.csv", index=False)

    summary_df = pd.DataFrame(
        [
            {
                "model_name": "baseline",
                "n_samples": len(df),
                "n_bins": 5,
                "binning": "uniform",
                "ece": baseline_ece,
                "brier_score": brier_score_loss(labels, baseline_scores),
            },
            {
                "model_name": "proposed",
                "n_samples": len(df),
                "n_bins": 5,
                "binning": "uniform",
                "ece": proposed_ece,
                "brier_score": brier_score_loss(labels, proposed_scores),
            },
        ]
    )
    summary_df.to_csv(results_dir / "calibration_summary.csv", index=False)

    fig, (ax_top, ax_bottom) = plt.subplots(
        2,
        1,
        figsize=(7.2, 8.4),
        gridspec_kw={"height_ratios": [3.0, 1.3]},
        constrained_layout=True,
    )

    ax_top.plot([0, 1], [0, 1], linestyle="--", color="#666666", linewidth=1.5, label="perfect calibration")
    add_curve(ax_top, baseline_bins, "Baseline (5-feature)", "#1f77b4")
    add_curve(ax_top, proposed_bins, "Proposed (+CP7)", "#d62728")
    ax_top.set_xlim(0, 1)
    ax_top.set_ylim(0, 1)
    ax_top.set_xlabel("Mean predicted probability of LoS")
    ax_top.set_ylabel("Observed LoS frequency")
    ax_top.set_title("Reliability Diagram on B+C OOF Predictions (5-bin uniform)")
    ax_top.grid(alpha=0.25)
    ax_top.legend(frameon=False, loc="upper left")

    hist_edges = np.linspace(0.0, 1.0, 21)
    ax_bottom.hist(
        baseline_scores,
        bins=hist_edges,
        alpha=0.45,
        label="Baseline",
        color="#1f77b4",
    )
    ax_bottom.hist(
        proposed_scores,
        bins=hist_edges,
        alpha=0.45,
        label="Proposed",
        color="#d62728",
    )
    ax_bottom.set_xlim(0, 1)
    ax_bottom.set_xlabel("Predicted probability of LoS")
    ax_bottom.set_ylabel("Count")
    ax_bottom.set_title("Score Distribution")
    ax_bottom.grid(alpha=0.25)
    ax_bottom.legend(frameon=False)

    png_path = results_dir / "calibration_plot.png"
    pdf_path = results_dir / "calibration_plot.pdf"
    fig.savefig(png_path, dpi=220)
    fig.savefig(pdf_path)
    plt.close(fig)

    baseline_mid = baseline_bins.loc[baseline_bins["bin_id"] == 3].iloc[0]
    proposed_mid = proposed_bins.loc[proposed_bins["bin_id"] == 3].iloc[0]
    lines: list[str] = []
    lines.append("# Geometric Calibration Check")
    lines.append("")
    lines.append("## Purpose")
    lines.append("")
    lines.append("- Visualize the reliability of the B+C OOF probabilities for the paired baseline and proposed models.")
    lines.append("- Quantify calibration with the same 5-bin uniform ECE setting that was referenced in the review report.")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append(
        f"- Baseline: ECE `{baseline_ece:.4f}`, Brier `{brier_score_loss(labels, baseline_scores):.4f}`."
    )
    lines.append(
        f"- Proposed: ECE `{proposed_ece:.4f}`, Brier `{brier_score_loss(labels, proposed_scores):.4f}`."
    )
    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- The proposed model shows a slightly lower 5-bin ECE and a markedly lower Brier score.")
    lines.append(
        f"- The mid-confidence bin `[0.4, 0.6]` remains imperfect: baseline gap `{baseline_mid['gap_observed_minus_pred']:.4f}`, "
        f"proposed gap `{proposed_mid['gap_observed_minus_pred']:.4f}`."
    )
    lines.append("- This supports using calibration as a secondary robustness note rather than as the main claim.")
    lines.append("")
    lines.append("## Files")
    lines.append("")
    lines.append("- `calibration_plot.png`: reliability diagram and score histogram")
    lines.append("- `calibration_plot.pdf`: vector-friendly export")
    lines.append("- `calibration_summary.csv`: ECE and Brier summary")
    lines.append("- `calibration_curve_points.csv`: bin-level mean prediction, observed frequency, and gap")

    (results_dir / "calibration_report.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
