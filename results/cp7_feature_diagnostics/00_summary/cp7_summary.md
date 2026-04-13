# CP7 Feature Diagnostics Summary

## geometric_class / B
- Samples: total=56, joint-valid=56, LoS=35, NLoS=21
- Best global feature: a_FP_LHCP_rx1 (effective AUC 0.8014)
- Dominant local winner: a_FP_LHCP_rx1 (fraction 0.286)
- L1 AUC: 0.8259, L1+XY AUC: 0.8660, delta: 0.0401, RF CV AUC: 0.7986

## geometric_class / C
- Samples: total=56, joint-valid=56, LoS=21, NLoS=35
- Best global feature: a_FP_LHCP_rx2 (effective AUC 0.8435)
- Dominant local winner: a_FP_LHCP_rx2 (fraction 0.464)
- L1 AUC: 0.8340, L1+XY AUC: 0.8490, delta: 0.0150, RF CV AUC: 0.7673

## geometric_class / B+C
- Samples: total=112, joint-valid=112, LoS=56, NLoS=56
- Best global feature: a_FP_LHCP_rx2 (effective AUC 0.8017)
- Dominant local winner: gamma_CP_rx1 (fraction 0.286)
- L1 AUC: 0.8396, L1+XY AUC: 0.8482, delta: 0.0086, RF CV AUC: 0.8195

## material_class / B
- Samples: total=56, joint-valid=56, LoS=55, NLoS=1
- Best global feature: a_FP_RHCP_rx1 (effective AUC 0.9818)
- Dominant local winner: a_FP_RHCP_rx1 (fraction 0.733)
- L1 AUC: NaN, L1+XY AUC: NaN, delta: NaN, RF CV AUC: NaN

## material_class / C
- Samples: total=56, joint-valid=56, LoS=40, NLoS=16
- Best global feature: a_FP_RHCP_rx2 (effective AUC 0.8641)
- Dominant local winner: a_FP_RHCP_rx2 (fraction 0.696)
- L1 AUC: 0.7563, L1+XY AUC: 0.8047, delta: 0.0484, RF CV AUC: 0.8516

## material_class / B+C
- Samples: total=112, joint-valid=112, LoS=95, NLoS=17
- Best global feature: a_FP_RHCP_rx1 (effective AUC 0.8502)
- Dominant local winner: a_FP_RHCP_rx1 (fraction 0.357)
- L1 AUC: 0.8780, L1+XY AUC: 0.8755, delta: -0.0025, RF CV AUC: 0.8932
