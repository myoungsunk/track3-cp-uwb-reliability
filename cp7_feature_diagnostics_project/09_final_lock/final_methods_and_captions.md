# Final Figure Drafts (CP6 Lock)

## Methods (fixed wording)
- RHCP transmission, dual-CP reception.
- Final model feature set is locked to 6 CP features: gamma_CP_rx1, gamma_CP_rx2, a_FP_RHCP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2.
- fp_idx_diff_rx12 is removed from the final model feature set.

## Figure Captions
- (a) Winner map (geometric, B+C): local winning feature across space under RHCP transmission, dual-CP reception. Caveat: the combined B+C scope is noisier than single-scenario maps B or C. (`D:\OneDrive - postech.ac.kr\명선\2026\2. ISAC\track3-cp-uwb-reliability\cp7_feature_diagnostics_project\09_final_lock\figA_winner_map_geometric_bc.png`)
- (b) Two-RX diversity: z(gamma_CP_rx1) vs z(gamma_CP_rx2) for B, C, and B+C under RHCP transmission, dual-CP reception, showing complementary behavior by scope. (`D:\OneDrive - postech.ac.kr\명선\2026\2. ISAC\track3-cp-uwb-reliability\cp7_feature_diagnostics_project\09_final_lock\figB_two_rx_diversity.png`)
- (c) Class-conditional violin (7->6 feature lock): LoS/NLoS distributions for the retained 6 features under RHCP transmission, dual-CP reception. (`D:\OneDrive - postech.ac.kr\명선\2026\2. ISAC\track3-cp-uwb-reliability\cp7_feature_diagnostics_project\09_final_lock\figC_class_conditional_violin_7to6.png`)

## Numeric Notes
- Diversity B: Pearson -0.614, Spearman -0.676, opposite-sign fraction 0.84 (n=56)
- Diversity C: Pearson -0.372, Spearman -0.402, opposite-sign fraction 0.70 (n=56)
- Diversity B+C: Pearson -0.445, Spearman -0.498, opposite-sign fraction 0.71 (n=112)
- Violin median gaps (LoS - NLoS):
  gamma_CP_rx1: 0.2485
  gamma_CP_rx2: -0.2011
  a_FP_RHCP_rx1: 0.0434
  a_FP_LHCP_rx1: 0.0835
  a_FP_RHCP_rx2: 0.0534
  a_FP_LHCP_rx2: 0.1307