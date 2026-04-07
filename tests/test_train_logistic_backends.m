function test_train_logistic_backends
% TEST_TRAIN_LOGISTIC_BACKENDS Validate fitglm/ridge backends and auto fallback path.
addpath('src');

rng(7);
n_sample = 120;
n_half = n_sample / 2;

r_cp_los = 10.^(0.9 + 0.12 * randn(n_half, 1));
a_fp_los = 0.72 + 0.06 * randn(n_half, 1);
r_cp_nlos = 10.^(0.2 + 0.12 * randn(n_half, 1));
a_fp_nlos = 0.35 + 0.08 * randn(n_half, 1);

features = [[r_cp_los; r_cp_nlos], [a_fp_los; a_fp_nlos]];
labels = [true(n_half, 1); false(n_half, 1)];

base_params = struct();
base_params.normalize = true;
base_params.cv_folds = 3;
base_params.random_seed = 7;
base_params.save_outputs = false;
base_params.log10_rcp = true;
base_params.logistic_ridge_lambda = 0.01;

% fitglm backend.
params_fitglm = base_params;
params_fitglm.logistic_backend = 'fitglm';
[model_fitglm, norm_fitglm] = train_logistic(features, labels, params_fitglm);
assert(strcmpi(model_fitglm.backend, 'fitglm'), 'fitglm backend not selected.');
res_fitglm = eval_roc_calibration(model_fitglm, norm_fitglm, features, labels, params_fitglm);
assert(isfinite(res_fitglm.roc.auc), 'fitglm backend AUC should be finite.');

% ridge backend.
params_ridge = base_params;
params_ridge.logistic_backend = 'ridge';
[model_ridge, norm_ridge] = train_logistic(features, labels, params_ridge);
assert(strcmpi(model_ridge.backend, 'ridge'), 'ridge backend not selected.');
res_ridge = eval_roc_calibration(model_ridge, norm_ridge, features, labels, params_ridge);
assert(isfinite(res_ridge.roc.auc), 'ridge backend AUC should be finite.');

% auto backend fallback (forced fitglm failure).
params_auto = base_params;
params_auto.logistic_backend = 'auto';
params_auto.logistic_force_fitglm_fail = true;
[model_auto, ~] = train_logistic(features, labels, params_auto);
assert(strcmpi(model_auto.backend, 'ridge'), 'auto backend should fall back to ridge when fitglm fails.');

fprintf('test_train_logistic_backends passed.\n');
end
