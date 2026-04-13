function outputs = run_geometric_l1_support_bundle(cfg_override)
% RUN_GEOMETRIC_L1_SUPPORT_BUNDLE
% Re-runs geometric evidence stages and adds an L1-regularized logistic check.

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);

cfg = default_config(script_dir, project_root);
if nargin >= 1 && isstruct(cfg_override)
    cfg = merge_config(cfg, cfg_override);
end

ensure_dir(cfg.bundle_root);
ensure_dir(cfg.stage00_execution_dir);
ensure_dir(cfg.stage01_reviewer_dir);
ensure_dir(cfg.stage02_priority_dir);
ensure_dir(cfg.stage03_l1_dir);
ensure_dir(cfg.stage04_report_dir);

fprintf('=== Geometric L1 Support Bundle ===\n');
fprintf('Bundle root: %s\n', cfg.bundle_root);

outputs = struct();
outputs.config = cfg;
outputs.started_at = datetime('now');

fprintf('\n[1/4] Re-running reviewer diagnostics...\n');
reviewer_cfg = struct();
reviewer_cfg.targets = ["material", "geometric"];
reviewer_cfg.results_dir = cfg.stage01_reviewer_dir;
reviewer_outputs = run_cp7_reviewer_diagnostics(reviewer_cfg);

fprintf('\n[2/4] Re-running priority validations...\n');
priority_cfg = struct();
priority_cfg.targets = "geometric";
priority_cfg.reviewer_results_dir = cfg.stage01_reviewer_dir;
priority_cfg.results_dir = cfg.stage02_priority_dir;
priority_outputs = run_cp7_priority_validations(priority_cfg);

fprintf('\n[3/4] Running L1-regularized logistic check...\n');
l1_outputs = run_l1_check(cfg);

fprintf('\n[4/4] Writing execution notes and summary report...\n');
write_execution_conditions(cfg);
write_summary_report(cfg, l1_outputs);
write_file_manifest(cfg);

outputs.reviewer = reviewer_outputs;
outputs.priority = priority_outputs;
outputs.l1 = l1_outputs;
outputs.completed_at = datetime('now');

save(fullfile(cfg.bundle_root, 'geometric_l1_support_bundle_outputs.mat'), 'outputs', '-v7.3');
fprintf('Saved bundle under %s\n', cfg.bundle_root);
end

function cfg = default_config(script_dir, project_root)
cfg = struct();
cfg.script_dir = script_dir;
cfg.project_root = project_root;

cfg.bundle_root = fullfile(script_dir, 'results', 'geometric_l1_support_bundle_20260413');
cfg.stage00_execution_dir = fullfile(cfg.bundle_root, '00_execution_conditions');
cfg.stage01_reviewer_dir = fullfile(cfg.bundle_root, '01_reviewer_rerun');
cfg.stage02_priority_dir = fullfile(cfg.bundle_root, '02_priority_rerun');
cfg.stage03_l1_dir = fullfile(cfg.bundle_root, '03_l1_regularization_check');
cfg.stage04_report_dir = fullfile(cfg.bundle_root, '04_report');

cfg.random_seed = 42;
cfg.cv_folds = 5;
cfg.classification_threshold = 0.5;
cfg.l1_num_lambda = 25;
cfg.l1_lambda_ratio = 1e-3;
cfg.repro_command = 'matlab -batch "cd(''los_nlos_baseline_project''); outputs = run_geometric_l1_support_bundle();"';

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
cfg.cp7_focus_features = {'gamma_CP_rx1', 'gamma_CP_rx2', 'a_FP_LHCP_rx1', 'a_FP_LHCP_rx2'};
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

function l1_outputs = run_l1_check(cfg)
dataset_csv = fullfile(cfg.stage01_reviewer_dir, 'geometric', 'cp7_target_dataset.csv');
if ~isfile(dataset_csv)
    error('[run_geometric_l1_support_bundle] Missing reviewer dataset: %s', dataset_csv);
end

dataset_table = readtable(dataset_csv, 'TextType', 'string');
dataset_table.case_name = string(dataset_table.case_name);
dataset_table.scenario = string(dataset_table.scenario);
dataset_table.polarization = string(dataset_table.polarization);
dataset_table.valid_for_cp7_model = logical(dataset_table.valid_for_cp7_model);
dataset_table.label = logical(dataset_table.label);

valid_mask = dataset_table.valid_for_cp7_model & ismember(dataset_table.scenario, ["B", "C"]);
valid_table = dataset_table(valid_mask, :);
valid_table = sortrows(valid_table, {'scenario', 'pos_id'}, {'ascend', 'ascend'});

writetable(valid_table, fullfile(cfg.stage03_l1_dir, 'cp7_target_dataset_valid_bc.csv'));

baseline_eval = evaluate_l1_variant(valid_table, cfg.baseline_features, "baseline_5feature_l1", cfg);
proposed_eval = evaluate_l1_variant(valid_table, cfg.proposed_features, "proposed_11feature_l1", cfg);

summary_table = [baseline_eval.summary_table; proposed_eval.summary_table];
focus_table = build_focus_selection_table(proposed_eval.coefficient_table, cfg.cp7_focus_features);
comparison_table = build_l1_vs_ridge_table(cfg, summary_table);

writetable(summary_table, fullfile(cfg.stage03_l1_dir, 'l1_model_summary.csv'));
writetable(focus_table, fullfile(cfg.stage03_l1_dir, 'l1_focus_feature_selection.csv'));
writetable(comparison_table, fullfile(cfg.stage03_l1_dir, 'ridge_vs_l1_summary.csv'));

l1_outputs = struct();
l1_outputs.valid_table = valid_table;
l1_outputs.baseline = baseline_eval;
l1_outputs.proposed = proposed_eval;
l1_outputs.summary_table = summary_table;
l1_outputs.focus_table = focus_table;
l1_outputs.comparison_table = comparison_table;

save(fullfile(cfg.stage03_l1_dir, 'l1_regularized_check_outputs.mat'), 'l1_outputs', '-v7.3');
end

function eval_out = evaluate_l1_variant(dataset_table, feature_names, variant_name, cfg)
labels = logical(dataset_table.label);
X_all = double(dataset_table{:, feature_names});
outer_folds = safe_cv_folds(labels, cfg.cv_folds);
if outer_folds < 2
    error('[run_geometric_l1_support_bundle] Insufficient minority samples for %s.', variant_name);
end

rng(cfg.random_seed);
cv = cvpartition(labels, 'KFold', outer_folds);

n_feature = size(X_all, 2);
n_sample = size(X_all, 1);
oof_score = nan(n_sample, 1);
oof_pred = false(n_sample, 1);
fold_id = zeros(n_sample, 1);
fold_selected = false(n_feature, outer_folds);
fold_lambda = nan(outer_folds, 1);
fold_summary = table();

for idx_fold = 1:outer_folds
    train_mask = training(cv, idx_fold);
    test_mask = test(cv, idx_fold);

    X_train = X_all(train_mask, :);
    y_train = labels(train_mask);
    X_test = X_all(test_mask, :);

    [X_train_norm, mean_values, std_values] = normalize_train_matrix(X_train);
    X_test_norm = apply_train_normalization(X_test, mean_values, std_values);

    fit_out = fit_lasso_inner(X_train_norm, y_train, cfg);
    if fit_out.failed
        error('[run_geometric_l1_support_bundle] L1 fit failed for %s fold %d: %s', ...
            variant_name, idx_fold, fit_out.warning_message);
    end

    score_fold = sigmoid(X_test_norm * fit_out.coefficients + fit_out.intercept);
    pred_fold = score_fold >= cfg.classification_threshold;

    oof_score(test_mask) = score_fold;
    oof_pred(test_mask) = pred_fold;
    fold_id(test_mask) = idx_fold;
    fold_selected(:, idx_fold) = abs(fit_out.coefficients) > 0;
    fold_lambda(idx_fold) = fit_out.lambda;

    selected_names = string(feature_names(fold_selected(:, idx_fold)));
    if isempty(selected_names)
        selected_text = "";
    else
        selected_text = strjoin(selected_names, ', ');
    end

    row = table( ...
        string(variant_name), ...
        idx_fold, ...
        sum(train_mask), ...
        sum(test_mask), ...
        sum(y_train), ...
        sum(~y_train), ...
        fit_out.lambda, ...
        sum(fold_selected(:, idx_fold)), ...
        string(selected_text), ...
        'VariableNames', {'variant_name', 'fold_id', 'n_train', 'n_test', 'n_los_train', 'n_nlos_train', 'lambda', 'n_selected', 'selected_features'});
    fold_summary = [fold_summary; row]; %#ok<AGROW>
end

try
    [~, ~, ~, auc_value] = perfcurve(labels, oof_score, true);
catch
    auc_value = NaN;
end
accuracy_value = mean(oof_pred == labels);
brier_value = mean((oof_score - double(labels)).^2);

[X_norm_all, mean_values_all, std_values_all] = normalize_train_matrix(X_all);
fit_full = fit_lasso_inner(X_norm_all, labels, cfg);
if fit_full.failed
    error('[run_geometric_l1_support_bundle] Full-fit L1 failed for %s: %s', ...
        variant_name, fit_full.warning_message);
end

selected_full = abs(fit_full.coefficients) > 0;
selection_frequency = mean(fold_selected, 2);
selected_names_full = string(feature_names(selected_full));
if isempty(selected_names_full)
    selected_text_full = "";
else
    selected_text_full = strjoin(selected_names_full, ', ');
end

coefficient_table = table( ...
    string(feature_names(:)), ...
    fit_full.coefficients(:), ...
    selected_full(:), ...
    selection_frequency(:), ...
    repmat(fit_full.lambda, n_feature, 1), ...
    'VariableNames', {'predictor_name', 'coefficient', 'selected_fullfit', 'selection_frequency', 'lambda_fullfit'});

prediction_table = build_prediction_table(dataset_table, oof_score, oof_pred, fold_id, variant_name);
summary_table = table( ...
    string(variant_name), ...
    size(X_all, 2), ...
    size(X_all, 1), ...
    sum(labels), ...
    sum(~labels), ...
    auc_value, ...
    accuracy_value, ...
    brier_value, ...
    mean(fold_lambda, 'omitnan'), ...
    fit_full.lambda, ...
    sum(selected_full), ...
    string(selected_text_full), ...
    'VariableNames', {'variant_name', 'n_input_features', 'n_samples', 'n_los', 'n_nlos', 'auc', 'accuracy', 'brier_score', 'mean_cv_lambda', 'fullfit_lambda', 'n_selected_fullfit', 'selected_features_fullfit'});

stub = char(string(variant_name));
writetable(fold_summary, fullfile(cfg.stage03_l1_dir, sprintf('%s_fold_summary.csv', stub)));
writetable(coefficient_table, fullfile(cfg.stage03_l1_dir, sprintf('%s_coefficients.csv', stub)));
writetable(prediction_table, fullfile(cfg.stage03_l1_dir, sprintf('%s_oof_predictions.csv', stub)));

normalization_table = table( ...
    string(feature_names(:)), ...
    mean_values_all(:), ...
    std_values_all(:), ...
    'VariableNames', {'predictor_name', 'mean_value', 'std_value'});
writetable(normalization_table, fullfile(cfg.stage03_l1_dir, sprintf('%s_fullfit_normalization.csv', stub)));

eval_out = struct();
eval_out.summary_table = summary_table;
eval_out.coefficient_table = coefficient_table;
eval_out.fold_summary = fold_summary;
eval_out.prediction_table = prediction_table;
eval_out.normalization_table = normalization_table;
end

function prediction_table = build_prediction_table(dataset_table, score, pred, fold_id, variant_name)
prediction_table = table();
if ismember('case_name', dataset_table.Properties.VariableNames)
    prediction_table.case_name = string(dataset_table.case_name);
end
if ismember('scenario', dataset_table.Properties.VariableNames)
    prediction_table.scenario = string(dataset_table.scenario);
end
if ismember('pos_id', dataset_table.Properties.VariableNames)
    prediction_table.pos_id = dataset_table.pos_id;
end
if ismember('x_m', dataset_table.Properties.VariableNames)
    prediction_table.x_m = dataset_table.x_m;
end
if ismember('y_m', dataset_table.Properties.VariableNames)
    prediction_table.y_m = dataset_table.y_m;
end
prediction_table.label = logical(dataset_table.label);
prediction_table.score = score;
prediction_table.pred = pred;
prediction_table.fold_id = fold_id;
prediction_table.variant_name = repmat(string(variant_name), height(prediction_table), 1);
end

function focus_table = build_focus_selection_table(coefficient_table, focus_features)
focus_mask = ismember(string(coefficient_table.predictor_name), string(focus_features));
focus_table = coefficient_table(focus_mask, :);
focus_table = sortrows(focus_table, {'selected_fullfit', 'selection_frequency'}, {'descend', 'descend'});
end

function comparison_table = build_l1_vs_ridge_table(cfg, l1_summary_table)
reviewer_csv = fullfile(cfg.stage01_reviewer_dir, 'geometric', 'incremental_summary.csv');
priority_csv = fullfile(cfg.stage02_priority_dir, 'geometric', 'spatial_cv_summary.csv');

comparison_table = table();

if isfile(reviewer_csv)
    reviewer_table = readtable(reviewer_csv, 'TextType', 'string');
    reviewer_row = reviewer_table(reviewer_table.scope == "B+C" & reviewer_table.subset_name == "overall", :);
    if ~isempty(reviewer_row)
        ridge_rows = table( ...
            ["ridge_baseline"; "ridge_proposed"], ...
            ["reviewer_paired_cv"; "reviewer_paired_cv"], ...
            [to_double_scalar(reviewer_row.baseline_auc); to_double_scalar(reviewer_row.proposed_auc)], ...
            [to_double_scalar(reviewer_row.baseline_accuracy); to_double_scalar(reviewer_row.proposed_accuracy)], ...
            [to_double_scalar(reviewer_row.baseline_brier); to_double_scalar(reviewer_row.proposed_brier)], ...
            [numel(cfg.baseline_features); numel(cfg.proposed_features)], ...
            [NaN; NaN], ...
            [NaN; NaN], ...
            ["ridge reference from reviewer rerun"; "ridge reference from reviewer rerun"], ...
            'VariableNames', {'variant_name', 'source', 'auc', 'accuracy', 'brier_score', 'n_input_features', 'fullfit_lambda', 'n_selected_fullfit', 'note'});
        comparison_table = [comparison_table; ridge_rows]; %#ok<AGROW>
    end
end

for idx = 1:height(l1_summary_table)
    row = l1_summary_table(idx, :);
    add_row = table( ...
        string(row.variant_name), ...
        "l1_stratified_kfold", ...
        row.auc, ...
        row.accuracy, ...
        row.brier_score, ...
        row.n_input_features, ...
        row.fullfit_lambda, ...
        row.n_selected_fullfit, ...
        row.selected_features_fullfit, ...
        'VariableNames', {'variant_name', 'source', 'auc', 'accuracy', 'brier_score', 'n_input_features', 'fullfit_lambda', 'n_selected_fullfit', 'note'});
    comparison_table = [comparison_table; add_row]; %#ok<AGROW>
end

if isfile(priority_csv)
    priority_table = readtable(priority_csv, 'TextType', 'string');
    priority_rows = priority_table(priority_table.scope == "B+C", :);
    for idx = 1:height(priority_rows)
        row = priority_rows(idx, :);
        if string(row.variant_name) == "baseline"
            n_input_features = numel(cfg.baseline_features);
        else
            n_input_features = numel(cfg.proposed_features);
        end
        add_row = table( ...
            "ridge_" + string(row.variant_name), ...
            "spatial_cv_leave_one_position_out", ...
            to_double_scalar(row.auc), ...
            to_double_scalar(row.accuracy), ...
            to_double_scalar(row.brier_score), ...
            n_input_features, ...
            NaN, ...
            NaN, ...
            "spatial CV reference", ...
            'VariableNames', {'variant_name', 'source', 'auc', 'accuracy', 'brier_score', 'n_input_features', 'fullfit_lambda', 'n_selected_fullfit', 'note'});
        comparison_table = [comparison_table; add_row]; %#ok<AGROW>
    end
end
end

function value = to_double_scalar(input_value)
if iscell(input_value)
    input_value = input_value{1};
end

if isempty(input_value)
    value = NaN;
elseif isnumeric(input_value) || islogical(input_value)
    value = double(input_value(1));
else
    value = str2double(string(input_value(1)));
end
end

function [X_norm, mean_values, std_values] = normalize_train_matrix(X)
mean_values = mean(X, 1, 'omitnan');
std_values = std(X, 0, 1, 'omitnan');
std_values(~isfinite(std_values) | std_values == 0) = 1;
X_norm = (X - mean_values) ./ std_values;
end

function X_norm = apply_train_normalization(X, mean_values, std_values)
X_norm = (X - mean_values) ./ std_values;
end

function fit_out = fit_lasso_inner(X_train_norm, y_train, cfg)
fit_out = struct();
fit_out.failed = false;
fit_out.coefficients = nan(size(X_train_norm, 2), 1);
fit_out.intercept = NaN;
fit_out.lambda = NaN;
fit_out.warning_message = "";

inner_folds = safe_cv_folds(y_train, min(cfg.cv_folds, 5));
if inner_folds < 2
    fit_out.failed = true;
    fit_out.warning_message = "insufficient_minority_inner";
    return;
end

try
    rng(cfg.random_seed);
    inner_cv = cvpartition(logical(y_train), 'KFold', inner_folds);
    weights = compute_class_weights(y_train);
    opts = statset('UseParallel', false);
    [B, fit_info] = lassoglm(X_train_norm, double(y_train), 'binomial', ...
        'CV', inner_cv, ...
        'NumLambda', cfg.l1_num_lambda, ...
        'LambdaRatio', cfg.l1_lambda_ratio, ...
        'Weights', weights, ...
        'Options', opts);
    idx = fit_info.IndexMinDeviance;
    fit_out.coefficients = B(:, idx);
    fit_out.intercept = fit_info.Intercept(idx);
    fit_out.lambda = fit_info.Lambda(idx);
catch exception_info
    fit_out.failed = true;
    fit_out.warning_message = string(exception_info.message);
end
end

function n_fold = safe_cv_folds(y, requested_folds)
y = logical(y(:));
n_pos = sum(y);
n_neg = sum(~y);
n_fold = min([requested_folds, n_pos, n_neg]);
if isempty(n_fold) || ~isfinite(n_fold)
    n_fold = 0;
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

function y = sigmoid(x)
x = max(min(double(x), 60), -60);
y = 1 ./ (1 + exp(-x));
end

function write_execution_conditions(cfg)
cond_table = table( ...
    ["bundle_root"; "reviewer_rerun_dir"; "priority_rerun_dir"; "l1_results_dir"; "random_seed"; "cv_folds"; "classification_threshold"; "l1_num_lambda"; "l1_lambda_ratio"; "baseline_features"; "cp7_features"; "repro_command"], ...
    [string(cfg.bundle_root); string(cfg.stage01_reviewer_dir); string(cfg.stage02_priority_dir); string(cfg.stage03_l1_dir); string(cfg.random_seed); string(cfg.cv_folds); string(cfg.classification_threshold); string(cfg.l1_num_lambda); string(cfg.l1_lambda_ratio); string(strjoin(cfg.baseline_features, ', ')); string(strjoin(cfg.cp7_features, ', ')); string(cfg.repro_command)], ...
    'VariableNames', {'key', 'value'});
    writetable(cond_table, fullfile(cfg.stage00_execution_dir, 'execution_conditions.csv'));

lines = {};
lines{end+1} = '# Geometric L1 Support Bundle';
lines{end+1} = '';
lines{end+1} = '## Purpose';
lines{end+1} = '';
lines{end+1} = '- Re-run the reviewer diagnostics for a fresh evidence snapshot.';
lines{end+1} = '- Re-run the priority validations to capture spatial CV evidence.';
lines{end+1} = '- Add an L1-regularized logistic check on the geometric CP7-capable B+C subset.';
lines{end+1} = '';
lines{end+1} = '## Key Settings';
lines{end+1} = '';
lines{end+1} = sprintf('- Random seed: `%d`', cfg.random_seed);
lines{end+1} = sprintf('- CV folds: `%d`', cfg.cv_folds);
lines{end+1} = sprintf('- Classification threshold: `%.1f`', cfg.classification_threshold);
lines{end+1} = sprintf('- L1 NumLambda: `%d`', cfg.l1_num_lambda);
lines{end+1} = sprintf('- L1 LambdaRatio: `%g`', cfg.l1_lambda_ratio);
lines{end+1} = sprintf('- Baseline features: `%s`', strjoin(cfg.baseline_features, ', '));
lines{end+1} = sprintf('- CP7 features: `%s`', strjoin(cfg.cp7_features, ', '));
lines{end+1} = '';
lines{end+1} = '## Reproduction';
lines{end+1} = '';
lines{end+1} = ['- `', cfg.repro_command, '`'];

write_text_file(fullfile(cfg.stage00_execution_dir, 'execution_conditions.md'), strjoin(lines, newline));
end

function write_summary_report(cfg, l1_outputs)
reviewer_csv = fullfile(cfg.stage01_reviewer_dir, 'geometric', 'incremental_summary.csv');
priority_csv = fullfile(cfg.stage02_priority_dir, 'geometric', 'spatial_cv_summary.csv');
recovery_csv = fullfile(cfg.stage01_reviewer_dir, 'geometric', 'misclassification_recovery_overall.csv');
mcnemar_csv = fullfile(cfg.stage01_reviewer_dir, 'geometric', 'mcnemar_tests.csv');

reviewer_table = readtable(reviewer_csv, 'TextType', 'string');
priority_table = readtable(priority_csv, 'TextType', 'string');
recovery_table = readtable(recovery_csv, 'TextType', 'string');
mcnemar_table = readtable(mcnemar_csv, 'TextType', 'string');

overall_row = reviewer_table(reviewer_table.scope == "B+C" & reviewer_table.subset_name == "overall", :);
hard_row = reviewer_table(reviewer_table.scope == "B+C" & reviewer_table.subset_name == "hard_case_0p4_0p6", :);
spatial_base = priority_table(priority_table.scope == "B+C" & priority_table.variant_name == "baseline", :);
spatial_prop = priority_table(priority_table.scope == "B+C" & priority_table.variant_name == "full_proposed", :);
recovery_row = recovery_table(1, :);
mcnemar_row = mcnemar_table(mcnemar_table.scope == "B+C" & mcnemar_table.subset_name == "overall", :);
focus_table = l1_outputs.focus_table;

key_metrics = table( ...
    ["paired_baseline_auc"; "paired_proposed_auc"; "paired_delta_auc"; "paired_delta_brier"; "paired_mcnemar_p"; "hardcase_baseline_auc"; "hardcase_proposed_auc"; "spatial_baseline_auc"; "spatial_proposed_auc"], ...
    [to_double_scalar(overall_row.baseline_auc); to_double_scalar(overall_row.proposed_auc); to_double_scalar(overall_row.delta_auc); to_double_scalar(overall_row.delta_brier); to_double_scalar(mcnemar_row.p_value_exact); to_double_scalar(hard_row.baseline_auc); to_double_scalar(hard_row.proposed_auc); to_double_scalar(spatial_base.auc); to_double_scalar(spatial_prop.auc)], ...
    'VariableNames', {'metric_name', 'value'});
    writetable(key_metrics, fullfile(cfg.stage04_report_dir, 'key_metrics_snapshot.csv'));

lines = {};
lines{end+1} = '# Geometric L1 Support Report';
lines{end+1} = '';
lines{end+1} = '## 1. Purpose';
lines{end+1} = '';
lines{end+1} = '- Create a fresh evidence bundle for manuscript writing.';
lines{end+1} = '- Re-run the paired reviewer diagnostics and the spatial-CV priority validation.';
lines{end+1} = '- Add an L1-regularized logistic check to address the overfitting question for the 112-sample B+C subset.';
lines{end+1} = '';
lines{end+1} = '## 2. Step 1: Reviewer rerun';
lines{end+1} = '';
lines{end+1} = sprintf('- Output root: `%s`', cfg.stage01_reviewer_dir);
lines{end+1} = sprintf('- Paired B+C baseline AUC: `%.4f`', to_double_scalar(overall_row.baseline_auc));
lines{end+1} = sprintf('- Paired B+C proposed AUC: `%.4f`', to_double_scalar(overall_row.proposed_auc));
lines{end+1} = sprintf('- Delta AUC: `%.4f`', to_double_scalar(overall_row.delta_auc));
lines{end+1} = sprintf('- Delta Brier: `%.4f`', to_double_scalar(overall_row.delta_brier));
lines{end+1} = sprintf('- Exact McNemar p-value: `%.4f`', to_double_scalar(mcnemar_row.p_value_exact));
lines{end+1} = '- These rerun outputs provide the paired AUC/Brier evidence used in the manuscript.';
lines{end+1} = '';
lines{end+1} = '## 3. Step 2: Priority rerun';
lines{end+1} = '';
lines{end+1} = sprintf('- Output root: `%s`', cfg.stage02_priority_dir);
lines{end+1} = sprintf('- Spatial CV baseline AUC: `%.4f`', to_double_scalar(spatial_base.auc));
lines{end+1} = sprintf('- Spatial CV proposed AUC: `%.4f`', to_double_scalar(spatial_prop.auc));
lines{end+1} = '- These rerun outputs provide the spatially aware robustness evidence.';
lines{end+1} = '';
lines{end+1} = '## 4. Step 3: L1-regularized logistic check';
lines{end+1} = '';
for idx = 1:height(l1_outputs.summary_table)
    row = l1_outputs.summary_table(idx, :);
    lines{end+1} = sprintf('- `%s`: AUC `%.4f`, accuracy `%.4f`, Brier `%.4f`, full-fit selected `%d` features, lambda `%.6g`.', ...
        row.variant_name, row.auc, row.accuracy, row.brier_score, row.n_selected_fullfit, row.fullfit_lambda);
    lines{end+1} = sprintf('  Selected full-fit features: `%s`', row.selected_features_fullfit);
end
lines{end+1} = '';
lines{end+1} = '### CP7 focus features under L1';
lines{end+1} = '';
for idx = 1:height(focus_table)
    row = focus_table(idx, :);
    lines{end+1} = sprintf('- `%s`: full-fit selected=`%d`, selection frequency=`%.2f`, coefficient=`%.6f`', ...
        row.predictor_name, row.selected_fullfit, row.selection_frequency, row.coefficient);
end
stable_focus = string(focus_table.predictor_name(focus_table.selection_frequency >= 0.8));
if ~isempty(stable_focus)
    lines{end+1} = sprintf('- Stable focus features across folds (selection frequency >= 0.8): `%s`', strjoin(stable_focus, ', '));
end
lines{end+1} = '';
lines{end+1} = '## 5. Recovery snapshot';
lines{end+1} = '';
lines{end+1} = sprintf('- Baseline errors: `%s`', string(recovery_row.baseline_errors));
lines{end+1} = sprintf('- Proposed errors: `%s`', string(recovery_row.proposed_errors));
lines{end+1} = sprintf('- Rescued by proposed: `%s`', string(recovery_row.rescued_by_proposed));
lines{end+1} = sprintf('- Harmed by proposed: `%s`', string(recovery_row.harmed_by_proposed));
lines{end+1} = sprintf('- Rescue rate given baseline error: `%.4f`', to_double_scalar(recovery_row.rescue_rate_given_baseline_error));
lines{end+1} = sprintf('- Harm rate given baseline correct: `%.4f`', to_double_scalar(recovery_row.harm_rate_given_baseline_correct));
lines{end+1} = '';
lines{end+1} = '## 6. File Guide';
lines{end+1} = '';
lines{end+1} = '- `01_reviewer_rerun`: fresh paired reviewer evidence';
lines{end+1} = '- `02_priority_rerun`: fresh spatial-CV and ablation/permutation evidence';
lines{end+1} = '- `03_l1_regularization_check`: new L1 logistic outputs';
lines{end+1} = '- `04_report/key_metrics_snapshot.csv`: condensed evidence table for manuscript drafting';

write_text_file(fullfile(cfg.stage04_report_dir, 'geometric_l1_support_report.md'), strjoin(lines, newline));
end

function write_file_manifest(cfg)
files = get_all_files_recursive(cfg.bundle_root);
rel_paths = strings(numel(files), 1);
for idx = 1:numel(files)
    rel_paths(idx) = string(strrep(files{idx}, [cfg.bundle_root filesep], ''));
end
manifest = table(rel_paths, 'VariableNames', {'relative_path'});
manifest = sortrows(manifest, 'relative_path');
    writetable(manifest, fullfile(cfg.stage04_report_dir, 'file_manifest.csv'));
end

function files = get_all_files_recursive(root_dir)
listing = dir(root_dir);
files = {};
for idx = 1:numel(listing)
    item = listing(idx);
    if strcmp(item.name, '.') || strcmp(item.name, '..')
        continue;
    end
    full_path = fullfile(root_dir, item.name);
    if item.isdir
        child_files = get_all_files_recursive(full_path);
        files = [files, child_files]; %#ok<AGROW>
    else
        files{end+1} = full_path; %#ok<AGROW>
    end
end
end

function write_text_file(filepath, text_content)
fid = fopen(filepath, 'w');
if fid < 0
    error('[run_geometric_l1_support_bundle] Failed to open file: %s', filepath);
end
cleanup_obj = onCleanup(@() fclose(fid));
fprintf(fid, '%s', text_content);
clear cleanup_obj;
end
