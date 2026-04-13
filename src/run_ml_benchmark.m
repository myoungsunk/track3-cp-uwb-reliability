function benchmark_results = run_ml_benchmark(features, labels, params)
% RUN_ML_BENCHMARK Benchmark logistic, SVM, random forest, and DNN using shared CV splits.
if nargin < 3
    params = struct();
end

features = double(features);
labels = logical(labels(:));
if size(features, 1) ~= numel(labels)
    error('[run_ml_benchmark] features rows and labels length must match.');
end
if size(features, 2) ~= 2
    error('[run_ml_benchmark] features must be [N x 2] = [r_CP, a_FP].');
end

valid_mask = all(isfinite(features), 2);
features = features(valid_mask, :);
labels = labels(valid_mask);

if numel(unique(labels)) < 2
    error('[run_ml_benchmark] labels must contain both classes.');
end

random_seed = get_param(params, 'random_seed', 42);
cv_folds = get_param(params, 'cv_folds', 5);
rng(random_seed);
cv = cvpartition(labels, 'KFold', cv_folds);

metrics_logistic = benchmark_logistic(features, labels, params, cv);
metrics_svm = benchmark_svm(features, labels, params, cv);
metrics_rf = benchmark_rf(features, labels, params, cv);
try
    metrics_dnn = benchmark_dnn(features, labels, params, cv);
catch exception_info
    warning('[run_ml_benchmark] DNN benchmark skipped: %s', exception_info.message);
    metrics_dnn = empty_metrics('DNN');
end

metrics_list = {metrics_logistic, metrics_svm, metrics_rf, metrics_dnn};
include_lightweight_models = logical(get_param(params, 'include_lightweight_models', true));
if include_lightweight_models
    try
        metrics_lda = benchmark_lda(features, labels, params, cv);
    catch exception_info
        warning('[run_ml_benchmark] LDA benchmark skipped: %s', exception_info.message);
        metrics_lda = empty_metrics('LDA');
    end

    try
        metrics_qda = benchmark_qda(features, labels, params, cv);
    catch exception_info
        warning('[run_ml_benchmark] QDA benchmark skipped: %s', exception_info.message);
        metrics_qda = empty_metrics('QDA');
    end

    try
        metrics_linear_svm = benchmark_linear_svm(features, labels, params, cv);
    catch exception_info
        warning('[run_ml_benchmark] LinearSVM benchmark skipped: %s', exception_info.message);
        metrics_linear_svm = empty_metrics('LinearSVM');
    end

    try
        metrics_tiny_tree = benchmark_tiny_tree(features, labels, params, cv);
    catch exception_info
        warning('[run_ml_benchmark] TinyTree benchmark skipped: %s', exception_info.message);
        metrics_tiny_tree = empty_metrics('TinyTree');
    end

    try
        metrics_logistic_quad = benchmark_logistic_quadratic(features, labels, params, cv);
    catch exception_info
        warning('[run_ml_benchmark] LogisticQuad benchmark skipped: %s', exception_info.message);
        metrics_logistic_quad = empty_metrics('LogisticQuad');
    end

    metrics_list = [metrics_list, {metrics_lda, metrics_qda, metrics_linear_svm, metrics_tiny_tree, metrics_logistic_quad}]; %#ok<AGROW>
end

n_model = numel(metrics_list);
model_name_col = strings(n_model, 1);
auc_col = nan(n_model, 1);
accuracy_col = nan(n_model, 1);
f1_col = nan(n_model, 1);
ece_col = nan(n_model, 1);
flops_col = nan(n_model, 1);
n_parameters_col = nan(n_model, 1);
train_time_col = nan(n_model, 1);
infer_time_col = nan(n_model, 1);

for idx = 1:n_model
    metrics_i = metrics_list{idx};
    model_name_col(idx) = string(metrics_i.model_name);
    auc_col(idx) = metrics_i.auc;
    accuracy_col(idx) = metrics_i.accuracy;
    f1_col(idx) = metrics_i.f1;
    ece_col(idx) = metrics_i.ece;
    flops_col(idx) = metrics_i.flops;
    n_parameters_col(idx) = metrics_i.n_parameters;
    train_time_col(idx) = metrics_i.train_time_s;
    infer_time_col(idx) = metrics_i.infer_time_us;
end

benchmark_results = table( ...
    model_name_col, ...
    auc_col, ...
    accuracy_col, ...
    f1_col, ...
    ece_col, ...
    flops_col, ...
    n_parameters_col, ...
    train_time_col, ...
    infer_time_col, ...
    'VariableNames', {'model_name', 'auc', 'accuracy', 'f1', 'ece', 'flops', 'n_parameters', 'train_time_s', 'infer_time_us'});

roc_curves = repmat(struct('model_name', "", 'fpr', [], 'tpr', [], 'auc', NaN), n_model, 1);
for idx = 1:n_model
    metrics_i = metrics_list{idx};
    roc_curves(idx).model_name = string(metrics_i.model_name);
    roc_curves(idx).fpr = metrics_i.roc_fpr;
    roc_curves(idx).tpr = metrics_i.roc_tpr;
    roc_curves(idx).auc = metrics_i.auc;
end

benchmark_results.Properties.UserData.roc_curves = roc_curves;

save_outputs = logical(get_param(params, 'save_outputs', true));
if save_outputs
    output_dir = char(get_param(params, 'results_dir', fullfile(pwd, 'results')));
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end

    save(fullfile(output_dir, 'benchmark_results.mat'), 'benchmark_results', 'roc_curves');
    writetable(benchmark_results, fullfile(output_dir, 'benchmark_results.csv'));
end
end

function metrics = benchmark_logistic(features, labels, params, cv)
params_local = params;
params_local.cv_partition = cv;
params_local.log10_rcp = true;

train_start = tic;
[model, norm_params] = train_logistic(features, labels, params_local);
train_time_s = toc(train_start);

eval_results = eval_roc_calibration(model, norm_params, features, labels, setfield(params_local, 'save_outputs', false)); %#ok<SFLD>

infer_time_us = measure_inference_time(@(x) predict_logistic_prob(model, x), ...
    prepare_single_input(features, norm_params));

metrics = struct();
metrics.model_name = 'Logistic';
metrics.auc = model.cv_auc;
metrics.accuracy = model.cv_accuracy;
metrics.f1 = eval_results.f1;
metrics.ece = eval_results.ece;
metrics.flops = get_param(params, 'logistic_flops', 5);
metrics.n_parameters = numel(model.coefficients);
metrics.train_time_s = train_time_s;
metrics.infer_time_us = infer_time_us;
metrics.roc_fpr = eval_results.roc.fpr;
metrics.roc_tpr = eval_results.roc.tpr;
end

function metrics = benchmark_svm(features, labels, params, cv)
random_seed = get_param(params, 'random_seed', 42);
svm_optimize = logical(get_param(params, 'svm_optimize_hyperparameters', true));
svm_max_evals = get_param(params, 'svm_max_objective_evals', 30);

n_folds = cv.NumTestSets;
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);

scores_oof = nan(size(labels));

for fold_idx = 1:n_folds
    train_idx = training(cv, fold_idx);
    test_idx = test(cv, fold_idx);

    x_train = features(train_idx, :);
    y_train = labels(train_idx);
    x_test = features(test_idx, :);
    y_test = labels(test_idx);

    [x_train_norm, norm_info] = normalize_binary(x_train);
    x_test_norm = apply_norm_binary(x_test, norm_info);

    rng(random_seed + fold_idx);
    if svm_optimize
        svm_mdl = fitcsvm(x_train_norm, y_train, 'KernelFunction', 'rbf', 'Standardize', true, ...
            'OptimizeHyperparameters', 'auto', ...
            'HyperparameterOptimizationOptions', struct('MaxObjectiveEvaluations', svm_max_evals, 'ShowPlots', false, 'Verbose', 0));
    else
        svm_mdl = fitcsvm(x_train_norm, y_train, 'KernelFunction', 'rbf', 'Standardize', true);
    end

    svm_mdl = fitPosterior(svm_mdl);
    [~, score_fold] = predict(svm_mdl, x_test_norm);
    prob_fold = get_positive_score(score_fold, svm_mdl.ClassNames);
    scores_oof(test_idx) = prob_fold;

    fold_metrics = binary_metrics(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = fold_metrics.auc;
    acc_list(fold_idx) = fold_metrics.accuracy;
    f1_list(fold_idx) = fold_metrics.f1;
    ece_list(fold_idx) = fold_metrics.ece;
end

train_start = tic;
[x_all_norm, norm_all] = normalize_binary(features);
rng(random_seed);
if svm_optimize
    svm_full = fitcsvm(x_all_norm, labels, 'KernelFunction', 'rbf', 'Standardize', true, ...
        'OptimizeHyperparameters', 'auto', ...
        'HyperparameterOptimizationOptions', struct('MaxObjectiveEvaluations', svm_max_evals, 'ShowPlots', false, 'Verbose', 0));
else
    svm_full = fitcsvm(x_all_norm, labels, 'KernelFunction', 'rbf', 'Standardize', true);
end
svm_full = fitPosterior(svm_full);
train_time_s = toc(train_start);

n_sv = size(svm_full.SupportVectors, 1);
input_dim = size(features, 2);
flops = n_sv * (2 * input_dim + 1) + 1;
n_parameters = n_sv * input_dim + n_sv + 1;

x_single = apply_norm_binary(features(1, :), norm_all);
infer_time_us = measure_inference_time(@(x) predict(svm_full, x), x_single);

[~, ~, ~, auc_all] = perfcurve(labels, scores_oof, true);
[fpr_all, tpr_all] = perfcurve(labels, scores_oof, true);

metrics = struct();
metrics.model_name = 'SVM';
metrics.auc = mean(auc_list, 'omitnan');
metrics.accuracy = mean(acc_list, 'omitnan');
metrics.f1 = mean(f1_list, 'omitnan');
metrics.ece = mean(ece_list, 'omitnan');
metrics.flops = flops;
metrics.n_parameters = n_parameters;
metrics.train_time_s = train_time_s;
metrics.infer_time_us = infer_time_us;
metrics.roc_fpr = fpr_all;
metrics.roc_tpr = tpr_all;

if isfinite(auc_all)
    metrics.auc = auc_all;
end
end

function metrics = benchmark_rf(features, labels, params, cv)
num_trees = get_param(params, 'rf_num_trees', 100);
max_splits = get_param(params, 'rf_max_num_splits', 20);

n_folds = cv.NumTestSets;
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);
scores_oof = nan(size(labels));

for fold_idx = 1:n_folds
    train_idx = training(cv, fold_idx);
    test_idx = test(cv, fold_idx);

    x_train = features(train_idx, :);
    y_train = labels(train_idx);
    x_test = features(test_idx, :);
    y_test = labels(test_idx);

    [x_train_norm, norm_info] = normalize_binary(x_train);
    x_test_norm = apply_norm_binary(x_test, norm_info);

    rf_mdl = fitcensemble(x_train_norm, y_train, 'Method', 'Bag', ...
        'NumLearningCycles', num_trees, 'Learners', templateTree('MaxNumSplits', max_splits));

    [~, score_fold] = predict(rf_mdl, x_test_norm);
    prob_fold = get_positive_score(score_fold, rf_mdl.ClassNames);
    scores_oof(test_idx) = prob_fold;

    fold_metrics = binary_metrics(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = fold_metrics.auc;
    acc_list(fold_idx) = fold_metrics.accuracy;
    f1_list(fold_idx) = fold_metrics.f1;
    ece_list(fold_idx) = fold_metrics.ece;
end

train_start = tic;
[x_all_norm, norm_all] = normalize_binary(features);
rf_full = fitcensemble(x_all_norm, labels, 'Method', 'Bag', ...
    'NumLearningCycles', num_trees, 'Learners', templateTree('MaxNumSplits', max_splits));
train_time_s = toc(train_start);

avg_depth = mean(cellfun(@tree_depth, rf_full.Trained));
flops = num_trees * avg_depth;
n_parameters = sum(cellfun(@(t) double(t.NumNodes), rf_full.Trained));

x_single = apply_norm_binary(features(1, :), norm_all);
infer_time_us = measure_inference_time(@(x) predict(rf_full, x), x_single);

[~, ~, ~, auc_all] = perfcurve(labels, scores_oof, true);
[fpr_all, tpr_all] = perfcurve(labels, scores_oof, true);

metrics = struct();
metrics.model_name = 'RandomForest';
metrics.auc = mean(auc_list, 'omitnan');
metrics.accuracy = mean(acc_list, 'omitnan');
metrics.f1 = mean(f1_list, 'omitnan');
metrics.ece = mean(ece_list, 'omitnan');
metrics.flops = flops;
metrics.n_parameters = n_parameters;
metrics.train_time_s = train_time_s;
metrics.infer_time_us = infer_time_us;
metrics.roc_fpr = fpr_all;
metrics.roc_tpr = tpr_all;

if isfinite(auc_all)
    metrics.auc = auc_all;
end
end

function metrics = benchmark_lda(features, labels, params, cv)
n_folds = cv.NumTestSets;
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);
scores_oof = nan(size(labels));

for fold_idx = 1:n_folds
    train_idx = training(cv, fold_idx);
    test_idx = test(cv, fold_idx);

    x_train = features(train_idx, :);
    y_train = labels(train_idx);
    x_test = features(test_idx, :);
    y_test = labels(test_idx);

    [x_train_norm, norm_info] = normalize_binary(x_train);
    x_test_norm = apply_norm_binary(x_test, norm_info);

    lda_mdl = fitcdiscr(x_train_norm, y_train, 'DiscrimType', 'linear');
    [~, score_fold] = predict(lda_mdl, x_test_norm);
    prob_fold = get_positive_score(score_fold, lda_mdl.ClassNames);
    scores_oof(test_idx) = prob_fold;

    fold_metrics = binary_metrics(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = fold_metrics.auc;
    acc_list(fold_idx) = fold_metrics.accuracy;
    f1_list(fold_idx) = fold_metrics.f1;
    ece_list(fold_idx) = fold_metrics.ece;
end

train_start = tic;
[x_all_norm, norm_all] = normalize_binary(features);
lda_full = fitcdiscr(x_all_norm, labels, 'DiscrimType', 'linear');
train_time_s = toc(train_start);

input_dim = size(features, 2);
flops = 2 * input_dim + 1;
n_parameters = (2 * input_dim) + (input_dim * (input_dim + 1) / 2);

x_single = apply_norm_binary(features(1, :), norm_all);
infer_time_us = measure_inference_time(@(x) predict(lda_full, x), x_single);

[~, ~, ~, auc_all] = perfcurve(labels, scores_oof, true);
[fpr_all, tpr_all] = perfcurve(labels, scores_oof, true);

metrics = struct();
metrics.model_name = 'LDA';
metrics.auc = mean(auc_list, 'omitnan');
metrics.accuracy = mean(acc_list, 'omitnan');
metrics.f1 = mean(f1_list, 'omitnan');
metrics.ece = mean(ece_list, 'omitnan');
metrics.flops = flops;
metrics.n_parameters = n_parameters;
metrics.train_time_s = train_time_s;
metrics.infer_time_us = infer_time_us;
metrics.roc_fpr = fpr_all;
metrics.roc_tpr = tpr_all;

if isfinite(auc_all)
    metrics.auc = auc_all;
end
end

function metrics = benchmark_qda(features, labels, params, cv)
n_folds = cv.NumTestSets;
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);
scores_oof = nan(size(labels));

for fold_idx = 1:n_folds
    train_idx = training(cv, fold_idx);
    test_idx = test(cv, fold_idx);

    x_train = features(train_idx, :);
    y_train = labels(train_idx);
    x_test = features(test_idx, :);
    y_test = labels(test_idx);

    [x_train_norm, norm_info] = normalize_binary(x_train);
    x_test_norm = apply_norm_binary(x_test, norm_info);

    qda_mdl = fitcdiscr(x_train_norm, y_train, 'DiscrimType', 'quadratic');
    [~, score_fold] = predict(qda_mdl, x_test_norm);
    prob_fold = get_positive_score(score_fold, qda_mdl.ClassNames);
    scores_oof(test_idx) = prob_fold;

    fold_metrics = binary_metrics(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = fold_metrics.auc;
    acc_list(fold_idx) = fold_metrics.accuracy;
    f1_list(fold_idx) = fold_metrics.f1;
    ece_list(fold_idx) = fold_metrics.ece;
end

train_start = tic;
[x_all_norm, norm_all] = normalize_binary(features);
qda_full = fitcdiscr(x_all_norm, labels, 'DiscrimType', 'quadratic');
train_time_s = toc(train_start);

input_dim = size(features, 2);
flops = input_dim * input_dim + (3 * input_dim) + 2;
n_parameters = 2 * (input_dim + input_dim * (input_dim + 1) / 2);

x_single = apply_norm_binary(features(1, :), norm_all);
infer_time_us = measure_inference_time(@(x) predict(qda_full, x), x_single);

[~, ~, ~, auc_all] = perfcurve(labels, scores_oof, true);
[fpr_all, tpr_all] = perfcurve(labels, scores_oof, true);

metrics = struct();
metrics.model_name = 'QDA';
metrics.auc = mean(auc_list, 'omitnan');
metrics.accuracy = mean(acc_list, 'omitnan');
metrics.f1 = mean(f1_list, 'omitnan');
metrics.ece = mean(ece_list, 'omitnan');
metrics.flops = flops;
metrics.n_parameters = n_parameters;
metrics.train_time_s = train_time_s;
metrics.infer_time_us = infer_time_us;
metrics.roc_fpr = fpr_all;
metrics.roc_tpr = tpr_all;

if isfinite(auc_all)
    metrics.auc = auc_all;
end
end

function metrics = benchmark_linear_svm(features, labels, params, cv)
random_seed = get_param(params, 'random_seed', 42);
n_folds = cv.NumTestSets;
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);
scores_oof = nan(size(labels));

for fold_idx = 1:n_folds
    train_idx = training(cv, fold_idx);
    test_idx = test(cv, fold_idx);

    x_train = features(train_idx, :);
    y_train = labels(train_idx);
    x_test = features(test_idx, :);
    y_test = labels(test_idx);

    [x_train_norm, norm_info] = normalize_binary(x_train);
    x_test_norm = apply_norm_binary(x_test, norm_info);

    rng(random_seed + fold_idx);
    svm_lin = fitcsvm(x_train_norm, y_train, 'KernelFunction', 'linear', 'Standardize', true);
    svm_lin = fitPosterior(svm_lin);
    [~, score_fold] = predict(svm_lin, x_test_norm);
    prob_fold = get_positive_score(score_fold, svm_lin.ClassNames);
    scores_oof(test_idx) = prob_fold;

    fold_metrics = binary_metrics(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = fold_metrics.auc;
    acc_list(fold_idx) = fold_metrics.accuracy;
    f1_list(fold_idx) = fold_metrics.f1;
    ece_list(fold_idx) = fold_metrics.ece;
end

train_start = tic;
[x_all_norm, norm_all] = normalize_binary(features);
rng(random_seed);
svm_lin_full = fitcsvm(x_all_norm, labels, 'KernelFunction', 'linear', 'Standardize', true);
svm_lin_full = fitPosterior(svm_lin_full);
train_time_s = toc(train_start);

input_dim = size(features, 2);
flops = 2 * input_dim + 1;
n_parameters = input_dim + 1;

x_single = apply_norm_binary(features(1, :), norm_all);
infer_time_us = measure_inference_time(@(x) predict(svm_lin_full, x), x_single);

[~, ~, ~, auc_all] = perfcurve(labels, scores_oof, true);
[fpr_all, tpr_all] = perfcurve(labels, scores_oof, true);

metrics = struct();
metrics.model_name = 'LinearSVM';
metrics.auc = mean(auc_list, 'omitnan');
metrics.accuracy = mean(acc_list, 'omitnan');
metrics.f1 = mean(f1_list, 'omitnan');
metrics.ece = mean(ece_list, 'omitnan');
metrics.flops = flops;
metrics.n_parameters = n_parameters;
metrics.train_time_s = train_time_s;
metrics.infer_time_us = infer_time_us;
metrics.roc_fpr = fpr_all;
metrics.roc_tpr = tpr_all;

if isfinite(auc_all)
    metrics.auc = auc_all;
end
end

function metrics = benchmark_tiny_tree(features, labels, params, cv)
max_splits = get_param(params, 'tiny_tree_max_splits', 3);
min_leaf_size = get_param(params, 'tiny_tree_min_leaf_size', 5);
n_folds = cv.NumTestSets;
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);
scores_oof = nan(size(labels));

for fold_idx = 1:n_folds
    train_idx = training(cv, fold_idx);
    test_idx = test(cv, fold_idx);

    x_train = features(train_idx, :);
    y_train = labels(train_idx);
    x_test = features(test_idx, :);
    y_test = labels(test_idx);

    [x_train_norm, norm_info] = normalize_binary(x_train);
    x_test_norm = apply_norm_binary(x_test, norm_info);

    tree_mdl = fitctree(x_train_norm, y_train, 'MaxNumSplits', max_splits, 'MinLeafSize', min_leaf_size);
    [~, score_fold] = predict(tree_mdl, x_test_norm);
    prob_fold = get_positive_score(score_fold, tree_mdl.ClassNames);
    scores_oof(test_idx) = prob_fold;

    fold_metrics = binary_metrics(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = fold_metrics.auc;
    acc_list(fold_idx) = fold_metrics.accuracy;
    f1_list(fold_idx) = fold_metrics.f1;
    ece_list(fold_idx) = fold_metrics.ece;
end

train_start = tic;
[x_all_norm, norm_all] = normalize_binary(features);
tree_full = fitctree(x_all_norm, labels, 'MaxNumSplits', max_splits, 'MinLeafSize', min_leaf_size);
train_time_s = toc(train_start);

flops = tree_depth(tree_full);
n_parameters = double(tree_full.NumNodes);

x_single = apply_norm_binary(features(1, :), norm_all);
infer_time_us = measure_inference_time(@(x) predict(tree_full, x), x_single);

[~, ~, ~, auc_all] = perfcurve(labels, scores_oof, true);
[fpr_all, tpr_all] = perfcurve(labels, scores_oof, true);

metrics = struct();
metrics.model_name = 'TinyTree';
metrics.auc = mean(auc_list, 'omitnan');
metrics.accuracy = mean(acc_list, 'omitnan');
metrics.f1 = mean(f1_list, 'omitnan');
metrics.ece = mean(ece_list, 'omitnan');
metrics.flops = flops;
metrics.n_parameters = n_parameters;
metrics.train_time_s = train_time_s;
metrics.infer_time_us = infer_time_us;
metrics.roc_fpr = fpr_all;
metrics.roc_tpr = tpr_all;

if isfinite(auc_all)
    metrics.auc = auc_all;
end
end

function metrics = benchmark_logistic_quadratic(features, labels, params, cv)
params_local = params;
params_local.cv_partition = cv;
params_local.log10_rcp = false;

features_quad = expand_quadratic_features(features);
train_start = tic;
[model, norm_params] = train_logistic(features_quad, labels, params_local);
train_time_s = toc(train_start);

eval_results = eval_roc_calibration(model, norm_params, features_quad, labels, setfield(params_local, 'save_outputs', false)); %#ok<SFLD>

x_single = prepare_single_input(features_quad, norm_params);
infer_time_us = measure_inference_time(@(x) predict_logistic_prob(model, x), x_single);

metrics = struct();
metrics.model_name = 'LogisticQuad';
metrics.auc = model.cv_auc;
metrics.accuracy = model.cv_accuracy;
metrics.f1 = eval_results.f1;
metrics.ece = eval_results.ece;
metrics.flops = 2 * size(features_quad, 2) + 1;
metrics.n_parameters = numel(model.coefficients);
metrics.train_time_s = train_time_s;
metrics.infer_time_us = infer_time_us;
metrics.roc_fpr = eval_results.roc.fpr;
metrics.roc_tpr = eval_results.roc.tpr;
end

function metrics = benchmark_dnn(features, labels, params, cv)
max_epochs = get_param(params, 'dnn_max_epochs', 100);
mini_batch = get_param(params, 'dnn_mini_batch', 32);
random_seed = get_param(params, 'random_seed', 42);

n_folds = cv.NumTestSets;
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);
scores_oof = nan(size(labels));

for fold_idx = 1:n_folds
    train_idx = training(cv, fold_idx);
    test_idx = test(cv, fold_idx);

    x_train = features(train_idx, :);
    y_train = labels(train_idx);
    x_test = features(test_idx, :);
    y_test = labels(test_idx);

    [x_train_norm, norm_info] = normalize_binary(x_train);
    x_test_norm = apply_norm_binary(x_test, norm_info);

    rng(random_seed + fold_idx);
    dnn_mdl = train_dnn_model(x_train_norm, y_train, max_epochs, mini_batch);
    score_fold = predict(dnn_mdl, x_test_norm);
    prob_fold = get_positive_score(score_fold, dnn_mdl.Layers(end).Classes);
    scores_oof(test_idx) = prob_fold;

    fold_metrics = binary_metrics(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = fold_metrics.auc;
    acc_list(fold_idx) = fold_metrics.accuracy;
    f1_list(fold_idx) = fold_metrics.f1;
    ece_list(fold_idx) = fold_metrics.ece;
end

train_start = tic;
[x_all_norm, norm_all] = normalize_binary(features);
rng(random_seed);
dnn_full = train_dnn_model(x_all_norm, labels, max_epochs, mini_batch);
train_time_s = toc(train_start);

flops = get_param(params, 'dnn_flops', 194);
n_parameters = get_param(params, 'dnn_n_parameters', 194);

x_single = apply_norm_binary(features(1, :), norm_all);
infer_time_us = measure_inference_time(@(x) predict(dnn_full, x), x_single);

[~, ~, ~, auc_all] = perfcurve(labels, scores_oof, true);
[fpr_all, tpr_all] = perfcurve(labels, scores_oof, true);

metrics = struct();
metrics.model_name = 'DNN';
metrics.auc = mean(auc_list, 'omitnan');
metrics.accuracy = mean(acc_list, 'omitnan');
metrics.f1 = mean(f1_list, 'omitnan');
metrics.ece = mean(ece_list, 'omitnan');
metrics.flops = flops;
metrics.n_parameters = n_parameters;
metrics.train_time_s = train_time_s;
metrics.infer_time_us = infer_time_us;
metrics.roc_fpr = fpr_all;
metrics.roc_tpr = tpr_all;

if isfinite(auc_all)
    metrics.auc = auc_all;
end
end

function metrics = empty_metrics(model_name)
metrics = struct();
metrics.model_name = char(model_name);
metrics.auc = NaN;
metrics.accuracy = NaN;
metrics.f1 = NaN;
metrics.ece = NaN;
metrics.flops = NaN;
metrics.n_parameters = NaN;
metrics.train_time_s = NaN;
metrics.infer_time_us = NaN;
metrics.roc_fpr = NaN;
metrics.roc_tpr = NaN;
end

function dnn_mdl = train_dnn_model(x_train, y_train, max_epochs, mini_batch)
if size(x_train, 1) ~= numel(y_train)
    error('[run_ml_benchmark] DNN train input size mismatch: X rows=%d, Y count=%d.', ...
        size(x_train, 1), numel(y_train));
end

layers = [ ...
    featureInputLayer(2)
    fullyConnectedLayer(16)
    reluLayer
    fullyConnectedLayer(8)
    reluLayer
    fullyConnectedLayer(2)
    softmaxLayer
    classificationLayer];

y_cat = categorical(y_train);
options = trainingOptions('adam', 'MaxEpochs', max_epochs, 'MiniBatchSize', mini_batch, ...
    'Verbose', false, 'Plots', 'none');

dnn_mdl = trainNetwork(x_train, y_cat, layers, options);
end

function [x_norm, info] = normalize_binary(x)
mean_values = mean(x, 1, 'omitnan');
std_values = std(x, 0, 1, 'omitnan');
std_values(std_values == 0) = 1;
x_norm = (x - mean_values) ./ std_values;
info = struct('mean_values', mean_values, 'std_values', std_values);
end

function x_out = apply_norm_binary(x, info)
x_out = (x - info.mean_values) ./ info.std_values;
end

function x_quad = expand_quadratic_features(features)
x1 = double(features(:, 1));
x2 = double(features(:, 2));
if any(x1 <= 0)
    error('[run_ml_benchmark] r_CP values must be > 0 for quadratic logistic expansion.');
end
x1_log = log10(x1);
x_quad = [x1_log, x2, x1_log.^2, x1_log .* x2, x2.^2];
end

function prob = get_positive_score(score_matrix, class_names)
if numel(class_names) ~= 2
    error('[run_ml_benchmark] binary class names expected.');
end

if islogical(class_names)
    pos_idx = find(class_names == true, 1, 'first');
else
    pos_idx = find(strcmp(string(class_names), string(true)), 1, 'first');
    if isempty(pos_idx)
        pos_idx = 2;
    end
end

prob = score_matrix(:, pos_idx);
end

function metrics = binary_metrics(prob, labels, n_bins)
[~, ~, ~, auc] = perfcurve(labels, prob, true);
y_hat = prob >= 0.5;
accuracy = mean(y_hat == labels);

tp = sum(y_hat & labels);
fp = sum(y_hat & ~labels);
fn = sum(~y_hat & labels);
precision = tp / max(tp + fp, eps);
recall = tp / max(tp + fn, eps);
f1 = 2 * precision * recall / max(precision + recall, eps);

ece = compute_ece(prob, labels, n_bins);

metrics = struct('auc', auc, 'accuracy', accuracy, 'f1', f1, 'ece', ece);
end

function ece = compute_ece(prob, labels, n_bins)
bin_edges = linspace(0, 1, n_bins + 1);
ece = 0;
n_total = numel(prob);

for bin_idx = 1:n_bins
    if bin_idx < n_bins
        in_bin = prob >= bin_edges(bin_idx) & prob < bin_edges(bin_idx + 1);
    else
        in_bin = prob >= bin_edges(bin_idx) & prob <= bin_edges(bin_idx + 1);
    end

    n_bin = sum(in_bin);
    if n_bin == 0
        continue;
    end

    avg_pred = mean(prob(in_bin));
    frac_pos = mean(labels(in_bin));
    ece = ece + (n_bin / n_total) * abs(avg_pred - frac_pos);
end
end

function depth = tree_depth(tree_obj)
if isprop(tree_obj, 'Children') && ~isempty(tree_obj.Children)
    children = tree_obj.Children;
    node_depth = zeros(size(children, 1), 1);
    for node_idx = 1:size(children, 1)
        left_child = children(node_idx, 1);
        right_child = children(node_idx, 2);
        if left_child > 0
            node_depth(left_child) = max(node_depth(left_child), node_depth(node_idx) + 1);
        end
        if right_child > 0
            node_depth(right_child) = max(node_depth(right_child), node_depth(node_idx) + 1);
        end
    end
    depth = max(node_depth);
else
    depth = ceil(log2(double(tree_obj.NumLeaves) + 1));
end
end

function infer_time_us = measure_inference_time(predict_fn, sample_input)
n_repeat = 1000;
for warm_idx = 1:10
    predict_fn(sample_input);
end

start_tic = tic;
for run_idx = 1:n_repeat
    predict_fn(sample_input);
end
elapsed_s = toc(start_tic);
infer_time_us = elapsed_s / n_repeat * 1e6;
end

function x_single = prepare_single_input(features, norm_params)
x_single = double(features(1, :));
if isfield(norm_params, 'log10_rcp') && logical(norm_params.log10_rcp)
    x_single(1) = log10(x_single(1));
end
if isfield(norm_params, 'normalize') && logical(norm_params.normalize)
    x_single = (x_single - norm_params.mean_values) ./ norm_params.std_values;
end
end
