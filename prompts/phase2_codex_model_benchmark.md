# Phase 2: Codex — Logistic Regression + ML Benchmark 구현 프롬프트

## 역할
너는 MATLAB 코드 구현 전문가이다. 아래 명세(spec)를 정확히 따라 구현하라.

## 구현 환경
- MATLAB R2021b 이상
- 허용 Toolbox: Statistics and Machine Learning Toolbox, Deep Learning Toolbox
- 이전 Phase에서 구현된 함수 사용 가능: extract_rcp.m, extract_afp.m, detect_first_path.m

## 선행 데이터
- data/processed/features_SIM1.mat (또는 .csv)
- 컬럼: position_id, r_CP, a_FP, label, scenario, distance_m
- label: true=LoS, false=NLoS

---

### 파일 1: src/train_logistic.m

```
function [model, norm_params] = train_logistic(features, labels, params)
% TRAIN_LOGISTIC  Binary Logistic Regression 학습
%
% 입력:
%   features - [N × 2] double, 각 행 = [r_CP, a_FP]
%   labels   - [N × 1] logical, true=LoS
%   params   - struct:
%     .normalize    = true          (z-score 정규화 여부)
%     .cv_folds     = 5             (Stratified K-fold)
%     .random_seed  = 42
%
% 출력:
%   model       - struct:
%     .coefficients  [3×1]  (intercept, beta_rcp, beta_afp)
%     .cv_auc        scalar (cross-validated ROC AUC)
%     .cv_accuracy   scalar
%   norm_params - struct:
%     .mean_rcp, .std_rcp, .mean_afp, .std_afp
%
% 구현 요구사항:
%   1. r_CP에 log10 변환 적용 (분포 정규화, r_CP>0 확인)
%   2. z-score 정규화: (x - mean) / std, mean/std는 학습 데이터에서 계산
%   3. fitglm(tbl, 'label ~ rcp_norm + afp_norm', 'Distribution', 'binomial')
%   4. Stratified 5-fold CV: cvpartition(labels, 'KFold', 5)로 분할
%      각 fold에서 AUC 계산 → 평균 AUC 반환
%   5. 전체 데이터로 최종 모델 재학습
```

---

### 파일 2: src/eval_roc_calibration.m

```
function results = eval_roc_calibration(model, norm_params, features, labels, params)
% EVAL_ROC_CALIBRATION  모델 성능 평가 (ROC, Calibration, ECE)
%
% 출력:
%   results - struct:
%     .roc         - struct (fpr, tpr, auc, thresholds)
%     .accuracy    - scalar (optimal threshold 기준)
%     .f1          - scalar
%     .precision   - scalar
%     .recall      - scalar
%     .ece         - scalar (Expected Calibration Error, 10 bins)
%     .cal_curve   - struct (mean_predicted, fraction_positive, bin_count)
%     .flops       - scalar (single inference FLOPs)
%
% 구현 요구사항:
%   1. 정규화 적용 (norm_params 사용, 학습 데이터 기준)
%   2. ROC: perfcurve(labels, predicted_prob, true)
%   3. Optimal threshold: Youden's J = max(TPR - FPR)
%   4. ECE 계산:
%      - 예측 확률을 10개 등간격 bin [0,0.1), [0.1,0.2), ..., [0.9,1.0]으로 분할
%      - 각 bin의 평균 예측 확률과 실제 positive 비율 차이의 가중 평균
%      - ECE = sum(n_bin/N * |avg_pred_bin - frac_pos_bin|)
%   5. FLOPs 계산: Logistic = 2 mul + 1 add + 1 exp + 1 div = 5 FLOPs
```

---

### 파일 3: src/run_ml_benchmark.m

```
function benchmark_results = run_ml_benchmark(features, labels, params)
% RUN_ML_BENCHMARK  4개 모델 비교 벤치마크
%
% 비교 모델:
%   1. Logistic Regression (본 연구 제안)
%   2. SVM (RBF kernel)
%   3. Random Forest (100 trees)
%   4. DNN (2 hidden layers: 16-8, ReLU)
%
% 출력:
%   benchmark_results - table with columns:
%     model_name    [string]
%     auc           [double]  - 5-fold CV ROC AUC
%     accuracy      [double]  - 5-fold CV Accuracy
%     f1            [double]
%     ece           [double]
%     flops         [double]  - single inference FLOPs
%     n_parameters  [double]  - 모델 파라미터 수
%     train_time_s  [double]  - 학습 소요 시간 [초]
%     infer_time_us [double]  - 단일 추론 소요 시간 [μs], 1000회 평균
%
% 구현 요구사항:
%   모든 모델은 동일한 5-fold split을 사용 (공정 비교)
%   fold split: rng(params.random_seed); cv = cvpartition(labels,'KFold',5)
%
%   SVM 세부:
%     mdl = fitcsvm(X, y, 'KernelFunction','rbf', 'Standardize',true, ...
%                   'OptimizeHyperparameters','auto', ...
%                   'HyperparameterOptimizationOptions', struct('MaxObjectiveEvaluations',30))
%     FLOPs = N_sv × (2×D + 1) + 1  (D=2, N_sv=학습 후 support vector 수)
%     n_parameters = N_sv × D + N_sv + 1
%
%   Random Forest 세부:
%     mdl = fitcensemble(X, y, 'Method','Bag','NumLearningCycles',100, ...
%                        'Learners', templateTree('MaxNumSplits',20))
%     FLOPs = 100 × avg_tree_depth × 1  (비교 연산)
%     n_parameters = sum of all tree nodes
%
%   DNN 세부:
%     layers = [featureInputLayer(2)
%               fullyConnectedLayer(16), reluLayer
%               fullyConnectedLayer(8), reluLayer
%               fullyConnectedLayer(2), softmaxLayer, classificationLayer]
%     options = trainingOptions('adam','MaxEpochs',100,'MiniBatchSize',32, ...
%               'Verbose',false,'Plots','none')
%     FLOPs = (2×16 + 16) + (16×8 + 8) + (8×2 + 2) = 194 FLOPs
%     n_parameters = (2×16+16) + (16×8+8) + (8×2+2) = 194
%
%   추론 시간 측정:
%     tic; for i=1:1000, predict(mdl, X(1,:)); end; t=toc;
%     infer_time_us = t / 1000 * 1e6;
```

---

### 파일 4: src/run_ablation.m

```
function ablation_results = run_ablation(features, labels, params)
% RUN_ABLATION  r_CP only / a_FP only / Combined 비교
%
% 출력:
%   ablation_results - table:
%     config        [string]  - 'r_CP_only', 'a_FP_only', 'combined'
%     auc           [double]
%     accuracy      [double]
%     f1            [double]
%     ece           [double]
%     delta_auc_vs_combined [double]  - combined 대비 AUC 차이
%
% 구현 요구사항:
%   - r_CP_only: features(:,1)만 사용, Logistic Regression
%   - a_FP_only: features(:,2)만 사용, Logistic Regression
%   - combined:  features(:,1:2) 모두 사용
%   - 동일 5-fold split 사용
%   - 각 config에서 train_logistic 호출 (features 컬럼만 변경)
```

---

### 파일 5: src/generate_figures.m

```
function generate_figures(feature_table, model, results, benchmark, ablation, params)
% GENERATE_FIGURES  논문용 Figure 일괄 생성
%
% 생성할 Figure 목록 (ISAP 2~4p 기준):
%
% Figure 1: 2D Scatter Plot (r_CP vs a_FP, LoS/NLoS 색상 구분)
%   - x축: log10(r_CP), y축: a_FP
%   - LoS: blue circle, NLoS: red cross
%   - Logistic regression decision boundary 오버레이 (P=0.5 등고선)
%   - 폰트: 12pt, 축 레이블 포함, grid on
%   - 저장: results/figures/fig1_scatter_2d.pdf, .fig, .png (300dpi)
%
% Figure 2: ROC Curve (4개 모델 비교)
%   - Logistic: solid blue, SVM: dashed red, RF: dotted green, DNN: dashdot magenta
%   - 범례에 AUC 수치 포함: "Logistic (AUC=0.XX)"
%   - diagonal reference line (gray)
%   - 저장: results/figures/fig2_roc_comparison.pdf
%
% Figure 3: Accuracy vs FLOPs (4개 모델 scatter)
%   - x축: FLOPs (log scale), y축: Accuracy [%]
%   - 각 점에 모델 이름 annotation
%   - 저장: results/figures/fig3_accuracy_vs_flops.pdf
%
% Figure 4 (optional, 지면 허용 시): Calibration Reliability Diagram
%   - x축: Mean predicted probability, y축: Fraction of positives
%   - 10 bins, 각 bin에 bar 또는 점
%   - perfect calibration line (diagonal)
%   - 저장: results/figures/fig4_calibration.pdf
%
% 공통 요구사항:
%   - 모든 Figure: figure('Units','centimeters','Position',[0 0 8.5 7])
%     (ISAP single-column width ≈ 8.5cm)
%   - 폰트: 'Times New Roman', 10pt (축 레이블), 9pt (범례)
%   - exportgraphics(gcf, filepath, 'Resolution', 300)
%   - .fig 파일도 함께 저장 (수정 편의)
```

## 코드 품질 요구사항 (Phase 1과 동일)
- 모든 함수 첫 줄에 one-line summary
- magic number 금지
- 재현성: rng(params.random_seed) 모든 랜덤 연산 앞에 호출
- 결과 저장: results/ 디렉토리에 .mat + .csv 양쪽으로 저장
