function outputs = run_cp7_interaction_check
% RUN_CP7_INTERACTION_CHECK Check whether gamma_CP_rx2 vs a_FP_RHCP_rx1 shows real interaction.
project_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(project_dir);
addpath(fullfile(repo_root, 'src'));

output_dir = fullfile(project_dir, '07_interaction');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

loaded = load(fullfile(project_dir, '01_sanity', 'cp7_analysis_table.mat'));
analysis_table = loaded.analysis_table;
params = loaded.params;

feature_names = string({ ...
    'gamma_CP_rx1', ...
    'gamma_CP_rx2', ...
    'a_FP_RHCP_rx1', ...
    'a_FP_LHCP_rx1', ...
    'a_FP_RHCP_rx2', ...
    'a_FP_LHCP_rx2', ...
    'fp_idx_diff_rx12'});

pair_features = ["gamma_CP_rx2", "a_FP_RHCP_rx1"];
pair_feature_display = ["gamma_CP_rx2", "a_FP_RHCP_rx1"];

scope_mask = analysis_table.scenario == "B" | analysis_table.scenario == "C";
label_values = double(analysis_table.label_material);
valid_mask = scope_mask & analysis_table.valid_flag & isfinite(label_values) & ...
    all(isfinite(analysis_table{:, cellstr(feature_names)}), 2);

scope_table = analysis_table(valid_mask, :);
x = scope_table{:, cellstr(feature_names)};
y = logical(label_values(valid_mask) == 1);

if numel(unique(y)) < 2
    error('[run_cp7_interaction_check] material/B+C must contain both classes.');
end

rng(local_get_param(params, 'random_seed', 42));
num_trees = local_get_param(params, 'rf_num_trees', 60);
min_leaf = local_get_param(params, 'rf_min_leaf_size', 2);
mdl = TreeBagger(num_trees, x, double(y), ...
    'Method', 'classification', ...
    'MinLeafSize', min_leaf, ...
    'OOBPrediction', 'on', ...
    'OOBPredictorImportance', 'on');

rf_importance = table(feature_names(:), mdl.OOBPermutedPredictorDeltaError(:), ...
    'VariableNames', {'predictor_name', 'permuted_delta_error'});
writetable(rf_importance, fullfile(output_dir, 'rf_importance_refit_material_bc.csv'));

idx_gamma2 = find(feature_names == pair_features(1), 1, 'first');
idx_afpr1 = find(feature_names == pair_features(2), 1, 'first');

[pdp_table, pdp_summary] = compute_pair_partial_dependence(mdl, x, idx_gamma2, idx_afpr1, pair_features);
writetable(pdp_table, fullfile(output_dir, 'pdp_material_bc_gamma2_afpr1.csv'));
writetable(struct2table(pdp_summary), fullfile(output_dir, 'interaction_summary_material_bc_gamma2_afpr1.csv'));

plot_pair_partial_dependence(pdp_table, pdp_summary, pair_feature_display, ...
    fullfile(output_dir, 'pdp_material_bc_gamma2_afpr1'));

logistic_summary = compare_logistic_models(x, y, idx_gamma2, idx_afpr1, params, feature_names);
writetable(logistic_summary, fullfile(output_dir, 'logistic_interaction_compare_material_bc.csv'));

summary_markdown = build_interaction_summary_markdown(pair_feature_display, pdp_summary, logistic_summary, rf_importance);
summary_path = fullfile(output_dir, 'interaction_summary_material_bc.md');
fid = fopen(summary_path, 'w');
if fid < 0
    error('[run_cp7_interaction_check] Failed to write summary markdown: %s', summary_path);
end
cleanup_obj = onCleanup(@() fclose(fid));
fprintf(fid, '%s', summary_markdown);
clear cleanup_obj;

outputs = struct();
outputs.output_dir = output_dir;
outputs.rf_importance = rf_importance;
outputs.pdp_table = pdp_table;
outputs.pdp_summary = pdp_summary;
outputs.logistic_summary = logistic_summary;
end

function [pdp_table, summary] = compute_pair_partial_dependence(mdl, x, idx_gamma2, idx_afpr1, pair_features)
gamma_values = x(:, idx_gamma2);
afpr1_values = x(:, idx_afpr1);

grid_gamma = linspace(prctile(gamma_values, 5), prctile(gamma_values, 95), 25);
grid_afpr1 = linspace(prctile(afpr1_values, 5), prctile(afpr1_values, 95), 25);

pdp_gamma = nan(numel(grid_gamma), 1);
pdp_afpr1 = nan(numel(grid_afpr1), 1);
pdp_surface = nan(numel(grid_gamma), numel(grid_afpr1));

for idx_g = 1:numel(grid_gamma)
    x_tmp = x;
    x_tmp(:, idx_gamma2) = grid_gamma(idx_g);
    pdp_gamma(idx_g) = mean(predict_positive_score(mdl, x_tmp), 'omitnan');
end

for idx_a = 1:numel(grid_afpr1)
    x_tmp = x;
    x_tmp(:, idx_afpr1) = grid_afpr1(idx_a);
    pdp_afpr1(idx_a) = mean(predict_positive_score(mdl, x_tmp), 'omitnan');
end

for idx_g = 1:numel(grid_gamma)
    for idx_a = 1:numel(grid_afpr1)
        x_tmp = x;
        x_tmp(:, idx_gamma2) = grid_gamma(idx_g);
        x_tmp(:, idx_afpr1) = grid_afpr1(idx_a);
        pdp_surface(idx_g, idx_a) = mean(predict_positive_score(mdl, x_tmp), 'omitnan');
    end
end

surface_mean = mean(pdp_surface(:), 'omitnan');
interaction_surface = pdp_surface - pdp_gamma - pdp_afpr1' + surface_mean;
surface_centered = pdp_surface - surface_mean;

numerator = mean(interaction_surface(:).^2, 'omitnan');
denominator = mean(surface_centered(:).^2, 'omitnan');
if denominator <= 0
    h_stat = NaN;
else
    h_stat = sqrt(numerator / denominator);
end

[peak_value, peak_linear_idx] = max(interaction_surface(:));
[trough_value, trough_linear_idx] = min(interaction_surface(:));
[peak_gamma_idx, peak_afpr1_idx] = ind2sub(size(interaction_surface), peak_linear_idx);
[trough_gamma_idx, trough_afpr1_idx] = ind2sub(size(interaction_surface), trough_linear_idx);

[xgamma_grid, xafpr1_grid] = ndgrid(grid_gamma, grid_afpr1);
pdp_table = table( ...
    repmat(string(pair_features(1)), numel(xgamma_grid), 1), ...
    repmat(string(pair_features(2)), numel(xgamma_grid), 1), ...
    xgamma_grid(:), xafpr1_grid(:), pdp_surface(:), ...
    repelem(pdp_gamma, numel(grid_afpr1)), repmat(pdp_afpr1(:), numel(grid_gamma), 1), ...
    interaction_surface(:), ...
    'VariableNames', {'feature_x', 'feature_y', 'gamma_cp_rx2', 'a_fp_rhcp_rx1', ...
    'partial_dependence', 'pd_gamma_cp_rx2', 'pd_a_fp_rhcp_rx1', 'interaction_residual'});

summary = struct();
summary.feature_x = string(pair_features(1));
summary.feature_y = string(pair_features(2));
summary.grid_n_gamma = numel(grid_gamma);
summary.grid_n_afpr1 = numel(grid_afpr1);
summary.rf_h_statistic = h_stat;
summary.interaction_rms = sqrt(numerator);
summary.interaction_peak = peak_value;
summary.interaction_peak_gamma_cp_rx2 = grid_gamma(peak_gamma_idx);
summary.interaction_peak_a_fp_rhcp_rx1 = grid_afpr1(peak_afpr1_idx);
summary.interaction_trough = trough_value;
summary.interaction_trough_gamma_cp_rx2 = grid_gamma(trough_gamma_idx);
summary.interaction_trough_a_fp_rhcp_rx1 = grid_afpr1(trough_afpr1_idx);
summary.pd_range = max(pdp_surface(:)) - min(pdp_surface(:));
summary.interaction_range = peak_value - trough_value;
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
    class_names_str = string(class_names);
else
    class_names_str = string(class_names(:));
end

idx = find(class_names_str == "1" | lower(class_names_str) == "true" | lower(class_names_str) == "los", 1, 'first');
if isempty(idx)
    idx = numel(class_names_str);
end
end

function logistic_summary = compare_logistic_models(x, y, idx_gamma2, idx_afpr1, params, feature_names)
pair_x = x(:, [idx_gamma2, idx_afpr1]);
pair_x_int = [pair_x, pair_x(:, 1) .* pair_x(:, 2)];
full_x = x;
full_x_int = [x, x(:, idx_gamma2) .* x(:, idx_afpr1)];

params_local = struct();
params_local.normalize = true;
params_local.cv_folds = local_get_param(params, 'cv_folds', 5);
params_local.random_seed = local_get_param(params, 'random_seed', 42);
params_local.save_outputs = false;
params_local.log10_rcp = false;
params_local.logistic_backend = 'auto';
params_local.logistic_ridge_lambda = local_get_param(params, 'logistic_ridge_lambda', 0.01);

[model_pair_add, ~] = train_logistic(pair_x, y, params_local);
[model_pair_int, ~] = train_logistic(pair_x_int, y, params_local);
[model_full_add, ~] = train_logistic(full_x, y, params_local);
[model_full_int, ~] = train_logistic(full_x_int, y, params_local);

[pair_int_coef, pair_int_pval] = fit_interaction_glm(pair_x, y, 3);
[full_int_coef, full_int_pval] = fit_interaction_glm(full_x_int, y, size(full_x_int, 2));

model_name = string({ ...
    'pair_additive'; ...
    'pair_plus_interaction'; ...
    'full7_additive'; ...
    'full7_plus_interaction'});

cv_auc = [model_pair_add.cv_auc; model_pair_int.cv_auc; model_full_add.cv_auc; model_full_int.cv_auc];
cv_accuracy = [model_pair_add.cv_accuracy; model_pair_int.cv_accuracy; model_full_add.cv_accuracy; model_full_int.cv_accuracy];
interaction_feature = ["none"; "gamma_CP_rx2*a_FP_RHCP_rx1"; "none"; "gamma_CP_rx2*a_FP_RHCP_rx1"];
interaction_coef = [NaN; pair_int_coef; NaN; full_int_coef];
interaction_pvalue = [NaN; pair_int_pval; NaN; full_int_pval];

logistic_summary = table(model_name, cv_auc, cv_accuracy, interaction_feature, interaction_coef, interaction_pvalue);
logistic_summary.delta_auc_vs_additive = [0; model_pair_int.cv_auc - model_pair_add.cv_auc; 0; model_full_int.cv_auc - model_full_add.cv_auc];
logistic_summary.delta_accuracy_vs_additive = [0; model_pair_int.cv_accuracy - model_pair_add.cv_accuracy; 0; model_full_int.cv_accuracy - model_full_add.cv_accuracy];
logistic_summary.feature_set = [ ...
    "gamma_CP_rx2 + a_FP_RHCP_rx1"; ...
    "gamma_CP_rx2 + a_FP_RHCP_rx1 + interaction"; ...
    strjoin(feature_names, " + "); ...
    strjoin(feature_names, " + ") + " + interaction"];
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

function plot_pair_partial_dependence(pdp_table, pdp_summary, pair_feature_display, stem_path)
gamma_vals = unique(pdp_table.gamma_cp_rx2);
afpr1_vals = unique(pdp_table.a_fp_rhcp_rx1);

pdp_surface = reshape(pdp_table.partial_dependence, numel(gamma_vals), numel(afpr1_vals));
interaction_surface = reshape(pdp_table.interaction_residual, numel(gamma_vals), numel(afpr1_vals));
pd_gamma = reshape(pdp_table.pd_gamma_cp_rx2, numel(gamma_vals), numel(afpr1_vals));
pd_afpr1 = reshape(pdp_table.pd_a_fp_rhcp_rx1, numel(gamma_vals), numel(afpr1_vals));
pd_gamma_line = pd_gamma(:, 1);
pd_afpr1_line = pd_afpr1(1, :).';

fig = figure('Visible', 'off', 'Position', [100, 100, 1200, 900]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
plot(gamma_vals, pd_gamma_line, 'LineWidth', 1.8, 'Color', [0.15, 0.45, 0.85]);
grid on;
xlabel(char(pair_feature_display(1)));
ylabel('Partial dependence');
title(sprintf('1D PDP: %s', char(pair_feature_display(1))));

nexttile;
plot(afpr1_vals, pd_afpr1_line, 'LineWidth', 1.8, 'Color', [0.1, 0.6, 0.3]);
grid on;
xlabel(char(pair_feature_display(2)));
ylabel('Partial dependence');
title(sprintf('1D PDP: %s', char(pair_feature_display(2))));

nexttile;
imagesc(afpr1_vals, gamma_vals, pdp_surface);
set(gca, 'YDir', 'normal');
colorbar;
xlabel(char(pair_feature_display(2)));
ylabel(char(pair_feature_display(1)));
title('2D RF partial dependence');

nexttile;
imagesc(afpr1_vals, gamma_vals, interaction_surface);
set(gca, 'YDir', 'normal');
colorbar;
xlabel(char(pair_feature_display(2)));
ylabel(char(pair_feature_display(1)));
title(sprintf('Interaction residual (H=%.3f)', pdp_summary.rf_h_statistic));

saveas(fig, [stem_path '.png']);
savefig(fig, [stem_path '.fig']);
close(fig);
end

function summary_markdown = build_interaction_summary_markdown(pair_feature_display, pdp_summary, logistic_summary, rf_importance)
lines = {};
lines{end+1} = '# Material B+C Interaction Check';
lines{end+1} = '';
lines{end+1} = sprintf('- Pair checked: `%s` x `%s`', char(pair_feature_display(1)), char(pair_feature_display(2)));
lines{end+1} = sprintf('- RF Friedman-style H statistic: %.4f', pdp_summary.rf_h_statistic);
lines{end+1} = sprintf('- PDP range: %.4f', pdp_summary.pd_range);
lines{end+1} = sprintf('- Interaction residual RMS: %.4f', pdp_summary.interaction_rms);
lines{end+1} = sprintf('- Interaction residual range: %.4f', pdp_summary.interaction_range);
lines{end+1} = sprintf('- Peak interaction residual: %.4f at gamma_CP_rx2=%.4f, a_FP_RHCP_rx1=%.4f', ...
    pdp_summary.interaction_peak, pdp_summary.interaction_peak_gamma_cp_rx2, pdp_summary.interaction_peak_a_fp_rhcp_rx1);
lines{end+1} = sprintf('- Trough interaction residual: %.4f at gamma_CP_rx2=%.4f, a_FP_RHCP_rx1=%.4f', ...
    pdp_summary.interaction_trough, pdp_summary.interaction_trough_gamma_cp_rx2, pdp_summary.interaction_trough_a_fp_rhcp_rx1);
lines{end+1} = '';
lines{end+1} = '## Logistic comparison';

for idx = 1:height(logistic_summary)
    row = logistic_summary(idx, :);
    lines{end+1} = sprintf('- %s: CV AUC %.4f, CV Acc %.4f, delta AUC %.4f, interaction coef %.4f, p=%.4g', ...
        row.model_name, row.cv_auc, row.cv_accuracy, row.delta_auc_vs_additive, row.interaction_coef, row.interaction_pvalue);
end

lines{end+1} = '';
lines{end+1} = '## RF importance reference';
rf_sorted = sortrows(rf_importance, 'permuted_delta_error', 'descend');
for idx = 1:height(rf_sorted)
    row = rf_sorted(idx, :);
    lines{end+1} = sprintf('- %s: %.4f', row.predictor_name, row.permuted_delta_error);
end

summary_markdown = strjoin(lines, newline);
end

function value = local_get_param(params, field_name, default_value)
if isstruct(params) && isfield(params, field_name) && ~isempty(params.(field_name))
    value = params.(field_name);
else
    value = default_value;
end
end
