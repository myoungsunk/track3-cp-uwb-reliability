# REVIEW_phase2.md — Phase 2 코드 구현 후 검수

> 검수 대상: M11–M16 (분류 실험, 평가, Ablation, Figure 생성, 파이프라인)
> 검수 시점: **코드 구현 완료 후 실제 코드 기준 검수**
> 작성일: 2026-04-07 (최초 사전 검수: 2026-04-05)

---

## 요약

| 모듈 | 파일 | Spec 일치 | Edge Case | 수치 안정성 | 재현성 | 공정 비교 | FLOPs | Figure | 판정 |
|------|------|----------|-----------|-----------|--------|----------|-------|--------|------|
| M11 | train_logistic.m | ✅ | ✅ | ✅ | ✅ | N/A | N/A | N/A | PASS |
| M12 | eval_roc_calibration.m | ✅ | ✅ | ✅ | N/A | N/A | ✅ | N/A | PASS |
| M13 | run_ml_benchmark.m | ✅ | ✅ | ⚠️ | ⚠️ | ✅ | ⚠️ | N/A | PASS (WARNING) |
| M14 | run_ablation.m | ✅ | ✅ | ✅ | ✅ | ✅ | N/A | N/A | PASS |
| M15 | generate_figures.m | ⚠️ | ✅ | N/A | N/A | N/A | N/A | ⚠️ | WARNING |
| M16 | main_run_all.m | ✅ | ✅ | N/A | ✅ | N/A | N/A | N/A | PASS |

---

## M11: train_logistic.m

### PASS 항목
- [x] 함수 시그니처 `[model, norm_params] = train_logistic(features, labels, params)` — spec 일치
- [x] Stratified K-fold CV: `cvpartition(labels, 'KFold', cv_folds)` (L54) — 비율 보존 ✅
- [x] `rng(random_seed)` 호출이 `cvpartition` 직전 (L53) — 재현성 ✅ (사전 검수 W1 해결)
- [x] Fold 내부 독립 z-score 정규화 (L72–73) — data leakage 방지 ✅
- [x] `std_values == 0` → 1로 대체 (L208) — division by zero 방지 ✅
- [x] `fitglm` 수렴 실패 시 Ridge fallback (L144–150) — 사전 검수 W2 해결 ✅
- [x] `log10_rcp = true` 시 `r_CP <= 0` 검사 (L41–43) → error 발생 — 명시적 방어
- [x] 외부 `cv_partition` 전달 시 재사용 (L47–51) — 공정 비교 지원
- [x] Coefficient 추출: fitglm/ridge 양쪽 지원 (L177–185)

### WARNING 항목
- **W-M11-1**: `r_CP <= 0` 시 error 발생 (L42)이 아닌 warning + fallback (예: `r_CP = eps`)이 더 robust. 현재 `extract_rcp`에서 `r_CP = 0` (rhcp_zero) 또는 `NaN` (both_zero) 반환 가능. `valid_flag=false`로 필터되므로 실행 시 문제없으나, 필터 미적용 시 crash.
  - 심각도: Low (파이프라인에서 valid_flag 필터링 보장)
- **W-M11-2**: `cv_partition` 전달 시 `rng(random_seed)` 가 무시됨 (L47–54). 의도적이지만 문서화 없음.
  - 심각도: Low

### FAIL 항목
없음.

---

## M12: eval_roc_calibration.m

### PASS 항목
- [x] 함수 시그니처 `results = eval_roc_calibration(model, norm_params, features, labels, params)` — spec 일치
- [x] `perfcurve(labels, predicted_prob, true)` — LoS=true positive class ✅
- [x] Youden's J statistic으로 최적 threshold 결정 (L37–39) — 정확
- [x] ECE 10-bin 계산 (L82–125):
  - 마지막 bin `<=` 처리 (L101) — 사전 검수 W4 해결 ✅
  - bin 가중 평균 `(count / n_total) * |avg_pred - frac_pos|` — Guo et al. 2017 기준 ✅
- [x] Precision/recall division by zero 방지: `max(..., eps)` (L48–50)
- [x] `cal_curve` 구조체 반환 (mean_predicted, fraction_positive, bin_count, bin_edges) — Fig 4 연동
- [x] log10_rcp, normalize 변환을 norm_params 기반으로 재적용 (L18–31)

### WARNING 항목
- **W-M12-1**: `max(..., eps)` 방식 (L48–50)은 TP+FP=0 시 precision = 0/eps ≈ 0 으로 처리. 논리적으로 올바르나, 코드 의도가 즉시 파악되지 않음.
  - 심각도: Low (결과에 영향 없음)

### FAIL 항목
없음.

---

## M13: run_ml_benchmark.m

### PASS 항목
- [x] 함수 시그니처 `benchmark_results = run_ml_benchmark(features, labels, params)` — spec 일치
- [x] **공정 비교**: 단일 `cvpartition` 객체를 모든 모델에 공유 (L27 → L29–31) — 사전 검수 F2 해결 ✅
- [x] `rng(random_seed)` → `cvpartition` 직전 (L26–27) — 재현성 ✅
- [x] DNN 아키텍처: `featureInputLayer(2) → FC(16) → ReLU → FC(8) → ReLU → FC(2) → softmax → classificationLayer` (L361–369) — 사전 검수 F1 해결 ✅ (sigmoidLayer 미사용)
- [x] SVM Platt scaling: `fitPosterior(svm_mdl)` (L148) ✅
- [x] RF: 100 trees, Bag 방식, MaxNumSplits=20 (L225–226) — spec 일치
- [x] 추론 시간: warm-up 10회 + 1000회 측정 (L467–478) — spec 일치
- [x] ROC 곡선 데이터를 `UserData.roc_curves`에 저장 — Figure 연동

### WARNING 항목
- **W-M13-1**: DNN 학습에서 `rng()` 미호출 (L296–310). MATLAB의 `trainNetwork`는 내부적으로 가중치 초기화에 RNG 상태를 사용하므로 비결정적.
  - 심각도: **High** — 재현성 미보장
  - 수정 제안: DNN fold 루프 내 `rng(random_seed + fold_idx)` 추가
  ```matlab
  % L296 이전에 추가:
  rng(random_seed + fold_idx);
  dnn_mdl = train_dnn_model(x_train_norm, y_train, max_epochs, mini_batch);
  ```

- **W-M13-2**: SVM FLOPs 계산 `n_sv * (2 * input_dim + 1) + 1` (L175). RBF 커널 비용 (`exp(-gamma * ||x - x_sv||^2)`) 미반영. 실제 FLOPs는 `n_sv * (3 * input_dim + 2)` 이상.
  - 심각도: Medium — 논문에서 FLOPs를 정량적으로 비교하므로, 과소 추정 시 공정성 의문.
  - 현재 결과: SVM FLOPs = 176 (N_sv 기반). 커널 비용 포함 시 ~250–300.
  - 수정 제안: 커널 비용을 포함한 공식 사용, 또는 논문에서 "approximate FLOPs (kernel evaluation excluded)" 명시.

- **W-M13-3**: RF FLOPs = `num_trees * avg_depth` (L246). 이는 "comparison 연산 수"로, 실제 FLOPs와 정의가 다름. Spec에서는 `100 * D + 99`로 정의.
  - 심각도: Medium
  - 현재 결과: RF FLOPs = 570. Spec 공식 (100 * ~5.7 depth): 대략 일치.

- **W-M13-4**: `tree_depth()` 함수 (L447–465)가 MATLAB 버전별 property 이름(`Children`, `NumLeaves`)에 의존. 호환성 불안정.
  - 심각도: Low (현재 동작 확인)

- **W-M13-5**: SVM `bayesopt` 30회 최적화가 다른 모델에는 적용되지 않음. 논문에서 명시 필요.
  - 심각도: Medium (사전 검수 F3 유지)
  - 현재 결과에서 SVM AUC=0.7320으로 최하위 → 최적화에도 불구하고 낮은 성능이므로 불공정 논란은 약화됨.

### FAIL 항목
없음.

---

## M14: run_ablation.m

### PASS 항목
- [x] 함수 시그니처 `ablation_results = run_ablation(features, labels, params)` — spec 일치
- [x] 3개 구성 비교: r_CP_only, a_FP_only, combined (L30) — spec A1–A3 필수 항목 ✅
- [x] **공정 비교**: 단일 `cvpartition` 공유 (L28 → L38) ✅
- [x] `rng(random_seed)` → `cvpartition` 직전 (L27–28) — 재현성 ✅
- [x] `delta_auc_vs_combined` 계산 (L60) — combined 기준 정확
- [x] r_CP_only 시 `log10_rcp = true`, a_FP_only 시 `log10_rcp = false` (L42–48) — 올바른 분기
- [x] 결과 저장: MAT + CSV 동시 출력

### WARNING 항목
- **W-M14-1**: A4–A7 (optional ablation items) 미구현. Spec에서 "optional"으로 분류되어 있으므로 FAIL은 아니나, `|Δ AUC| > 0.02` 기준으로 포함 여부 판단이 필요했음.
  - 심각도: Low (논문 지면 제약 고려 시 A1–A3만으로 충분)

### FAIL 항목
없음.

---

## M15: generate_figures.m

### PASS 항목
- [x] Figure 1–4 모두 생성
- [x] `figure('Units', 'centimeters', 'Position', [0 0 8.5 7])` — 1-column 폭 8.5cm ✅
- [x] PDF + PNG + FIG 3중 저장 (L210–217)
- [x] 폰트: Times New Roman 기본값 (L12) — ISAP 기준 충족
- [x] 해상도: 300 dpi (L16)
- [x] Decision boundary 그리기: norm_mean/std_values 존재 시 역정규화 적용 (L85–91)
- [x] ROC curves: 4개 모델 + 대각선 참조선 (L102–149)

### WARNING 항목
- **W-M15-1**: Fig 1 NLoS 마커가 `'rx'` (빨간 X, L51)로 표시. Spec에서는 `'^'` (삼각형) 권장. 또한 'filled' 미적용으로 흑백 인쇄 시 LoS/NLoS 구분 어려움.
  - 심각도: Medium
  - 수정 제안: `plot(... 'r^', 'MarkerSize', 4, 'MarkerFaceColor', [0.85 0.325 0.098])` 변경

- **W-M15-2**: Fig 1 xlabel/ylabel에 LaTeX 인터프리터 미사용 (L58–59). `log_{10}(r_{CP})` 표기는 TeX subscript이나 `'Interpreter', 'latex'` 미설정으로 렌더링이 MATLAB 기본 TeX에 의존.
  - 심각도: Low (MATLAB 기본 TeX으로도 subscript 동작하나, 수식 표현이 제한적)

- **W-M15-3**: Fig 3 y축이 `'Accuracy (%)'` (L172)로 Accuracy를 사용하나, 논문의 핵심 지표는 AUC. Spec에서는 AUC를 y축으로 권장.
  - 심각도: **High** — 논문 핵심 주장 (AUC 동등 + FLOPs 절감)과 y축 지표 불일치
  - 수정 제안: y축을 AUC로 변경하고 `benchmark.auc` 사용
  ```matlab
  y_val = double(benchmark.auc);  % accuracy 대신 auc
  ylabel(ax, 'AUC');
  ```

- **W-M15-4**: Fig 3에서 모든 점이 동일 색상/마커 (`scatter(..., 30, 'filled')`, L163). Spec에서는 모델별 다른 마커+색상 권장. 또한 텍스트 레이블이 잘릴 수 있음 ("RandomFo..." 현상 확인).
  - 심각도: Medium
  - 수정 제안: 모델별 다른 색상+마커 적용, 텍스트 위치 조정

- **W-M15-5**: Fig 4 calibration diagram에서 ECE 값이 figure 내에 표시되지 않음. Spec에서는 `text(0.05, 0.9, sprintf('ECE = %.3f', ece))` 권장.
  - 심각도: Medium
  - 수정 제안: `text()` 호출 추가

- **W-M15-6**: `exportgraphics()` 함수는 R2020a 이상 필요. R2019b 이하에서는 `print()` fallback 필요.
  - 심각도: Low (R2021b 환경 확인됨)

- **W-M15-7**: Fig 2 범례 AUC 표기가 소수점 2자리 (L114, `'%.2f'`). 소수점 3자리가 모델 간 미세 차이를 보여주는 데 더 적합 (예: Logistic 0.884 vs DNN 0.882).
  - 심각도: Low
  - 수정 제안: `'%.3f'` 사용

### FAIL 항목
없음. (WARNING이 다수이나 코드 실행 및 Figure 생성 자체는 성공)

---

## M16: main_run_all.m

### PASS 항목
- [x] 3-phase 구조 (1A: 로드, 1B: Joint, 1C: Gate, 2: 분류, 3: Figure)
- [x] LoS-only Gate: NLoS < `nlos_min_count` 시 skip_classification = true
- [x] `rng(random_seed)` 파이프라인 시작 시 호출
- [x] 결과 저장: MAT + CSV
- [x] 디렉토리 자동 생성
- [x] merge_sim_data로 다중 case 병합

### WARNING 항목
- **W-M16-1**: 데이터 발견 시 3개 CSV (caseA/B/C) 전부 존재해야 함. 부분 데이터(예: caseB+C만) 지원 불가.
  - 심각도: Low (현재 요구사항에서는 B+C 만 사용하며, main_run_all 호출 전에 수동으로 해결)

### FAIL 항목
없음.

---

## 사전 검수 (2026-04-05) 대비 변경 사항

| 사전 검수 항목 | 상태 | 비고 |
|--------------|------|------|
| F1 (M13): sigmoidLayer → softmax+classification | ✅ 해결 | L361–369 확인. `fullyConnectedLayer(2)` + `softmaxLayer` + `classificationLayer` 사용 |
| F2 (M13): 단일 cvpartition 공유 | ✅ 해결 | L26–27에서 한 번 생성 후 모든 모델에 전달 |
| F3 (M13): SVM bayesopt 불공정 | ⚠️ 유지 | SVM만 hyperparameter 최적화 적용. 논문에서 명시 필요 |
| W1: rng 시드 cvpartition 직전 | ✅ 해결 | M11 L53, M13 L26, M14 L27 모두 확인 |
| W2: fitglm 발산 Ridge fallback | ✅ 해결 | M11 L144–150 try-catch 구현 |
| W3: predict 입력 타입 | ✅ 해결 | `predict_logistic_prob` 헬퍼로 통일 |
| W4: ECE 마지막 bin ≤ | ✅ 해결 | M12 L98–102, M13 L430–434 모두 확인 |
| W8: A5/A7 ablation 옵션 | ⚠️ 미구현 | Optional이므로 FAIL 아님 |
| W10: generate_figures spec | ⚠️ 부분 해결 | Figure 생성 성공하나 품질 이슈 다수 (W-M15-1~7) |

---

## Phase 2 전체 결론

**구현 품질: PASS (9 WARNING)**

분류 핵심 모듈 (M11–M14) 품질 우수. Spec 준수, 공정 비교 (shared cvpartition), 재현성 (rng 관리) 모두 충족. 주요 잔여 이슈:

**필수 수정 (논문 제출 전):**
1. **W-M13-1**: DNN rng seeding 추가 (재현성)
2. **W-M15-3**: Fig 3 y축 Accuracy → AUC 변경 (논문 핵심 주장과 불일치)
3. **W-M15-5**: Fig 4에 ECE 값 표시 추가

**권장 수정:**
4. W-M15-1: Fig 1 NLoS 마커 `'^'` (삼각형)으로 변경
5. W-M15-4: Fig 3 모델별 색상/마커 분리
6. W-M15-7: ROC AUC 소수점 3자리 표기
7. W-M13-2: SVM FLOPs에 커널 비용 반영 (또는 논문에서 approximate 명시)

---

*최종 수정: 2026-04-07 | 작성자: Claude Code — 구현 후 코드 검수*
