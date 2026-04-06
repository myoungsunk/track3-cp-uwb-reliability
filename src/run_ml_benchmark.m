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

benchmark_results = table( ...
    string({metrics_logistic.model_name; metrics_svm.model_name; metrics_rf.model_name; metrics_dnn.model_name}), ...
    [metrics_logistic.auc; metrics_svm.auc; metrics_rf.auc; metrics_dnn.auc], ...
    [metrics_logistic.accuracy; metrics_svm.accuracy; metrics_rf.accuracy; metrics_dnn.accuracy], ...
    [metrics_logistic.f1; metrics_svm.f1; metrics_rf.f1; metrics_dnn.f1], ...
    [metrics_logistic.ece; metrics_svm.ece; metrics_rf.ece; metrics_dnn.ece], ...
    [metrics_logistic.flops; metrics_svm.flops; metrics_rf.flops; metrics_dnn.flops], ...
    [metrics_logistic.n_parameters; metrics_svm.n_parameters; metrics_rf.n_parameters; metrics_dnn.n_parameters], ...
    [metrics_logistic.train_time_s; metrics_svm.train_time_s; metrics_rf.train_time_s; metrics_dnn.train_time_s], ...
    [metrics_logistic.infer_time_us; metrics_svm.infer_time_us; metrics_rf.infer_time_us; metrics_dnn.infer_time_us], ...
    'VariableNames', {'model_name', 'auc', 'accuracy', 'f1', 'ece', 'flops', 'n_parameters', 'train_time_s', 'infer_time_us'});

roc_curves = struct([]);
roc_curves(1).model_name = metrics_logistic.model_name;
roc_curves(1).fpr = metrics_logistic.roc_fpr;
roc_curves(1).tpr = metrics_logistic.roc_tpr;
roc_curves(1).auc = metrics_logistic.auc;

roc_curves(2).model_name = metrics_svm.model_name;
roc_curves(2).fpr = metrics_svm.roc_fpr;
roc_curves(2).tpr = metrics_svm.roc_tpr;
roc_curves(2).auc = metrics_svm.auc;

roc_curves(3).model_name = metrics_rf.model_name;
roc_curves(3).fpr = metrics_rf.roc_fpr;
roc_curves(3).tpr = metrics_rf.roc_tpr;
roc_curves(3).auc = metrics_rf.auc;

roc_curves(4).model_name = metrics_dnn.model_name;
roc_curves(4).fpr = metrics_dnn.roc_fpr;
roc_curves(4).tpr = metrics_dnn.roc_tpr;
roc_curves(4).auc = metrics_dnn.auc;

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

function metrics = benchmark_dnn(features, labels, params, cv)
max_epochs = get_param(params, 'dnn_max_epochs', 100);
mini_batch = get_param(params, 'dnn_mini_batch', 32);

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
