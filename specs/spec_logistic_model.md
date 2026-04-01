# 구현 명세: train_logistic.m / eval_model.m

> 모듈: M04 (train_models), M05 (eval_model) | 의존: M03 (split_dataset) | 버전: 1.0

---

## 1. 학습 함수: train_logistic

### 1.1 시그니처

```matlab
model = train_logistic(features, labels, params)
```

### 1.2 입력

| 인자 | 타입 | 차원 | 설명 |
|------|------|------|------|
| `features` | double | [N × 2] | 열1=r_CP (linear), 열2=a_FP |
| `labels` | logical | [N × 1] | 0=NLoS, 1=LoS |
| `params.cv_folds` | uint8 | scalar | CV fold 수 (기본값: 5) |
| `params.regularization` | char | — | 'ridge' (L2) 또는 'lasso' (L1), 기본값: 'ridge' |

### 1.3 정규화 (z-score)

```
μ_r  = mean(features(:,1))   % 학습 데이터 기준
σ_r  = std(features(:,1))
μ_a  = mean(features(:,2))
σ_a  = std(features(:,2))

X_norm(:,1) = (features(:,1) - μ_r) / σ_r
X_norm(:,2) = (features(:,2) - μ_a) / σ_a
```

**중요**: μ, σ는 **학습 fold에서만** 계산하고, 테스트 fold에 동일하게 적용 (data leakage 방지).

### 1.4 학습 방법: MATLAB fitglm

```matlab
mdl = fitglm(X_norm, labels, ...
    'Distribution', 'binomial', ...
    'Link', 'logit');
% 모델: logit(P(LoS)) = β0 + β1·r_CP_norm + β2·a_FP_norm
```

**fitglm vs mnrfit 선택 근거:**
- `fitglm`: 자동 통계 요약 (p-value, CI) 제공 → 논문의 coefficient significance 보고에 유리.
- `mnrfit`: 다중 클래스 확장 가능하나 2-class에서는 동일 결과.
- **채택: fitglm** (단, mnrfit로 재현성 확인 권장).

### 1.5 출력 구조체

```matlab
model.type        = 'logistic'
model.coeffs      = mdl.Coefficients.Estimate   % [3×1]: [β0; β1; β2]
model.coeff_pvals = mdl.Coefficients.pValue      % [3×1]: p-값
model.norm_mu     = [μ_r, μ_a]                  % [1×2]: 정규화 평균
model.norm_sigma  = [σ_r, σ_a]                  % [1×2]: 정규화 표준편차
model.mdl_object  = mdl                          % fitglm 객체 (선택적 저장)
```

---

## 2. Cross-Validation: Stratified 5-Fold

### 2.1 구현 방법

```
% MATLAB cvpartition으로 Stratified 분할
cv = cvpartition(labels, 'KFold', 5, 'Stratify', true)

for k = 1 : cv.NumTestSets
    train_idx = training(cv, k)
    test_idx  = test(cv, k)

    X_tr = features(train_idx, :)
    y_tr = labels(train_idx)
    X_te = features(test_idx, :)
    y_te = labels(test_idx)

    % 정규화: 학습 fold 기준
    [X_tr_norm, mu, sigma] = zscore(X_tr)
    X_te_norm = (X_te - mu) ./ sigma

    % 학습
    model_k = train_logistic(X_tr_norm, y_tr, params)

    % 평가
    results_k(k) = eval_model(model_k, X_te_norm, y_te)
end

% 평균 ± 표준편차 보고
mean_auc = mean([results_k.auc])
std_auc  = std([results_k.auc])
```

### 2.2 Stratified의 이유

LoS/NLoS 비율이 불균등할 경우 fold 간 class imbalance 편차 발생. `'Stratify', true`로 각 fold가 원본 class 비율을 유지하도록 강제.

---

## 3. 평가 함수: eval_model

### 3.1 시그니처

```matlab
results = eval_model(model, features_norm, labels)
```

### 3.2 출력 메트릭

#### (A) ROC AUC

```matlab
[~, ~, ~, auc] = perfcurve(labels, P_pos, 1)
% P_pos: 모델의 LoS 확률 예측값 [N×1]
```

#### (B) Accuracy

```matlab
y_pred   = double(P_pos >= 0.5)    % 임계값 0.5
accuracy = mean(y_pred == labels)
```

#### (C) F1-score

```matlab
TP = sum(y_pred == 1 & labels == 1)
FP = sum(y_pred == 1 & labels == 0)
FN = sum(y_pred == 0 & labels == 1)
precision = TP / (TP + FP)
recall    = TP / (TP + FN)
f1        = 2 * precision * recall / (precision + recall)
```

#### (D) ECE (Expected Calibration Error)

```
% 10개 구간 [0, 0.1), [0.1, 0.2), ..., [0.9, 1.0]
n_bins = 10
for b = 1 : n_bins
    bin_mask  = (P_pos >= (b-1)/n_bins) & (P_pos < b/n_bins)
    if sum(bin_mask) == 0, continue; end
    conf_b    = mean(P_pos(bin_mask))         % 평균 예측 신뢰도
    acc_b     = mean(labels(bin_mask))        % 실제 정확도
    ECE += (sum(bin_mask) / N) * abs(conf_b - acc_b)
end
```

출처: Guo, C. et al., "On Calibration of Modern Neural Networks," *ICML*, 2017.

#### (E) Calibration Curve 데이터

```matlab
results.cal_bins = [conf_b_array, acc_b_array]   % [10 × 2]
```

### 3.3 연산 복잡도 (FLOPs)

**Logistic Regression 추론 FLOPs 계산:**

```
입력: x = [r_CP_norm, a_FP_norm]  (2 features)
연산: z = β0 + β1·x1 + β2·x2
      P = 1 / (1 + exp(-z))

FLOPs 분해:
  β1·x1          : 1 multiply
  β2·x2          : 1 multiply
  β1·x1 + β2·x2  : 1 add
  + β0            : 1 add
  sigmoid(z)      : 1 exp + 2 add + 1 div ≈ 4 ops (exp는 1 FLOP으로 근사)

총계: 2 multiply + 2 add + 1 sigmoid ≈ 5~8 FLOPs (추론 1회 기준)
```

> 정밀 계산: sigmoid = exp(-z) + 1 + divide = 3 ops → 총 7 FLOPs.
> 비교 목적으로는 **5 FLOPs** (multiply-add 기준) 또는 **7 FLOPs** (모든 op) 중 일관성 있게 선택.

```matlab
results.flops = 7   % per inference, 추론 1회
```

---

## 4. 비교 ML 모델 사양

### 4.1 SVM

```matlab
% 학습
svm_model = fitcsvm(X_train_norm, y_train, ...
    'KernelFunction', 'rbf', ...
    'OptimizeHyperparameters', {'BoxConstraint', 'KernelScale'}, ...
    'HyperparameterOptimizationOptions', struct('Optimizer', 'bayesopt', ...
        'MaxObjectiveEvaluations', 30, ...
        'ShowPlots', false))

% 확률 출력을 위한 Platt scaling
svm_model = fitPosterior(svm_model)
```

**FLOPs 계산 (RBF-SVM, N_sv 개 support vector 기준):**
```
각 support vector 연산:
  - 유클리드 거리²: 2(features) × 2 ops = 4 FLOPs
  - RBF 지수:       1 exp + 1 multiply = 2 FLOPs
  subtotal per SV:  6 FLOPs

총 추론 FLOPs ≈ N_sv × 6 + N_sv (가중합) + 1 (부호) + Platt 보정 7
             = 7·N_sv + 8 FLOPs
```
→ N_sv는 학습 후 `svm_model.SupportVectors` 행 수로 측정.

```matlab
results.flops = 7 * size(svm_model.SupportVectors, 1) + 8
```

---

### 4.2 Random Forest

```matlab
rf_model = fitcensemble(X_train_norm, y_train, ...
    'Method', 'Bag', ...
    'NumLearningCycles', 100, ...
    'Learners', templateTree('MaxNumSplits', 20))
```

**FLOPs 계산 (100 trees, 평균 depth D, 2 features):**
```
단일 트리 추론:
  각 노드: feature 비교 1 op × depth D
  subtotal: D FLOPs/tree

100 트리 평균 집계:
  100 predictions + 99 adds = 199 FLOPs

총 FLOPs ≈ 100 × D + 199
```
→ D는 `max([rf_model.Trained{:}.NumNodes])` 로 추정 (upper bound).
→ 평균 depth는 `log2(MaxNumSplits)` ≈ 4–5로 근사.

```matlab
avg_depth = mean(cellfun(@(t) t.Depth, rf_model.Trained))
results.flops = 100 * avg_depth + 199
```

---

### 4.3 DNN

```matlab
% 아키텍처: [2] → [16] → [8] → [1]
layers = [
    featureInputLayer(2)
    fullyConnectedLayer(16)
    reluLayer()
    fullyConnectedLayer(8)
    reluLayer()
    fullyConnectedLayer(1)
    sigmoidLayer()
]

options = trainingOptions('adam', ...
    'MaxEpochs', 200, ...
    'InitialLearnRate', 1e-3, ...
    'ValidationData', {X_val_norm, y_val}, ...
    'ValidationPatience', 10, ...    % Early stopping
    'MiniBatchSize', 32, ...
    'Shuffle', 'every-epoch', ...
    'Plots', 'none', ...
    'Verbose', false)

dnn_model = trainNetwork(X_train_norm', y_train', layers, options)
```

**FLOPs 계산 (추론 1회, forward pass만):**
```
Layer 1: FC(2→16)   : 2×16 multiply + 16 add + 16 bias = 2×16 + 16 + 16 = 80 FLOPs
Layer 2: ReLU(16)   : 16 FLOPs (max 연산)
Layer 3: FC(16→8)   : 16×8 + 8 + 8 = 144 FLOPs
Layer 4: ReLU(8)    : 8 FLOPs
Layer 5: FC(8→1)    : 8×1 + 1 + 1 = 10 FLOPs
Layer 6: Sigmoid(1) : 7 FLOPs (exp 기준)

총 FLOPs ≈ 80 + 16 + 144 + 8 + 10 + 7 = 265 FLOPs
```

```matlab
results.flops = 265   % per inference (2-16-8-1 구조 고정)
```

---

## 5. FLOPs 비교 요약 (논문 Table용)

| 모델 | 추론 FLOPs | 비고 |
|------|-----------|------|
| Logistic Regression | ~7 | 입력 dim=2 고정 |
| SVM (RBF) | ~7·N_sv + 8 | N_sv: 학습 후 결정 |
| Random Forest (100 trees) | ~100·D + 199 | D: 평균 트리 depth |
| DNN [2-16-8-1] | ~265 | forward pass만 |

> Logistic 대비 복잡도 비: SVM × (N_sv), RF × (100·D/7), DNN × 38.
> 예: N_sv=50이면 SVM은 Logistic의 ~51배; D=5이면 RF는 ~72배.

---

## 6. 결과 저장 구조

```matlab
results.(model_name).auc          % scalar [0–1]
results.(model_name).accuracy     % scalar [0–1]
results.(model_name).f1           % scalar [0–1]
results.(model_name).ece          % scalar [0–1]
results.(model_name).flops        % scalar (integer)
results.(model_name).roc_fpr      % [K×1] double
results.(model_name).roc_tpr      % [K×1] double
results.(model_name).cal_bins     % [10×2] double [conf, acc]
results.(model_name).cv_auc_std   % scalar (5-fold std)
```

---

## 7. 검증 체크리스트

- [ ] Logistic AUC: SIM1 기준 > 0.85 (그 이하면 r_CP/a_FP 분별력 부족, M02 파라미터 재검토)
- [ ] FLOPs 비율: Logistic / DNN < 0.05 (3자릿수 이상 차이)
- [ ] ECE: Logistic < 0.10 (잘 보정된 확률 출력)
- [ ] F1 macro: 모든 모델에서 accuracy와 ±0.05 이내 (class imbalance 확인)
- [ ] CV std: AUC 표준편차 < 0.03 (안정적 학습)

---

*최종 수정: 2026-04-01 | 작성자: Claude Code (Architecture Agent)*
