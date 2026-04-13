function outputs = run_cp7_reviewer_diagnostics(cfg_override)
% RUN_CP7_REVIEWER_DIAGNOSTICS
% Reviewer-oriented diagnostics using channel-specific CP7 features.

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
addpath(fullfile(project_root, 'src'));

cfg = default_config(script_dir, project_root);
if nargin >= 1 && isstruct(cfg_override)
    cfg = merge_config(cfg, cfg_override);
end
ensure_dir(cfg.results_dir);
ensure_dir(fullfile(cfg.results_dir, 'shared'));

ensure_baseline_outputs_exist(cfg);
[cp7_table, cp7_metadata] = load_or_build_cp7_table(cfg);

writetable(cp7_table, fullfile(cfg.results_dir, 'shared', 'cp7_analysis_table_used.csv'));
save(fullfile(cfg.results_dir, 'shared', 'cp7_analysis_table_used.mat'), ...
    'cp7_table', 'cp7_metadata', 'cfg');

outputs = struct();
outputs.config = cfg;
outputs.cp7_metadata = cp7_metadata;
outputs.targets = struct();

combined_incremental = table();
combined_mcnemar = table();
combined_join_summary = table();

for idx_target = 1:numel(cfg.targets)
    target_name = cfg.targets(idx_target);
    fprintf('\n=== CP7 Reviewer Diagnostics: %s ===\n', target_name);

    target_outputs = run_target_diagnostics(target_name, cp7_table, cfg);
    outputs.targets.(char(target_name)) = target_outputs;

    incremental_block = target_outputs.incremental_summary;
    incremental_block.label_target = repmat(string(target_name), height(incremental_block), 1);
    incremental_block = movevars(incremental_block, 'label_target', 'Before', 'scope');
    combined_incremental = [combined_incremental; incremental_block]; %#ok<AGROW>

    mcnemar_block = target_outputs.mcnemar_table;
    mcnemar_block.label_target = repmat(string(target_name), height(mcnemar_block), 1);
    mcnemar_block = movevars(mcnemar_block, 'label_target', 'Before', 'scope');
    combined_mcnemar = [combined_mcnemar; mcnemar_block]; %#ok<AGROW>

    join_row = target_outputs.join_summary;
    join_row.label_target = repmat(string(target_name), height(join_row), 1);
    join_row = movevars(join_row, 'label_target', 'Before', 'n_baseline_rows');
    combined_join_summary = [combined_join_summary; join_row]; %#ok<AGROW>
end

writetable(combined_incremental, fullfile(cfg.results_dir, 'incremental_summary_all_targets.csv'));
writetable(combined_mcnemar, fullfile(cfg.results_dir, 'mcnemar_all_targets.csv'));
writetable(combined_join_summary, fullfile(cfg.results_dir, 'join_summary_all_targets.csv'));

write_summary_markdown(outputs, combined_incremental, combined_mcnemar, cfg);

outputs.incremental_summary = combined_incremental;
outputs.mcnemar_table = combined_mcnemar;
outputs.join_summary = combined_join_summary;
outputs.timestamp = datetime('now');
save(fullfile(cfg.results_dir, 'cp7_reviewer_diagnostics_outputs.mat'), 'outputs', '-v7.3');
end

function cfg = default_config(script_dir, project_root)
cfg = struct();
cfg.script_dir = script_dir;
cfg.project_root = project_root;
cfg.results_root_dir = fullfile(script_dir, 'results');
cfg.results_dir = fullfile(cfg.results_root_dir, 'cp7_reviewer_diagnostics');
cfg.targets = ["material", "geometric"];
cfg.scopes = ["B", "C", "B+C"];
cfg.random_seed = 42;
cfg.cv_folds = 5;
cfg.classification_threshold = 0.5;
cfg.hard_case_band = [0.4, 0.6];
cfg.logistic_lambda = 1e-2;
cfg.metric_bootstrap_repeats = 1000;
cfg.cv_strategy = "stratified_kfold";

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

cfg.focus_top_features = {'fp_energy_db', 'skewness_pdp', 'kurtosis_pdp'};
cfg.case_feature_set = [cfg.baseline_features, cfg.cp7_features];
cfg.case_names = ["CP_caseB", "CP_caseC"];
cfg.case_feature_focus = cfg.cp7_features;

cfg.label_csv = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_all_scenarios_los_nlos.csv');
cfg.scenario_b_json = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_scenario_b.json');
cfg.scenario_c_json = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_scenario_c.json');
cfg.cp7_cached_csv = fullfile(project_root, 'cp7_feature_diagnostics_project', '01_sanity', 'cp7_analysis_table.csv');
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

function [cp7_table, metadata] = load_or_build_cp7_table(cfg)
metadata = struct();
metadata.source = "";

if isfile(cfg.cp7_cached_csv)
    cp7_table = readtable(cfg.cp7_cached_csv, 'TextType', 'string');
    metadata.source = string(cfg.cp7_cached_csv);
else
    [cp7_table, metadata_build] = build_cp7_analysis_table(cfg.project_root, struct('label_csv', cfg.label_csv));
    metadata = metadata_build;
    metadata.source = "build_cp7_analysis_table";
end

cp7_table.scenario = string(cp7_table.scenario);
cp7_table.case_id = string(cp7_table.case_id);
cp7_table.case_name = "CP_" + cp7_table.case_id;
cp7_table.key = compose_position_key(cp7_table.scenario, cp7_table.x_m, cp7_table.y_m);

if ~ismember('label_geometric', cp7_table.Properties.VariableNames)
    cp7_table.label_geometric = nan(height(cp7_table), 1);
end
if ~ismember('label_material', cp7_table.Properties.VariableNames)
    cp7_table.label_material = nan(height(cp7_table), 1);
end

cp7_table = sortrows(cp7_table, {'scenario', 'pos_id'}, {'ascend', 'ascend'});
metadata.n_rows = height(cp7_table);
end

function target_outputs = run_target_diagnostics(target_name, cp7_table, cfg)
target_dir = fullfile(cfg.results_dir, char(target_name));
ensure_dir(target_dir);

dataset_table = build_target_dataset(target_name, cp7_table, cfg);
join_summary = summarize_join(target_name, dataset_table, cfg);
correlation_outputs = run_correlation_analysis(dataset_table, cfg);

writetable(dataset_table, fullfile(target_dir, 'cp7_target_dataset.csv'));
writetable(join_summary, fullfile(target_dir, 'join_summary.csv'));
writetable(correlation_outputs.pair_table, fullfile(target_dir, 'correlation_pairs_all.csv'));
writetable(correlation_outputs.focus_pair_table, fullfile(target_dir, 'correlation_focus_pairs.csv'));
writetable(correlation_outputs.orthogonality_summary, fullfile(target_dir, 'orthogonality_summary.csv'));
writetable(correlation_outputs.pearson_matrix, fullfile(target_dir, 'correlation_pearson_matrix.csv'), 'WriteRowNames', true);
writetable(correlation_outputs.spearman_matrix, fullfile(target_dir, 'correlation_spearman_matrix.csv'), 'WriteRowNames', true);

incremental_summary = table();
mcnemar_table = table();
coefficient_table = table();
scope_results = struct();

for idx_scope = 1:numel(cfg.scopes)
    scope_name = cfg.scopes(idx_scope);
    scope_result = run_scope_analysis(scope_name, dataset_table, cfg);
    scope_results.(scope_field_name(scope_name)) = scope_result;

    incremental_summary = [incremental_summary; scope_result.incremental_summary]; %#ok<AGROW>
    mcnemar_table = [mcnemar_table; scope_result.mcnemar_table]; %#ok<AGROW>
    coefficient_table = [coefficient_table; scope_result.coefficient_table]; %#ok<AGROW>
end

writetable(incremental_summary, fullfile(target_dir, 'incremental_summary.csv'));
writetable(mcnemar_table, fullfile(target_dir, 'mcnemar_tests.csv'));
writetable(coefficient_table, fullfile(target_dir, 'logistic_coefficients.csv'));

bc_result = scope_results.bc;
rescue_outputs = compute_rescue_analysis(bc_result.dataset_table, bc_result.labels, bc_result.baseline_eval, bc_result.proposed_eval, cfg);
case_outputs = compute_case_analysis(target_name, bc_result.dataset_table, bc_result.labels, bc_result.baseline_eval, bc_result.proposed_eval, cfg);

writetable(rescue_outputs.overall, fullfile(target_dir, 'misclassification_recovery_overall.csv'));
writetable(rescue_outputs.by_case, fullfile(target_dir, 'misclassification_recovery_by_case.csv'));
writetable(rescue_outputs.by_scenario, fullfile(target_dir, 'misclassification_recovery_by_scenario.csv'));
writetable(rescue_outputs.sample_table, fullfile(target_dir, 'misclassification_recovery_samples.csv'));
writetable(case_outputs.case_feature_auc, fullfile(target_dir, 'case_feature_auc.csv'));
writetable(case_outputs.gamma_case_stats, fullfile(target_dir, 'gamma_case_stats.csv'));
writetable(case_outputs.scenario_b_samples, fullfile(target_dir, 'scenario_b_samples.csv'));
writetable(case_outputs.scenario_b_objects, fullfile(target_dir, 'scenario_b_objects.csv'));
writetable(case_outputs.scenario_c_objects, fullfile(target_dir, 'scenario_c_objects.csv'));
write_text_file(fullfile(target_dir, 'scenario_bc_note.txt'), case_outputs.note_text);
if ~isempty(bc_result.prediction_table)
    writetable(bc_result.prediction_table, fullfile(target_dir, 'oof_predictions_bc.csv'));
end

target_outputs = struct();
target_outputs.dataset_table = dataset_table;
target_outputs.join_summary = join_summary;
target_outputs.correlation_outputs = correlation_outputs;
target_outputs.incremental_summary = incremental_summary;
target_outputs.mcnemar_table = mcnemar_table;
target_outputs.coefficient_table = coefficient_table;
target_outputs.scope_results = scope_results;
target_outputs.rescue_outputs = rescue_outputs;
target_outputs.case_outputs = case_outputs;
end

function dataset_table = build_target_dataset(target_name, cp7_table, cfg)
baseline_path = fullfile(cfg.results_root_dir, char(target_name), 'baseline_feature_table.csv');
if ~isfile(baseline_path)
    error('[run_cp7_reviewer_diagnostics] Missing baseline table: %s', baseline_path);
end

baseline_table = readtable(baseline_path, 'TextType', 'string');
baseline_table.case_name = string(baseline_table.case_name);
baseline_table.scenario = string(baseline_table.scenario);
baseline_table.polarization = string(baseline_table.polarization);
baseline_table.key = compose_position_key(baseline_table.scenario, baseline_table.x_m, baseline_table.y_m);
baseline_table = baseline_table(ismember(baseline_table.case_name, cfg.case_names) & baseline_table.polarization == "CP", :);

label_col_cp7 = target_to_cp7_label(target_name);
baseline_keep = [{'key', 'case_name', 'scenario', 'polarization', 'pos_id', 'x_m', 'y_m', 'label', 'valid_flag', 'valid_for_model'}, cfg.baseline_features];
cp7_keep = [{'key', 'all_features_valid', label_col_cp7}, cfg.cp7_features];

cp7_join = cp7_table(:, cp7_keep);
dataset_table = innerjoin(baseline_table(:, baseline_keep), cp7_join, 'Keys', 'key');

dataset_table.label = logical(dataset_table.label);
dataset_table.label_cp7 = logical(dataset_table.(label_col_cp7) == 1);
dataset_table.label_match = dataset_table.label == dataset_table.label_cp7;
dataset_table.valid_for_cp7_model = logical(dataset_table.valid_for_model) & logical(dataset_table.all_features_valid);
dataset_table = removevars(dataset_table, {label_col_cp7});
dataset_table = sortrows(dataset_table, {'scenario', 'pos_id'}, {'ascend', 'ascend'});
end

function join_summary = summarize_join(target_name, dataset_table, cfg)
baseline_path = fullfile(cfg.results_root_dir, char(target_name), 'baseline_feature_table.csv');
baseline_table = readtable(baseline_path, 'TextType', 'string');
baseline_table.case_name = string(baseline_table.case_name);
baseline_table.polarization = string(baseline_table.polarization);
baseline_table = baseline_table(ismember(baseline_table.case_name, cfg.case_names) & baseline_table.polarization == "CP", :);

cp7_keys = unique(dataset_table.key);
baseline_keys = compose_position_key(string(baseline_table.scenario), baseline_table.x_m, baseline_table.y_m);

join_summary = table();
join_summary.n_baseline_rows = height(baseline_table);
join_summary.n_cp7_rows_joined = numel(cp7_keys);
join_summary.n_distinct_baseline_keys = numel(unique(baseline_keys));
join_summary.n_distinct_joined_keys = numel(cp7_keys);
join_summary.n_unmatched_baseline_keys = numel(setdiff(unique(baseline_keys), cp7_keys));
join_summary.n_joined_rows = height(dataset_table);
join_summary.n_label_mismatch = sum(~dataset_table.label_match);
join_summary.n_valid_for_cp7_model = sum(dataset_table.valid_for_cp7_model);
join_summary.n_los_valid = sum(dataset_table.valid_for_cp7_model & dataset_table.label);
join_summary.n_nlos_valid = sum(dataset_table.valid_for_cp7_model & ~dataset_table.label);
end

function correlation_outputs = run_correlation_analysis(dataset_table, cfg)
valid_table = dataset_table(dataset_table.valid_for_cp7_model, :);
all_features = [cfg.baseline_features, cfg.cp7_features];
X = valid_table{:, all_features};

[pearson_r, pearson_p] = corr(X, 'Type', 'Pearson', 'Rows', 'pairwise');
[spearman_rho, spearman_p] = corr(X, 'Type', 'Spearman', 'Rows', 'pairwise');

pearson_matrix = array2table(pearson_r, 'VariableNames', all_features, 'RowNames', all_features);
spearman_matrix = array2table(spearman_rho, 'VariableNames', all_features, 'RowNames', all_features);

pair_table = table();
focus_pair_table = table();
for idx_cp7 = 1:numel(cfg.cp7_features)
    cp7_name = cfg.cp7_features{idx_cp7};
    cp7_idx = find(strcmp(all_features, cp7_name), 1, 'first');
    for idx_base = 1:numel(cfg.baseline_features)
        base_name = cfg.baseline_features{idx_base};
        base_idx = find(strcmp(all_features, base_name), 1, 'first');

        row = table();
        row.cp7_feature = string(cp7_name);
        row.baseline_feature = string(base_name);
        row.pearson_r = pearson_r(cp7_idx, base_idx);
        row.pearson_p = pearson_p(cp7_idx, base_idx);
        row.spearman_rho = spearman_rho(cp7_idx, base_idx);
        row.spearman_p = spearman_p(cp7_idx, base_idx);
        row.abs_pearson_r = abs(row.pearson_r);
        row.abs_spearman_rho = abs(row.spearman_rho);
        pair_table = [pair_table; row]; %#ok<AGROW>
        if ismember(base_name, cfg.focus_top_features)
            focus_pair_table = [focus_pair_table; row]; %#ok<AGROW>
        end
    end
end

orthogonality_summary = table();
for idx_cp7 = 1:numel(cfg.cp7_features)
    cp7_name = string(cfg.cp7_features{idx_cp7});
    mask = focus_pair_table.cp7_feature == cp7_name;
    row = table();
    row.cp7_feature = cp7_name;
    row.max_abs_pearson_top3 = max(focus_pair_table.abs_pearson_r(mask), [], 'omitnan');
    row.mean_abs_pearson_top3 = mean(focus_pair_table.abs_pearson_r(mask), 'omitnan');
    row.max_abs_spearman_top3 = max(focus_pair_table.abs_spearman_rho(mask), [], 'omitnan');
    row.mean_abs_spearman_top3 = mean(focus_pair_table.abs_spearman_rho(mask), 'omitnan');
    orthogonality_summary = [orthogonality_summary; row]; %#ok<AGROW>
end

correlation_outputs = struct();
correlation_outputs.pearson_matrix = pearson_matrix;
correlation_outputs.spearman_matrix = spearman_matrix;
correlation_outputs.pair_table = sortrows(pair_table, {'cp7_feature', 'baseline_feature'});
correlation_outputs.focus_pair_table = sortrows(focus_pair_table, {'cp7_feature', 'baseline_feature'});
correlation_outputs.orthogonality_summary = sortrows(orthogonality_summary, 'mean_abs_spearman_top3', 'ascend');
end

function scope_result = run_scope_analysis(scope_name, dataset_table, cfg)
scope_mask = scope_mask_from_name(dataset_table.scenario, scope_name);
scope_table = dataset_table(scope_mask & dataset_table.valid_for_cp7_model, :);
labels = logical(scope_table.label);

incremental_summary = table();
mcnemar_table = table();
coefficient_table = table();
prediction_table = table();

skip_scope = false;
skip_reason = "";
folds = safe_cv_folds(labels, cfg.cv_folds);
if isempty(scope_table) || numel(unique(labels)) < 2 || folds < 2
    skip_scope = true;
    if isempty(scope_table)
        skip_reason = "no valid samples";
    elseif numel(unique(labels)) < 2
        skip_reason = "single_class";
    else
        skip_reason = "insufficient_minority";
    end
end

if skip_scope
    incremental_summary = build_skipped_incremental(scope_name, "overall", height(scope_table), sum(labels), sum(~labels), skip_reason, cfg);
    incremental_summary = [incremental_summary; ...
        build_skipped_incremental(scope_name, "hard_case_0p4_0p6", 0, NaN, NaN, skip_reason, cfg)]; %#ok<AGROW>
    mcnemar_table = build_skipped_mcnemar(scope_name, "overall", height(scope_table), skip_reason);
    mcnemar_table = [mcnemar_table; build_skipped_mcnemar(scope_name, "hard_case_0p4_0p6", 0, skip_reason)]; %#ok<AGROW>

    scope_result = struct();
    scope_result.scope = string(scope_name);
    scope_result.skip_scope = true;
    scope_result.skip_reason = string(skip_reason);
    scope_result.dataset_table = scope_table;
    scope_result.labels = labels;
    scope_result.baseline_eval = empty_eval(cfg.baseline_features);
    scope_result.proposed_eval = empty_eval([cfg.baseline_features, cfg.cp7_features]);
    scope_result.incremental_summary = incremental_summary;
    scope_result.mcnemar_table = mcnemar_table;
    scope_result.coefficient_table = coefficient_table;
    scope_result.prediction_table = prediction_table;
    scope_result.cv_record = struct();
    return;
end

fprintf('[scope] %s: n=%d, LoS=%d, NLoS=%d, folds=%d\n', ...
    char(scope_name), height(scope_table), sum(labels), sum(~labels), folds);

cv_plan = build_cv_plan(scope_table, labels, folds, cfg.random_seed, cfg.cv_strategy);
baseline_eval = cross_validated_logistic(scope_table, labels, cfg.baseline_features, cv_plan, cfg);
proposed_eval = cross_validated_logistic(scope_table, labels, [cfg.baseline_features, cfg.cp7_features], cv_plan, cfg);

hard_mask = baseline_eval.score >= cfg.hard_case_band(1) & baseline_eval.score <= cfg.hard_case_band(2);

incremental_summary = compare_model_rows(scope_name, "overall", labels, baseline_eval, proposed_eval, true(size(labels)), cfg);
incremental_summary = [incremental_summary; ...
    compare_model_rows(scope_name, "hard_case_0p4_0p6", labels, baseline_eval, proposed_eval, hard_mask, cfg)]; %#ok<AGROW>

mcnemar_table = mcnemar_row(scope_name, "overall", labels, baseline_eval.pred, proposed_eval.pred, true(size(labels)));
mcnemar_table = [mcnemar_table; ...
    mcnemar_row(scope_name, "hard_case_0p4_0p6", labels, baseline_eval.pred, proposed_eval.pred, hard_mask)]; %#ok<AGROW>

coefficient_table = [ ...
    export_model_coefficients(scope_name, "baseline", baseline_eval.full_model); ...
    export_model_coefficients(scope_name, "proposed", proposed_eval.full_model)];

prediction_table = scope_table(:, [{'case_name', 'scenario', 'pos_id', 'x_m', 'y_m', 'label'}, cfg.baseline_features, cfg.cp7_features]);
prediction_table.baseline_score = baseline_eval.score;
prediction_table.proposed_score = proposed_eval.score;
prediction_table.baseline_pred = baseline_eval.pred;
prediction_table.proposed_pred = proposed_eval.pred;
prediction_table.fold_id = baseline_eval.fold_id;
prediction_table.hard_case_mask = hard_mask;
prediction_table = sortrows(prediction_table, {'scenario', 'pos_id'}, {'ascend', 'ascend'});

scope_result = struct();
scope_result.scope = string(scope_name);
scope_result.skip_scope = false;
scope_result.skip_reason = "";
scope_result.dataset_table = scope_table;
scope_result.labels = labels;
scope_result.baseline_eval = baseline_eval;
scope_result.proposed_eval = proposed_eval;
scope_result.incremental_summary = incremental_summary;
scope_result.mcnemar_table = mcnemar_table;
scope_result.coefficient_table = coefficient_table;
scope_result.prediction_table = prediction_table;
scope_result.cv_record = cv_plan;
end

function eval_outputs = cross_validated_logistic(dataset_table, labels, feature_names, cv_plan, cfg)
X_all = dataset_table{:, feature_names};
n_samples = size(X_all, 1);

score = nan(n_samples, 1);
pred = false(n_samples, 1);
fold_id = zeros(n_samples, 1);

for idx_fold = 1:cv_plan.num_test_sets
    train_mask = cv_plan.train_masks{idx_fold};
    test_mask = cv_plan.test_masks{idx_fold};

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

if all(~isnan(score))
    [X_all_norm, norm_params_all] = normalize_feature_matrix(X_all);
    full_model = fit_logistic_model(X_all_norm, labels, cfg);
    full_model.normalization = norm_params_all;
    full_model.feature_names = feature_names;
else
    full_model = empty_model(feature_names);
end

eval_outputs = struct();
eval_outputs.feature_names = feature_names;
eval_outputs.score = score;
eval_outputs.pred = pred;
eval_outputs.fold_id = fold_id;
eval_outputs.full_model = full_model;
end

function cv_plan = build_cv_plan(dataset_table, labels, folds, seed, strategy)
strategy = string(strategy);
labels = logical(labels(:));
n_samples = numel(labels);

switch strategy
    case "stratified_kfold"
        rng(seed);
        cv = cvpartition(labels, 'KFold', folds);
        train_masks = cell(cv.NumTestSets, 1);
        test_masks = cell(cv.NumTestSets, 1);
        fold_assignment = zeros(n_samples, 1);
        for idx_fold = 1:cv.NumTestSets
            train_masks{idx_fold} = training(cv, idx_fold);
            test_masks{idx_fold} = test(cv, idx_fold);
            fold_assignment(test_masks{idx_fold}) = idx_fold;
        end
        cv_plan = struct();
        cv_plan.strategy = strategy;
        cv_plan.seed = seed;
        cv_plan.num_test_sets = cv.NumTestSets;
        cv_plan.train_masks = train_masks;
        cv_plan.test_masks = test_masks;
        cv_plan.fold_assignment = fold_assignment;
    otherwise
        error('[run_cp7_reviewer_diagnostics] Unsupported cv strategy: %s', strategy);
end
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
    warning('[run_cp7_reviewer_diagnostics] fitclinear failed (%s). Falling back to fitglm.', ...
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
        error('[run_cp7_reviewer_diagnostics] Unsupported backend: %s', string(model.backend));
end
end

function y = logistic_sigmoid(x)
x = max(min(double(x), 60), -60);
y = 1 ./ (1 + exp(-x));
end

function row = compare_model_rows(scope_name, subset_name, labels, baseline_eval, proposed_eval, subset_mask, cfg)
subset_mask = logical(subset_mask(:));
labels = logical(labels(:));

row = table();
row.scope = string(scope_name);
row.subset_name = string(subset_name);
row.n_samples = sum(subset_mask);
row.n_los = sum(labels(subset_mask));
row.n_nlos = sum(~labels(subset_mask));
row.status = "ok";
row.skip_reason = "";

if row.n_samples == 0 || numel(unique(labels(subset_mask))) < 2
    row.baseline_auc = NaN;
    row.proposed_auc = NaN;
    row.delta_auc = NaN;
    row.n_boot_valid = NaN;
    row.baseline_auc_ci_low = NaN;
    row.baseline_auc_ci_high = NaN;
    row.proposed_auc_ci_low = NaN;
    row.proposed_auc_ci_high = NaN;
    row.delta_auc_ci_low = NaN;
    row.delta_auc_ci_high = NaN;
    row.baseline_brier = NaN;
    row.proposed_brier = NaN;
    row.delta_brier = NaN;
    row.baseline_accuracy = NaN;
    row.proposed_accuracy = NaN;
    row.delta_accuracy = NaN;
    row.confidence_band_low = cfg.hard_case_band(1);
    row.confidence_band_high = cfg.hard_case_band(2);
    if row.n_samples == 0
        row.status = "empty_subset";
        row.skip_reason = "no samples in subset";
    else
        row.status = "single_class_subset";
        row.skip_reason = "subset has single class";
    end
    return;
end

base_row = metrics_table_from_vectors(labels(subset_mask), baseline_eval.score(subset_mask), baseline_eval.pred(subset_mask), "baseline");
prop_row = metrics_table_from_vectors(labels(subset_mask), proposed_eval.score(subset_mask), proposed_eval.pred(subset_mask), "proposed");

row.baseline_auc = base_row.auc;
row.proposed_auc = prop_row.auc;
row.delta_auc = prop_row.auc - base_row.auc;
[row.n_boot_valid, row.baseline_auc_ci_low, row.baseline_auc_ci_high, ...
    row.proposed_auc_ci_low, row.proposed_auc_ci_high, ...
    row.delta_auc_ci_low, row.delta_auc_ci_high] = ...
    bootstrap_auc_comparison(labels(subset_mask), baseline_eval.score(subset_mask), proposed_eval.score(subset_mask), cfg);
row.baseline_brier = base_row.brier_score;
row.proposed_brier = prop_row.brier_score;
row.delta_brier = prop_row.brier_score - base_row.brier_score;
row.baseline_accuracy = base_row.accuracy;
row.proposed_accuracy = prop_row.accuracy;
row.delta_accuracy = prop_row.accuracy - base_row.accuracy;
row.confidence_band_low = cfg.hard_case_band(1);
row.confidence_band_high = cfg.hard_case_band(2);
end

function row = build_skipped_incremental(scope_name, subset_name, n_samples, n_los, n_nlos, skip_reason, cfg)
row = table();
row.scope = string(scope_name);
row.subset_name = string(subset_name);
row.n_samples = n_samples;
row.n_los = n_los;
row.n_nlos = n_nlos;
row.status = "skipped";
row.skip_reason = string(skip_reason);
row.baseline_auc = NaN;
row.proposed_auc = NaN;
row.delta_auc = NaN;
row.n_boot_valid = NaN;
row.baseline_auc_ci_low = NaN;
row.baseline_auc_ci_high = NaN;
row.proposed_auc_ci_low = NaN;
row.proposed_auc_ci_high = NaN;
row.delta_auc_ci_low = NaN;
row.delta_auc_ci_high = NaN;
row.baseline_brier = NaN;
row.proposed_brier = NaN;
row.delta_brier = NaN;
row.baseline_accuracy = NaN;
row.proposed_accuracy = NaN;
row.delta_accuracy = NaN;
row.confidence_band_low = cfg.hard_case_band(1);
row.confidence_band_high = cfg.hard_case_band(2);
end

function [n_boot_valid, baseline_ci_low, baseline_ci_high, proposed_ci_low, proposed_ci_high, delta_ci_low, delta_ci_high] = bootstrap_auc_comparison(labels, baseline_scores, proposed_scores, cfg)
labels = logical(labels(:));
baseline_scores = double(baseline_scores(:));
proposed_scores = double(proposed_scores(:));
n_samples = numel(labels);

baseline_auc_boot = nan(cfg.metric_bootstrap_repeats, 1);
proposed_auc_boot = nan(cfg.metric_bootstrap_repeats, 1);
delta_auc_boot = nan(cfg.metric_bootstrap_repeats, 1);

for idx_boot = 1:cfg.metric_bootstrap_repeats
    rng(cfg.random_seed + idx_boot - 1);
    sample_idx = randi(n_samples, n_samples, 1);
    labels_b = labels(sample_idx);
    if numel(unique(labels_b)) < 2
        continue;
    end
    baseline_auc_boot(idx_boot) = compute_auc(labels_b, baseline_scores(sample_idx));
    proposed_auc_boot(idx_boot) = compute_auc(labels_b, proposed_scores(sample_idx));
    delta_auc_boot(idx_boot) = proposed_auc_boot(idx_boot) - baseline_auc_boot(idx_boot);
end

baseline_valid = baseline_auc_boot(isfinite(baseline_auc_boot));
proposed_valid = proposed_auc_boot(isfinite(proposed_auc_boot));
delta_valid = delta_auc_boot(isfinite(delta_auc_boot));
n_boot_valid = numel(delta_valid);
baseline_ci_low = safe_quantile(baseline_valid, 0.025);
baseline_ci_high = safe_quantile(baseline_valid, 0.975);
proposed_ci_low = safe_quantile(proposed_valid, 0.025);
proposed_ci_high = safe_quantile(proposed_valid, 0.975);
delta_ci_low = safe_quantile(delta_valid, 0.025);
delta_ci_high = safe_quantile(delta_valid, 0.975);
end

function row = mcnemar_row(scope_name, subset_name, labels, baseline_pred, proposed_pred, subset_mask)
subset_mask = logical(subset_mask(:));
labels = logical(labels(:));
baseline_correct = logical(baseline_pred(:)) == labels;
proposed_correct = logical(proposed_pred(:)) == labels;

baseline_correct = baseline_correct(subset_mask);
proposed_correct = proposed_correct(subset_mask);

row = table();
row.scope = string(scope_name);
row.subset_name = string(subset_name);
row.n_samples = sum(subset_mask);
row.status = "ok";
row.skip_reason = "";

if row.n_samples == 0
    row.baseline_correct_proposed_wrong = NaN;
    row.baseline_wrong_proposed_correct = NaN;
    row.chi_square_cc = NaN;
    row.p_value_exact = NaN;
    row.status = "empty_subset";
    row.skip_reason = "no samples in subset";
    return;
end

if numel(unique(labels(subset_mask))) < 2
    row.baseline_correct_proposed_wrong = NaN;
    row.baseline_wrong_proposed_correct = NaN;
    row.chi_square_cc = NaN;
    row.p_value_exact = NaN;
    row.status = "single_class_subset";
    row.skip_reason = "subset has single class";
    return;
end

[p_value, statistic_cc, exact_b, exact_c] = mcnemar_exact_test(baseline_correct, proposed_correct);
row.baseline_correct_proposed_wrong = exact_b;
row.baseline_wrong_proposed_correct = exact_c;
row.chi_square_cc = statistic_cc;
row.p_value_exact = p_value;
end

function row = build_skipped_mcnemar(scope_name, subset_name, n_samples, skip_reason)
row = table();
row.scope = string(scope_name);
row.subset_name = string(subset_name);
row.n_samples = n_samples;
row.status = "skipped";
row.skip_reason = string(skip_reason);
row.baseline_correct_proposed_wrong = NaN;
row.baseline_wrong_proposed_correct = NaN;
row.chi_square_cc = NaN;
row.p_value_exact = NaN;
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

function rescue_outputs = compute_rescue_analysis(dataset_table, labels, baseline_eval, proposed_eval, cfg)
if isempty(dataset_table) || isempty(baseline_eval.score)
    rescue_outputs = empty_rescue_outputs();
    return;
end

baseline_wrong = baseline_eval.pred ~= labels;
proposed_wrong = proposed_eval.pred ~= labels;
rescued = baseline_wrong & ~proposed_wrong;
harmed = ~baseline_wrong & proposed_wrong;

sample_vars = [{'case_name', 'scenario', 'pos_id', 'x_m', 'y_m', 'label'}, cfg.baseline_features, cfg.cp7_features];
sample_table = dataset_table(:, sample_vars);
sample_table.baseline_score = baseline_eval.score;
sample_table.proposed_score = proposed_eval.score;
sample_table.baseline_pred = baseline_eval.pred;
sample_table.proposed_pred = proposed_eval.pred;
sample_table.baseline_wrong = baseline_wrong;
sample_table.proposed_wrong = proposed_wrong;
sample_table.rescued_by_proposed = rescued;
sample_table.harmed_by_proposed = harmed;
sample_table.score_delta_proposed_minus_baseline = proposed_eval.score - baseline_eval.score;
sample_table = sortrows(sample_table, {'rescued_by_proposed', 'harmed_by_proposed', 'scenario', 'pos_id'}, ...
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

function out = empty_rescue_outputs()
out = struct();
out.overall = table();
out.by_case = table();
out.by_scenario = table();
out.sample_table = table();
end

function grouped = grouped_rescue_table(sample_table, group_column)
if isempty(sample_table)
    grouped = table();
    return;
end

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

function case_outputs = compute_case_analysis(target_name, dataset_table, labels, baseline_eval, proposed_eval, cfg)
if isempty(dataset_table)
    case_outputs = empty_case_outputs();
    return;
end

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
scenario_b_samples = outerjoin( ...
    scenario_b_dataset, ...
    label_meta(:, {'key', 'tag_id', 'geometric_class', 'material_class', 'penetration_loss_db', 'num_hits', 'hit_objects', 'hit_materials', 'criterion'}), ...
    'Keys', 'key', ...
    'MergeKeys', true, ...
    'Type', 'left');
scenario_b_samples = removevars(scenario_b_samples, intersect({'key'}, scenario_b_samples.Properties.VariableNames));

case_feature_auc = table();
for idx_case = 1:numel(cfg.case_names)
    case_name = cfg.case_names(idx_case);
    case_mask = dataset_table.case_name == case_name;
    labels_case = labels(case_mask);
    n_los = sum(labels_case);
    n_nlos = sum(~labels_case);

    for idx_feature = 1:numel(cfg.case_feature_set)
        feature_name = string(cfg.case_feature_set{idx_feature});
        values = dataset_table.(cfg.case_feature_set{idx_feature})(case_mask);
        [auc_raw, auc_best] = compute_auc_pair(labels_case, values);

        row = table();
        row.case_name = case_name;
        row.feature_name = feature_name;
        row.n_samples = sum(case_mask);
        row.n_los = n_los;
        row.n_nlos = n_nlos;
        row.auc_raw = auc_raw;
        row.auc_best_direction = auc_best;
        row.direction = auc_direction_text(auc_raw);
        case_feature_auc = [case_feature_auc; row]; %#ok<AGROW>
    end
end

gamma_case_stats = table();
for idx_case = 1:numel(cfg.case_names)
    case_name = cfg.case_names(idx_case);
    case_mask = dataset_table.case_name == case_name;
    labels_case = labels(case_mask);
    for idx_feature = 1:numel(cfg.case_feature_focus)
        feature_name = string(cfg.case_feature_focus{idx_feature});
        values = dataset_table.(cfg.case_feature_focus{idx_feature})(case_mask);
        [auc_raw, auc_best] = compute_auc_pair(labels_case, values);

        los_values = values(labels_case);
        nlos_values = values(~labels_case);
        [perfect_sep, sep_direction, threshold_value, sep_margin] = detect_perfect_separation(los_values, nlos_values);

        row = table();
        row.case_name = case_name;
        row.feature_name = feature_name;
        row.n_samples = sum(case_mask);
        row.n_los = sum(labels_case);
        row.n_nlos = sum(~labels_case);
        row.auc_raw = auc_raw;
        row.auc_best_direction = auc_best;
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
        gamma_case_stats = [gamma_case_stats; row]; %#ok<AGROW>
    end
end

scenario_b_objects = objects_to_table(load_json_struct(cfg.scenario_b_json), "B");
scenario_c_objects = objects_to_table(load_json_struct(cfg.scenario_c_json), "C");
note_text = build_scenario_note(target_name, scenario_b_samples, gamma_case_stats, scenario_b_objects, scenario_c_objects);

case_outputs = struct();
case_outputs.case_feature_auc = case_feature_auc;
case_outputs.gamma_case_stats = gamma_case_stats;
case_outputs.scenario_b_samples = scenario_b_samples;
case_outputs.scenario_b_objects = scenario_b_objects;
case_outputs.scenario_c_objects = scenario_c_objects;
case_outputs.note_text = note_text;
end

function out = empty_case_outputs()
out = struct();
out.case_feature_auc = table();
out.gamma_case_stats = table();
out.scenario_b_samples = table();
out.scenario_b_objects = table();
out.scenario_c_objects = table();
out.note_text = "";
end

function text_out = build_scenario_note(target_name, scenario_b_samples, gamma_case_stats, scenario_b_objects, scenario_c_objects)
target_name = string(target_name);
lines = strings(0, 1);
lines(end+1) = "Scenario B/C CP7 note";
lines(end+1) = sprintf("Target: %s", target_name);
lines(end+1) = sprintf("Scenario B objects: %d (%s)", ...
    height(scenario_b_objects), strjoin(unique(scenario_b_objects.material), ', '));
lines(end+1) = sprintf("Scenario C objects: %d (%s)", ...
    height(scenario_c_objects), strjoin(unique(scenario_c_objects.material), ', '));

case_name_list = ["CP_caseB", "CP_caseC"];
for idx_case = 1:numel(case_name_list)
    case_block = gamma_case_stats(gamma_case_stats.case_name == case_name_list(idx_case) & ...
        ismember(gamma_case_stats.feature_name, ["gamma_CP_rx1", "gamma_CP_rx2"]), :);
    if isempty(case_block)
        continue;
    end
    for idx_row = 1:height(case_block)
        row = case_block(idx_row, :);
        lines(end+1) = sprintf("%s %s AUC=%.3f with n_los=%d, n_nlos=%d.", ...
            char(row.case_name), char(row.feature_name), row.auc_best_direction, row.n_los, row.n_nlos);
    end
end

material_nlos_mask = upper(string(scenario_b_samples.material_class)) == "NLOS";
geometric_nlos_mask = upper(string(scenario_b_samples.geometric_class)) == "NLOS";
lines(end+1) = sprintf("Scenario B label split from export CSV: geometric NLoS=%d, material NLoS=%d.", ...
    sum(geometric_nlos_mask), sum(material_nlos_mask));

if any(material_nlos_mask)
    material_row = scenario_b_samples(find(material_nlos_mask, 1, 'first'), :);
    lines(end+1) = sprintf([ ...
        'First material-NLoS sample in Scenario B: (%0.3f, %0.3f), tag=%s, hits=%s, materials=%s, criterion=%s.'], ...
        material_row.x_m, material_row.y_m, char(string(material_row.tag_id)), ...
        char(string(material_row.hit_objects)), char(string(material_row.hit_materials)), char(string(material_row.criterion)));
end

if any(geometric_nlos_mask)
    hit_types = unique(scenario_b_samples.hit_materials(geometric_nlos_mask));
    lines(end+1) = sprintf("Scenario B geometric NLoS hit materials: %s.", strjoin(hit_types, ', '));
end

if target_name == "material"
    lines(end+1) = "Interpretation: CP7 gains should be read as regime-selective. Scenario B material NLoS is driven by an extremely sparse hard-block sample, while Scenario C mixes diffuse interactions that weaken parity cues.";
else
    lines(end+1) = "Interpretation: under geometric labels, many glass-partition links are already NLoS, so channel-specific parity and polarization cues become diagnostic only in selected sub-regimes.";
end

text_out = strjoin(cellstr(lines), newline);
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

function feature_dir = auc_direction_text(auc_raw)
if ~isfinite(auc_raw)
    feature_dir = "";
elseif auc_raw >= 0.5
    feature_dir = "higher_is_los";
else
    feature_dir = "higher_is_nlos";
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

function auc = compute_auc(labels, scores)
labels = logical(labels(:));
scores = double(scores(:));
valid_mask = isfinite(scores);
labels = labels(valid_mask);
scores = scores(valid_mask);
if numel(unique(labels)) < 2
    auc = NaN;
    return;
end
[~, ~, ~, auc] = perfcurve(labels, scores, true);
end

function value = safe_divide(num, den)
if den == 0
    value = NaN;
else
    value = num / den;
end
end

function row_table = export_model_coefficients(scope_name, model_name, model_struct)
if ~isfield(model_struct, 'feature_names') || isempty(model_struct.feature_names)
    row_table = table();
    return;
end

switch string(model_struct.backend)
    case "fitclinear"
        feature_names = string(model_struct.feature_names(:));
        coeff_values = double(model_struct.mdl_object.Beta(:));
        intercept_value = double(model_struct.mdl_object.Bias);
    case "fitglm"
        coeff_table = model_struct.mdl_object.Coefficients;
        intercept_value = coeff_table.Estimate(1);
        coeff_values = coeff_table.Estimate(2:end);
        feature_names = string(model_struct.feature_names(:));
    otherwise
        row_table = table();
        return;
end

row_table = table();
row_table.scope = repmat(string(scope_name), numel(feature_names) + 1, 1);
row_table.model_name = repmat(string(model_name), numel(feature_names) + 1, 1);
row_table.term_name = ["intercept"; feature_names];
row_table.coefficient = [intercept_value; coeff_values];
end

function model = empty_model(feature_names)
model = struct();
model.backend = "";
model.feature_names = feature_names;
end

function out = empty_eval(feature_names)
out = struct();
out.feature_names = feature_names;
out.score = [];
out.pred = [];
out.fold_id = [];
out.full_model = empty_model(feature_names);
end

function field_name = scope_field_name(scope_name)
switch string(scope_name)
    case "B"
        field_name = 'b';
    case "C"
        field_name = 'c';
    case "B+C"
        field_name = 'bc';
    otherwise
        field_name = matlab.lang.makeValidName(char(scope_name));
end
end

function mask = scope_mask_from_name(scenario, scope_name)
scenario = string(scenario);
switch string(scope_name)
    case "B"
        mask = scenario == "B";
    case "C"
        mask = scenario == "C";
    case "B+C"
        mask = scenario == "B" | scenario == "C";
    otherwise
        error('[run_cp7_reviewer_diagnostics] Unsupported scope: %s', string(scope_name));
end
end

function folds = safe_cv_folds(labels, requested_folds)
labels = logical(labels(:));
if isempty(labels) || numel(unique(labels)) < 2
    folds = 0;
    return;
end
minority = min(sum(labels), sum(~labels));
folds = min([requested_folds, minority, numel(labels)]);
if folds < 2
    folds = 0;
end
end

function cfg = merge_config(cfg, overrides)
if nargin < 2 || ~isstruct(overrides)
    return;
end
fields = fieldnames(overrides);
for idx = 1:numel(fields)
    cfg.(fields{idx}) = overrides.(fields{idx});
end
end

function value = safe_quantile(x, q)
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = quantile(x, q);
end
end

function label_col_cp7 = target_to_cp7_label(target_name)
switch string(target_name)
    case "material"
        label_col_cp7 = 'label_material';
    case "geometric"
        label_col_cp7 = 'label_geometric';
    otherwise
        error('[run_cp7_reviewer_diagnostics] Unsupported target: %s', string(target_name));
end
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

function write_summary_markdown(outputs, combined_incremental, combined_mcnemar, cfg)
path_md = fullfile(cfg.results_dir, 'diagnostics_summary.md');
fid = fopen(path_md, 'w');
if fid < 0
    error('Failed to open markdown summary: %s', path_md);
end
cleanup_obj = onCleanup(@() fclose(fid));

fprintf(fid, '# CP7 Reviewer Diagnostics Summary\n\n');
fprintf(fid, 'Baseline feature set: `%s`\n\n', strjoin(cfg.baseline_features, ', '));
fprintf(fid, 'Added CP7 feature set: `%s`\n\n', strjoin(cfg.cp7_features, ', '));

fprintf(fid, '## Incremental Gain\n\n');
fprintf(fid, '| Target | Scope | Subset | n | Baseline AUC | Proposed AUC | Delta AUC | Delta 95%% CI | Baseline Brier | Proposed Brier | Delta Brier | Status |\n');
fprintf(fid, '|---|---|---|---:|---:|---:|---:|---|---:|---:|---:|---|\n');
for idx = 1:height(combined_incremental)
    row = combined_incremental(idx, :);
    fprintf(fid, '| %s | %s | %s | %d | %.4f | %.4f | %.4f | [%.4f, %.4f] | %.4f | %.4f | %.4f | %s |\n', ...
        char(row.label_target), char(row.scope), char(row.subset_name), row.n_samples, ...
        row.baseline_auc, row.proposed_auc, row.delta_auc, row.delta_auc_ci_low, row.delta_auc_ci_high, ...
        row.baseline_brier, row.proposed_brier, row.delta_brier, char(row.status));
end

fprintf(fid, '\n## McNemar\n\n');
fprintf(fid, '| Target | Scope | Subset | n | b | c | p |\n');
fprintf(fid, '|---|---|---|---:|---:|---:|---:|\n');
for idx = 1:height(combined_mcnemar)
    row = combined_mcnemar(idx, :);
    fprintf(fid, '| %s | %s | %s | %d | %.0f | %.0f | %.6f |\n', ...
        char(row.label_target), char(row.scope), char(row.subset_name), row.n_samples, ...
        row.baseline_correct_proposed_wrong, row.baseline_wrong_proposed_correct, row.p_value_exact);
end

fprintf(fid, '\n## Orthogonality Snapshot\n\n');
fprintf(fid, '| Target | CP7 feature | max |rho| vs top3 | mean |rho| vs top3 |\n');
fprintf(fid, '|---|---|---:|---:|\n');
for idx_target = 1:numel(cfg.targets)
    target_name = cfg.targets(idx_target);
    ortho_table = outputs.targets.(char(target_name)).correlation_outputs.orthogonality_summary;
    for idx_row = 1:height(ortho_table)
        row = ortho_table(idx_row, :);
        fprintf(fid, '| %s | %s | %.4f | %.4f |\n', ...
            char(target_name), char(row.cp7_feature), row.max_abs_spearman_top3, row.mean_abs_spearman_top3);
    end
end
end
