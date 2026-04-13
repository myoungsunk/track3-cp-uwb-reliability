# Geometric LoS/NLoS Validation Report (Version 2.0)

This file is the manuscript-facing revision of `geometric_cp7_story_report.md`. The result bundle itself is unchanged, but the argument is reorganized around the claim that CP7 channel-resolved features reduce geometric LoS/NLoS ambiguity, rather than merely increasing average performance.

## 1. Central Takeaway

The strongest supported claim is:

> CP7 channel-resolved features reduce geometric LoS/NLoS ambiguity on the CP7-capable paired subset.

The main evidence is not only the paired AUC gain, but also the concentration of that gain on ambiguous samples, the rescue of baseline mistakes, and the consistency of the result under spatially aware and cross-scenario robustness checks.

## 2. Baseline Definitions Must Be Separated

The manuscript must explicitly separate the full reference baseline from the paired CP7 comparison baseline.

| Evaluation stage | Data universe | Model definition | Main result | How to use it |
|---|---|---|---:|---|
| Full 6-case reference baseline | `CP_caseA/B/C` + `LP_caseA/B/C` | Original 16-feature reference baseline including `r_CP`, `a_FP`, and standard CIR descriptors | AUC `0.7959` | Broad reference only |
| Paired 5-feature subset baseline | `CP_caseB` + `CP_caseC`, CP only, `n=112` | 5-feature CIR baseline: `fp_energy_db`, `skewness_pdp`, `kurtosis_pdp`, `mean_excess_delay_ns`, `rms_delay_spread_ns` | AUC `0.8498` | Direct comparator for CP7 contribution |
| Proposed paired CP7 model | Same `CP_caseB` + `CP_caseC` subset and same folds | 5 CIR features + 6 CP7 features | AUC `0.9139` | Main CP7 result |

Therefore the manuscript should **not** state that performance improved directly from `0.7959` to `0.9139`. The correct formulation is:

- The full 6-case reference baseline achieved AUC `0.7959`.
- The contribution of CP7 was evaluated separately on the CP7-capable paired subset.
- On that paired subset, the 5-feature CIR baseline achieved AUC `0.8498`, and the proposed CP7-augmented model achieved AUC `0.9139`.

## 3. Main Result: CP7 Reduces Ambiguity on the Paired CP7-Capable Subset

The paired CP7-capable subset contains `112` samples with a balanced `56/56` LoS/NLoS split. On this subset, the main evidence chain is:

| Evidence | Baseline | Proposed | Interpretation |
|---|---:|---:|---|
| Overall paired AUC | `0.8498` | `0.9139` | Clear same-fold gain |
| Brier score | `0.1556` | `0.1126` | Probability error decreased |
| Exact McNemar | - | `p = 0.0352` | Paired decision quality improved |
| Ambiguity band AUC `[0.4, 0.6]` | `0.4286` | `0.9286` | Gain concentrates on uncertain samples |
| Total errors on B+C | `26` | `17` | Net error reduction of `9` |

Operationally, the proposed model rescued `12` of the `26` baseline errors and introduced only `3` new errors. This corresponds to:

- Rescue rate given baseline error: `0.4615`
- Harm rate given baseline correct: `0.0349`

Within the ambiguity band `[0.4, 0.6]`, the evidence is even stronger:

- Baseline hard-case errors: `9`
- Proposed hard-case errors: `3`
- Hard-case rescues: `6`
- Hard-case new harms: `0`

This is the clearest evidence that CP7 is not only shifting an average metric, but is actually repairing decisions where the baseline is uncertain.

## 4. Error-Type Directionality

The error-type breakdown supports a discussion-level statement that CP7 more often restores LoS samples that the baseline misread as NLoS.

| Error type | Baseline | Proposed | Change |
|---|---:|---:|---:|
| FP (`NLoS -> LoS`) | `14` | `10` | `-4` |
| FN (`LoS -> NLoS`) | `12` | `7` | `-5` |

Rescued samples by baseline error type:

- Rescued from baseline FN: `8`
- Rescued from baseline FP: `4`

All three harmed samples were proposed FN, and no proposed FP was newly introduced in the harmed set. This supports the wording:

> CP7 reduced both error types, but the stronger directional effect was the correction of LoS samples that the baseline had misclassified as NLoS.

This should remain an **observed tendency**, not a mechanism proof.

## 5. Robustness and Overfitting Checks

The ambiguity-reduction story remains consistent under additional checks.

| Check | Baseline | Proposed | Reading |
|---|---:|---:|---|
| Position-aware spatial CV (`leave_one_position_out`) | `0.8406` | `0.9066` | Improvement remains under position-aware splitting |
| LOSO `B -> C` | `0.7578` | `0.8299` | Cross-scenario gain remains positive |
| LOSO `C -> B` | `0.8327` | `0.8735` | Cross-scenario gain remains positive |
| L1 logistic on B+C | `0.8444` | `0.8763` | Gain remains after sparse regularization |

Additional reviewer-side independent verification also reported a GroupKFold-style position-aware check of `0.8313 -> 0.8970` (`delta AUC +0.0657`). This is not the main rerun table, but it is directionally consistent with the stored spatial CV evidence.

The L1 regularization check is especially useful against the overfitting question. In the L1 rerun:

- `gamma_CP_rx2` and `a_FP_LHCP_rx1` remained non-zero in every fold.
- `gamma_CP_rx1` and `a_FP_LHCP_rx2` remained non-zero in `80%` of folds.

This supports the view that the main CP7 signal is not removed by sparse regularization.

## 6. Feature Interpretation Should Be Conservative

The feature story should be stated as **complementarity** or **low redundancy**, not strict orthogonality.

The most defensible synthesis across correlation, permutation, ablation, L1, and sign stability is:

- `gamma` forms the main complementary axis.
- LHCP first-path amplitude provides additional support.
- RHCP contribution is weaker and less stable.

Why this wording is safer:

- Correlation analysis shows that `gamma_CP_rx2` has the lowest redundancy against strong baseline descriptors.
- Logistic permutation ranks `a_FP_LHCP_rx1` first and `gamma_CP_rx2` second.
- Repeated ablation shows the largest drop when both `gamma` channels are removed, with the LHCP pair as the next most important group.
- The RHCP pair has a much smaller ablation effect, and `a_FP_RHCP_rx2` is sign-unstable.

### CP7 coefficient sign stability

| Feature | B | C | B+C | Stability |
|---|---:|---:|---:|---|
| `gamma_CP_rx1` | `+0.6733` | `+0.8884` | `+0.5259` | stable |
| `gamma_CP_rx2` | `-0.5211` | `-1.0178` | `-0.8122` | stable |
| `a_FP_LHCP_rx1` | `+1.0687` | `+1.1809` | `+0.9993` | stable |
| `a_FP_LHCP_rx2` | `+0.7866` | `+0.3135` | `+0.3286` | stable |
| `a_FP_RHCP_rx1` | `-0.2593` | `-1.1145` | `-0.6425` | stable |
| `a_FP_RHCP_rx2` | `-0.8287` | `+1.0282` | `+0.0893` | unstable |

This is why RHCP-specific discussion should stay out of the main claim.

## 7. Claim Boundaries

The following claims are supported:

- CP7 improves paired geometric LoS/NLoS discrimination on the CP7-capable subset.
- The gain is concentrated on ambiguous samples rather than being only an average shift.
- Baseline mistakes are rescued at a materially higher rate than new mistakes are introduced.
- The core direction remains consistent under spatial CV, LOSO, and L1 checks.

The following claims should **not** be main-text claims:

- A direct `0.7959 -> 0.9139` improvement claim
- Calibration improvement as a headline result
- Strict orthogonality
- Universal dual-RX diversity gain
- Strong subgroup mechanism proof
- Direct identification of a specific reflection mechanism

Physical interpretation is still possible, but it should remain hypothesis-level wording such as:

> CP7 may reflect branch-specific polarization distortion patterns that help resolve otherwise ambiguous geometric decisions.

## 8. Manuscript-Ready Result Text

### Option A: Main result paragraph

Across the full 6-case geometric rerun, the original 16-feature reference baseline achieved an OOF AUC of `0.7959`. Because the six channel-resolved CP7 features are available only for the CP measurements of `CP_caseB` and `CP_caseC`, the contribution of CP7 was evaluated separately on a CP7-capable paired subset rather than by direct comparison to the full 6-case baseline. This subset contained `112` samples with a balanced `56/56` LoS/NLoS split. Under the same cross-validation folds, the 5-feature CIR baseline achieved an AUC of `0.8498`, whereas the proposed model with six additional CP7 features achieved `0.9139`. The proposed model also reduced the Brier score by `0.0430`, and the exact McNemar test yielded `p = 0.0352`, indicating that the gain was linked to improved paired decision quality rather than to a score fluctuation alone.

### Option B: Ambiguity-focused paragraph

The gain was concentrated on samples that the baseline found ambiguous. In the baseline ambiguity band `[0.4, 0.6]`, AUC increased from `0.4286` to `0.9286`. On the full B+C subset, the proposed model corrected `12` of the `26` baseline errors while introducing only `3` new errors; within the ambiguity band it rescued `6` of the `9` baseline errors and introduced no new harm. Error-type analysis further showed that false positives decreased from `14` to `10` and false negatives decreased from `12` to `7`, with `8` of the `12` rescues corresponding to LoS samples that the baseline had misclassified as NLoS. Together, these results support the interpretation that CP7 channel-resolved features reduce geometric LoS/NLoS ambiguity.

### Option C: Robustness and feature paragraph

This interpretation remained consistent under robustness checks. Position-aware spatial CV preserved the gain (`0.8406` vs. `0.9066`), and independent LOSO validation improved in both directions (`B -> C`: `0.7578 -> 0.8299`; `C -> B`: `0.8327 -> 0.8735`). Feature analysis should also be stated conservatively: `gamma` forms the main complementary axis, LHCP first-path amplitude provides additional support, and RHCP contribution is weaker and less stable, with `a_FP_RHCP_rx2` flipping sign between `B` and `C`. These observations support complementarity beyond conventional CIR descriptors, but any branch-specific physical mechanism should remain at hypothesis level.

## 9. Evidence Files Used by Version 2.0

Main paired result files:

- `03_reviewer_geometric/geometric/incremental_summary.csv`
- `03_reviewer_geometric/geometric/mcnemar_tests.csv`
- `03_reviewer_geometric/geometric/misclassification_recovery_overall.csv`

Additional support files from `geometric_l1_support_bundle_20260413`:

- `04_report/key_metrics_snapshot.csv`
- `05_loso_generalization_check/loso_summary.csv`
- `06_error_type_directionality_check/error_type_summary.csv`
- `07_coefficient_sign_stability_check/coefficient_sign_stability_cp7_focus.csv`
- `08_calibration_check/calibration_summary.csv`
