function outputs = run_casec_4port_cp3(input_csv_name, run_name, label_class_col)
% RUN_CASEC_4PORT_CP3 Run Track-3 pipeline with 3 CP features:
% [gamma_CP, a_FP, fp_idx_diff_rx12]
%
% This file is a copied/extended variant of run_casec_4port.m
% to keep the original 2-feature pipeline unchanged.
script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
addpath(script_dir);

if nargin < 1 || strlength(string(input_csv_name)) == 0
    input_csv_name = 'CP_caseC_4port.csv';
end
if nargin < 2 || strlength(string(run_name)) == 0
    [~, default_stem] = fileparts(char(input_csv_name));
    run_name = lower(default_stem) + "_cp3";
end
if nargin < 3 || strlength(string(label_class_col)) == 0
    label_class_col = 'material_class';
end

input_csv = fullfile(project_root, char(input_csv_name));
if ~isfile(input_csv)
    error('[run_casec_4port_cp3] Input CSV not found: %s', input_csv);
end

results_dir = fullfile(project_root, 'results', char(run_name));
figures_dir = fullfile(results_dir, 'figures');
if ~exist(results_dir, 'dir')
    mkdir(results_dir);
end
if ~exist(figures_dir, 'dir')
    mkdir(figures_dir);
end

params = struct();
params.fp_threshold_ratio = 0.2;
params.fp_window_ns = 2.0;
params.min_power_dbm = -120;
params.r_CP_clip = 10000;
params.normalize = true;
params.cv_folds = 5;
params.random_seed = 42;
params.T_w = 2.0;
params.log10_rcp = false;
params.cp4_fp_reference = 'RHCP';
params.rcp_power_mode = 'WINDOW';
params.rcp_window_ns = 2.0;
params.gamma_cp_floor = 1e-6;
params.save_outputs = true;
params.results_dir = results_dir;
params.figures_dir = figures_dir;
params.input_format = 'mp';
params.coord_unit = 'mm';
params.phase_unit = 'deg';
params.zeropad_factor = 4;
params.window_type = 'hanning';
params.freq_range_ghz = [3.1, 10.6];
params.data_role = 'test';
params.svm_optimize_hyperparameters = false;
params.svm_max_objective_evals = 10;
params.nlos_min_count = 10;
params.label_csv = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_all_scenarios_los_nlos.csv');
params.label_col_class = char(label_class_col);
params.case_label_map = containers.Map({'caseA', 'caseB', 'caseC'}, {true, true, true});

fprintf('=== run_casec_4port_cp3 ===\n');
fprintf('Input: %s\n', input_csv);
fprintf('Results: %s\n', results_dir);
fprintf('Label column: %s\n', params.label_col_class);
rng(params.random_seed);

fprintf('\n[1/4] Loading and feature extraction...\n');
freq_table = load_sparam_table(input_csv, params);
sim_data = build_sim_data_from_table(freq_table, params);
[feature_table, sim_data] = extract_features_batch(sim_data, params);
feature_table = ensure_feature_columns_cp3(feature_table);

gamma_floor = get_param(params, 'gamma_cp_floor', 1e-6);
gamma_floor = max(gamma_floor, eps);
feature_table.gamma_CP = log10(max(double(feature_table.r_CP), gamma_floor));

save(fullfile(results_dir, 'step1_features.mat'), 'feature_table', 'sim_data', 'params');
writetable(feature_table, fullfile(results_dir, 'step1_features.csv'));

valid_mask = feature_table.valid_flag & ...
    isfinite(feature_table.gamma_CP) & ...
    isfinite(feature_table.a_FP) & ...
    isfinite(feature_table.fp_idx_diff_rx12);

features = [ ...
    double(feature_table.gamma_CP(valid_mask)), ...
    double(feature_table.a_FP(valid_mask)), ...
    double(feature_table.fp_idx_diff_rx12(valid_mask))];
labels = logical(feature_table.label(valid_mask));

fprintf('  Samples: %d (valid=%d), LoS=%d, NLoS=%d\n', ...
    height(feature_table), sum(valid_mask), sum(labels), sum(~labels));

benchmark = table();
ablation = table();
model = struct();
norm_params = struct();
results = struct();

if numel(unique(labels)) < 2
    warning('[run_casec_4port_cp3] Single-class labels detected. Skipping classification/benchmark/ablation.');
elseif min(sum(labels), sum(~labels)) < get_param(params, 'nlos_min_count', 10)
    warning('[run_casec_4port_cp3] Minority class count=%d < nlos_min_count=%d. Skipping classification/benchmark/ablation.', ...
        min(sum(labels), sum(~labels)), get_param(params, 'nlos_min_count', 10));
else
    fprintf('\n[2/4] Logistic training/evaluation (3 features)...\n');
    [model, norm_params] = train_logistic(features, labels, params);
    results = eval_roc_calibration(model, norm_params, features, labels, params);
    fprintf('  CV AUC=%.4f, CV Acc=%.4f, ECE=%.4f\n', model.cv_auc, model.cv_accuracy, results.ece);
    save(fullfile(results_dir, 'step2_logistic.mat'), 'model', 'norm_params', 'results');

    fprintf('\n[3/4] Benchmark and ablation (3 features)...\n');
    benchmark = run_ml_benchmark_cp3(features, labels, params);
    ablation = run_ablation_cp3(features, labels, params);
    writetable(benchmark, fullfile(results_dir, 'step3_benchmark_cp3.csv'));
    writetable(ablation, fullfile(results_dir, 'step4_ablation_cp3.csv'));
    save(fullfile(results_dir, 'step3_step4_cp3.mat'), 'benchmark', 'ablation');
end

fprintf('\n[4/4] Figure generation...\n');
if isempty(fieldnames(model))
    fprintf('  Skipped (classification artifacts unavailable).\n');
else
    generate_figures(feature_table(valid_mask, :), model, results, benchmark, ablation, params);
    fprintf('  Figures saved to: %s\n', figures_dir);
end

outputs = struct();
outputs.feature_table = feature_table;
outputs.sim_data = sim_data;
outputs.model = model;
outputs.norm_params = norm_params;
outputs.results = results;
outputs.benchmark = benchmark;
outputs.ablation = ablation;
outputs.params = params;
outputs.timestamp = datetime('now');
save(fullfile(results_dir, 'all_results_4port_cp3.mat'), 'outputs', '-v7.3');

fprintf('\n=== Done ===\n');
end

function feature_table = ensure_feature_columns_cp3(feature_table)
if ~ismember('position_id', feature_table.Properties.VariableNames)
    feature_table.position_id = double(feature_table.pos_id);
end
if ~ismember('scenario', feature_table.Properties.VariableNames)
    feature_table.scenario = repmat("NA", height(feature_table), 1);
end
if ~ismember('distance_m', feature_table.Properties.VariableNames)
    feature_table.distance_m = nan(height(feature_table), 1);
end
if ~ismember('fp_idx_diff_rx12', feature_table.Properties.VariableNames)
    feature_table.fp_idx_diff_rx12 = nan(height(feature_table), 1);
end
if ~ismember('fp_delay_diff_ns_rx12', feature_table.Properties.VariableNames)
    feature_table.fp_delay_diff_ns_rx12 = nan(height(feature_table), 1);
end
end
