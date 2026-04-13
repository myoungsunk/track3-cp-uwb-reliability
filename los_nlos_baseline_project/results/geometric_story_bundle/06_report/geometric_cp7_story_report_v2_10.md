# Geometric LoS/NLoS Validation Report (Version 2.10)

This version keeps the `v2.0` evidence chain unchanged and applies the most conservative baseline naming scheme for manuscript use.

## 1. Recommended Naming Scheme

Use the following three labels consistently:

| Role | Recommended name |
|---|---|
| Full geometric reference across all six cases | `full 6-case reference baseline` |
| Direct comparator on the CP7-capable subset | `paired 5-feature subset baseline` |
| Proposed model on the same paired subset | `proposed CP7-augmented paired model` |

This naming is the safest option because it makes the evaluation scope explicit before the feature definition.

## 2. Baseline Separation Statement

The manuscript should clearly separate the two evaluation stages.

| Evaluation stage | Data universe | Model definition | Main result | Use in manuscript |
|---|---|---|---:|---|
| Full 6-case reference baseline | `CP_caseA/B/C` + `LP_caseA/B/C` | Original reference model used in the full geometric rerun | AUC `0.7959` | Broad reference only |
| Paired 5-feature subset baseline | `CP_caseB` + `CP_caseC`, CP only, `n=112` | Same paired-fold subset baseline used for CP7 contribution testing | AUC `0.8498` | Direct CP7 comparator |
| Proposed CP7-augmented paired model | Same `CP_caseB` + `CP_caseC` subset and same folds | Paired subset baseline plus 6 CP7 features | AUC `0.9139` | Main paired result |

The manuscript should therefore avoid any wording that directly connects `0.7959` to `0.9139` as a single baseline-to-proposed jump.

The safe formulation is:

- The `full 6-case reference baseline` achieved AUC `0.7959`.
- CP7 contribution was evaluated separately on the CP7-capable paired subset.
- On that subset, the `paired 5-feature subset baseline` achieved AUC `0.8498`, and the `proposed CP7-augmented paired model` achieved AUC `0.9139`.

## 3. Main Result Chain

The CP7-capable paired subset contains `112` samples with a balanced `56/56` LoS/NLoS split.

| Evidence | Paired 5-feature subset baseline | Proposed CP7-augmented paired model | Interpretation |
|---|---:|---:|---|
| Overall paired AUC | `0.8498` | `0.9139` | Same-fold gain |
| Brier score | `0.1556` | `0.1126` | Probability error decreased |
| Exact McNemar | - | `p = 0.0352` | Paired decision quality improved |
| Ambiguity band AUC `[0.4, 0.6]` | `0.4286` | `0.9286` | Gain concentrates on uncertain samples |
| Total errors on B+C | `26` | `17` | Net reduction of `9` |

Operationally:

- Baseline errors rescued: `12`
- New harms introduced: `3`
- Rescue rate given baseline error: `0.4615`
- Harm rate given baseline correct: `0.0349`

Within the ambiguity band `[0.4, 0.6]`:

- Baseline hard-case errors: `9`
- Proposed hard-case errors: `3`
- Hard-case rescues: `6`
- Hard-case new harms: `0`

This supports the claim that CP7 mainly reduces geometric ambiguity rather than only raising an average metric.

## 4. Robustness Summary

| Check | Baseline | Proposed | Reading |
|---|---:|---:|---|
| Position-aware spatial CV (`leave_one_position_out`) | `0.8406` | `0.9066` | Improvement remains under position-aware splitting |
| LOSO `B -> C` | `0.7578` | `0.8299` | Cross-scenario gain remains positive |
| LOSO `C -> B` | `0.8327` | `0.8735` | Cross-scenario gain remains positive |
| L1 logistic on B+C | `0.8444` | `0.8763` | Gain remains after sparse regularization |

Independent reviewer-side checking also reported a GroupKFold-style position-aware result of `0.8313 -> 0.8970` (`delta AUC +0.0657`), which is directionally aligned with the stored spatial CV result.

## 5. Conservative Feature Interpretation

The safest synthesis is:

- `gamma` forms the main complementary axis.
- LHCP first-path amplitude provides additional support.
- RHCP contribution is weaker and less stable.

This wording is consistent with correlation, permutation, ablation, L1, and sign-stability evidence.

## 6. Manuscript-Ready Paragraphs

### Paragraph A: Baseline definition

Across the full geometric rerun, the `full 6-case reference baseline` achieved an OOF AUC of `0.7959`. Because the six channel-resolved CP7 features are available only for the CP measurements of `CP_caseB` and `CP_caseC`, the contribution of CP7 was evaluated separately on a CP7-capable paired subset rather than by direct comparison to the full reference stage. This paired subset contained `112` samples with a balanced `56/56` LoS/NLoS split. Under the same cross-validation folds, the `paired 5-feature subset baseline` achieved an AUC of `0.8498`, whereas the `proposed CP7-augmented paired model` achieved `0.9139`. The proposed model also reduced the Brier score by `0.0430`, and the exact McNemar test yielded `p = 0.0352`, indicating improved paired decision quality.

### Paragraph B: Ambiguity reduction

The gain was concentrated on samples that the baseline judged ambiguously. In the baseline ambiguity band `[0.4, 0.6]`, AUC increased from `0.4286` to `0.9286`. On the full B+C subset, the proposed model corrected `12` of the `26` baseline errors while introducing only `3` new errors; within the ambiguity band it rescued `6` of the `9` baseline errors and introduced no new harm. These patterns support the interpretation that CP7 channel-resolved features reduce geometric LoS/NLoS ambiguity.

### Paragraph C: Robustness and feature role

This interpretation remained consistent under robustness checks. Position-aware spatial CV preserved the gain (`0.8406` vs. `0.9066`), and LOSO validation improved in both directions (`B -> C`: `0.7578 -> 0.8299`; `C -> B`: `0.8327 -> 0.8735`). Feature analysis should be stated conservatively: `gamma` forms the main complementary axis, LHCP first-path amplitude provides additional support, and RHCP contribution is weaker and less stable. These observations support complementarity beyond conventional CIR descriptors, but any branch-specific physical mechanism should remain hypothesis-level.

## 7. When To Use Version 2.10

Choose `v2.10` if the priority is maximum reviewer defensibility on baseline-definition clarity. This version is best when you want the terminology itself to foreground evaluation scope before feature composition.
