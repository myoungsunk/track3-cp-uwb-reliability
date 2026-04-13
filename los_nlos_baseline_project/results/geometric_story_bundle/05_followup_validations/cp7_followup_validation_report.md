# CP7 Follow-up Validation Report

## Validation 4: Single-RX vs Dual-RX

| Target | Scope | Model | AUC | Brier | Accuracy |
|---|---|---|---:|---:|---:|
| geometric | B | baseline_plus_rx1 | 0.8898 | 0.1301 | 0.8393 |
| geometric | B | baseline_plus_rx2 | 0.9007 | 0.1235 | 0.8393 |
| geometric | B | baseline_plus_dual | 0.8952 | 0.1226 | 0.8571 |
| geometric | C | baseline_plus_rx1 | 0.8272 | 0.1655 | 0.7857 |
| geometric | C | baseline_plus_rx2 | 0.8762 | 0.1384 | 0.8036 |
| geometric | C | baseline_plus_dual | 0.8912 | 0.1268 | 0.8214 |
| geometric | B+C | baseline_plus_rx1 | 0.9005 | 0.1261 | 0.8304 |
| geometric | B+C | baseline_plus_rx2 | 0.8992 | 0.1218 | 0.8214 |
| geometric | B+C | baseline_plus_dual | 0.9139 | 0.1126 | 0.8482 |

### Dual-RX Gain vs Best Single-RX

| Target | Scope | Delta AUC | 95% CI | p(dual <= best) |
|---|---|---:|---|---:|
| geometric | B | -0.0054 | [-0.0293, 0.0338] | 0.4750 |
| geometric | C | 0.0150 | [-0.0271, 0.0583] | 0.3470 |
| geometric | B+C | 0.0134 | [-0.0096, 0.0276] | 0.2370 |

## Validation 5: Mechanism Subgroups

| Target | Subset | Feature | n(L/N) | AUC | 95% CI | Status |
|---|---|---|---|---:|---|---|
| geometric | geom_B_metal_single_bounce | a_FP_LHCP_rx1 | 35/1 | 0.7714 | [0.6286, 0.9143] | underpowered |
| geometric | geom_B_metal_single_bounce | a_FP_LHCP_rx2 | 35/1 | 0.3143 | [0.1714, 0.4706] | underpowered |
| geometric | geom_B_metal_single_bounce | gamma_CP_rx1 | 35/1 | 0.8857 | [0.7714, 0.9714] | underpowered |
| geometric | geom_B_metal_single_bounce | gamma_CP_rx2 | 35/1 | 0.5714 | [0.4000, 0.7429] | underpowered |
| geometric | geom_B_glass_partition | a_FP_LHCP_rx1 | 35/20 | 0.8029 | [0.6759, 0.9037] | ok |
| geometric | geom_B_glass_partition | a_FP_LHCP_rx2 | 35/20 | 0.8057 | [0.6771, 0.9112] | ok |
| geometric | geom_B_glass_partition | gamma_CP_rx1 | 35/20 | 0.6200 | [0.4624, 0.7575] | ok |
| geometric | geom_B_glass_partition | gamma_CP_rx2 | 35/20 | 0.4100 | [0.2496, 0.5778] | ok |
| geometric | geom_C_dense_clutter_all | a_FP_LHCP_rx1 | 21/35 | 0.7714 | [0.6308, 0.8852] | ok |
| geometric | geom_C_dense_clutter_all | a_FP_LHCP_rx2 | 21/35 | 0.8435 | [0.7093, 0.9418] | ok |
| geometric | geom_C_dense_clutter_all | gamma_CP_rx1 | 21/35 | 0.7102 | [0.5677, 0.8449] | ok |
| geometric | geom_C_dense_clutter_all | gamma_CP_rx2 | 21/35 | 0.3741 | [0.2116, 0.5488] | ok |
