# Geometric LOSO Generalization Check

## Purpose

- Evaluate whether CP7 gains remain when the model is trained on one scenario and tested on the other scenario.
- Store the independent LOSO validation that was referenced in the review reports.

## Setup

- Dataset: CP7-capable B+C subset
- Model: sklearn logistic regression with L2 regularization
- Class weight: `balanced`
- Normalization: fit on the training scenario only, then applied to the held-out scenario
- Inverse regularization strength C: `100.0`

## Results

- `B_to_C`: baseline AUC `0.7578`, proposed AUC `0.8299`, delta AUC `0.0721`, baseline accuracy `0.7143`, proposed accuracy `0.7321`, exact McNemar p `1.0000`.
- `C_to_B`: baseline AUC `0.8327`, proposed AUC `0.8735`, delta AUC `0.0408`, baseline accuracy `0.7143`, proposed accuracy `0.8214`, exact McNemar p `0.2632`.

## Interpretation

- Both directions improve, which supports the claim that CP7 information is not confined to one scenario.
- These numbers are best used in a robustness subsection rather than as the primary headline result.