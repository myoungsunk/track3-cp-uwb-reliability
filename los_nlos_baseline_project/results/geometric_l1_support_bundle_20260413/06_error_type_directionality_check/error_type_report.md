# Geometric Error-Type Directionality Check

## Purpose

- Quantify whether CP7 reduces false positives and false negatives symmetrically or preferentially.
- Provide a discussion-ready statement about whether CP7 more often corrects LoS samples that were misread as NLoS.

## Overall Results

- Baseline FP: `14` -> Proposed FP: `10` (`-4` change).
- Baseline FN: `12` -> Proposed FN: `7` (`-5` change).
- Rescued samples: `12` total = `8` from baseline FN + `4` from baseline FP.
- Harmed samples: `3` total = `3` proposed FN + `0` proposed FP.
- Rescue rate among baseline FN: `0.6667`; rescue rate among baseline FP: `0.2857`.

## Interpretation

- CP7 reduces both error types, but the larger directional effect is on baseline FN.
- In this label convention, baseline FN corresponds to LoS samples that the baseline misread as NLoS.
- The rescued set therefore supports the observed tendency that CP7 more often restores LoS samples than NLoS samples.
- This should be framed as an observed tendency or discussion-level interpretation, not as a mechanism proof.

## Files

- `error_type_summary.csv`: overall, per-scenario, and hard-case counts and rates
- `error_type_event_samples.csv`: rescued and harmed samples with explicit error-type labels