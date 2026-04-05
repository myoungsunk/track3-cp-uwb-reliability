function [model, norm_params] = train_logistic(features, labels, params)
% TRAIN_LOGISTIC Train binary logistic regression with stratified K-fold CV.
if nargin < 3
    params = struct();
end

features = double(features);
labels = logical(labels(:));

if size(features, 1) ~= numel(labels)
    error('[train_logistic] features rows and labels length must match.');
end
if size(features, 2) < 1
    error('[train_logistic] features must have at least one column.');
end

valid_mask = all(isfinite(features), 2) & isfinite(double(labels));
features = features(valid_mask, :);
labels = labels(valid_mask);

if numel(unique(labels)) < 2
    error('[train_logistic] labels must contain both classes.');
end

random_seed = get_param(params, 'random_seed', 42);
cv_folds = get_param(params, 'cv_folds', 5);
normalize = logical(get_param(params, 'normalize', true));
log10_rcp = logical(get_param(params, 'log10_rcp', true));

features_proc = features;
if log10_rcp
    if any(features_proc(:, 1) <= 0)
        error('[train_logistic] r_CP values must be > 0 for log10 transform.');
    end
    features_proc(:, 1) = log10(features_proc(:, 1));
end

if isfield(params, 'cv_partition') && isa(params.cv_partition, 'cvpartition')
    cv = params.cv_partition;
    if cv.NumObservations ~= numel(labels)
        error('[train_logistic] params.cv_partition observation count mismatch.');
    end
else
    rng(random_seed);
    cv = cvpartition(labels, 'KFold', cv_folds);
end

n_folds = cv.NumTestSets;
cv_auc_list = nan(n_folds, 1);
cv_acc_list = nan(n_folds, 1);

for fold_idx = 1:n_folds
    train_idx = training(cv, fold_idx);
    test_idx = test(cv, fold_idx);

    x_train = features_proc(train_idx, :);
    y_train = labels(train_idx);
    x_test = features_proc(test_idx, :);
    y_test = labels(test_idx);

    [x_train_norm, norm_fold] = normalize_features(x_train, normalize);
    x_test_norm = apply_normalization(x_test, norm_fold, normalize);

    mdl_fold = fit_logistic_model(x_train_norm, y_train);
    p_fold = predict(mdl_fold, array2table(x_test_norm, 'VariableNames', predictor_names(size(x_test_norm, 2))));

    [~, ~, ~, fold_auc] = perfcurve(y_test, p_fold, true);
    y_hat_fold = p_fold >= 0.5;

    cv_auc_list(fold_idx) = fold_auc;
    cv_acc_list(fold_idx) = mean(y_hat_fold == y_test);
end

[x_all_norm, norm_all] = normalize_features(features_proc, normalize);
mdl_full = fit_logistic_model(x_all_norm, labels);

coefs = mdl_full.Coefficients.Estimate;
model = struct();
model.coefficients = coefs;
model.cv_auc = mean(cv_auc_list, 'omitnan');
model.cv_accuracy = mean(cv_acc_list, 'omitnan');
model.cv_auc_per_fold = cv_auc_list;
model.cv_accuracy_per_fold = cv_acc_list;
model.mdl_object = mdl_full;
model.predictor_names = predictor_names(size(features_proc, 2));
model.log10_rcp = log10_rcp;
model.normalize = normalize;
model.norm_mean_values = norm_all.mean_values;
model.norm_std_values = norm_all.std_values;

norm_params = struct();
norm_params.mean_values = norm_all.mean_values;
norm_params.std_values = norm_all.std_values;
norm_params.normalize = normalize;
norm_params.log10_rcp = log10_rcp;

if numel(norm_all.mean_values) >= 1
    norm_params.mean_rcp = norm_all.mean_values(1);
    norm_params.std_rcp = norm_all.std_values(1);
else
    norm_params.mean_rcp = NaN;
    norm_params.std_rcp = NaN;
end
if numel(norm_all.mean_values) >= 2
    norm_params.mean_afp = norm_all.mean_values(2);
    norm_params.std_afp = norm_all.std_values(2);
else
    norm_params.mean_afp = NaN;
    norm_params.std_afp = NaN;
end
end

function mdl = fit_logistic_model(x_norm, y)
tbl = array2table(x_norm, 'VariableNames', predictor_names(size(x_norm, 2)));
tbl.label = y;
formula = sprintf('label ~ %s', strjoin(tbl.Properties.VariableNames(1:end-1), ' + '));
mdl = fitglm(tbl, formula, 'Distribution', 'binomial');
end

function names = predictor_names(n_features)
if n_features == 1
    names = {'x1'};
elseif n_features == 2
    names = {'rcp_norm', 'afp_norm'};
else
    names = arrayfun(@(k) sprintf('x%d', k), 1:n_features, 'UniformOutput', false);
end
end

function [x_norm, info] = normalize_features(x, use_normalize)
if use_normalize
    mean_values = mean(x, 1, 'omitnan');
    std_values = std(x, 0, 1, 'omitnan');
    std_values(std_values == 0) = 1;
    x_norm = (x - mean_values) ./ std_values;
else
    mean_values = zeros(1, size(x, 2));
    std_values = ones(1, size(x, 2));
    x_norm = x;
end

info = struct();
info.mean_values = mean_values;
info.std_values = std_values;
end

function x_out = apply_normalization(x, info, use_normalize)
if use_normalize
    x_out = (x - info.mean_values) ./ info.std_values;
else
    x_out = x;
end
end
