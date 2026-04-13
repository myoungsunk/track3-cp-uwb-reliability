function metrics = cp7_binary_feature_metrics(scores, labels, params)
% CP7_BINARY_FEATURE_METRICS Compute binary-label diagnostics for one feature.
if nargin < 3
    params = struct();
end

scores = double(scores(:));
labels = double(labels(:));
if numel(scores) ~= numel(labels)
    error('[cp7_binary_feature_metrics] scores and labels length must match.');
end

valid_mask = isfinite(scores) & isfinite(labels);
scores = scores(valid_mask);
labels = labels(valid_mask);

metrics = struct();
metrics.n = numel(scores);
metrics.n_los = sum(labels == 1);
metrics.n_nlos = sum(labels == 0);
metrics.point_biserial = NaN;
metrics.auc_raw = NaN;
metrics.auc_effective = NaN;
metrics.ks_stat = NaN;
metrics.mi_bits = NaN;
metrics.direction = "undefined";
metrics.status = "ok";

if isempty(scores)
    metrics.status = "empty";
    return;
end

if numel(unique(labels)) < 2
    metrics.status = "single_class";
    return;
end

metrics.point_biserial = corr(scores, labels, 'Type', 'Pearson', 'Rows', 'complete');

try
    [~, ~, ~, auc_raw] = perfcurve(logical(labels), scores, true);
    metrics.auc_raw = auc_raw;
    metrics.auc_effective = max(auc_raw, 1 - auc_raw);
    if auc_raw >= 0.5
        metrics.direction = "higher->LoS";
    else
        metrics.direction = "higher->NLoS";
    end
catch
    metrics.status = "auc_failed";
end

metrics.ks_stat = local_ks_stat(scores(labels == 1), scores(labels == 0));
metrics.mi_bits = local_mutual_information(scores, labels, get_param(params, 'mi_num_bins', 10));
end

function ks_stat = local_ks_stat(x_los, x_nlos)
x_los = sort(double(x_los(:)));
x_nlos = sort(double(x_nlos(:)));

if isempty(x_los) || isempty(x_nlos)
    ks_stat = NaN;
    return;
end

grid = unique([x_los; x_nlos]);
if isempty(grid)
    ks_stat = NaN;
    return;
end

cdf_los = arrayfun(@(v) mean(x_los <= v), grid);
cdf_nlos = arrayfun(@(v) mean(x_nlos <= v), grid);
ks_stat = max(abs(cdf_los - cdf_nlos));
end

function mi_bits = local_mutual_information(scores, labels, n_bin)
scores = double(scores(:));
labels = double(labels(:));

if numel(scores) < 2 || numel(unique(labels)) < 2
    mi_bits = NaN;
    return;
end

n_bin = max(2, round(double(n_bin)));
prob_grid = linspace(0, 1, n_bin + 1);
edges = quantile(scores, prob_grid);
edges = unique(edges);

if numel(edges) < 2
    mi_bits = 0;
    return;
end

edges(1) = -inf;
edges(end) = inf;
bin_idx = discretize(scores, edges);
valid_mask = ~isnan(bin_idx);
bin_idx = bin_idx(valid_mask);
labels = labels(valid_mask);

if isempty(bin_idx)
    mi_bits = NaN;
    return;
end

bin_values = unique(bin_idx);
label_values = unique(labels);

n_total = numel(bin_idx);
mi_bits = 0;
for idx_bin = 1:numel(bin_values)
    for idx_label = 1:numel(label_values)
        joint_count = sum(bin_idx == bin_values(idx_bin) & labels == label_values(idx_label));
        if joint_count == 0
            continue;
        end
        p_xy = joint_count / n_total;
        p_x = sum(bin_idx == bin_values(idx_bin)) / n_total;
        p_y = sum(labels == label_values(idx_label)) / n_total;
        mi_bits = mi_bits + p_xy * log2(p_xy / (p_x * p_y));
    end
end
end
