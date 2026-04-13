function test_cp7_local_knn_auc
% TEST_CP7_LOCAL_KNN_AUC Validate KNN local AUC and single-class NaN behavior.
project_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(project_root, 'src'));

coords = [
    0.0, 0.0;
    0.0, 0.1;
    0.1, 0.0;
    5.0, 5.0;
    5.0, 5.1;
    5.1, 5.0];
scores = [0.90; 0.85; 0.20; 0.10; 0.12; 0.08];
labels = [1; 1; 0; 0; 0; 0];

params = struct();
params.local_k = 3;
params.local_warn_min_class = 2;
local_table = cp7_local_knn_auc(coords, scores, labels, params);

assert(height(local_table) == 6, 'Local output row count mismatch.');
assert(local_table.n_local(1) == 3, 'First point should use 3 neighbors.');
assert(local_table.min_class_local(1) == 1, 'Mixed neighborhood should have minority count 1.');
assert(isfinite(local_table.local_effective_auc(1)), 'Mixed neighborhood should produce finite local AUC.');
assert(local_table.unstable_flag(1), 'Minority count below warning threshold should be flagged unstable.');

assert(local_table.n_local(6) == 3, 'Last point should also use 3 neighbors.');
assert(local_table.min_class_local(6) == 0, 'Single-class neighborhood should have minority count 0.');
assert(isnan(local_table.local_raw_auc(6)), 'Single-class neighborhood raw AUC should be NaN.');
assert(isnan(local_table.local_effective_auc(6)), 'Single-class neighborhood effective AUC should be NaN.');

fprintf('test_cp7_local_knn_auc passed.\n');
end
