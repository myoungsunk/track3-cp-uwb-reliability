# CP7 Follow-up Checks

## L1 follow-up
- Geometric / B: L1 AUC 0.826 vs best single-feature 0.801 (gain 0.024), non-zero=4, selected={gamma_CP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2}
- Geometric / C: L1 AUC 0.834 vs best single-feature 0.844 (gain -0.010), non-zero=4, selected={gamma_CP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2}
- Geometric / B+C: L1 AUC 0.840 vs best single-feature 0.802 (gain 0.038), non-zero=5, selected={gamma_CP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2, fp_idx_diff_rx12}
- Material / C: L1 AUC 0.756 vs best single-feature 0.864 (gain -0.108), non-zero=6, selected={gamma_CP_rx1, gamma_CP_rx2, a_FP_RHCP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2}
- Material / B+C: L1 AUC 0.878 vs best single-feature 0.850 (gain 0.028), non-zero=5, selected={gamma_CP_rx1, gamma_CP_rx2, a_FP_RHCP_rx1, a_FP_RHCP_rx2, fp_idx_diff_rx12}
- Material / B: skipped_minority_scope

## Key Collinearity Pairs
- B | a_FP_RHCP_rx1 <-> a_FP_LHCP_rx1: Pearson 0.431, Spearman 0.398
- B | gamma_CP_rx1 <-> gamma_CP_rx2: Pearson -0.614, Spearman -0.676
- C | a_FP_RHCP_rx1 <-> a_FP_LHCP_rx1: Pearson 0.580, Spearman 0.582
- C | gamma_CP_rx1 <-> gamma_CP_rx2: Pearson -0.372, Spearman -0.402
- B+C | a_FP_RHCP_rx1 <-> a_FP_LHCP_rx1: Pearson 0.531, Spearman 0.536
- B+C | gamma_CP_rx1 <-> gamma_CP_rx2: Pearson -0.445, Spearman -0.498

## Material RF Importance
- Material / C: top=a_FP_LHCP_rx1 (0.717), second=gamma_CP_rx1 (0.693)
- Material / B+C: top=a_FP_RHCP_rx1 (0.860), second=gamma_CP_rx1 (0.616)

## Winner Margin
- Geometric / B: margin mean/median = 0.122 / 0.111, stable mean/median = 0.182 / 0.185, share<0.05(all/stable)=0.26 / 0.12
- Geometric / C: margin mean/median = 0.104 / 0.105, stable mean/median = 0.080 / 0.057, share<0.05(all/stable)=0.30 / 0.42
- Geometric / B+C: margin mean/median = 0.058 / 0.049, stable mean/median = 0.054 / 0.049, share<0.05(all/stable)=0.54 / 0.51
- Material / C: margin mean/median = 0.062 / 0.056, stable mean/median = 0.058 / 0.056, share<0.05(all/stable)=0.43 / 0.42
- Material / B+C: margin mean/median = 0.061 / 0.044, stable mean/median = 0.050 / 0.044, share<0.05(all/stable)=0.54 / 0.58

## fp_idx_diff Material Local Rank
- Material / C: winner=7, runner-up=7, stable winner=0, stable runner-up=0, gap mean/median=0.185 / 0.236, footprint=x=[0.75, 2.25], y=[-1.75, 1.75], n=14
- Material / B+C: winner=13, runner-up=6, stable winner=0, stable runner-up=1, gap mean/median=0.135 / 0.140, footprint=x=[0.75, 3.75], y=[-1.75, 1.75], n=19