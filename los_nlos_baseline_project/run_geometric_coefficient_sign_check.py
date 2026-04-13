from __future__ import annotations

from pathlib import Path

import pandas as pd


def sign_label(value: float) -> str:
    if value > 0:
        return "positive"
    if value < 0:
        return "negative"
    return "zero"


def main() -> None:
    project_root = Path(__file__).resolve().parent
    bundle_root = project_root / "results" / "geometric_l1_support_bundle_20260413"
    source_csv = bundle_root / "01_reviewer_rerun" / "geometric" / "logistic_coefficients.csv"
    results_dir = bundle_root / "07_coefficient_sign_stability_check"
    results_dir.mkdir(parents=True, exist_ok=True)

    coeff_df = pd.read_csv(source_csv)
    coeff_df = coeff_df[(coeff_df["model_name"] == "proposed") & (coeff_df["term_name"] != "intercept")].copy()

    pivot = (
        coeff_df.pivot(index="term_name", columns="scope", values="coefficient")
        .reset_index()
        .rename_axis(None, axis=1)
        .rename(
            columns={
                "B": "coef_B",
                "C": "coef_C",
                "B+C": "coef_BC",
            }
        )
    )

    pivot["sign_B"] = pivot["coef_B"].map(sign_label)
    pivot["sign_C"] = pivot["coef_C"].map(sign_label)
    pivot["sign_BC"] = pivot["coef_BC"].map(sign_label)
    pivot["sign_consistent_B_vs_C"] = pivot["sign_B"] == pivot["sign_C"]
    pivot["sign_consistent_all"] = (pivot["sign_B"] == pivot["sign_C"]) & (pivot["sign_C"] == pivot["sign_BC"])
    pivot["flip_B_vs_C"] = pivot["sign_B"] != pivot["sign_C"]
    pivot["near_zero_BC_abs_lt_0p1"] = pivot["coef_BC"].abs() < 0.1
    pivot["is_cp7_feature"] = pivot["term_name"].isin(
        [
            "gamma_CP_rx1",
            "gamma_CP_rx2",
            "a_FP_RHCP_rx1",
            "a_FP_LHCP_rx1",
            "a_FP_RHCP_rx2",
            "a_FP_LHCP_rx2",
        ]
    )

    pivot = pivot[
        [
            "term_name",
            "is_cp7_feature",
            "coef_B",
            "coef_C",
            "coef_BC",
            "sign_B",
            "sign_C",
            "sign_BC",
            "sign_consistent_B_vs_C",
            "sign_consistent_all",
            "flip_B_vs_C",
            "near_zero_BC_abs_lt_0p1",
        ]
    ].sort_values(["is_cp7_feature", "term_name"], ascending=[False, True]).reset_index(drop=True)

    cp7_focus = pivot[pivot["is_cp7_feature"]].copy().reset_index(drop=True)

    pivot.to_csv(results_dir / "coefficient_sign_stability_all_features.csv", index=False)
    cp7_focus.to_csv(results_dir / "coefficient_sign_stability_cp7_focus.csv", index=False)

    stable_cp7 = cp7_focus[cp7_focus["sign_consistent_all"]]["term_name"].tolist()
    unstable_cp7 = cp7_focus[~cp7_focus["sign_consistent_all"]].copy()

    lines: list[str] = []
    lines.append("# Geometric Coefficient Sign Stability Check")
    lines.append("")
    lines.append("## Purpose")
    lines.append("")
    lines.append("- Check whether the full-fit proposed logistic coefficients keep the same sign across scenario B, scenario C, and pooled B+C.")
    lines.append("- Provide a compact supplement table that makes feature-level reliability explicit.")
    lines.append("")
    lines.append("## CP7 Summary")
    lines.append("")
    if stable_cp7:
        lines.append(f"- CP7 features with fully consistent sign across `B`, `C`, and `B+C`: `{', '.join(stable_cp7)}`.")
    if not unstable_cp7.empty:
        for _, row in unstable_cp7.iterrows():
            lines.append(
                f"- `{row['term_name']}` is sign-unstable: "
                f"`B={row['coef_B']:.4f} ({row['sign_B']})`, "
                f"`C={row['coef_C']:.4f} ({row['sign_C']})`, "
                f"`B+C={row['coef_BC']:.4f} ({row['sign_BC']})`."
            )
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append("- The main CP7 pattern is sign-stable for `gamma_CP_rx1`, `gamma_CP_rx2`, `a_FP_RHCP_rx1`, `a_FP_LHCP_rx1`, and `a_FP_LHCP_rx2`.")
    lines.append("- `a_FP_RHCP_rx2` is the only CP7 feature that flips sign between `B` and `C`, and its pooled B+C coefficient is near zero.")
    lines.append("- This supports keeping RHCP-specific interpretation out of the main claim and treating it as a weaker, less stable auxiliary signal.")

    (results_dir / "coefficient_sign_report.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
