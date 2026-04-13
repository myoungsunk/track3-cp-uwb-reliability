function outputs = run_los_nlos_baseline()
% RUN_LOS_NLOS_BASELINE Single-file LoS/NLoS baseline for UWB CIR data.
% The script reuses the current project's CSV loader and label join logic,
% then computes a richer CIR feature set, trains a logistic baseline with
% stratified cross-validation, and saves tables, figures, and MAT outputs.

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
source_dir = fullfile(project_root, 'src');

if ~isfolder(source_dir)
    error('[run_los_nlos_baseline] Source directory not found: %s', source_dir);
end

addpath(source_dir);

cfg = default_config(script_dir, project_root);
ensure_dir(cfg.results_root_dir);

fprintf('=== LoS/NLoS Baseline Pipeline ===\n');
fprintf('Project root: %s\n', project_root);
fprintf('Results dir : %s\n', cfg.results_root_dir);
fprintf('Random seed : %d\n', cfg.random_seed);

rng(cfg.random_seed);

summary_table = table();
outputs = struct();

for target_idx = 1:numel(cfg.label_targets)
    target_cfg = with_label_target(cfg, cfg.label_targets(target_idx));
    target_output = run_single_target_pipeline(target_cfg);
    outputs.(char(target_cfg.label_target.name)) = target_output;

    summary_row = target_output.metrics_overall;
    summary_row.label_target = repmat(string(target_cfg.label_target.name), height(summary_row), 1);
    summary_row.label_column = repmat(string(target_cfg.label_target.label_column), height(summary_row), 1);
    summary_row = movevars(summary_row, {'label_target', 'label_column'}, 'Before', 'group_name');
    summary_table = [summary_table; summary_row]; %#ok<AGROW>
end

outputs.config = cfg;
outputs.summary_table = summary_table;
outputs.timestamp = datetime('now');

writetable(summary_table, fullfile(cfg.results_root_dir, 'target_summary.csv'));
save(fullfile(cfg.results_root_dir, 'los_nlos_baseline_outputs_all_targets.mat'), 'outputs', '-v7.3');

fprintf('\n=== Combined Summary ===\n');
disp(summary_table(:, {'label_target', 'n_samples', 'n_los', 'n_nlos', 'auc', 'accuracy', 'f1_score'}));
fprintf('Saved outputs under %s\n', cfg.results_root_dir);
end

function outputs = run_single_target_pipeline(cfg)
ensure_dir(cfg.results_dir);
ensure_dir(cfg.figures_dir);

fprintf('\n--- Target: %s (%s) ---\n', cfg.label_target.name, cfg.label_target.label_column);

case_paths = resolve_case_paths(cfg);
dataset_table = table();

for case_idx = 1:numel(case_paths)
    case_path = case_paths{case_idx};
    fprintf('\n[%s][%d/%d] Loading %s\n', ...
        cfg.label_target.name, case_idx, numel(case_paths), case_path);

    freq_table = load_sparam_table(case_path, cfg.loader_params);
    sim_data = build_sim_data_from_table(freq_table, cfg.loader_params);
    [legacy_feature_table, sim_data] = extract_features_batch(sim_data, cfg.loader_params);

    case_table = build_case_feature_table(sim_data, legacy_feature_table, case_path, cfg);
    dataset_table = [dataset_table; case_table]; %#ok<AGROW>
end

dataset_table.valid_for_model = all(isfinite(dataset_table{:, cfg.model_feature_names}), 2) & ...
    logical(dataset_table.valid_flag);

if ~any(dataset_table.valid_for_model)
    error('[run_los_nlos_baseline] No valid rows available for model fitting for target %s.', ...
        cfg.label_target.name);
end

[cv_outputs, final_model, coefficient_table, normalization_table] = run_cv_logistic_baseline(dataset_table, cfg);

dataset_table.oof_score = nan(height(dataset_table), 1);
dataset_table.oof_pred = false(height(dataset_table), 1);
dataset_table.fold_id = zeros(height(dataset_table), 1);
dataset_table.full_fit_score = nan(height(dataset_table), 1);

dataset_table.oof_score(dataset_table.valid_for_model) = cv_outputs.oof_score;
dataset_table.oof_pred(dataset_table.valid_for_model) = cv_outputs.oof_pred;
dataset_table.fold_id(dataset_table.valid_for_model) = cv_outputs.fold_id;
dataset_table.full_fit_score(dataset_table.valid_for_model) = ...
    predict_with_model(final_model, dataset_table{dataset_table.valid_for_model, cfg.model_feature_names});

valid_dataset = dataset_table(dataset_table.valid_for_model, :);

metrics_overall = metrics_table_from_vectors( ...
    valid_dataset.label, ...
    valid_dataset.oof_score, ...
    valid_dataset.oof_pred, ...
    "overall");

metrics_by_case = grouped_metrics_table(valid_dataset, 'case_name');
metrics_by_scenario = grouped_metrics_table(valid_dataset, 'scenario');
metrics_by_polarization = grouped_metrics_table(valid_dataset, 'polarization');
feature_summary = build_feature_summary(valid_dataset, cfg.model_feature_names);
feature_auc = build_feature_auc_tables(valid_dataset, cfg.model_feature_names);

write_outputs(dataset_table, metrics_overall, metrics_by_case, metrics_by_scenario, ...
    metrics_by_polarization, feature_summary, coefficient_table, normalization_table, ...
    cv_outputs.fold_metrics, feature_auc, cfg);

create_all_figures(valid_dataset, metrics_by_case, coefficient_table, cfg);

outputs = struct();
outputs.config = cfg;
outputs.dataset_table = dataset_table;
outputs.metrics_overall = metrics_overall;
outputs.metrics_by_case = metrics_by_case;
outputs.metrics_by_scenario = metrics_by_scenario;
outputs.metrics_by_polarization = metrics_by_polarization;
outputs.feature_summary = feature_summary;
outputs.feature_auc = feature_auc;
outputs.coefficient_table = coefficient_table;
outputs.normalization_table = normalization_table;
outputs.cv_outputs = cv_outputs;
outputs.final_model = final_model;
outputs.timestamp = datetime('now');

save(fullfile(cfg.results_dir, 'los_nlos_baseline_outputs.mat'), 'outputs', '-v7.3');

fprintf('\n=== Summary: %s ===\n', cfg.label_target.name);
fprintf('Samples: %d (valid=%d)\n', height(dataset_table), sum(dataset_table.valid_for_model));
fprintf('LoS    : %d\n', sum(valid_dataset.label));
fprintf('NLoS   : %d\n', sum(~valid_dataset.label));
fprintf('OOF AUC: %.4f\n', metrics_overall.auc);
fprintf('OOF ACC: %.4f\n', metrics_overall.accuracy);
fprintf('OOF F1 : %.4f\n', metrics_overall.f1_score);
fprintf('Saved outputs under %s\n', cfg.results_dir);
end

function cfg = default_config(script_dir, project_root)
cfg = struct();
cfg.script_dir = script_dir;
cfg.project_root = project_root;
cfg.results_root_dir = fullfile(script_dir, 'results');
cfg.label_csv = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_all_scenarios_los_nlos.csv');
cfg.case_files = { ...
    'CP_caseA.csv', 'CP_caseB.csv', 'CP_caseC.csv', ...
    'LP_caseA.csv', 'LP_caseB.csv', 'LP_caseC.csv'};
cfg.label_targets = [ ...
    struct('name', "material", 'label_column', "material_class"), ...
    struct('name', "geometric", 'label_column', "geometric_class")];

cfg.random_seed = 42;
cfg.cv_folds = 5;
cfg.classification_threshold = 0.5;
cfg.logistic_lambda = 1e-2;

cfg.fp_threshold_ratio = 0.20;
cfg.fp_search_window_ns = [0, 80];
cfg.fp_energy_window_ns = 2.0;
cfg.component_threshold_db_down = 25.0;
cfg.noise_tail_fraction = 0.20;
cfg.noise_tail_min_samples = 64;
cfg.noise_guard_factor = 5.0;

cfg.model_feature_names = { ...
    'r_CP', ...
    'a_FP', ...
    'fp_energy_gap_db', ...
    'rise_time_ns', ...
    'mean_excess_delay_ns', ...
    'rms_delay_spread_ns', ...
    'max_excess_delay_ns', ...
    'kurtosis_pdp', ...
    'skewness_pdp', ...
    'fp_energy_db', ...
    'total_energy_db', ...
    'fp_energy_ratio', ...
    'fp_amp_norm', ...
    'peak_to_leading_db', ...
    'multipath_count', ...
    'ricean_k_db'};

cfg.case_label_map = containers.Map({'caseA', 'caseB', 'caseC'}, {true, true, true});

cfg.loader_params = struct();
cfg.loader_params.input_format = 'mp';
cfg.loader_params.coord_unit = 'mm';
cfg.loader_params.phase_unit = 'deg';
cfg.loader_params.zeropad_factor = 4;
cfg.loader_params.window_type = 'hanning';
cfg.loader_params.data_role = 'baseline';
cfg.loader_params.label_csv = cfg.label_csv;
cfg.loader_params.case_label_map = cfg.case_label_map;
cfg.loader_params.fp_threshold_ratio = cfg.fp_threshold_ratio;
cfg.loader_params.fp_search_window_ns = cfg.fp_search_window_ns;
cfg.loader_params.fp_window_ns = cfg.fp_energy_window_ns;
cfg.loader_params.T_w = cfg.fp_energy_window_ns;
cfg.loader_params.r_CP_clip = 1e4;
cfg.loader_params.use_cp4_features = false;
end

function target_cfg = with_label_target(cfg, label_target)
target_cfg = cfg;
target_cfg.label_target = label_target;
target_cfg.results_dir = fullfile(cfg.results_root_dir, char(label_target.name));
target_cfg.figures_dir = fullfile(target_cfg.results_dir, 'figures');
target_cfg.loader_params = cfg.loader_params;
target_cfg.loader_params.label_col_class = char(label_target.label_column);
end

function ensure_dir(dirpath)
if ~exist(dirpath, 'dir')
    mkdir(dirpath);
end
end

function case_paths = resolve_case_paths(cfg)
case_paths = {};
for idx = 1:numel(cfg.case_files)
    candidate = fullfile(cfg.project_root, cfg.case_files{idx});
    if isfile(candidate)
        case_paths{end+1} = candidate; %#ok<AGROW>
    else
        warning('[run_los_nlos_baseline] Missing input file: %s', candidate);
    end
end

if isempty(case_paths)
    error('[run_los_nlos_baseline] No case CSV files were found.');
end
end

function case_table = build_case_feature_table(sim_data, legacy_feature_table, case_path, cfg)
[~, case_name, ~] = fileparts(case_path);
[scenario_id, polarization] = parse_case_name(case_name);

n_pos = size(sim_data.CIR_rx1, 1);
feature_names = cir_feature_names();
feature_matrix = nan(n_pos, numel(feature_names));

for idx_pos = 1:n_pos
    channel_1 = extract_channel_cir_features(sim_data.CIR_rx1(idx_pos, :).', sim_data.t_axis(:), cfg);
    channel_2 = extract_channel_cir_features(sim_data.CIR_rx2(idx_pos, :).', sim_data.t_axis(:), cfg);
    feature_matrix(idx_pos, :) = aggregate_channel_features(channel_1, channel_2);

    if mod(idx_pos, 25) == 0 || idx_pos == n_pos
        fprintf('  [%s] %d/%d positions processed (%.1f%%)\n', ...
            case_name, idx_pos, n_pos, 100 * idx_pos / n_pos);
    end
end

case_table = table();
case_table.case_name = repmat(string(case_name), n_pos, 1);
case_table.scenario = repmat(string(scenario_id), n_pos, 1);
case_table.polarization = repmat(string(polarization), n_pos, 1);
case_table.pos_id = double(sim_data.pos_id(:));
case_table.x_m = double(sim_data.x_coord_m(:));
case_table.y_m = double(sim_data.y_coord_m(:));
case_table.label = logical(sim_data.labels(:));
case_table.valid_flag = logical(legacy_feature_table.valid_flag(:));
case_table.r_CP = double(legacy_feature_table.r_CP(:));
case_table.a_FP = double(legacy_feature_table.a_FP(:));
case_table.fp_idx_rx1 = double(legacy_feature_table.fp_idx_RHCP(:));
case_table.fp_idx_rx2 = double(legacy_feature_table.fp_idx_LHCP(:));
case_table.rss_rx1_db = double(legacy_feature_table.RSS_RHCP(:));
case_table.rss_rx2_db = double(legacy_feature_table.RSS_LHCP(:));

for idx_feature = 1:numel(feature_names)
    case_table.(feature_names{idx_feature}) = feature_matrix(:, idx_feature);
end
end

function [scenario_id, polarization] = parse_case_name(case_name)
case_name = string(case_name);
parts = split(case_name, '_');
if numel(parts) ~= 2
    scenario_id = "UNKNOWN";
    polarization = "UNKNOWN";
    return;
end

polarization = upper(parts(1));
case_token = lower(parts(2));
if startsWith(case_token, "case") && strlength(case_token) >= 5
    scenario_id = upper(extractAfter(case_token, 4));
else
    scenario_id = upper(case_token);
end
end

function names = cir_feature_names()
names = { ...
    'fp_energy_gap_db', ...
    'rise_time_ns', ...
    'mean_excess_delay_ns', ...
    'rms_delay_spread_ns', ...
    'max_excess_delay_ns', ...
    'kurtosis_pdp', ...
    'skewness_pdp', ...
    'fp_energy_db', ...
    'total_energy_db', ...
    'fp_energy_ratio', ...
    'fp_amp_norm', ...
    'peak_to_leading_db', ...
    'multipath_count', ...
    'ricean_k_db'};
end

function feature_vector = aggregate_channel_features(channel_1, channel_2)
names = cir_feature_names();
feature_vector = nan(1, numel(names));
for idx = 1:numel(names)
    values = [channel_1.(names{idx}), channel_2.(names{idx})];
    feature_vector(idx) = mean(values, 'omitnan');
end
end

function features = extract_channel_cir_features(cir, t_axis_ns, cfg)
amp = abs(double(cir(:)));
power_profile = amp .^ 2;
t_axis_ns = double(t_axis_ns(:));

features = empty_channel_feature_struct();

if isempty(power_profile) || numel(power_profile) ~= numel(t_axis_ns)
    return;
end

[fp_idx, peak_idx, threshold_power] = detect_first_path_local(power_profile, t_axis_ns, cfg);
if ~isfinite(fp_idx)
    return;
end

dt_ns = median(diff(t_axis_ns));
if ~isfinite(dt_ns) || dt_ns <= 0
    dt_ns = 1.0;
end

fp_window_samples = max(1, round(cfg.fp_energy_window_ns / dt_ns));
fp_end_idx = min(numel(power_profile), fp_idx + fp_window_samples - 1);

total_energy = sum(power_profile);
fp_energy = sum(power_profile(fp_idx:fp_end_idx));
leading_amp = amp(fp_idx);
peak_amp = amp(peak_idx);

tail_count = max(cfg.noise_tail_min_samples, round(cfg.noise_tail_fraction * numel(power_profile)));
tail_count = min(tail_count, numel(power_profile));
noise_floor = median(power_profile(end-tail_count+1:end));
if ~isfinite(noise_floor) || noise_floor <= 0
    noise_floor = eps;
end

component_threshold = max(threshold_power * 10^(-cfg.component_threshold_db_down / 10), ...
    cfg.noise_guard_factor * noise_floor);
significant_mask = false(size(power_profile));
significant_mask(fp_idx:end) = power_profile(fp_idx:end) >= component_threshold;
if ~any(significant_mask)
    significant_mask(fp_idx:fp_end_idx) = true;
end

tau_ns = t_axis_ns(significant_mask) - t_axis_ns(fp_idx);
power_sig = power_profile(significant_mask);
power_sig_sum = sum(power_sig);

if power_sig_sum <= 0
    return;
end

tau_mean = sum(tau_ns .* power_sig) / power_sig_sum;
tau_centered = tau_ns - tau_mean;
tau_var = sum((tau_centered .^ 2) .* power_sig) / power_sig_sum;
tau_rms = sqrt(max(tau_var, 0));

if tau_rms > 0
    skewness_pdp = sum((tau_centered .^ 3) .* power_sig) / (power_sig_sum * tau_rms^3);
    kurtosis_pdp = sum((tau_centered .^ 4) .* power_sig) / (power_sig_sum * tau_rms^4);
else
    skewness_pdp = 0;
    kurtosis_pdp = 1;
end

dominant_power = max(power_profile(fp_idx:end));
scattered_power = max(power_sig_sum - dominant_power, eps);
ricean_k_db = 10 * log10((dominant_power + eps) / scattered_power);

features.fp_energy_gap_db = 10 * log10(total_energy + eps) - 10 * log10(fp_energy + eps);
features.rise_time_ns = max(0, t_axis_ns(peak_idx) - t_axis_ns(fp_idx));
features.mean_excess_delay_ns = tau_mean;
features.rms_delay_spread_ns = tau_rms;
features.max_excess_delay_ns = max(tau_ns);
features.kurtosis_pdp = kurtosis_pdp;
features.skewness_pdp = skewness_pdp;
features.fp_energy_db = 10 * log10(fp_energy + eps);
features.total_energy_db = 10 * log10(total_energy + eps);
features.fp_energy_ratio = fp_energy / (total_energy + eps);
features.fp_amp_norm = leading_amp / sqrt(total_energy + eps);
features.peak_to_leading_db = 20 * log10((peak_amp + eps) / (leading_amp + eps));
features.multipath_count = sum(significant_mask);
features.ricean_k_db = ricean_k_db;
end

function features = empty_channel_feature_struct()
features = struct( ...
    'fp_energy_gap_db', NaN, ...
    'rise_time_ns', NaN, ...
    'mean_excess_delay_ns', NaN, ...
    'rms_delay_spread_ns', NaN, ...
    'max_excess_delay_ns', NaN, ...
    'kurtosis_pdp', NaN, ...
    'skewness_pdp', NaN, ...
    'fp_energy_db', NaN, ...
    'total_energy_db', NaN, ...
    'fp_energy_ratio', NaN, ...
    'fp_amp_norm', NaN, ...
    'peak_to_leading_db', NaN, ...
    'multipath_count', NaN, ...
    'ricean_k_db', NaN);
end

function [fp_idx, peak_idx, threshold_power] = detect_first_path_local(power_profile, t_axis_ns, cfg)
power_profile = double(power_profile(:));
t_axis_ns = double(t_axis_ns(:));

fp_idx = NaN;
peak_idx = NaN;
threshold_power = NaN;

if isempty(power_profile)
    return;
end

search_start = 1;
search_end = numel(power_profile);
if numel(cfg.fp_search_window_ns) == 2
    search_start = find(t_axis_ns >= min(cfg.fp_search_window_ns), 1, 'first');
    search_end = find(t_axis_ns <= max(cfg.fp_search_window_ns), 1, 'last');
    if isempty(search_start)
        search_start = 1;
    end
    if isempty(search_end)
        search_end = numel(power_profile);
    end
end

search_slice = power_profile(search_start:search_end);
[peak_power, peak_rel_idx] = max(search_slice);
peak_idx = peak_rel_idx + search_start - 1;
threshold_power = cfg.fp_threshold_ratio * peak_power;

candidate_rel = find(search_slice >= threshold_power, 1, 'first');
if isempty(candidate_rel)
    return;
end

fp_idx = candidate_rel + search_start - 1;

post_peak_rel = find(power_profile(fp_idx:end) == max(power_profile(fp_idx:end)), 1, 'first');
peak_idx = post_peak_rel + fp_idx - 1;
end

function [cv_outputs, final_model, coefficient_table, normalization_table] = run_cv_logistic_baseline(dataset_table, cfg)
valid_rows = find(dataset_table.valid_for_model);
X_all = dataset_table{valid_rows, cfg.model_feature_names};
y_all = logical(dataset_table.label(valid_rows));

rng(cfg.random_seed);
cv = cvpartition(y_all, 'KFold', cfg.cv_folds);

oof_score = nan(numel(valid_rows), 1);
oof_pred = false(numel(valid_rows), 1);
fold_id = zeros(numel(valid_rows), 1);
fold_metrics = table();

for fold_idx = 1:cv.NumTestSets
    train_mask = training(cv, fold_idx);
    test_mask = test(cv, fold_idx);

    X_train = X_all(train_mask, :);
    y_train = y_all(train_mask);
    X_test = X_all(test_mask, :);
    y_test = y_all(test_mask);

    [X_train_norm, norm_params] = normalize_feature_matrix(X_train);
    X_test_norm = apply_normalization(X_test, norm_params);

    model_fold = fit_logistic_model(X_train_norm, y_train, cfg);
    score_fold = predict_with_model(model_fold, X_test_norm);
    pred_fold = score_fold >= cfg.classification_threshold;

    oof_score(test_mask) = score_fold;
    oof_pred(test_mask) = pred_fold;
    fold_id(test_mask) = fold_idx;

    fold_metric_row = metrics_table_from_vectors(y_test, score_fold, pred_fold, "fold_" + string(fold_idx));
    fold_metric_row.fold_id = fold_idx;
    fold_metrics = [fold_metrics; fold_metric_row]; %#ok<AGROW>
end

[X_all_norm, norm_params_full] = normalize_feature_matrix(X_all);
final_model = fit_logistic_model(X_all_norm, y_all, cfg);
final_model.normalization = norm_params_full;
final_model.feature_names = cfg.model_feature_names;
final_model.classification_threshold = cfg.classification_threshold;

coefficient_table = extract_coefficient_table(final_model, cfg.model_feature_names);
normalization_table = table(string(cfg.model_feature_names(:)), ...
    norm_params_full.mean_values(:), norm_params_full.std_values(:), ...
    'VariableNames', {'feature_name', 'mean_value', 'std_value'});

cv_outputs = struct();
cv_outputs.oof_score = oof_score;
cv_outputs.oof_pred = oof_pred;
cv_outputs.fold_id = fold_id;
cv_outputs.fold_metrics = fold_metrics;
cv_outputs.valid_row_indices = valid_rows;
end

function [X_norm, params] = normalize_feature_matrix(X)
mean_values = mean(X, 1, 'omitnan');
std_values = std(X, 0, 1, 'omitnan');
std_values(~isfinite(std_values) | std_values == 0) = 1;

X_norm = (X - mean_values) ./ std_values;

params = struct();
params.mean_values = mean_values;
params.std_values = std_values;
end

function X_norm = apply_normalization(X, params)
X_norm = (X - params.mean_values) ./ params.std_values;
end

function model = fit_logistic_model(X, y, cfg)
sample_weights = compute_class_weights(y);

model = struct();
try
    mdl = fitclinear(X, y, ...
        'Learner', 'logistic', ...
        'Regularization', 'ridge', ...
        'Lambda', cfg.logistic_lambda, ...
        'Solver', 'lbfgs', ...
        'Weights', sample_weights);

    model.backend = "fitclinear";
    model.mdl_object = mdl;
catch exception_info
    warning('[run_los_nlos_baseline] fitclinear failed (%s). Falling back to fitglm.', exception_info.message);

    predictor_names = make_predictor_names(size(X, 2));
    train_table = array2table(X, 'VariableNames', predictor_names);
    train_table.label = y;
    mdl = fitglm(train_table, 'label ~ .', 'Distribution', 'binomial', 'Weights', sample_weights);

    model.backend = "fitglm";
    model.mdl_object = mdl;
    model.predictor_names = predictor_names;
end
end

function weights = compute_class_weights(y)
y = logical(y(:));
n_total = numel(y);
n_pos = sum(y);
n_neg = sum(~y);

weights = ones(n_total, 1);
if n_pos == 0 || n_neg == 0
    return;
end

weights(y) = 0.5 * n_total / n_pos;
weights(~y) = 0.5 * n_total / n_neg;
end

function predictor_names = make_predictor_names(n_feature)
predictor_names = arrayfun(@(idx) sprintf('x%d', idx), 1:n_feature, 'UniformOutput', false);
end

function score = predict_with_model(model, X_raw)
X_norm = X_raw;
if isfield(model, 'normalization') && ~isempty(model.normalization)
    X_norm = apply_normalization(X_raw, model.normalization);
end

switch string(model.backend)
    case "fitclinear"
        linear_score = X_norm * double(model.mdl_object.Beta(:)) + double(model.mdl_object.Bias);
        score = logistic_sigmoid(linear_score);
    case "fitglm"
        predictor_names = model.predictor_names;
        predict_table = array2table(X_norm, 'VariableNames', predictor_names);
        score = predict(model.mdl_object, predict_table);
    otherwise
        error('[run_los_nlos_baseline] Unsupported backend: %s', string(model.backend));
end
end

function y = logistic_sigmoid(x)
x = max(min(double(x), 60), -60);
y = 1 ./ (1 + exp(-x));
end

function coefficient_table = extract_coefficient_table(model, feature_names)
switch string(model.backend)
    case "fitclinear"
        intercept = double(model.mdl_object.Bias);
        coefficients = double(model.mdl_object.Beta(:));
    case "fitglm"
        estimate = double(model.mdl_object.Coefficients.Estimate);
        intercept = estimate(1);
        coefficients = estimate(2:end);
    otherwise
        error('[run_los_nlos_baseline] Unsupported backend for coefficient export.');
end

coefficient_table = table();
coefficient_table.term = ["intercept"; string(feature_names(:))];
coefficient_table.coefficient = [intercept; coefficients(:)];
coefficient_table.abs_coefficient = abs(coefficient_table.coefficient);
end

function metric_table = grouped_metrics_table(dataset_table, group_column)
group_values = unique(string(dataset_table.(group_column)), 'stable');
metric_table = table();

for idx = 1:numel(group_values)
    group_value = group_values(idx);
    row_mask = string(dataset_table.(group_column)) == group_value;
    metric_row = metrics_table_from_vectors( ...
        dataset_table.label(row_mask), ...
        dataset_table.oof_score(row_mask), ...
        dataset_table.oof_pred(row_mask), ...
        group_value);
    metric_row.group_type = repmat(string(group_column), height(metric_row), 1);
    metric_table = [metric_table; metric_row]; %#ok<AGROW>
end

metric_table = movevars(metric_table, 'group_type', 'Before', 'group_name');
end

function metric_row = metrics_table_from_vectors(labels, scores, predictions, group_name)
labels = logical(labels(:));
scores = double(scores(:));
predictions = logical(predictions(:));

n_samples = numel(labels);
tp = sum(predictions & labels);
tn = sum(~predictions & ~labels);
fp = sum(predictions & ~labels);
fn = sum(~predictions & labels);

accuracy = safe_divide(tp + tn, n_samples);
precision = safe_divide(tp, tp + fp);
recall = safe_divide(tp, tp + fn);
specificity = safe_divide(tn, tn + fp);
f1_score = safe_divide(2 * precision * recall, precision + recall);
balanced_accuracy = mean([recall, specificity], 'omitnan');
brier_score = mean((scores - double(labels)) .^ 2, 'omitnan');

if numel(unique(labels)) >= 2
    [~, ~, ~, auc] = perfcurve(labels, scores, true);
else
    auc = NaN;
end

metric_row = table();
metric_row.group_name = string(group_name);
metric_row.n_samples = n_samples;
metric_row.n_los = sum(labels);
metric_row.n_nlos = sum(~labels);
metric_row.accuracy = accuracy;
metric_row.precision = precision;
metric_row.recall = recall;
metric_row.specificity = specificity;
metric_row.f1_score = f1_score;
metric_row.balanced_accuracy = balanced_accuracy;
metric_row.auc = auc;
metric_row.brier_score = brier_score;
metric_row.tp = tp;
metric_row.tn = tn;
metric_row.fp = fp;
metric_row.fn = fn;
end

function value = safe_divide(num, den)
if den == 0
    value = NaN;
else
    value = num / den;
end
end

function feature_summary = build_feature_summary(dataset_table, feature_names)
feature_summary = table();
labels = logical(dataset_table.label);

for idx = 1:numel(feature_names)
    feature_name = feature_names{idx};
    values = double(dataset_table.(feature_name));

    row = table();
    row.feature_name = string(feature_name);
    row.mean_los = mean(values(labels), 'omitnan');
    row.std_los = std(values(labels), 0, 1, 'omitnan');
    row.mean_nlos = mean(values(~labels), 'omitnan');
    row.std_nlos = std(values(~labels), 0, 1, 'omitnan');
    row.mean_gap_los_minus_nlos = row.mean_los - row.mean_nlos;
    feature_summary = [feature_summary; row]; %#ok<AGROW>
end
end

function feature_auc = build_feature_auc_tables(dataset_table, feature_names)
labels = logical(dataset_table.label);
scenarios = unique(string(dataset_table.scenario), 'stable');

overall_table = table();
for idx = 1:numel(feature_names)
    feature_name = string(feature_names{idx});
    values = double(dataset_table.(feature_names{idx}));
    [auc_raw, auc_best] = compute_auc_pair(labels, values);

    row = table();
    row.feature = feature_name;
    row.auc_raw = auc_raw;
    row.auc_best_direction = auc_best;
    row.los_higher = double(auc_raw >= 0.5);
    overall_table = [overall_table; row]; %#ok<AGROW>
end
overall_table = sortrows(overall_table, 'auc_best_direction', 'descend');

by_scenario = table();
for idx_scenario = 1:numel(scenarios)
    scenario_value = scenarios(idx_scenario);
    scenario_mask = string(dataset_table.scenario) == scenario_value;
    labels_s = labels(scenario_mask);
    n_samples = sum(scenario_mask);
    n_los = sum(labels_s);
    n_nlos = sum(~labels_s);

    for idx_feature = 1:numel(feature_names)
        feature_name = string(feature_names{idx_feature});
        values_s = double(dataset_table.(feature_names{idx_feature})(scenario_mask));
        [auc_raw, auc_best] = compute_auc_pair(labels_s, values_s);

        row = table();
        row.scenario = scenario_value;
        row.feature = feature_name;
        row.n_samples = n_samples;
        row.n_los = n_los;
        row.n_nlos = n_nlos;
        row.auc_raw = auc_raw;
        row.auc_best_direction = auc_best;
        by_scenario = [by_scenario; row]; %#ok<AGROW>
    end
end

by_scenario_best_pivot = table();
by_scenario_best_pivot.feature = overall_table.feature;
by_scenario_best_pivot.higher_value_class = repmat("LoS", height(overall_table), 1);
by_scenario_best_pivot.higher_value_class(overall_table.los_higher < 0.5) = "NLoS";
by_scenario_best_pivot.overall_auc = overall_table.auc_best_direction;

for idx_scenario = 1:numel(scenarios)
    scenario_value = scenarios(idx_scenario);
    auc_values = nan(height(overall_table), 1);
    for idx_feature = 1:height(overall_table)
        row_mask = (by_scenario.feature == overall_table.feature(idx_feature)) & ...
            (by_scenario.scenario == scenario_value);
        if any(row_mask)
            auc_values(idx_feature) = by_scenario.auc_best_direction(find(row_mask, 1, 'first'));
        end
    end
    by_scenario_best_pivot.(sprintf('auc_%s', char(scenario_value))) = auc_values;
end

by_scenario_raw_pivot = table();
by_scenario_raw_pivot.feature = overall_table.feature;
by_scenario_raw_pivot.auc_overall_raw = overall_table.auc_raw;
for idx_scenario = 1:numel(scenarios)
    scenario_value = scenarios(idx_scenario);
    auc_values = nan(height(overall_table), 1);
    for idx_feature = 1:height(overall_table)
        row_mask = (by_scenario.feature == overall_table.feature(idx_feature)) & ...
            (by_scenario.scenario == scenario_value);
        if any(row_mask)
            auc_values(idx_feature) = by_scenario.auc_raw(find(row_mask, 1, 'first'));
        end
    end
    by_scenario_raw_pivot.(sprintf('auc_%s', char(scenario_value))) = auc_values;
end

feature_auc = struct();
feature_auc.overall = overall_table;
feature_auc.by_scenario = by_scenario;
feature_auc.by_scenario_best_pivot = by_scenario_best_pivot;
feature_auc.by_scenario_raw_pivot = by_scenario_raw_pivot;
feature_auc.summary = by_scenario_best_pivot;
end

function [auc_raw, auc_best] = compute_auc_pair(labels, scores)
labels = logical(labels(:));
scores = double(scores(:));

auc_raw = NaN;
auc_best = NaN;

valid_mask = isfinite(scores) & isfinite(double(labels));
labels = labels(valid_mask);
scores = scores(valid_mask);

if numel(unique(labels)) < 2
    return;
end

[~, ~, ~, auc_raw] = perfcurve(labels, scores, true);
auc_best = max(auc_raw, 1 - auc_raw);
end

function write_outputs(dataset_table, metrics_overall, metrics_by_case, metrics_by_scenario, ...
    metrics_by_polarization, feature_summary, coefficient_table, normalization_table, ...
    fold_metrics, feature_auc, cfg)

writetable(dataset_table, fullfile(cfg.results_dir, 'baseline_feature_table.csv'));
writetable(metrics_overall, fullfile(cfg.results_dir, 'metrics_overall.csv'));
writetable(metrics_by_case, fullfile(cfg.results_dir, 'metrics_by_case.csv'));
writetable(metrics_by_scenario, fullfile(cfg.results_dir, 'metrics_by_scenario.csv'));
writetable(metrics_by_polarization, fullfile(cfg.results_dir, 'metrics_by_polarization.csv'));
writetable(feature_summary, fullfile(cfg.results_dir, 'feature_summary.csv'));
writetable(coefficient_table, fullfile(cfg.results_dir, 'logistic_coefficients.csv'));
writetable(normalization_table, fullfile(cfg.results_dir, 'feature_normalization.csv'));
writetable(fold_metrics, fullfile(cfg.results_dir, 'metrics_by_fold.csv'));
writetable(feature_auc.overall, fullfile(cfg.results_dir, 'feature_auc_univariate.csv'));
writetable(feature_auc.by_scenario, fullfile(cfg.results_dir, 'feature_auc_by_scenario.csv'));
writetable(feature_auc.by_scenario_best_pivot, fullfile(cfg.results_dir, 'feature_auc_by_scenario_best_pivot.csv'));
writetable(feature_auc.by_scenario_raw_pivot, fullfile(cfg.results_dir, 'feature_auc_by_scenario_raw_pivot.csv'));
writetable(feature_auc.summary, fullfile(cfg.results_dir, 'feature_auc_summary_table.csv'));
end

function create_all_figures(dataset_table, metrics_by_case, coefficient_table, cfg)
plot_roc_curve(dataset_table, cfg);
plot_score_histogram(dataset_table, cfg);
plot_confusion_matrix(dataset_table, cfg);
plot_feature_importance(coefficient_table, cfg);
plot_case_accuracy(metrics_by_case, cfg);
end

function plot_roc_curve(dataset_table, cfg)
labels = logical(dataset_table.label);
scores = double(dataset_table.oof_score);

[fpr, tpr, ~, auc] = perfcurve(labels, scores, true);

fig = figure('Visible', 'off', 'Color', 'w');
plot(fpr, tpr, 'LineWidth', 2, 'Color', [0.00 0.45 0.74]);
hold on;
plot([0 1], [0 1], '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 1);
grid on;
xlim([0 1]);
ylim([0 1]);
xlabel('False Positive Rate');
ylabel('True Positive Rate');
title(sprintf('LoS/NLoS ROC Curve (AUC = %.3f)', auc));
save_figure_bundle(fig, fullfile(cfg.figures_dir, 'roc_curve'));
close(fig);
end

function plot_score_histogram(dataset_table, cfg)
labels = logical(dataset_table.label);
scores = double(dataset_table.oof_score);

fig = figure('Visible', 'off', 'Color', 'w');
histogram(scores(labels), 'BinWidth', 0.05, 'Normalization', 'probability', ...
    'FaceColor', [0.20 0.60 0.20], 'FaceAlpha', 0.60, 'EdgeColor', 'none');
hold on;
histogram(scores(~labels), 'BinWidth', 0.05, 'Normalization', 'probability', ...
    'FaceColor', [0.85 0.33 0.10], 'FaceAlpha', 0.60, 'EdgeColor', 'none');
xline(0.5, '--k', 'Threshold', 'LabelVerticalAlignment', 'bottom');
grid on;
xlim([0 1]);
xlabel('Predicted LoS Probability');
ylabel('Probability');
legend({'LoS', 'NLoS', 'Threshold'}, 'Location', 'best');
title('Out-of-Fold Score Distribution');
save_figure_bundle(fig, fullfile(cfg.figures_dir, 'score_histogram'));
close(fig);
end

function plot_confusion_matrix(dataset_table, cfg)
labels = logical(dataset_table.label);
predictions = logical(dataset_table.oof_pred);
cm = confusionmat(labels, predictions, 'Order', [false true]);
cm_norm = cm ./ max(sum(cm, 2), 1);

fig = figure('Visible', 'off', 'Color', 'w');
imagesc(cm_norm);
axis image;
colormap(parula(256));
colorbar;
set(gca, 'XTick', 1:2, 'XTickLabel', {'Pred NLoS', 'Pred LoS'}, ...
    'YTick', 1:2, 'YTickLabel', {'True NLoS', 'True LoS'});
title('Normalized Confusion Matrix');

for row = 1:2
    for col = 1:2
        text(col, row, sprintf('%.2f\n(%d)', cm_norm(row, col), cm(row, col)), ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'Color', 'w', ...
            'FontWeight', 'bold', ...
            'Interpreter', 'none');
    end
end

save_figure_bundle(fig, fullfile(cfg.figures_dir, 'confusion_matrix'));
close(fig);
end

function plot_feature_importance(coefficient_table, cfg)
feature_rows = coefficient_table(2:end, :);
[~, sort_idx] = sort(feature_rows.abs_coefficient, 'descend');
feature_rows = feature_rows(sort_idx, :);

fig = figure('Visible', 'off', 'Color', 'w');
barh(feature_rows.coefficient, 'FaceColor', [0.49 0.18 0.56]);
grid on;
xlabel('Standardized Logistic Coefficient');
ylabel('Feature');
title('Feature Importance (Full-Fit Logistic Coefficients)');
set(gca, 'YTick', 1:height(feature_rows), 'YTickLabel', cellstr(feature_rows.term));
set(gca, 'YDir', 'reverse');
save_figure_bundle(fig, fullfile(cfg.figures_dir, 'feature_importance'));
close(fig);
end

function plot_case_accuracy(metrics_by_case, cfg)
fig = figure('Visible', 'off', 'Color', 'w');
bar(metrics_by_case.accuracy, 'FaceColor', [0.12 0.47 0.71]);
hold on;
plot(xlim, [0.5 0.5], '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 1);
ylim([0 1]);
grid on;
set(gca, 'XTick', 1:height(metrics_by_case), 'XTickLabel', cellstr(metrics_by_case.group_name));
xlabel('Case');
ylabel('Accuracy');
title('Per-Case Accuracy');
save_figure_bundle(fig, fullfile(cfg.figures_dir, 'case_accuracy'));
close(fig);
end

function save_figure_bundle(fig, filepath_without_ext)
try
    savefig(fig, [filepath_without_ext '.fig']);
catch
end

try
    exportgraphics(fig, [filepath_without_ext '.png'], 'Resolution', 200);
catch
    saveas(fig, [filepath_without_ext '.png']);
end
end
