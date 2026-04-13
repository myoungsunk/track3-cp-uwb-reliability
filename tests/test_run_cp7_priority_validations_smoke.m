function test_run_cp7_priority_validations_smoke
% TEST_RUN_CP7_PRIORITY_VALIDATIONS_SMOKE Validate repeated-CV summary fields.
test_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(test_dir);
addpath(fullfile(project_root, 'los_nlos_baseline_project'));

run_dir = fullfile(project_root, 'results', sprintf('tmp_cp7_priority_%d', randi(1e6)));
cfg = struct();
cfg.n_cv_repeats = 2;
cfg.permutation_repeats = 2;
cfg.spatial_cv_enabled = true;
cfg.results_dir = run_dir;

outputs = run_cp7_priority_validations(cfg);

assert(istable(outputs.ablation_summary) && ~isempty(outputs.ablation_summary), 'Ablation summary missing.');
required_vars = {'auc_ci_low', 'auc_ci_high', 'n_cv_repeats', 'n_cv_valid', 'cv_strategy'};
assert(all(ismember(required_vars, outputs.ablation_summary.Properties.VariableNames)), 'Repeated-CV summary columns missing.');

if ~isempty(outputs.spatial_cv_summary)
    assert(ismember('cv_strategy', outputs.spatial_cv_summary.Properties.VariableNames), 'Spatial CV summary missing strategy column.');
end

fprintf('test_run_cp7_priority_validations_smoke passed.\n');
end
