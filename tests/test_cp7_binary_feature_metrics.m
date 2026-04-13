function test_cp7_binary_feature_metrics
% TEST_CP7_BINARY_FEATURE_METRICS Validate raw/effective AUC and direction logic.
project_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(project_root, 'src'));

scores_pos = [0.95; 0.85; 0.75; 0.20; 0.15; 0.05];
labels = [1; 1; 1; 0; 0; 0];
metrics_pos = cp7_binary_feature_metrics(scores_pos, labels, struct('mi_num_bins', 4));
assert(metrics_pos.auc_raw > 0.99, 'Raw AUC should be near-perfect for aligned scores.');
assert(abs(metrics_pos.auc_effective - metrics_pos.auc_raw) < 1e-12, 'Effective AUC should match raw AUC when raw >= 0.5.');
assert(metrics_pos.direction == "higher->LoS", 'Direction should indicate higher values imply LoS.');

scores_neg = -scores_pos;
metrics_neg = cp7_binary_feature_metrics(scores_neg, labels, struct('mi_num_bins', 4));
assert(metrics_neg.auc_raw < 0.01, 'Raw AUC should invert for reversed scores.');
assert(metrics_neg.auc_effective > 0.99, 'Effective AUC should stay near-perfect after inversion.');
assert(metrics_neg.direction == "higher->NLoS", 'Direction should indicate higher values imply NLoS.');

fprintf('test_cp7_binary_feature_metrics passed.\n');
end
