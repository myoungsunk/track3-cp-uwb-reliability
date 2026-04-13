# Individual Evaluation of 7 CP7 Features

This note summarizes the current investigation results on how each of the 7 features relates to the two classification criteria:

- `geometric_class`
- `material_class`

Main interpretation rule:

- `single-feature effective AUC` measures standalone discriminative power
- `L1 coefficient / selected` shows whether the feature survives in a multivariate linear model
- `RF permutation importance` shows whether the feature still matters in a nonlinear ensemble
- `local winner / diversity / drop ablation` indicate whether the feature is globally stable, locally conditional, or mainly complementary

`material_class / B` is excluded from interpretation because the minority class is too small.

## 1. `gamma_CP_rx1`

### Geometric
- `B+C` effective AUC: `0.675`
- Direction: `higher -> LoS`
- L1: selected, coefficient `+0.571`

Interpretation:
- not the best standalone geometric feature
- still useful in multivariate geometric models
- becomes more important locally than globally, consistent with the winner-map behavior

### Material
- `B+C` effective AUC: `0.780`
- L1: selected, coefficient `+0.079`
- RF importance (`B+C`): `0.616`

Interpretation:
- a strong complementary material feature
- contributes to nonlinear material models more than its small linear coefficient suggests

## 2. `gamma_CP_rx2`

### Geometric
- `B+C` effective AUC: `0.584`
- Direction: `higher -> NLoS`
- L1: not selected

Interpretation:
- weak standalone geometric discriminator
- not retained by the geometric L1 model

### Material
- `B+C` effective AUC: `0.640`
- Direction: `higher -> LoS`
- L1: selected, coefficient `+0.059`
- RF importance (`B+C`): `0.449`

Interpretation:
- the most interesting "weak alone, useful in combination" feature
- likely carries complementary information that is not well expressed by a simple linear term
- RF 2D partial dependence with `a_FP_RHCP_rx1` shows non-additive behavior, but adding a simple product term to logistic regression does not improve AUC

Conclusion:
- keep as a complementary feature
- do not justify a simple `gamma_CP * a_FP` interaction term yet

## 3. `a_FP_RHCP_rx1`

### Geometric
- `B+C` effective AUC: `0.712`
- L1: not selected

Interpretation:
- reasonably strong alone
- but largely redundant once the stronger LHCP-based `a_FP` terms are included

### Material
- `B+C` effective AUC: `0.850`
- L1: selected, coefficient `+0.713`
- RF importance (`B+C`): `0.860`

Interpretation:
- the strongest material discriminator in the combined scope
- both linear and nonlinear models agree that it is a core feature

Conclusion:
- one of the main anchors for any material-based classifier

## 4. `a_FP_LHCP_rx1`

### Geometric
- `B+C` effective AUC: `0.788`
- L1: selected, coefficient `+0.781`

Interpretation:
- one of the strongest geometric features
- survives multivariate selection with a large coefficient

### Material
- `B+C` effective AUC: `0.757`
- L1: not selected
- RF importance (`B+C`): `0.387`
- RF importance (`C`): `0.717`

Interpretation:
- useful in material classification, especially in scenario `C`
- but not stable enough across `B+C` to survive L1 selection

Conclusion:
- strong geometric feature
- scenario-dependent material feature

## 5. `a_FP_RHCP_rx2`

### Geometric
- `B+C` effective AUC: `0.694`
- L1: selected, coefficient `+0.042`

Interpretation:
- moderate geometric feature
- selected, but with small linear weight

### Material
- `B+C` effective AUC: `0.819`
- L1: selected, coefficient `+0.480`
- RF importance (`B+C`): `0.478`
- `C` standalone AUC: `0.864`

Interpretation:
- consistently strong material feature
- especially dominant in scenario `C`

Conclusion:
- important material feature
- secondary but not dominant in geometric classification

## 6. `a_FP_LHCP_rx2`

### Geometric
- `B+C` effective AUC: `0.802`
- L1: selected, coefficient `+0.813`
- RF importance (`B+C`, geometric refit): strongest among geometric features

Interpretation:
- the single strongest global geometric feature
- consistently favored by both standalone ranking and multivariate selection

### Material
- `B+C` effective AUC: `0.680`
- L1: not selected
- RF importance (`B+C`): `0.221`

Interpretation:
- not a core material feature

Conclusion:
- best global geometric anchor
- weak-to-moderate material relevance only

## 7. `fp_idx_diff_rx12`

### Geometric
- `B+C` effective AUC: `0.592`
- Direction: `higher -> NLoS`
- L1: selected, coefficient `-0.232`
- 7 -> 6 feature ablation:
  - logistic delta: `+0.008`
  - RF delta: `-0.004`

Interpretation:
- not a strong standalone geometric feature
- can help as a complementary cue
- but removing it causes almost no loss in `B+C`

### Material
- `B+C` effective AUC: `0.729`
- Direction: `higher -> NLoS`
- L1: selected, coefficient `-0.128`
- RF importance (`B+C`): `0.198`
- 7 -> 6 feature ablation:
  - logistic delta: `+0.011`
  - RF delta: `-0.007`

Interpretation:
- globally better than in the geometric case
- still behaves more like a conditional auxiliary cue than a core feature
- local winner behavior is mostly concentrated in unstable or low-support regions

Conclusion:
- scientifically interesting as a geometry cue
- not necessary as a primary production feature
- removable for model simplification, especially in the geometric `B+C` setup

## Overall Takeaways

### Geometric criterion
- main global features: `a_FP_LHCP_rx2`, `a_FP_LHCP_rx1`
- complementary feature: `gamma_CP_rx1`
- conditional auxiliary feature: `fp_idx_diff_rx12`
- weak feature: `gamma_CP_rx2`

### Material criterion
- main global features: `a_FP_RHCP_rx1`, `a_FP_RHCP_rx2`
- complementary feature: `gamma_CP_rx1`
- nonlinear/combination-sensitive feature: `gamma_CP_rx2`
- conditional auxiliary feature: `fp_idx_diff_rx12`

### Diversity message
- `gamma_CP_rx1` and `gamma_CP_rx2` are negatively correlated:
  - `B`: Pearson `-0.614`, Spearman `-0.676`
  - `C`: Pearson `-0.372`, Spearman `-0.402`
  - `B+C`: Pearson `-0.445`, Spearman `-0.498`
- This supports the Track 3 motivation that the two RX views provide complementary information rather than redundant measurements.
