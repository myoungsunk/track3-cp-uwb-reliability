function outputs = run_cp6_final_package
% RUN_CP6_FINAL_PACKAGE Build final 3-figure draft package for locked 6-feature pipeline.
project_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(project_dir);
addpath(fullfile(repo_root, 'src'));

output_dir = fullfile(project_dir, '09_final_lock');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

loaded = load(fullfile(project_dir, '01_sanity', 'cp7_analysis_table.mat'));
analysis_table = loaded.analysis_table;

feature_names = [ ...
    "gamma_CP_rx1", ...
    "gamma_CP_rx2", ...
    "a_FP_RHCP_rx1", ...
    "a_FP_LHCP_rx1", ...
    "a_FP_RHCP_rx2", ...
    "a_FP_LHCP_rx2"];

winner_table = readtable(fullfile(project_dir, '04_local', 'winner_map_geometric_bc.csv'));
winner_table.best_feature = string(winner_table.best_feature);

fig_a_path = fullfile(output_dir, 'figA_winner_map_geometric_bc');
plot_winner_map_draft(winner_table, fig_a_path);

[diversity_table, fig_b_path] = build_two_rx_diversity_figure(analysis_table, output_dir);
[violin_summary, fig_c_path] = build_class_conditional_violin(analysis_table, feature_names, output_dir);

caption_md = build_caption_markdown(diversity_table, violin_summary, fig_a_path, fig_b_path, fig_c_path);
caption_path = fullfile(output_dir, 'final_methods_and_captions.md');
fid = fopen(caption_path, 'w');
if fid < 0
    error('[run_cp6_final_package] Failed to write markdown: %s', caption_path);
end
cleanup_obj = onCleanup(@() fclose(fid));
fprintf(fid, '%s', caption_md);
clear cleanup_obj;

outputs = struct();
outputs.output_dir = output_dir;
outputs.fig_a = string([fig_a_path '.png']);
outputs.fig_b = string(fig_b_path);
outputs.fig_c = string(fig_c_path);
outputs.diversity = diversity_table;
outputs.violin_summary = violin_summary;
outputs.caption_path = string(caption_path);
end

function plot_winner_map_draft(winner_table, stem_path)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [120, 120, 900, 650]);
ax = axes(fig);
hold(ax, 'on');

valid_mask = winner_table.best_feature ~= "" & isfinite(winner_table.best_auc_effective);
features = unique(winner_table.best_feature(valid_mask), 'stable');
if isempty(features)
    text(ax, 0.5, 0.5, 'No valid winner map', 'HorizontalAlignment', 'center');
    axis(ax, 'off');
    save_plot(fig, stem_path);
    return;
end

colors = lines(max(numel(features), 1));
for idx = 1:numel(features)
    mask = valid_mask & winner_table.best_feature == features(idx);
    scatter(ax, winner_table.x_m(mask), winner_table.y_m(mask), 110, colors(idx, :), 'filled', ...
        'DisplayName', char(features(idx)));
end

unstable_mask = valid_mask & winner_table.unstable_flag;
if any(unstable_mask)
    scatter(ax, winner_table.x_m(unstable_mask), winner_table.y_m(unstable_mask), 150, 'k', 'x', ...
        'LineWidth', 1.4, 'DisplayName', 'unstable');
end

grid(ax, 'on');
axis(ax, 'equal');
xlabel(ax, 'x [m]');
ylabel(ax, 'y [m]');
title(ax, 'Winner map (geometric B+C) | RHCP transmission, dual-CP reception');
legend(ax, 'Location', 'bestoutside');
text(ax, 0.02, 0.02, 'Caveat: combined B+C scope is noisier than single-scenario maps.', ...
    'Units', 'normalized', 'FontSize', 9, 'Color', [0.25, 0.25, 0.25], ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
    'BackgroundColor', [1.0, 1.0, 1.0]);

save_plot(fig, stem_path);
end

function [rows, figure_path] = build_two_rx_diversity_figure(analysis_table, output_dir)
scopes = ["B", "C", "B+C"];
rows = table();

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1500, 460]);
tiledlayout(1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

for idx_scope = 1:numel(scopes)
    scope_name = scopes(idx_scope);
    scope_mask = scope_mask_from_name(analysis_table.scenario, scope_name) & ...
        analysis_table.valid_flag & ...
        isfinite(analysis_table.gamma_CP_rx1) & ...
        isfinite(analysis_table.gamma_CP_rx2) & ...
        isfinite(double(analysis_table.label_geometric));
    block = analysis_table(scope_mask, :);

    x = zscore_safe(double(block.gamma_CP_rx1));
    y = zscore_safe(double(block.gamma_CP_rx2));
    label = logical(block.label_geometric == 1);

    pearson_value = corr(x, y, 'Type', 'Pearson', 'Rows', 'complete');
    spearman_value = corr(x, y, 'Type', 'Spearman', 'Rows', 'complete');
    opposite_fraction = mean(sign(x) ~= sign(y), 'omitnan');

    rows = [rows; table(scope_name, height(block), pearson_value, spearman_value, opposite_fraction, ...
        'VariableNames', {'scope', 'n_valid', 'pearson', 'spearman', 'opposite_sign_fraction'})]; %#ok<AGROW>

    nexttile;
    hold on;
    if any(label)
        scatter(x(label), y(label), 38, [0.1, 0.45, 0.85], 'filled', 'DisplayName', 'LoS');
    end
    if any(~label)
        scatter(x(~label), y(~label), 38, [0.9, 0.45, 0.1], 'filled', 'DisplayName', 'NLoS');
    end
    xline(0, 'k:');
    yline(0, 'k:');
    if numel(x) >= 2 && numel(y) >= 2
        coeff = polyfit(x, y, 1);
        xx = linspace(min(x), max(x), 100);
        yy = polyval(coeff, xx);
        plot(xx, yy, 'k-', 'LineWidth', 1.1);
    end
    hold off;
    axis square;
    grid on;
    xlabel('z(gamma\_CP\_rx1)', 'Interpreter', 'tex');
    ylabel('z(gamma\_CP\_rx2)', 'Interpreter', 'tex');
    title(sprintf('%s | r=%.3f | \\rho=%.3f | opp=%.2f', char(scope_name), pearson_value, spearman_value, opposite_fraction), ...
        'Interpreter', 'tex');
    legend('Location', 'southoutside', 'Orientation', 'horizontal');
end

annotation(fig, 'textbox', [0.16, 0.92, 0.7, 0.06], ...
    'String', 'Two-RX diversity (RHCP transmission, dual-CP reception)', ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontSize', 12, 'FontWeight', 'bold');

stem_path = fullfile(output_dir, 'figB_two_rx_diversity');
save_plot(fig, stem_path);
writetable(rows, fullfile(output_dir, 'figB_two_rx_diversity_summary.csv'));
figure_path = string([stem_path '.png']);
end

function [summary_table, figure_path] = build_class_conditional_violin(analysis_table, feature_names, output_dir)
mask = (analysis_table.scenario == "B" | analysis_table.scenario == "C") & ...
    analysis_table.valid_flag & ...
    isfinite(double(analysis_table.label_geometric)) & ...
    all(isfinite(analysis_table{:, cellstr(feature_names)}), 2);

block = analysis_table(mask, :);
labels = double(block.label_geometric);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [90, 90, 1500, 850]);
layout = tiledlayout(fig, 2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
title(layout, 'Class-conditional violin (7->6 feature lock) | RHCP transmission, dual-CP reception');

summary_rows = table();
for idx = 1:numel(feature_names)
    feat = feature_names(idx);
    values = double(block.(feat));
    los_vals = values(labels == 1);
    nlos_vals = values(labels == 0);

    ax = nexttile(layout, idx);
    draw_mirrored_violin(ax, los_vals, nlos_vals);
    title(ax, strrep(char(feat), '_', '\_'));
    ylabel(ax, 'Feature value');
    grid(ax, 'on');
    box(ax, 'on');

    med_los = median(los_vals, 'omitnan');
    med_nlos = median(nlos_vals, 'omitnan');
    summary_rows = [summary_rows; table(feat, numel(los_vals), numel(nlos_vals), med_los, med_nlos, med_los - med_nlos, ...
        'VariableNames', {'feature_name', 'n_los', 'n_nlos', 'median_los', 'median_nlos', 'median_gap_los_minus_nlos'})]; %#ok<AGROW>
end

stem_path = fullfile(output_dir, 'figC_class_conditional_violin_7to6');
save_plot(fig, stem_path);
writetable(summary_rows, fullfile(output_dir, 'figC_class_conditional_violin_summary.csv'));
summary_table = summary_rows;
figure_path = string([stem_path '.png']);
end

function markdown_text = build_caption_markdown(diversity_table, violin_summary, fig_a_stem, fig_b_path, fig_c_path)
line = {};
line{end+1} = '# Final Figure Drafts (CP6 Lock)';
line{end+1} = '';
line{end+1} = '## Methods (fixed wording)';
line{end+1} = '- RHCP transmission, dual-CP reception.';
line{end+1} = '- Final model feature set is locked to 6 CP features: gamma_CP_rx1, gamma_CP_rx2, a_FP_RHCP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2.';
line{end+1} = '- fp_idx_diff_rx12 is removed from the final model feature set.';
line{end+1} = '';
line{end+1} = '## Figure Captions';
line{end+1} = sprintf('- (a) Winner map (geometric, B+C): local winning feature across space under RHCP transmission, dual-CP reception. Caveat: the combined B+C scope is noisier than single-scenario maps B or C. (`%s.png`)', fig_a_stem);
line{end+1} = sprintf('- (b) Two-RX diversity: z(gamma_CP_rx1) vs z(gamma_CP_rx2) for B, C, and B+C under RHCP transmission, dual-CP reception, showing complementary behavior by scope. (`%s`)', fig_b_path);
line{end+1} = sprintf('- (c) Class-conditional violin (7->6 feature lock): LoS/NLoS distributions for the retained 6 features under RHCP transmission, dual-CP reception. (`%s`)', fig_c_path);
line{end+1} = '';
line{end+1} = '## Numeric Notes';
for idx = 1:height(diversity_table)
    row = diversity_table(idx, :);
    line{end+1} = sprintf('- Diversity %s: Pearson %.3f, Spearman %.3f, opposite-sign fraction %.2f (n=%d)', ...
        char(row.scope), row.pearson, row.spearman, row.opposite_sign_fraction, row.n_valid);
end
line{end+1} = '- Violin median gaps (LoS - NLoS):';
for idx = 1:height(violin_summary)
    row = violin_summary(idx, :);
    line{end+1} = sprintf('  %s: %.4f', char(row.feature_name), row.median_gap_los_minus_nlos);
end

markdown_text = strjoin(line, newline);
end

function draw_mirrored_violin(ax, values_los, values_nlos)
hold(ax, 'on');
draw_half_violin(ax, values_los, -1, [0.10, 0.45, 0.75]);
draw_half_violin(ax, values_nlos, 1, [0.80, 0.25, 0.25]);
xlim(ax, [-1.5, 1.5]);
xticks(ax, [-1, 1]);
xticklabels(ax, {'LoS', 'NLoS'});
hold(ax, 'off');
end

function draw_half_violin(ax, values, side, color_value)
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

function mask = scope_mask_from_name(scenario, scope_name)
scenario = string(scenario);
scope_name = string(scope_name);
if scope_name == "B"
    mask = scenario == "B";
elseif scope_name == "C"
    mask = scenario == "C";
elseif scope_name == "B+C"
    mask = scenario == "B" | scenario == "C";
else
    error('Unknown scope: %s', scope_name);
end
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

function save_plot(fig, stem_path)
saveas(fig, [stem_path '.png']);
savefig(fig, [stem_path '.fig']);
close(fig);
end
