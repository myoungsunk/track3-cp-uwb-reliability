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

| Target | Variant | AUC mean | 95% CI | Delta vs Full | Brier | Delta Brier |
|---|---|---:|---|---:|---:|---:|
| geometric | baseline | 0.8358 | [0.8147, 0.8524] | -0.0701 | 0.1644 | 0.0452 |
| geometric | full_proposed | 0.9059 | [0.8795, 0.9225] | 0.0000 | 0.1192 | 0.0000 |
| geometric | drop_gamma_rx1_only | 0.9069 | [0.8804, 0.9212] | 0.0010 | 0.1188 | -0.0004 |
| geometric | drop_gamma_rx2_only | 0.8959 | [0.8680, 0.9117] | -0.0100 | 0.1260 | 0.0068 |
| geometric | drop_gamma_both | 0.8787 | [0.8517, 0.8973] | -0.0272 | 0.1349 | 0.0156 |
| geometric | drop_rx1_branch | 0.8936 | [0.8622, 0.9139] | -0.0122 | 0.1276 | 0.0084 |
| geometric | drop_rx2_branch | 0.8929 | [0.8718, 0.9056] | -0.0130 | 0.1313 | 0.0121 |
| geometric | drop_lhcp_pair | 0.8893 | [0.8638, 0.9107] | -0.0165 | 0.1323 | 0.0131 |
| geometric | drop_rhcp_pair | 0.9040 | [0.8833, 0.9155] | -0.0019 | 0.1162 | -0.0030 |
| geometric | drop_a_fp_all | 0.8972 | [0.8779, 0.9123] | -0.0087 | 0.1276 | 0.0084 |

## Validation 2b: Spatial CV Check

| Target | Scope | Variant | Strategy | Folds | AUC | Brier | Accuracy |
|---|---|---|---|---:|---:|---:|---:|
| geometric | B+C | baseline | leave_one_position_out | 112 | 0.8406 | 0.1615 | 0.7589 |
| geometric | B+C | full_proposed | leave_one_position_out | 112 | 0.9066 | 0.1177 | 0.8661 |

## Validation 3: Permutation Importance (B+C)

| Target | Model | Feature | Mean AUC drop | Median AUC drop |
|---|---|---|---:|---:|
| geometric | logistic | a_FP_LHCP_rx1 | 0.0713 | 0.0716 |
| geometric | logistic | gamma_CP_rx2 | 0.0388 | 0.0410 |
| geometric | logistic | a_FP_RHCP_rx1 | 0.0129 | 0.0131 |
| geometric | logistic | gamma_CP_rx1 | 0.0085 | 0.0085 |
| geometric | logistic | a_FP_LHCP_rx2 | 0.0029 | 0.0029 |
| geometric | logistic | a_FP_RHCP_rx2 | -0.0016 | -0.0018 |
| geometric | rf | gamma_CP_rx2 | 0.0506 | 0.0505 |
| geometric | rf | a_FP_LHCP_rx2 | 0.0143 | 0.0140 |
| geometric | rf | a_FP_LHCP_rx1 | 0.0023 | 0.0022 |
| geometric | rf | a_FP_RHCP_rx1 | 0.0009 | 0.0010 |
| geometric | rf | a_FP_RHCP_rx2 | 0.0006 | 0.0006 |
| geometric | rf | gamma_CP_rx1 | -0.0025 | -0.0028 |
