function outputs = run_cp7_priority_validations(cfg_override)
% RUN_CP7_PRIORITY_VALIDATIONS
% Priority validations for the 6 channel-resolved CP7 features:
% 1) channel-resolved correlation and VIF
% 2) stepwise ablation
% 3) permutation importance (logistic + RF)

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
cfg = default_config(script_dir, project_root);
if nargin >= 1 && isstruct(cfg_override)
    cfg = merge_config(cfg, cfg_override);
end

ensure_dir(cfg.results_dir);
ensure_dir(fullfile(cfg.results_dir, 'shared'));

ensure_reviewer_outputs_exist(cfg);

shared_table = load_target_dataset("material", cfg);
shared_outputs = run_shared_correlation_validation(shared_table, cfg);
write_shared_outputs(shared_outputs, cfg);

outputs = struct();
outputs.config = cfg;
outputs.shared = shared_outputs;
outputs.targets = struct();

combined_ablation = table();
combined_ablation_repeats = table();
combined_perm_summary = table();
combined_spatial_summary = table();

for idx_target = 1:numel(cfg.targets)
    target_name = cfg.targets(idx_target);
    fprintf('\n=== CP7 Priority Validations: %s ===\n', target_name);
    dataset_table = load_target_dataset(target_name, cfg);

    target_outputs = run_target_validations(target_name, dataset_table, cfg);
    outputs.targets.(char(target_name)) = target_outputs;

    ablation_block = target_outputs.ablation_summary;
    ablation_block.label_target = repmat(string(target_name), height(ablation_block), 1);
    ablation_block = movevars(ablation_block, 'label_target', 'Before', 'scope');
    combined_ablation = [combined_ablation; ablation_block]; %#ok<AGROW>

    ablation_repeat_block = target_outputs.ablation_repeat_metrics;
    if ~isempty(ablation_repeat_block)
        ablation_repeat_block.label_target = repmat(string(target_name), height(ablation_repeat_block), 1);
        ablation_repeat_block = movevars(ablation_repeat_block, 'label_target', 'Before', 'scope');
        combined_ablation_repeats = [combined_ablation_repeats; ablation_repeat_block]; %#ok<AGROW>
    end

    perm_block = target_outputs.permutation_summary;
    perm_block.label_target = repmat(string(target_name), height(perm_block), 1);
    perm_block = movevars(perm_block, 'label_target', 'Before', 'model_name');
    combined_perm_summary = [combined_perm_summary; perm_block]; %#ok<AGROW>

    spatial_block = target_outputs.spatial_cv_summary;
    if ~isempty(spatial_block)
        spatial_block.label_target = repmat(string(target_name), height(spatial_block), 1);
        spatial_block = movevars(spatial_block, 'label_target', 'Before', 'scope');
        combined_spatial_summary = [combined_spatial_summary; spatial_block]; %#ok<AGROW>
    end
end

writetable(combined_ablation, fullfile(cfg.results_dir, 'ablation_summary_all_targets.csv'));
if ~isempty(combined_ablation_repeats)
    writetable(combined_ablation_repeats, fullfile(cfg.results_dir, 'ablation_repeat_metrics_all_targets.csv'));
end
writetable(combined_perm_summary, fullfile(cfg.results_dir, 'permutation_summary_all_targets.csv'));
if ~isempty(combined_spatial_summary)
    writetable(combined_spatial_summary, fullfile(cfg.results_dir, 'spatial_cv_summary_all_targets.csv'));
end

write_summary_markdown(outputs, combined_ablation, combined_perm_summary, combined_spatial_summary, cfg);

outputs.ablation_summary = combined_ablation;
outputs.ablation_repeat_metrics = combined_ablation_repeats;
outputs.permutation_summary = combined_perm_summary;
outputs.spatial_cv_summary = combined_spatial_summary;
outputs.timestamp = datetime('now');
save(fullfile(cfg.results_dir, 'cp7_priority_validations_outputs.mat'), 'outputs', '-v7.3');
end

function cfg = default_config(script_dir, project_root)
cfg = struct();
cfg.script_dir = script_dir;
cfg.project_root = project_root;
cfg.reviewer_results_dir = fullfile(script_dir, 'results', 'cp7_reviewer_diagnostics');
cfg.results_dir = fullfile(script_dir, 'results', 'cp7_priority_validations');
cfg.targets = ["material", "geometric"];
cfg.scopes = ["B", "C", "B+C"];
cfg.random_seed = 42;
cfg.cv_folds = 5;
cfg.n_cv_repeats = 20;
cfg.classification_threshold = 0.5;
cfg.logistic_lambda = 1e-2;
cfg.rf_num_trees = 80;
cfg.rf_min_leaf_size = 2;
cfg.permutation_repeats = 100;
cfg.cv_strategy = "stratified_kfold";
cfg.save_cv_records = true;
cfg.spatial_cv_enabled = true;
cfg.spatial_cv_scope = "B+C";
cfg.spatial_cv_strategy = "leave_one_position_out";

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

cfg.all_features = [cfg.baseline_features, cfg.cp7_features];
cfg.decision_thresholds = [0.3, 0.6];

cfg.ablation_variants = { ...
    struct('name', "baseline", 'features', {cfg.baseline_features}, 'dropped', {{'all_cp7'}}), ...
    struct('name', "full_proposed", 'features', {cfg.all_features}, 'dropped', {{}}), ...
    struct('name', "drop_gamma_rx1_only", 'features', {{ ...
        'fp_energy_db', 'skewness_pdp', 'kurtosis_pdp', 'mean_excess_delay_ns', 'rms_delay_spread_ns', ...
        'gamma_CP_rx2', 'a_FP_RHCP_rx1', 'a_FP_LHCP_rx1', 'a_FP_RHCP_rx2', 'a_FP_LHCP_rx2'}}, ...
        'dropped', {{'gamma_CP_rx1'}}), ...
    struct('name', "drop_gamma_rx2_only", 'features', {{ ...
        'fp_energy_db', 'skewness_pdp', 'kurtosis_pdp', 'mean_excess_delay_ns', 'rms_delay_spread_ns', ...
        'gamma_CP_rx1', 'a_FP_RHCP_rx1', 'a_FP_LHCP_rx1', 'a_FP_RHCP_rx2', 'a_FP_LHCP_rx2'}}, ...
        'dropped', {{'gamma_CP_rx2'}}), ...
    struct('name', "drop_gamma_both", 'features', {{ ...
        'fp_energy_db', 'skewness_pdp', 'kurtosis_pdp', 'mean_excess_delay_ns', 'rms_delay_spread_ns', ...
        'a_FP_RHCP_rx1', 'a_FP_LHCP_rx1', 'a_FP_RHCP_rx2', 'a_FP_LHCP_rx2'}}, ...
        'dropped', {{'gamma_CP_rx1', 'gamma_CP_rx2'}}), ...
    struct('name', "drop_rx1_branch", 'features', {{ ...
        'fp_energy_db', 'skewness_pdp', 'kurtosis_pdp', 'mean_excess_delay_ns', 'rms_delay_spread_ns', ...
        'gamma_CP_rx2', 'a_FP_RHCP_rx2', 'a_FP_LHCP_rx2'}}, ...
        'dropped', {{'gamma_CP_rx1', 'a_FP_RHCP_rx1', 'a_FP_LHCP_rx1'}}), ...
    struct('name', "drop_rx2_branch", 'features', {{ ...
        'fp_energy_db', 'skewness_pdp', 'kurtosis_pdp', 'mean_excess_delay_ns', 'rms_delay_spread_ns', ...
        'gamma_CP_rx1', 'a_FP_RHCP_rx1', 'a_FP_LHCP_rx1'}}, ...
        'dropped', {{'gamma_CP_rx2', 'a_FP_RHCP_rx2', 'a_FP_LHCP_rx2'}}), ...
    struct('name', "drop_lhcp_pair", 'features', {{ ...
        'fp_energy_db', 'skewness_pdp', 'kurtosis_pdp', 'mean_excess_delay_ns', 'rms_delay_spread_ns', ...
        'gamma_CP_rx1', 'gamma_CP_rx2', 'a_FP_RHCP_rx1', 'a_FP_RHCP_rx2'}}, ...
        'dropped', {{'a_FP_LHCP_rx1', 'a_FP_LHCP_rx2'}}), ...
    struct('name', "drop_rhcp_pair", 'features', {{ ...
        'fp_energy_db', 'skewness_pdp', 'kurtosis_pdp', 'mean_excess_delay_ns', 'rms_delay_spread_ns', ...
        'gamma_CP_rx1', 'gamma_CP_rx2', 'a_FP_LHCP_rx1', 'a_FP_LHCP_rx2'}}, ...
        'dropped', {{'a_FP_RHCP_rx1', 'a_FP_RHCP_rx2'}}), ...
    struct('name', "drop_a_fp_all", 'features', {{ ...
        'fp_energy_db', 'skewness_pdp', 'kurtosis_pdp', 'mean_excess_delay_ns', 'rms_delay_spread_ns', ...
        'gamma_CP_rx1', 'gamma_CP_rx2'}}, ...
        'dropped', {{'a_FP_RHCP_rx1', 'a_FP_LHCP_rx1', 'a_FP_RHCP_rx2', 'a_FP_LHCP_rx2'}})};
end

function ensure_dir(dirpath)
if ~exist(dirpath, 'dir')
    mkdir(dirpath);
end
end

function ensure_reviewer_outputs_exist(cfg)
required_csv = fullfile(cfg.reviewer_results_dir, 'material', 'cp7_target_dataset.csv');
if isfile(required_csv)
    return;
end

current_dir = pwd;
cleanup_obj = onCleanup(@() cd(current_dir));
cd(cfg.script_dir);
run_cp7_reviewer_diagnostics();
clear cleanup_obj;
cd(current_dir);
end

function dataset_table = load_target_dataset(target_name, cfg)
path_csv = fullfile(cfg.reviewer_results_dir, char(target_name), 'cp7_target_dataset.csv');
if ~isfile(path_csv)
    error('[run_cp7_priority_validations] Missing reviewer dataset: %s', path_csv);
end

dataset_table = readtable(path_csv, 'TextType', 'string');
dataset_table.case_name = string(dataset_table.case_name);
dataset_table.scenario = string(dataset_table.scenario);
dataset_table.polarization = string(dataset_table.polarization);
dataset_table.label = logical(dataset_table.label);
dataset_table.valid_for_cp7_model = logical(dataset_table.valid_for_cp7_model);
end

function shared_outputs = run_shared_correlation_validation(dataset_table, cfg)
dataset_table = dataset_table(dataset_table.valid_for_cp7_model, :);

[pearson_cross, spearman_cross, cross_rows] = compute_cross_correlation_tables( ...
    dataset_table, cfg.cp7_features, cfg.baseline_features);
[pearson_cp, spearman_cp, cp_rows] = compute_cross_correlation_tables( ...
    dataset_table, cfg.cp7_features, cfg.cp7_features);

decision_table = table();
for idx_feature = 1:numel(cfg.cp7_features)
    feature_name = string(cfg.cp7_features{idx_feature});
    mask = cross_rows.source_feature == feature_name;
    max_abs_pearson = max(cross_rows.abs_pearson_r(mask), [], 'omitnan');
    max_abs_spearman = max(cross_rows.abs_spearman_rho(mask), [], 'omitnan');
    max_abs_corr_any = max([max_abs_pearson, max_abs_spearman]);

    row = table();
    row.cp7_feature = feature_name;
    row.max_abs_pearson_baseline = max_abs_pearson;
    row.max_abs_spearman_baseline = max_abs_spearman;
    row.max_abs_corr_any = max_abs_corr_any;
    row.decision = classify_correlation_level(max_abs_corr_any, cfg.decision_thresholds);
    decision_table = [decision_table; row]; %#ok<AGROW>
end

vif_full = compute_vif_table(dataset_table, cfg.all_features);
vif_cp_only = compute_vif_table(dataset_table, cfg.cp7_features);

shared_outputs = struct();
shared_outputs.n_samples = height(dataset_table);
shared_outputs.pearson_cross = pearson_cross;
shared_outputs.spearman_cross = spearman_cross;
shared_outputs.cross_rows = cross_rows;
shared_outputs.pearson_cp = pearson_cp;
shared_outputs.spearman_cp = spearman_cp;
shared_outputs.cp_rows = cp_rows;
shared_outputs.decision_table = sortrows(decision_table, 'max_abs_corr_any', 'ascend');
shared_outputs.vif_full = vif_full;
shared_outputs.vif_cp_only = vif_cp_only;
end

function write_shared_outputs(shared_outputs, cfg)
shared_dir = fullfile(cfg.results_dir, 'shared');
ensure_dir(shared_dir);

writetable(shared_outputs.pearson_cross, fullfile(shared_dir, 'corr_abs_pearson_cp7_vs_baseline.csv'), 'WriteRowNames', true);
writetable(shared_outputs.spearman_cross, fullfile(shared_dir, 'corr_abs_spearman_cp7_vs_baseline.csv'), 'WriteRowNames', true);
writetable(shared_outputs.pearson_cp, fullfile(shared_dir, 'corr_abs_pearson_cp7_internal.csv'), 'WriteRowNames', true);
writetable(shared_outputs.spearman_cp, fullfile(shared_dir, 'corr_abs_spearman_cp7_internal.csv'), 'WriteRowNames', true);
writetable(shared_outputs.cross_rows, fullfile(shared_dir, 'corr_pairs_cp7_vs_baseline.csv'));
writetable(shared_outputs.cp_rows, fullfile(shared_dir, 'corr_pairs_cp7_internal.csv'));
writetable(shared_outputs.decision_table, fullfile(shared_dir, 'correlation_decision_summary.csv'));
writetable(shared_outputs.vif_full, fullfile(shared_dir, 'vif_full_proposed.csv'));
writetable(shared_outputs.vif_cp_only, fullfile(shared_dir, 'vif_cp7_only.csv'));
end

function [pearson_mat_table, spearman_mat_table, pair_rows] = compute_cross_correlation_tables(dataset_table, source_features, target_features)
source_x = dataset_table{:, source_features};
target_x = dataset_table{:, target_features};

n_source = numel(source_features);
n_target = numel(target_features);
pearson_mat = nan(n_source, n_target);
spearman_mat = nan(n_source, n_target);
pair_rows = table();

for idx_source = 1:n_source
    for idx_target = 1:n_target
        x = source_x(:, idx_source);
        y = target_x(:, idx_target);
        valid_mask = isfinite(x) & isfinite(y);

        if sum(valid_mask) >= 2
            [pearson_r, pearson_p] = corr(x(valid_mask), y(valid_mask), 'Type', 'Pearson');
            [spearman_rho, spearman_p] = corr(x(valid_mask), y(valid_mask), 'Type', 'Spearman');
        else
            pearson_r = NaN;
            pearson_p = NaN;
            spearman_rho = NaN;
            spearman_p = NaN;
        end

        pearson_mat(idx_source, idx_target) = abs(pearson_r);
        spearman_mat(idx_source, idx_target) = abs(spearman_rho);

        row = table();
        row.source_feature = string(source_features{idx_source});
        row.target_feature = string(target_features{idx_target});
        row.pearson_r = pearson_r;
        row.pearson_p = pearson_p;
        row.spearman_rho = spearman_rho;
        row.spearman_p = spearman_p;
        row.abs_pearson_r = abs(pearson_r);
        row.abs_spearman_rho = abs(spearman_rho);
        pair_rows = [pair_rows; row]; %#ok<AGROW>
    end
end

pearson_mat_table = array2table(pearson_mat, 'VariableNames', target_features, 'RowNames', source_features);
spearman_mat_table = array2table(spearman_mat, 'VariableNames', target_features, 'RowNames', source_features);
end

function decision_text = classify_correlation_level(max_abs_corr_any, thresholds)
if ~isfinite(max_abs_corr_any)
    decision_text = "undefined";
elseif max_abs_corr_any < thresholds(1)
    decision_text = "orthogonal";
elseif max_abs_corr_any < thresholds(2)
    decision_text = "partial_redundancy";
else
    decision_text = "high_redundancy";
end
end

function vif_table = compute_vif_table(dataset_table, feature_names)
X = dataset_table{:, feature_names};
n_feature = numel(feature_names);

vif_table = table();
for idx_feature = 1:n_feature
    y = X(:, idx_feature);
    x_other = X(:, setdiff(1:n_feature, idx_feature));
    valid_mask = all(isfinite([y, x_other]), 2);

    row = table();
    row.feature_name = string(feature_names{idx_feature});
    row.n_valid = sum(valid_mask);

    if row.n_valid < 3
        row.r_squared = NaN;
        row.vif = NaN;
        vif_table = [vif_table; row]; %#ok<AGROW>
        continue;
    end

    y_valid = y(valid_mask);
    x_valid = x_other(valid_mask, :);
    x_valid = [ones(size(x_valid, 1), 1), x_valid];
    beta = x_valid \ y_valid;
    y_hat = x_valid * beta;

    sst = sum((y_valid - mean(y_valid)).^2);
    ssr = sum((y_valid - y_hat).^2);
    if sst <= eps
        r_squared = 0;
    else
        r_squared = max(0, min(1, 1 - ssr / sst));
    end

    row.r_squared = r_squared;
    row.vif = 1 / max(1 - r_squared, eps);
    vif_table = [vif_table; row]; %#ok<AGROW>
end

vif_table = sortrows(vif_table, 'vif', 'descend');
end

function target_outputs = run_target_validations(target_name, dataset_table, cfg)
target_dir = fullfile(cfg.results_dir, char(target_name));
ensure_dir(target_dir);

ablation_summary = table();
ablation_repeat_metrics = table();
ablation_cv_records = struct([]);
[ablation_summary, ablation_repeat_metrics, ablation_cv_records] = run_ablation_validation(dataset_table, cfg);
permutation_outputs = run_permutation_validation(dataset_table, cfg);
spatial_cv_summary = run_spatial_cv_validation(dataset_table, cfg);
figure_path = plot_permutation_boxplots(permutation_outputs.raw_table, target_name, target_dir);

writetable(ablation_summary, fullfile(target_dir, 'ablation_summary.csv'));
if ~isempty(ablation_repeat_metrics)
    writetable(ablation_repeat_metrics, fullfile(target_dir, 'ablation_repeat_metrics.csv'));
end
if ~isempty(ablation_cv_records)
    save(fullfile(target_dir, 'ablation_cv_records.mat'), 'ablation_cv_records');
end
writetable(permutation_outputs.raw_table, fullfile(target_dir, 'permutation_importance_raw.csv'));
writetable(permutation_outputs.summary_table, fullfile(target_dir, 'permutation_importance_summary.csv'));
writetable(permutation_outputs.base_metrics, fullfile(target_dir, 'permutation_base_metrics.csv'));
if ~isempty(spatial_cv_summary)
    writetable(spatial_cv_summary, fullfile(target_dir, 'spatial_cv_summary.csv'));
end
permutation_outputs.figure_path = figure_path;

target_outputs = struct();
target_outputs.ablation_summary = ablation_summary;
target_outputs.ablation_repeat_metrics = ablation_repeat_metrics;
target_outputs.ablation_cv_records = ablation_cv_records;
target_outputs.permutation_raw = permutation_outputs.raw_table;
target_outputs.permutation_summary = permutation_outputs.summary_table;
target_outputs.permutation_base_metrics = permutation_outputs.base_metrics;
target_outputs.spatial_cv_summary = spatial_cv_summary;
end

function [ablation_summary, ablation_repeat_metrics, ablation_cv_records] = run_ablation_validation(dataset_table, cfg)
ablation_summary = table();
ablation_repeat_metrics = table();
ablation_cv_records = struct([]);

for idx_scope = 1:numel(cfg.scopes)
    scope_name = cfg.scopes(idx_scope);
    scope_mask = scope_mask_from_name(dataset_table.scenario, scope_name);
    scope_table = dataset_table(scope_mask & dataset_table.valid_for_cp7_model, :);
    labels = logical(scope_table.label);

    folds = safe_cv_folds(labels, cfg.cv_folds);
    if isempty(scope_table) || numel(unique(labels)) < 2 || folds < 2
        for idx_variant = 1:numel(cfg.ablation_variants)
            variant = cfg.ablation_variants{idx_variant};
            row = build_skipped_ablation_row(scope_name, variant.name, variant.dropped, height(scope_table), labels, "insufficient_scope");
            ablation_summary = [ablation_summary; row]; %#ok<AGROW>
        end
        continue;
    end

    scope_rows = table();

    for idx_variant = 1:numel(cfg.ablation_variants)
        variant = cfg.ablation_variants{idx_variant};
        [row, repeat_rows, cv_record_rows] = evaluate_repeated_cv_variant( ...
            scope_table, labels, variant.features, scope_name, variant, cfg);
        scope_rows = [scope_rows; row]; %#ok<AGROW>
        ablation_repeat_metrics = [ablation_repeat_metrics; repeat_rows]; %#ok<AGROW>
        ablation_cv_records = [ablation_cv_records; cv_record_rows(:)]; %#ok<AGROW>
    end

    full_idx = find(scope_rows.variant_name == "full_proposed", 1, 'first');
    full_auc = scope_rows.auc(full_idx);
    full_brier = scope_rows.brier_score(full_idx);
    full_acc = scope_rows.accuracy(full_idx);

    scope_rows.delta_auc_vs_full = scope_rows.auc - full_auc;
    scope_rows.delta_brier_vs_full = scope_rows.brier_score - full_brier;
    scope_rows.delta_accuracy_vs_full = scope_rows.accuracy - full_acc;

    ablation_summary = [ablation_summary; scope_rows]; %#ok<AGROW>
end
end

function [row, repeat_rows, cv_record_rows] = evaluate_repeated_cv_variant(scope_table, labels, feature_names, scope_name, variant, cfg)
folds = safe_cv_folds(labels, cfg.cv_folds);
repeat_rows = table();
cv_record_rows = struct([]);

for idx_repeat = 1:cfg.n_cv_repeats
    seed = cfg.random_seed + idx_repeat - 1;
    cv_plan = build_cv_plan(scope_table, labels, folds, seed, cfg.cv_strategy);
    [score, pred] = cross_validated_logistic(scope_table, labels, feature_names, cv_plan, cfg);
    metric_row = metrics_table_from_vectors(labels, score, pred, variant.name);

    repeat_row = table();
    repeat_row.scope = string(scope_name);
    repeat_row.variant_name = string(variant.name);
    repeat_row.repeat_idx = idx_repeat;
    repeat_row.seed = seed;
    repeat_row.cv_strategy = string(cv_plan.strategy);
    repeat_row.n_folds = cv_plan.num_test_sets;
    repeat_row.auc = metric_row.auc;
    repeat_row.brier_score = metric_row.brier_score;
    repeat_row.accuracy = metric_row.accuracy;
    repeat_rows = [repeat_rows; repeat_row]; %#ok<AGROW>

    if get_param(cfg, 'save_cv_records', true)
        record = struct();
        record.scope = string(scope_name);
        record.variant_name = string(variant.name);
        record.repeat_idx = idx_repeat;
        record.seed = seed;
        record.strategy = string(cv_plan.strategy);
        record.fold_assignment = cv_plan.fold_assignment;
        record.num_folds = cv_plan.num_test_sets;
        cv_record_rows = [cv_record_rows; record]; %#ok<AGROW>
    end
end

row = table();
row.scope = string(scope_name);
row.variant_name = string(variant.name);
row.dropped_features = string(strjoin(string(variant.dropped), ','));
row.n_features = numel(feature_names);
row.n_samples = height(scope_table);
row.n_los = sum(labels);
row.n_nlos = sum(~labels);
row.status = "ok";
row.n_cv_repeats = cfg.n_cv_repeats;
row.n_cv_valid = height(repeat_rows);
row.cv_strategy = string(cfg.cv_strategy);
row.auc = mean(repeat_rows.auc, 'omitnan');
row.auc_std = std(repeat_rows.auc, 0, 'omitnan');
row.auc_ci_low = safe_quantile(repeat_rows.auc, 0.025);
row.auc_ci_high = safe_quantile(repeat_rows.auc, 0.975);
row.brier_score = mean(repeat_rows.brier_score, 'omitnan');
row.brier_std = std(repeat_rows.brier_score, 0, 'omitnan');
row.accuracy = mean(repeat_rows.accuracy, 'omitnan');
row.accuracy_std = std(repeat_rows.accuracy, 0, 'omitnan');
end

function row = build_skipped_ablation_row(scope_name, variant_name, dropped_features, n_samples, labels, reason_text)
row = table();
row.scope = string(scope_name);
row.variant_name = string(variant_name);
row.dropped_features = string(strjoin(string(dropped_features), ','));
row.n_features = NaN;
row.n_samples = n_samples;
row.n_los = sum(labels);
row.n_nlos = sum(~labels);
row.status = string(reason_text);
row.n_cv_repeats = NaN;
row.n_cv_valid = NaN;
row.cv_strategy = "";
row.auc = NaN;
row.auc_std = NaN;
row.auc_ci_low = NaN;
row.auc_ci_high = NaN;
row.brier_score = NaN;
row.brier_std = NaN;
row.accuracy = NaN;
row.accuracy_std = NaN;
row.delta_auc_vs_full = NaN;
row.delta_brier_vs_full = NaN;
row.delta_accuracy_vs_full = NaN;
end

function permutation_outputs = run_permutation_validation(dataset_table, cfg)
scope_mask = scope_mask_from_name(dataset_table.scenario, "B+C");
scope_table = dataset_table(scope_mask & dataset_table.valid_for_cp7_model, :);
labels = logical(scope_table.label);
folds = safe_cv_folds(labels, cfg.cv_folds);

if isempty(scope_table) || numel(unique(labels)) < 2 || folds < 2
    permutation_outputs = struct();
    permutation_outputs.raw_table = table();
    permutation_outputs.summary_table = table();
    permutation_outputs.base_metrics = table();
    permutation_outputs.figure_path = "";
    return;
end

cv_plan = build_cv_plan(scope_table, labels, folds, cfg.random_seed, cfg.cv_strategy);

[log_scores, ~, log_models] = cross_validated_logistic(scope_table, labels, cfg.all_features, cv_plan, cfg);
log_auc = metrics_table_from_vectors(labels, log_scores, log_scores >= cfg.classification_threshold, "logistic_full").auc;

[rf_scores, rf_models] = cross_validated_rf(scope_table, labels, cfg.all_features, cv_plan, cfg);
rf_auc = metrics_table_from_vectors(labels, rf_scores, rf_scores >= cfg.classification_threshold, "rf_full").auc;

raw_table = table();
base_metrics = table( ...
    ["logistic"; "rf"], ...
    [log_auc; rf_auc], ...
    'VariableNames', {'model_name', 'baseline_auc'});

for idx_rep = 1:cfg.permutation_repeats
    rng(cfg.random_seed + idx_rep);
    for idx_feature = 1:numel(cfg.cp7_features)
        feature_name = cfg.cp7_features{idx_feature};

        perm_scores_log = predict_permuted_scores_logistic(scope_table, cv_plan, cfg.all_features, feature_name, log_models);
        perm_auc_log = compute_auc(labels, perm_scores_log);
        raw_table = append_perm_row(raw_table, "logistic", feature_name, idx_rep, log_auc, perm_auc_log);

        perm_scores_rf = predict_permuted_scores_rf(scope_table, cv_plan, cfg.all_features, feature_name, rf_models);
        perm_auc_rf = compute_auc(labels, perm_scores_rf);
        raw_table = append_perm_row(raw_table, "rf", feature_name, idx_rep, rf_auc, perm_auc_rf);
    end
end

summary_table = summarize_permutation_rows(raw_table);
figure_path = fullfile(cfg.results_dir, 'tmp_perm_placeholder.png');
permutation_outputs = struct();
permutation_outputs.raw_table = raw_table;
permutation_outputs.summary_table = summary_table;
permutation_outputs.base_metrics = base_metrics;
permutation_outputs.figure_path = "";
end

function spatial_summary = run_spatial_cv_validation(dataset_table, cfg)
spatial_summary = table();
if ~get_param(cfg, 'spatial_cv_enabled', true)
    return;
end

scope_name = string(get_param(cfg, 'spatial_cv_scope', "B+C"));
scope_mask = scope_mask_from_name(dataset_table.scenario, scope_name);
scope_table = dataset_table(scope_mask & dataset_table.valid_for_cp7_model, :);
labels = logical(scope_table.label);

if isempty(scope_table) || numel(unique(labels)) < 2
    return;
end

cv_plan = build_cv_plan(scope_table, labels, height(scope_table), cfg.random_seed, get_param(cfg, 'spatial_cv_strategy', "leave_one_position_out"));
variant_map = { ...
    "baseline", cfg.baseline_features; ...
    "full_proposed", cfg.all_features};

for idx_variant = 1:size(variant_map, 1)
    variant_name = string(variant_map{idx_variant, 1});
    feature_names = variant_map{idx_variant, 2};
    [score, pred] = cross_validated_logistic(scope_table, labels, feature_names, cv_plan, cfg);
    metric_row = metrics_table_from_vectors(labels, score, pred, variant_name);

    row = table();
    row.scope = scope_name;
    row.variant_name = variant_name;
    row.cv_strategy = string(cv_plan.strategy);
    row.n_samples = height(scope_table);
    row.n_los = sum(labels);
    row.n_nlos = sum(~labels);
    row.n_folds = cv_plan.num_test_sets;
    row.auc = metric_row.auc;
    row.brier_score = metric_row.brier_score;
    row.accuracy = metric_row.accuracy;
    spatial_summary = [spatial_summary; row]; %#ok<AGROW>
end
end

function raw_table = append_perm_row(raw_table, model_name, feature_name, rep_idx, baseline_auc, perm_auc)
row = table();
row.model_name = string(model_name);
row.feature_name = string(feature_name);
row.rep_idx = rep_idx;
row.baseline_auc = baseline_auc;
row.permuted_auc = perm_auc;
row.auc_drop = baseline_auc - perm_auc;
raw_table = [raw_table; row]; %#ok<AGROW>
end

function summary_table = summarize_permutation_rows(raw_table)
summary_table = table();
if isempty(raw_table)
    return;
end

model_values = unique(raw_table.model_name, 'stable');
feature_values = unique(raw_table.feature_name, 'stable');

for idx_model = 1:numel(model_values)
    for idx_feature = 1:numel(feature_values)
        mask = raw_table.model_name == model_values(idx_model) & raw_table.feature_name == feature_values(idx_feature);
        values = raw_table.auc_drop(mask);
        row = table();
        row.model_name = model_values(idx_model);
        row.feature_name = feature_values(idx_feature);
        row.n_repeats = sum(mask);
        row.mean_auc_drop = mean(values, 'omitnan');
        row.median_auc_drop = median(values, 'omitnan');
        row.std_auc_drop = std(values, 0, 'omitnan');
        row.p05_auc_drop = quantile(values, 0.05);
        row.p95_auc_drop = quantile(values, 0.95);
        summary_table = [summary_table; row]; %#ok<AGROW>
    end
end

summary_table = sortrows(summary_table, {'model_name', 'mean_auc_drop'}, {'ascend', 'descend'});
end

function perm_scores = predict_permuted_scores_logistic(scope_table, cv_plan, feature_names, permuted_feature, fold_models)
n_samples = height(scope_table);
perm_scores = nan(n_samples, 1);
feature_idx = find(strcmp(feature_names, permuted_feature), 1, 'first');
X_all = scope_table{:, feature_names};

for idx_fold = 1:cv_plan.num_test_sets
    test_mask = cv_plan.test_masks{idx_fold};
    X_test = X_all(test_mask, :);
    X_test(:, feature_idx) = X_test(randperm(size(X_test, 1)), feature_idx);
    X_test_norm = apply_normalization(X_test, fold_models(idx_fold).normalization);
    perm_scores(test_mask) = predict_with_model(fold_models(idx_fold).model, X_test_norm);
end
end

function perm_scores = predict_permuted_scores_rf(scope_table, cv_plan, feature_names, permuted_feature, fold_models)
n_samples = height(scope_table);
perm_scores = nan(n_samples, 1);
feature_idx = find(strcmp(feature_names, permuted_feature), 1, 'first');
X_all = scope_table{:, feature_names};

for idx_fold = 1:cv_plan.num_test_sets
    test_mask = cv_plan.test_masks{idx_fold};
    X_test = X_all(test_mask, :);
    X_test(:, feature_idx) = X_test(randperm(size(X_test, 1)), feature_idx);
    [~, scores] = predict(fold_models(idx_fold).model, X_test);
    perm_scores(test_mask) = extract_positive_score(scores, fold_models(idx_fold).class_names);
end
end

function [score, fold_models] = cross_validated_rf(dataset_table, labels, feature_names, cv_plan, cfg)
X_all = dataset_table{:, feature_names};
n_samples = size(X_all, 1);
score = nan(n_samples, 1);
fold_models = repmat(struct('model', [], 'class_names', []), cv_plan.num_test_sets, 1);

for idx_fold = 1:cv_plan.num_test_sets
    train_mask = cv_plan.train_masks{idx_fold};
    test_mask = cv_plan.test_masks{idx_fold};

    mdl = TreeBagger(cfg.rf_num_trees, X_all(train_mask, :), double(labels(train_mask)), ...
        'Method', 'classification', ...
        'MinLeafSize', cfg.rf_min_leaf_size);
    [~, scores] = predict(mdl, X_all(test_mask, :));
    score(test_mask) = extract_positive_score(scores, mdl.ClassNames);
    fold_models(idx_fold).model = mdl;
    fold_models(idx_fold).class_names = mdl.ClassNames;
end
end

function [score, pred, fold_models] = cross_validated_logistic(dataset_table, labels, feature_names, cv_plan, cfg)
X_all = dataset_table{:, feature_names};
n_samples = size(X_all, 1);
score = nan(n_samples, 1);
pred = false(n_samples, 1);
fold_models = repmat(struct('model', [], 'normalization', []), cv_plan.num_test_sets, 1);

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

    fold_models(idx_fold).model = model;
    fold_models(idx_fold).normalization = norm_params;
end
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
    case "leave_one_position_out"
        if ismember('key', dataset_table.Properties.VariableNames)
            group_key = string(dataset_table.key);
        else
            group_key = compose_position_key(dataset_table);
        end
        [~, ~, group_idx] = unique(group_key, 'stable');
        n_group = max(group_idx);
        train_masks = cell(n_group, 1);
        test_masks = cell(n_group, 1);
        fold_assignment = zeros(n_samples, 1);
        for idx_fold = 1:n_group
            test_masks{idx_fold} = group_idx == idx_fold;
            train_masks{idx_fold} = ~test_masks{idx_fold};
            fold_assignment(test_masks{idx_fold}) = idx_fold;
        end
        cv_plan = struct();
        cv_plan.strategy = strategy;
        cv_plan.seed = seed;
        cv_plan.num_test_sets = n_group;
        cv_plan.train_masks = train_masks;
        cv_plan.test_masks = test_masks;
        cv_plan.fold_assignment = fold_assignment;
    otherwise
        error('[run_cp7_priority_validations] Unsupported cv strategy: %s', strategy);
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
    warning('[run_cp7_priority_validations] fitclinear failed (%s). Falling back to fitglm.', ...
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
        error('[run_cp7_priority_validations] Unsupported backend: %s', string(model.backend));
end
end

function y = logistic_sigmoid(x)
x = max(min(double(x), 60), -60);
y = 1 ./ (1 + exp(-x));
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
row.auc = compute_auc(labels, scores);
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

function value = safe_quantile(x, q)
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = quantile(x, q);
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
        error('[run_cp7_priority_validations] Unsupported scope: %s', string(scope_name));
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

function score_pos = extract_positive_score(score_matrix, class_names)
if isempty(score_matrix)
    score_pos = nan(0, 1);
    return;
end

class_names = lower(string(class_names(:)));
pos_idx = find(class_names == "1" | class_names == "true" | class_names == "los", 1, 'first');
if isempty(pos_idx)
    pos_idx = min(2, size(score_matrix, 2));
end
score_pos = double(score_matrix(:, pos_idx));
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

function value = get_param(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
    value = s.(field_name);
else
    value = default_value;
end
end

function key = compose_position_key(dataset_table)
if all(ismember({'scenario', 'x_m', 'y_m'}, dataset_table.Properties.VariableNames))
    scenario = string(dataset_table.scenario);
    x_m = double(dataset_table.x_m);
    y_m = double(dataset_table.y_m);
elseif all(ismember({'scenario', 'x_coord_m', 'y_coord_m'}, dataset_table.Properties.VariableNames))
    scenario = string(dataset_table.scenario);
    x_m = double(dataset_table.x_coord_m);
    y_m = double(dataset_table.y_coord_m);
else
    error('[run_cp7_priority_validations] Unable to compose position key.');
end
key = strings(numel(x_m), 1);
for idx = 1:numel(x_m)
    key(idx) = sprintf('%s|%.3f|%.3f', upper(char(scenario(idx))), x_m(idx), y_m(idx));
end
end

function write_summary_markdown(outputs, combined_ablation, combined_perm_summary, combined_spatial_summary, cfg)
path_md = fullfile(cfg.results_dir, 'cp7_priority_validation_report.md');
fid = fopen(path_md, 'w');
if fid < 0
    error('Failed to open markdown summary: %s', path_md);
end
cleanup_obj = onCleanup(@() fclose(fid));

fprintf(fid, '# CP7 Priority Validation Report\n\n');
fprintf(fid, '## Validation 1: Channel-Resolved Correlation\n\n');
fprintf(fid, '| Feature | max abs corr | Decision |\n');
fprintf(fid, '|---|---:|---|\n');
for idx = 1:height(outputs.shared.decision_table)
    row = outputs.shared.decision_table(idx, :);
    fprintf(fid, '| %s | %.4f | %s |\n', ...
        char(row.cp7_feature), row.max_abs_corr_any, char(row.decision));
end

fprintf(fid, '\n## Validation 2: Stepwise Ablation (B+C)\n\n');
fprintf(fid, '| Target | Variant | AUC mean | 95%% CI | Delta vs Full | Brier | Delta Brier |\n');
fprintf(fid, '|---|---|---:|---|---:|---:|---:|\n');
bc_rows = combined_ablation(combined_ablation.scope == "B+C" & combined_ablation.status == "ok", :);
for idx = 1:height(bc_rows)
    row = bc_rows(idx, :);
    fprintf(fid, '| %s | %s | %.4f | [%.4f, %.4f] | %.4f | %.4f | %.4f |\n', ...
        char(row.label_target), char(row.variant_name), row.auc, row.auc_ci_low, row.auc_ci_high, row.delta_auc_vs_full, ...
        row.brier_score, row.delta_brier_vs_full);
end

if ~isempty(combined_spatial_summary)
    fprintf(fid, '\n## Validation 2b: Spatial CV Check\n\n');
    fprintf(fid, '| Target | Scope | Variant | Strategy | Folds | AUC | Brier | Accuracy |\n');
    fprintf(fid, '|---|---|---|---|---:|---:|---:|---:|\n');
    for idx = 1:height(combined_spatial_summary)
        row = combined_spatial_summary(idx, :);
        fprintf(fid, '| %s | %s | %s | %s | %d | %.4f | %.4f | %.4f |\n', ...
            char(row.label_target), char(row.scope), char(row.variant_name), char(row.cv_strategy), ...
            row.n_folds, row.auc, row.brier_score, row.accuracy);
    end
end

fprintf(fid, '\n## Validation 3: Permutation Importance (B+C)\n\n');
fprintf(fid, '| Target | Model | Feature | Mean AUC drop | Median AUC drop |\n');
fprintf(fid, '|---|---|---|---:|---:|\n');
for idx = 1:height(combined_perm_summary)
    row = combined_perm_summary(idx, :);
    fprintf(fid, '| %s | %s | %s | %.4f | %.4f |\n', ...
        char(row.label_target), char(row.model_name), char(row.feature_name), ...
        row.mean_auc_drop, row.median_auc_drop);
end
end

function figure_path = plot_permutation_boxplots(raw_table, target_name, target_dir)
figure_path = "";
if isempty(raw_table)
    return;
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1400, 500]);
layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(layout, sprintf('Permutation importance AUC drop: %s', char(string(target_name))));

model_values = ["logistic", "rf"];
for idx_model = 1:numel(model_values)
    ax = nexttile(layout, idx_model);
    hold(ax, 'on');
    block = raw_table(raw_table.model_name == model_values(idx_model), :);
    feature_values = unique(block.feature_name, 'stable');
    for idx_feature = 1:numel(feature_values)
        mask = block.feature_name == feature_values(idx_feature);
        boxchart(ax, repmat(idx_feature, sum(mask), 1), block.auc_drop(mask));
    end
    xticks(ax, 1:numel(feature_values));
    xticklabels(ax, feature_values);
    xtickangle(ax, 35);
    ylabel(ax, 'AUC drop');
    title(ax, upper(char(model_values(idx_model))));
    grid(ax, 'on');
end

figure_path = fullfile(target_dir, 'permutation_importance_boxplot.png');
exportgraphics(fig, figure_path, 'Resolution', 150);
savefig(fig, fullfile(target_dir, 'permutation_importance_boxplot.fig'));
close(fig);
end
