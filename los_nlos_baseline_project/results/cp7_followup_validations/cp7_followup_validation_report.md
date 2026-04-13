# CP7 Follow-up Validation Report

## Validation 4: Single-RX vs Dual-RX

| Target | Scope | Model | AUC | Brier | Accuracy |
|---|---|---|---:|---:|---:|
| material | B | baseline_plus_rx1 | NaN | NaN | NaN |
| material | B | baseline_plus_rx2 | NaN | NaN | NaN |
| material | B | baseline_plus_dual | NaN | NaN | NaN |
| material | C | baseline_plus_rx1 | 0.9156 | 0.1121 | 0.8393 |
| material | C | baseline_plus_rx2 | 0.9234 | 0.1100 | 0.8393 |
| material | C | baseline_plus_dual | 0.9141 | 0.1147 | 0.8393 |
| material | B+C | baseline_plus_rx1 | 0.9474 | 0.0808 | 0.8929 |
| material | B+C | baseline_plus_rx2 | 0.9455 | 0.0864 | 0.9018 |
| material | B+C | baseline_plus_dual | 0.9418 | 0.0841 | 0.8839 |
| geometric | B | baseline_plus_rx1 | 0.9075 | 0.1274 | 0.8214 |
| geometric | B | baseline_plus_rx2 | 0.9129 | 0.1166 | 0.8393 |
| geometric | B | baseline_plus_dual | 0.9102 | 0.1200 | 0.8036 |
| geometric | C | baseline_plus_rx1 | 0.8299 | 0.1730 | 0.7321 |
| geometric | C | baseline_plus_rx2 | 0.8422 | 0.1535 | 0.8036 |
| geometric | C | baseline_plus_dual | 0.8558 | 0.1421 | 0.8571 |
| geometric | B+C | baseline_plus_rx1 | 0.8919 | 0.1323 | 0.8214 |
| geometric | B+C | baseline_plus_rx2 | 0.8951 | 0.1266 | 0.8036 |
| geometric | B+C | baseline_plus_dual | 0.9050 | 0.1232 | 0.8214 |

### Dual-RX Gain vs Best Single-RX

| Target | Scope | Delta AUC | 95% CI | p(dual <= best) |
|---|---|---:|---|---:|
| material | B | NaN | [NaN, NaN] | NaN |
| material | C | -0.0094 | [-0.0416, 0.0082] | 0.8780 |
| material | B+C | -0.0056 | [-0.0304, 0.0047] | 0.9080 |
| geometric | B | -0.0027 | [-0.0709, 0.0231] | 0.7800 |
| geometric | C | 0.0136 | [-0.0714, 0.0512] | 0.4970 |
| geometric | B+C | 0.0099 | [-0.0246, 0.0229] | 0.3850 |

## Validation 5: Mechanism Subgroups

| Target | Subset | Feature | n(L/N) | AUC | Status |
|---|---|---|---|---:|---|
| material | mat_BC_hardblock_metal | a_FP_RHCP_rx1 | 95/15 | 0.8772 | ok |
| material | mat_BC_hardblock_metal | a_FP_RHCP_rx2 | 95/15 | 0.7972 | ok |
| material | mat_BC_hardblock_metal | gamma_CP_rx1 | 95/15 | 0.8175 | ok |
| material | mat_BC_hardblock_metal | gamma_CP_rx2 | 95/15 | 0.6246 | ok |
| material | mat_C_softblock_wood | a_FP_RHCP_rx1 | 95/2 | 0.6474 | underpowered |
| material | mat_C_softblock_wood | a_FP_RHCP_rx2 | 95/2 | 0.9842 | underpowered |
| material | mat_C_softblock_wood | gamma_CP_rx1 | 95/2 | 0.5000 | underpowered |
| material | mat_C_softblock_wood | gamma_CP_rx2 | 95/2 | 0.7579 | underpowered |
| material | mat_C_all | a_FP_RHCP_rx1 | 40/16 | 0.8063 | ok |
| material | mat_C_all | a_FP_RHCP_rx2 | 40/16 | 0.8641 | ok |
| material | mat_C_all | gamma_CP_rx1 | 40/16 | 0.7703 | ok |
| material | mat_C_all | gamma_CP_rx2 | 40/16 | 0.5828 | ok |
| geometric | geom_B_metal_single_bounce | a_FP_LHCP_rx1 | 35/1 | 0.7714 | underpowered |
| geometric | geom_B_metal_single_bounce | a_FP_LHCP_rx2 | 35/1 | 0.3143 | underpowered |
| geometric | geom_B_metal_single_bounce | gamma_CP_rx1 | 35/1 | 0.8857 | underpowered |
| geometric | geom_B_metal_single_bounce | gamma_CP_rx2 | 35/1 | 0.5714 | underpowered |
| geometric | geom_B_glass_partition | a_FP_LHCP_rx1 | 35/20 | 0.8029 | ok |
| geometric | geom_B_glass_partition | a_FP_LHCP_rx2 | 35/20 | 0.8057 | ok |
| geometric | geom_B_glass_partition | gamma_CP_rx1 | 35/20 | 0.6200 | ok |
| geometric | geom_B_glass_partition | gamma_CP_rx2 | 35/20 | 0.4100 | ok |
| geometric | geom_C_dense_clutter_all | a_FP_LHCP_rx1 | 21/35 | 0.7714 | ok |
| geometric | geom_C_dense_clutter_all | a_FP_LHCP_rx2 | 21/35 | 0.8435 | ok |
| geometric | geom_C_dense_clutter_all | gamma_CP_rx1 | 21/35 | 0.7102 | ok |
| geometric | geom_C_dense_clutter_all | gamma_CP_rx2 | 21/35 | 0.3741 | ok |
