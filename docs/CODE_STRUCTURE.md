# Code Structure Guide

This document is a practical guide to the current code structure of `track3-cp-uwb-reliability`.
It explains:

- where the main entry points are
- how raw data moves through the codebase
- which runners are used for which purpose
- where outputs are written
- which files are most important when reading the project

This guide reflects the current code, not just the original design intent.

## 1. Repository Layout

```text
track3-cp-uwb-reliability/
|- src/                              MATLAB source files
|- tests/                            unit and smoke tests
|- docs/                             high-level documentation
|- specs/                            detailed design/specification docs
|- data/                             raw and processed data
|- results/                          outputs from legacy/main runners
|- LOS_NLOS_EXPORT_20260405/         coordinate-based label CSV
|- cp7_feature_diagnostics_project/  dedicated CP7 diagnostics run folder
|- CP_caseA.csv / CP_caseB.csv / CP_caseC.csv
|- CP_caseA_4port.csv / CP_caseB_4port.csv / CP_caseC_4port.csv
`- LP_caseA.csv / LP_caseB.csv / LP_caseC.csv
```

The main implementation lives in `src/`. Most top-level workflows are thin runners that call shared utilities from `src/`.

## 2. Common Data Flow

Most workflows follow the same basic path:

```text
CSV or MAT input
  -> load_sparam_table
  -> build_sim_data_from_table
  -> extract_features_batch
  -> task-specific runner
  -> results folder
```

### 2.1 `src/load_sparam_table.m`

Purpose:
- Load CSV or MAT input
- Normalize column names and coordinate/frequency fields
- Convert magnitude/phase or real/imag columns into complex S-parameters
- Detect 4-port CP input when LHCP columns are present

Main output:
- `freq_table`

Important fields in `freq_table`:
- `x_coord_mm`, `y_coord_mm`
- `freq_ghz`
- `S21_rx1`, `S21_rx2`
- `group_id`
- `pol_type`, `case_id`
- optional 4-port fields:
  `S21_rhcp_rx1`, `S21_lhcp_rx1`, `S21_rhcp_rx2`, `S21_lhcp_rx2`

### 2.2 `src/build_sim_data_from_table.m`

Purpose:
- Group rows by position
- Apply Hanning window and zero-padding
- Run IFFT to build CIRs
- Attach coordinate, RSS, and binary labels

Main output:
- `sim_data` struct

Important fields in `sim_data`:
- `CIR_rx1`, `CIR_rx2`
- `t_axis`, `fs_eff`
- `x_coord_m`, `y_coord_m`
- `RSS_rx1`, `RSS_rx2`
- `labels`
- `case_id`, `pol_type`
- optional 4-port CIR/RSS fields for RHCP/LHCP

Label behavior:
- Labels are loaded from `LOS_NLOS_EXPORT_20260405/track23_all_scenarios_los_nlos.csv`
- The standard `sim_data.labels` field keeps one binary LoS/NLoS label for compatibility with older runners

### 2.3 `src/extract_features_batch.m`

Purpose:
- Compute feature values for each position from CIR data
- Handle both standard 2-channel input and 4-port CP input

Base outputs:
- `r_CP`
- `a_FP`
- `label`
- `valid_flag`

Additional outputs in 4-port mode:
- `r_CP_rx1`, `r_CP_rx2`
- `a_FP_RHCP_rx1`, `a_FP_LHCP_rx1`
- `a_FP_RHCP_rx2`, `a_FP_LHCP_rx2`
- `fp_idx_RHCP_rx1`, `fp_idx_RHCP_rx2`
- `fp_idx_diff_rx12`
- `fp_delay_diff_ns_rx12`

Main output object:
- `feature_table`

## 3. Main Execution Paths

The repository is not organized around a single runner. It has several parallel entry points for different analysis goals.

### 3.1 `src/main_run_all.m`

This is the legacy main Track 3 pipeline.

Workflow:
1. Extract or load feature table
2. Train 2-feature logistic regression
3. Run ML benchmark
4. Run ablation
5. Generate figures
6. Save outputs
7. Optionally run 4-port B/C sweep

Default classification features:
- `r_CP`
- `a_FP`

Typical output root:
- `results/`

Use this when:
- you want the original main pipeline
- you want the standard 2-feature baseline

### 3.2 `src/run_casec_4port.m`

This runs the existing 2-feature classification flow on one 4-port CP CSV file.

Behavior:
- loads a 4-port file such as `CP_caseC_4port.csv`
- uses one label basis, defaulting to `material_class`
- runs logistic, benchmark, and ablation if both classes are present with enough samples
- skips classification stages when the minority class is too small

Typical output:
- `results/<run_name>/`

Use this when:
- you want the old 2-feature workflow on a single 4-port case

### 3.3 `src/run_casec_4port_cp3.m`

This is a separate 3-feature variant of the 4-port runner.

Features used:
- `gamma_CP = log10(r_CP)`
- `a_FP`
- `fp_idx_diff_rx12`

Reason it exists:
- the original 2-feature runner was kept unchanged
- the 3-feature flow was added as a separate file rather than modifying the older one

Use this when:
- you want a compact CP3 comparison without changing the legacy 2-feature path

### 3.4 `src/run_subset_search_cp7.m`

This performs exhaustive subset search over 7 CP features.

Features:
1. `gamma_CP_rx1`
2. `gamma_CP_rx2`
3. `a_FP_RHCP_rx1`
4. `a_FP_LHCP_rx1`
5. `a_FP_RHCP_rx2`
6. `a_FP_LHCP_rx2`
7. `fp_idx_diff_rx12`

Scopes:
- `B`
- `C`
- `B+C`

Behavior:
- evaluates all non-empty subsets
- saves per-scope ranking tables
- is focused on model selection, not detailed interpretation

Use this when:
- you want to know which feature subset performs best

### 3.5 `src/run_cp7_feature_diagnostics.m`

This is the new 7-feature diagnostics pipeline.

Goal:
- analyze feature quality, redundancy, spatial dependence, and baseline model behavior

Default label modes:
- `geometric_class`
- `material_class`

Default scopes:
- `B`
- `C`
- `B+C`

Output stages:
- `00_summary`
- `01_sanity`
- `02_global`
- `03_collinearity`
- `04_local`
- `05_baselines`

Key characteristics:
- independent from the older 2-feature and CP3 training flows
- builds a metadata-rich analysis table with coordinates and scenario tags
- computes global binary metrics, local KNN AUC maps, L1 logistic baselines, and random-forest baselines
- skips scopes with an unusable minority class, and records the reason in the summary
- current local-K defaults are:
  - `B` and `C`: `15`
  - `B+C`: `30`

Use this when:
- you need interpretation rather than just a final classifier
- you want local winner maps or collinearity analysis
- you want geometric and material label views side by side

### 3.6 `cp7_feature_diagnostics_project/run_cp7_project.m`

This is a thin launcher for the CP7 diagnostics workflow.

Behavior:
- adds `src/` to path
- calls `run_cp7_feature_diagnostics`
- writes outputs directly into `cp7_feature_diagnostics_project/`

Use this when:
- you want the current CP7 diagnostics results to stay in a dedicated folder rather than under `results/`

Run example:

```matlab
run('cp7_feature_diagnostics_project/run_cp7_project.m')
```

## 4. CP7 Diagnostics Internal Structure

### 4.1 `src/build_cp7_analysis_table.m`

Purpose:
- build one combined analysis table from `CP_caseB_4port.csv` and `CP_caseC_4port.csv`
- preserve both metadata and the 7 modeled features

Important output columns:
- `sample_id`
- `scenario`
- `case_id`
- `x_m`, `y_m`
- `valid_flag`
- `gamma_CP_rx1`, `gamma_CP_rx2`
- `a_FP_RHCP_rx1`, `a_FP_LHCP_rx1`
- `a_FP_RHCP_rx2`, `a_FP_LHCP_rx2`
- `fp_idx_diff_rx12`
- `label_geometric`, `label_material`
- `all_features_valid`

Feature definition note:
- `gamma_CP_rx* = log10(max(r_CP_rx*, gamma_cp_floor))`

### 4.2 `src/cp7_binary_feature_metrics.m`

Purpose:
- measure how discriminative a single feature is for a binary label

Metrics:
- point-biserial correlation
- raw AUC
- effective AUC
- KS statistic
- mutual information
- effect direction:
  - `higher->LoS`
  - `higher->NLoS`

### 4.3 `src/cp7_local_knn_auc.m`

Purpose:
- compute local AUC around each sample using its K nearest neighbors

Important outputs:
- `local_raw_auc`
- `local_effective_auc`
- `n_local`
- `n_los_local`
- `n_nlos_local`
- `min_class_local`
- `unstable_flag`

Interpretation:
- if the local neighborhood has only one class, local AUC is `NaN`
- if the minority count is too small, the point is marked unstable

### 4.4 Stage Meaning in `run_cp7_feature_diagnostics.m`

`01_sanity`
- class counts
- valid sample counts
- missing-value counts
- spatial coverage plots

`02_global`
- feature-level global discriminative metrics
- class-conditional distribution plots

`03_collinearity`
- Pearson and Spearman feature-feature dependence

`04_local`
- local AUC maps per feature
- winner maps across space

`05_baselines`
- univariate logistic
- multivariate L1 logistic
- coordinate-augmented L1 logistic
- random forest

`00_summary`
- compact cross-scope summary of the above results

## 5. Core Data Objects

### 5.1 `freq_table`

Standardized frequency-domain table created from raw input.

Main use:
- common entry format before CIR construction

### 5.2 `sim_data`

Time-domain intermediate struct containing CIR, coordinates, labels, and metadata.

Main use:
- feature extraction
- localization
- shared intermediate across multiple runners

### 5.3 `feature_table`

Feature-level table used by the older classification workflows.

Main use:
- logistic training
- benchmark
- ablation

### 5.4 `analysis_table`

Metadata-rich table used by the new CP7 diagnostics pipeline.

Main use:
- global and local diagnostics
- multi-label analysis
- coordinate-aware interpretation

## 6. Label Handling

There are effectively two label layers in the current codebase.

### 6.1 Standard binary label

Used by the older training flows:
- `label`
- `sim_data.labels`

These are consumed by:
- `main_run_all`
- `run_casec_4port`
- `run_casec_4port_cp3`
- `run_subset_search_cp7`

### 6.2 Diagnostics dual-label view

Used by the CP7 diagnostics path:
- `label_geometric`
- `label_material`

This allows the same feature set to be evaluated under two different interpretations of LoS/NLoS.

Important current behavior:
- `material_class / B` is skipped in diagnostics because its minority class count is too small to support meaningful global/local analysis

## 7. Output Locations

### 7.1 Legacy and general runners

Most legacy outputs go under:

```text
results/<run_name>/
```

Examples:
- `results/step1_features.csv`
- `results/<casec_run>/`
- `results/<subset_search_run>/`

### 7.2 CP7 diagnostics dedicated folder

Current dedicated output root:

```text
cp7_feature_diagnostics_project/
|- 00_summary/
|- 01_sanity/
|- 02_global/
|- 03_collinearity/
|- 04_local/
|- 05_baselines/
`- run_cp7_project.m
```

This folder serves both as:
- the launcher location
- the results root

## 8. Tests

The `tests/` folder mixes small unit tests and smoke tests.

CP7 diagnostics related tests:
- `test_build_cp7_analysis_table.m`
- `test_cp7_binary_feature_metrics.m`
- `test_cp7_local_knn_auc.m`
- `test_run_cp7_feature_diagnostics_smoke.m`

Examples of older/common tests:
- `test_build_sim_data.m`
- `test_train_logistic_backends.m`
- `test_run_joint_phase1_smoke.m`

Typical MATLAB test commands:

```matlab
addpath('tests')
test_build_cp7_analysis_table
test_cp7_binary_feature_metrics
test_cp7_local_knn_auc
test_run_cp7_feature_diagnostics_smoke
```

## 9. Recommended Reading Order

If someone needs to understand the project quickly, this order is efficient:

1. `src/main_run_all.m`
2. `src/load_sparam_table.m`
3. `src/build_sim_data_from_table.m`
4. `src/extract_features_batch.m`
5. `src/run_casec_4port.m`
6. `src/run_casec_4port_cp3.m`
7. `src/run_subset_search_cp7.m`
8. `src/run_cp7_feature_diagnostics.m`
9. `src/build_cp7_analysis_table.m`

That order shows the architecture as:
- raw data normalization
- shared feature construction
- runner-specific branching

## 10. Practical Summary

From an operations perspective, the repository currently behaves like this:

- the project has a shared feature-extraction layer
- multiple runners sit on top of that layer for different experiments
- the legacy main path is still centered on `r_CP + a_FP`
- the 4-port runners were added as separate files to avoid breaking older flows
- the CP7 diagnostics path is primarily an interpretation pipeline, not just a training pipeline

In short:
- use `main_run_all` for the original main workflow
- use `run_casec_4port*` for case-specific 4-port classification runs
- use `run_subset_search_cp7` for subset ranking
- use `run_cp7_feature_diagnostics` or `cp7_feature_diagnostics_project/run_cp7_project.m` for feature diagnostics and spatial analysis

## 11. Related Documentation

Detailed design docs still exist in `specs/` and `docs/`.

Useful references:
- `specs/spec_load_and_build.md`
- `specs/spec_extract_features_v2.md`
- `specs/spec_logistic_model_v2.md`
- `specs/spec_rssd_localization.md`
- `specs/spec_run_joint.md`
- `docs/ARCHITECTURE.md`

This file is intended as the current codebase guide, not as a replacement for those lower-level specifications.
