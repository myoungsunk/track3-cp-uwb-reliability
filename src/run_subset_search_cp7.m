function outputs = run_subset_search_cp7(run_name, label_class_col)
% RUN_SUBSET_SEARCH_CP7 Exhaustive subset search over 7 CP features.
% Features:
%   1) gamma_CP_rx1        = log10(r_CP_rx1)
%   2) gamma_CP_rx2        = log10(r_CP_rx2)
%   3) a_FP_RHCP_rx1
%   4) a_FP_LHCP_rx1
%   5) a_FP_RHCP_rx2
%   6) a_FP_LHCP_rx2
%   7) fp_idx_diff_rx12
%
% Search space: all non-empty subsets (2^7 - 1 = 127).
%
% Outputs include per-scope results:
%   scope B, C, and B+C.

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
addpath(script_dir);

if nargin < 1 || strlength(string(run_name)) == 0
    run_name = 'subset_search_cp7_geometric_bc';
end
if nargin < 2 || strlength(string(label_class_col)) == 0
    label_class_col = 'geometric_class';
end

results_dir = fullfile(project_root, 'results', char(run_name));
if ~exist(results_dir, 'dir')
    mkdir(results_dir);
end

params = struct();
params.input_format = 'mp';
params.coord_unit = 'mm';
params.phase_unit = 'deg';
params.zeropad_factor = 4;
params.window_type = 'hanning';
params.freq_range_ghz = [3.1, 10.6];
params.label_csv = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_all_scenarios_los_nlos.csv');
params.label_col_class = char(label_class_col);
params.case_label_map = containers.Map({'caseA', 'caseB', 'caseC'}, {true, true, true});
params.fp_threshold_ratio = 0.2;
params.T_w = 2.0;
params.min_power_dbm = -120;
params.r_CP_clip = 1e4;
params.cp4_fp_reference = 'RHCP';
params.rcp_power_mode = 'WINDOW';
params.rcp_window_ns = 4.0;
params.gamma_cp_floor = 1e-6;
params.random_seed = 42;
params.cv_folds = 5;
params.normalize = true;
params.log10_rcp = false;
params.save_outputs = false;

case_files = {'CP_caseB_4port.csv', 'B'; 'CP_caseC_4port.csv', 'C'};

all_data = table();
for idx_case = 1:size(case_files, 1)
    csv_name = case_files{idx_case, 1};
    scenario_tag = string(case_files{idx_case, 2});
    csv_path = fullfile(project_root, csv_name);
    if ~isfile(csv_path)
        error('[run_subset_search_cp7] Missing CSV: %s', csv_path);
    end

    freq_table = load_sparam_table(csv_path, params);
    sim_data = build_sim_data_from_table(freq_table, params);
    [feature_table, ~] = extract_features_batch(sim_data, params);

    n_row = min(height(feature_table), numel(sim_data.x_coord_m));
    feature_table = feature_table(1:n_row, :);
    x_coord_m = double(sim_data.x_coord_m(1:n_row));
    y_coord_m = double(sim_data.y_coord_m(1:n_row));

    gamma_floor = max(get_param(params, 'gamma_cp_floor', 1e-6), eps);
    gamma_cp_rx1 = log10(max(double(feature_table.r_CP_rx1), gamma_floor));
    gamma_cp_rx2 = log10(max(double(feature_table.r_CP_rx2), gamma_floor));

    block = table();
    block.scenario = repmat(scenario_tag, n_row, 1);
    block.pos_id = double(feature_table.pos_id);
    block.x_m = x_coord_m;
    block.y_m = y_coord_m;
    block.label = logical(feature_table.label);
    block.valid_flag = logical(feature_table.valid_flag);
    block.gamma_CP_rx1 = gamma_cp_rx1;
    block.gamma_CP_rx2 = gamma_cp_rx2;
    block.a_FP_RHCP_rx1 = double(feature_table.a_FP_RHCP_rx1);
    block.a_FP_LHCP_rx1 = double(feature_table.a_FP_LHCP_rx1);
    block.a_FP_RHCP_rx2 = double(feature_table.a_FP_RHCP_rx2);
    block.a_FP_LHCP_rx2 = double(feature_table.a_FP_LHCP_rx2);
    block.fp_idx_diff_rx12 = double(feature_table.fp_idx_diff_rx12);

    all_data = [all_data; block]; %#ok<AGROW>
end

feature_names = { ...
    'gamma_CP_rx1', ...
    'gamma_CP_rx2', ...
    'a_FP_RHCP_rx1', ...
    'a_FP_LHCP_rx1', ...
    'a_FP_RHCP_rx2', ...
    'a_FP_LHCP_rx2', ...
    'fp_idx_diff_rx12'};

X_all = [ ...
    all_data.gamma_CP_rx1, ...
    all_data.gamma_CP_rx2, ...
    all_data.a_FP_RHCP_rx1, ...
    all_data.a_FP_LHCP_rx1, ...
    all_data.a_FP_RHCP_rx2, ...
    all_data.a_FP_LHCP_rx2, ...
    all_data.fp_idx_diff_rx12];

valid_global = all_data.valid_flag & all(isfinite(X_all), 2);
all_data = all_data(valid_global, :);
X_all = X_all(valid_global, :);
y_all = logical(all_data.label);

scope_masks = { ...
    'B', all_data.scenario == "B"; ...
    'C', all_data.scenario == "C"; ...
    'B+C', true(height(all_data), 1)};

all_results = table();
best_rows = table();

for idx_scope = 1:size(scope_masks, 1)
    scope_name = string(scope_masks{idx_scope, 1});
    scope_mask = logical(scope_masks{idx_scope, 2});

    X_scope = X_all(scope_mask, :);
    y_scope = y_all(scope_mask, :);

    result_scope = evaluate_all_subsets(X_scope, y_scope, feature_names, params);
    result_scope.scope = repmat(scope_name, height(result_scope), 1);

    all_results = [all_results; result_scope]; %#ok<AGROW>
    best_rows = [best_rows; result_scope(1, :)]; %#ok<AGROW>

    fprintf('[run_subset_search_cp7] scope=%s best_auc=%.4f features=%s\n', ...
        scope_name, result_scope.auc(1), result_scope.feature_set{1});
end

all_results = movevars(all_results, 'scope', 'Before', 1);
best_rows = movevars(best_rows, 'scope', 'Before', 1);

csv_all = fullfile(results_dir, 'subset_search_cp7_all.csv');
csv_best = fullfile(results_dir, 'subset_search_cp7_best_by_scope.csv');
writetable(all_results, csv_all);
writetable(best_rows, csv_best);

save(fullfile(results_dir, 'subset_search_cp7.mat'), ...
    'all_results', 'best_rows', 'all_data', 'feature_names', 'params');

outputs = struct();
outputs.all_results = all_results;
outputs.best_rows = best_rows;
outputs.results_dir = results_dir;
outputs.csv_all = csv_all;
outputs.csv_best = csv_best;
end

function result_table = evaluate_all_subsets(X, y, feature_names, params)
if numel(unique(y)) < 2
    error('[run_subset_search_cp7] Scope labels must contain both classes.');
end

n_feat = size(X, 2);
if n_feat ~= numel(feature_names)
    error('[run_subset_search_cp7] Feature name count mismatch.');
end

n_case = 2^n_feat - 1;
auc_col = nan(n_case, 1);
acc_col = nan(n_case, 1);
n_feat_col = nan(n_case, 1);
subset_id_col = strings(n_case, 1);
feature_set_col = strings(n_case, 1);
n_sample_col = repmat(size(X, 1), n_case, 1);
n_los_col = repmat(sum(y), n_case, 1);
n_nlos_col = repmat(sum(~y), n_case, 1);

rng(get_param(params, 'random_seed', 42));
cv = cvpartition(y, 'KFold', get_param(params, 'cv_folds', 5));

params_train = params;
params_train.cv_partition = cv;
params_train.log10_rcp = false;
params_train.normalize = true;

for mask = 1:n_case
    idx = find(bitget(mask, 1:n_feat));
    X_sub = X(:, idx);
    subset_id_col(mask) = "S" + string(mask);
    n_feat_col(mask) = numel(idx);
    feature_set_col(mask) = string(strjoin(feature_names(idx), ' + '));

    [model, ~] = train_logistic(X_sub, y, params_train);
    auc_col(mask) = model.cv_auc;
    acc_col(mask) = model.cv_accuracy;
end

result_table = table( ...
    subset_id_col, ...
    n_feat_col, ...
    feature_set_col, ...
    auc_col, ...
    acc_col, ...
    n_sample_col, ...
    n_los_col, ...
    n_nlos_col, ...
    'VariableNames', {'subset_id', 'n_features', 'feature_set', 'auc', 'accuracy', 'n_samples', 'n_los', 'n_nlos'});

result_table = sortrows(result_table, {'auc', 'accuracy', 'n_features'}, {'descend', 'descend', 'ascend'});
end
