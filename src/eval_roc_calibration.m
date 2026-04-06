function results = eval_roc_calibration(model, norm_params, features, labels, params)
% EVAL_ROC_CALIBRATION Evaluate ROC, threshold metrics, calibration, and FLOPs.
if nargin < 5
    params = struct();
end

features = double(features);
labels = logical(labels(:));

if size(features, 1) ~= numel(labels)
    error('[eval_roc_calibration] features rows and labels length must match.');
end

valid_mask = all(isfinite(features), 2);
features = features(valid_mask, :);
labels = labels(valid_mask);

if isfield(norm_params, 'log10_rcp') && logical(norm_params.log10_rcp)
    if any(features(:, 1) <= 0)
        error('[eval_roc_calibration] r_CP values must be > 0 for log10 transform.');
    end
    features(:, 1) = log10(features(:, 1));
end

if isfield(norm_params, 'normalize') && logical(norm_params.normalize)
    mean_values = norm_params.mean_values;
    std_values = norm_params.std_values;
    std_values(std_values == 0) = 1;
    features_norm = (features - mean_values) ./ std_values;
else
    features_norm = features;
end

predicted_prob = predict_logistic_prob(model, features_norm);

[fpr, tpr, thresholds, auc] = perfcurve(labels, predicted_prob, true);
youden_j = tpr - fpr;
[~, best_idx] = max(youden_j);
optimal_threshold = thresholds(best_idx);

y_pred = predicted_prob >= optimal_threshold;
accuracy = mean(y_pred == labels);

true_pos = sum(y_pred & labels);
false_pos = sum(y_pred & ~labels);
false_neg = sum(~y_pred & labels);

precision = true_pos / max(true_pos + false_pos, eps);
recall = true_pos / max(true_pos + false_neg, eps);
f1 = 2 * precision * recall / max(precision + recall, eps);

[ece, cal_curve] = compute_ece_curve(predicted_prob, labels, get_param(params, 'ece_num_bins', 10));

logistic_flops = get_param(params, 'logistic_flops', 5);

results = struct();
results.roc = struct('fpr', fpr, 'tpr', tpr, 'auc', auc, 'thresholds', thresholds, 'optimal_threshold', optimal_threshold);
results.accuracy = accuracy;
results.f1 = f1;
results.precision = precision;
results.recall = recall;
results.ece = ece;
results.cal_curve = cal_curve;
results.flops = logistic_flops;
results.predicted_prob = predicted_prob;

save_outputs = logical(get_param(params, 'save_outputs', false));
if save_outputs
    output_dir = char(get_param(params, 'results_dir', fullfile(pwd, 'results')));
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end

    metrics_table = table(auc, optimal_threshold, accuracy, f1, precision, recall, ece, logistic_flops, ...
        'VariableNames', {'auc', 'optimal_threshold', 'accuracy', 'f1', 'precision', 'recall', 'ece', 'flops'});

    save(fullfile(output_dir, 'eval_roc_calibration.mat'), 'results');
    writetable(metrics_table, fullfile(output_dir, 'eval_roc_calibration.csv'));
end
end

function [ece, cal_curve] = compute_ece_curve(prob, labels, n_bins)
prob = double(prob(:));
labels = logical(labels(:));

bin_edges = linspace(0, 1, n_bins + 1);
mean_predicted = nan(n_bins, 1);
fraction_positive = nan(n_bins, 1);
bin_count = zeros(n_bins, 1);

ece = 0;
n_total = numel(prob);

for bin_idx = 1:n_bins
    left_edge = bin_edges(bin_idx);
    right_edge = bin_edges(bin_idx + 1);

    if bin_idx < n_bins
        in_bin = (prob >= left_edge) & (prob < right_edge);
    else
        in_bin = (prob >= left_edge) & (prob <= right_edge);
    end

    count_bin = sum(in_bin);
    bin_count(bin_idx) = count_bin;

    if count_bin == 0
        continue;
    end

    avg_pred_bin = mean(prob(in_bin));
    frac_pos_bin = mean(labels(in_bin));

    mean_predicted(bin_idx) = avg_pred_bin;
    fraction_positive(bin_idx) = frac_pos_bin;

    ece = ece + (count_bin / n_total) * abs(avg_pred_bin - frac_pos_bin);
end

cal_curve = struct();
cal_curve.mean_predicted = mean_predicted;
cal_curve.fraction_positive = fraction_positive;
cal_curve.bin_count = bin_count;
cal_curve.bin_edges = bin_edges(:);
end
