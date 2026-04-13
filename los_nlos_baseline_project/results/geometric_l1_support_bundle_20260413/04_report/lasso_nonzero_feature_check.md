# Lasso Non-Zero Feature Check

## Purpose

- Confirm that the proposed logistic model still retains the key CP7 features under L1-regularized logistic regression.
- Address the reviewer question that the 112-sample B+C subset may be overfit when 6 CP7 features are added.

## Setup

- Dataset: CP7-capable `B+C` subset (`n=112`, LoS=`56`, NLoS=`56`)
- Model family: logistic regression with L1 regularization (`lassoglm`)
- Outer CV: stratified 5-fold with seed `42`
- Normalization: train-fold mean/std applied to held-out fold
- Selection rule: report both full-fit non-zero coefficients and fold-wise selection frequency

## L1 Performance Snapshot

- Baseline 5-feature L1: AUC `0.8444`, accuracy `0.7679`, Brier `0.1586`
- Proposed 11-feature L1: AUC `0.8763`, accuracy `0.8393`, Brier `0.1369`

## Key CP7 Features

| Feature | Full-fit non-zero | Selection frequency | Coefficient |
| --- | --- | --- | --- |
| `gamma_CP_rx1` | Yes | `0.80` | `+0.5146` |
| `gamma_CP_rx2` | Yes | `1.00` | `-1.2601` |
| `a_FP_LHCP_rx1` | Yes | `1.00` | `+1.2038` |
| `a_FP_LHCP_rx2` | Yes | `0.80` | `+0.0175` |

## Conclusion

- All four target CP7 features remain non-zero in the full-fit L1 logistic model.
- `gamma_CP_rx2` and `a_FP_LHCP_rx1` are retained in every fold.
- `gamma_CP_rx1` and `a_FP_LHCP_rx2` are retained in `80%` of folds.
- This supports the claim that the main CP7 signal is not removed by sparse logistic regularization.
