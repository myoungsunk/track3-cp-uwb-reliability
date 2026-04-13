# CP7 Follow-up 2

## Interaction Check
- Pair: a_FP_RHCP_rx1 x gamma_CP_rx2
- RF H statistic: 0.4828
- Interaction residual range: 0.1578 (PDP range 0.4301)
- Pair logistic: additive 0.8816 -> +interaction 0.8711 (delta -0.0105)
- Full-7 logistic: additive 0.8430 -> +interaction 0.8167 (delta -0.0263, p=0.9854)

## fp_idx_diff Drop Ablation
- geometric_class / B: logistic delta 0.0157, RF delta 0.0340, single AUC 0.510, L1 selected=0, drop candidate=0, note=feature removal changes at least one model materially
- geometric_class / C: logistic delta 0.0143, RF delta 0.0463, single AUC 0.635, L1 selected=0, drop candidate=0, note=feature removal changes at least one model materially
- geometric_class / B+C: logistic delta 0.0081, RF delta -0.0037, single AUC 0.592, L1 selected=1, drop candidate=1, note=near-zero loss in both logistic and RF
- material_class / B: logistic delta NaN, RF delta NaN, single AUC NaN, L1 selected=0, drop candidate=0, note=minority class too small
- material_class / C: logistic delta 0.0062, RF delta -0.0039, single AUC 0.674, L1 selected=0, drop candidate=1, note=near-zero loss in both logistic and RF
- material_class / B+C: logistic delta 0.0105, RF delta -0.0065, single AUC 0.729, L1 selected=1, drop candidate=0, note=near-zero RF loss only

## Two-RX gamma_CP Diversity
- B: Pearson -0.614, Spearman -0.676, opposite-sign fraction 0.84 (n=56)
- C: Pearson -0.372, Spearman -0.402, opposite-sign fraction 0.70 (n=56)
- B+C: Pearson -0.445, Spearman -0.498, opposite-sign fraction 0.71 (n=112)