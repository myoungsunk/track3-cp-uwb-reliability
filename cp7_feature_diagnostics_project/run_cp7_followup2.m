function outputs = run_cp7_followup2
% RUN_CP7_FOLLOWUP2 Build focused follow-up package:
% 1) material/B+C 2D PDP for (a_FP_RHCP_rx1, gamma_CP_rx2)
% 2) re-run 7 -> 6 feature models without fp_idx_diff_rx12
% 3) two-RX gamma_CP diversity figure

project_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(project_dir);
addpath(fullfile(repo_root, 'src'));

output_dir = fullfile(project_dir, '08_followup2');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

loaded = load(fullfile(project_dir, '01_sanity', 'cp7_analysis_table.mat'));
analysis_table = loaded.analysis_table;
params = loaded.params;

feature_names_7 = [ ...
    "gamma_CP_rx1", ...
    "gamma_CP_rx2", ...
    "a_FP_RHCP_rx1", ...
    "a_FP_LHCP_rx1", ...
    "a_FP_RHCP_rx2", ...
    "a_FP_LHCP_rx2", ...
    "fp_idx_diff_rx12"];
feature_names_6 = feature_names_7(feature_names_7 ~= "fp_idx_diff_rx12");

global_overview = readtable(fullfile(project_dir, '00_summary', 'cp7_global_overview.csv'));
global_overview.label_mode = string(global_overview.label_mode);
global_overview.scope = string(global_overview.scope);
global_overview.feature_name = string(global_overview.feature_name);

interaction_outputs = run_material_bc_interaction_check(analysis_table, params, output_dir, feature_names_7);
fp_ablation_table = run_fp_idx_ablation(analysis_table, params, output_dir, feature_names_7, feature_names_6, global_overview, project_dir);
diversity_table = run_gamma_diversity_figure(analysis_table, output_dir);

summary_md = build_followup2_summary(interaction_outputs, fp_ablation_table, diversity_table);
summary_path = fullfile(output_dir, 'followup2_summary.md');
fid = fopen(summary_path, 'w');
if fid < 0
    error('[run_cp7_followup2] Failed to write summary markdown: %s', summary_path);
end
cleanup_obj = onCleanup(@() fclose(fid));
fprintf(fid, '%s', summary_md);
clear cleanup_obj;

outputs = struct();
outputs.output_dir = output_dir;
outputs.interaction = interaction_outputs;
outputs.fp_ablation = fp_ablation_table;
outputs.diversity = diversity_table;
end

function out = run_material_bc_interaction_check(analysis_table, params, output_dir, feature_names_7)
scope_mask = analysis_table.scenario == "B" | analysis_table.scenario == "C";
label_values = double(analysis_table.label_material);
valid_mask = scope_mask & analysis_table.valid_flag & isfinite(label_values) & ...
    all(isfinite(analysis_table{:, cellstr(feature_names_7)}), 2);

scope_table = analysis_table(valid_mask, :);
x = scope_table{:, cellstr(feature_names_7)};
y = logical(label_values(valid_mask) == 1);

pair_features = ["a_FP_RHCP_rx1", "gamma_CP_rx2"];
idx_x = find(feature_names_7 == pair_features(1), 1, 'first');
idx_y = find(feature_names_7 == pair_features(2), 1, 'first');

rng(local_get_param(params, 'random_seed', 42));
num_trees = local_get_param(params, 'rf_num_trees', 60);
min_leaf = local_get_param(params, 'rf_min_leaf_size', 2);
mdl = TreeBagger(num_trees, x, double(y), ...
    'Method', 'classification', ...
    'MinLeafSize', min_leaf, ...
    'OOBPrediction', 'on', ...
    'OOBPredictorImportance', 'on');

rf_importance = table(feature_names_7(:), mdl.OOBPermutedPredictorDeltaError(:), ...
    'VariableNames', {'predictor_name', 'permuted_delta_error'});
rf_importance = sortrows(rf_importance, 'permuted_delta_error', 'descend');
rf_path = fullfile(output_dir, 'rf_importance_refit_material_bc.csv');
writetable(rf_importance, rf_path);

[pdp_table, pdp_summary] = compute_pair_partial_dependence(mdl, x, idx_x, idx_y, pair_features);
writetable(pdp_table, fullfile(output_dir, 'pdp_material_bc_afpr1_gamma2.csv'));
writetable(struct2table(pdp_summary), fullfile(output_dir, 'interaction_summary_material_bc_afpr1_gamma2.csv'));
plot_pair_partial_dependence(pdp_table, pdp_summary, pair_features, fullfile(output_dir, 'pdp_material_bc_afpr1_gamma2'));

logistic_compare = compare_logistic_interaction_models(x, y, idx_x, idx_y, feature_names_7, params);
writetable(logistic_compare, fullfile(output_dir, 'logistic_interaction_compare_material_bc_afpr1_gamma2.csv'));

out = struct();
out.rf_importance = rf_importance;
out.rf_path = string(rf_path);
out.pdp_table = pdp_table;
out.pdp_summary = pdp_summary;
out.logistic_compare = logistic_compare;
end

function fp_ablation_table = run_fp_idx_ablation(analysis_table, params, output_dir, feature_names_7, feature_names_6, global_overview, project_dir)
combo_table = table( ...
    ["geometric_class"; "geometric_class"; "geometric_class"; "material_class"; "material_class"; "material_class"], ...
    ["geometric"; "geometric"; "geometric"; "material"; "material"; "material"], ...
    ["B"; "C"; "B+C"; "B"; "C"; "B+C"], ...
    ["b"; "c"; "bc"; "b"; "c"; "bc"], ...
    'VariableNames', {'label_mode', 'label_short', 'scope', 'scope_short'});

rows = table();
for idx = 1:height(combo_table)
    label_mode = combo_table.label_mode(idx);
    scope_name = combo_table.scope(idx);
    scope_short = combo_table.scope_short(idx);
    label_col = label_mode_to_column(label_mode);

    scope_mask = scope_mask_from_name(analysis_table.scenario, scope_name);
    label_values = double(analysis_table.(label_col));
    valid_7 = scope_mask & analysis_table.valid_flag & isfinite(label_values) & ...
        all(isfinite(analysis_table{:, cellstr(feature_names_7)}), 2);

    x7 = analysis_table{valid_7, cellstr(feature_names_7)};
    x6 = analysis_table{valid_7, cellstr(feature_names_6)};
    y = logical(label_values(valid_7) == 1);

    row = table();
    row.label_mode = label_mode;
    row.scope = scope_name;
    row.n_valid = sum(valid_7);
    row.n_los = sum(y);
    row.n_nlos = sum(~y);
    row.status = "ok";
    row.fp_idx_single_auc = NaN;
    row.fp_idx_direction = "";
    row.fp_idx_l1_selected = false;
    row.logistic_auc_7 = NaN;
    row.logistic_auc_6 = NaN;
    row.delta_logistic_auc = NaN;
    row.logistic_acc_7 = NaN;
    row.logistic_acc_6 = NaN;
    row.delta_logistic_acc = NaN;
    row.rf_auc_7 = NaN;
    row.rf_auc_6 = NaN;
    row.delta_rf_auc = NaN;
    row.drop_candidate = false;
    row.decision_note = "";

    if numel(unique(y)) < 2 || min(sum(y), sum(~y)) < 2
        row.status = "skipped_minority_scope";
        row.decision_note = "minority class too small";
        rows = [rows; row]; %#ok<AGROW>
        continue;
    end

    params_local = struct();
    params_local.normalize = true;
    params_local.cv_folds = local_get_param(params, 'cv_folds', 5);
    params_local.random_seed = local_get_param(params, 'random_seed', 42);
    params_local.save_outputs = false;
    params_local.log10_rcp = false;
    params_local.logistic_backend = 'auto';
    params_local.logistic_ridge_lambda = local_get_param(params, 'logistic_ridge_lambda', 0.01);

    model7 = train_logistic(x7, y, params_local);
    model6 = train_logistic(x6, y, params_local);
    rf7 = fit_rf_cv_auc(x7, y, feature_names_7, params);
    rf6 = fit_rf_cv_auc(x6, y, feature_names_6, params);

    row.logistic_auc_7 = model7.cv_auc;
    row.logistic_auc_6 = model6.cv_auc;
    row.delta_logistic_auc = model6.cv_auc - model7.cv_auc;
    row.logistic_acc_7 = model7.cv_accuracy;
    row.logistic_acc_6 = model6.cv_accuracy;
    row.delta_logistic_acc = model6.cv_accuracy - model7.cv_accuracy;
    row.rf_auc_7 = rf7.cv_auc;
    row.rf_auc_6 = rf6.cv_auc;
    row.delta_rf_auc = rf6.cv_auc - rf7.cv_auc;

    fp_global = global_overview(global_overview.label_mode == label_mode & ...
        global_overview.scope == scope_name & global_overview.feature_name == "fp_idx_diff_rx12", :);
    if ~isempty(fp_global)
        row.fp_idx_single_auc = fp_global.auc_effective(1);
        row.fp_idx_direction = string(fp_global.direction(1));
    end

    l1_coeff_path = fullfile(project_dir, '05_baselines', ...
        sprintf('l1_coefficients_%s_%s.csv', combo_table.label_short(idx), scope_short));
    if isfile(l1_coeff_path)
        l1_coeff = readtable(l1_coeff_path);
        l1_coeff.predictor_name = string(l1_coeff.predictor_name);
        fp_mask = l1_coeff.predictor_name == "fp_idx_diff_rx12";
        if any(fp_mask)
            row.fp_idx_l1_selected = logical(l1_coeff.selected(find(fp_mask, 1, 'first')));
        end
    end

    if abs(row.delta_logistic_auc) <= 0.01 && abs(row.delta_rf_auc) <= 0.01
        row.drop_candidate = true;
        row.decision_note = "near-zero loss in both logistic and RF";
    elseif abs(row.delta_logistic_auc) <= 0.01
        row.decision_note = "near-zero logistic loss only";
    elseif abs(row.delta_rf_auc) <= 0.01
        row.decision_note = "near-zero RF loss only";
    else
        row.decision_note = "feature removal changes at least one model materially";
    end

    rows = [rows; row]; %#ok<AGROW>
end

fp_ablation_table = rows;
writetable(fp_ablation_table, fullfile(output_dir, 'fp_idx_drop_ablation.csv'));
plot_fp_drop_ablation(fp_ablation_table, fullfile(output_dir, 'fp_idx_drop_ablation'));
end

function rf_result = fit_rf_cv_auc(x, y, predictor_names, params)
rf_result = struct();
rf_result.cv_auc = NaN;
rf_result.cv_accuracy = NaN;
rf_result.importance = table(string(predictor_names(:)), nan(numel(predictor_names), 1), ...
    'VariableNames', {'predictor_name', 'permuted_delta_error'});

if isempty(x) || numel(unique(y)) < 2
    return;
end

folds = safe_cv_folds_local(y, local_get_param(params, 'cv_folds', 5));
if folds < 2
    return;
end

num_trees = local_get_param(params, 'rf_num_trees', 60);
min_leaf = local_get_param(params, 'rf_min_leaf_size', 2);
oof_scores = nan(size(y));
cv = cvpartition(y, 'KFold', folds);

for idx_fold = 1:folds
    tr = training(cv, idx_fold);
    te = test(cv, idx_fold);
    mdl = TreeBagger(num_trees, x(tr, :), double(y(tr)), ...
        'Method', 'classification', ...
        'MinLeafSize', min_leaf);
    oof_scores(te) = predict_positive_score(mdl, x(te, :));
end

try
    [~, ~, ~, auc_value] = perfcurve(y, oof_scores, true);
catch
    auc_value = NaN;
end
rf_result.cv_auc = auc_value;
rf_result.cv_accuracy = mean((oof_scores >= 0.5) == y);
end

function diversity_table = run_gamma_diversity_figure(analysis_table, output_dir)
scopes = ["B", "C", "B+C"];
rows = table();

fig = figure('Visible', 'off', 'Position', [100, 100, 1500, 450]);
tiledlayout(1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

for idx_scope = 1:numel(scopes)
    scope_name = scopes(idx_scope);
    scope_mask = scope_mask_from_name(analysis_table.scenario, scope_name) & ...
        analysis_table.valid_flag & isfinite(analysis_table.gamma_CP_rx1) & isfinite(analysis_table.gamma_CP_rx2) & ...
        isfinite(double(analysis_table.label_geometric));
    block = analysis_table(scope_mask, :);

    x = double(block.gamma_CP_rx1);
    y = double(block.gamma_CP_rx2);
    z1 = zscore_safe(x);
    z2 = zscore_safe(y);
    pearson_value = corr(x, y, 'Type', 'Pearson', 'Rows', 'complete');
    spearman_value = corr(x, y, 'Type', 'Spearman', 'Rows', 'complete');
    opposite_fraction = mean(sign(z1) ~= sign(z2), 'omitnan');

    rows = [rows; table(scope_name, height(block), pearson_value, spearman_value, opposite_fraction, ...
        'VariableNames', {'scope', 'n_valid', 'pearson', 'spearman', 'opposite_sign_fraction'})]; %#ok<AGROW>

    nexttile;
    los_mask = logical(block.label_geometric == 1);
    nlos_mask = logical(block.label_geometric == 0);
    hold on;
    if any(los_mask)
        scatter(z1(los_mask), z2(los_mask), 42, [0.1, 0.45, 0.85], 'filled');
    end
    if any(nlos_mask)
        scatter(z1(nlos_mask), z2(nlos_mask), 42, [0.9, 0.45, 0.1], 'filled');
    end
    xline(0, 'k:');
    yline(0, 'k:');
    coeff = polyfit(z1, z2, 1);
    x_line = linspace(min(z1), max(z1), 100);
    y_line = polyval(coeff, x_line);
    plot(x_line, y_line, 'k-', 'LineWidth', 1.2);
    hold off;
    grid on;
    axis square;
    xlabel('z(gamma\_CP\_rx1)', 'Interpreter', 'tex');
    ylabel('z(gamma\_CP\_rx2)', 'Interpreter', 'tex');
    title(sprintf('%s | r=%.3f | \\rho=%.3f | opp=%.2f', ...
        char(scope_name), pearson_value, spearman_value, opposite_fraction), 'Interpreter', 'tex');
    legend({'LoS', 'NLoS'}, 'Location', 'southoutside', 'Orientation', 'horizontal');
end

save_plot(fig, fullfile(output_dir, 'gamma_cp_diversity_figure'));
writetable(rows, fullfile(output_dir, 'gamma_cp_diversity_summary.csv'));
diversity_table = rows;
end

function [pdp_table, summary] = compute_pair_partial_dependence(mdl, x, idx_x, idx_y, pair_features)
x_values = x(:, idx_x);
y_values = x(:, idx_y);

grid_x = linspace(prctile(x_values, 5), prctile(x_values, 95), 25);
grid_y = linspace(prctile(y_values, 5), prctile(y_values, 95), 25);

pdp_x = nan(numel(grid_x), 1);
pdp_y = nan(numel(grid_y), 1);
pdp_surface = nan(numel(grid_x), numel(grid_y));

for idx1 = 1:numel(grid_x)
    x_tmp = x;
    x_tmp(:, idx_x) = grid_x(idx1);
    pdp_x(idx1) = mean(predict_positive_score(mdl, x_tmp), 'omitnan');
end

for idx2 = 1:numel(grid_y)
    x_tmp = x;
    x_tmp(:, idx_y) = grid_y(idx2);
    pdp_y(idx2) = mean(predict_positive_score(mdl, x_tmp), 'omitnan');
end

for idx1 = 1:numel(grid_x)
    for idx2 = 1:numel(grid_y)
        x_tmp = x;
        x_tmp(:, idx_x) = grid_x(idx1);
        x_tmp(:, idx_y) = grid_y(idx2);
        pdp_surface(idx1, idx2) = mean(predict_positive_score(mdl, x_tmp), 'omitnan');
    end
end

surface_mean = mean(pdp_surface(:), 'omitnan');
interaction_surface = pdp_surface - pdp_x - pdp_y' + surface_mean;
surface_centered = pdp_surface - surface_mean;
num_value = mean(interaction_surface(:).^2, 'omitnan');
den_value = mean(surface_centered(:).^2, 'omitnan');
if den_value <= 0
    h_value = NaN;
else
    h_value = sqrt(num_value / den_value);
end

[peak_value, peak_idx] = max(interaction_surface(:));
[trough_value, trough_idx] = min(interaction_surface(:));
[peak_x_idx, peak_y_idx] = ind2sub(size(interaction_surface), peak_idx);
[trough_x_idx, trough_y_idx] = ind2sub(size(interaction_surface), trough_idx);

[grid_x_mesh, grid_y_mesh] = ndgrid(grid_x, grid_y);
pdp_table = table( ...
    repmat(pair_features(1), numel(grid_x_mesh), 1), ...
    repmat(pair_features(2), numel(grid_x_mesh), 1), ...
    grid_x_mesh(:), grid_y_mesh(:), pdp_surface(:), ...
    repelem(pdp_x, numel(grid_y)), repmat(pdp_y(:), numel(grid_x), 1), ...
    interaction_surface(:), ...
    'VariableNames', {'feature_x', 'feature_y', 'feature_x_value', 'feature_y_value', ...
    'partial_dependence', 'pd_feature_x', 'pd_feature_y', 'interaction_residual'});

summary = struct();
summary.feature_x = pair_features(1);
summary.feature_y = pair_features(2);
summary.rf_h_statistic = h_value;
summary.interaction_rms = sqrt(num_value);
summary.interaction_peak = peak_value;
summary.interaction_peak_feature_x = grid_x(peak_x_idx);
summary.interaction_peak_feature_y = grid_y(peak_y_idx);
summary.interaction_trough = trough_value;
summary.interaction_trough_feature_x = grid_x(trough_x_idx);
summary.interaction_trough_feature_y = grid_y(trough_y_idx);
summary.pd_range = max(pdp_surface(:)) - min(pdp_surface(:));
summary.interaction_range = peak_value - trough_value;
end

function logistic_table = compare_logistic_interaction_models(x, y, idx_x, idx_y, feature_names_7, params)
pair_x = x(:, [idx_x, idx_y]);
pair_int = [pair_x, pair_x(:, 1) .* pair_x(:, 2)];
full_x = x;
full_int = [x, x(:, idx_x) .* x(:, idx_y)];

params_local = struct();
params_local.normalize = true;
params_local.cv_folds = local_get_param(params, 'cv_folds', 5);
params_local.random_seed = local_get_param(params, 'random_seed', 42);
params_local.save_outputs = false;
params_local.log10_rcp = false;
params_local.logistic_backend = 'auto';
params_local.logistic_ridge_lambda = local_get_param(params, 'logistic_ridge_lambda', 0.01);

model_pair_add = train_logistic(pair_x, y, params_local);
model_pair_int = train_logistic(pair_int, y, params_local);
model_full_add = train_logistic(full_x, y, params_local);
model_full_int = train_logistic(full_int, y, params_local);

[pair_coef, pair_p] = fit_interaction_glm(pair_int, y, size(pair_int, 2));
[full_coef, full_p] = fit_interaction_glm(full_int, y, size(full_int, 2));

logistic_table = table( ...
    ["pair_additive"; "pair_plus_interaction"; "full7_additive"; "full7_plus_interaction"], ...
    [model_pair_add.cv_auc; model_pair_int.cv_auc; model_full_add.cv_auc; model_full_int.cv_auc], ...
    [model_pair_add.cv_accuracy; model_pair_int.cv_accuracy; model_full_add.cv_accuracy; model_full_int.cv_accuracy], ...
    ["none"; "a_FP_RHCP_rx1*gamma_CP_rx2"; "none"; "a_FP_RHCP_rx1*gamma_CP_rx2"], ...
    [NaN; pair_coef; NaN; full_coef], ...
    [NaN; pair_p; NaN; full_p], ...
    [0; model_pair_int.cv_auc - model_pair_add.cv_auc; 0; model_full_int.cv_auc - model_full_add.cv_auc], ...
    [0; model_pair_int.cv_accuracy - model_pair_add.cv_accuracy; 0; model_full_int.cv_accuracy - model_full_add.cv_accuracy], ...
    ["a_FP_RHCP_rx1 + gamma_CP_rx2"; ...
     "a_FP_RHCP_rx1 + gamma_CP_rx2 + interaction"; ...
     strjoin(feature_names_7, " + "); ...
     strjoin(feature_names_7, " + ") + " + interaction"], ...
    'VariableNames', {'model_name', 'cv_auc', 'cv_accuracy', 'interaction_feature', ...
    'interaction_coef', 'interaction_pvalue', 'delta_auc_vs_additive', 'delta_accuracy_vs_additive', 'feature_set'});
end

function [coef_value, p_value] = fit_interaction_glm(x, y, interaction_col_idx)
coef_value = NaN;
p_value = NaN;

mu = mean(x, 1, 'omitnan');
sigma = std(x, 0, 1, 'omitnan');
sigma(sigma == 0) = 1;
z = (x - mu) ./ sigma;

tbl = array2table(z, 'VariableNames', arrayfun(@(k) sprintf('x%d', k), 1:size(z, 2), 'UniformOutput', false));
tbl.label = y;
formula = sprintf('label ~ %s', strjoin(tbl.Properties.VariableNames(1:end-1), ' + '));
try
    mdl = fitglm(tbl, formula, 'Distribution', 'binomial');
    coef_value = mdl.Coefficients.Estimate(interaction_col_idx + 1);
    p_value = mdl.Coefficients.pValue(interaction_col_idx + 1);
catch
end
end

function plot_pair_partial_dependence(pdp_table, pdp_summary, pair_features, stem_path)
x_vals = unique(pdp_table.feature_x_value);
y_vals = unique(pdp_table.feature_y_value);
surface_vals = reshape(pdp_table.partial_dependence, numel(x_vals), numel(y_vals));
interaction_vals = reshape(pdp_table.interaction_residual, numel(x_vals), numel(y_vals));
pd_x = reshape(pdp_table.pd_feature_x, numel(x_vals), numel(y_vals));
pd_y = reshape(pdp_table.pd_feature_y, numel(x_vals), numel(y_vals));

fig = figure('Visible', 'off', 'Position', [120, 120, 1200, 900]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
plot(x_vals, pd_x(:, 1), 'LineWidth', 1.8, 'Color', [0.1, 0.45, 0.85]);
grid on;
xlabel(char(pair_features(1)));
ylabel('Partial dependence');
title(sprintf('1D PDP: %s', char(pair_features(1))));

nexttile;
plot(y_vals, pd_y(1, :), 'LineWidth', 1.8, 'Color', [0.1, 0.65, 0.3]);
grid on;
xlabel(char(pair_features(2)));
ylabel('Partial dependence');
title(sprintf('1D PDP: %s', char(pair_features(2))));

nexttile;
imagesc(y_vals, x_vals, surface_vals);
set(gca, 'YDir', 'normal');
colorbar;
xlabel(char(pair_features(2)));
ylabel(char(pair_features(1)));
title('2D RF partial dependence');

nexttile;
imagesc(y_vals, x_vals, interaction_vals);
set(gca, 'YDir', 'normal');
colorbar;
xlabel(char(pair_features(2)));
ylabel(char(pair_features(1)));
title(sprintf('Interaction residual (H=%.3f)', pdp_summary.rf_h_statistic));

save_plot(fig, stem_path);
end

function plot_fp_drop_ablation(ablation_table, stem_path)
valid_mask = ablation_table.status == "ok";
block = ablation_table(valid_mask, :);

fig = figure('Visible', 'off', 'Position', [120, 120, 1100, 500]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
bar(categorical(block.label_mode + " / " + block.scope), [block.delta_logistic_auc, block.delta_rf_auc], 'grouped');
hold on;
yline(0, 'k-');
yline(-0.01, 'r--', '-0.01');
yline(0.01, 'r--', '+0.01');
hold off;
grid on;
ylabel('AUC(6 features) - AUC(7 features)');
legend({'Logistic', 'RF'}, 'Location', 'southoutside', 'Orientation', 'horizontal');
title('AUC change after dropping fp\_idx\_diff\_rx12', 'Interpreter', 'tex');

nexttile;
scatter(block.fp_idx_single_auc, block.delta_logistic_auc, 90, [0.1, 0.45, 0.85], 'filled');
hold on;
scatter(block.fp_idx_single_auc, block.delta_rf_auc, 90, [0.9, 0.45, 0.1], 'filled');
for idx = 1:height(block)
    text(block.fp_idx_single_auc(idx) + 0.003, block.delta_rf_auc(idx), char(block.label_mode(idx) + "/" + block.scope(idx)), ...
        'FontSize', 8);
end
yline(0, 'k-');
grid on;
xlabel('fp\_idx\_diff\_rx12 single-feature effective AUC', 'Interpreter', 'tex');
ylabel('AUC change after drop');
legend({'Logistic', 'RF'}, 'Location', 'southoutside', 'Orientation', 'horizontal');
title('Does stronger standalone fp\_idx imply bigger drop?', 'Interpreter', 'tex');

save_plot(fig, stem_path);
end

function summary_md = build_followup2_summary(interaction_outputs, fp_ablation_table, diversity_table)
lines = {};
lines{end+1} = '# CP7 Follow-up 2';
lines{end+1} = '';
lines{end+1} = '## Interaction Check';
lines{end+1} = sprintf('- Pair: %s x %s', interaction_outputs.pdp_summary.feature_x, interaction_outputs.pdp_summary.feature_y);
lines{end+1} = sprintf('- RF H statistic: %.4f', interaction_outputs.pdp_summary.rf_h_statistic);
lines{end+1} = sprintf('- Interaction residual range: %.4f (PDP range %.4f)', ...
    interaction_outputs.pdp_summary.interaction_range, interaction_outputs.pdp_summary.pd_range);

pair_plus = interaction_outputs.logistic_compare(strcmp(cellstr(interaction_outputs.logistic_compare.model_name), 'pair_plus_interaction'), :);
pair_add = interaction_outputs.logistic_compare(strcmp(cellstr(interaction_outputs.logistic_compare.model_name), 'pair_additive'), :);
full_plus = interaction_outputs.logistic_compare(strcmp(cellstr(interaction_outputs.logistic_compare.model_name), 'full7_plus_interaction'), :);
full_add = interaction_outputs.logistic_compare(strcmp(cellstr(interaction_outputs.logistic_compare.model_name), 'full7_additive'), :);

lines{end+1} = sprintf('- Pair logistic: additive %.4f -> +interaction %.4f (delta %.4f)', ...
    pair_add.cv_auc, pair_plus.cv_auc, pair_plus.delta_auc_vs_additive);
lines{end+1} = sprintf('- Full-7 logistic: additive %.4f -> +interaction %.4f (delta %.4f, p=%.4g)', ...
    full_add.cv_auc, full_plus.cv_auc, full_plus.delta_auc_vs_additive, full_plus.interaction_pvalue);

lines{end+1} = '';
lines{end+1} = '## fp_idx_diff Drop Ablation';
for idx = 1:height(fp_ablation_table)
    row = fp_ablation_table(idx, :);
    lines{end+1} = sprintf('- %s / %s: logistic delta %.4f, RF delta %.4f, single AUC %.3f, L1 selected=%d, drop candidate=%d, note=%s', ...
        row.label_mode, row.scope, row.delta_logistic_auc, row.delta_rf_auc, row.fp_idx_single_auc, ...
        row.fp_idx_l1_selected, row.drop_candidate, row.decision_note);
end

lines{end+1} = '';
lines{end+1} = '## Two-RX gamma_CP Diversity';
for idx = 1:height(diversity_table)
    row = diversity_table(idx, :);
    lines{end+1} = sprintf('- %s: Pearson %.3f, Spearman %.3f, opposite-sign fraction %.2f (n=%d)', ...
        row.scope, row.pearson, row.spearman, row.opposite_sign_fraction, row.n_valid);
end

summary_md = strjoin(lines, newline);
end

function label_col = label_mode_to_column(label_mode)
if label_mode == "geometric_class"
    label_col = 'label_geometric';
elseif label_mode == "material_class"
    label_col = 'label_material';
else
    error('Unknown label mode: %s', label_mode);
end
end

function mask = scope_mask_from_name(scenarios, scope_name)
scenarios = string(scenarios);
if scope_name == "B"
    mask = scenarios == "B";
elseif scope_name == "C"
    mask = scenarios == "C";
elseif scope_name == "B+C"
    mask = scenarios == "B" | scenarios == "C";
else
    error('Unknown scope: %s', scope_name);
end
end

function scores = predict_positive_score(mdl, x)
[~, score_raw] = predict(mdl, x);
class_names = mdl.ClassNames;
positive_idx = find_positive_class_index(class_names);

if iscell(score_raw)
    score_matrix = nan(size(score_raw));
    for idx = 1:numel(score_raw)
        score_matrix(idx) = str2double(score_raw{idx});
    end
else
    score_matrix = score_raw;
end

if isvector(score_matrix)
    scores = double(score_matrix(:));
else
    scores = double(score_matrix(:, positive_idx));
end
end

function idx = find_positive_class_index(class_names)
if isnumeric(class_names)
    idx = find(class_names == 1, 1, 'first');
    if isempty(idx)
        idx = numel(class_names);
    end
    return;
end

if iscell(class_names)
    class_names = string(class_names);
else
    class_names = string(class_names(:));
end

idx = find(class_names == "1" | lower(class_names) == "true" | lower(class_names) == "los", 1, 'first');
if isempty(idx)
    idx = numel(class_names);
end
end

function folds = safe_cv_folds_local(labels, requested_folds)
minority_count = min(sum(labels == 1), sum(labels == 0));
folds = min(requested_folds, minority_count);
folds = max(0, floor(folds));
end

function z = zscore_safe(x)
mu = mean(x, 'omitnan');
sigma = std(x, 0, 'omitnan');
if sigma == 0 || ~isfinite(sigma)
    z = zeros(size(x));
else
    z = (x - mu) ./ sigma;
end
end

function value = local_get_param(params, field_name, default_value)
if isstruct(params) && isfield(params, field_name) && ~isempty(params.(field_name))
    value = params.(field_name);
else
    value = default_value;
end
end

function save_plot(fig, stem_path)
saveas(fig, [stem_path '.png']);
savefig(fig, [stem_path '.fig']);
close(fig);
end
