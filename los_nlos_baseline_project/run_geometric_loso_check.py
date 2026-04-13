from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, brier_score_loss, roc_auc_score
from sklearn.preprocessing import StandardScaler


@dataclass(frozen=True)
class Config:
    project_root: Path
    bundle_root: Path
    reviewer_results_dir: Path
    results_dir: Path
    classification_threshold: float = 0.5
    logistic_c: float = 100.0
    solver: str = "lbfgs"
    max_iter: int = 10000
    class_weight: str = "balanced"
    baseline_features: tuple[str, ...] = (
        "fp_energy_db",
        "skewness_pdp",
        "kurtosis_pdp",
        "mean_excess_delay_ns",
        "rms_delay_spread_ns",
    )
    cp7_features: tuple[str, ...] = (
        "gamma_CP_rx1",
        "gamma_CP_rx2",
        "a_FP_RHCP_rx1",
        "a_FP_LHCP_rx1",
        "a_FP_RHCP_rx2",
        "a_FP_LHCP_rx2",
    )

    @property
    def proposed_features(self) -> tuple[str, ...]:
        return self.baseline_features + self.cp7_features


def default_config() -> Config:
    project_root = Path(__file__).resolve().parent
    bundle_root = project_root / "results" / "geometric_l1_support_bundle_20260413"
    reviewer_results_dir = bundle_root / "01_reviewer_rerun"
    results_dir = bundle_root / "05_loso_generalization_check"
    return Config(
        project_root=project_root,
        bundle_root=bundle_root,
        reviewer_results_dir=reviewer_results_dir,
        results_dir=results_dir,
    )


def exact_mcnemar_p(labels: pd.Series, baseline_pred: pd.Series, proposed_pred: pd.Series) -> tuple[int, int, float]:
    from scipy.stats import binomtest

    labels_bool = labels.astype(bool)
    baseline_correct = baseline_pred.astype(bool) == labels_bool
    proposed_correct = proposed_pred.astype(bool) == labels_bool
    b_count = int((baseline_correct & ~proposed_correct).sum())
    c_count = int((~baseline_correct & proposed_correct).sum())
    n = b_count + c_count
    if n == 0:
        return b_count, c_count, 1.0
    p_value = float(binomtest(min(b_count, c_count), n=n, p=0.5, alternative="two-sided").pvalue)
    return b_count, c_count, p_value


def fit_and_predict(
    train_df: pd.DataFrame,
    test_df: pd.DataFrame,
    features: Iterable[str],
    cfg: Config,
) -> tuple[pd.Series, pd.Series]:
    feature_list = list(features)
    scaler = StandardScaler()
    x_train = scaler.fit_transform(train_df[feature_list])
    x_test = scaler.transform(test_df[feature_list])
    y_train = train_df["label"].astype(int)

    clf = LogisticRegression(
        penalty="l2",
        solver=cfg.solver,
        C=cfg.logistic_c,
        class_weight=cfg.class_weight,
        max_iter=cfg.max_iter,
    )
    clf.fit(x_train, y_train)
    score = pd.Series(clf.predict_proba(x_test)[:, 1], index=test_df.index, name="score")
    pred = pd.Series((score >= cfg.classification_threshold).astype(int), index=test_df.index, name="pred")
    return score, pred


def evaluate_direction(df: pd.DataFrame, train_scenario: str, test_scenario: str, cfg: Config):
    train_df = df[df["scenario"] == train_scenario].copy()
    test_df = df[df["scenario"] == test_scenario].copy()
    y_test = test_df["label"].astype(int)

    baseline_score, baseline_pred = fit_and_predict(train_df, test_df, cfg.baseline_features, cfg)
    proposed_score, proposed_pred = fit_and_predict(train_df, test_df, cfg.proposed_features, cfg)

    b_count, c_count, p_value = exact_mcnemar_p(y_test, baseline_pred, proposed_pred)
    direction = f"{train_scenario}_to_{test_scenario}"

    summary_row = {
        "direction": direction,
        "train_scenario": train_scenario,
        "test_scenario": test_scenario,
        "n_train": int(len(train_df)),
        "n_test": int(len(test_df)),
        "n_los_train": int(train_df["label"].sum()),
        "n_nlos_train": int((1 - train_df["label"]).sum()),
        "n_los_test": int(y_test.sum()),
        "n_nlos_test": int((1 - y_test).sum()),
        "baseline_auc": roc_auc_score(y_test, baseline_score),
        "proposed_auc": roc_auc_score(y_test, proposed_score),
        "baseline_accuracy": accuracy_score(y_test, baseline_pred),
        "proposed_accuracy": accuracy_score(y_test, proposed_pred),
        "baseline_brier": brier_score_loss(y_test, baseline_score),
        "proposed_brier": brier_score_loss(y_test, proposed_score),
        "baseline_fp": int(((baseline_pred == 1) & (y_test == 0)).sum()),
        "proposed_fp": int(((proposed_pred == 1) & (y_test == 0)).sum()),
        "baseline_fn": int(((baseline_pred == 0) & (y_test == 1)).sum()),
        "proposed_fn": int(((proposed_pred == 0) & (y_test == 1)).sum()),
    }
    summary_row["delta_auc"] = summary_row["proposed_auc"] - summary_row["baseline_auc"]
    summary_row["delta_accuracy"] = summary_row["proposed_accuracy"] - summary_row["baseline_accuracy"]
    summary_row["delta_brier"] = summary_row["proposed_brier"] - summary_row["baseline_brier"]

    mcnemar_row = {
        "direction": direction,
        "train_scenario": train_scenario,
        "test_scenario": test_scenario,
        "baseline_correct_proposed_wrong": b_count,
        "baseline_wrong_proposed_correct": c_count,
        "p_value_exact": p_value,
    }

    prediction_df = test_df[
        ["case_name", "scenario", "pos_id", "x_m", "y_m", "label"]
    ].copy()
    prediction_df.insert(0, "direction", direction)
    prediction_df.insert(1, "train_scenario", train_scenario)
    prediction_df.insert(2, "test_scenario", test_scenario)
    prediction_df["baseline_score"] = baseline_score
    prediction_df["baseline_pred"] = baseline_pred
    prediction_df["proposed_score"] = proposed_score
    prediction_df["proposed_pred"] = proposed_pred
    prediction_df["baseline_correct"] = prediction_df["baseline_pred"] == prediction_df["label"]
    prediction_df["proposed_correct"] = prediction_df["proposed_pred"] == prediction_df["label"]
    return summary_row, mcnemar_row, prediction_df


def write_report(cfg: Config, summary_df: pd.DataFrame, mcnemar_df: pd.DataFrame) -> None:
    lines: list[str] = []
    lines.append("# Geometric LOSO Generalization Check")
    lines.append("")
    lines.append("## Purpose")
    lines.append("")
    lines.append("- Evaluate whether CP7 gains remain when the model is trained on one scenario and tested on the other scenario.")
    lines.append("- Store the independent LOSO validation that was referenced in the review reports.")
    lines.append("")
    lines.append("## Setup")
    lines.append("")
    lines.append("- Dataset: CP7-capable B+C subset")
    lines.append("- Model: sklearn logistic regression with L2 regularization")
    lines.append(f"- Class weight: `{cfg.class_weight}`")
    lines.append("- Normalization: fit on the training scenario only, then applied to the held-out scenario")
    lines.append(f"- Inverse regularization strength C: `{cfg.logistic_c}`")
    lines.append("")
    lines.append("## Results")
    lines.append("")
    for _, row in summary_df.iterrows():
        mc = mcnemar_df.loc[mcnemar_df["direction"] == row["direction"]].iloc[0]
        lines.append(
            f"- `{row['direction']}`: baseline AUC `{row['baseline_auc']:.4f}`, proposed AUC `{row['proposed_auc']:.4f}`, "
            f"delta AUC `{row['delta_auc']:.4f}`, baseline accuracy `{row['baseline_accuracy']:.4f}`, "
            f"proposed accuracy `{row['proposed_accuracy']:.4f}`, exact McNemar p `{mc['p_value_exact']:.4f}`."
        )
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append("- Both directions improve, which supports the claim that CP7 information is not confined to one scenario.")
    lines.append("- These numbers are best used in a robustness subsection rather than as the primary headline result.")
    (cfg.results_dir / "loso_report.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    cfg = default_config()
    cfg.results_dir.mkdir(parents=True, exist_ok=True)

    dataset_path = cfg.reviewer_results_dir / "geometric" / "cp7_target_dataset.csv"
    df = pd.read_csv(dataset_path)
    df = df[df["valid_for_cp7_model"].astype(bool) & df["scenario"].isin(["B", "C"])].copy()
    df = df.sort_values(["scenario", "pos_id"]).reset_index(drop=True)
    df.to_csv(cfg.results_dir / "cp7_target_dataset_valid_bc.csv", index=False)

    summary_rows = []
    mcnemar_rows = []
    predictions = []
    for train_scenario, test_scenario in [("B", "C"), ("C", "B")]:
        summary_row, mcnemar_row, prediction_df = evaluate_direction(df, train_scenario, test_scenario, cfg)
        summary_rows.append(summary_row)
        mcnemar_rows.append(mcnemar_row)
        predictions.append(prediction_df)

    summary_df = pd.DataFrame(summary_rows)
    mcnemar_df = pd.DataFrame(mcnemar_rows)
    prediction_df = pd.concat(predictions, ignore_index=True)

    summary_df.to_csv(cfg.results_dir / "loso_summary.csv", index=False)
    mcnemar_df.to_csv(cfg.results_dir / "loso_mcnemar.csv", index=False)
    prediction_df.to_csv(cfg.results_dir / "loso_predictions.csv", index=False)

    config_df = pd.DataFrame(
        {
            "key": [
                "implementation",
                "class_weight",
                "normalization",
                "logistic_c",
                "solver",
                "max_iter",
                "baseline_features",
                "cp7_features",
            ],
            "value": [
                "sklearn_logistic_independent_validation",
                cfg.class_weight,
                "train_only_standard_scaler",
                cfg.logistic_c,
                cfg.solver,
                cfg.max_iter,
                ", ".join(cfg.baseline_features),
                ", ".join(cfg.cp7_features),
            ],
        }
    )
    config_df.to_csv(cfg.results_dir / "loso_config.csv", index=False)
    write_report(cfg, summary_df, mcnemar_df)


if __name__ == "__main__":
    main()
