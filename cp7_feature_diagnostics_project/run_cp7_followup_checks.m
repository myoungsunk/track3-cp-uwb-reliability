function outputs = run_cp7_followup_checks
% RUN_CP7_FOLLOWUP_CHECKS Build follow-up summaries/plots from CP7 diagnostics outputs.
project_dir = fileparts(mfilename('fullpath'));
followup_dir = fullfile(project_dir, '06_followup');
if ~exist(followup_dir, 'dir')
    mkdir(followup_dir);
end

feature_names = string({ ...
    'gamma_CP_rx1', ...
    'gamma_CP_rx2', ...
    'a_FP_RHCP_rx1', ...
    'a_FP_LHCP_rx1', ...
    'a_FP_RHCP_rx2', ...
    'a_FP_LHCP_rx2', ...
    'fp_idx_diff_rx12'});

feature_labels = string({ ...
    '\gamma_{CP,rx1}', ...
    '\gamma_{CP,rx2}', ...
    'a_{FP,RHCP,rx1}', ...
    'a_{FP,LHCP,rx1}', ...
    'a_{FP,RHCP,rx2}', ...
    'a_{FP,LHCP,rx2}', ...
    'fp\_idx\_diff'});

combos = build_combo_table();
global_overview = readtable(fullfile(project_dir, '00_summary', 'cp7_global_overview.csv'));
global_overview.label_mode = string(global_overview.label_mode);
global_overview.scope = string(global_overview.scope);
global_overview.feature_name = string(global_overview.feature_name);

[l1_summary, l1_coefficients] = collect_l1_outputs(project_dir, combos, global_overview, feature_names);
writetable(l1_summary, fullfile(followup_dir, 'l1_followup_summary.csv'));
writetable(l1_coefficients, fullfile(followup_dir, 'l1_followup_coefficients.csv'));
plot_l1_coefficients(l1_summary, l1_coefficients, combos, feature_names, feature_labels, ...
    fullfile(followup_dir, 'l1_coefficients_followup'));

collinearity_pairs = collect_collinearity_pairs(project_dir);
writetable(collinearity_pairs, fullfile(followup_dir, 'collinearity_key_pairs.csv'));
plot_collinearity_pairs(collinearity_pairs, fullfile(followup_dir, 'collinearity_key_pairs'));

[rf_summary, rf_material] = collect_rf_material_outputs(project_dir);
writetable(rf_summary, fullfile(followup_dir, 'rf_material_summary.csv'));
writetable(rf_material, fullfile(followup_dir, 'rf_material_importance_long.csv'));
plot_rf_material(rf_material, feature_names, feature_labels, fullfile(followup_dir, 'rf_material_importance'));

[margin_summary, margin_detail] = collect_local_margin_outputs(project_dir, combos, feature_names);
writetable(margin_summary, fullfile(followup_dir, 'winner_margin_summary.csv'));
writetable(margin_detail, fullfile(followup_dir, 'winner_margin_detail.csv'));
plot_margin_distributions(margin_detail, fullfile(followup_dir, 'winner_margin_distribution'));
plot_margin_maps(margin_summary, margin_detail, combos, fullfile(followup_dir, 'winner_margin_maps'));

[fp_rank_summary, fp_rank_detail] = collect_fp_idx_rank_outputs(margin_detail);
writetable(fp_rank_summary, fullfile(followup_dir, 'fp_idx_material_rank_summary.csv'));
writetable(fp_rank_detail, fullfile(followup_dir, 'fp_idx_material_rank_detail.csv'));
plot_fp_idx_material_behavior(fp_rank_summary, fp_rank_detail, ...
    fullfile(followup_dir, 'fp_idx_material_local_behavior'));

summary_markdown = build_followup_summary_markdown(l1_summary, collinearity_pairs, rf_summary, ...
    margin_summary, fp_rank_summary, fp_rank_detail);
summary_path = fullfile(followup_dir, 'followup_summary.md');
fid = fopen(summary_path, 'w');
if fid < 0
    error('[run_cp7_followup_checks] Failed to write summary markdown: %s', summary_path);
end
cleanup_obj = onCleanup(@() fclose(fid));
fprintf(fid, '%s', summary_markdown);
clear cleanup_obj;

outputs = struct();
outputs.followup_dir = followup_dir;
outputs.l1_summary = l1_summary;
outputs.l1_coefficients = l1_coefficients;
outputs.collinearity_pairs = collinearity_pairs;
outputs.rf_summary = rf_summary;
outputs.rf_material = rf_material;
outputs.margin_summary = margin_summary;
outputs.margin_detail = margin_detail;
outputs.fp_rank_summary = fp_rank_summary;
outputs.fp_rank_detail = fp_rank_detail;
end

function combos = build_combo_table()
combos = table( ...
    string({'geometric_class'; 'geometric_class'; 'geometric_class'; 'material_class'; 'material_class'; 'material_class'}), ...
    string({'geometric'; 'geometric'; 'geometric'; 'material'; 'material'; 'material'}), ...
    string({'Geometric'; 'Geometric'; 'Geometric'; 'Material'; 'Material'; 'Material'}), ...
    string({'B'; 'C'; 'B+C'; 'B'; 'C'; 'B+C'}), ...
    string({'b'; 'c'; 'bc'; 'b'; 'c'; 'bc'}), ...
    string({'B'; 'C'; 'B+C'; 'B'; 'C'; 'B+C'}), ...
    'VariableNames', {'label_mode', 'label_short', 'label_display', 'scope', 'scope_short', 'scope_display'});
combos.group_display = combos.label_display + " / " + combos.scope_display;
end

function [l1_summary, coefficient_rows] = collect_l1_outputs(project_dir, combos, global_overview, feature_names)
l1_summary = table();
coefficient_rows = table();

for idx = 1:height(combos)
    combo = combos(idx, :);
    summary_path = fullfile(project_dir, '05_baselines', ...
        sprintf('multivariate_l1_%s_%s.csv', combo.label_short, combo.scope_short));
    coeff_path = fullfile(project_dir, '05_baselines', ...
        sprintf('l1_coefficients_%s_%s.csv', combo.label_short, combo.scope_short));

    summary_tbl = readtable(summary_path);
    coeff_tbl = readtable(coeff_path);

    if ~isempty(summary_tbl)
        status = string(summary_tbl.status(1));
        l1_auc = double(summary_tbl.auc(1));
        l1_accuracy = double(summary_tbl.accuracy(1));
        lambda_value = double(summary_tbl.lambda(1));
        n_selected = double(summary_tbl.n_selected(1));
        selected_features = string(summary_tbl.selected_features(1));
        warning_message = string(summary_tbl.warning_message(1));
    else
        status = "missing";
        l1_auc = NaN;
        l1_accuracy = NaN;
        lambda_value = NaN;
        n_selected = NaN;
        selected_features = "";
        warning_message = "";
    end

    scope_global = global_overview(global_overview.label_mode == combo.label_mode & ...
        global_overview.scope == combo.scope, :);
    if isempty(scope_global)
        best_global_feature = "";
        best_global_auc = NaN;
    else
        [best_global_auc, best_idx] = max(scope_global.auc_effective);
        best_global_feature = string(scope_global.feature_name(best_idx));
    end

    auc_gain = l1_auc - best_global_auc;
    largest_feature = "";
    largest_abscoef = NaN;

    coeff_map = containers.Map('KeyType', 'char', 'ValueType', 'double');
    selected_map = containers.Map('KeyType', 'char', 'ValueType', 'double');
    if ~isempty(coeff_tbl)
        coeff_tbl.predictor_name = string(coeff_tbl.predictor_name);
        for jdx = 1:height(coeff_tbl)
            name_j = char(coeff_tbl.predictor_name(jdx));
            coeff_map(name_j) = double(coeff_tbl.coefficient(jdx));
            selected_map(name_j) = double(coeff_tbl.selected(jdx));
        end
    end

    for fdx = 1:numel(feature_names)
        feature_name = feature_names(fdx);
        coefficient = NaN;
        selected = 0;
        if isKey(coeff_map, char(feature_name))
            coefficient = coeff_map(char(feature_name));
        end
        if isKey(selected_map, char(feature_name))
            selected = selected_map(char(feature_name));
        end

        if isfinite(coefficient)
            if isnan(largest_abscoef) || abs(coefficient) > largest_abscoef
                largest_abscoef = abs(coefficient);
                largest_feature = feature_name;
            end
        end

        coefficient_rows = [coefficient_rows; table( ...
            combo.label_mode, combo.scope, combo.group_display, feature_name, coefficient, logical(selected), ...
            'VariableNames', {'label_mode', 'scope', 'group_display', 'predictor_name', 'coefficient', 'selected'})]; %#ok<AGROW>
    end

    l1_summary = [l1_summary; table( ...
        combo.label_mode, combo.scope, combo.group_display, status, best_global_feature, best_global_auc, ...
        l1_auc, auc_gain, l1_accuracy, lambda_value, n_selected, selected_features, ...
        largest_feature, largest_abscoef, warning_message, ...
        'VariableNames', {'label_mode', 'scope', 'group_display', 'status', 'best_global_feature', ...
        'best_global_auc', 'l1_auc', 'auc_gain_vs_best_global', 'l1_accuracy', 'lambda', 'n_selected', ...
        'selected_features', 'largest_abscoef_feature', 'largest_abscoef', 'warning_message'})]; %#ok<AGROW>
end
end

function collinearity_pairs = collect_collinearity_pairs(project_dir)
scopes = { ...
    'B', 'b'; ...
    'C', 'c'; ...
    'B+C', 'bc'};

pair_defs = { ...
    'a_FP_RHCP_rx1', 'a_FP_LHCP_rx1', 'a_FP_RHCP_rx1 <-> a_FP_LHCP_rx1'; ...
    'gamma_CP_rx1', 'gamma_CP_rx2', 'gamma_CP_rx1 <-> gamma_CP_rx2'};

collinearity_pairs = table();
for idx_scope = 1:size(scopes, 1)
    scope_display = string(scopes{idx_scope, 1});
    scope_short = char(scopes{idx_scope, 2});
    pearson_tbl = readtable(fullfile(project_dir, '03_collinearity', ...
        sprintf('collinearity_pearson_%s.csv', scope_short)));
    spearman_tbl = readtable(fullfile(project_dir, '03_collinearity', ...
        sprintf('collinearity_spearman_%s.csv', scope_short)));
    pearson_tbl.feature_name = string(pearson_tbl.feature_name);
    spearman_tbl.feature_name = string(spearman_tbl.feature_name);

    for idx_pair = 1:size(pair_defs, 1)
        feature_a = string(pair_defs{idx_pair, 1});
        feature_b = string(pair_defs{idx_pair, 2});
        pair_name = string(pair_defs{idx_pair, 3});

        pearson_value = lookup_matrix_value(pearson_tbl, feature_a, feature_b);
        spearman_value = lookup_matrix_value(spearman_tbl, feature_a, feature_b);

        collinearity_pairs = [collinearity_pairs; table( ...
            scope_display, pair_name, feature_a, feature_b, pearson_value, spearman_value, ...
            'VariableNames', {'scope', 'pair_name', 'feature_a', 'feature_b', 'pearson', 'spearman'})]; %#ok<AGROW>
    end
end
end

function value = lookup_matrix_value(matrix_table, row_name, col_name)
row_mask = matrix_table.feature_name == row_name;
if ~any(row_mask)
    value = NaN;
    return;
end

var_name = char(col_name);
if ~ismember(var_name, matrix_table.Properties.VariableNames)
    value = NaN;
    return;
end

value = double(matrix_table{find(row_mask, 1, 'first'), var_name});
end

function [rf_summary, rf_long] = collect_rf_material_outputs(project_dir)
scopes = { ...
    'C', 'c'; ...
    'B+C', 'bc'};

rf_summary = table();
rf_long = table();
for idx_scope = 1:size(scopes, 1)
    scope_display = string(scopes{idx_scope, 1});
    scope_short = char(scopes{idx_scope, 2});
    rf_tbl = readtable(fullfile(project_dir, '05_baselines', ...
        sprintf('rf_importance_material_%s.csv', scope_short)));
    rf_tbl.predictor_name = string(rf_tbl.predictor_name);
    rf_tbl.scope = repmat(scope_display, height(rf_tbl), 1);
    rf_tbl.label_mode = repmat("material_class", height(rf_tbl), 1);
    rf_tbl = movevars(rf_tbl, {'label_mode', 'scope'}, 'Before', 1);
    rf_long = [rf_long; rf_tbl]; %#ok<AGROW>

    sorted_tbl = sortrows(rf_tbl, 'permuted_delta_error', 'descend');
    top_feature = "";
    top_importance = NaN;
    second_feature = "";
    second_importance = NaN;
    if ~isempty(sorted_tbl)
        top_feature = string(sorted_tbl.predictor_name(1));
        top_importance = double(sorted_tbl.permuted_delta_error(1));
    end
    if height(sorted_tbl) >= 2
        second_feature = string(sorted_tbl.predictor_name(2));
        second_importance = double(sorted_tbl.permuted_delta_error(2));
    end

    rf_summary = [rf_summary; table( ...
        "material_class", scope_display, top_feature, top_importance, second_feature, second_importance, ...
        'VariableNames', {'label_mode', 'scope', 'top_feature', 'top_importance', 'second_feature', 'second_importance'})]; %#ok<AGROW>
end
end

function [margin_summary, margin_detail] = collect_local_margin_outputs(project_dir, combos, feature_names)
margin_summary = table();
margin_detail = table();

for idx = 1:height(combos)
    combo = combos(idx, :);
    local_path = fullfile(project_dir, '04_local', ...
        sprintf('local_grid_metrics_%s_%s.csv', combo.label_short, combo.scope_short));
    local_tbl = readtable(local_path);

    if isempty(local_tbl)
        margin_summary = [margin_summary; table( ...
            combo.label_mode, combo.scope, combo.group_display, "skipped", ...
            0, 0, NaN, NaN, NaN, NaN, NaN, NaN, ...
            'VariableNames', {'label_mode', 'scope', 'group_display', 'status', 'n_coords_total', ...
            'n_margin_valid', 'mean_margin_all', 'median_margin_all', 'mean_margin_stable', ...
            'median_margin_stable', 'share_margin_lt_005_all', 'share_margin_lt_005_stable'})]; %#ok<AGROW>
        continue;
    end

    local_tbl.feature_name = string(local_tbl.feature_name);
    [coord_groups, coord_keys] = findgroups(local_tbl(:, {'x_m', 'y_m'}));
    n_groups = max(coord_groups);

    detail_rows = table();
    for idx_group = 1:n_groups
        group_mask = coord_groups == idx_group;
        block = local_tbl(group_mask, :);
        auc_values = nan(numel(feature_names), 1);
        min_class_value = NaN;
        unstable_flag = false;

        for fdx = 1:numel(feature_names)
            feature_name = feature_names(fdx);
            row_mask = block.feature_name == feature_name;
            if any(row_mask)
                auc_values(fdx) = double(block.local_effective_auc(find(row_mask, 1, 'first')));
                min_class_value = double(block.min_class_local(find(row_mask, 1, 'first')));
                unstable_flag = logical(block.unstable_flag(find(row_mask, 1, 'first')));
            end
        end

        finite_mask = isfinite(auc_values);
        n_finite = sum(finite_mask);
        winner_feature = "";
        runner_feature = "";
        winner_auc = NaN;
        runner_auc = NaN;
        margin = NaN;
        fp_rank = NaN;
        fp_auc = NaN;
        fp_gap_to_best = NaN;

        if n_finite > 0
            finite_idx = find(finite_mask);
            finite_auc = auc_values(finite_idx);
            [sorted_auc, order] = sort(finite_auc, 'descend');
            sorted_idx = finite_idx(order);
            winner_feature = feature_names(sorted_idx(1));
            winner_auc = sorted_auc(1);

            fp_idx = find(feature_names == "fp_idx_diff_rx12", 1, 'first');
            if isfinite(auc_values(fp_idx))
                fp_auc = auc_values(fp_idx);
                fp_gap_to_best = winner_auc - fp_auc;
                fp_rank = find(sorted_idx == fp_idx, 1, 'first');
            end

            if n_finite >= 2
                runner_feature = feature_names(sorted_idx(2));
                runner_auc = sorted_auc(2);
                margin = winner_auc - runner_auc;
            end
        end

        stable_flag = isfinite(min_class_value) && min_class_value >= 5;

        detail_rows = [detail_rows; table( ...
            combo.label_mode, combo.scope, combo.group_display, coord_keys.x_m(idx_group), coord_keys.y_m(idx_group), ...
            n_finite, winner_feature, runner_feature, winner_auc, runner_auc, margin, min_class_value, ...
            logical(unstable_flag), logical(stable_flag), fp_rank, fp_auc, fp_gap_to_best, ...
            'VariableNames', {'label_mode', 'scope', 'group_display', 'x_m', 'y_m', 'n_finite', ...
            'winner_feature', 'runner_feature', 'winner_auc', 'runner_auc', 'margin', 'min_class_local', ...
            'unstable_flag', 'stable_flag', 'fp_idx_rank', 'fp_idx_auc', 'fp_idx_gap_to_best'})]; %#ok<AGROW>
    end

    margin_detail = [margin_detail; detail_rows]; %#ok<AGROW>

    finite_margin = isfinite(detail_rows.margin);
    stable_margin = finite_margin & detail_rows.stable_flag;

    margin_summary = [margin_summary; table( ...
        combo.label_mode, combo.scope, combo.group_display, "ok", ...
        height(detail_rows), sum(finite_margin), ...
        safe_mean(detail_rows.margin(finite_margin)), safe_median(detail_rows.margin(finite_margin)), ...
        safe_mean(detail_rows.margin(stable_margin)), safe_median(detail_rows.margin(stable_margin)), ...
        safe_mean(double(detail_rows.margin(finite_margin) < 0.05)), ...
        safe_mean(double(detail_rows.margin(stable_margin) < 0.05)), ...
        'VariableNames', {'label_mode', 'scope', 'group_display', 'status', 'n_coords_total', ...
        'n_margin_valid', 'mean_margin_all', 'median_margin_all', 'mean_margin_stable', ...
        'median_margin_stable', 'share_margin_lt_005_all', 'share_margin_lt_005_stable'})]; %#ok<AGROW>
end
end

function [fp_rank_summary, fp_rank_detail] = collect_fp_idx_rank_outputs(margin_detail)
material_mask = margin_detail.label_mode == "material_class" & ...
    ismember(margin_detail.scope, ["C", "B+C"]);
fp_rank_detail = margin_detail(material_mask, :);
fp_rank_summary = table();

scopes = unique(fp_rank_detail.scope, 'stable');
for idx_scope = 1:numel(scopes)
    scope_name = scopes(idx_scope);
    block = fp_rank_detail(fp_rank_detail.scope == scope_name, :);
    rank_winner = sum(block.fp_idx_rank == 1);
    rank_runner = sum(block.fp_idx_rank == 2);
    rank_lower = sum(block.fp_idx_rank > 2);
    rank_missing = sum(~isfinite(block.fp_idx_rank));
    stable_winner = sum(block.fp_idx_rank == 1 & block.stable_flag);
    stable_runner = sum(block.fp_idx_rank == 2 & block.stable_flag);
    median_gap = safe_median(block.fp_idx_gap_to_best(isfinite(block.fp_idx_gap_to_best)));
    mean_gap = safe_mean(block.fp_idx_gap_to_best(isfinite(block.fp_idx_gap_to_best)));

    fp_rank_summary = [fp_rank_summary; table( ...
        "material_class", scope_name, height(block), rank_winner, rank_runner, rank_lower, rank_missing, ...
        stable_winner, stable_runner, mean_gap, median_gap, ...
        'VariableNames', {'label_mode', 'scope', 'n_coords', 'winner_count', 'runner_up_count', ...
        'lower_rank_count', 'missing_count', 'stable_winner_count', 'stable_runner_up_count', ...
        'mean_gap_to_best', 'median_gap_to_best'})]; %#ok<AGROW>
end
end

function plot_l1_coefficients(l1_summary, l1_coefficients, combos, feature_names, feature_labels, stem_path)
fig = figure('Visible', 'off', 'Position', [100, 100, 1400, 800]);
tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

for idx = 1:height(combos)
    nexttile;
    combo = combos(idx, :);
    coeff_block = l1_coefficients(l1_coefficients.label_mode == combo.label_mode & ...
        l1_coefficients.scope == combo.scope, :);
    summary_block = l1_summary(l1_summary.label_mode == combo.label_mode & ...
        l1_summary.scope == combo.scope, :);

    if isempty(coeff_block)
        axis off;
        text(0.1, 0.5, 'No coefficients', 'FontWeight', 'bold');
        title(char(combo.group_display));
        continue;
    end

    coeff_values = nan(numel(feature_names), 1);
    selected = false(numel(feature_names), 1);
    for fdx = 1:numel(feature_names)
        row_mask = coeff_block.predictor_name == feature_names(fdx);
        if any(row_mask)
            coeff_values(fdx) = coeff_block.coefficient(find(row_mask, 1, 'first'));
            selected(fdx) = coeff_block.selected(find(row_mask, 1, 'first'));
        end
    end

    bh = barh(coeff_values, 'FaceColor', 'flat');
    bh.CData = repmat([0.7, 0.7, 0.7], numel(feature_names), 1);
    bh.CData(selected, :) = repmat([0.1, 0.45, 0.85], sum(selected), 1);
    set(gca, 'YDir', 'reverse');
    yticklabels(feature_labels);
    xline(0, 'k-');
    grid on;

    auc_gain = NaN;
    n_selected = NaN;
    if ~isempty(summary_block)
        auc_gain = summary_block.auc_gain_vs_best_global(1);
        n_selected = summary_block.n_selected(1);
    end
    title(sprintf('%s | nz=%d | \\DeltaAUC=%.3f', ...
        char(combo.group_display), round(n_selected), auc_gain), 'Interpreter', 'tex');
end

save_plot(fig, stem_path);
end

function plot_collinearity_pairs(collinearity_pairs, stem_path)
pair_names = unique(collinearity_pairs.pair_name, 'stable');
scopes = categorical(["B", "C", "B+C"], ["B", "C", "B+C"]);

fig = figure('Visible', 'off', 'Position', [120, 120, 1200, 450]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

for idx_pair = 1:numel(pair_names)
    nexttile;
    block = collinearity_pairs(collinearity_pairs.pair_name == pair_names(idx_pair), :);
    pearson_vals = nan(1, numel(scopes));
    spearman_vals = nan(1, numel(scopes));
    for idx_scope = 1:numel(scopes)
        row_mask = block.scope == string(scopes(idx_scope));
        if any(row_mask)
            pearson_vals(idx_scope) = block.pearson(find(row_mask, 1, 'first'));
            spearman_vals(idx_scope) = block.spearman(find(row_mask, 1, 'first'));
        end
    end

    bar(scopes, [pearson_vals(:), spearman_vals(:)], 'grouped');
    yline(0.8, 'r--', '0.8');
    yline(-0.8, 'r--', '-0.8');
    ylim([-1, 1]);
    ylabel('Correlation');
    legend({'Pearson', 'Spearman'}, 'Location', 'northoutside', 'Orientation', 'horizontal');
    title(char(pair_names(idx_pair)));
    grid on;
end

save_plot(fig, stem_path);
end

function plot_rf_material(rf_material, feature_names, feature_labels, stem_path)
scopes = ["C", "B+C"];
fig = figure('Visible', 'off', 'Position', [120, 120, 1200, 500]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

for idx_scope = 1:numel(scopes)
    nexttile;
    block = rf_material(rf_material.scope == scopes(idx_scope), :);
    values = nan(numel(feature_names), 1);
    for fdx = 1:numel(feature_names)
        row_mask = block.predictor_name == feature_names(fdx);
        if any(row_mask)
            values(fdx) = block.permuted_delta_error(find(row_mask, 1, 'first'));
        end
    end
    [sorted_values, order] = sort(values, 'descend');
    barh(sorted_values, 'FaceColor', [0.2, 0.6, 0.35]);
    set(gca, 'YDir', 'reverse');
    yticklabels(feature_labels(order));
    xline(0, 'k-');
    grid on;
    title(sprintf('Material / %s RF Permutation Importance', scopes(idx_scope)), 'Interpreter', 'none');
    xlabel('\Delta error after permutation');
end

save_plot(fig, stem_path);
end

function plot_margin_distributions(margin_detail, stem_path)
valid_mask = isfinite(margin_detail.margin);
stable_mask = valid_mask & margin_detail.stable_flag;

fig = figure('Visible', 'off', 'Position', [120, 120, 1200, 500]);
subplot(1, 2, 1);
if any(valid_mask)
    boxplot(margin_detail.margin(valid_mask), cellstr(margin_detail.group_display(valid_mask)));
    yline(0.05, 'r--', '0.05');
    ylabel('Winner - Runner-up effective AUC');
    title('All valid local margins');
    xtickangle(25);
    grid on;
else
    axis off;
    text(0.1, 0.5, 'No valid margins');
end

subplot(1, 2, 2);
if any(stable_mask)
    boxplot(margin_detail.margin(stable_mask), cellstr(margin_detail.group_display(stable_mask)));
    yline(0.05, 'r--', '0.05');
    ylabel('Winner - Runner-up effective AUC');
    title('Stable local margins (min class >= 5)');
    xtickangle(25);
    grid on;
else
    axis off;
    text(0.1, 0.5, 'No stable margins');
end

save_plot(fig, stem_path);
end

function plot_margin_maps(margin_summary, margin_detail, combos, stem_path)
fig = figure('Visible', 'off', 'Position', [100, 100, 1400, 800]);
tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

margin_cap = 0.25;
for idx = 1:height(combos)
    nexttile;
    combo = combos(idx, :);
    block = margin_detail(margin_detail.label_mode == combo.label_mode & ...
        margin_detail.scope == combo.scope, :);
    summary_block = margin_summary(margin_summary.label_mode == combo.label_mode & ...
        margin_summary.scope == combo.scope, :);

    if isempty(block)
        axis off;
        status_text = 'No local data';
        if ~isempty(summary_block)
            status_text = char(summary_block.status(1));
        end
        text(0.15, 0.55, status_text, 'FontWeight', 'bold');
        title(char(combo.group_display));
        continue;
    end

    color_values = block.margin;
    color_values(~isfinite(color_values)) = -0.02;
    scatter(block.x_m, block.y_m, 260, color_values, 's', 'filled');
    hold on;
    unstable_mask = block.unstable_flag;
    if any(unstable_mask)
        plot(block.x_m(unstable_mask), block.y_m(unstable_mask), 'kx', 'MarkerSize', 8, 'LineWidth', 1.2);
    end
    hold off;
    axis equal;
    set(gca, 'YDir', 'normal');
    caxis([-0.02, margin_cap]);
    grid on;
    colorbar;
    title(sprintf('%s | med=%.3f | <0.05=%.2f', char(combo.group_display), ...
        summary_block.median_margin_all(1), summary_block.share_margin_lt_005_all(1)));
    xlabel('x (m)');
    ylabel('y (m)');
end

colormap(parula(256));
save_plot(fig, stem_path);
end

function plot_fp_idx_material_behavior(fp_rank_summary, fp_rank_detail, stem_path)
scopes = ["C", "B+C"];
fig = figure('Visible', 'off', 'Position', [80, 80, 1200, 900]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

rank_colors = [ ...
    0.85, 0.2, 0.2; ...
    0.95, 0.65, 0.2; ...
    0.65, 0.65, 0.65; ...
    0.9, 0.9, 0.9];

for idx_scope = 1:numel(scopes)
    scope_name = scopes(idx_scope);
    block = fp_rank_detail(fp_rank_detail.scope == scope_name, :);
    summary_block = fp_rank_summary(fp_rank_summary.scope == scope_name, :);

    nexttile;
    if isempty(block)
        axis off;
        text(0.1, 0.5, 'No data');
    else
        hold on;
        legend_handles = gobjects(0);
        legend_labels = {};
        rank_code = 4 * ones(height(block), 1);
        rank_code(block.fp_idx_rank == 1) = 1;
        rank_code(block.fp_idx_rank == 2) = 2;
        rank_code(block.fp_idx_rank > 2) = 3;

        for code = 1:4
            mask = rank_code == code;
            if any(mask)
                scatter_handle = scatter(block.x_m(mask), block.y_m(mask), 280, ...
                    repmat(rank_colors(code, :), sum(mask), 1), 's', 'filled');
                legend_handles(end+1) = scatter_handle; %#ok<AGROW>
                switch code
                    case 1
                        legend_labels{end+1} = 'Winner'; %#ok<AGROW>
                    case 2
                        legend_labels{end+1} = 'Runner-up'; %#ok<AGROW>
                    case 3
                        legend_labels{end+1} = '3+'; %#ok<AGROW>
                    otherwise
                        legend_labels{end+1} = 'Unavailable'; %#ok<AGROW>
                end
            end
        end
        stable_mask = block.stable_flag & block.fp_idx_rank <= 2;
        if any(stable_mask)
            stable_handle = plot(block.x_m(stable_mask), block.y_m(stable_mask), 'ko', 'MarkerSize', 7, 'LineWidth', 1.1);
            legend_handles(end+1) = stable_handle; %#ok<AGROW>
            legend_labels{end+1} = 'Stable W/R'; %#ok<AGROW>
        end
        hold off;
        axis equal;
        set(gca, 'YDir', 'normal');
        grid on;
        xlabel('x (m)');
        ylabel('y (m)');
        title(sprintf('fp\\_idx rank | Material / %s | W=%d, R=%d', ...
            char(scope_name), summary_block.winner_count(1), summary_block.runner_up_count(1)), ...
            'Interpreter', 'tex');
        legend(legend_handles, legend_labels, 'Location', 'southoutside', 'Orientation', 'horizontal');
    end

    nexttile;
    if isempty(block)
        axis off;
        text(0.1, 0.5, 'No data');
    else
        gap_values = block.fp_idx_gap_to_best;
        gap_values(~isfinite(gap_values)) = NaN;
        scatter(block.x_m, block.y_m, 280, gap_values, 's', 'filled');
        hold on;
        stable_mask = block.stable_flag & isfinite(gap_values);
        if any(stable_mask)
            plot(block.x_m(stable_mask), block.y_m(stable_mask), 'k.', 'MarkerSize', 10);
        end
        hold off;
        axis equal;
        set(gca, 'YDir', 'normal');
        grid on;
        xlabel('x (m)');
        ylabel('y (m)');
        colorbar;
        title(sprintf('Best AUC - fp\\_idx AUC | Material / %s | med=%.3f', ...
            char(scope_name), summary_block.median_gap_to_best(1)), 'Interpreter', 'tex');
    end
end

save_plot(fig, stem_path);
end

function summary_markdown = build_followup_summary_markdown(l1_summary, collinearity_pairs, rf_summary, ...
    margin_summary, fp_rank_summary, fp_rank_detail)
lines = strings(0, 1);
lines(end+1) = "# CP7 Follow-up Checks";
lines(end+1) = "";
lines(end+1) = "## L1 follow-up";

valid_l1 = l1_summary(l1_summary.status == "ok", :);
for idx = 1:height(valid_l1)
    row = valid_l1(idx, :);
    lines(end+1) = sprintf("- %s: L1 AUC %.3f vs best single-feature %.3f (gain %.3f), non-zero=%d, selected={%s}", ...
        row.group_display, row.l1_auc, row.best_global_auc, row.auc_gain_vs_best_global, ...
        round(row.n_selected), char(row.selected_features));
end
skipped_l1 = l1_summary(l1_summary.status ~= "ok", :);
for idx = 1:height(skipped_l1)
    row = skipped_l1(idx, :);
    lines(end+1) = sprintf("- %s: %s", row.group_display, row.status);
end

lines(end+1) = "";
lines(end+1) = "## Key Collinearity Pairs";
for idx = 1:height(collinearity_pairs)
    row = collinearity_pairs(idx, :);
    lines(end+1) = sprintf("- %s | %s: Pearson %.3f, Spearman %.3f", ...
        row.scope, row.pair_name, row.pearson, row.spearman);
end

lines(end+1) = "";
lines(end+1) = "## Material RF Importance";
for idx = 1:height(rf_summary)
    row = rf_summary(idx, :);
    lines(end+1) = sprintf("- Material / %s: top=%s (%.3f), second=%s (%.3f)", ...
        row.scope, row.top_feature, row.top_importance, row.second_feature, row.second_importance);
end

lines(end+1) = "";
lines(end+1) = "## Winner Margin";
valid_margin = margin_summary(margin_summary.status == "ok", :);
for idx = 1:height(valid_margin)
    row = valid_margin(idx, :);
    lines(end+1) = sprintf("- %s: margin mean/median = %.3f / %.3f, stable mean/median = %.3f / %.3f, share<0.05(all/stable)=%.2f / %.2f", ...
        row.group_display, row.mean_margin_all, row.median_margin_all, ...
        row.mean_margin_stable, row.median_margin_stable, ...
        row.share_margin_lt_005_all, row.share_margin_lt_005_stable);
end

lines(end+1) = "";
lines(end+1) = "## fp_idx_diff Material Local Rank";
for idx = 1:height(fp_rank_summary)
    row = fp_rank_summary(idx, :);
    block = fp_rank_detail(fp_rank_detail.scope == row.scope & fp_rank_detail.fp_idx_rank <= 2, :);
    coord_summary = summarize_coord_extent(block);
    lines(end+1) = sprintf("- Material / %s: winner=%d, runner-up=%d, stable winner=%d, stable runner-up=%d, gap mean/median=%.3f / %.3f, footprint=%s", ...
        row.scope, row.winner_count, row.runner_up_count, row.stable_winner_count, row.stable_runner_up_count, ...
        row.mean_gap_to_best, row.median_gap_to_best, coord_summary);
end

summary_markdown = strjoin(cellstr(lines), newline);
end

function coord_summary = summarize_coord_extent(block)
if isempty(block)
    coord_summary = 'none';
    return;
end

x_min = min(block.x_m);
x_max = max(block.x_m);
y_min = min(block.y_m);
y_max = max(block.y_m);
coord_summary = sprintf('x=[%.2f, %.2f], y=[%.2f, %.2f], n=%d', ...
    x_min, x_max, y_min, y_max, height(block));
end

function value = safe_mean(x)
if isempty(x)
    value = NaN;
else
    value = mean(x, 'omitnan');
end
end

function value = safe_median(x)
if isempty(x)
    value = NaN;
else
    value = median(x, 'omitnan');
end
end

function save_plot(fig, stem_path)
png_path = [stem_path '.png'];
fig_path = [stem_path '.fig'];
saveas(fig, png_path);
savefig(fig, fig_path);
close(fig);
end
