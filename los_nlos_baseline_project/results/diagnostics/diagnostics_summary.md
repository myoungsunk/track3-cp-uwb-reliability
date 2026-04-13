# Feature Diagnostics Summary

## Shared Correlation

Samples used: 336

| Source | Target | Pearson r | Spearman rho |
|---|---|---:|---:|
| a_FP | fp_energy_db | 0.6689 | 0.6828 |
| a_FP | kurtosis_pdp | 0.0223 | 0.4727 |
| a_FP | skewness_pdp | 0.3408 | 0.5546 |
| r_CP | fp_energy_db | -0.0095 | -0.1918 |
| r_CP | kurtosis_pdp | -0.0151 | -0.0582 |
| r_CP | skewness_pdp | 0.0271 | -0.0218 |

## Incremental Gain

| Target | Subset | Baseline AUC | Proposed AUC | Delta AUC | Baseline Brier | Proposed Brier | Delta Brier |
|---|---|---:|---:|---:|---:|---:|---:|
| material | overall | 0.9098 | 0.8980 | -0.0118 | 0.1250 | 0.1209 | -0.0041 |
| material | hard_case_0p4_0p6 | 0.7440 | 0.7600 | 0.0160 | 0.2242 | 0.2193 | -0.0049 |
| geometric | overall | 0.7640 | 0.7663 | 0.0024 | 0.1983 | 0.1972 | -0.0012 |
| geometric | hard_case_0p4_0p6 | 0.3916 | 0.3469 | -0.0448 | 0.2675 | 0.2761 | 0.0086 |

## Scenario B Notes

### material

```
Scenario B focus note
Target: material
Scenario B objects: 3 (glass, metal, wood)
Scenario C objects: 8 (glass, metal, wood)
CP_caseB r_CP AUC=1.000 with n_los=55, n_nlos=1.
CP_caseC r_CP AUC=0.508 with n_los=40, n_nlos=16.
Scenario B label split from export CSV: geometric NLoS=42, material NLoS=2.
Material NLoS in Scenario B is sparse: first NLoS sample is (5.250, -1.750), tag=T49, hits=metal_cabinet_1, materials=metal, criterion=hard_block_material.
Geometric NLoS in Scenario B is mostly driven by: glass, metal.
Interpretation: the perfect CP_caseB r_CP score is driven by a tiny hard-block regime, not a broad class split.
Scenario B has one metal-cabinet path that flips the material label to NLoS, while most other blocked links are thin-glass geometric NLoS but material LoS.
This supports a regime-selective diagnostic view: r_CP is informative when a specular, hard-block interaction dominates, but it collapses in dense clutter (Scenario C).
```

### geometric

```
Scenario B focus note
Target: geometric
Scenario B objects: 3 (glass, metal, wood)
Scenario C objects: 8 (glass, metal, wood)
CP_caseB r_CP AUC=0.535 with n_los=35, n_nlos=21.
CP_caseC r_CP AUC=0.509 with n_los=21, n_nlos=35.
Scenario B label split from export CSV: geometric NLoS=42, material NLoS=2.
Material NLoS in Scenario B is sparse: first NLoS sample is (5.250, -1.750), tag=T49, hits=metal_cabinet_1, materials=metal, criterion=hard_block_material.
Geometric NLoS in Scenario B is mostly driven by: glass, metal.
Interpretation: under geometric labels, Scenario B includes many glass-partition NLoS links, so r_CP no longer tracks the label as a clean binary cue.
This is consistent with parity information being partially preserved only in specific reflection/blockage regimes rather than all geometric obstructions.
```

