function test_run_cp7_feature_diagnostics_smoke
% TEST_RUN_CP7_FEATURE_DIAGNOSTICS_SMOKE Run focused smoke checks for CP7 diagnostics.
project_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(project_root, 'src'));

params_geo = struct();
params_geo.label_modes = {'geometric_class'};
params_geo.scopes = {'C'};
params_geo.cv_folds = 3;
params_geo.local_k = 20;
params_geo.l1_num_lambda = 10;
params_geo.rf_num_trees = 20;
run_name_geo = sprintf('tmp_cp7_diag_geo_%d', randi(1e6));
results_dir_geo = fullfile(project_root, 'results', run_name_geo);
cleanup_geo = onCleanup(@() cleanup_results_dir(results_dir_geo));

outputs_geo = run_cp7_feature_diagnostics(run_name_geo, params_geo);
assert(height(outputs_geo.summary) == 1, 'Geometric/C smoke run should produce one summary row.');
assert(isfolder(outputs_geo.stage_dirs.global), 'Global output folder missing.');
assert(isfile(fullfile(outputs_geo.stage_dirs.global, 'global_metrics_geometric_c.csv')), 'Global metrics output missing.');
assert(isfile(fullfile(outputs_geo.stage_dirs.local, 'winner_map_geometric_c.csv')), 'Winner map output missing.');
assert(isfile(fullfile(outputs_geo.stage_dirs.baselines, 'multivariate_l1_geometric_c.csv')), 'L1 baseline output missing.');

params_mat = struct();
params_mat.label_modes = {'material_class'};
params_mat.scopes = {'B'};
params_mat.cv_folds = 3;
params_mat.l1_num_lambda = 10;
params_mat.rf_num_trees = 20;
run_name_mat = sprintf('tmp_cp7_diag_mat_%d', randi(1e6));
results_dir_mat = fullfile(project_root, 'results', run_name_mat);
cleanup_mat = onCleanup(@() cleanup_results_dir(results_dir_mat));

outputs_mat = run_cp7_feature_diagnostics(run_name_mat, params_mat);
assert(height(outputs_mat.summary) == 1, 'Material/B smoke run should produce one summary row.');
assert(isfile(fullfile(outputs_mat.stage_dirs.local, 'local_grid_metrics_material_b.csv')), 'Material local grid output missing.');
assert(isfile(fullfile(outputs_mat.stage_dirs.baselines, 'univariate_logistic_material_b.csv')), 'Material univariate baseline output missing.');
assert(isfile(fullfile(outputs_mat.stage_dirs.summary, 'cp7_summary.csv')), 'Summary output missing.');
assert(outputs_mat.summary.analysis_status(1) == "skipped_minority_scope", 'Material/B should be skipped at scope level.');
assert(contains(outputs_mat.summary.skip_reason(1), "minority class count"), 'Skip reason should record minority-class cause.');
assert(outputs_mat.summary.local_k(1) == 15, 'Single-scope default local K should be 15.');

fprintf('test_run_cp7_feature_diagnostics_smoke passed.\n');
end

function cleanup_results_dir(results_dir)
if isfolder(results_dir)
    rmdir(results_dir, 's');
end
end
