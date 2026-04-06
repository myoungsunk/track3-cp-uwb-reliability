%% main_run_all.m — Track 3 전체 분석 파이프라인
% 실행 전 확인사항:
%   1. data/raw/SIM1.mat (또는 SIM2.mat) 존재
%   2. src/ 디렉토리가 MATLAB path에 추가됨
%   3. results/ 및 results/figures/ 디렉토리 존재
%
% 실행: >> main_run_all

clear; clc; close all;
script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);
addpath(script_dir);

%% ===== 0. 파라미터 설정 =====
params = struct();
params.fp_threshold_ratio = 0.2;    % first-path 검출 임계치
params.fp_window_ns       = 2.0;    % first-path 에너지 윈도우 [ns]
params.min_power_dbm      = -120;   % noise floor [dBm]
params.r_CP_clip          = 10000;  % r_CP 최대값 (linear, = 40 dB)
params.normalize          = true;   % z-score 정규화
params.cv_folds           = 5;      % Stratified K-fold
params.random_seed        = 42;     % 재현성
params.dataset_name       = 'SIM1'; % 데이터셋 이름

% Phase-1/2 추가 파라미터
params.T_w                = 2.0;
params.log10_rcp          = true;
params.save_outputs       = true;
params.results_dir        = fullfile(project_root, 'results');
params.figures_dir        = fullfile(params.results_dir, 'figures');
params.input_format       = 'mp';
params.coord_unit         = 'mm';
params.phase_unit         = 'deg';
params.zeropad_factor     = 4;
params.window_type        = 'hanning';
params.freq_range_ghz     = [3.1, 10.6];
params.data_role          = 'test';
params.svm_optimize_hyperparameters = true;
params.svm_max_objective_evals = 30;
params.label_csv = fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_all_scenarios_los_nlos.csv');
params.case_label_map = containers.Map({'caseA', 'caseB', 'caseC'}, {true, true, true});
params.merge_t_axis_tol_ns = 1e-9;
params.merge_fs_eff_tol_hz = 1e-3;

if ~exist(fullfile(project_root, 'data'), 'dir'), mkdir(fullfile(project_root, 'data')); end
if ~exist(fullfile(project_root, 'data', 'raw'), 'dir'), mkdir(fullfile(project_root, 'data', 'raw')); end
if ~exist(fullfile(project_root, 'data', 'processed'), 'dir'), mkdir(fullfile(project_root, 'data', 'processed')); end
if ~exist(params.results_dir, 'dir'), mkdir(params.results_dir); end
if ~exist(params.figures_dir, 'dir'), mkdir(params.figures_dir); end

rng(params.random_seed);
fprintf('=== Track 3 Analysis Pipeline ===\n');
fprintf('Timestamp: %s\n', datestr(now));
fprintf('Random seed: %d\n', params.random_seed);

%% ===== 1. Feature 추출 =====
fprintf('\n[1/5] Extracting features...\n');
sim_data_path = fullfile(project_root, 'data', 'raw', [params.dataset_name '.mat']);
[feature_table, sim_data] = extract_or_load_feature_table(sim_data_path, params, project_root);
fprintf('  Extracted %d samples (LoS: %d, NLoS: %d)\n', ...
    height(feature_table), sum(feature_table.label), sum(~feature_table.label));

% 저장
save(fullfile(project_root, 'data', 'processed', ['features_' params.dataset_name '.mat']), 'feature_table', 'sim_data');
writetable(feature_table, fullfile(project_root, 'data', 'processed', ['features_' params.dataset_name '.csv']));
save(fullfile(params.results_dir, 'step1_features.mat'), 'feature_table', 'sim_data', 'params');
writetable(feature_table, fullfile(params.results_dir, 'step1_features.csv'));

%% ===== 2. Logistic Regression 학습 =====
fprintf('\n[2/5] Training Logistic Regression...\n');
features = [feature_table.r_CP, feature_table.a_FP];
labels   = feature_table.label;

[model, norm_params] = train_logistic(features, labels, params);
fprintf('  CV AUC: %.4f, CV Accuracy: %.4f\n', model.cv_auc, model.cv_accuracy);

% 상세 평가
results = eval_roc_calibration(model, norm_params, features, labels, params);
fprintf('  Test AUC: %.4f, ECE: %.4f\n', results.roc.auc, results.ece);
save(fullfile(params.results_dir, 'step2_logistic.mat'), 'model', 'norm_params', 'results');

%% ===== 3. ML 벤치마크 =====
fprintf('\n[3/5] Running ML benchmark...\n');
benchmark = run_ml_benchmark(features, labels, params);
disp(benchmark);
save(fullfile(params.results_dir, 'step3_benchmark.mat'), 'benchmark');
writetable(benchmark, fullfile(params.results_dir, 'step3_benchmark.csv'));

%% ===== 4. Ablation Study =====
fprintf('\n[4/5] Running ablation study...\n');
ablation = run_ablation(features, labels, params);
disp(ablation);
save(fullfile(params.results_dir, 'step4_ablation.mat'), 'ablation');
writetable(ablation, fullfile(params.results_dir, 'step4_ablation.csv'));

%% ===== 5. Figure 생성 =====
fprintf('\n[5/5] Generating figures...\n');
generate_figures(feature_table, model, results, benchmark, ablation, params);
fprintf('  Figures saved to results/figures/\n');

%% ===== 6. 결과 요약 저장 =====
save(fullfile(project_root, 'results', 'all_results.mat'), ...
    'model', 'norm_params', 'results', 'benchmark', 'ablation', 'params', 'feature_table');
fprintf('\n=== Pipeline Complete ===\n');

% 핵심 수치 요약 출력 (논문 작성용)
fprintf('\n--- Paper Key Numbers ---\n');
fprintf('Logistic AUC: %.3f\n', results.roc.auc);
fprintf('Logistic ECE: %.4f\n', results.ece);
fprintf('Logistic FLOPs: %d\n', results.flops);
for i = 1:height(benchmark)
    model_name_i = string(benchmark.model_name(i));
    auc_i = benchmark.auc(i);
    flops_i = benchmark.flops(i);
    ratio_i = flops_i / results.flops;
    if ~isfinite(ratio_i)
        ratio_i = NaN;
    end
    fprintf('%s: AUC=%.3f, FLOPs=%g, ratio=%.0fx\n', ...
        char(model_name_i), auc_i, flops_i, ratio_i);
end
fprintf('\nAblation:\n');
for i = 1:height(ablation)
    fprintf('  %s: AUC=%.3f (ΔAUC=%.3f)\n', ...
        char(ablation.config(i)), ablation.auc(i), ablation.delta_auc_vs_combined(i));
end

function [feature_table, sim_data_all] = extract_or_load_feature_table(sim_data_path, params, project_root)
% EXTRACT_OR_LOAD_FEATURE_TABLE Load feature table from MAT/CSV or build from raw S-parameter tables.
if isfile(sim_data_path)
    [~, ~, ext] = fileparts(sim_data_path);
    ext = lower(ext);

    if strcmp(ext, '.mat')
        loaded = load(sim_data_path);

        if isfield(loaded, 'feature_table') && istable(loaded.feature_table)
            feature_table = loaded.feature_table;
            sim_data_all = [];
            return;
        end

        table_candidate = find_table_in_struct(loaded);
        if ~isempty(table_candidate)
            freq_table = normalize_to_freq_table(table_candidate, sim_data_path, params);
            sim_data_all = build_sim_data_from_table(freq_table, params);
            [feature_table, sim_data_all] = extract_features_batch(sim_data_all, params);
            feature_table = ensure_feature_columns(feature_table);
            return;
        end

        if isfield(loaded, 'sim_data') && isstruct(loaded.sim_data)
            sim_data_all = loaded.sim_data;
            [feature_table, sim_data_all] = extract_features_batch(sim_data_all, params);
            feature_table = ensure_feature_columns(feature_table);
            return;
        end

        error('Unsupported MAT content: feature_table/sim_data/table not found (%s).', sim_data_path);
    end

    if strcmp(ext, '.csv')
        freq_table = load_sparam_table(sim_data_path, params);
        sim_data_all = build_sim_data_from_table(freq_table, params);
        [feature_table, sim_data_all] = extract_features_batch(sim_data_all, params);
        feature_table = ensure_feature_columns(feature_table);
        return;
    end
end

cp_candidates = {
    fullfile(project_root, 'cp_caseA.csv'), fullfile(project_root, 'cp_caseB.csv'), fullfile(project_root, 'cp_caseC.csv');
    fullfile(project_root, 'data', 'raw', 'cp_caseA.csv'), fullfile(project_root, 'data', 'raw', 'cp_caseB.csv'), fullfile(project_root, 'data', 'raw', 'cp_caseC.csv')
};

feature_table = table();
sim_data_all = struct([]);
has_any = false;

for row_idx = 1:size(cp_candidates, 1)
    paths = cp_candidates(row_idx, :);
    if all(cellfun(@isfile, paths))
        has_any = true;
        for idx = 1:numel(paths)
            freq_table_i = load_sparam_table(paths{idx}, params);
            sim_data_i = build_sim_data_from_table(freq_table_i, params);
            [feature_i, sim_data_i] = extract_features_batch(sim_data_i, params);
            feature_i = ensure_feature_columns(feature_i);
            if isempty(feature_table)
                feature_table = feature_i;
                sim_data_all = sim_data_i;
            else
                feature_table = [feature_table; feature_i]; %#ok<AGROW>
                sim_data_all = merge_sim_data(sim_data_all, sim_data_i, params);
            end
        end
        break;
    end
end

if ~has_any
    error(['No valid input found. Provide data/raw/<dataset>.mat or cp_caseA/B/C.csv ' ...
        '(project root or data/raw).']);
end
end

function table_out = find_table_in_struct(loaded)
% FIND_TABLE_IN_STRUCT Find first table variable in loaded MAT struct.
table_out = [];
fields = fieldnames(loaded);
for idx = 1:numel(fields)
    value = loaded.(fields{idx});
    if istable(value)
        table_out = value;
        return;
    end
end
end

function freq_table = normalize_to_freq_table(table_in, source_path, params)
% NORMALIZE_TO_FREQ_TABLE Convert arbitrary table into standardized freq_table.
if all(ismember({'x_coord_mm', 'y_coord_mm', 'freq_ghz', 'S21_rx1', 'S21_rx2', 'group_id'}, table_in.Properties.VariableNames))
    freq_table = table_in;
    return;
end

tmp_csv = [tempname '.csv'];
cleanup_obj = onCleanup(@() safe_delete(tmp_csv));
writetable(table_in, tmp_csv);
freq_table = load_sparam_table(tmp_csv, params);
if isempty(freq_table)
    error('Failed to normalize table from source: %s', source_path);
end
clear cleanup_obj;
safe_delete(tmp_csv);
end

function feature_table = ensure_feature_columns(feature_table)
% ENSURE_FEATURE_COLUMNS Ensure phase-2 required columns exist.
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

function safe_delete(path_str)
% SAFE_DELETE Delete temporary file if it exists.
if isfile(path_str)
    delete(path_str);
end
end
