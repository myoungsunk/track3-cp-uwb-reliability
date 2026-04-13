function test_run_cp7_reviewer_diagnostics_smoke
% TEST_RUN_CP7_REVIEWER_DIAGNOSTICS_SMOKE Validate reviewer bootstrap CI fields.
test_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(test_dir);
addpath(fullfile(project_root, 'los_nlos_baseline_project'));

run_dir = fullfile(project_root, 'results', sprintf('tmp_cp7_reviewer_%d', randi(1e6)));
cfg = struct();
cfg.metric_bootstrap_repeats = 10;
cfg.results_dir = run_dir;

outputs = run_cp7_reviewer_diagnostics(cfg);

assert(istable(outputs.incremental_summary) && ~isempty(outputs.incremental_summary), 'Incremental summary missing.');
required_vars = {'n_boot_valid', 'baseline_auc_ci_low', 'baseline_auc_ci_high', 'delta_auc_ci_low', 'delta_auc_ci_high'};
assert(all(ismember(required_vars, outputs.incremental_summary.Properties.VariableNames)), ...
    'Reviewer CI columns missing.');

fprintf('test_run_cp7_reviewer_diagnostics_smoke passed.\n');
end
