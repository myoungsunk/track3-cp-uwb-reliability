function generate_figures(feature_table, model, results, benchmark, ablation, params)
% GENERATE_FIGURES Generate publication-ready figures for phase-2 evaluation outputs.
if nargin < 6
    params = struct();
end

figure_dir = char(get_param(params, 'figures_dir', fullfile(pwd, 'results', 'figures')));
if ~exist(figure_dir, 'dir')
    mkdir(figure_dir);
end

font_name = char(get_param(params, 'figure_font_name', 'Times New Roman'));
font_size_axis = get_param(params, 'figure_font_size_axis', 10);
font_size_legend = get_param(params, 'figure_font_size_legend', 9);
figure_pos = get_param(params, 'figure_position_cm', [0, 0, 8.5, 7]);
resolution_dpi = get_param(params, 'figure_resolution_dpi', 300);

plot_figure_1(feature_table, model, params, figure_dir, font_name, font_size_axis, font_size_legend, figure_pos, resolution_dpi);
plot_figure_2(results, benchmark, figure_dir, font_name, font_size_axis, font_size_legend, figure_pos, resolution_dpi);
plot_figure_3(benchmark, figure_dir, font_name, font_size_axis, font_size_legend, figure_pos, resolution_dpi);
plot_figure_4(results, figure_dir, font_name, font_size_axis, font_size_legend, figure_pos, resolution_dpi);

save(fullfile(figure_dir, 'figure_inputs_snapshot.mat'), 'feature_table', 'model', 'results', 'benchmark', 'ablation', 'params');
end

function plot_figure_1(feature_table, model, params, figure_dir, font_name, font_size_axis, font_size_legend, figure_pos, resolution_dpi)
if isempty(feature_table) || ~istable(feature_table)
    return;
end
if ~ismember('r_CP', feature_table.Properties.VariableNames) || ~ismember('a_FP', feature_table.Properties.VariableNames)
    return;
end

r_cp = double(feature_table.r_CP(:));
a_fp = double(feature_table.a_FP(:));
labels = logical(feature_table.label(:));

valid_mask = isfinite(r_cp) & isfinite(a_fp) & (r_cp > 0);
r_cp = r_cp(valid_mask);
a_fp = a_fp(valid_mask);
labels = labels(valid_mask);

x_log = log10(r_cp);
y_val = a_fp;

fig = figure('Units', 'centimeters', 'Position', figure_pos);
ax = axes(fig);
hold(ax, 'on');

plot(ax, x_log(labels), y_val(labels), 'bo', 'MarkerSize', 4, 'LineWidth', 0.8);
plot(ax, x_log(~labels), y_val(~labels), 'r^', 'MarkerSize', 4, 'LineWidth', 0.8);

if isfield(model, 'coefficients') && numel(model.coefficients) >= 3
    draw_decision_boundary(ax, model, params, x_log, y_val);
end

grid(ax, 'on');
xlabel(ax, 'log_{10}(r_{CP})');
ylabel(ax, 'a_{FP}');
set(ax, 'FontName', font_name, 'FontSize', font_size_axis);
legend(ax, {'LoS', 'NLoS', 'P=0.5 boundary'}, 'FontName', font_name, 'FontSize', font_size_legend, 'Location', 'best');

save_figure_multi(fig, figure_dir, 'fig1_scatter_2d', resolution_dpi);
close(fig);
end

function draw_decision_boundary(ax, model, params, x_log, y_val)
if ~isfield(model, 'coefficients')
    return;
end
b = model.coefficients(:);
if numel(b) < 3
    return;
end

if isfield(model, 'predictor_names')
    predictor_names = model.predictor_names;
else
    predictor_names = {'rcp_norm', 'afp_norm'};
end

if strcmp(predictor_names{1}, 'rcp_norm')
    x_axis = linspace(min(x_log), max(x_log), 200);

    if isfield(model, 'norm_mean_values') && isfield(model, 'norm_std_values') && numel(model.norm_mean_values) >= 2
        mu = model.norm_mean_values;
        sigma = model.norm_std_values;
    else
        mu = [0, 0];
        sigma = [1, 1];
    end

    z_x = (x_axis - mu(1)) / sigma(1);
    if abs(b(3)) > eps
        z_y = -(b(1) + b(2) * z_x) / b(3);
        y_axis = z_y * sigma(2) + mu(2);
        plot(ax, x_axis, y_axis, 'k-', 'LineWidth', 1.0);
    end
end
end

function plot_figure_2(results, benchmark, figure_dir, font_name, font_size_axis, font_size_legend, figure_pos, resolution_dpi)
fig = figure('Units', 'centimeters', 'Position', figure_pos);
ax = axes(fig);
hold(ax, 'on');

plot(ax, [0, 1], [0, 1], '-', 'Color', [0.6, 0.6, 0.6], 'LineWidth', 0.8);

legend_text = {};

if isfield(results, 'roc') && isfield(results.roc, 'fpr') && isfield(results.roc, 'tpr')
    auc_log = results.roc.auc;
    plot(ax, results.roc.fpr, results.roc.tpr, 'b-', 'LineWidth', 1.2);
    legend_text{end + 1} = sprintf('Logistic (AUC=%.3f)', auc_log); %#ok<AGROW>
end

roc_curves = [];
if istable(benchmark) && ~isempty(benchmark.Properties.UserData) && isfield(benchmark.Properties.UserData, 'roc_curves')
    roc_curves = benchmark.Properties.UserData.roc_curves;
end

style_map = struct( ...
    'SVM', 'r--', ...
    'RandomForest', 'g:', ...
    'DNN', 'm-.', ...
    'LDA', 'c-', ...
    'QDA', 'c--', ...
    'LinearSVM', 'y-', ...
    'TinyTree', 'y--', ...
    'LogisticQuad', 'k-.');
for idx = 1:numel(roc_curves)
    name = string(roc_curves(idx).model_name);
    if name == "Logistic"
        continue;
    end
    if any(~isfinite(roc_curves(idx).fpr)) || any(~isfinite(roc_curves(idx).tpr))
        continue;
    end
    if isfield(style_map, char(name))
        style = style_map.(char(name));
    else
        style = 'k--';
    end
    plot(ax, roc_curves(idx).fpr, roc_curves(idx).tpr, style, 'LineWidth', 1.2);
    legend_text{end + 1} = sprintf('%s (AUC=%.3f)', char(name), roc_curves(idx).auc); %#ok<AGROW>
end

grid(ax, 'on');
xlabel(ax, 'False Positive Rate');
ylabel(ax, 'True Positive Rate');
set(ax, 'FontName', font_name, 'FontSize', font_size_axis);
if ~isempty(legend_text)
    legend(ax, legend_text, 'Location', 'southeast', 'FontName', font_name, 'FontSize', font_size_legend);
end

save_figure_multi(fig, figure_dir, 'fig2_roc_comparison', resolution_dpi);
close(fig);
end

function plot_figure_3(benchmark, figure_dir, font_name, font_size_axis, font_size_legend, figure_pos, resolution_dpi)
if ~istable(benchmark) || isempty(benchmark)
    return;
end

fig = figure('Units', 'centimeters', 'Position', figure_pos);
ax = axes(fig);
hold(ax, 'on');

x_flops = double(benchmark.flops);
y_auc = double(benchmark.auc);
valid_mask = isfinite(x_flops) & isfinite(y_auc) & x_flops > 0;
x_flops = x_flops(valid_mask);
y_auc = y_auc(valid_mask);
names = string(benchmark.model_name(valid_mask));

scatter(ax, x_flops, y_auc, 30, 'filled');

for idx = 1:numel(names)
    text(ax, x_flops(idx), y_auc(idx), ...
        sprintf(' %s (%.3f)', char(names(idx)), y_auc(idx)), ...
        'FontName', font_name, 'FontSize', font_size_legend);
end

set(ax, 'XScale', 'log');
grid(ax, 'on');
xlabel(ax, 'FLOPs (log scale)');
ylabel(ax, 'AUC');
ylim(ax, [0, 1]);
set(ax, 'FontName', font_name, 'FontSize', font_size_axis);

save_figure_multi(fig, figure_dir, 'fig3_auc_vs_flops', resolution_dpi);
% Keep legacy filename for downstream scripts that still reference old name.
save_figure_multi(fig, figure_dir, 'fig3_accuracy_vs_flops', resolution_dpi);
close(fig);
end

function plot_figure_4(results, figure_dir, font_name, font_size_axis, font_size_legend, figure_pos, resolution_dpi)
if ~isfield(results, 'cal_curve')
    return;
end

cal_curve = results.cal_curve;
if ~isfield(cal_curve, 'mean_predicted') || ~isfield(cal_curve, 'fraction_positive')
    return;
end

x_val = cal_curve.mean_predicted(:);
y_val = cal_curve.fraction_positive(:);
valid_mask = isfinite(x_val) & isfinite(y_val);

fig = figure('Units', 'centimeters', 'Position', figure_pos);
ax = axes(fig);
hold(ax, 'on');

plot(ax, [0, 1], [0, 1], '-', 'Color', [0.6, 0.6, 0.6], 'LineWidth', 0.8);
plot(ax, x_val(valid_mask), y_val(valid_mask), 'bo-', 'LineWidth', 1.0, 'MarkerSize', 4);

grid(ax, 'on');
xlabel(ax, 'Mean Predicted Probability');
ylabel(ax, 'Fraction of Positives');
set(ax, 'FontName', font_name, 'FontSize', font_size_axis);
legend(ax, {'Perfect calibration', 'Model'}, 'Location', 'northwest', 'FontName', font_name, 'FontSize', font_size_legend);

if isfield(results, 'ece') && isfinite(results.ece)
    text(ax, 0.04, 0.95, sprintf('ECE = %.3f', results.ece), ...
        'Units', 'normalized', 'VerticalAlignment', 'top', ...
        'FontName', font_name, 'FontSize', font_size_legend);
end

save_figure_multi(fig, figure_dir, 'fig4_calibration', resolution_dpi);
close(fig);
end

function save_figure_multi(fig, figure_dir, base_name, resolution_dpi)
pdf_path = fullfile(figure_dir, [base_name '.pdf']);
png_path = fullfile(figure_dir, [base_name '.png']);
fig_path = fullfile(figure_dir, [base_name '.fig']);

exportgraphics(fig, pdf_path, 'Resolution', resolution_dpi);
exportgraphics(fig, png_path, 'Resolution', resolution_dpi);
savefig(fig, fig_path);
end
