function outputs = run_casec_4port(input_csv_name, run_name, label_class_col)
% RUN_CASEC_4PORT Run Track-3 pipeline for a 4-port CP CSV input.
% Default usage keeps backward compatibility:
%   run_casec_4port()
%   run_casec_4port('CP_caseB_4port.csv', 'caseB_4port')
script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
addpath(script_dir);

if nargin < 1 || strlength(string(input_csv_name)) == 0
    input_csv_name = 'CP_caseC_4port.csv';
end
if nargin < 2 || strlength(string(run_name)) == 0
    [~, default_stem] = fileparts(char(input_csv_name));
    run_name = lower(default_stem);
end
if nargin < 3 || strlength(string(label_class_col)) == 0
    label_class_col = 'material_class';
end

input_csv = fullfile(project_root, char(input_csv_name));
if ~isfile(input_csv)
    error('[run_casec_4port] Input CSV not found: %s', input_csv);
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
params.log10_rcp = true;
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

fprintf('=== run_casec_4port ===\n');
fprintf('Input: %s\n', input_csv);
fprintf('Results: %s\n', results_dir);
fprintf('Label column: %s\n', params.label_col_class);
rng(params.random_seed);

fprintf('\n[1/4] Loading and feature extraction...\n');
freq_table = load_sparam_table(input_csv, params);
sim_data = build_sim_data_from_table(freq_table, params);
[feature_table, sim_data] = extract_features_batch(sim_data, params);
feature_table = ensure_feature_columns(feature_table);
save(fullfile(results_dir, 'step1_features.mat'), 'feature_table', 'sim_data', 'params');
writetable(feature_table, fullfile(results_dir, 'step1_features.csv'));

valid_mask = feature_table.valid_flag & isfinite(feature_table.r_CP) & isfinite(feature_table.a_FP);
features = [feature_table.r_CP(valid_mask), feature_table.a_FP(valid_mask)];
labels = logical(feature_table.label(valid_mask));

fprintf('  Samples: %d (valid=%d), LoS=%d, NLoS=%d\n', ...
    height(feature_table), sum(valid_mask), sum(labels), sum(~labels));

benchmark = table();
ablation = table();
model = struct();
norm_params = struct();
results = struct();

if numel(unique(labels)) < 2
    warning('[run_casec_4port] Single-class labels detected. Skipping classification/benchmark/ablation.');
elseif min(sum(labels), sum(~labels)) < get_param(params, 'nlos_min_count', 10)
    warning('[run_casec_4port] Minority class count=%d < nlos_min_count=%d. Skipping classification/benchmark/ablation.', ...
        min(sum(labels), sum(~labels)), get_param(params, 'nlos_min_count', 10));
else
    fprintf('\n[2/4] Logistic training/evaluation...\n');
    [model, norm_params] = train_logistic(features, labels, params);
    results = eval_roc_calibration(model, norm_params, features, labels, params);
    fprintf('  CV AUC=%.4f, CV Acc=%.4f, ECE=%.4f\n', model.cv_auc, model.cv_accuracy, results.ece);
    save(fullfile(results_dir, 'step2_logistic.mat'), 'model', 'norm_params', 'results');

    fprintf('\n[3/4] Benchmark and ablation...\n');
    benchmark = run_ml_benchmark(features, labels, params);
    ablation = run_ablation(features, labels, params);
    writetable(benchmark, fullfile(results_dir, 'step3_benchmark.csv'));
    writetable(ablation, fullfile(results_dir, 'step4_ablation.csv'));
    save(fullfile(results_dir, 'step3_step4.mat'), 'benchmark', 'ablation');
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
save(fullfile(results_dir, 'all_results_4port.mat'), 'outputs', '-v7.3');

fprintf('\n=== Done ===\n');
end

function feature_table = ensure_feature_columns(feature_table)
if ~ismember('position_id', feature_table.Properties.VariableNames)
    feature_table.position_id = double(feature_table.pos_id);
end
if ~ismember('scenario', feature_table.Properties.VariableNames)
    feature_table.scenario = repmat("NA", height(feature_table), 1);
end
if ~ismember('distance_m', feature_table.Properties.VariableNames)
    feature_table.distance_m = nan(height(feature_table), 1);
end
end
