# Geometric LoS/NLoS Validation Report

## 1. Purpose

This report explains only the `geometric_class` target. It is written so that a first-time reader can understand the current status, the exact execution conditions, the data universe used at each step, and which claims are supported by the rerun results.

## 2. What Is Being Classified

- This report uses the `geometric_class` label only.
- The baseline stage uses the full 6-case dataset (`CP_caseA/B/C`, `LP_caseA/B/C`).
- The CP7 stages use `CP_caseB` and `CP_caseC` only, because the six channel-resolved CP7 features are available only for those CP measurements.
- Because the sample universe changes between stages, the full-baseline AUC and the CP7-subset AUC must be interpreted separately.

## 3. Exact Execution Conditions

- Full baseline: 16 CIR features, 5-fold stratified logistic regression, random seed 42, threshold 0.5, regularization `lambda = 1e-2`.
- Reviewer CP7 stage: baseline feature set `{fp_energy_db, skewness_pdp, kurtosis_pdp, mean_excess_delay_ns, rms_delay_spread_ns}`.
- Added CP7 feature set: `{gamma_CP_rx1, gamma_CP_rx2, a_FP_RHCP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2}`.
- CP7 reviewer stage: 5-fold stratified logistic regression, random seed 42, threshold 0.5, hard-case band `[0.4, 0.6]`, bootstrap repeats 1000.
- Priority stage: repeated CV count 20, permutation repeats 100, RF trees 80, RF min leaf size 2, spatial CV enabled.
- Follow-up stage: dual-RX bootstrap repeats 1000, mechanism subgroup bootstrap repeats 1000.
- A machine-readable condition table is saved at `00_execution_conditions/execution_conditions.csv`.

## 4. Data Separation by Procedure

The bundle stores each subset used for validation as a separate CSV under `02_dataset_splits`.

| Split | Description | n | LoS | NLoS |
|---|---|---:|---:|---:|
| cp7_target_dataset_raw | Joined CP7-capable geometric dataset before valid_for_cp7_model filtering | 112 | 56 | 56 |
| cp7_target_dataset_valid | Rows used for CP7 modeling after valid_for_cp7_model filtering | 112 | 56 | 56 |
| scope_B | Scenario B only | 56 | 35 | 21 |
| scope_C | Scenario C only | 56 | 21 | 35 |
| scope_BplusC | Scenario B and C combined | 112 | 56 | 56 |
| hard_case_B | Baseline confidence in [0.4, 0.6], scenario B | 9 | 4 | 5 |
| hard_case_C | Baseline confidence in [0.4, 0.6], scenario C | 8 | 3 | 5 |
| hard_case_BplusC | Baseline confidence in [0.4, 0.6], scenario B+C | 17 | 7 | 10 |
| baseline_errors_BplusC | Baseline misclassifications on B+C | 26 | 12 | 14 |
| proposed_errors_BplusC | Proposed misclassifications on B+C | 17 | 7 | 10 |
| rescued_by_cp7_BplusC | Baseline wrong but CP7-correct on B+C | 12 | 8 | 4 |
| harmed_by_cp7_BplusC | Baseline correct but CP7-wrong on B+C | 3 | 3 | 0 |

Important split files:
- `02_dataset_splits/04_scope_BplusC.csv`: final CP7 modeling universe.
- `02_dataset_splits/07_hard_case_BplusC.csv`: ambiguous subset defined by baseline confidence `[0.4, 0.6]`.
- `02_dataset_splits/10_rescued_by_cp7_BplusC.csv`: samples misclassified by baseline but corrected by CP7 fusion.
- `02_dataset_splits/11_harmed_by_cp7_BplusC.csv`: samples correct in baseline but flipped incorrectly by CP7 fusion.

## 5. Step-by-Step Validation Story

### Step 1. Full 6-case geometric baseline

- Overall geometric baseline AUC: `0.79592`.
- Overall accuracy: `0.69643`, F1: `0.75243`.
- This is the broad reference point, but it is not yet the CP7 universe.
- In the full baseline output, `CP_caseB` geometric AUC is `0.91293`.
- In the full baseline output, `CP_caseC` geometric AUC is `0.75918`.

### Step 2. Restrict to the CP7-capable universe

- The CP7 analysis universe is `CP_caseB + CP_caseC`, CP polarization only.
- After joining the baseline table and the CP7 table, the valid geometric modeling set contains 112 samples with a balanced label split of 56 LoS / 56 NLoS.
- This balanced subset is the correct universe for all CP7 claims below.

### Step 3. Reviewer validation: orthogonality, fusion gain, rescue

- On the geometric B+C subset, baseline AUC is `0.84981` and proposed AUC is `0.9139`.
- The AUC gain is `0.064094`, the Brier-score gain is `-0.04296`, and McNemar exact `p = 0.035156`.
- On the hard-case subset, baseline AUC is `0.42857` and proposed AUC is `0.92857`.
- The hard-case McNemar exact `p = 0.03125`.
- Baseline errors on B+C: `26`; proposed errors: `17`; rescued samples: `12`; harmed samples: `3`.
- This is the operational proof that CP7 features reduce geometric ambiguity: they improve paired metrics and rescue a large share of baseline mistakes.

Orthogonality snapshot versus top-3 baseline features:

| CP7 feature | max abs Spearman | mean abs Spearman |
|---|---:|---:|
| gamma_CP_rx2 | 0.3314 | 0.13009 |
| gamma_CP_rx1 | 0.39289 | 0.31628 |
| a_FP_LHCP_rx2 | 0.53255 | 0.43022 |
| a_FP_RHCP_rx2 | 0.59237 | 0.44668 |
| a_FP_LHCP_rx1 | 0.57243 | 0.49172 |
| a_FP_RHCP_rx1 | 0.54185 | 0.5012 |

Interpretation: `gamma_CP_rx2` is the most orthogonal CP7 channel, while the `a_FP` channels overlap more with existing energy/shape descriptors.

### Step 4. Priority validation: channel-resolved correlation, ablation, permutation

Channel-resolved max abs correlation against the full 5-feature baseline set:

| Feature | max abs corr | Decision |
|---|---:|---|
| gamma_CP_rx2 | 0.35396 | partial_redundancy |
| gamma_CP_rx1 | 0.40851 | partial_redundancy |
| a_FP_LHCP_rx2 | 0.53255 | partial_redundancy |
| a_FP_LHCP_rx1 | 0.57243 | partial_redundancy |
| a_FP_RHCP_rx2 | 0.64416 | high_redundancy |
| a_FP_RHCP_rx1 | 0.65789 | high_redundancy |

Ablation on geometric B+C:

| Variant | AUC | Delta vs full | Brier | Delta Brier |
|---|---:|---:|---:|---:|
| baseline | 0.83583 | -0.070057 | 0.16437 | 0.045156 |
| full_proposed | 0.90588 | 0 | 0.11921 | 0 |
| drop_gamma_rx1_only | 0.90689 | 0.0010045 | 0.11877 | -0.00044608 |
| drop_gamma_rx2_only | 0.89592 | -0.0099649 | 0.12597 | 0.0067522 |
| drop_gamma_both | 0.87867 | -0.027216 | 0.13486 | 0.015647 |
| drop_rx1_branch | 0.89364 | -0.012245 | 0.12757 | 0.0083601 |
| drop_rx2_branch | 0.89289 | -0.012994 | 0.1313 | 0.01209 |
| drop_lhcp_pair | 0.88935 | -0.016534 | 0.13233 | 0.013112 |
| drop_rhcp_pair | 0.90397 | -0.0019133 | 0.11617 | -0.0030394 |
| drop_a_fp_all | 0.89716 | -0.0087213 | 0.12761 | 0.008396 |

Key reading:
- Dropping both `gamma` channels yields the largest AUC loss (`-0.027216`).
- Dropping the LHCP pair is the next-largest loss (`-0.016534`).
- Dropping the RHCP pair has a smaller impact (`-0.0019133`).
- This supports a story where `gamma` is the main complementary axis and LHCP `a_FP` is the secondary geometric helper.

Permutation importance ranking:

| Model | Feature | Mean AUC drop |
|---|---|---:|
| logistic | a_FP_LHCP_rx1 | 0.071276 |
| logistic | gamma_CP_rx2 | 0.038839 |
| logistic | a_FP_RHCP_rx1 | 0.012864 |
| logistic | gamma_CP_rx1 | 0.0084885 |
| logistic | a_FP_LHCP_rx2 | 0.0029145 |
| logistic | a_FP_RHCP_rx2 | -0.0016167 |
| rf | gamma_CP_rx2 | 0.050553 |
| rf | a_FP_LHCP_rx2 | 0.014346 |
| rf | a_FP_LHCP_rx1 | 0.0022561 |
| rf | a_FP_RHCP_rx1 | 0.00091837 |
| rf | a_FP_RHCP_rx2 | 0.00064094 |
| rf | gamma_CP_rx1 | -0.0025415 |

The geometric importance ranking again keeps `gamma` and LHCP near the top, even under a model-agnostic check.

### Step 5. Follow-up validation: single-RX vs dual-RX and subgroup mechanism checks

Single-RX vs dual-RX on geometric B+C:

| Model | AUC | Brier | Accuracy |
|---|---:|---:|---:|
| baseline_plus_rx1 | 0.90051 | 0.12605 | 0.83036 |
| baseline_plus_rx2 | 0.89923 | 0.12184 | 0.82143 |
| baseline_plus_dual | 0.9139 | 0.1126 | 0.84821 |

Dual-vs-best-single bootstrap:

| Delta AUC | 95% CI | p(dual <= best) |
|---:|---|---:|
| 0.013393 | [-0.0096309, 0.027589] | 0.237 |

Interpretation: the dual-RX gain exists numerically but is not statistically secure enough to be the main performance claim.

Mechanism subgroup checks:

| Subset | Feature | n(L/N) | AUC | Status |
|---|---|---|---:|---|
| geom_B_metal_single_bounce | a_FP_LHCP_rx1 | 35/1 | 0.77143 | underpowered |
| geom_B_metal_single_bounce | a_FP_LHCP_rx2 | 35/1 | 0.31429 | underpowered |
| geom_B_metal_single_bounce | gamma_CP_rx1 | 35/1 | 0.88571 | underpowered |
| geom_B_metal_single_bounce | gamma_CP_rx2 | 35/1 | 0.57143 | underpowered |
| geom_B_glass_partition | a_FP_LHCP_rx1 | 35/20 | 0.80286 | ok |
| geom_B_glass_partition | a_FP_LHCP_rx2 | 35/20 | 0.80571 | ok |
| geom_B_glass_partition | gamma_CP_rx1 | 35/20 | 0.62 | ok |
| geom_B_glass_partition | gamma_CP_rx2 | 35/20 | 0.41 | ok |
| geom_C_dense_clutter_all | a_FP_LHCP_rx1 | 21/35 | 0.77143 | ok |
| geom_C_dense_clutter_all | a_FP_LHCP_rx2 | 21/35 | 0.84354 | ok |
| geom_C_dense_clutter_all | gamma_CP_rx1 | 21/35 | 0.7102 | ok |
| geom_C_dense_clutter_all | gamma_CP_rx2 | 21/35 | 0.37415 | ok |

Interpretation: the mechanism trend is partially supportive, but some subgroup claims are underpowered and should stay in the discussion section rather than the main claim.

## 6. What Is Actually Proven for the Geometric Target

Supported:
- The 6 CP7 features improve geometric LoS/NLoS discrimination on the CP7-capable B+C subset.
- The improvement is not only in AUC; it is also visible in Brier score, McNemar paired testing, and explicit rescue of baseline errors.
- The improvement concentrates on ambiguous samples defined by baseline confidence `[0.4, 0.6]`.
- `gamma` is the main complementary feature group, and LHCP `a_FP` is the secondary geometric helper.

Not yet supported as a main claim:
- A universal multi-RX diversity gain.
- A strong subgroup-mechanism claim for every material/object subset.
- Any blanket statement that the CP7 features improve both geometric and material targets equally.

## 7. File Guide

- `00_execution_conditions`: exact run settings and reproduction command.
- `01_baseline_full6cases`: rerun geometric baseline outputs copied from the fresh baseline run.
- `02_dataset_splits`: step-by-step geometric subsets used in the CP7 story.
- `03_reviewer_geometric`: reviewer diagnostics rerun; contains geometric outputs plus the material helper dataset required by the priority stage.
- `04_priority_validations`: geometric-only correlation/ablation/permutation rerun.
- `05_followup_validations`: geometric-only single-vs-dual RX and subgroup rerun.
- `06_report`: this report and the file manifest.
