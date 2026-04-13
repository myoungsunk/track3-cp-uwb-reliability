# CP7 Reviewer Diagnostics Summary

Baseline feature set: `fp_energy_db, skewness_pdp, kurtosis_pdp, mean_excess_delay_ns, rms_delay_spread_ns`

Added CP7 feature set: `gamma_CP_rx1, gamma_CP_rx2, a_FP_RHCP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2`

## Incremental Gain

| Target | Scope | Subset | n | Baseline AUC | Proposed AUC | Delta AUC | Delta 95% CI | Baseline Brier | Proposed Brier | Delta Brier | Status |
|---|---|---|---:|---:|---:|---:|---|---:|---:|---:|---|
| material | B | overall | 56 | NaN | NaN | NaN | [NaN, NaN] | NaN | NaN | NaN | skipped |
| material | B | hard_case_0p4_0p6 | 0 | NaN | NaN | NaN | [NaN, NaN] | NaN | NaN | NaN | skipped |
| material | C | overall | 56 | 0.9297 | 0.9281 | -0.0016 | [-0.0264, 0.0249] | 0.1033 | 0.0977 | -0.0055 | ok |
| material | C | hard_case_0p4_0p6 | 6 | 0.2500 | 0.7500 | 0.5000 | [-0.5000, 1.0000] | 0.2600 | 0.1784 | -0.0816 | ok |
| material | B+C | overall | 112 | 0.9579 | 0.9536 | -0.0043 | [-0.0226, 0.0131] | 0.0766 | 0.0788 | 0.0022 | ok |
| material | B+C | hard_case_0p4_0p6 | 3 | 1.0000 | 1.0000 | 0.0000 | [0.0000, 0.0000] | 0.2134 | 0.1877 | -0.0257 | ok |
| geometric | B | overall | 56 | 0.8626 | 0.8952 | 0.0327 | [-0.0486, 0.1151] | 0.1535 | 0.1226 | -0.0309 | ok |
| geometric | B | hard_case_0p4_0p6 | 12 | 0.4444 | 0.8519 | 0.4074 | [-0.1818, 1.0000] | 0.2624 | 0.1359 | -0.1264 | ok |
| geometric | C | overall | 56 | 0.8027 | 0.8912 | 0.0884 | [0.0209, 0.1742] | 0.1834 | 0.1268 | -0.0566 | ok |
| geometric | C | hard_case_0p4_0p6 | 9 | 0.6667 | 1.0000 | 0.3333 | [0.0000, 0.7778] | 0.2351 | 0.0523 | -0.1827 | ok |
| geometric | B+C | overall | 112 | 0.8498 | 0.9139 | 0.0641 | [0.0131, 0.1198] | 0.1556 | 0.1126 | -0.0430 | ok |
| geometric | B+C | hard_case_0p4_0p6 | 17 | 0.4286 | 0.9286 | 0.5000 | [0.2222, 0.7753] | 0.2583 | 0.1243 | -0.1340 | ok |

## McNemar

| Target | Scope | Subset | n | b | c | p |
|---|---|---|---:|---:|---:|---:|
| material | B | overall | 56 | NaN | NaN | NaN |
| material | B | hard_case_0p4_0p6 | 0 | NaN | NaN | NaN |
| material | C | overall | 56 | 1 | 3 | 0.625000 |
| material | C | hard_case_0p4_0p6 | 6 | 1 | 3 | 0.625000 |
| material | B+C | overall | 112 | 5 | 2 | 0.453125 |
| material | B+C | hard_case_0p4_0p6 | 3 | 1 | 1 | 1.000000 |
| geometric | B | overall | 56 | 3 | 7 | 0.343750 |
| geometric | B | hard_case_0p4_0p6 | 12 | 1 | 4 | 0.375000 |
| geometric | C | overall | 56 | 3 | 8 | 0.226562 |
| geometric | C | hard_case_0p4_0p6 | 9 | 0 | 3 | 0.250000 |
| geometric | B+C | overall | 112 | 3 | 12 | 0.035156 |
| geometric | B+C | hard_case_0p4_0p6 | 17 | 0 | 6 | 0.031250 |

## Orthogonality Snapshot

| Target | CP7 feature | max |rho| vs top3 | mean |rho| vs top3 |
|---|---|---:|---:|
| material | gamma_CP_rx2 | 0.3314 | 0.1301 |
| material | gamma_CP_rx1 | 0.3929 | 0.3163 |
| material | a_FP_LHCP_rx2 | 0.5326 | 0.4302 |
| material | a_FP_RHCP_rx2 | 0.5924 | 0.4467 |
| material | a_FP_LHCP_rx1 | 0.5724 | 0.4917 |
| material | a_FP_RHCP_rx1 | 0.5418 | 0.5012 |
| geometric | gamma_CP_rx2 | 0.3314 | 0.1301 |
| geometric | gamma_CP_rx1 | 0.3929 | 0.3163 |
| geometric | a_FP_LHCP_rx2 | 0.5326 | 0.4302 |
| geometric | a_FP_RHCP_rx2 | 0.5924 | 0.4467 |
| geometric | a_FP_LHCP_rx1 | 0.5724 | 0.4917 |
| geometric | a_FP_RHCP_rx1 | 0.5418 | 0.5012 |
