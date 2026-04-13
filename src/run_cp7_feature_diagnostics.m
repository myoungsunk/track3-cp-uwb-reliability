function outputs = run_cp7_feature_diagnostics(run_name, params)
% RUN_CP7_FEATURE_DIAGNOSTICS Run locked 6-feature diagnostics with folderized outputs.
if nargin < 1 || strlength(string(run_name)) == 0
    run_name = 'cp7_feature_diagnostics';
end
if nargin < 2
    params = struct();
end

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
addpath(script_dir);

params = apply_cp7_defaults(project_root, run_name, params);
feature_names = { ...
    'gamma_CP_rx1', ...
    'gamma_CP_rx2', ...
    'a_FP_RHCP_rx1', ...
    'a_FP_LHCP_rx1', ...
    'a_FP_RHCP_rx2', ...
    'a_FP_LHCP_rx2'};

stage_dirs = ensure_stage_dirs(params.results_dir);

fprintf('=== run_cp7_feature_diagnostics ===\n');
fprintf('Results: %s\n', params.results_dir);
fprintf('Label modes: %s\n', strjoin(cellstr(params.label_modes), ', '));
fprintf('Scopes: %s\n', strjoin(cellstr(params.scopes), ', '));

[analysis_table, metadata] = build_cp7_analysis_table(project_root, params);
save(fullfile(stage_dirs.sanity, 'cp7_analysis_table.mat'), 'analysis_table', 'metadata', 'params');
writetable(analysis_table, fullfile(stage_dirs.sanity, 'cp7_analysis_table.csv'));

collinearity_outputs = run_collinearity_stage(analysis_table, feature_names, stage_dirs.collinearity);

summary_rows = table();
sanity_rows_all = table();
missing_rows_all = table();
global_rows_all = table();
baseline_rows_all = table();
local_winner_rows_all = table();

for idx_label = 1:numel(params.label_modes)
    label_mode = string(params.label_modes(idx_label));
    [label_col, label_short] = label_mode_to_column(label_mode);

    for idx_scope = 1:numel(params.scopes)
        scope_name = string(params.scopes(idx_scope));
        scope_short = scope_to_short(scope_name);
        scope_mask = scope_mask_from_name(analysis_table.scenario, scope_name);
        scope_table = analysis_table(scope_mask, :);

        fprintf('[diagnostics] label=%s scope=%s n=%d\n', label_mode, scope_name, height(scope_table));

        [sanity_counts, missing_table] = compute_sanity_tables(scope_table, label_col, feature_names, label_mode, scope_name);
        [skip_scope, skip_reason] = should_skip_scope(sanity_counts, params);
        scope_params = params;
        scope_params.local_k = resolve_local_k(scope_name, params);
        sanity_counts.local_k = scope_params.local_k;
        sanity_counts.analysis_status = string(skip_status_label(skip_scope));
        sanity_counts.skip_reason = string(skip_reason);
        sanity_rows_all = [sanity_rows_all; sanity_counts]; %#ok<AGROW>
        missing_rows_all = [missing_rows_all; missing_table]; %#ok<AGROW>
        writetable(sanity_counts, fullfile(stage_dirs.sanity, sprintf('sanity_counts_%s_%s.csv', label_short, scope_short)));
        writetable(missing_table, fullfile(stage_dirs.sanity, sprintf('sanity_missing_%s_%s.csv', label_short, scope_short)));
        save(fullfile(stage_dirs.sanity, sprintf('sanity_%s_%s.mat', label_short, scope_short)), ...
            'sanity_counts', 'missing_table');
        plot_spatial_coverage(scope_table, label_col, label_mode, scope_name, feature_names, ...
            fullfile(stage_dirs.sanity, sprintf('spatial_coverage_%s_%s', label_short, scope_short)));

        if skip_scope
            global_table = make_empty_global_table();
        else
            global_table = compute_global_metrics(scope_table, label_col, feature_names, label_mode, scope_name, params);
        end
        global_rows_all = [global_rows_all; global_table]; %#ok<AGROW>
        writetable(global_table, fullfile(stage_dirs.global, sprintf('global_metrics_%s_%s.csv', label_short, scope_short)));
        save(fullfile(stage_dirs.global, sprintf('global_metrics_%s_%s.mat', label_short, scope_short)), 'global_table');
        if ~skip_scope
            plot_global_distribution(scope_table, label_col, feature_names, label_mode, scope_name, ...
                fullfile(stage_dirs.global, sprintf('global_distribution_%s_%s', label_short, scope_short)));
        end

        if skip_scope
            [local_sample_table, local_grid_table, winner_table, local_summary] = ...
                make_skipped_local_outputs(label_mode, scope_name, skip_reason, scope_params.local_k);
        else
            [local_sample_table, local_grid_table, winner_table, local_summary] = ...
                run_local_stage(scope_table, label_col, feature_names, label_mode, scope_name, scope_params);
        end
        writetable(local_sample_table, fullfile(stage_dirs.local, sprintf('local_sample_metrics_%s_%s.csv', label_short, scope_short)));
        writetable(local_grid_table, fullfile(stage_dirs.local, sprintf('local_grid_metrics_%s_%s.csv', label_short, scope_short)));
        writetable(winner_table, fullfile(stage_dirs.local, sprintf('winner_map_%s_%s.csv', label_short, scope_short)));
        save(fullfile(stage_dirs.local, sprintf('local_metrics_%s_%s.mat', label_short, scope_short)), ...
            'local_sample_table', 'local_grid_table', 'winner_table', 'local_summary');
        local_winner_rows_all = [local_winner_rows_all; winner_table]; %#ok<AGROW>
        if ~skip_scope
            plot_local_auc_maps(local_grid_table, feature_names, label_mode, scope_name, scope_params, ...
                fullfile(stage_dirs.local, sprintf('local_auc_maps_%s_%s', label_short, scope_short)));
            plot_winner_map(winner_table, label_mode, scope_name, ...
                fullfile(stage_dirs.local, sprintf('winner_map_%s_%s', label_short, scope_short)));
        end

        if skip_scope
            baseline_outputs = make_skipped_baseline_outputs(label_mode, scope_name, skip_reason);
        else
            baseline_outputs = run_baseline_stage(scope_table, label_col, feature_names, label_mode, scope_name, params);
        end
        writetable(baseline_outputs.univariate_table, fullfile(stage_dirs.baselines, sprintf('univariate_logistic_%s_%s.csv', label_short, scope_short)));
        writetable(baseline_outputs.l1_summary, fullfile(stage_dirs.baselines, sprintf('multivariate_l1_%s_%s.csv', label_short, scope_short)));
        writetable(baseline_outputs.l1_xy_summary, fullfile(stage_dirs.baselines, sprintf('multivariate_l1_xy_%s_%s.csv', label_short, scope_short)));
        writetable(baseline_outputs.rf_summary, fullfile(stage_dirs.baselines, sprintf('rf_baseline_%s_%s.csv', label_short, scope_short)));
        writetable(baseline_outputs.rf_importance, fullfile(stage_dirs.baselines, sprintf('rf_importance_%s_%s.csv', label_short, scope_short)));
        writetable(baseline_outputs.l1_coefficients, fullfile(stage_dirs.baselines, sprintf('l1_coefficients_%s_%s.csv', label_short, scope_short)));
        writetable(baseline_outputs.l1_xy_coefficients, fullfile(stage_dirs.baselines, sprintf('l1_xy_coefficients_%s_%s.csv', label_short, scope_short)));
        save(fullfile(stage_dirs.baselines, sprintf('baselines_%s_%s.mat', label_short, scope_short)), 'baseline_outputs');
        baseline_rows_all = [baseline_rows_all; baseline_outputs.summary_row]; %#ok<AGROW>

        summary_rows = [summary_rows; build_summary_row(global_table, winner_table, baseline_outputs, sanity_counts, skip_scope, skip_reason)]; %#ok<AGROW>
    end
end

summary_markdown = build_summary_markdown(summary_rows);
summary_md_path = fullfile(stage_dirs.summary, 'cp7_summary.md');
fid = fopen(summary_md_path, 'w');
if fid < 0
    error('[run_cp7_feature_diagnostics] Failed to write summary markdown: %s', summary_md_path);
end
cleanup_obj = onCleanup(@() fclose(fid));
fprintf(fid, '%s', summary_markdown);
clear cleanup_obj;

writetable(summary_rows, fullfile(stage_dirs.summary, 'cp7_summary.csv'));
writetable(sanity_rows_all, fullfile(stage_dirs.summary, 'cp7_sanity_overview.csv'));
writetable(missing_rows_all, fullfile(stage_dirs.summary, 'cp7_missing_overview.csv'));
writetable(global_rows_all, fullfile(stage_dirs.summary, 'cp7_global_overview.csv'));
writetable(baseline_rows_all, fullfile(stage_dirs.summary, 'cp7_baseline_overview.csv'));
save(fullfile(stage_dirs.summary, 'cp7_summary.mat'), ...
    'summary_rows', 'sanity_rows_all', 'missing_rows_all', 'global_rows_all', ...
    'baseline_rows_all', 'local_winner_rows_all', 'collinearity_outputs', ...
    'analysis_table', 'metadata', 'params');

outputs = struct();
outputs.analysis_table = analysis_table;
outputs.metadata = metadata;
outputs.collinearity = collinearity_outputs;
outputs.summary = summary_rows;
outputs.results_dir = params.results_dir;
outputs.stage_dirs = stage_dirs;
end

function params = apply_cp7_defaults(project_root, run_name, params)
params.local_k_explicit = isfield(params, 'local_k') && isfinite(double(params.local_k));
params.results_dir = char(get_param(params, 'results_dir', fullfile(project_root, 'results', char(run_name))));
params.label_csv = char(get_param(params, 'label_csv', ...
    fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_all_scenarios_los_nlos.csv')));
params.label_modes = string(get_param(params, 'label_modes', {'geometric_class', 'material_class'}));
params.scopes = string(get_param(params, 'scopes', {'B', 'C', 'B+C'}));
params.local_method = string(get_param(params, 'local_method', 'knn'));
params.local_k = get_param(params, 'local_k', NaN);
params.local_k_single_scope = get_param(params, 'local_k_single_scope', 15);
params.local_k_combined_scope = get_param(params, 'local_k_combined_scope', 30);
params.local_warn_min_class = get_param(params, 'local_warn_min_class', 5);
params.scope_skip_min_class = get_param(params, 'scope_skip_min_class', 2);
params.mi_num_bins = get_param(params, 'mi_num_bins', 10);
params.cv_folds = get_param(params, 'cv_folds', 5);
params.random_seed = get_param(params, 'random_seed', 42);
params.gamma_cp_floor = max(get_param(params, 'gamma_cp_floor', 1e-6), eps);
params.logistic_ridge_lambda = get_param(params, 'logistic_ridge_lambda', 0.01);
params.l1_num_lambda = get_param(params, 'l1_num_lambda', 25);
params.l1_lambda_ratio = get_param(params, 'l1_lambda_ratio', 1e-3);
params.rf_num_trees = get_param(params, 'rf_num_trees', 60);
params.rf_min_leaf_size = get_param(params, 'rf_min_leaf_size', 2);
params.save_outputs = false;
end

function stage_dirs = ensure_stage_dirs(results_dir)
stage_dirs = struct();
stage_dirs.summary = fullfile(results_dir, '00_summary');
stage_dirs.sanity = fullfile(results_dir, '01_sanity');
stage_dirs.global = fullfile(results_dir, '02_global');
stage_dirs.collinearity = fullfile(results_dir, '03_collinearity');
stage_dirs.local = fullfile(results_dir, '04_local');
stage_dirs.baselines = fullfile(results_dir, '05_baselines');

dir_list = struct2cell(stage_dirs);
for idx = 1:numel(dir_list)
    if ~exist(dir_list{idx}, 'dir')
        mkdir(dir_list{idx});
    end
end
end

function [skip_scope, skip_reason] = should_skip_scope(sanity_counts, params)
min_class = min(double([sanity_counts.n_los, sanity_counts.n_nlos]));
threshold = get_param(params, 'scope_skip_min_class', 2);
skip_scope = min_class < threshold;
if skip_scope
    skip_reason = sprintf('minority class count %d < %d', min_class, threshold);
else
    skip_reason = "";
end
end

function status_label = skip_status_label(skip_scope)
if skip_scope
    status_label = "skipped_minority_scope";
else
    status_label = "ok";
end
end

function local_k = resolve_local_k(scope_name, params)
if isfield(params, 'local_k_explicit') && params.local_k_explicit && isfinite(params.local_k)
    local_k = params.local_k;
    return;
end

scope_name = string(scope_name);
if scope_name == "B+C"
    local_k = get_param(params, 'local_k_combined_scope', 30);
else
    local_k = get_param(params, 'local_k_single_scope', 15);
end
end

function global_table = make_empty_global_table()
global_table = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', {'label_mode', 'scope', 'feature_name', 'n', 'n_los', 'n_nlos', ...
    'point_biserial', 'auc_raw', 'auc_effective', 'ks_stat', 'mi_bits', 'direction', 'status'});
end

function [local_sample_table, local_grid_table, winner_table, summary] = make_skipped_local_outputs(label_mode, scope_name, skip_reason, local_k)
local_sample_table = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), ...
    'VariableNames', {'label_mode', 'scope', 'feature_name', 'sample_id', 'scenario', ...
    'x_m', 'y_m', 'label', 'feature_value', 'local_raw_auc', 'local_effective_auc', ...
    'n_local', 'n_los_local', 'n_nlos_local', 'min_class_local', 'unstable_flag'});

local_grid_table = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), zeros(0, 1), ...
    'VariableNames', {'label_mode', 'scope', 'feature_name', 'x_m', 'y_m', 'local_raw_auc', ...
    'local_effective_auc', 'n_local', 'n_los_local', 'n_nlos_local', 'min_class_local', ...
    'unstable_flag', 'n_points_at_coord'});

winner_table = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), false(0, 1), ...
    'VariableNames', {'label_mode', 'scope', 'x_m', 'y_m', 'best_feature', ...
    'best_auc_effective', 'best_min_class_local', 'unstable_flag'});

summary = struct();
summary.label_mode = string(label_mode);
summary.scope = string(scope_name);
summary.status = "skipped_minority_scope";
summary.skip_reason = string(skip_reason);
summary.local_k = local_k;
summary.n_local_rows = 0;
summary.n_grid_rows = 0;
summary.winner_valid_count = 0;
end

function baseline_outputs = make_skipped_baseline_outputs(label_mode, scope_name, skip_reason)
univariate_table = table(strings(0, 1), strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    strings(0, 1), strings(0, 1), strings(0, 1), strings(0, 1), ...
    'VariableNames', {'label_mode', 'scope', 'feature_name', 'n_valid', 'n_los', 'n_nlos', ...
    'intercept', 'coef', 'coef_stderr', 'coef_pvalue', 'cv_auc', 'cv_accuracy', ...
    'cv_backend', 'stats_backend', 'status', 'warning_message'});

summary_struct = struct( ...
    'status', "skipped_minority_scope", ...
    'n_valid', NaN, ...
    'n_los', NaN, ...
    'n_nlos', NaN, ...
    'auc', NaN, ...
    'accuracy', NaN, ...
    'lambda', NaN, ...
    'n_selected', NaN, ...
    'selected_features', "", ...
    'warning_message', string(skip_reason));

rf_struct = struct( ...
    'status', "skipped_minority_scope", ...
    'n_valid', NaN, ...
    'n_los', NaN, ...
    'n_nlos', NaN, ...
    'cv_auc', NaN, ...
    'cv_accuracy', NaN, ...
    'oob_auc', NaN, ...
    'warning_message', string(skip_reason));

coefficient_table = table(strings(0, 1), zeros(0, 1), false(0, 1), ...
    'VariableNames', {'predictor_name', 'coefficient', 'selected'});
importance_table = table(strings(0, 1), zeros(0, 1), ...
    'VariableNames', {'predictor_name', 'permuted_delta_error'});

l1_summary = struct_to_single_row(summary_struct, label_mode, scope_name);
l1_xy_summary = struct_to_single_row(summary_struct, label_mode, scope_name);
rf_summary = struct_to_single_row(rf_struct, label_mode, scope_name);
summary_row = table(string(label_mode), string(scope_name), NaN, NaN, NaN, NaN, ...
    "skipped_minority_scope", string(skip_reason), ...
    'VariableNames', {'label_mode', 'scope', 'l1_auc', 'l1_xy_auc', 'delta_auc_xy', 'rf_cv_auc', 'status', 'skip_reason'});

baseline_outputs = struct();
baseline_outputs.univariate_table = univariate_table;
baseline_outputs.l1_summary = l1_summary;
baseline_outputs.l1_xy_summary = l1_xy_summary;
baseline_outputs.rf_summary = rf_summary;
baseline_outputs.rf_importance = importance_table;
baseline_outputs.l1_coefficients = coefficient_table;
baseline_outputs.l1_xy_coefficients = coefficient_table;
baseline_outputs.summary_row = summary_row;
end

function out = run_collinearity_stage(analysis_table, feature_names, output_dir)
scope_list = ["B", "C", "B+C"];
rows = table();
for idx_scope = 1:numel(scope_list)
    scope_name = scope_list(idx_scope);
    scope_short = scope_to_short(scope_name);
    scope_mask = scope_mask_from_name(analysis_table.scenario, scope_name);
    scope_table = analysis_table(scope_mask, :);

    valid_mask = scope_table.valid_flag & all(isfinite(scope_table{:, feature_names}), 2);
    x = scope_table{valid_mask, feature_names};
    if size(x, 1) >= 2
        pearson_mat = corr(x, 'Type', 'Pearson', 'Rows', 'complete');
        spearman_mat = corr(x, 'Type', 'Spearman', 'Rows', 'complete');
    else
        pearson_mat = nan(numel(feature_names));
        spearman_mat = nan(numel(feature_names));
    end

    pearson_table = matrix_to_labeled_table(pearson_mat, feature_names);
    spearman_table = matrix_to_labeled_table(spearman_mat, feature_names);
    writetable(pearson_table, fullfile(output_dir, sprintf('collinearity_pearson_%s.csv', scope_short)));
    writetable(spearman_table, fullfile(output_dir, sprintf('collinearity_spearman_%s.csv', scope_short)));
    save(fullfile(output_dir, sprintf('collinearity_%s.mat', scope_short)), ...
        'pearson_mat', 'spearman_mat', 'feature_names');
    plot_collinearity_heatmap(pearson_mat, spearman_mat, feature_names, scope_name, ...
        fullfile(output_dir, sprintf('collinearity_heatmap_%s', scope_short)));

    row = table(scope_name, sum(scope_mask), sum(valid_mask), ...
        'VariableNames', {'scope', 'n_total', 'n_valid_all_features'});
    rows = [rows; row]; %#ok<AGROW>
end
out = rows;
end

function [sanity_counts, missing_table] = compute_sanity_tables(scope_table, label_col, feature_names, label_mode, scope_name)
label_values = double(scope_table.(label_col));
label_valid = isfinite(label_values);
labels_binary = label_values == 1;
all_feature_valid = scope_table.valid_flag & all(isfinite(scope_table{:, feature_names}), 2);

sanity_counts = table();
sanity_counts.label_mode = string(label_mode);
sanity_counts.scope = string(scope_name);
sanity_counts.n_total = height(scope_table);
sanity_counts.n_label_valid = sum(label_valid);
sanity_counts.n_label_missing = sum(~label_valid);
sanity_counts.n_los = sum(label_valid & labels_binary);
sanity_counts.n_nlos = sum(label_valid & ~labels_binary);
sanity_counts.n_all_features_valid = sum(all_feature_valid);
sanity_counts.n_joint_valid = sum(label_valid & all_feature_valid);

missing_table = table();
missing_table.label_mode = repmat(string(label_mode), numel(feature_names), 1);
missing_table.scope = repmat(string(scope_name), numel(feature_names), 1);
missing_table.feature_name = string(feature_names(:));
missing_table.n_missing = zeros(numel(feature_names), 1);
missing_table.n_valid = zeros(numel(feature_names), 1);
for idx = 1:numel(feature_names)
    values = scope_table.(feature_names{idx});
    valid_feature = isfinite(values);
    missing_table.n_missing(idx) = sum(~valid_feature);
    missing_table.n_valid(idx) = sum(valid_feature);
end
end

function global_table = compute_global_metrics(scope_table, label_col, feature_names, label_mode, scope_name, params)
rows = repmat(struct( ...
    'label_mode', "", ...
    'scope', "", ...
    'feature_name', "", ...
    'n', NaN, ...
    'n_los', NaN, ...
    'n_nlos', NaN, ...
    'point_biserial', NaN, ...
    'auc_raw', NaN, ...
    'auc_effective', NaN, ...
    'ks_stat', NaN, ...
    'mi_bits', NaN, ...
    'direction', "", ...
    'status', ""), numel(feature_names), 1);

label_values = double(scope_table.(label_col));
for idx = 1:numel(feature_names)
    feature_name = feature_names{idx};
    values = double(scope_table.(feature_name));
    metrics = cp7_binary_feature_metrics(values, label_values, params);
    rows(idx).label_mode = string(label_mode);
    rows(idx).scope = string(scope_name);
    rows(idx).feature_name = string(feature_name);
    rows(idx).n = metrics.n;
    rows(idx).n_los = metrics.n_los;
    rows(idx).n_nlos = metrics.n_nlos;
    rows(idx).point_biserial = metrics.point_biserial;
    rows(idx).auc_raw = metrics.auc_raw;
    rows(idx).auc_effective = metrics.auc_effective;
    rows(idx).ks_stat = metrics.ks_stat;
    rows(idx).mi_bits = metrics.mi_bits;
    rows(idx).direction = string(metrics.direction);
    rows(idx).status = string(metrics.status);
end

global_table = struct2table(rows);
global_table = sortrows(global_table, {'auc_effective', 'ks_stat', 'mi_bits'}, {'descend', 'descend', 'descend'});
end

function [local_sample_table, local_grid_table, winner_table, summary] = ...
    run_local_stage(scope_table, label_col, feature_names, label_mode, scope_name, params)
label_values = double(scope_table.(label_col));
local_sample_table = table();
local_grid_table = table();

for idx = 1:numel(feature_names)
    feature_name = feature_names{idx};
    feature_values = double(scope_table.(feature_name));
    valid_mask = isfinite(feature_values) & isfinite(label_values) & all(isfinite(scope_table{:, {'x_m', 'y_m'}}), 2);
    if ~any(valid_mask)
        continue;
    end

    sub = scope_table(valid_mask, :);
    local_metrics = cp7_local_knn_auc(sub{:, {'x_m', 'y_m'}}, feature_values(valid_mask), label_values(valid_mask), params);

    sample_block = table();
    sample_block.label_mode = repmat(string(label_mode), height(sub), 1);
    sample_block.scope = repmat(string(scope_name), height(sub), 1);
    sample_block.feature_name = repmat(string(feature_name), height(sub), 1);
    sample_block.sample_id = sub.sample_id;
    sample_block.scenario = sub.scenario;
    sample_block.x_m = sub.x_m;
    sample_block.y_m = sub.y_m;
    sample_block.label = label_values(valid_mask);
    sample_block.feature_value = feature_values(valid_mask);
    sample_block.local_raw_auc = local_metrics.local_raw_auc;
    sample_block.local_effective_auc = local_metrics.local_effective_auc;
    sample_block.n_local = local_metrics.n_local;
    sample_block.n_los_local = local_metrics.n_los_local;
    sample_block.n_nlos_local = local_metrics.n_nlos_local;
    sample_block.min_class_local = local_metrics.min_class_local;
    sample_block.unstable_flag = local_metrics.unstable_flag;

    local_sample_table = [local_sample_table; sample_block]; %#ok<AGROW>

    [grid_x, grid_y, mean_raw, mean_eff, mean_n_local, mean_n_los, mean_n_nlos, mean_min_class, any_unstable, n_point] = ...
        aggregate_local_grid(sample_block);
    grid_block = table();
    grid_block.label_mode = repmat(string(label_mode), numel(grid_x), 1);
    grid_block.scope = repmat(string(scope_name), numel(grid_x), 1);
    grid_block.feature_name = repmat(string(feature_name), numel(grid_x), 1);
    grid_block.x_m = grid_x;
    grid_block.y_m = grid_y;
    grid_block.local_raw_auc = mean_raw;
    grid_block.local_effective_auc = mean_eff;
    grid_block.n_local = mean_n_local;
    grid_block.n_los_local = mean_n_los;
    grid_block.n_nlos_local = mean_n_nlos;
    grid_block.min_class_local = mean_min_class;
    grid_block.unstable_flag = any_unstable;
    grid_block.n_points_at_coord = n_point;
    local_grid_table = [local_grid_table; grid_block]; %#ok<AGROW>
end

winner_table = build_winner_table(local_grid_table, feature_names, label_mode, scope_name);

summary = struct();
summary.label_mode = string(label_mode);
summary.scope = string(scope_name);
summary.n_local_rows = height(local_sample_table);
summary.n_grid_rows = height(local_grid_table);
summary.winner_valid_count = sum(isfinite(winner_table.best_auc_effective));
end

function baseline_outputs = run_baseline_stage(scope_table, label_col, feature_names, label_mode, scope_name, params)
label_values = double(scope_table.(label_col));

univariate_rows = repmat(struct( ...
    'label_mode', "", ...
    'scope', "", ...
    'feature_name', "", ...
    'n_valid', NaN, ...
    'n_los', NaN, ...
    'n_nlos', NaN, ...
    'intercept', NaN, ...
    'coef', NaN, ...
    'coef_stderr', NaN, ...
    'coef_pvalue', NaN, ...
    'cv_auc', NaN, ...
    'cv_accuracy', NaN, ...
    'cv_backend', "", ...
    'stats_backend', "", ...
    'status', "", ...
    'warning_message', ""), numel(feature_names), 1);

for idx = 1:numel(feature_names)
    feature_name = feature_names{idx};
    values = double(scope_table.(feature_name));
    result = fit_univariate_logistic(values, label_values, params);
    univariate_rows(idx).label_mode = string(label_mode);
    univariate_rows(idx).scope = string(scope_name);
    univariate_rows(idx).feature_name = string(feature_name);
    univariate_rows(idx).n_valid = result.n_valid;
    univariate_rows(idx).n_los = result.n_los;
    univariate_rows(idx).n_nlos = result.n_nlos;
    univariate_rows(idx).intercept = result.intercept;
    univariate_rows(idx).coef = result.coef;
    univariate_rows(idx).coef_stderr = result.coef_stderr;
    univariate_rows(idx).coef_pvalue = result.coef_pvalue;
    univariate_rows(idx).cv_auc = result.cv_auc;
    univariate_rows(idx).cv_accuracy = result.cv_accuracy;
    univariate_rows(idx).cv_backend = string(result.cv_backend);
    univariate_rows(idx).stats_backend = string(result.stats_backend);
    univariate_rows(idx).status = string(result.status);
    univariate_rows(idx).warning_message = string(result.warning_message);
end
univariate_table = struct2table(univariate_rows);
univariate_table = sortrows(univariate_table, {'cv_auc', 'coef_pvalue'}, {'descend', 'ascend'});

all_feature_mask = all(isfinite(scope_table{:, feature_names}), 2) & isfinite(label_values);
coords_mask = all_feature_mask & all(isfinite(scope_table{:, {'x_m', 'y_m'}}), 2);
labels_all = label_values(all_feature_mask) == 1;
labels_xy = label_values(coords_mask) == 1;

l1_result = fit_l1_logistic(scope_table{all_feature_mask, feature_names}, labels_all, feature_names, params);
l1_xy_result = fit_l1_logistic(scope_table{coords_mask, [feature_names, {'x_m', 'y_m'}]}, labels_xy, [feature_names, {'x_m', 'y_m'}], params);
rf_result = fit_rf_baseline(scope_table{all_feature_mask, feature_names}, labels_all, feature_names, params);

l1_summary = struct_to_single_row(l1_result.summary, label_mode, scope_name);
l1_xy_summary = struct_to_single_row(l1_xy_result.summary, label_mode, scope_name);
rf_summary = struct_to_single_row(rf_result.summary, label_mode, scope_name);

delta_auc = l1_xy_result.summary.auc - l1_result.summary.auc;
summary_row = table(string(label_mode), string(scope_name), l1_result.summary.auc, l1_xy_result.summary.auc, ...
    delta_auc, rf_result.summary.cv_auc, ...
    "ok", "", ...
    'VariableNames', {'label_mode', 'scope', 'l1_auc', 'l1_xy_auc', 'delta_auc_xy', 'rf_cv_auc', 'status', 'skip_reason'});

baseline_outputs = struct();
baseline_outputs.univariate_table = univariate_table;
baseline_outputs.l1_summary = l1_summary;
baseline_outputs.l1_xy_summary = l1_xy_summary;
baseline_outputs.rf_summary = rf_summary;
baseline_outputs.rf_importance = rf_result.importance_table;
baseline_outputs.l1_coefficients = l1_result.coefficient_table;
baseline_outputs.l1_xy_coefficients = l1_xy_result.coefficient_table;
baseline_outputs.summary_row = summary_row;
end

function result = fit_univariate_logistic(values, label_values, params)
valid_mask = isfinite(values) & isfinite(label_values);
x = double(values(valid_mask));
y = double(label_values(valid_mask)) == 1;

result = struct();
result.n_valid = numel(x);
result.n_los = sum(y == 1);
result.n_nlos = sum(y == 0);
result.intercept = NaN;
result.coef = NaN;
result.coef_stderr = NaN;
result.coef_pvalue = NaN;
result.cv_auc = NaN;
result.cv_accuracy = NaN;
result.cv_backend = "none";
result.stats_backend = "none";
result.status = "ok";
result.warning_message = "";

if numel(unique(y)) < 2
    result.status = "single_class";
    return;
end

safe_folds = safe_cv_folds(y, get_param(params, 'cv_folds', 5));
if safe_folds < 2
    result.status = "insufficient_minority";
    return;
end

params_local = struct();
params_local.normalize = true;
params_local.cv_folds = safe_folds;
params_local.random_seed = get_param(params, 'random_seed', 42);
params_local.save_outputs = false;
params_local.log10_rcp = false;
params_local.logistic_backend = 'auto';
params_local.logistic_ridge_lambda = get_param(params, 'logistic_ridge_lambda', 0.01);

try
    [model, ~] = train_logistic(x, y, params_local);
    result.cv_auc = model.cv_auc;
    result.cv_accuracy = model.cv_accuracy;
    result.cv_backend = string(model.backend);
catch exception_info
    result.status = "cv_failed";
    result.warning_message = string(exception_info.message);
    return;
end

[x_norm, ~, ~] = normalize_train_matrix(x);
tbl = table(x_norm, y, 'VariableNames', {'x1', 'label'});
try
    mdl = fitglm(tbl, 'label ~ x1', 'Distribution', 'binomial');
    result.intercept = mdl.Coefficients.Estimate(1);
    result.coef = mdl.Coefficients.Estimate(2);
    result.coef_stderr = mdl.Coefficients.SE(2);
    result.coef_pvalue = mdl.Coefficients.pValue(2);
    result.stats_backend = "fitglm";
catch exception_info
    result.warning_message = string(exception_info.message);
    try
        mdl = fitclinear(x_norm, y, 'Learner', 'logistic', 'Regularization', 'ridge', ...
            'Lambda', get_param(params, 'logistic_ridge_lambda', 0.01), 'Solver', 'lbfgs');
        result.intercept = mdl.Bias;
        result.coef = mdl.Beta(1);
        result.stats_backend = "ridge_fallback";
        result.status = "fitglm_failed";
    catch exception_ridge
        result.warning_message = string(exception_info.message) + " | " + string(exception_ridge.message);
        result.status = "stats_failed";
    end
end
end

function result = fit_l1_logistic(x, y, predictor_names, params)
result = struct();
result.summary = struct( ...
    'status', "ok", ...
    'n_valid', size(x, 1), ...
    'n_los', sum(y == 1), ...
    'n_nlos', sum(y == 0), ...
    'auc', NaN, ...
    'accuracy', NaN, ...
    'lambda', NaN, ...
    'n_selected', NaN, ...
    'selected_features', "", ...
    'warning_message', "");
result.coefficient_table = table(string(predictor_names(:)), nan(numel(predictor_names), 1), false(numel(predictor_names), 1), ...
    'VariableNames', {'predictor_name', 'coefficient', 'selected'});

if isempty(x) || numel(unique(y)) < 2
    result.summary.status = "single_class";
    return;
end

outer_folds = safe_cv_folds(y, get_param(params, 'cv_folds', 5));
if outer_folds < 2
    result.summary.status = "insufficient_minority";
    return;
end

oof_scores = nan(size(y));
lambda_list = nan(outer_folds, 1);
cv = cvpartition(y, 'KFold', outer_folds);

for idx_fold = 1:outer_folds
    tr = training(cv, idx_fold);
    te = test(cv, idx_fold);
    [x_train_norm, mean_values, std_values] = normalize_train_matrix(x(tr, :));
    x_test_norm = apply_train_normalization(x(te, :), mean_values, std_values);

    fit_out = fit_lasso_inner(x_train_norm, y(tr), params);
    if fit_out.failed
        result.summary.status = "lasso_failed";
        result.summary.warning_message = fit_out.warning_message;
        return;
    end

    oof_scores(te) = sigmoid(x_test_norm * fit_out.coefficients + fit_out.intercept);
    lambda_list(idx_fold) = fit_out.lambda;
end

try
    [~, ~, ~, auc_value] = perfcurve(y, oof_scores, true);
catch
    auc_value = NaN;
end
result.summary.auc = auc_value;
result.summary.accuracy = mean((oof_scores >= 0.5) == y);
result.summary.lambda = mean(lambda_list, 'omitnan');

[x_norm_all, ~, ~] = normalize_train_matrix(x);
fit_full = fit_lasso_inner(x_norm_all, y, params);
if fit_full.failed
    result.summary.status = "lasso_failed";
    result.summary.warning_message = fit_full.warning_message;
    return;
end

selected_mask = abs(fit_full.coefficients) > 0;
selected_names = string(predictor_names(selected_mask));
result.summary.lambda = fit_full.lambda;
result.summary.n_selected = sum(selected_mask);
    if any(selected_mask)
        result.summary.selected_features = strjoin(selected_names, ', ');
    else
        result.summary.selected_features = "";
    end
result.coefficient_table = table(string(predictor_names(:)), fit_full.coefficients(:), selected_mask(:), ...
    'VariableNames', {'predictor_name', 'coefficient', 'selected'});
end

function fit_out = fit_lasso_inner(x_train_norm, y_train, params)
fit_out = struct();
fit_out.failed = false;
fit_out.coefficients = nan(size(x_train_norm, 2), 1);
fit_out.intercept = NaN;
fit_out.lambda = NaN;
fit_out.warning_message = "";

inner_folds = safe_cv_folds(y_train, min(get_param(params, 'cv_folds', 5), 5));
if inner_folds < 2
    fit_out.failed = true;
    fit_out.warning_message = "insufficient_minority_inner";
    return;
end

try
    opts = statset('UseParallel', false);
    [B, fit_info] = lassoglm(x_train_norm, double(y_train), 'binomial', ...
        'CV', inner_folds, ...
        'NumLambda', get_param(params, 'l1_num_lambda', 25), ...
        'LambdaRatio', get_param(params, 'l1_lambda_ratio', 1e-3), ...
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

function result = fit_rf_baseline(x, y, predictor_names, params)
result = struct();
result.summary = struct( ...
    'status', "ok", ...
    'n_valid', size(x, 1), ...
    'n_los', sum(y == 1), ...
    'n_nlos', sum(y == 0), ...
    'cv_auc', NaN, ...
    'cv_accuracy', NaN, ...
    'oob_auc', NaN, ...
    'warning_message', "");
result.importance_table = table(string(predictor_names(:)), nan(numel(predictor_names), 1), ...
    'VariableNames', {'predictor_name', 'permuted_delta_error'});

if isempty(x) || numel(unique(y)) < 2
    result.summary.status = "single_class";
    return;
end

outer_folds = safe_cv_folds(y, get_param(params, 'cv_folds', 5));
if outer_folds < 2
    result.summary.status = "insufficient_minority";
    return;
end

num_trees = get_param(params, 'rf_num_trees', 60);
min_leaf = get_param(params, 'rf_min_leaf_size', 2);
oof_scores = nan(size(y));
cv = cvpartition(y, 'KFold', outer_folds);

for idx_fold = 1:outer_folds
    tr = training(cv, idx_fold);
    te = test(cv, idx_fold);
    mdl = TreeBagger(num_trees, x(tr, :), double(y(tr)), ...
        'Method', 'classification', ...
        'MinLeafSize', min_leaf);
    [~, scores] = predict(mdl, x(te, :));
    oof_scores(te) = extract_positive_score(scores, mdl.ClassNames);
end

try
    [~, ~, ~, auc_value] = perfcurve(y, oof_scores, true);
catch
    auc_value = NaN;
end
result.summary.cv_auc = auc_value;
result.summary.cv_accuracy = mean((oof_scores >= 0.5) == y);

try
    mdl_full = TreeBagger(num_trees, x, double(y), ...
        'Method', 'classification', ...
        'MinLeafSize', min_leaf, ...
        'OOBPrediction', 'on', ...
        'OOBPredictorImportance', 'on');
    [~, oob_scores] = oobPredict(mdl_full);
    oob_positive = extract_positive_score(oob_scores, mdl_full.ClassNames);
    [~, ~, ~, result.summary.oob_auc] = perfcurve(y, oob_positive, true);
    result.importance_table = table(string(predictor_names(:)), mdl_full.OOBPermutedPredictorDeltaError(:), ...
        'VariableNames', {'predictor_name', 'permuted_delta_error'});
catch exception_info
    result.summary.status = "oob_failed";
    result.summary.warning_message = string(exception_info.message);
end
end

function row_table = struct_to_single_row(summary_struct, label_mode, scope_name)
row_table = struct2table(summary_struct);
row_table = addvars(row_table, repmat(string(label_mode), height(row_table), 1), ...
    repmat(string(scope_name), height(row_table), 1), ...
    'Before', 1, 'NewVariableNames', {'label_mode', 'scope'});
end

function summary_row = build_summary_row(global_table, winner_table, baseline_outputs, sanity_counts, skip_scope, skip_reason)
if skip_scope || isempty(global_table)
    best_feature = "";
    best_auc = NaN;
else
    best_feature = string(global_table.feature_name(1));
    best_auc = global_table.auc_effective(1);
end

winner_valid = winner_table(isfinite(winner_table.best_auc_effective), :);
if isempty(winner_valid)
    dominant_feature = "";
    dominant_fraction = NaN;
else
    [group_id, feature_names] = findgroups(winner_valid.best_feature);
    counts = splitapply(@numel, winner_valid.best_feature, group_id);
    [max_count, idx_best] = max(counts);
    dominant_feature = string(feature_names(idx_best));
    dominant_fraction = max_count / height(winner_valid);
end

summary_row = table();
summary_row.label_mode = string(sanity_counts.label_mode);
summary_row.scope = string(sanity_counts.scope);
summary_row.n_total = sanity_counts.n_total;
summary_row.n_joint_valid = sanity_counts.n_joint_valid;
summary_row.n_los = sanity_counts.n_los;
summary_row.n_nlos = sanity_counts.n_nlos;
summary_row.analysis_status = string(skip_status_label(skip_scope));
summary_row.skip_reason = string(skip_reason);
summary_row.local_k = sanity_counts.local_k;
summary_row.best_global_feature = best_feature;
summary_row.best_global_effective_auc = best_auc;
summary_row.dominant_local_feature = dominant_feature;
summary_row.dominant_local_fraction = dominant_fraction;
summary_row.l1_auc = baseline_outputs.summary_row.l1_auc;
summary_row.l1_xy_auc = baseline_outputs.summary_row.l1_xy_auc;
summary_row.delta_auc_xy = baseline_outputs.summary_row.delta_auc_xy;
summary_row.rf_cv_auc = baseline_outputs.summary_row.rf_cv_auc;
end

function summary_markdown = build_summary_markdown(summary_rows)
lines = {};
lines{end + 1} = '# CP6 Feature Diagnostics Summary';
lines{end + 1} = '- Measurement setting: RHCP transmission, dual-CP reception.';
lines{end + 1} = '- Final lock: 6 features (fp_idx_diff_rx12 removed from model feature set).';
lines{end + 1} = '';
for idx = 1:height(summary_rows)
    row = summary_rows(idx, :);
    lines{end + 1} = sprintf('## %s / %s', char(row.label_mode), char(row.scope));
    lines{end + 1} = sprintf('- Samples: total=%d, joint-valid=%d, LoS=%d, NLoS=%d', ...
        row.n_total, row.n_joint_valid, row.n_los, row.n_nlos);
    lines{end + 1} = sprintf('- Status: %s', char(row.analysis_status));
    lines{end + 1} = sprintf('- Local K: %d', row.local_k);
    if row.analysis_status == "skipped_minority_scope"
        lines{end + 1} = sprintf('- Skip reason: %s', char(row.skip_reason));
    else
        lines{end + 1} = sprintf('- Best global feature: %s (effective AUC %.4f)', ...
            char(row.best_global_feature), row.best_global_effective_auc);
        lines{end + 1} = sprintf('- Dominant local winner: %s (fraction %.3f)', ...
            char(row.dominant_local_feature), row.dominant_local_fraction);
        lines{end + 1} = sprintf('- L1 AUC: %.4f, L1+XY AUC: %.4f, delta: %.4f, RF CV AUC: %.4f', ...
            row.l1_auc, row.l1_xy_auc, row.delta_auc_xy, row.rf_cv_auc);
    end
    lines{end + 1} = '';
end
summary_markdown = strjoin(lines, newline);
end

function [grid_x, grid_y, mean_raw, mean_eff, mean_n_local, mean_n_los, mean_n_nlos, mean_min_class, any_unstable, n_point] = ...
    aggregate_local_grid(sample_block)
xy = [round(double(sample_block.x_m), 6), round(double(sample_block.y_m), 6)];
[groups, grid_x, grid_y] = findgroups(xy(:, 1), xy(:, 2));

mean_raw = splitapply(@(v) mean(v, 'omitnan'), sample_block.local_raw_auc, groups);
mean_eff = splitapply(@(v) mean(v, 'omitnan'), sample_block.local_effective_auc, groups);
mean_n_local = splitapply(@(v) mean(v, 'omitnan'), sample_block.n_local, groups);
mean_n_los = splitapply(@(v) mean(v, 'omitnan'), sample_block.n_los_local, groups);
mean_n_nlos = splitapply(@(v) mean(v, 'omitnan'), sample_block.n_nlos_local, groups);
mean_min_class = splitapply(@(v) mean(v, 'omitnan'), sample_block.min_class_local, groups);
any_unstable = splitapply(@any, sample_block.unstable_flag, groups);
n_point = splitapply(@numel, sample_block.sample_id, groups);
end

function winner_table = build_winner_table(local_grid_table, ~, label_mode, scope_name)
if isempty(local_grid_table)
    winner_table = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
        strings(0, 1), zeros(0, 1), zeros(0, 1), false(0, 1), ...
        'VariableNames', {'label_mode', 'scope', 'x_m', 'y_m', ...
        'best_feature', 'best_auc_effective', 'best_min_class_local', 'unstable_flag'});
    return;
end

[groups, x_unique, y_unique] = findgroups(local_grid_table.x_m, local_grid_table.y_m);
n_group = max(groups);
rows = repmat(struct( ...
    'label_mode', "", ...
    'scope', "", ...
    'x_m', NaN, ...
    'y_m', NaN, ...
    'best_feature', "", ...
    'best_auc_effective', NaN, ...
    'best_min_class_local', NaN, ...
    'unstable_flag', false), n_group, 1);

for idx_group = 1:n_group
    mask = groups == idx_group;
    block = local_grid_table(mask, :);
    [best_auc, idx_best] = max(block.local_effective_auc);
    if isempty(idx_best) || ~isfinite(best_auc)
        best_feature = "";
        best_min_class = NaN;
        unstable_flag = false;
        best_auc = NaN;
    else
        best_feature = string(block.feature_name(idx_best));
        best_min_class = block.min_class_local(idx_best);
        unstable_flag = logical(block.unstable_flag(idx_best));
    end

    rows(idx_group).label_mode = string(label_mode);
    rows(idx_group).scope = string(scope_name);
    rows(idx_group).x_m = x_unique(idx_group);
    rows(idx_group).y_m = y_unique(idx_group);
    rows(idx_group).best_feature = best_feature;
    rows(idx_group).best_auc_effective = best_auc;
    rows(idx_group).best_min_class_local = best_min_class;
    rows(idx_group).unstable_flag = unstable_flag;
end

winner_table = struct2table(rows);
winner_table = sortrows(winner_table, {'y_m', 'x_m'}, {'ascend', 'ascend'});
end

function plot_spatial_coverage(scope_table, label_col, label_mode, scope_name, feature_names, output_stub)
fig = figure('Visible', 'off', 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');

label_values = double(scope_table.(label_col));
all_feature_valid = scope_table.valid_flag & all(isfinite(scope_table{:, feature_names}), 2);
los_mask = isfinite(label_values) & (label_values == 1);
nlos_mask = isfinite(label_values) & (label_values == 0);
invalid_mask = ~all_feature_valid;

scatter(ax, scope_table.x_m(los_mask), scope_table.y_m(los_mask), 70, [0.10, 0.45, 0.75], 'filled', 'DisplayName', 'LoS');
scatter(ax, scope_table.x_m(nlos_mask), scope_table.y_m(nlos_mask), 70, [0.80, 0.25, 0.25], 'filled', 'DisplayName', 'NLoS');
if any(invalid_mask)
    scatter(ax, scope_table.x_m(invalid_mask), scope_table.y_m(invalid_mask), 90, ...
        [0.25, 0.25, 0.25], 'x', 'LineWidth', 1.5, 'DisplayName', 'Feature invalid');
end

title(ax, sprintf('Spatial coverage: %s / %s', char(label_mode), char(scope_name)));
xlabel(ax, 'x [m]');
ylabel(ax, 'y [m]');
grid(ax, 'on');
axis(ax, 'equal');
legend(ax, 'Location', 'bestoutside');

save_figure_bundle(fig, output_stub);
end

function plot_global_distribution(scope_table, label_col, feature_names, label_mode, scope_name, output_stub)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1500, 900]);
layout = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(layout, sprintf('Class-conditional violin (7->6 lock): %s / %s | RHCP TX, dual-CP RX', ...
    char(label_mode), char(scope_name)));

label_values = double(scope_table.(label_col));
for idx = 1:numel(feature_names)
    ax = nexttile(layout, idx);
    feature_name = feature_names{idx};
    values = double(scope_table.(feature_name));
    valid_mask = isfinite(values) & isfinite(label_values);
    draw_mirrored_violin(ax, values(valid_mask & (label_values == 1)), values(valid_mask & (label_values == 0)));
    title(ax, strrep(feature_name, '_', '\_'));
    ylabel(ax, 'Feature value');
end

nexttile(layout, 8);
axis off;
text(0, 0.7, 'Left: LoS', 'Color', [0.10, 0.45, 0.75], 'FontSize', 11);
text(0, 0.45, 'Right: NLoS', 'Color', [0.80, 0.25, 0.25], 'FontSize', 11);
text(0, 0.2, sprintf('label=%s, scope=%s', char(label_mode), char(scope_name)), 'FontSize', 10);
text(0, 0.0, 'RHCP transmission, dual-CP reception', 'FontSize', 9, 'Color', [0.2, 0.2, 0.2]);

save_figure_bundle(fig, output_stub);
end

function draw_mirrored_violin(ax, values_los, values_nlos)
hold(ax, 'on');
box(ax, 'on');
grid(ax, 'on');
colors = {[0.10, 0.45, 0.75], [0.80, 0.25, 0.25]};
draw_single_half_violin(ax, values_los, -1, colors{1});
draw_single_half_violin(ax, values_nlos, 1, colors{2});
xlim(ax, [-1.5, 1.5]);
xticks(ax, [-1, 1]);
xticklabels(ax, {'LoS', 'NLoS'});
end

function draw_single_half_violin(ax, values, side, color_value)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    return;
end

center_x = side * 0.4;
if isscalar(values) || isscalar(unique(values))
    plot(ax, center_x, values(1), 'o', 'Color', color_value, 'MarkerFaceColor', color_value);
    return;
end

[f, xi] = ksdensity(values);
if isempty(f) || max(f) <= 0
    plot(ax, center_x * ones(size(values)), values, '.', 'Color', color_value);
    return;
end

width = 0.45 * f ./ max(f);
if side < 0
    x_patch = [center_x - width, fliplr(center_x * ones(size(width)))];
else
    x_patch = [center_x * ones(size(width)), fliplr(center_x + width)];
end
patch(ax, x_patch, [xi, fliplr(xi)], color_value, ...
    'FaceAlpha', 0.35, 'EdgeColor', color_value, 'LineWidth', 1.0);
plot(ax, center_x, median(values), 'k_', 'LineWidth', 1.2, 'MarkerSize', 12);
end

function plot_local_auc_maps(local_grid_table, feature_names, label_mode, scope_name, params, output_stub)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80, 80, 1500, 900]);
layout = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(layout, sprintf('Local effective AUC maps: %s / %s', char(label_mode), char(scope_name)));

for idx = 1:numel(feature_names)
    ax = nexttile(layout, idx);
    feature_name = feature_names{idx};
    block = local_grid_table(local_grid_table.feature_name == string(feature_name), :);
    draw_local_heatmap(ax, block, 'local_effective_auc', [0.5, 1.0], feature_name, ...
        label_mode == "material_class", get_param(params, 'local_warn_min_class', 5));
end

nexttile(layout, 8);
axis off;
text(0, 0.7, 'Color: effective AUC', 'FontSize', 11);
if label_mode == "material_class"
    text(0, 0.45, sprintf('X marker: min class local < %d', get_param(params, 'local_warn_min_class', 5)), 'FontSize', 10);
end

save_figure_bundle(fig, output_stub);
end

function plot_winner_map(winner_table, label_mode, scope_name, output_stub)
fig = figure('Visible', 'off', 'Color', 'w');
ax = axes(fig);
hold(ax, 'on');

valid_mask = winner_table.best_feature ~= "" & isfinite(winner_table.best_auc_effective);
unique_features = unique(winner_table.best_feature(valid_mask), 'stable');
if isempty(unique_features)
    text(ax, 0.5, 0.5, 'No valid winner map', 'HorizontalAlignment', 'center');
    axis(ax, 'off');
    save_figure_bundle(fig, output_stub);
    return;
end

color_map = lines(max(numel(unique_features), 1));
for idx = 1:numel(unique_features)
    mask = valid_mask & winner_table.best_feature == unique_features(idx);
    scatter(ax, winner_table.x_m(mask), winner_table.y_m(mask), 120, color_map(idx, :), 'filled', ...
        'DisplayName', char(unique_features(idx)));
end
unstable_mask = valid_mask & winner_table.unstable_flag;
if any(unstable_mask)
    scatter(ax, winner_table.x_m(unstable_mask), winner_table.y_m(unstable_mask), 150, 'k', 'x', ...
        'LineWidth', 1.5, 'DisplayName', 'unstable');
end

title(ax, sprintf('Winner map (RHCP TX, dual-CP RX): %s / %s', char(label_mode), char(scope_name)));
xlabel(ax, 'x [m]');
ylabel(ax, 'y [m]');
grid(ax, 'on');
axis(ax, 'equal');
legend(ax, 'Location', 'bestoutside');
if string(scope_name) == "B+C"
    text(ax, 0.02, 0.02, 'Caveat: B+C combined scope is noisier than single-scenario maps.', ...
        'Units', 'normalized', 'FontSize', 9, 'Color', [0.25, 0.25, 0.25], ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
        'BackgroundColor', [1.0, 1.0, 1.0]);
end

save_figure_bundle(fig, output_stub);
end

function draw_local_heatmap(ax, grid_table, metric_name, c_limits, plot_title, mark_unstable, warn_min_class)
if isempty(grid_table)
    axis(ax, 'off');
    title(ax, strrep(plot_title, '_', '\_'));
    return;
end

x_unique = unique(grid_table.x_m, 'sorted');
y_unique = unique(grid_table.y_m, 'sorted');
z_mat = nan(numel(y_unique), numel(x_unique));
for idx = 1:height(grid_table)
    x_idx = find(abs(x_unique - grid_table.x_m(idx)) < 1e-9, 1, 'first');
    y_idx = find(abs(y_unique - grid_table.y_m(idx)) < 1e-9, 1, 'first');
    z_mat(y_idx, x_idx) = grid_table.(metric_name)(idx);
end

imagesc(ax, x_unique, y_unique, z_mat);
set(ax, 'YDir', 'normal');
axis(ax, 'image');
hold(ax, 'on');
grid(ax, 'on');
title(ax, strrep(plot_title, '_', '\_'));
xlabel(ax, 'x [m]');
ylabel(ax, 'y [m]');
colormap(ax, parula);
clim(ax, c_limits);
colorbar(ax);

if mark_unstable
    unstable_mask = grid_table.min_class_local < warn_min_class & isfinite(grid_table.min_class_local);
    if any(unstable_mask)
        scatter(ax, grid_table.x_m(unstable_mask), grid_table.y_m(unstable_mask), 80, 'k', 'x', 'LineWidth', 1.2);
    end
end
end

function plot_collinearity_heatmap(pearson_mat, spearman_mat, feature_names, scope_name, output_stub)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1300, 520]);
layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(layout, sprintf('Feature collinearity: %s', char(scope_name)));

ax1 = nexttile(layout, 1);
imagesc(ax1, pearson_mat);
axis(ax1, 'image');
title(ax1, 'Pearson');
xticks(ax1, 1:numel(feature_names));
yticks(ax1, 1:numel(feature_names));
xticklabels(ax1, feature_names);
yticklabels(ax1, feature_names);
xtickangle(ax1, 45);
colorbar(ax1);
clim(ax1, [-1, 1]);

ax2 = nexttile(layout, 2);
imagesc(ax2, spearman_mat);
axis(ax2, 'image');
title(ax2, 'Spearman');
xticks(ax2, 1:numel(feature_names));
yticks(ax2, 1:numel(feature_names));
xticklabels(ax2, feature_names);
yticklabels(ax2, feature_names);
xtickangle(ax2, 45);
colorbar(ax2);
clim(ax2, [-1, 1]);

save_figure_bundle(fig, output_stub);
end

function save_figure_bundle(fig, output_stub)
[output_dir, output_name, ~] = fileparts(output_stub);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
savefig(fig, fullfile(output_dir, [output_name, '.fig']));
exportgraphics(fig, fullfile(output_dir, [output_name, '.png']), 'Resolution', 150);
close(fig);
end

function [label_col, label_short] = label_mode_to_column(label_mode)
label_mode = string(label_mode);
switch label_mode
    case "geometric_class"
        label_col = 'label_geometric';
        label_short = 'geometric';
    case "material_class"
        label_col = 'label_material';
        label_short = 'material';
    otherwise
        error('[run_cp7_feature_diagnostics] Unsupported label mode: %s', label_mode);
end
end

function scope_short = scope_to_short(scope_name)
scope_name = string(scope_name);
switch scope_name
    case "B"
        scope_short = 'b';
    case "C"
        scope_short = 'c';
    case "B+C"
        scope_short = 'bc';
    otherwise
        scope_short = lower(regexprep(char(scope_name), '[^a-zA-Z0-9]', '_'));
end
end

function mask = scope_mask_from_name(scenario, scope_name)
scenario = string(scenario);
scope_name = string(scope_name);
switch scope_name
    case "B"
        mask = scenario == "B";
    case "C"
        mask = scenario == "C";
    case "B+C"
        mask = scenario == "B" | scenario == "C";
    otherwise
        error('[run_cp7_feature_diagnostics] Unsupported scope: %s', scope_name);
end
end

function tbl = matrix_to_labeled_table(mat, names)
tbl = array2table(mat, 'VariableNames', matlab.lang.makeValidName(names));
tbl = addvars(tbl, string(names(:)), 'Before', 1, 'NewVariableNames', 'feature_name');
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

function [x_norm, mean_values, std_values] = normalize_train_matrix(x)
mean_values = mean(x, 1, 'omitnan');
std_values = std(x, 0, 1, 'omitnan');
std_values(std_values == 0) = 1;
x_norm = (x - mean_values) ./ std_values;
end

function x_norm = apply_train_normalization(x, mean_values, std_values)
x_norm = (x - mean_values) ./ std_values;
end

function p = sigmoid(z)
p = 1 ./ (1 + exp(-z));
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
