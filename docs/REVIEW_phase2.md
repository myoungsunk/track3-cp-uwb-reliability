# REVIEW_phase2.md — Phase 2 코드 사전 검수

> 검수 대상: M11–M15 (분류 실험, 평가, Ablation, Figure 생성)
> 검수 시점: **코드 구현 전 spec 수준 사전 검수**
> 작성일: 2026-04-05

---

## 요약

| 모듈 | Spec 완성도 | 구현 리스크 | 우선순위 |
|------|-----------|-----------|---------|
| M11 train_logistic | ✅ 완성 | 낮음 | 3 |
| M12 eval_roc_calibration | ✅ 완성 | 낮음 | 3 |
| M13 run_ml_benchmark | ⚠️ DNN R2021b | 중간 | 4 |
| M14 run_ablation | ✅ 완성 | 낮음 | 5 |
| M15 generate_figures | ⚠️ 사양 미완성 | 중간 | 4 |
| M16 main_run_all | ✅ 완성 | 낮음 | 2 |

---

## 공통 전제조건 체크리스트

모든 Phase 2 모듈은 **LoS + NLoS 데이터 모두 존재** 시에만 의미 있음.

```
[ ] M01b가 caseB/caseC 레이블 로딩에 성공했는가?
[ ] feature_table에서 valid_flag=true인 NLoS 샘플 수 ≥ 10인가?
[ ] LoS-only Gate가 올바르게 작동하여 NLoS=0 시 Phase 2 전체 skip되는가?
```

---

## M11: train_logistic

### ✅ PASS

- [x] `cvpartition`의 `'Stratify', true` 적용 → LoS/NLoS 비율 보존
- [x] fold 내부에서 독립적으로 z-score 계산 → data leakage 없음
- [x] `fitglm` 사용으로 p-value, CI 자동 출력 → 논문 coefficient 보고 용이
- [x] `rng(params.random_seed)` 필요: **구현 시 반드시 fitglm 호출 전에 추가**

### ⚠️ WARNING

**W1**: `cvpartition`의 `rng` 시드 적용 여부 불명확.
- MATLAB에서 `cvpartition`은 내부적으로 `rng` 상태를 사용.
- **조치**: `rng(params.random_seed, 'twister')` 를 `cvpartition` 호출 직전에 추가.

**W2**: `fitglm`의 수렴 실패 가능성.
- LoS/NLoS가 완벽히 선형 분리 가능할 경우 logistic regression이 발산(coefficient → ±∞).
- **조치**: `try-catch`로 감싸고, 수렴 실패 시 `'Ridge'` regularization 적용:
  ```matlab
  try
    mdl = fitglm(X, y, 'Distribution','binomial','Link','logit')
  catch e
    warning('fitglm 수렴 실패: %s. Ridge 정규화 시도.', e.message)
    mdl = fitglm(X, y, 'Distribution','binomial','Link','logit', ...
                 'Lambda', 0.01)
  end
  ```

**W3**: `predict(fitglm_object, X_test_norm)` 입력이 table인지 array인지 확인.
- `fitglm`으로 학습한 경우 `predict`의 입력은 table 또는 array 모두 가능하나 버전별 차이 있음.
- **조치**: `X_test_norm`이 matrix일 때 `array2table`로 변환하거나, predict 대신 수동 계산 사용.

### ❌ FAIL (없음)

---

## M12: eval_roc_calibration

### ✅ PASS

- [x] `perfcurve(labels, P_pos, true)` — true=LoS positive class 기준 ✅
- [x] ECE 10-bin 계산 공식 정확 (Guo et al. 2017 기준)
- [x] warm-up 10회 포함 추론 시간 측정
- [x] FLOPs = 7 (logistic, 수동 계산 기준)

### ⚠️ WARNING

**W4**: ECE에서 `bin_mask = (P_pos >= lo & P_pos < hi)` 마지막 bin 경계 처리.
- 마지막 bin (`b = n_bins`): `hi = 1.0` → `P_pos < 1.0` 이면 `P_pos = 1.0` 인 샘플이 bin에서 빠질 수 있음.
- **조치**: 마지막 bin은 `P_pos >= lo & P_pos <= hi`로 변경 (≤ 사용).

**W5**: `precision = TP / (TP + FP + eps)` 에서 `eps`가 분모를 미미하게 바꿔 F1이 부정확.
- eps = 2.2e-16이므로 실용적 영향 없으나, 논문에서 수치를 다룰 때 주의.
- **조치**: `if TP + FP == 0, precision = 0; else precision = TP/(TP+FP); end` 방식이 더 명확.

**W6**: 추론 시간 측정을 단일 샘플로 수행 (`features(1,:)`) — 배치 효율은 측정 안 함.
- 논문에서 "단일 위치 추론 시간" 임을 명시하면 문제없음.

### ❌ FAIL (없음)

---

## M13: run_ml_benchmark

### ✅ PASS

- [x] SVM Platt scaling (`fitPosterior`) 포함
- [x] RF 100 trees, bag 방식
- [x] FLOPs 계산: SVM=6·N_sv+7, RF=100·D+99, DNN≈260

### ❌ FAIL

**F1**: DNN에서 `sigmoidLayer()` 사용 시 R2021b에서 미지원.
- spec v2에서 `softmaxLayer + classificationLayer`로 수정 완료.
- **구현 시 반드시** `fullyConnectedLayer(2)` + `softmaxLayer` + `classificationLayer` 사용.
- **추가 주의**: label을 categorical로 변환 필요: `categorical(y_train)`.

**F2**: 공정 비교 미확인.
- Logistic, SVM, RF, DNN 모두 **동일한 fold split**을 사용해야 함.
- spec에서 각 모델이 독립 `cvpartition`을 생성하면 split이 달라져 비교 불공정.
- **조치**: `cv = cvpartition(labels, 'KFold', 5, 'Stratify', true)` 를 한 번만 생성하고 모든 모델에 전달.

**F3**: SVM `bayesopt` 30회 최적화가 Logistic과 RF에는 적용되지 않음.
- SVM만 hyperparameter 최적화 → SVM이 과도하게 유리한 조건.
- **논문 서술 주의**: "SVM은 hyperparameter tuning 포함, 나머지는 기본값" 명시 필요.
- 또는 SVM도 고정 hyperparameter를 사용하여 공정 비교 (단, 성능 하락 가능).

### ⚠️ WARNING

**W7**: `mean(cellfun(@(t) ceil(log2(t.NumLeaves+1)), rf_model.Trained))` RF depth 계산.
- `fitcensemble` 출력에서 `t.NumLeaves`가 존재하지 않을 수 있음.
- **조치**: `t.NumNodes` 또는 `t.Depth` 사용 (`t = rf_model.Trained{k}`); MATLAB 문서 확인.

---

## M14: run_ablation

### ✅ PASS

- [x] A1–A7 항목 체계적으로 분류
- [x] delta_auc 기준 모델(A3 combined) 대비 계산
- [x] 논문 포함 판단 기준 명시

### ⚠️ WARNING

**W8**: A5 (r_CP 정의 변경)을 구현하려면 M04 `extract_rcp`에 `params.rcp_definition` 옵션 추가 필요.
- spec_extract_features_v2.md에 해당 파라미터가 명시되어 있지 않음.
- **조치**: M04 구현 시 `params.rcp_definition = 'single'` (기본) / `'window'` 분기 추가.

**W9**: A7 (log10 scale)을 구현하려면 `extract_features_batch` 이후에 `r_CP = log10(r_CP)` 변환을 어디서 수행할지 결정 필요.
- feature_table에는 raw linear r_CP 저장, ablation 시에만 log10 변환하는 것이 clean.
- **조치**: `run_ablation` 내부에서 `r_CP_mod = log10(feat(:,1))` 로 변환 후 모델 학습.

---

## M15: generate_figures

### ⚠️ WARNING (Figure spec 작성 필요)

**W10**: `generate_figures.m` 과 `generate_figures_losonly.m` 의 구체적인 구현 spec이 없음.
- ARCHITECTURE.md §6에 Figure 목록은 있으나, 각 Figure의 MATLAB 코드 수준 명세가 없음.
- **조치**: 아래 §Figure 품질 체크리스트로 구현 가이드 제공.

### Figure 품질 체크리스트 (ISAP IEEE 기준)

```
공통:
  [ ] figure('Units','centimeters','Position',[0 0 8.5 8.5])  % 1-column = 8.5 cm
  [ ] 모든 축 레이블: 12pt 이상, LaTeX 형식 (예: '$r_{CP}$')
  [ ] 범례: 10pt 이상, 위치 명시
  [ ] 해상도: print('-depsc2', '-r300', filename) 또는 exportgraphics(... 'Resolution',300)
  [ ] 색상: colorblind-friendly palette (예: [0 0.447 0.741] blue, [0.85 0.325 0.098] red)

Fig 1 (Feature Scatter):
  [ ] x축: log10(r_CP), y축: a_FP
  [ ] LoS: 파란 원(o), NLoS: 빨간 삼각형(^), 크기 일정
  [ ] Decision boundary: logistic regression contour (0.5 확률 등고선)
  [ ] 제목 없음, xlabel/ylabel 필수

Fig 2 (ROC Curves):
  [ ] 4개 모델 곡선 + 대각선(회색 점선)
  [ ] 범례: 'Logistic (AUC=0.xx)' 형식
  [ ] x: False Positive Rate, y: True Positive Rate

Fig 3 (Accuracy vs FLOPs):
  [ ] x축: log10 scale
  [ ] 각 점에 모델 이름 annotation (text 함수)
  [ ] 오차 막대 없음 (단일 값이므로)

Fig 4 (Calibration):
  [ ] x: Mean predicted probability, y: Fraction of positives
  [ ] 완벽 보정 대각선 (회색 점선)
  [ ] bin별 막대 또는 점으로 표현
```

---

## M16: main_run_all

### ✅ PASS

- [x] 3-phase 구조 명확 (1A: 로드, 1B: Joint, 1C: Gate, 2: 분류, 3: Figure)
- [x] `results/` 및 `figures/` 디렉토리 자동 생성
- [x] 결과 저장 (`-v7.3` 플래그 포함)
- [x] LoS-only Gate 로직 명확

### ⚠️ WARNING

**W11**: `merge_sim_data` 헬퍼에서 `t_axis`, `fs_eff`를 첫 번째 파일 기준으로 유지.
- 세 case 파일의 주파수 범위가 동일하면 문제없음.
- 다르면 CIR 길이가 달라 matrix 결합 불가.
- **조치**: `merge_sim_data` 시작 시 `N_fft` 일치 여부 검증. 불일치 시 error.

**W12**: 전체 파이프라인 실행 시 `bayesopt` (SVM) 등으로 인한 긴 실행 시간.
- **조치**: `params.fast_mode = true` 옵션 시 bayesopt 횟수를 5회로 축소하는 분기 추가.

---

## Phase 2 전체 결론

**코드 구현 착수 전 필수 해결 항목:**
1. **F1** (M13): `sigmoidLayer` → `softmaxLayer` + `classificationLayer` (R2021b)
2. **F2** (M13): 공정 비교를 위해 단일 `cvpartition` 객체를 모든 모델에 전달

**구현 중 주의 항목:**
- W1: `rng` 시드를 `cvpartition` 직전에 설정
- W2: `fitglm` 발산 시 Ridge fallback
- W4: ECE 마지막 bin `<=` 처리
- W8: `run_ablation` 내 `params.rcp_definition` 옵션 추가

---

*최종 수정: 2026-04-05 | 작성자: Claude Code (Architecture Agent) — 사전 검수*
*코드 구현 완료 후 실제 코드 기준으로 업데이트 예정*
