# CP7 Priority Validation Report

## Validation 1: Channel-Resolved Correlation

| Feature | max abs corr | Decision |
|---|---:|---|
| gamma_CP_rx2 | 0.3540 | partial_redundancy |
| gamma_CP_rx1 | 0.4085 | partial_redundancy |
| a_FP_LHCP_rx2 | 0.5326 | partial_redundancy |
| a_FP_LHCP_rx1 | 0.5724 | partial_redundancy |
| a_FP_RHCP_rx2 | 0.6442 | high_redundancy |
| a_FP_RHCP_rx1 | 0.6579 | high_redundancy |

## Validation 2: Stepwise Ablation (B+C)

| Target | Variant | AUC | Delta vs Full | Brier | Delta Brier |
|---|---|---:|---:|---:|---:|
| material | baseline | 0.9474 | 0.0192 | 0.0853 | -0.0095 |
| material | full_proposed | 0.9282 | 0.0000 | 0.0948 | 0.0000 |
| material | drop_gamma_rx2_only | 0.9337 | 0.0056 | 0.0945 | -0.0003 |
| material | drop_gamma_both | 0.9399 | 0.0118 | 0.0899 | -0.0049 |
| material | drop_rx1_branch | 0.9307 | 0.0025 | 0.0927 | -0.0021 |
| material | drop_lhcp_pair | 0.9356 | 0.0074 | 0.0904 | -0.0043 |
| material | drop_rhcp_pair | 0.9387 | 0.0105 | 0.0864 | -0.0084 |
| geometric | baseline | 0.8348 | -0.0676 | 0.1651 | 0.0413 |
| geometric | full_proposed | 0.9024 | 0.0000 | 0.1238 | 0.0000 |
| geometric | drop_gamma_rx2_only | 0.8938 | -0.0086 | 0.1305 | 0.0066 |
| geometric | drop_gamma_both | 0.8747 | -0.0277 | 0.1391 | 0.0153 |
| geometric | drop_rx1_branch | 0.8842 | -0.0182 | 0.1345 | 0.0106 |
| geometric | drop_lhcp_pair | 0.8820 | -0.0204 | 0.1374 | 0.0136 |
| geometric | drop_rhcp_pair | 0.8938 | -0.0086 | 0.1226 | -0.0012 |

## Validation 3: Permutation Importance (B+C)

| Target | Model | Feature | Mean AUC drop | Median AUC drop |
|---|---|---|---:|---:|
| material | logistic | a_FP_LHCP_rx1 | 0.0104 | 0.0105 |
| material | logistic | gamma_CP_rx1 | 0.0088 | 0.0090 |
| material | logistic | gamma_CP_rx2 | 0.0050 | 0.0043 |
| material | logistic | a_FP_RHCP_rx1 | 0.0047 | 0.0043 |
| material | logistic | a_FP_RHCP_rx2 | 0.0020 | 0.0019 |
| material | logistic | a_FP_LHCP_rx2 | -0.0005 | -0.0006 |
| material | rf | a_FP_RHCP_rx1 | 0.0153 | 0.0156 |
| material | rf | a_FP_LHCP_rx1 | 0.0085 | 0.0093 |
| material | rf | gamma_CP_rx2 | 0.0009 | 0.0009 |
| material | rf | a_FP_LHCP_rx2 | -0.0001 | 0.0000 |
| material | rf | a_FP_RHCP_rx2 | -0.0008 | -0.0006 |
| material | rf | gamma_CP_rx1 | -0.0013 | -0.0012 |
| geometric | logistic | a_FP_LHCP_rx1 | 0.0748 | 0.0773 |
| geometric | logistic | gamma_CP_rx2 | 0.0419 | 0.0427 |
| geometric | logistic | a_FP_RHCP_rx1 | 0.0136 | 0.0137 |
| geometric | logistic | gamma_CP_rx1 | 0.0126 | 0.0128 |
| geometric | logistic | a_FP_LHCP_rx2 | 0.0089 | 0.0091 |
| geometric | logistic | a_FP_RHCP_rx2 | -0.0069 | -0.0069 |
| geometric | rf | gamma_CP_rx2 | 0.0432 | 0.0435 |
| geometric | rf | a_FP_LHCP_rx2 | 0.0188 | 0.0189 |
| geometric | rf | a_FP_LHCP_rx1 | 0.0017 | 0.0024 |
| geometric | rf | gamma_CP_rx1 | -0.0018 | -0.0021 |
| geometric | rf | a_FP_RHCP_rx2 | -0.0032 | -0.0029 |
| geometric | rf | a_FP_RHCP_rx1 | -0.0037 | -0.0037 |
