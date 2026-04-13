# Geometric L1 Support Report

## 1. Purpose

- Create a fresh evidence bundle for manuscript writing.
- Re-run the paired reviewer diagnostics and the spatial-CV priority validation.
- Add an L1-regularized logistic check to address the overfitting question for the 112-sample B+C subset.

## 2. Step 1: Reviewer rerun

- Output root: `D:\OneDrive - postech.ac.kr\명선\2026\2. ISAC\track3-cp-uwb-reliability\los_nlos_baseline_project\results\geometric_l1_support_bundle_20260413\01_reviewer_rerun`
- Paired B+C baseline AUC: `0.8498`
- Paired B+C proposed AUC: `0.9139`
- Delta AUC: `0.0641`
- Delta Brier: `-0.0430`
- Exact McNemar p-value: `0.0352`
- These rerun outputs provide the paired AUC/Brier evidence used in the manuscript.

## 3. Step 2: Priority rerun

- Output root: `D:\OneDrive - postech.ac.kr\명선\2026\2. ISAC\track3-cp-uwb-reliability\los_nlos_baseline_project\results\geometric_l1_support_bundle_20260413\02_priority_rerun`
- Spatial CV baseline AUC: `0.8406`
- Spatial CV proposed AUC: `0.9066`
- These rerun outputs provide the spatially aware robustness evidence.

## 4. Step 3: L1-regularized logistic check

- `baseline_5feature_l1`: AUC `0.8444`, accuracy `0.7679`, Brier `0.1586`, full-fit selected `3` features, lambda `0.0114826`.
  Selected full-fit features: `fp_energy_db, kurtosis_pdp, rms_delay_spread_ns`
- `proposed_11feature_l1`: AUC `0.8763`, accuracy `0.8393`, Brier `0.1369`, full-fit selected `11` features, lambda `0.00484218`.
  Selected full-fit features: `fp_energy_db, skewness_pdp, kurtosis_pdp, mean_excess_delay_ns, rms_delay_spread_ns, gamma_CP_rx1, gamma_CP_rx2, a_FP_RHCP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2`

### CP7 focus features under L1

- `gamma_CP_rx2`: full-fit selected=`1`, selection frequency=`1.00`, coefficient=`-1.260055`
- `a_FP_LHCP_rx1`: full-fit selected=`1`, selection frequency=`1.00`, coefficient=`1.203820`
- `gamma_CP_rx1`: full-fit selected=`1`, selection frequency=`0.80`, coefficient=`0.514581`
- `a_FP_LHCP_rx2`: full-fit selected=`1`, selection frequency=`0.80`, coefficient=`0.017546`
- Stable focus features across folds (selection frequency >= 0.8): `gamma_CP_rx2, a_FP_LHCP_rx1, gamma_CP_rx1, a_FP_LHCP_rx2`

## 5. Recovery snapshot

- Baseline errors: `26`
- Proposed errors: `17`
- Rescued by proposed: `12`
- Harmed by proposed: `3`
- Rescue rate given baseline error: `0.4615`
- Harm rate given baseline correct: `0.0349`

## 6. File Guide

- `01_reviewer_rerun`: fresh paired reviewer evidence
- `02_priority_rerun`: fresh spatial-CV and ablation/permutation evidence
- `03_l1_regularization_check`: new L1 logistic outputs
- `04_report/key_metrics_snapshot.csv`: condensed evidence table for manuscript drafting