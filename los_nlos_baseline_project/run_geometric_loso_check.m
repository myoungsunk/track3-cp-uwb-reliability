function outputs = run_geometric_loso_check(cfg_override)
% RUN_GEOMETRIC_LOSO_CHECK
% Leave-one-scenario-out validation for geometric CP7 paired comparison.

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);

cfg = default_config(script_dir, project_root);
if nargin >= 1 && isstruct(cfg_override)
    cfg = merge_config(cfg, cfg_override);
end

ensure_dir(cfg.results_dir);

dataset_csv = fullfile(cfg.reviewer_results_dir, 'geometric', 'cp7_target_dataset.csv');
if ~isfile(dataset_csv)
    error('[run_geometric_loso_check] Missing dataset CSV: %s', dataset_csv);
end

dataset_table = readtable(dataset_csv, 'TextType', 'string');
dataset_table.scenario = string(dataset_table.scenario);
dataset_table.case_name = string(dataset_table.case_name);
dataset_table.valid_for_cp7_model = logical(dataset_table.valid_for_cp7_model);
dataset_table.label = logical(dataset_table.label);

valid_mask = dataset_table.valid_for_cp7_model & ismember(dataset_table.scenario, ["B", "C"]);
dataset_table = dataset_table(valid_mask, :);
dataset_table = sortrows(dataset_table, {'scenario', 'pos_id'}, {'ascend', 'ascend'});

writetable(dataset_table, fullfile(cfg.results_dir, 'cp7_target_dataset_valid_bc.csv'));

directions = { ...
    struct('train_scenario', "B", 'test_scenario', "C"), ...
    struct('train_scenario', "C", 'test_scenario', "B")};

summary_table = table();
prediction_table = table();
mcnemar_table = table();

for idx = 1:numel(directions)
    direction_cfg = directions{idx};
    result = evaluate_direction(dataset_table, direction_cfg.train_scenario, direction_cfg.test_scenario, cfg);
    summary_table = [summary_table; result.summary_row]; %#ok<AGROW>
    prediction_table = [prediction_table; result.prediction_table]; %#ok<AGROW>
    mcnemar_table = [mcnemar_table; result.mcnemar_row]; %#ok<AGROW>
end

writetable(summary_table, fullfile(cfg.results_dir, 'loso_summary.csv'));
writetable(prediction_table, fullfile(cfg.results_dir, 'loso_predictions.csv'));
writetable(mcnemar_table, fullfile(cfg.results_dir, 'loso_mcnemar.csv'));

write_report(cfg, summary_table, mcnemar_table);

outputs = struct();
outputs.config = cfg;
outputs.summary_table = summary_table;
outputs.prediction_table = prediction_table;
outputs.mcnemar_table = mcnemar_table;

save(fullfile(cfg.results_dir, 'geometric_loso_check_outputs.mat'), 'outputs', '-v7.3');
end

function cfg = default_config(script_dir, project_root)
cfg = struct();
cfg.script_dir = script_dir;
cfg.project_root = project_root;
cfg.bundle_root = fullfile(script_dir, 'results', 'geometric_l1_support_bundle_20260413');
cfg.reviewer_results_dir = fullfile(cfg.bundle_root, '01_reviewer_rerun');
cfg.results_dir = fullfile(cfg.bundle_root, '05_loso_generalization_check');
cfg.logistic_lambda = 1e-2;
cfg.classification_threshold = 0.5;
cfg.baseline_features = { ...
    'fp_energy_db', ...
    'skewness_pdp', ...
    'kurtosis_pdp', ...
    'mean_excess_delay_ns', ...
    'rms_delay_spread_ns'};
cfg.cp7_features = { ...
    'gamma_CP_rx1', ...
    'gamma_CP_rx2', ...
    'a_FP_RHCP_rx1', ...
    'a_FP_LHCP_rx1', ...
    'a_FP_RHCP_rx2', ...
    'a_FP_LHCP_rx2'};
cfg.proposed_features = [cfg.baseline_features, cfg.cp7_features];
end

function cfg = merge_config(cfg, override)
names = fieldnames(override);
for idx = 1:numel(names)
    cfg.(names{idx}) = override.(names{idx});
end
end

function ensure_dir(dirpath)
if ~exist(dirpath, 'dir')
    mkdir(dirpath);
end
end

function result = evaluate_direction(dataset_table, train_scenario, test_scenario, cfg)
train_mask = dataset_table.scenario == string(train_scenario);
test_mask = dataset_table.scenario == string(test_scenario);

train_table = dataset_table(train_mask, :);
test_table = dataset_table(test_mask, :);
labels_test = logical(test_table.label);

baseline_eval = fit_and_predict(train_table, test_table, cfg.baseline_features, "baseline", cfg);
proposed_eval = fit_and_predict(train_table, test_table, cfg.proposed_features, "proposed", cfg);

base_metrics = metrics_table_from_vectors(labels_test, baseline_eval.score, baseline_eval.pred, "baseline");
prop_metrics = metrics_table_from_vectors(labels_test, proposed_eval.score, proposed_eval.pred, "proposed");

direction_name = string(train_scenario) + "_to_" + string(test_scenario);
summary_row = table();
summary_row.direction = direction_name;
summary_row.train_scenario = string(train_scenario);
summary_row.test_scenario = string(test_scenario);
summary_row.n_train = height(train_table);
summary_row.n_test = height(test_table);
summary_row.n_los_train = sum(train_table.label);
summary_row.n_nlos_train = sum(~train_table.label);
summary_row.n_los_test = sum(test_table.label);
summary_row.n_nlos_test = sum(~test_table.label);
summary_row.baseline_auc = base_metrics.auc;
summary_row.proposed_auc = prop_metrics.auc;
summary_row.delta_auc = prop_metrics.auc - base_metrics.auc;
summary_row.baseline_accuracy = base_metrics.accuracy;
summary_row.proposed_accuracy = prop_metrics.accuracy;
summary_row.delta_accuracy = prop_metrics.accuracy - base_metrics.accuracy;
summary_row.baseline_brier = base_metrics.brier_score;
summary_row.proposed_brier = prop_metrics.brier_score;
summary_row.delta_brier = prop_metrics.brier_score - base_metrics.brier_score;
summary_row.baseline_fp = base_metrics.fp;
summary_row.proposed_fp = prop_metrics.fp;
summary_row.baseline_fn = base_metrics.fn;
summary_row.proposed_fn = prop_metrics.fn;

[b_count, c_count, p_exact] = exact_mcnemar(labels_test, baseline_eval.pred, proposed_eval.pred);
mcnemar_row = table();
mcnemar_row.direction = direction_name;
mcnemar_row.train_scenario = string(train_scenario);
mcnemar_row.test_scenario = string(test_scenario);
mcnemar_row.baseline_correct_proposed_wrong = b_count;
mcnemar_row.baseline_wrong_proposed_correct = c_count;
mcnemar_row.p_value_exact = p_exact;

prediction_table = table();
prediction_table.direction = repmat(direction_name, height(test_table), 1);
prediction_table.train_scenario = repmat(string(train_scenario), height(test_table), 1);
prediction_table.test_scenario = repmat(string(test_scenario), height(test_table), 1);
prediction_table.case_name = string(test_table.case_name);
prediction_table.scenario = string(test_table.scenario);
prediction_table.pos_id = test_table.pos_id;
prediction_table.x_m = test_table.x_m;
prediction_table.y_m = test_table.y_m;
prediction_table.label = labels_test;
prediction_table.baseline_score = baseline_eval.score;
prediction_table.baseline_pred = baseline_eval.pred;
prediction_table.proposed_score = proposed_eval.score;
prediction_table.proposed_pred = proposed_eval.pred;
prediction_table.baseline_correct = baseline_eval.pred == labels_test;
prediction_table.proposed_correct = proposed_eval.pred == labels_test;

result = struct();
result.summary_row = summary_row;
result.mcnemar_row = mcnemar_row;
result.prediction_table = prediction_table;
end

function eval_out = fit_and_predict(train_table, test_table, feature_names, model_name, cfg)
X_train = double(train_table{:, feature_names});
y_train = logical(train_table.label);
X_test = double(test_table{:, feature_names});

[X_train_norm, norm_params] = normalize_training_matrix(X_train);
X_test_norm = apply_normalization(X_test, norm_params);

model = fit_logistic_model(X_train_norm, y_train, cfg);
model.feature_names = string(feature_names(:));
score = predict_with_model(model, X_test_norm);
pred = score >= cfg.classification_threshold;

eval_out = struct();
eval_out.model_name = string(model_name);
eval_out.score = score;
eval_out.pred = pred;
eval_out.model = model;
end

function [X_norm, params] = normalize_training_matrix(X)
mean_values = mean(X, 1, 'omitnan');
std_values = std(X, 0, 1, 'omitnan');
std_values(~isfinite(std_values) | std_values == 0) = 1;
X_norm = (X - mean_values) ./ std_values;
params = struct();
params.mean_values = mean_values;
params.std_values = std_values;
end

function X_norm = apply_normalization(X, params)
X_norm = (X - params.mean_values) ./ params.std_values;
end

function model = fit_logistic_model(X, y, cfg)
weights = compute_class_weights(y);
model = struct();

try
    mdl = fitclinear(X, y, ...
        'Learner', 'logistic', ...
        'Regularization', 'ridge', ...
        'Lambda', cfg.logistic_lambda, ...
        'Solver', 'lbfgs', ...
        'Weights', weights);

    model.backend = "fitclinear";
    model.mdl_object = mdl;
catch exception_info
    warning('[run_geometric_loso_check] fitclinear failed (%s). Falling back to fitglm.', ...
        exception_info.message);

    predictor_names = make_predictor_names(size(X, 2));
    train_table = array2table(X, 'VariableNames', predictor_names);
    train_table.label = y;
    mdl = fitglm(train_table, 'label ~ .', 'Distribution', 'binomial', 'Weights', weights);

    model.backend = "fitglm";
    model.mdl_object = mdl;
    model.predictor_names = predictor_names;
end
end

function weights = compute_class_weights(y)
y = logical(y(:));
n_total = numel(y);
n_pos = sum(y);
n_neg = sum(~y);
weights = ones(n_total, 1);
if n_pos == 0 || n_neg == 0
    return;
end
weights(y) = 0.5 * n_total / n_pos;
weights(~y) = 0.5 * n_total / n_neg;
end

function predictor_names = make_predictor_names(n_feature)
predictor_names = arrayfun(@(idx) sprintf('x%d', idx), 1:n_feature, 'UniformOutput', false);
end

function score = predict_with_model(model, X_norm)
switch string(model.backend)
    case "fitclinear"
        linear_score = X_norm * double(model.mdl_object.Beta(:)) + double(model.mdl_object.Bias);
        score = logistic_sigmoid(linear_score);
    case "fitglm"
        predict_table = array2table(X_norm, 'VariableNames', model.predictor_names);
        score = predict(model.mdl_object, predict_table);
    otherwise
        error('[run_geometric_loso_check] Unsupported backend: %s', string(model.backend));
end
end

function y = logistic_sigmoid(x)
x = max(min(double(x), 60), -60);
y = 1 ./ (1 + exp(-x));
end

function row = metrics_table_from_vectors(labels, scores, predictions, group_name)
labels = logical(labels(:));
scores = double(scores(:));
predictions = logical(predictions(:));

n_samples = numel(labels);
tp = sum(predictions & labels);
tn = sum(~predictions & ~labels);
fp = sum(predictions & ~labels);
fn = sum(~predictions & labels);

accuracy = safe_divide(tp + tn, n_samples);
precision = safe_divide(tp, tp + fp);
recall = safe_divide(tp, tp + fn);
specificity = safe_divide(tn, tn + fp);
f1_score = safe_divide(2 * precision * recall, precision + recall);
balanced_accuracy = mean([recall, specificity], 'omitnan');
brier_score = mean((scores - double(labels)) .^ 2, 'omitnan');

if numel(unique(labels)) >= 2
    [~, ~, ~, auc] = perfcurve(labels, scores, true);
else
    auc = NaN;
end

row = table();
row.group_name = string(group_name);
row.n_samples = n_samples;
row.n_los = sum(labels);
row.n_nlos = sum(~labels);
row.accuracy = accuracy;
row.precision = precision;
row.recall = recall;
row.specificity = specificity;
row.f1_score = f1_score;
row.balanced_accuracy = balanced_accuracy;
row.auc = auc;
row.brier_score = brier_score;
row.tp = tp;
row.tn = tn;
row.fp = fp;
row.fn = fn;
end

function value = safe_divide(num, den)
if den == 0
    value = NaN;
else
    value = num / den;
end
end

function [b_count, c_count, p_exact] = exact_mcnemar(labels, baseline_pred, proposed_pred)
labels = logical(labels(:));
baseline_pred = logical(baseline_pred(:));
proposed_pred = logical(proposed_pred(:));

baseline_correct = baseline_pred == labels;
proposed_correct = proposed_pred == labels;

b_count = sum(baseline_correct & ~proposed_correct);
c_count = sum(~baseline_correct & proposed_correct);
n_discordant = b_count + c_count;

if n_discordant == 0
    p_exact = 1.0;
else
    p_exact = 2 * binocdf(min(b_count, c_count), n_discordant, 0.5);
    p_exact = min(1.0, p_exact);
end
end

function write_report(cfg, summary_table, mcnemar_table)
lines = {};
lines{end+1} = '# Geometric LOSO Generalization Check';
lines{end+1} = '';
lines{end+1} = '## Purpose';
lines{end+1} = '';
lines{end+1} = '- Evaluate whether CP7 gains remain when the model is trained on one scenario and tested on the other scenario.';
lines{end+1} = '- Provide directional evidence for cross-environment generalization beyond same-fold paired CV and spatial CV.';
lines{end+1} = '';
lines{end+1} = '## Setup';
lines{end+1} = '';
lines{end+1} = '- Dataset: CP7-capable B+C subset';
lines{end+1} = '- Baseline: 5-feature CIR model';
lines{end+1} = '- Proposed: baseline + 6 CP7 features';
lines{end+1} = '- Training normalization was fit only on the training scenario and then applied to the held-out scenario.';
lines{end+1} = '- Logistic learner: ridge regularized logistic with class-balanced weights and lambda `1e-2`.';
lines{end+1} = '';
lines{end+1} = '## Results';
lines{end+1} = '';

for idx = 1:height(summary_table)
    row = summary_table(idx, :);
    mc_row = mcnemar_table(mcnemar_table.direction == row.direction, :);
    lines{end+1} = sprintf('- `%s`: baseline AUC `%.4f`, proposed AUC `%.4f`, delta AUC `%.4f`, baseline Brier `%.4f`, proposed Brier `%.4f`, exact McNemar p `%.4f`.', ...
        row.direction, row.baseline_auc, row.proposed_auc, row.delta_auc, row.baseline_brier, row.proposed_brier, mc_row.p_value_exact);
end

lines{end+1} = '';
lines{end+1} = '## Interpretation';
lines{end+1} = '';
lines{end+1} = '- Improvement in both directions supports the claim that CP7 information is not tied to a single scenario split.';
lines{end+1} = '- These numbers should be used as robustness evidence rather than the primary headline metric.';

write_text_file(fullfile(cfg.results_dir, 'loso_report.md'), strjoin(lines, newline));
end

function write_text_file(filepath, text_content)
fid = fopen(filepath, 'w');
if fid < 0
    error('[run_geometric_loso_check] Failed to open file: %s', filepath);
end
cleanup_obj = onCleanup(@() fclose(fid));
fprintf(fid, '%s', text_content);
clear cleanup_obj;
end
