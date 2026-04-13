function local_table = cp7_local_knn_auc(coords, scores, labels, params)
% CP7_LOCAL_KNN_AUC Compute KNN-centered local AUC support statistics.
if nargin < 4
    params = struct();
end

coords = double(coords);
scores = double(scores(:));
labels = double(labels(:));

if size(coords, 1) ~= numel(scores) || numel(scores) ~= numel(labels)
    error('[cp7_local_knn_auc] coords, scores, and labels must share the same row count.');
end
if size(coords, 2) ~= 2
    error('[cp7_local_knn_auc] coords must be [N x 2].');
end

n_row = size(coords, 1);
local_raw_auc = nan(n_row, 1);
local_effective_auc = nan(n_row, 1);
n_local = zeros(n_row, 1);
n_los_local = zeros(n_row, 1);
n_nlos_local = zeros(n_row, 1);
min_class_local = zeros(n_row, 1);
unstable_flag = false(n_row, 1);

valid_mask = all(isfinite(coords), 2) & isfinite(scores) & isfinite(labels);
idx_valid = find(valid_mask);
if isempty(idx_valid)
    local_table = table(local_raw_auc, local_effective_auc, n_local, n_los_local, ...
        n_nlos_local, min_class_local, unstable_flag);
    return;
end

coords_valid = coords(valid_mask, :);
scores_valid = scores(valid_mask);
labels_valid = labels(valid_mask);

local_k = min(get_param(params, 'local_k', 30), numel(idx_valid));
warn_min_class = get_param(params, 'local_warn_min_class', 5);
dist_mat = pdist2(coords_valid, coords_valid);

for idx = 1:numel(idx_valid)
    [~, sort_idx] = sort(dist_mat(idx, :), 'ascend');
    knn_idx = sort_idx(1:local_k);
    local_scores = scores_valid(knn_idx);
    local_labels = labels_valid(knn_idx);

    target_idx = idx_valid(idx);
    n_local(target_idx) = numel(knn_idx);
    n_los_local(target_idx) = sum(local_labels == 1);
    n_nlos_local(target_idx) = sum(local_labels == 0);
    min_class_local(target_idx) = min(n_los_local(target_idx), n_nlos_local(target_idx));
    unstable_flag(target_idx) = min_class_local(target_idx) < warn_min_class;

    metrics = cp7_binary_feature_metrics(local_scores, local_labels, params);
    local_raw_auc(target_idx) = metrics.auc_raw;
    local_effective_auc(target_idx) = metrics.auc_effective;
end

local_table = table(local_raw_auc, local_effective_auc, n_local, n_los_local, ...
    n_nlos_local, min_class_local, unstable_flag);
end
