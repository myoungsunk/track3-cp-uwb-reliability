function benchmark_results = run_ml_benchmark_cp3(features, labels, params)
% RUN_ML_BENCHMARK_CP3 Benchmark models with 3 CP features:
% [gamma_CP, a_FP, fp_idx_diff].
if nargin < 3
    params = struct();
end

features = double(features);
labels = logical(labels(:));

if size(features, 1) ~= numel(labels)
    error('[run_ml_benchmark_cp3] features rows and labels length must match.');
end
if size(features, 2) < 3
    error('[run_ml_benchmark_cp3] features must have at least 3 columns [gamma_CP, a_FP, fp_idx_diff].');
end

features = features(:, 1:3);
valid_mask = all(isfinite(features), 2);
features = features(valid_mask, :);
labels = labels(valid_mask);

if numel(unique(labels)) < 2
    error('[run_ml_benchmark_cp3] labels must contain both classes.');
end

random_seed = get_param(params, 'random_seed', 42);
cv_folds = get_param(params, 'cv_folds', 5);
rng(random_seed);
cv = cvpartition(labels, 'KFold', cv_folds);

metrics_list = {};
metrics_list{end + 1} = benchmark_logistic_cp3(features, labels, params, cv);
metrics_list{end + 1} = benchmark_svm_cp3(features, labels, params, cv);
metrics_list{end + 1} = benchmark_rf_cp3(features, labels, params, cv);
metrics_list{end + 1} = benchmark_lda_cp3(features, labels, params, cv);
metrics_list{end + 1} = benchmark_linear_svm_cp3(features, labels, params, cv);

try
    metrics_list{end + 1} = benchmark_dnn_cp3(features, labels, params, cv); %#ok<AGROW>
catch exception_info
    warning('[run_ml_benchmark_cp3] DNN benchmark skipped: %s', exception_info.message);
    metrics_list{end + 1} = empty_metrics_cp3('DNN'); %#ok<AGROW>
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

roc_curves = repmat(struct('model_name', "", 'fpr', [], 'tpr', [], 'auc', NaN), n_model, 1);

for idx = 1:n_model
    m = metrics_list{idx};
    model_name_col(idx) = string(m.model_name);
    auc_col(idx) = m.auc;
    accuracy_col(idx) = m.accuracy;
    f1_col(idx) = m.f1;
    ece_col(idx) = m.ece;
    flops_col(idx) = m.flops;
    n_parameters_col(idx) = m.n_parameters;
    train_time_col(idx) = m.train_time_s;
    infer_time_col(idx) = m.infer_time_us;

    roc_curves(idx).model_name = string(m.model_name);
    roc_curves(idx).fpr = m.roc_fpr;
    roc_curves(idx).tpr = m.roc_tpr;
    roc_curves(idx).auc = m.auc;
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

benchmark_results.Properties.UserData.roc_curves = roc_curves;

save_outputs = logical(get_param(params, 'save_outputs', true));
if save_outputs
    output_dir = char(get_param(params, 'results_dir', fullfile(pwd, 'results')));
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    save(fullfile(output_dir, 'benchmark_results_cp3.mat'), 'benchmark_results', 'roc_curves');
    writetable(benchmark_results, fullfile(output_dir, 'benchmark_results_cp3.csv'));
end
end

function metrics = benchmark_logistic_cp3(features, labels, params, cv)
params_local = params;
params_local.cv_partition = cv;
params_local.log10_rcp = false;

train_start = tic;
[model, norm_params] = train_logistic(features, labels, params_local);
train_time_s = toc(train_start);

eval_results = eval_roc_calibration(model, norm_params, features, labels, ...
    setfield(params_local, 'save_outputs', false)); %#ok<SFLD>

x_single = prepare_single_input_cp3(features, norm_params);
infer_time_us = measure_inference_time_cp3(@(x) predict_logistic_prob(model, x), x_single);

n_feat = size(features, 2);
metrics = struct();
metrics.model_name = 'Logistic';
metrics.auc = model.cv_auc;
metrics.accuracy = model.cv_accuracy;
metrics.f1 = eval_results.f1;
metrics.ece = eval_results.ece;
metrics.flops = get_param(params, 'logistic_flops_cp3', 2 * n_feat + 1);
metrics.n_parameters = numel(model.coefficients);
metrics.train_time_s = train_time_s;
metrics.infer_time_us = infer_time_us;
metrics.roc_fpr = eval_results.roc.fpr;
metrics.roc_tpr = eval_results.roc.tpr;
end

function metrics = benchmark_svm_cp3(features, labels, params, cv)
random_seed = get_param(params, 'random_seed', 42);
n_folds = cv.NumTestSets;
scores_oof = nan(size(labels));
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);

for fold_idx = 1:n_folds
    tr = training(cv, fold_idx);
    te = test(cv, fold_idx);

    x_train = features(tr, :);
    y_train = labels(tr);
    x_test = features(te, :);
    y_test = labels(te);

    [x_train_n, norm_info] = normalize_generic_cp3(x_train);
    x_test_n = apply_norm_generic_cp3(x_test, norm_info);

    rng(random_seed + fold_idx);
    svm_mdl = fitcsvm(x_train_n, y_train, 'KernelFunction', 'rbf', 'Standardize', true);
    svm_mdl = fitPosterior(svm_mdl);

    [~, score_fold] = predict(svm_mdl, x_test_n);
    prob_fold = get_positive_score_cp3(score_fold, svm_mdl.ClassNames);
    scores_oof(te) = prob_fold;

    m = binary_metrics_cp3(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = m.auc;
    acc_list(fold_idx) = m.accuracy;
    f1_list(fold_idx) = m.f1;
    ece_list(fold_idx) = m.ece;
end

train_start = tic;
[x_all_n, norm_all] = normalize_generic_cp3(features);
rng(random_seed);
svm_full = fitcsvm(x_all_n, labels, 'KernelFunction', 'rbf', 'Standardize', true);
svm_full = fitPosterior(svm_full);
train_time_s = toc(train_start);

n_sv = size(svm_full.SupportVectors, 1);
input_dim = size(features, 2);
flops = n_sv * (2 * input_dim + 1) + 1;
n_parameters = n_sv * input_dim + n_sv + 1;
infer_time_us = measure_inference_time_cp3(@(x) predict(svm_full, x), apply_norm_generic_cp3(features(1, :), norm_all));

[fpr_all, tpr_all, ~, auc_all] = perfcurve(labels, scores_oof, true);

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

function metrics = benchmark_rf_cp3(features, labels, params, cv)
num_trees = get_param(params, 'rf_num_trees', 100);
max_splits = get_param(params, 'rf_max_num_splits', 20);
n_folds = cv.NumTestSets;
scores_oof = nan(size(labels));
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);

for fold_idx = 1:n_folds
    tr = training(cv, fold_idx);
    te = test(cv, fold_idx);

    x_train = features(tr, :);
    y_train = labels(tr);
    x_test = features(te, :);
    y_test = labels(te);

    [x_train_n, norm_info] = normalize_generic_cp3(x_train);
    x_test_n = apply_norm_generic_cp3(x_test, norm_info);

    rf_mdl = fitcensemble(x_train_n, y_train, 'Method', 'Bag', ...
        'NumLearningCycles', num_trees, ...
        'Learners', templateTree('MaxNumSplits', max_splits));

    [~, score_fold] = predict(rf_mdl, x_test_n);
    prob_fold = get_positive_score_cp3(score_fold, rf_mdl.ClassNames);
    scores_oof(te) = prob_fold;

    m = binary_metrics_cp3(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = m.auc;
    acc_list(fold_idx) = m.accuracy;
    f1_list(fold_idx) = m.f1;
    ece_list(fold_idx) = m.ece;
end

train_start = tic;
[x_all_n, norm_all] = normalize_generic_cp3(features);
rf_full = fitcensemble(x_all_n, labels, 'Method', 'Bag', ...
    'NumLearningCycles', num_trees, ...
    'Learners', templateTree('MaxNumSplits', max_splits));
train_time_s = toc(train_start);

avg_depth = mean(cellfun(@tree_depth_cp3, rf_full.Trained));
flops = num_trees * avg_depth;
n_parameters = sum(cellfun(@(t) double(t.NumNodes), rf_full.Trained));
infer_time_us = measure_inference_time_cp3(@(x) predict(rf_full, x), apply_norm_generic_cp3(features(1, :), norm_all));

[fpr_all, tpr_all, ~, auc_all] = perfcurve(labels, scores_oof, true);

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

function metrics = benchmark_lda_cp3(features, labels, params, cv)
n_folds = cv.NumTestSets;
scores_oof = nan(size(labels));
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);

for fold_idx = 1:n_folds
    tr = training(cv, fold_idx);
    te = test(cv, fold_idx);

    x_train = features(tr, :);
    y_train = labels(tr);
    x_test = features(te, :);
    y_test = labels(te);

    [x_train_n, norm_info] = normalize_generic_cp3(x_train);
    x_test_n = apply_norm_generic_cp3(x_test, norm_info);

    mdl = fitcdiscr(x_train_n, y_train, 'DiscrimType', 'linear');
    [~, score_fold] = predict(mdl, x_test_n);
    prob_fold = get_positive_score_cp3(score_fold, mdl.ClassNames);
    scores_oof(te) = prob_fold;

    m = binary_metrics_cp3(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = m.auc;
    acc_list(fold_idx) = m.accuracy;
    f1_list(fold_idx) = m.f1;
    ece_list(fold_idx) = m.ece;
end

train_start = tic;
[x_all_n, norm_all] = normalize_generic_cp3(features);
mdl_full = fitcdiscr(x_all_n, labels, 'DiscrimType', 'linear');
train_time_s = toc(train_start);

input_dim = size(features, 2);
flops = 2 * input_dim + 1;
n_parameters = (2 * input_dim) + (input_dim * (input_dim + 1) / 2);
infer_time_us = measure_inference_time_cp3(@(x) predict(mdl_full, x), apply_norm_generic_cp3(features(1, :), norm_all));

[fpr_all, tpr_all, ~, auc_all] = perfcurve(labels, scores_oof, true);

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

function metrics = benchmark_linear_svm_cp3(features, labels, params, cv)
random_seed = get_param(params, 'random_seed', 42);
n_folds = cv.NumTestSets;
scores_oof = nan(size(labels));
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);

for fold_idx = 1:n_folds
    tr = training(cv, fold_idx);
    te = test(cv, fold_idx);

    x_train = features(tr, :);
    y_train = labels(tr);
    x_test = features(te, :);
    y_test = labels(te);

    [x_train_n, norm_info] = normalize_generic_cp3(x_train);
    x_test_n = apply_norm_generic_cp3(x_test, norm_info);

    rng(random_seed + fold_idx);
    mdl = fitcsvm(x_train_n, y_train, 'KernelFunction', 'linear', 'Standardize', true);
    mdl = fitPosterior(mdl);

    [~, score_fold] = predict(mdl, x_test_n);
    prob_fold = get_positive_score_cp3(score_fold, mdl.ClassNames);
    scores_oof(te) = prob_fold;

    m = binary_metrics_cp3(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = m.auc;
    acc_list(fold_idx) = m.accuracy;
    f1_list(fold_idx) = m.f1;
    ece_list(fold_idx) = m.ece;
end

train_start = tic;
[x_all_n, norm_all] = normalize_generic_cp3(features);
rng(random_seed);
mdl_full = fitcsvm(x_all_n, labels, 'KernelFunction', 'linear', 'Standardize', true);
mdl_full = fitPosterior(mdl_full);
train_time_s = toc(train_start);

input_dim = size(features, 2);
flops = 2 * input_dim + 1;
n_parameters = input_dim + 1;
infer_time_us = measure_inference_time_cp3(@(x) predict(mdl_full, x), apply_norm_generic_cp3(features(1, :), norm_all));

[fpr_all, tpr_all, ~, auc_all] = perfcurve(labels, scores_oof, true);

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

function metrics = benchmark_dnn_cp3(features, labels, params, cv)
max_epochs = get_param(params, 'dnn_max_epochs', 100);
mini_batch = get_param(params, 'dnn_mini_batch', 32);
random_seed = get_param(params, 'random_seed', 42);
n_folds = cv.NumTestSets;
scores_oof = nan(size(labels));
auc_list = nan(n_folds, 1);
acc_list = nan(n_folds, 1);
f1_list = nan(n_folds, 1);
ece_list = nan(n_folds, 1);

for fold_idx = 1:n_folds
    tr = training(cv, fold_idx);
    te = test(cv, fold_idx);

    x_train = features(tr, :);
    y_train = labels(tr);
    x_test = features(te, :);
    y_test = labels(te);

    [x_train_n, norm_info] = normalize_generic_cp3(x_train);
    x_test_n = apply_norm_generic_cp3(x_test, norm_info);

    rng(random_seed + fold_idx);
    dnn_mdl = train_dnn_model_cp3(x_train_n, y_train, size(features, 2), max_epochs, mini_batch);
    score_fold = predict(dnn_mdl, x_test_n);
    prob_fold = get_positive_score_cp3(score_fold, dnn_mdl.Layers(end).Classes);
    scores_oof(te) = prob_fold;

    m = binary_metrics_cp3(prob_fold, y_test, get_param(params, 'ece_num_bins', 10));
    auc_list(fold_idx) = m.auc;
    acc_list(fold_idx) = m.accuracy;
    f1_list(fold_idx) = m.f1;
    ece_list(fold_idx) = m.ece;
end

train_start = tic;
[x_all_n, norm_all] = normalize_generic_cp3(features);
rng(random_seed);
dnn_full = train_dnn_model_cp3(x_all_n, labels, size(features, 2), max_epochs, mini_batch);
train_time_s = toc(train_start);

input_dim = size(features, 2);
flops = get_param(params, 'dnn_flops_cp3', (input_dim * 16) + (16 * 8) + (8 * 2));
n_parameters = get_param(params, 'dnn_n_parameters_cp3', flops);
infer_time_us = measure_inference_time_cp3(@(x) predict(dnn_full, x), apply_norm_generic_cp3(features(1, :), norm_all));

[fpr_all, tpr_all, ~, auc_all] = perfcurve(labels, scores_oof, true);

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

function dnn_mdl = train_dnn_model_cp3(x_train, y_train, input_dim, max_epochs, mini_batch)
if size(x_train, 1) ~= numel(y_train)
    error('[run_ml_benchmark_cp3] DNN train size mismatch.');
end

layers = [ ...
    featureInputLayer(input_dim)
    fullyConnectedLayer(16)
    reluLayer
    fullyConnectedLayer(8)
    reluLayer
    fullyConnectedLayer(2)
    softmaxLayer
    classificationLayer];

y_cat = categorical(y_train);
options = trainingOptions('adam', ...
    'MaxEpochs', max_epochs, ...
    'MiniBatchSize', mini_batch, ...
    'Verbose', false, ...
    'Plots', 'none');

dnn_mdl = trainNetwork(x_train, y_cat, layers, options);
end

function metrics = empty_metrics_cp3(model_name)
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

function [x_norm, info] = normalize_generic_cp3(x)
mu = mean(x, 1, 'omitnan');
sigma = std(x, 0, 1, 'omitnan');
sigma(sigma == 0) = 1;
x_norm = (x - mu) ./ sigma;
info = struct('mean_values', mu, 'std_values', sigma);
end

function x_out = apply_norm_generic_cp3(x, info)
x_out = (x - info.mean_values) ./ info.std_values;
end

function prob = get_positive_score_cp3(score_matrix, class_names)
if numel(class_names) ~= 2
    error('[run_ml_benchmark_cp3] binary class names expected.');
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

function out = binary_metrics_cp3(prob, labels, n_bins)
[~, ~, ~, auc] = perfcurve(labels, prob, true);
y_hat = prob >= 0.5;
accuracy = mean(y_hat == labels);

tp = sum(y_hat & labels);
fp = sum(y_hat & ~labels);
fn = sum(~y_hat & labels);
precision = tp / max(tp + fp, eps);
recall = tp / max(tp + fn, eps);
f1 = 2 * precision * recall / max(precision + recall, eps);

ece = compute_ece_cp3(prob, labels, n_bins);
out = struct('auc', auc, 'accuracy', accuracy, 'f1', f1, 'ece', ece);
end

function ece = compute_ece_cp3(prob, labels, n_bins)
bin_edges = linspace(0, 1, n_bins + 1);
ece = 0;
n_total = numel(prob);

for b = 1:n_bins
    if b < n_bins
        in_bin = prob >= bin_edges(b) & prob < bin_edges(b + 1);
    else
        in_bin = prob >= bin_edges(b) & prob <= bin_edges(b + 1);
    end
    n_bin = sum(in_bin);
    if n_bin == 0
        continue;
    end
    ece = ece + (n_bin / n_total) * abs(mean(prob(in_bin)) - mean(labels(in_bin)));
end
end

function depth = tree_depth_cp3(tree_obj)
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

function infer_time_us = measure_inference_time_cp3(predict_fn, sample_input)
n_repeat = 1000;
for w = 1:10
    predict_fn(sample_input);
end
tic_id = tic;
for k = 1:n_repeat
    predict_fn(sample_input);
end
infer_time_us = toc(tic_id) / n_repeat * 1e6;
end

function x_single = prepare_single_input_cp3(features, norm_params)
x_single = double(features(1, :));
if isfield(norm_params, 'normalize') && logical(norm_params.normalize)
    x_single = (x_single - norm_params.mean_values) ./ norm_params.std_values;
end
end
