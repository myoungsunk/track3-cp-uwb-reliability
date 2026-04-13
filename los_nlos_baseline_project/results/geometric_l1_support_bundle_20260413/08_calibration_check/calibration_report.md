# Geometric Calibration Check

## Purpose

- Visualize the reliability of the B+C OOF probabilities for the paired baseline and proposed models.
- Quantify calibration with the same 5-bin uniform ECE setting that was referenced in the review report.

## Summary

- Baseline: ECE `0.0427`, Brier `0.1556`.
- Proposed: ECE `0.0409`, Brier `0.1126`.

## Notes

- The proposed model shows a slightly lower 5-bin ECE and a markedly lower Brier score.
- The mid-confidence bin `[0.4, 0.6]` remains imperfect: baseline gap `-0.0942`, proposed gap `0.1693`.
- This supports using calibration as a secondary robustness note rather than as the main claim.

## Files

- `calibration_plot.png`: reliability diagram and score histogram
- `calibration_plot.pdf`: vector-friendly export
- `calibration_summary.csv`: ECE and Brier summary
- `calibration_curve_points.csv`: bin-level mean prediction, observed frequency, and gap