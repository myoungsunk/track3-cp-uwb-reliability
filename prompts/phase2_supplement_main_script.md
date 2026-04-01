# Phase 2 보충: Codex — Main Script 구현 프롬프트

## 역할
이 스크립트는 Track 3의 전체 분석 파이프라인을 순차 실행하는 마스터 스크립트이다.
src/ 디렉토리의 모든 함수가 이미 구현되어 있다는 전제 하에 작성하라.

## 파일: src/main_run_all.m

```matlab
%% main_run_all.m — Track 3 전체 분석 파이프라인
% 실행 전 확인사항:
%   1. data/raw/SIM1.mat (또는 SIM2.mat) 존재
%   2. src/ 디렉토리가 MATLAB path에 추가됨
%   3. results/ 및 results/figures/ 디렉토리 존재
%
% 실행: >> main_run_all

clear; clc; close all;
addpath('src');
addpath('src/private');

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

fprintf('=== Track 3 Analysis Pipeline ===\n');
fprintf('Timestamp: %s\n', datestr(now));
fprintf('Random seed: %d\n', params.random_seed);

%% ===== 1. Feature 추출 =====
fprintf('\n[1/5] Extracting features...\n');
sim_data_path = fullfile('data', 'raw', [params.dataset_name '.mat']);
feature_table = extract_features_batch(sim_data_path, params);
fprintf('  Extracted %d samples (LoS: %d, NLoS: %d)\n', ...
    height(feature_table), sum(feature_table.label), sum(~feature_table.label));

% 저장
save(fullfile('data','processed',['features_' params.dataset_name '.mat']), 'feature_table');
writetable(feature_table, fullfile('data','processed',['features_' params.dataset_name '.csv']));

%% ===== 2. Logistic Regression 학습 =====
fprintf('\n[2/5] Training Logistic Regression...\n');
features = [feature_table.r_CP, feature_table.a_FP];
labels   = feature_table.label;

[model, norm_params] = train_logistic(features, labels, params);
fprintf('  CV AUC: %.4f, CV Accuracy: %.4f\n', model.cv_auc, model.cv_accuracy);

% 상세 평가
results = eval_roc_calibration(model, norm_params, features, labels, params);
fprintf('  Test AUC: %.4f, ECE: %.4f\n', results.roc.auc, results.ece);

%% ===== 3. ML 벤치마크 =====
fprintf('\n[3/5] Running ML benchmark...\n');
benchmark = run_ml_benchmark(features, labels, params);
disp(benchmark);

%% ===== 4. Ablation Study =====
fprintf('\n[4/5] Running ablation study...\n');
ablation = run_ablation(features, labels, params);
disp(ablation);

%% ===== 5. Figure 생성 =====
fprintf('\n[5/5] Generating figures...\n');
generate_figures(feature_table, model, results, benchmark, ablation, params);
fprintf('  Figures saved to results/figures/\n');

%% ===== 6. 결과 요약 저장 =====
save(fullfile('results', 'all_results.mat'), ...
    'model', 'norm_params', 'results', 'benchmark', 'ablation', 'params');
fprintf('\n=== Pipeline Complete ===\n');

% 핵심 수치 요약 출력 (논문 작성용)
fprintf('\n--- Paper Key Numbers ---\n');
fprintf('Logistic AUC: %.3f\n', results.roc.auc);
fprintf('Logistic ECE: %.4f\n', results.ece);
fprintf('Logistic FLOPs: %d\n', results.flops);
for i = 1:height(benchmark)
    fprintf('%s: AUC=%.3f, FLOPs=%d, ratio=%.0fx\n', ...
        benchmark.model_name{i}, benchmark.auc(i), ...
        benchmark.flops(i), benchmark.flops(i)/results.flops);
end
fprintf('\nAblation:\n');
for i = 1:height(ablation)
    fprintf('  %s: AUC=%.3f (ΔAUC=%.3f)\n', ...
        ablation.config{i}, ablation.auc(i), ablation.delta_auc_vs_combined(i));
end
```

## 구현 요구사항
- 위 스크립트를 그대로 src/main_run_all.m으로 저장
- 모든 fprintf 메시지는 유지 (디버깅 및 결과 추적용)
- 중간 결과도 results/에 단계별로 저장 (파이프라인 중단 시 복구 가능)
- extract_features_batch의 PLACEHOLDER 부분은 실제 데이터에 맞게 수정 필요 (MSK가 직접)
