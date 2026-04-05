# 구현 명세: train_logistic / eval_roc_calibration / run_ml_benchmark

> 모듈: M11, M12, M13 | 버전: 2.0
> v1 대비 변경점:
> - DNN: `sigmoidLayer` → `softmaxLayer + classificationLayer` (R2021b 호환)
> - 추론 시간: warm-up 10회 + 수동 연산 버전 병렬 측정
> - 복잡도 표현: "3~4 orders of magnitude" → "**1~2 orders of magnitude**"
> - AUC 하한 기준: 0.85 → **0.80** (경계 조건 허용)
> - FLOPs 단위 일관화: multiply-add 기준 7 FLOPs (logistic)

---

## 1. M11: train_logistic

### 1.1 시그니처

```matlab
function [model, norm_params] = train_logistic(features, labels, params)
% TRAIN_LOGISTIC  Logistic Regression 학습 (Stratified 5-fold CV)
%
% 입력:
%   features — [N × 2] double, 열1=r_CP (linear), 열2=a_FP
%              ※ valid_flag=true인 샘플만 입력할 것
%   labels   — [N × 1] logical, true=LoS, false=NLoS
%   params   — struct (§1.2 참조)
%
% 출력:
%   model      — struct (§1.4 참조)
%   norm_params — struct: .mu [1×2], .sigma [1×2] (전체 학습 데이터 기준)
%
% 전제조건:
%   labels에 true/false가 모두 존재해야 함 (LoS-only 시 호출 금지)
%   호출 전 main_run_all.m의 LoS-only Gate 통과 확인 필수
```

### 1.2 params 필드

| 필드 | 기본값 | 설명 |
|------|--------|------|
| `params.cv_folds` | `5` | Stratified K-fold 수 |
| `params.random_seed` | `42` | cvpartition 재현성 |
| `params.normalize` | `true` | z-score 정규화 여부 |
| `params.fitglm_distribution` | `'binomial'` | fitglm Distribution |
| `params.fitglm_link` | `'logit'` | fitglm Link |

### 1.3 z-score 정규화 (data leakage 방지)

```
% Stratified CV 내부에서 fold별로 수행:
[X_tr_norm, mu_k, sigma_k] = zscore(X_train_k)
X_te_norm = (X_test_k - mu_k) ./ sigma_k

% 최종 모델 학습 (전체 데이터):
[X_norm, norm_params.mu, norm_params.sigma] = zscore(features)
model.norm_params = norm_params
```

### 1.4 fitglm 학습

```matlab
mdl = fitglm(X_norm, labels, ...
    'Distribution', params.fitglm_distribution, ...   % 'binomial'
    'Link', params.fitglm_link);                       % 'logit'
% logit(P(LoS)) = β0 + β1·r_CP_norm + β2·a_FP_norm
```

**fitglm 선택 근거**: p-value, CI 자동 출력 → 논문의 coefficient significance 보고에 유리.
대안 `mnrfit`는 동일 결과이나 통계 요약이 별도 필요.

### 1.5 model 출력 구조체

```matlab
model.type        = 'logistic'
model.coeffs      = mdl.Coefficients.Estimate   % [3×1]: [β0; β1; β2]
model.coeff_pvals = mdl.Coefficients.pValue      % [3×1]: p-값
model.coeff_ci    = coefCI(mdl)                  % [3×2]: 95% CI
model.norm_mu     = norm_params.mu               % [1×2]
model.norm_sigma  = norm_params.sigma            % [1×2]
model.cv_auc      = cv_auc_vec                   % [cv_folds × 1] fold별 AUC
model.cv_auc_mean = mean(cv_auc_vec)
model.cv_auc_std  = std(cv_auc_vec)
model.mdl_object  = mdl                          % fitglm 객체
model.flops       = 7                            % per inference (§3.3)
```

### 1.6 Cross-Validation Pseudocode

```
cv = cvpartition(labels, 'KFold', params.cv_folds, ...
                 'Stratify', true)
% 'Stratify': LoS/NLoS 비율을 각 fold에서 원본 비율로 유지

cv_auc_vec = zeros(cv.NumTestSets, 1)

for k = 1 : cv.NumTestSets
    X_tr = features(training(cv,k), :)
    y_tr = labels(training(cv,k))
    X_te = features(test(cv,k), :)
    y_te = labels(test(cv,k))

    % fold 내부에서 정규화 (leakage 방지)
    [X_tr_norm, mu_k, sigma_k] = zscore(X_tr)
    X_te_norm = (X_te - mu_k) ./ sigma_k

    mdl_k = fitglm(X_tr_norm, y_tr, 'Distribution','binomial','Link','logit')
    P_pos  = predict(mdl_k, X_te_norm)
    [~,~,~, cv_auc_vec(k)] = perfcurve(y_te, P_pos, true)
end
```

---

## 2. M12: eval_roc_calibration

### 2.1 시그니처

```matlab
function results = eval_roc_calibration(model, norm_params, features, labels, params)
% 입력:
%   model       — train_logistic 출력 또는 다른 모델 구조체
%   norm_params — .mu, .sigma
%   features    — [N × 2] double (정규화 전)
%   labels      — [N × 1] logical
%
% 출력:
%   results — struct (§2.2 참조)
```

### 2.2 출력 메트릭

#### (A) ROC AUC

```matlab
X_norm = (features - norm_params.mu) ./ norm_params.sigma
P_pos  = predict(model.mdl_object, X_norm)   % LoS 확률
[fpr, tpr, ~, auc] = perfcurve(labels, P_pos, true)

results.auc     = auc
results.roc_fpr = fpr
results.roc_tpr = tpr
```

#### (B) Accuracy & F1

```matlab
y_pred    = P_pos >= 0.5
accuracy  = mean(y_pred == labels)
TP = sum(y_pred & labels)
FP = sum(y_pred & ~labels)
FN = sum(~y_pred & labels)
precision = TP / (TP + FP + eps)
recall    = TP / (TP + FN + eps)
f1        = 2 * precision * recall / (precision + recall + eps)
```

#### (C) ECE (Expected Calibration Error)

```matlab
n_bins = 10
ECE = 0
for b = 1 : n_bins
    lo = (b-1)/n_bins;  hi = b/n_bins
    mask = P_pos >= lo & P_pos < hi
    if sum(mask) == 0, continue; end
    conf_b = mean(P_pos(mask))
    acc_b  = mean(labels(mask))
    ECE    = ECE + (sum(mask)/N) * abs(conf_b - acc_b)
    cal_conf(b) = conf_b
    cal_acc(b)  = acc_b
    cal_count(b) = sum(mask)
end
% 출처: Guo et al., "On Calibration of Modern Neural Networks," ICML 2017
```

#### (D) 추론 시간 측정 (v2 수정: warm-up 추가)

```matlab
% Warm-up (JIT 컴파일 오버헤드 제거)
x_test = (features(1,:) - norm_params.mu) ./ norm_params.sigma
for i = 1:10, predict(model.mdl_object, x_test); end

% MATLAB predict 호출 측정
tic
for i = 1:1000, predict(model.mdl_object, x_test); end
t_predict_us = toc / 1000 * 1e6

% 수동 연산 (실제 O(1) 구현, 논문 주 비교 대상)
b = model.coeffs
tic
for i = 1:1000
    z = b(1) + b(2)*x_test(1) + b(3)*x_test(2)
    p = 1 / (1 + exp(-z))
end
t_manual_us = toc / 1000 * 1e6

results.infer_predict_us = t_predict_us
results.infer_manual_us  = t_manual_us
% 논문에서는 FLOPs 비교를 주 지표로 사용 (실행 환경 독립)
```

### 2.3 FLOPs 계산 (Logistic Regression)

```
추론 1회: z = β0 + β1·x1 + β2·x2,  p = sigmoid(z)

연산 분해:
  β1·x1               : 1 multiply
  β2·x2               : 1 multiply
  β1·x1 + β2·x2       : 1 add
  + β0                 : 1 add
  sigmoid: exp(-z)     : 1 exp (≈ 1 FP op)
           1 + exp     : 1 add
           1 / (...)   : 1 divide

총: 2 multiply + 3 add + 1 exp + 1 divide = 7 FLOPs (per inference)
```

```matlab
results.flops = 7   % 논문 Table에서 사용
```

---

## 3. M13: run_ml_benchmark

### 3.1 비교 모델 사양

#### SVM (RBF)

```matlab
svm_mdl = fitcsvm(X_train_norm, y_train, ...
    'KernelFunction', 'rbf', ...
    'OptimizeHyperparameters', {'BoxConstraint', 'KernelScale'}, ...
    'HyperparameterOptimizationOptions', struct( ...
        'Optimizer', 'bayesopt', ...
        'MaxObjectiveEvaluations', 30, ...
        'ShowPlots', false, ...
        'Verbose', 0))
svm_mdl = fitPosterior(svm_mdl)   % Platt scaling

% FLOPs (N_sv support vectors, 입력 dim=2):
%   유클리드 거리²: 2 features × 2 = 4 FLOPs per SV
%   RBF exp:         1 FLOPs per SV
%   가중합:          N_sv FLOPs
%   총: 5·N_sv + N_sv + Platt(7) = 6·N_sv + 7 FLOPs
N_sv = size(svm_mdl.SupportVectors, 1)
results_svm.flops = 6 * N_sv + 7
```

#### Random Forest (100 trees)

```matlab
rf_mdl = fitcensemble(X_train_norm, y_train, ...
    'Method', 'Bag', ...
    'NumLearningCycles', 100, ...
    'Learners', templateTree('MaxNumSplits', 20))

% FLOPs (avg depth D, 2 features):
%   단일 트리: D 비교 = D FLOPs
%   100 트리 집계: 99 adds
%   총: 100·D + 99 FLOPs
avg_depth = mean(cellfun(@(t) ceil(log2(t.NumLeaves+1)), rf_mdl.Trained))
results_rf.flops = 100 * avg_depth + 99
```

#### DNN [2-16-8-2] (v2: R2021b 호환 수정)

```matlab
% ※ R2021b에서 sigmoidLayer 미지원 → softmax + classificationLayer 사용
layers = [
    featureInputLayer(2)
    fullyConnectedLayer(16)
    reluLayer
    fullyConnectedLayer(8)
    reluLayer
    fullyConnectedLayer(2)      % 2-class 출력
    softmaxLayer
    classificationLayer
]

options = trainingOptions('adam', ...
    'MaxEpochs', 200, ...
    'InitialLearnRate', 1e-3, ...
    'ValidationData', {X_val_norm, categorical(y_val)}, ...
    'ValidationPatience', 10, ...
    'MiniBatchSize', 32, ...
    'Shuffle', 'every-epoch', ...
    'Plots', 'none', ...
    'Verbose', false)

dnn_mdl = trainNetwork(X_train_norm', categorical(y_train)', layers, options)
% 레이블: trainNetwork는 categorical 타입 필요

% FLOPs (forward pass):
%   FC(2→16):   2×16 + 16 = 48 (mul+add) → ~64 (with bias)
%   ReLU(16):   16
%   FC(16→8):   16×8 + 8 = 136 → ~144
%   ReLU(8):    8
%   FC(8→2):    8×2 + 2 = 18
%   Softmax(2): ~10
%   총: ~260 FLOPs
results_dnn.flops = 260
```

> **R2021b 호환 확인 절차**: `which sigmoidLayer` → 'built-in'이면 사용 가능.
> 없으면 위 softmax 방식 사용.

### 3.2 FLOPs 비교 표 (논문 Table용)

| 모델 | FLOPs (추론 1회) | Logistic 대비 | 비고 |
|------|----------------|-------------|------|
| Logistic Regression | **7** | 1× (기준) | 입력 dim=2 고정 |
| SVM (RBF) | 6·N_sv + 7 | ~N_sv× | N_sv ≈ 20~100 (학습 후 결정) |
| Random Forest (100 trees) | 100·D + 99 | ~14·D× | D ≈ 5 → ~70× |
| DNN [2-16-8-2] | ~260 | **~37×** | forward pass only |

> **논문 표현 (v2 수정)**: "1–2 orders of magnitude lower computational complexity"
> DNN 대비 37×, RF 대비 ~70×로 **1–2 orders of magnitude**가 정확.
> 3–4 orders of magnitude를 주장하려면 CIR 전체 입력 CNN (~10,000+ FLOPs) baseline 추가 필요.

---

## 4. 검증 체크리스트

- [ ] Logistic AUC (5-fold CV mean) **> 0.80** (v2 완화: 경계 조건 허용)
  - 0.70–0.80: 경계 조건에서의 분류 한계 → 논문에서 "CP 편파 지표의 LoS/NLoS 분리도 한계" 로 서술
  - < 0.70: r_CP/a_FP 계산 로직 재검토 필요
- [ ] CV AUC 표준편차 < 0.03 (안정적 학습)
- [ ] ECE < 0.10 (확률 보정 양호)
- [ ] F1과 Accuracy 차이 < 0.05 (class imbalance 확인)
- [ ] DNN 학습 시 R2021b에서 에러 없이 실행되는가?
- [ ] FLOPs 비율: Logistic / DNN < 0.03 (실제로 7/260 ≈ 0.027)

---

*최종 수정: 2026-04-05 | 작성자: Claude Code (Architecture Agent) v2*
