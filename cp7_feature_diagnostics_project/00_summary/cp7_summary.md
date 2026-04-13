# CP6 Feature Diagnostics Summary
- Measurement setting: RHCP transmission, dual-CP reception.
- Final lock: 6 features (fp_idx_diff_rx12 removed from model feature set).

## geometric_class / B
- Samples: total=56, joint-valid=56, LoS=35, NLoS=21
- Status: ok
- Local K: 15
- Best global feature: a_FP_LHCP_rx1 (effective AUC 0.8014)
- Dominant local winner: gamma_CP_rx1 (fraction 0.381)
- L1 AUC: 0.8082, L1+XY AUC: 0.8578, delta: 0.0497, RF CV AUC: 0.7932

## geometric_class / C
- Samples: total=56, joint-valid=56, LoS=21, NLoS=35
- Status: ok
- Local K: 15
- Best global feature: a_FP_LHCP_rx2 (effective AUC 0.8435)
- Dominant local winner: gamma_CP_rx1 (fraction 0.411)
- L1 AUC: 0.8245, L1+XY AUC: 0.8544, delta: 0.0299, RF CV AUC: 0.7517

## geometric_class / B+C
- Samples: total=112, joint-valid=112, LoS=56, NLoS=56
- Status: ok
- Local K: 30
- Best global feature: a_FP_LHCP_rx2 (effective AUC 0.8017)
- Dominant local winner: gamma_CP_rx1 (fraction 0.393)
- L1 AUC: 0.8422, L1+XY AUC: 0.8402, delta: -0.0019, RF CV AUC: 0.8208

## material_class / B
- Samples: total=56, joint-valid=56, LoS=55, NLoS=1
- Status: skipped_minority_scope
- Local K: 15
- Skip reason: minority class count 1 < 2

## material_class / C
- Samples: total=56, joint-valid=56, LoS=40, NLoS=16
- Status: ok
- Local K: 15
- Best global feature: a_FP_RHCP_rx2 (effective AUC 0.8641)
- Dominant local winner: gamma_CP_rx2 (fraction 0.321)
- L1 AUC: 0.7625, L1+XY AUC: 0.8234, delta: 0.0609, RF CV AUC: 0.8516

## material_class / B+C
- Samples: total=112, joint-valid=112, LoS=95, NLoS=17
- Status: ok
- Local K: 30
- Best global feature: a_FP_RHCP_rx1 (effective AUC 0.8502)
- Dominant local winner: a_FP_RHCP_rx1 (fraction 0.357)
- L1 AUC: 0.8805, L1+XY AUC: 0.8842, delta: 0.0037, RF CV AUC: 0.8684
