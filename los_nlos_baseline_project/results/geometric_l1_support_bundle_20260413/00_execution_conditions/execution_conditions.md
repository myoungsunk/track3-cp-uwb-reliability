# Geometric L1 Support Bundle

## Purpose

- Re-run the reviewer diagnostics for a fresh evidence snapshot.
- Re-run the priority validations to capture spatial CV evidence.
- Add an L1-regularized logistic check on the geometric CP7-capable B+C subset.

## Key Settings

- Random seed: `42`
- CV folds: `5`
- Classification threshold: `0.5`
- L1 NumLambda: `25`
- L1 LambdaRatio: `0.001`
- Baseline features: `fp_energy_db, skewness_pdp, kurtosis_pdp, mean_excess_delay_ns, rms_delay_spread_ns`
- CP7 features: `gamma_CP_rx1, gamma_CP_rx2, a_FP_RHCP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2`

## Reproduction

- `matlab -batch "cd('los_nlos_baseline_project'); outputs = run_geometric_l1_support_bundle();"`