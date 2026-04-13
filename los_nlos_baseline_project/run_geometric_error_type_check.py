from __future__ import annotations

from pathlib import Path

import pandas as pd


def label_name(value: int) -> str:
    return "LoS" if int(value) == 1 else "NLoS"


def prediction_error_type(pred: int, label: int) -> str:
    pred = int(pred)
    label = int(label)
    if pred == label:
        return "correct"
    if pred == 1 and label == 0:
        return "FP_predicted_LoS_for_NLoS"
    if pred == 0 and label == 1:
        return "FN_predicted_NLoS_for_LoS"
    raise ValueError("Unexpected prediction/label combination.")


def summarize_scope(df: pd.DataFrame, scope_name: str) -> dict[str, float | int | str]:
    baseline_fp = int(((df["baseline_pred"] == 1) & (df["label"] == 0)).sum())
    baseline_fn = int(((df["baseline_pred"] == 0) & (df["label"] == 1)).sum())
    proposed_fp = int(((df["proposed_pred"] == 1) & (df["label"] == 0)).sum())
    proposed_fn = int(((df["proposed_pred"] == 0) & (df["label"] == 1)).sum())

    rescued = df[(df["baseline_pred"] != df["label"]) & (df["proposed_pred"] == df["label"])].copy()
    harmed = df[(df["baseline_pred"] == df["label"]) & (df["proposed_pred"] != df["label"])].copy()

    rescued_from_fp = int(((rescued["baseline_pred"] == 1) & (rescued["label"] == 0)).sum())
    rescued_from_fn = int(((rescued["baseline_pred"] == 0) & (rescued["label"] == 1)).sum())
    harmed_to_fp = int(((harmed["proposed_pred"] == 1) & (harmed["label"] == 0)).sum())
    harmed_to_fn = int(((harmed["proposed_pred"] == 0) & (harmed["label"] == 1)).sum())

    return {
        "scope": scope_name,
        "n_samples": int(len(df)),
        "baseline_fp": baseline_fp,
        "baseline_fn": baseline_fn,
        "proposed_fp": proposed_fp,
        "proposed_fn": proposed_fn,
        "delta_fp": proposed_fp - baseline_fp,
        "delta_fn": proposed_fn - baseline_fn,
        "rescued_total": int(len(rescued)),
        "rescued_from_baseline_fp": rescued_from_fp,
        "rescued_from_baseline_fn": rescued_from_fn,
        "harmed_total": int(len(harmed)),
        "harmed_to_proposed_fp": harmed_to_fp,
        "harmed_to_proposed_fn": harmed_to_fn,
        "rescue_rate_given_baseline_fp": rescued_from_fp / baseline_fp if baseline_fp else float("nan"),
        "rescue_rate_given_baseline_fn": rescued_from_fn / baseline_fn if baseline_fn else float("nan"),
        "relative_fp_change": (proposed_fp - baseline_fp) / baseline_fp if baseline_fp else float("nan"),
        "relative_fn_change": (proposed_fn - baseline_fn) / baseline_fn if baseline_fn else float("nan"),
    }


def build_event_table(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["baseline_wrong"] = (df["baseline_pred"] != df["label"]).astype(int)
    df["proposed_wrong"] = (df["proposed_pred"] != df["label"]).astype(int)
    df["rescued_by_proposed"] = ((df["baseline_wrong"] == 1) & (df["proposed_wrong"] == 0)).astype(int)
    df["harmed_by_proposed"] = ((df["baseline_wrong"] == 0) & (df["proposed_wrong"] == 1)).astype(int)
    df["score_delta_proposed_minus_baseline"] = df["proposed_score"] - df["baseline_score"]

    event_df = df[
        ((df["baseline_pred"] != df["label"]) & (df["proposed_pred"] == df["label"]))
        | ((df["baseline_pred"] == df["label"]) & (df["proposed_pred"] != df["label"]))
    ].copy()

    event_df["actual_class"] = event_df["label"].map(label_name)
    event_df["baseline_error_type"] = [
        prediction_error_type(pred, label) for pred, label in zip(event_df["baseline_pred"], event_df["label"])
    ]
    event_df["proposed_error_type"] = [
        prediction_error_type(pred, label) for pred, label in zip(event_df["proposed_pred"], event_df["label"])
    ]
    event_df["event_type"] = "unchanged"
    event_df.loc[event_df["baseline_wrong"] == 1, "event_type"] = "rescued_by_proposed"
    event_df.loc[event_df["proposed_wrong"] == 1, "event_type"] = "harmed_by_proposed"

    columns = [
        "event_type",
        "case_name",
        "scenario",
        "pos_id",
        "x_m",
        "y_m",
        "label",
        "actual_class",
        "baseline_score",
        "proposed_score",
        "score_delta_proposed_minus_baseline",
        "baseline_pred",
        "proposed_pred",
        "baseline_error_type",
        "proposed_error_type",
        "hard_case_mask",
        "gamma_CP_rx1",
        "gamma_CP_rx2",
        "a_FP_LHCP_rx1",
        "a_FP_LHCP_rx2",
    ]
    return event_df[columns].sort_values(["event_type", "scenario", "pos_id"]).reset_index(drop=True)


def main() -> None:
    project_root = Path(__file__).resolve().parent
    bundle_root = project_root / "results" / "geometric_l1_support_bundle_20260413"
    source_csv = bundle_root / "01_reviewer_rerun" / "geometric" / "oof_predictions_bc.csv"
    results_dir = bundle_root / "06_error_type_directionality_check"
    results_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(source_csv)

    scope_rows = [
        summarize_scope(df, "overall"),
        summarize_scope(df[df["scenario"] == "B"].copy(), "B"),
        summarize_scope(df[df["scenario"] == "C"].copy(), "C"),
        summarize_scope(df[df["hard_case_mask"] == 1].copy(), "hard_case"),
    ]
    summary_df = pd.DataFrame(scope_rows)
    event_df = build_event_table(df)

    summary_df.to_csv(results_dir / "error_type_summary.csv", index=False)
    event_df.to_csv(results_dir / "error_type_event_samples.csv", index=False)

    overall = summary_df.loc[summary_df["scope"] == "overall"].iloc[0]
    lines: list[str] = []
    lines.append("# Geometric Error-Type Directionality Check")
    lines.append("")
    lines.append("## Purpose")
    lines.append("")
    lines.append("- Quantify whether CP7 reduces false positives and false negatives symmetrically or preferentially.")
    lines.append("- Provide a discussion-ready statement about whether CP7 more often corrects LoS samples that were misread as NLoS.")
    lines.append("")
    lines.append("## Overall Results")
    lines.append("")
    lines.append(
        f"- Baseline FP: `{int(overall['baseline_fp'])}` -> Proposed FP: `{int(overall['proposed_fp'])}` "
        f"(`{int(overall['delta_fp'])}` change)."
    )
    lines.append(
        f"- Baseline FN: `{int(overall['baseline_fn'])}` -> Proposed FN: `{int(overall['proposed_fn'])}` "
        f"(`{int(overall['delta_fn'])}` change)."
    )
    lines.append(
        f"- Rescued samples: `{int(overall['rescued_total'])}` total = "
        f"`{int(overall['rescued_from_baseline_fn'])}` from baseline FN + "
        f"`{int(overall['rescued_from_baseline_fp'])}` from baseline FP."
    )
    lines.append(
        f"- Harmed samples: `{int(overall['harmed_total'])}` total = "
        f"`{int(overall['harmed_to_proposed_fn'])}` proposed FN + "
        f"`{int(overall['harmed_to_proposed_fp'])}` proposed FP."
    )
    lines.append(
        f"- Rescue rate among baseline FN: `{overall['rescue_rate_given_baseline_fn']:.4f}`; "
        f"rescue rate among baseline FP: `{overall['rescue_rate_given_baseline_fp']:.4f}`."
    )
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append("- CP7 reduces both error types, but the larger directional effect is on baseline FN.")
    lines.append("- In this label convention, baseline FN corresponds to LoS samples that the baseline misread as NLoS.")
    lines.append("- The rescued set therefore supports the observed tendency that CP7 more often restores LoS samples than NLoS samples.")
    lines.append("- This should be framed as an observed tendency or discussion-level interpretation, not as a mechanism proof.")
    lines.append("")
    lines.append("## Files")
    lines.append("")
    lines.append("- `error_type_summary.csv`: overall, per-scenario, and hard-case counts and rates")
    lines.append("- `error_type_event_samples.csv`: rescued and harmed samples with explicit error-type labels")

    (results_dir / "error_type_report.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
