function outputs = run_los_nlos_feature_diagnostics()
% RUN_LOS_NLOS_FEATURE_DIAGNOSTICS
% Second-stage analysis for correlation/redundancy, incremental feature
% gain, misclassification rescue, and Scenario-B-focused interpretation.

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cfg = default_config(script_dir, project_root);

ensure_dir(cfg.diagnostics_dir);
ensure_dir(fullfile(cfg.diagnostics_dir, 'shared'));

ensure_baseline_outputs_exist(cfg);

fprintf('=== LoS/NLoS Feature Diagnostics ===\n');
fprintf('Baseline results root: %s\n', cfg.results_root_dir);
fprintf('Diagnostics root     : %s\n', cfg.diagnostics_dir);

shared_dataset = load_target_dataset("material", cfg);
shared_outputs = run_shared_feature_correlation_analysis(shared_dataset, cfg);
write_shared_outputs(shared_outputs, cfg);

outputs = struct();
outputs.config = cfg;
outputs.shared = shared_outputs;
outputs.targets = struct();

combined_summary = table();

for idx_target = 1:numel(cfg.targets)
    target_name = cfg.targets(idx_target);
    fprintf('\n--- Diagnostics Target: %s ---\n', target_name);
    target_outputs = run_target_diagnostics(target_name, cfg);
    outputs.targets.(char(target_name)) = target_outputs;

    row = target_outputs.incremental_summary;
    row.label_target = repmat(string(target_name), height(row), 1);
    row = movevars(row, 'label_target', 'Before', 'subset_name');
    combined_summary = [combined_summary; row]; %#ok<AGROW>
end

writetable(combined_summary, fullfile(cfg.diagnostics_dir, 'incremental_summary_all_targets.csv'));
write_combined_markdown(outputs, combined_summary, cfg);

outputs.combined_summary = combined_summary;
outputs.timestamp = datetime('now');
save(fullfile(cfg.diagnostics_dir, 'feature_diagnostics_outputs.mat'), 'outputs', '-v7.3');
end

function cfg = default_config(script_dir, project_root)
cfg = struct();
cfg.script_dir = script_dir;
cfg.project_root = project_root;
cfg.results_root_dir = fullfile(script_dir, 'results');
cfg.diagnostics_dir = fullfile(cfg.results_root_dir, 'diagnostics');
cfg.targets = ["material", "geometric"];
cfg.random_seed = 42;
cfg.cv_folds = 5;
cfg.classification_threshold = 0.5;
cfg.hard_case_band = [0.4, 0.6];
cfg.logistic_lambda = 1e-2;

cfg.correlation_features = { ...
    'r_CP', ...
    'a_FP', ...
    'fp_energy_db', ...
    'skewness_pdp', ...
    'kurtosis_pdp'};
cfg.correlation_focus_sources = {'r_CP', 'a_FP'};
cfg.correlation_focus_targets = {'fp_energy_db', 'skewness_pdp', 'kurtosis_pdp'};

cfg.baseline_features = { ...
    'fp_energy_db', ...
    'skewness_pdp', ...
    'kurtosis_pdp', ...
    'mean_excess_delay_ns', ...
    'rms_delay_spread_ns'};
cfg.proposed_features = [cfg.baseline_features, {'r_CP', 'a_FP'}];

cfg.scenario_focus_cases = { ...
    'CP_caseB', 'CP_caseC', ...
    'LP_caseB', 'LP_caseC'};
cfg.scenario_focus_features = { ...
    'r_CP', ...
    'a_FP', ...
    'fp_energy_db', ...
    'skewness_pdp', ...
    'kurtosis_pdp', ...
    'mean_excess_delay_ns', ...
    'rms_delay_spread_ns'};

cfg.label_csv = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_all_scenarios_los_nlos.csv');
cfg.scenario_b_json = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_scenario_b.json');
cfg.scenario_c_json = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_scenario_c.json');
end

function ensure_dir(dirpath)
if ~exist(dirpath, 'dir')
    mkdir(dirpath);
end
end

function ensure_baseline_outputs_exist(cfg)
material_csv = fullfile(cfg.results_root_dir, 'material', 'baseline_feature_table.csv');
geometric_csv = fullfile(cfg.results_root_dir, 'geometric', 'baseline_feature_table.csv');
if isfile(material_csv) && isfile(geometric_csv)
    return;
end

current_dir = pwd;
cleanup_obj = onCleanup(@() cd(current_dir));
cd(cfg.script_dir);
run_los_nlos_baseline();
clear cleanup_obj;
cd(current_dir);
end

function dataset_table = load_target_dataset(target_name, cfg)
path_csv = fullfile(cfg.results_root_dir, char(target_name), 'baseline_feature_table.csv');
if ~isfile(path_csv)
    error('[run_los_nlos_feature_diagnostics] Missing baseline feature table: %s', path_csv);
end

dataset_table = readtable(path_csv);
dataset_table.case_name = string(dataset_table.case_name);
dataset_table.scenario = string(dataset_table.scenario);
dataset_table.polarization = string(dataset_table.polarization);
dataset_table.valid_for_model = logical(dataset_table.valid_for_model);
dataset_table.label = logical(dataset_table.label);
end

function shared_outputs = run_shared_feature_correlation_analysis(dataset_table, cfg)
dataset_table = dataset_table(dataset_table.valid_for_model, :);
feature_names = cfg.correlation_features;
X = dataset_table{:, feature_names};

[pearson_r, pearson_p] = corr(X, 'Type', 'Pearson', 'Rows', 'pairwise');
[spearman_rho, spearman_p] = corr(X, 'Type', 'Spearman', 'Rows', 'pairwise');

pearson_table = array2table(pearson_r, 'VariableNames', feature_names, 'RowNames', feature_names);
spearman_table = array2table(spearman_rho, 'VariableNames', feature_names, 'RowNames', feature_names);

pair_table = table();
for idx_source = 1:numel(cfg.correlation_focus_sources)
    source_name = cfg.correlation_focus_sources{idx_source};
    source_idx = find(strcmp(feature_names, source_name), 1, 'first');
    for idx_target = 1:numel(cfg.correlation_focus_targets)
        target_name = cfg.correlation_focus_targets{idx_target};
        target_idx = find(strcmp(feature_names, target_name), 1, 'first');

        row = table();
        row.source_feature = string(source_name);
        row.target_feature = string(target_name);
        row.pearson_r = pearson_r(source_idx, target_idx);
        row.pearson_p = pearson_p(source_idx, target_idx);
        row.spearman_rho = spearman_rho(source_idx, target_idx);
        row.spearman_p = spearman_p(source_idx, target_idx);
        row.abs_pearson_r = abs(row.pearson_r);
        row.abs_spearman_rho = abs(row.spearman_rho);
        pair_table = [pair_table; row]; %#ok<AGROW>
    end
end

shared_outputs = struct();
shared_outputs.n_samples = height(dataset_table);
shared_outputs.pearson_table = pearson_table;
shared_outputs.spearman_table = spearman_table;
shared_outputs.pair_table = sortrows(pair_table, {'source_feature', 'target_feature'});
end

function write_shared_outputs(shared_outputs, cfg)
shared_dir = fullfile(cfg.diagnostics_dir, 'shared');
ensure_dir(shared_dir);

writetable(shared_outputs.pearson_table, fullfile(shared_dir, 'correlation_pearson_matrix.csv'), ...
    'WriteRowNames', true);
writetable(shared_outputs.spearman_table, fullfile(shared_dir, 'correlation_spearman_matrix.csv'), ...
    'WriteRowNames', true);
writetable(shared_outputs.pair_table, fullfile(shared_dir, 'correlation_focus_pairs.csv'));
end

function target_outputs = run_target_diagnostics(target_name, cfg)
target_dir = fullfile(cfg.diagnostics_dir, char(target_name));
ensure_dir(target_dir);

dataset_table = load_target_dataset(target_name, cfg);
dataset_table = dataset_table(dataset_table.valid_for_model, :);
labels = logical(dataset_table.label);

rng(cfg.random_seed);
rng(cfg.random_seed);
cv = cvpartition(labels, 'KFold', cfg.cv_folds);

baseline_eval = cross_validated_logistic(dataset_table, labels, cfg.baseline_features, cv, cfg);
proposed_eval = cross_validated_logistic(dataset_table, labels, cfg.proposed_features, cv, cfg);

baseline_metrics = model_metrics_row(labels, baseline_eval.score, baseline_eval.pred, "baseline");
proposed_metrics = model_metrics_row(labels, proposed_eval.score, proposed_eval.pred, "proposed");
metrics_overall = [baseline_metrics; proposed_metrics];

hard_mask = baseline_eval.score >= cfg.hard_case_band(1) & baseline_eval.score <= cfg.hard_case_band(2);
hard_metrics = table();
if any(hard_mask)
    hard_metrics = [ ...
        model_metrics_row(labels(hard_mask), baseline_eval.score(hard_mask), baseline_eval.pred(hard_mask), "baseline"); ...
        model_metrics_row(labels(hard_mask), proposed_eval.score(hard_mask), proposed_eval.pred(hard_mask), "proposed")];
end

incremental_summary = table();
incremental_summary = [incremental_summary; compare_model_rows("overall", labels, baseline_eval, proposed_eval, true(size(labels)), cfg)]; %#ok<AGROW>
incremental_summary = [incremental_summary; compare_model_rows("hard_case_0p4_0p6", labels, baseline_eval, proposed_eval, hard_mask, cfg)]; %#ok<AGROW>

mcnemar_table = table();
mcnemar_table = [mcnemar_table; mcnemar_row("overall", labels, baseline_eval.pred, proposed_eval.pred)]; %#ok<AGROW>
mcnemar_table = [mcnemar_table; mcnemar_row("hard_case_0p4_0p6", labels, baseline_eval.pred, proposed_eval.pred, hard_mask)]; %#ok<AGROW>

rescue_outputs = compute_rescue_analysis(dataset_table, labels, baseline_eval, proposed_eval);
scenario_b_outputs = compute_scenario_b_analysis(target_name, dataset_table, labels, baseline_eval, proposed_eval, cfg);

writetable(metrics_overall, fullfile(target_dir, 'model_metrics_overall.csv'));
writetable(hard_metrics, fullfile(target_dir, 'model_metrics_hard_cases.csv'));
writetable(incremental_summary, fullfile(target_dir, 'incremental_summary.csv'));
writetable(mcnemar_table, fullfile(target_dir, 'mcnemar_tests.csv'));
writetable(rescue_outputs.overall, fullfile(target_dir, 'misclassification_recovery_overall.csv'));
writetable(rescue_outputs.by_case, fullfile(target_dir, 'misclassification_recovery_by_case.csv'));
writetable(rescue_outputs.by_scenario, fullfile(target_dir, 'misclassification_recovery_by_scenario.csv'));
writetable(rescue_outputs.sample_table, fullfile(target_dir, 'misclassification_recovery_samples.csv'));
writetable(scenario_b_outputs.case_feature_auc, fullfile(target_dir, 'scenario_b_case_feature_auc.csv'));
writetable(scenario_b_outputs.r_cp_case_stats, fullfile(target_dir, 'scenario_b_r_cp_case_stats.csv'));
writetable(scenario_b_outputs.scenario_b_samples, fullfile(target_dir, 'scenario_b_samples.csv'));
writetable(scenario_b_outputs.scenario_b_objects, fullfile(target_dir, 'scenario_b_objects.csv'));
writetable(scenario_b_outputs.scenario_c_objects, fullfile(target_dir, 'scenario_c_objects.csv'));
write_text_file(fullfile(target_dir, 'scenario_b_note.txt'), scenario_b_outputs.note_text);

target_outputs = struct();
target_outputs.dataset_table = dataset_table;
target_outputs.baseline_eval = baseline_eval;
target_outputs.proposed_eval = proposed_eval;
target_outputs.metrics_overall = metrics_overall;
target_outputs.metrics_hard_cases = hard_metrics;
target_outputs.incremental_summary = incremental_summary;
target_outputs.mcnemar_table = mcnemar_table;
target_outputs.rescue_outputs = rescue_outputs;
target_outputs.scenario_b_outputs = scenario_b_outputs;
end

function eval_outputs = cross_validated_logistic(dataset_table, labels, feature_names, cv, cfg)
X_all = dataset_table{:, feature_names};
n_samples = size(X_all, 1);

score = nan(n_samples, 1);
pred = false(n_samples, 1);
fold_id = zeros(n_samples, 1);

for idx_fold = 1:cv.NumTestSets
    train_mask = training(cv, idx_fold);
    test_mask = test(cv, idx_fold);

    X_train = X_all(train_mask, :);
    y_train = labels(train_mask);
    X_test = X_all(test_mask, :);

    [X_train_norm, norm_params] = normalize_feature_matrix(X_train);
    X_test_norm = apply_normalization(X_test, norm_params);

    model = fit_logistic_model(X_train_norm, y_train, cfg);
    score(test_mask) = predict_with_model(model, X_test_norm);
    pred(test_mask) = score(test_mask) >= cfg.classification_threshold;
    fold_id(test_mask) = idx_fold;
end

[X_all_norm, norm_params_all] = normalize_feature_matrix(X_all);
full_model = fit_logistic_model(X_all_norm, labels, cfg);
full_model.normalization = norm_params_all;
full_model.feature_names = feature_names;

eval_outputs = struct();
eval_outputs.feature_names = feature_names;
eval_outputs.score = score;
eval_outputs.pred = pred;
eval_outputs.fold_id = fold_id;
eval_outputs.full_model = full_model;
end

function [X_norm, params] = normalize_feature_matrix(X)
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
sample_weights = compute_class_weights(y);
model = struct();

try
    mdl = fitclinear(X, y, ...
        'Learner', 'logistic', ...
        'Regularization', 'ridge', ...
        'Lambda', cfg.logistic_lambda, ...
        'Solver', 'lbfgs', ...
        'Weights', sample_weights);

    model.backend = "fitclinear";
    model.mdl_object = mdl;
catch exception_info
    warning('[run_los_nlos_feature_diagnostics] fitclinear failed (%s). Falling back to fitglm.', ...
        exception_info.message);

    predictor_names = make_predictor_names(size(X, 2));
    train_table = array2table(X, 'VariableNames', predictor_names);
    train_table.label = y;
    mdl = fitglm(train_table, 'label ~ .', 'Distribution', 'binomial', 'Weights', sample_weights);

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
        error('[run_los_nlos_feature_diagnostics] Unsupported backend: %s', string(model.backend));
end
end

function y = logistic_sigmoid(x)
x = max(min(double(x), 60), -60);
y = 1 ./ (1 + exp(-x));
end

function row = model_metrics_row(labels, scores, predictions, model_name)
row = metrics_table_from_vectors(labels, scores, predictions, model_name);
row.model_name = string(model_name);
row = movevars(row, 'model_name', 'Before', 'group_name');
end

function row = compare_model_rows(subset_name, labels, baseline_eval, proposed_eval, subset_mask, cfg)
subset_mask = logical(subset_mask(:));
labels = logical(labels(:));

row = table();
row.subset_name = string(subset_name);
row.n_samples = sum(subset_mask);

if row.n_samples == 0
    row.baseline_auc = NaN;
    row.proposed_auc = NaN;
    row.delta_auc = NaN;
    row.baseline_brier = NaN;
    row.proposed_brier = NaN;
    row.delta_brier = NaN;
    row.baseline_accuracy = NaN;
    row.proposed_accuracy = NaN;
    row.delta_accuracy = NaN;
    row.confidence_band_low = cfg.hard_case_band(1);
    row.confidence_band_high = cfg.hard_case_band(2);
    return;
end

base_row = metrics_table_from_vectors(labels(subset_mask), baseline_eval.score(subset_mask), baseline_eval.pred(subset_mask), "baseline");
prop_row = metrics_table_from_vectors(labels(subset_mask), proposed_eval.score(subset_mask), proposed_eval.pred(subset_mask), "proposed");

row.baseline_auc = base_row.auc;
row.proposed_auc = prop_row.auc;
row.delta_auc = prop_row.auc - base_row.auc;
row.baseline_brier = base_row.brier_score;
row.proposed_brier = prop_row.brier_score;
row.delta_brier = prop_row.brier_score - base_row.brier_score;
row.baseline_accuracy = base_row.accuracy;
row.proposed_accuracy = prop_row.accuracy;
row.delta_accuracy = prop_row.accuracy - base_row.accuracy;
row.confidence_band_low = cfg.hard_case_band(1);
row.confidence_band_high = cfg.hard_case_band(2);
end

function row = mcnemar_row(subset_name, labels, baseline_pred, proposed_pred, subset_mask)
if nargin < 5
    subset_mask = true(size(labels));
end

subset_mask = logical(subset_mask(:));
labels = logical(labels(:));
baseline_correct = logical(baseline_pred(:)) == labels;
proposed_correct = logical(proposed_pred(:)) == labels;

baseline_correct = baseline_correct(subset_mask);
proposed_correct = proposed_correct(subset_mask);

[p_value, statistic_cc, exact_b, exact_c] = mcnemar_exact_test(baseline_correct, proposed_correct);

row = table();
row.subset_name = string(subset_name);
row.n_samples = sum(subset_mask);
row.baseline_correct_proposed_wrong = exact_b;
row.baseline_wrong_proposed_correct = exact_c;
row.chi_square_cc = statistic_cc;
row.p_value_exact = p_value;
end

function [p_value, statistic_cc, b, c] = mcnemar_exact_test(model_a_correct, model_b_correct)
model_a_correct = logical(model_a_correct(:));
model_b_correct = logical(model_b_correct(:));

b = sum(model_a_correct & ~model_b_correct);
c = sum(~model_a_correct & model_b_correct);

if (b + c) == 0
    statistic_cc = 0;
    p_value = 1;
    return;
end

statistic_cc = (abs(b - c) - 1)^2 / (b + c);
tail_prob = binocdf(min(b, c), b + c, 0.5);
p_value = min(1, 2 * tail_prob);
end

function rescue_outputs = compute_rescue_analysis(dataset_table, labels, baseline_eval, proposed_eval)
baseline_wrong = baseline_eval.pred ~= labels;
proposed_wrong = proposed_eval.pred ~= labels;
rescued = baseline_wrong & ~proposed_wrong;
harmed = ~baseline_wrong & proposed_wrong;

sample_table = dataset_table(:, {'case_name', 'scenario', 'polarization', 'pos_id', 'x_m', 'y_m', 'label', 'r_CP', 'a_FP', 'fp_energy_db', 'mean_excess_delay_ns'});
sample_table.baseline_score = baseline_eval.score;
sample_table.proposed_score = proposed_eval.score;
sample_table.baseline_pred = baseline_eval.pred;
sample_table.proposed_pred = proposed_eval.pred;
sample_table.baseline_wrong = baseline_wrong;
sample_table.proposed_wrong = proposed_wrong;
sample_table.rescued_by_proposed = rescued;
sample_table.harmed_by_proposed = harmed;
sample_table.score_delta_proposed_minus_baseline = proposed_eval.score - baseline_eval.score;
sample_table = sortrows(sample_table, {'rescued_by_proposed', 'harmed_by_proposed', 'case_name', 'pos_id'}, ...
    {'descend', 'descend', 'ascend', 'ascend'});

overall = table();
overall.n_samples = height(sample_table);
overall.baseline_errors = sum(baseline_wrong);
overall.proposed_errors = sum(proposed_wrong);
overall.rescued_by_proposed = sum(rescued);
overall.harmed_by_proposed = sum(harmed);
overall.net_error_gain = overall.rescued_by_proposed - overall.harmed_by_proposed;
overall.rescue_rate_given_baseline_error = safe_divide(overall.rescued_by_proposed, overall.baseline_errors);
overall.harm_rate_given_baseline_correct = safe_divide(overall.harmed_by_proposed, sum(~baseline_wrong));

by_case = grouped_rescue_table(sample_table, 'case_name');
by_scenario = grouped_rescue_table(sample_table, 'scenario');

rescue_outputs = struct();
rescue_outputs.overall = overall;
rescue_outputs.by_case = by_case;
rescue_outputs.by_scenario = by_scenario;
rescue_outputs.sample_table = sample_table;
end

function grouped = grouped_rescue_table(sample_table, group_column)
group_values = unique(string(sample_table.(group_column)), 'stable');
grouped = table();

for idx = 1:numel(group_values)
    value = group_values(idx);
    mask = string(sample_table.(group_column)) == value;

    row = table();
    row.group_type = string(group_column);
    row.group_name = value;
    row.n_samples = sum(mask);
    row.baseline_errors = sum(sample_table.baseline_wrong(mask));
    row.proposed_errors = sum(sample_table.proposed_wrong(mask));
    row.rescued_by_proposed = sum(sample_table.rescued_by_proposed(mask));
    row.harmed_by_proposed = sum(sample_table.harmed_by_proposed(mask));
    row.net_error_gain = row.rescued_by_proposed - row.harmed_by_proposed;
    row.rescue_rate_given_baseline_error = safe_divide(row.rescued_by_proposed, row.baseline_errors);
    grouped = [grouped; row]; %#ok<AGROW>
end
end

function scenario_outputs = compute_scenario_b_analysis(target_name, dataset_table, labels, baseline_eval, proposed_eval, cfg)
dataset_table.baseline_score = baseline_eval.score;
dataset_table.proposed_score = proposed_eval.score;
dataset_table.baseline_pred = baseline_eval.pred;
dataset_table.proposed_pred = proposed_eval.pred;
dataset_table.rescued_by_proposed = (baseline_eval.pred ~= labels) & (proposed_eval.pred == labels);
dataset_table.harmed_by_proposed = (baseline_eval.pred == labels) & (proposed_eval.pred ~= labels);

label_meta = readtable(cfg.label_csv, 'TextType', 'string');
label_meta.scenario = string(label_meta.scenario);
label_meta.hit_objects = string(label_meta.hit_objects);
label_meta.hit_materials = string(label_meta.hit_materials);
label_meta.criterion = string(label_meta.criterion);
label_meta.key = compose_position_key(label_meta.scenario, label_meta.x_m, label_meta.y_m);

scenario_b_dataset = dataset_table(dataset_table.scenario == "B", :);
scenario_b_dataset.key = compose_position_key(scenario_b_dataset.scenario, scenario_b_dataset.x_m, scenario_b_dataset.y_m);

scenario_b_samples = outerjoin( ...
    scenario_b_dataset, ...
    label_meta(:, {'key', 'tag_id', 'geometric_class', 'material_class', 'penetration_loss_db', 'num_hits', 'hit_objects', 'hit_materials', 'criterion'}), ...
    'Keys', 'key', ...
    'MergeKeys', true, ...
    'Type', 'left');
scenario_b_samples = removevars(scenario_b_samples, intersect({'key'}, scenario_b_samples.Properties.VariableNames));

case_feature_auc = table();
for idx_case = 1:numel(cfg.scenario_focus_cases)
    case_name = string(cfg.scenario_focus_cases{idx_case});
    case_mask = dataset_table.case_name == case_name;
    labels_case = labels(case_mask);
    n_los = sum(labels_case);
    n_nlos = sum(~labels_case);

    for idx_feature = 1:numel(cfg.scenario_focus_features)
        feature_name = string(cfg.scenario_focus_features{idx_feature});
        values = dataset_table.(cfg.scenario_focus_features{idx_feature})(case_mask);
        [auc_raw, auc_best] = compute_auc_pair(labels_case, values);

        row = table();
        row.case_name = case_name;
        row.feature = feature_name;
        row.n_samples = sum(case_mask);
        row.n_los = n_los;
        row.n_nlos = n_nlos;
        row.auc_raw = auc_raw;
        row.auc_best_direction = auc_best;
        case_feature_auc = [case_feature_auc; row]; %#ok<AGROW>
    end
end

r_cp_case_stats = table();
for idx_case = 1:numel(cfg.scenario_focus_cases)
    case_name = string(cfg.scenario_focus_cases{idx_case});
    case_mask = dataset_table.case_name == case_name;
    labels_case = labels(case_mask);
    values = dataset_table.r_CP(case_mask);
    [auc_raw, auc_best] = compute_auc_pair(labels_case, values);

    los_values = values(labels_case);
    nlos_values = values(~labels_case);
    [perfect_sep, sep_direction, threshold_value, sep_margin] = detect_perfect_separation(los_values, nlos_values);

    row = table();
    row.case_name = case_name;
    row.n_samples = sum(case_mask);
    row.n_los = sum(labels_case);
    row.n_nlos = sum(~labels_case);
    row.r_cp_auc_raw = auc_raw;
    row.r_cp_auc_best = auc_best;
    row.los_median = median(los_values, 'omitnan');
    row.los_min = min_or_nan(los_values);
    row.los_max = max_or_nan(los_values);
    row.nlos_median = median(nlos_values, 'omitnan');
    row.nlos_min = min_or_nan(nlos_values);
    row.nlos_max = max_or_nan(nlos_values);
    row.perfect_separation = perfect_sep;
    row.separation_direction = string(sep_direction);
    row.threshold_candidate = threshold_value;
    row.separation_margin = sep_margin;
    r_cp_case_stats = [r_cp_case_stats; row]; %#ok<AGROW>
end

scenario_b_objects = objects_to_table(load_json_struct(cfg.scenario_b_json), "B");
scenario_c_objects = objects_to_table(load_json_struct(cfg.scenario_c_json), "C");
note_text = build_scenario_b_note(target_name, scenario_b_samples, r_cp_case_stats, scenario_b_objects, scenario_c_objects);

scenario_outputs = struct();
scenario_outputs.scenario_b_samples = scenario_b_samples;
scenario_outputs.case_feature_auc = case_feature_auc;
scenario_outputs.r_cp_case_stats = r_cp_case_stats;
scenario_outputs.scenario_b_objects = scenario_b_objects;
scenario_outputs.scenario_c_objects = scenario_c_objects;
scenario_outputs.note_text = note_text;
end

function [perfect_sep, direction_text, threshold_value, separation_margin] = detect_perfect_separation(los_values, nlos_values)
los_values = double(los_values(:));
nlos_values = double(nlos_values(:));

los_values = los_values(isfinite(los_values));
nlos_values = nlos_values(isfinite(nlos_values));

perfect_sep = false;
direction_text = "none";
threshold_value = NaN;
separation_margin = NaN;

if isempty(los_values) || isempty(nlos_values)
    return;
end

if min(los_values) > max(nlos_values)
    perfect_sep = true;
    direction_text = "higher_is_los";
    threshold_value = 0.5 * (min(los_values) + max(nlos_values));
    separation_margin = min(los_values) - max(nlos_values);
elseif min(nlos_values) > max(los_values)
    perfect_sep = true;
    direction_text = "higher_is_nlos";
    threshold_value = 0.5 * (min(nlos_values) + max(los_values));
    separation_margin = min(nlos_values) - max(los_values);
end
end

function text_out = build_scenario_b_note(target_name, scenario_b_samples, r_cp_case_stats, scenario_b_objects, scenario_c_objects)
target_name = string(target_name);
lines = strings(0, 1);
lines(end+1) = "Scenario B focus note";
lines(end+1) = sprintf("Target: %s", target_name);
lines(end+1) = sprintf("Scenario B objects: %d (%s)", ...
    height(scenario_b_objects), strjoin(unique(scenario_b_objects.material), ', '));
lines(end+1) = sprintf("Scenario C objects: %d (%s)", ...
    height(scenario_c_objects), strjoin(unique(scenario_c_objects.material), ', '));

cp_b_stats = r_cp_case_stats(r_cp_case_stats.case_name == "CP_caseB", :);
cp_c_stats = r_cp_case_stats(r_cp_case_stats.case_name == "CP_caseC", :);

if ~isempty(cp_b_stats)
    lines(end+1) = sprintf("CP_caseB r_CP AUC=%.3f with n_los=%d, n_nlos=%d.", ...
        cp_b_stats.r_cp_auc_best, cp_b_stats.n_los, cp_b_stats.n_nlos);
end
if ~isempty(cp_c_stats)
    lines(end+1) = sprintf("CP_caseC r_CP AUC=%.3f with n_los=%d, n_nlos=%d.", ...
        cp_c_stats.r_cp_auc_best, cp_c_stats.n_los, cp_c_stats.n_nlos);
end

material_nlos_mask = upper(string(scenario_b_samples.material_class)) == "NLOS";
geometric_nlos_mask = upper(string(scenario_b_samples.geometric_class)) == "NLOS";
lines(end+1) = sprintf("Scenario B label split from export CSV: geometric NLoS=%d, material NLoS=%d.", ...
    sum(geometric_nlos_mask), sum(material_nlos_mask));

if any(material_nlos_mask)
    material_nlos_rows = scenario_b_samples(material_nlos_mask, :);
    row1 = material_nlos_rows(1, :);
    lines(end+1) = sprintf([ ...
        'Material NLoS in Scenario B is sparse: first NLoS sample is (%0.3f, %0.3f), ' ...
        'tag=%s, hits=%s, materials=%s, criterion=%s.'], ...
        row1.x_m, row1.y_m, char(string(row1.tag_id)), ...
        char(string(row1.hit_objects)), char(string(row1.hit_materials)), char(string(row1.criterion)));
end

if any(geometric_nlos_mask)
    geometric_hit_types = unique(scenario_b_samples.hit_materials(geometric_nlos_mask));
    lines(end+1) = sprintf("Geometric NLoS in Scenario B is mostly driven by: %s.", ...
        strjoin(geometric_hit_types, ', '));
end

if target_name == "material"
    lines(end+1) = "Interpretation: the perfect CP_caseB r_CP score is driven by a tiny hard-block regime, not a broad class split.";
    lines(end+1) = "Scenario B has one metal-cabinet path that flips the material label to NLoS, while most other blocked links are thin-glass geometric NLoS but material LoS.";
    lines(end+1) = "This supports a regime-selective diagnostic view: r_CP is informative when a specular, hard-block interaction dominates, but it collapses in dense clutter (Scenario C).";
else
    lines(end+1) = "Interpretation: under geometric labels, Scenario B includes many glass-partition NLoS links, so r_CP no longer tracks the label as a clean binary cue.";
    lines(end+1) = "This is consistent with parity information being partially preserved only in specific reflection/blockage regimes rather than all geometric obstructions.";
end

text_out = strjoin(cellstr(lines), newline);
end

function key = compose_position_key(scenario, x_m, y_m)
scenario = string(scenario);
x_m = double(x_m);
y_m = double(y_m);
key = strings(numel(x_m), 1);
for idx = 1:numel(x_m)
    key(idx) = sprintf('%s|%.3f|%.3f', upper(char(scenario(idx))), x_m(idx), y_m(idx));
end
end

function scene_struct = load_json_struct(path_json)
scene_struct = jsondecode(fileread(path_json));
end

function object_table = objects_to_table(scene_struct, scenario_name)
objects = scene_struct.objects;
object_table = table();
for idx = 1:numel(objects)
    obj = objects(idx);
    row = table();
    row.scenario = string(scenario_name);
    row.name = string(obj.name);
    row.material = string(obj.material);
    row.category = string(obj.category);
    row.origin_x = obj.origin(1);
    row.origin_y = obj.origin(2);
    row.origin_z = obj.origin(3);
    row.size_x = obj.size(1);
    row.size_y = obj.size(2);
    row.size_z = obj.size(3);
    if isfield(obj, 'notes')
        row.notes = string(obj.notes);
    else
        row.notes = "";
    end
    object_table = [object_table; row]; %#ok<AGROW>
end
end

function write_text_file(path_txt, content)
fid = fopen(path_txt, 'w');
if fid < 0
    error('Failed to open file for writing: %s', path_txt);
end
cleanup_obj = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', content);
end

function value = min_or_nan(x)
if isempty(x)
    value = NaN;
else
    value = min(x);
end
end

function value = max_or_nan(x)
if isempty(x)
    value = NaN;
else
    value = max(x);
end
end

function [auc_raw, auc_best] = compute_auc_pair(labels, scores)
labels = logical(labels(:));
scores = double(scores(:));
valid_mask = isfinite(scores) & isfinite(double(labels));
labels = labels(valid_mask);
scores = scores(valid_mask);

auc_raw = NaN;
auc_best = NaN;
if numel(unique(labels)) < 2
    return;
end

[~, ~, ~, auc_raw] = perfcurve(labels, scores, true);
auc_best = max(auc_raw, 1 - auc_raw);
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

function write_combined_markdown(outputs, combined_summary, cfg)
path_md = fullfile(cfg.diagnostics_dir, 'diagnostics_summary.md');
fid = fopen(path_md, 'w');
if fid < 0
    error('Failed to open markdown summary: %s', path_md);
end
cleanup_obj = onCleanup(@() fclose(fid));

fprintf(fid, '# Feature Diagnostics Summary\n\n');
fprintf(fid, '## Shared Correlation\n\n');
fprintf(fid, 'Samples used: %d\n\n', outputs.shared.n_samples);
fprintf(fid, '| Source | Target | Pearson r | Spearman rho |\n');
fprintf(fid, '|---|---|---:|---:|\n');
for idx = 1:height(outputs.shared.pair_table)
    row = outputs.shared.pair_table(idx, :);
    fprintf(fid, '| %s | %s | %.4f | %.4f |\n', ...
        char(row.source_feature), char(row.target_feature), row.pearson_r, row.spearman_rho);
end

fprintf(fid, '\n## Incremental Gain\n\n');
fprintf(fid, '| Target | Subset | Baseline AUC | Proposed AUC | Delta AUC | Baseline Brier | Proposed Brier | Delta Brier |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|\n');
for idx = 1:height(combined_summary)
    row = combined_summary(idx, :);
    fprintf(fid, '| %s | %s | %.4f | %.4f | %.4f | %.4f | %.4f | %.4f |\n', ...
        char(row.label_target), char(row.subset_name), row.baseline_auc, row.proposed_auc, ...
        row.delta_auc, row.baseline_brier, row.proposed_brier, row.delta_brier);
end

fprintf(fid, '\n## Scenario B Notes\n\n');
for idx_target = 1:numel(cfg.targets)
    target_name = cfg.targets(idx_target);
    note_text = outputs.targets.(char(target_name)).scenario_b_outputs.note_text;
    fprintf(fid, '### %s\n\n```\n%s\n```\n\n', char(target_name), note_text);
end
end
