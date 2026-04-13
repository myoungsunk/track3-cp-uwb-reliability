# Geometric Coefficient Sign Stability Check

## Purpose

- Check whether the full-fit proposed logistic coefficients keep the same sign across scenario B, scenario C, and pooled B+C.
- Provide a compact supplement table that makes feature-level reliability explicit.

## CP7 Summary

- CP7 features with fully consistent sign across `B`, `C`, and `B+C`: `a_FP_LHCP_rx1, a_FP_LHCP_rx2, a_FP_RHCP_rx1, gamma_CP_rx1, gamma_CP_rx2`.
- `a_FP_RHCP_rx2` is sign-unstable: `B=-0.8287 (negative)`, `C=1.0282 (positive)`, `B+C=0.0893 (positive)`.

## Interpretation

- The main CP7 pattern is sign-stable for `gamma_CP_rx1`, `gamma_CP_rx2`, `a_FP_RHCP_rx1`, `a_FP_LHCP_rx1`, and `a_FP_LHCP_rx2`.
- `a_FP_RHCP_rx2` is the only CP7 feature that flips sign between `B` and `C`, and its pooled B+C coefficient is near zero.
- This supports keeping RHCP-specific interpretation out of the main claim and treating it as a weaker, less stable auxiliary signal.