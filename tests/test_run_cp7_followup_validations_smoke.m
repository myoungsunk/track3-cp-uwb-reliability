function test_run_cp7_followup_validations_smoke
% TEST_RUN_CP7_FOLLOWUP_VALIDATIONS_SMOKE Validate bootstrap-refit and mechanism CI outputs.
test_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(test_dir);
addpath(fullfile(project_root, 'los_nlos_baseline_project'));

run_dir = fullfile(project_root, 'results', sprintf('tmp_cp7_followup_%d', randi(1e6)));
cfg = struct();
cfg.bootstrap_repeats = 3;
cfg.mechanism_bootstrap_repeats = 10;
cfg.results_dir = run_dir;

outputs = run_cp7_followup_validations(cfg);

assert(istable(outputs.bootstrap_summary) && ~isempty(outputs.bootstrap_summary), 'Bootstrap summary missing.');
assert(all(ismember({'ci_low', 'ci_high', 'p_dual_le_best'}, outputs.bootstrap_summary.Properties.VariableNames)), ...
    'Bootstrap summary CI columns missing.');
assert(istable(outputs.mechanism_summary) && ~isempty(outputs.mechanism_summary), 'Mechanism summary missing.');
assert(all(ismember({'auc_ci_low', 'auc_ci_high', 'n_boot_valid'}, outputs.mechanism_summary.Properties.VariableNames)), ...
    'Mechanism CI columns missing.');

fprintf('test_run_cp7_followup_validations_smoke passed.\n');
end
