function test_phase2_smoke
% TEST_PHASE2_SMOKE Run smoke validation for phase-2 training/evaluation modules.
addpath('src');

rng(42);
n_sample = 80;
n_half = n_sample / 2;

r_cp_los = 10.^(0.9 + 0.15 * randn(n_half, 1));
a_fp_los = 0.72 + 0.08 * randn(n_half, 1);
r_cp_nlos = 10.^(0.2 + 0.15 * randn(n_half, 1));
a_fp_nlos = 0.38 + 0.10 * randn(n_half, 1);

features = [ [r_cp_los; r_cp_nlos], [a_fp_los; a_fp_nlos] ];
labels = [true(n_half, 1); false(n_half, 1)];

params = struct();
params.normalize = true;
params.cv_folds = 3;
params.random_seed = 42;
params.save_outputs = false;
params.svm_optimize_hyperparameters = false;
params.dnn_max_epochs = 5;
params.dnn_mini_batch = 16;

[model, norm_params] = train_logistic(features, labels, params);
assert(isfield(model, 'coefficients') && numel(model.coefficients) >= 2, 'train_logistic output is invalid.');

results = eval_roc_calibration(model, norm_params, features, labels, params);
assert(isfield(results, 'roc') && isfield(results.roc, 'auc'), 'eval_roc_calibration output is invalid.');

benchmark = run_ml_benchmark(features, labels, params);
assert(istable(benchmark) && height(benchmark) == 4, 'run_ml_benchmark output is invalid.');

ablation = run_ablation(features, labels, params);
assert(istable(ablation) && height(ablation) == 3, 'run_ablation output is invalid.');

feature_table = table((1:n_sample)', features(:, 1), features(:, 2), labels, ...
    'VariableNames', {'position_id', 'r_CP', 'a_FP', 'label'});

generate_figures(feature_table, model, results, benchmark, ablation, params);

fprintf('test_phase2_smoke passed.\n');
end
