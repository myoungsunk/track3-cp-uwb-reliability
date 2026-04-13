# Material B+C Interaction Check

- Pair checked: `gamma_CP_rx2` x `a_FP_RHCP_rx1`
- RF Friedman-style H statistic: 0.4828
- PDP range: 0.4301
- Interaction residual RMS: 0.0678
- Interaction residual range: 0.1578
- Peak interaction residual: 0.0350 at gamma_CP_rx2=1.7015, a_FP_RHCP_rx1=0.2089
- Trough interaction residual: -0.1229 at gamma_CP_rx2=0.5419, a_FP_RHCP_rx1=0.1967

## Logistic comparison
- pair_additive: CV AUC 0.8816, CV Acc 0.8929, delta AUC 0.0000, interaction coef NaN, p=NaN
- pair_plus_interaction: CV AUC 0.8711, CV Acc 0.8838, delta AUC -0.0105, interaction coef NaN, p=NaN
- full7_additive: CV AUC 0.8430, CV Acc 0.8925, delta AUC 0.0000, interaction coef NaN, p=NaN
- full7_plus_interaction: CV AUC 0.8167, CV Acc 0.8838, delta AUC -0.0263, interaction coef -0.0349, p=0.9854

## RF importance reference
- a_FP_RHCP_rx1: 0.9009
- a_FP_LHCP_rx1: 0.4879
- gamma_CP_rx1: 0.3895
- gamma_CP_rx2: 0.3823
- fp_idx_diff_rx12: 0.2028
- a_FP_RHCP_rx2: 0.1711
- a_FP_LHCP_rx2: -0.0014