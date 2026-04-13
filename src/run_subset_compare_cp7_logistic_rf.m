function outputs = run_subset_compare_cp7_logistic_rf(search_run_name, out_run_name)
% RUN_SUBSET_COMPARE_CP7_LOGISTIC_RF Compare Logistic vs RF on CP7 subset search.
%
% Requires outputs from run_subset_search_cp7(...), specifically:
%   results/<search_run_name>/subset_search_cp7.mat
%
% Produces:
%   results/<out_run_name>/subset_compare_logistic_rf_by_scope.csv
%   results/<out_run_name>/subset_compare_logistic_rf_rfbest_detail.csv

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);

if nargin < 1 || strlength(string(search_run_name)) == 0
    search_run_name = 'subset_search_cp7_geometric_bc';
end
if nargin < 2 || strlength(string(out_run_name)) == 0
    out_run_name = 'subset_compare_cp7_logistic_rf_geometric_bc';
end

in_mat = fullfile(project_root, 'results', char(search_run_name), 'subset_search_cp7.mat');
if ~isfile(in_mat)
    error('[run_subset_compare_cp7_logistic_rf] Missing input MAT: %s', in_mat);
end

loaded = load(in_mat, 'all_results', 'all_data', 'feature_names', 'params');
all_results = loaded.all_results;
all_data = loaded.all_data;
feature_names = loaded.feature_names;
params = loaded.params;

out_dir = fullfile(project_root, 'results', char(out_run_name));
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

X_all = [ ...
    all_data.gamma_CP_rx1, ...
    all_data.gamma_CP_rx2, ...
    all_data.a_FP_RHCP_rx1, ...
    all_data.a_FP_LHCP_rx1, ...
    all_data.a_FP_RHCP_rx2, ...
    all_data.a_FP_LHCP_rx2, ...
    all_data.fp_idx_diff_rx12];
y_all = logical(all_data.label);

scope_names = {'B', 'C', 'B+C'};
scope_masks = {all_data.scenario == "B", all_data.scenario == "C", true(height(all_data), 1)};

n_scope = numel(scope_names);
summary_scope = table();
rfbest_detail = table();

for idx_scope = 1:n_scope
    scope_name = string(scope_names{idx_scope});
    mask_scope = logical(scope_masks{idx_scope});
    X = X_all(mask_scope, :);
    y = y_all(mask_scope, :);

    rows_scope = all_results(all_results.scope == scope_name, :);
    if isempty(rows_scope)
        error('[run_subset_compare_cp7_logistic_rf] No rows for scope=%s', scope_name);
    end

    % Logistic-best subset from existing exhaustive search (already sorted).
    best_log = rows_scope(1, :);
    idx_log = parse_subset_id(best_log.subset_id);
    [rf_auc_on_log, rf_acc_on_log] = eval_rf_subset_cv(X(:, idx_log), y, params);

    % RF-best subset by exhaustive scan across all 127 subsets.
    n_feat = size(X, 2);
    n_case = 2^n_feat - 1;
    rf_auc_col = nan(n_case, 1);
    rf_acc_col = nan(n_case, 1);
    rf_subset_id = strings(n_case, 1);
    rf_feature_set = strings(n_case, 1);

    for mask = 1:n_case
        idx = find(bitget(mask, 1:n_feat));
        [rf_auc_col(mask), rf_acc_col(mask)] = eval_rf_subset_cv(X(:, idx), y, params);
        rf_subset_id(mask) = "S" + string(mask);
        rf_feature_set(mask) = string(strjoin(feature_names(idx), ' + '));
    end

    rf_table = table(rf_subset_id, rf_feature_set, rf_auc_col, rf_acc_col, ...
        'VariableNames', {'subset_id', 'feature_set', 'rf_auc', 'rf_accuracy'});
    rf_table = sortrows(rf_table, {'rf_auc', 'rf_accuracy'}, {'descend', 'descend'});

    best_rf = rf_table(1, :);
    idx_rf = parse_subset_id(best_rf.subset_id);
    row_log_at_rf = rows_scope(rows_scope.subset_id == best_rf.subset_id, :);
    if isempty(row_log_at_rf)
        % Should not happen if all subset IDs exist.
        log_auc_at_rf = NaN;
        log_acc_at_rf = NaN;
    else
        log_auc_at_rf = row_log_at_rf.auc(1);
        log_acc_at_rf = row_log_at_rf.accuracy(1);
    end

    % Summary per scope.
    row = table();
    row.scope = scope_name;
    row.log_best_subset_id = best_log.subset_id;
    row.log_best_features = best_log.feature_set;
    row.log_best_auc = best_log.auc;
    row.log_best_acc = best_log.accuracy;
    row.rf_on_logbest_auc = rf_auc_on_log;
    row.rf_on_logbest_acc = rf_acc_on_log;
    row.rf_best_subset_id = best_rf.subset_id;
    row.rf_best_features = best_rf.feature_set;
    row.rf_best_auc = best_rf.rf_auc;
    row.rf_best_acc = best_rf.rf_accuracy;
    row.log_on_rfbest_auc = log_auc_at_rf;
    row.log_on_rfbest_acc = log_acc_at_rf;

    summary_scope = [summary_scope; row]; %#ok<AGROW>

    best_rf.scope = scope_name;
    rfbest_detail = [rfbest_detail; best_rf]; %#ok<AGROW>

    fprintf('[subset_compare] scope=%s | log_best_auc=%.4f | rf_on_log_best=%.4f | rf_best_auc=%.4f\n', ...
        scope_name, best_log.auc, rf_auc_on_log, best_rf.rf_auc);
end

csv_summary = fullfile(out_dir, 'subset_compare_logistic_rf_by_scope.csv');
csv_rfbest = fullfile(out_dir, 'subset_compare_logistic_rf_rfbest_detail.csv');
writetable(summary_scope, csv_summary);
writetable(rfbest_detail, csv_rfbest);

save(fullfile(out_dir, 'subset_compare_logistic_rf.mat'), 'summary_scope', 'rfbest_detail');

outputs = struct();
outputs.summary_scope = summary_scope;
outputs.rfbest_detail = rfbest_detail;
outputs.csv_summary = csv_summary;
outputs.csv_rfbest = csv_rfbest;
outputs.out_dir = out_dir;
end

function subset_idx = parse_subset_id(subset_id)
subset_str = char(string(subset_id));
if isempty(subset_str) || subset_str(1) ~= 'S'
    error('[run_subset_compare_cp7_logistic_rf] Invalid subset_id: %s', subset_str);
end
mask = str2double(subset_str(2:end));
if ~isfinite(mask) || mask < 1
    error('[run_subset_compare_cp7_logistic_rf] Invalid subset mask in subset_id: %s', subset_str);
end
subset_idx = find(bitget(mask, 1:64));
end

function [auc_val, acc_val] = eval_rf_subset_cv(X, y, params)
if size(X, 1) ~= numel(y)
    error('[run_subset_compare_cp7_logistic_rf] X/y size mismatch.');
end
if numel(unique(y)) < 2
    auc_val = NaN;
    acc_val = NaN;
    return;
end

n = size(X, 1);
rf_prob = nan(n, 1);
random_seed = get_param(params, 'random_seed', 42);
cv_folds = get_param(params, 'cv_folds', 5);
rng(random_seed);
cv = cvpartition(y, 'KFold', cv_folds);

num_trees = get_param(params, 'rf_num_trees', 100);
max_splits = get_param(params, 'rf_max_num_splits', 20);

for fold_idx = 1:cv.NumTestSets
    tr = training(cv, fold_idx);
    te = test(cv, fold_idx);

    x_train = X(tr, :);
    y_train = y(tr);
    x_test = X(te, :);

    [x_train_n, norm_info] = normalize_matrix(x_train);
    x_test_n = apply_norm_matrix(x_test, norm_info);

    rf_mdl = fitcensemble(x_train_n, y_train, 'Method', 'Bag', ...
        'NumLearningCycles', num_trees, ...
        'Learners', templateTree('MaxNumSplits', max_splits));

    [~, score_fold] = predict(rf_mdl, x_test_n);
    rf_prob(te) = positive_score(score_fold, rf_mdl.ClassNames);
end

[~, ~, ~, auc_val] = perfcurve(y, rf_prob, true);
acc_val = mean((rf_prob >= 0.5) == y);
end

function [x_norm, info] = normalize_matrix(x)
mu = mean(x, 1, 'omitnan');
sigma = std(x, 0, 1, 'omitnan');
sigma(sigma == 0) = 1;
x_norm = (x - mu) ./ sigma;
info = struct('mu', mu, 'sigma', sigma);
end

function x_out = apply_norm_matrix(x, info)
x_out = (x - info.mu) ./ info.sigma;
end

function prob = positive_score(score_matrix, class_names)
if islogical(class_names)
    pos_idx = find(class_names == true, 1, 'first');
else
    pos_idx = find(strcmp(string(class_names), string(true)), 1, 'first');
    if isempty(pos_idx)
        pos_idx = 2;
    end
end
prob = score_matrix(:, pos_idx);
end
