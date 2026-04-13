# 단계별 코드 및 결과 정리 (2026-04-08)

이 문서는 현재 저장소 상태와 이미 생성된 결과물을 기준으로, 지금까지의 작업 흐름을 단계별로 역추적하여 정리한 요약본이다.

## Step 1. 기본 Track-3 2-feature 파이프라인 구성

- 핵심 코드
  - `src/main_run_all.m`
  - `src/load_sparam_table.m`
  - `src/build_sim_data_from_table.m`
  - `src/extract_features_batch.m`
  - `src/train_logistic.m`
  - `src/run_ml_benchmark.m`
  - `src/run_ablation.m`
  - `src/generate_figures.m`
- 구현 내용
  - CSV/MAT 입력을 표준 `freq_table`로 정규화
  - IFFT 기반 CIR 생성
  - 기본 특징 `r_CP`, `a_FP` 추출
  - Logistic 학습, benchmark, ablation, figure 생성
- 주요 산출물
  - `results/step1_features.csv`
  - `results/eval_roc_calibration.csv`
  - `results/step3_benchmark.csv`
  - `results/step4_ablation.csv`
  - `results/figures/`
- 핵심 결과

| 항목 | 값 |
|---|---:|
| Logistic eval AUC | 0.8898 |
| Logistic accuracy | 0.8750 |
| Logistic ECE | 0.0382 |
| Benchmark Logistic AUC | 0.8842 |
| Benchmark SVM AUC | 0.7320 |
| Benchmark RandomForest AUC | 0.8543 |
| Benchmark DNN AUC | 0.8824 |

- 해석
  - 기본 2-feature 조합만으로도 AUC 0.88대 성능을 확보했다.
  - `a_FP` 단독 AUC는 0.8806으로 조합형(0.8842)에 매우 근접했고, `r_CP` 단독 AUC는 0.5826으로 낮아 기본 조합에서 `a_FP` 기여가 더 컸다.

## Step 2. 4-port CP 입력 확장과 case별 라벨 실험

- 핵심 코드
  - `src/load_sparam_table.m`
  - `src/build_sim_data_from_table.m`
  - `src/extract_features_batch.m`
  - `src/extract_rcp.m`
  - `src/extract_afp.m`
  - `src/run_casec_4port.m`
  - `src/run_4port_bc_sweep.m`
- 구현 내용
  - RHCP/LHCP 4-port 입력을 감지하고 채널별 특징을 추출하도록 로더와 feature extractor를 확장
  - `material_class`, `geometric_class` 두 라벨 체계를 각각 실험
  - case B/C 4-port 단일 실행과 요약 sweep 추가
- 주요 산출물
  - `results/summary_abc_los_nlos_split.csv`
  - `results/summary_abc_2label_trend.csv`
  - `results/summary_bc_4cases.csv`
  - `results/summary_lightweight_trend.csv`
  - `results/caseB_4port_geometric/`
  - `results/caseC_4port_material/`
  - `results/caseC_4port_geometric/`
- 핵심 결과

| 실행 | 라벨 | 상태 | Logistic eval AUC | 비고 |
|---|---|---|---:|---|
| caseA_4port | material/geometric | single class | NaN | 전부 LoS |
| caseB_4port | material | minority below threshold | NaN | LoS 55, NLoS 1 |
| caseB_4port | geometric | ok | 0.6531 | LoS 35, NLoS 21 |
| caseC_4port | material | ok | 0.8344 | LoS 40, NLoS 16 |
| caseC_4port | geometric | ok | 0.7592 | LoS 21, NLoS 35 |

- 추가 관찰
  - `results/summary_lightweight_trend.csv` 기준으로 `caseB_4port_geometric`의 최고 AUC는 RandomForest 0.9150이지만, 경량 모델 `LogisticQuad`도 AUC 0.9000을 달성했다.
  - `caseC_4port_material`은 `LogisticQuad` AUC 0.8625, `caseC_4port_geometric`은 `LogisticQuad` AUC 0.7571이었다.

## Step 3. CP3 compact 3-feature 경로 추가

- 핵심 코드
  - `src/run_casec_4port_cp3.m`
  - `src/run_ml_benchmark_cp3.m`
  - `src/run_ablation_cp3.m`
- 구현 내용
  - 기존 2-feature 경로를 보존한 채 별도 3-feature 실험 경로 추가
  - 사용 특징: `gamma_CP`, `a_FP`, `fp_idx_diff_rx12`
  - `r_CP` 계산 윈도우 변화에 따른 성능 sweep 추가
- 주요 산출물
  - `results/caseB_4port_geometric_cp3/`
  - `results/caseC_4port_geometric_cp3/`
  - `results/rcp_window_sweep_cp3_geometric.csv`
  - `results/classification_map_window4_cp3.csv`
- 핵심 결과

| scope | 최고 AUC | 설정 |
|---|---:|---|
| B | 0.8057 | `WINDOW`, 4 ns |
| C | 0.8629 | `WINDOW`, 1 ns |
| B+C | 0.8362 | `WINDOW`, 4 ns |

- 세부 결과
  - `caseB_4port_geometric_cp3` benchmark에서 최고 AUC는 LDA 0.7714였다.
  - `caseC_4port_geometric_cp3` benchmark에서 최고 AUC는 LDA 0.8517, Logistic 0.8486이었다.
  - CP3 ablation에서는 B/C 모두 `a_FP_only`가 조합형과 비슷하거나 더 좋은 결과를 보였고, `gamma_CP_only`와 `fp_idx_diff_only`는 약했다.

## Step 4. CP7 exhaustive subset search와 Logistic/RF 비교

- 핵심 코드
  - `src/run_subset_search_cp7.m`
  - `src/run_subset_compare_cp7_logistic_rf.m`
- 구현 내용
  - 7개 CP 특징 전체 조합 127개를 모두 평가
  - scope `B`, `C`, `B+C`별 최적 subset을 탐색
  - Logistic 최적 subset과 RF 최적 subset을 비교
- 주요 산출물
  - `results/subset_search_cp7_geometric_bc/subset_search_cp7_all.csv`
  - `results/subset_search_cp7_geometric_bc/subset_search_cp7_best_by_scope.csv`
  - `results/subset_compare_cp7_logistic_rf_geometric_bc/subset_compare_logistic_rf_by_scope.csv`
- 핵심 결과

| scope | Logistic best subset | AUC |
|---|---|---:|
| B | `gamma_CP_rx1 + a_FP_LHCP_rx1` | 0.8486 |
| C | `gamma_CP_rx1 + a_FP_LHCP_rx1 + a_FP_RHCP_rx2 + a_FP_LHCP_rx2` | 0.9000 |
| B+C | `gamma_CP_rx1 + gamma_CP_rx2 + a_FP_RHCP_rx1 + a_FP_LHCP_rx1 + a_FP_LHCP_rx2 + fp_idx_diff_rx12` | 0.8399 |

- 비교 결과
  - RF를 Logistic-best subset에 얹었을 때 AUC는 B/C/B+C에서 각각 0.7986, 0.7850, 0.7935로 Logistic보다 낮았다.
  - 즉, 이 단계에서는 subset 탐색 기준으로 Logistic이 더 일관된 상한을 보여주었다.

## Step 5. CP7 full diagnostics 파이프라인 구축

- 핵심 코드
  - `src/run_cp7_feature_diagnostics.m`
  - `src/build_cp7_analysis_table.m`
  - `src/cp7_binary_feature_metrics.m`
  - `src/cp7_local_knn_auc.m`
  - `cp7_feature_diagnostics_project/run_cp7_project.m`
- 구현 내용
  - 7개 CP 특징(이후 최종 6개 lock) 기반의 진단 파이프라인 구축
  - `00_summary`, `01_sanity`, `02_global`, `03_collinearity`, `04_local`, `05_baselines` 구조로 결과를 단계별 저장
  - global AUC, local winner map, collinearity, L1 baseline, RF baseline까지 일괄 생성
- 주요 산출물
  - `cp7_feature_diagnostics_project/00_summary/cp7_summary.md`
  - `cp7_feature_diagnostics_project/01_sanity/`
  - `cp7_feature_diagnostics_project/02_global/`
  - `cp7_feature_diagnostics_project/03_collinearity/`
  - `cp7_feature_diagnostics_project/04_local/`
  - `cp7_feature_diagnostics_project/05_baselines/`
- 핵심 결과

| 라벨 / scope | best global feature | eff. AUC | dominant local winner | L1 AUC | L1+XY AUC | RF CV AUC |
|---|---|---:|---|---:|---:|---:|
| geometric / B | `a_FP_LHCP_rx1` | 0.8014 | `gamma_CP_rx1` | 0.8082 | 0.8578 | 0.7932 |
| geometric / C | `a_FP_LHCP_rx2` | 0.8435 | `gamma_CP_rx1` | 0.8245 | 0.8544 | 0.7517 |
| geometric / B+C | `a_FP_LHCP_rx2` | 0.8017 | `gamma_CP_rx1` | 0.8422 | 0.8402 | 0.8208 |
| material / B | skipped | NaN | skipped | NaN | NaN | NaN |
| material / C | `a_FP_RHCP_rx2` | 0.8641 | `gamma_CP_rx2` | 0.7625 | 0.8234 | 0.8516 |
| material / B+C | `a_FP_RHCP_rx1` | 0.8502 | `a_FP_RHCP_rx1` | 0.8805 | 0.8842 | 0.8684 |

- 해석
  - geometric 기준에서는 LHCP 기반 `a_FP`와 `gamma_CP_rx1`의 공간적 역할이 컸다.
  - material 기준에서는 `a_FP_RHCP_rx1`, `a_FP_RHCP_rx2`가 더 직접적인 분리력을 보였다.
  - `material / B`는 소수 클래스가 1개뿐이라 진단 대상에서 제외되었다.

## Step 6. CP7 follow-up 분석과 6-feature 최종 lock

- 핵심 코드
  - `cp7_feature_diagnostics_project/run_cp7_followup_checks.m`
  - `cp7_feature_diagnostics_project/run_cp7_followup2.m`
  - `cp7_feature_diagnostics_project/run_cp6_final_package.m`
- 구현 내용
  - L1 선택 결과, key collinearity, winner margin, `fp_idx_diff_rx12` 제거 가능성 재검토
  - interaction check와 two-RX diversity 시각화 추가
  - 최종적으로 6개 특징 lock
- 주요 산출물
  - `cp7_feature_diagnostics_project/06_followup/followup_summary.md`
  - `cp7_feature_diagnostics_project/08_followup2/followup2_summary.md`
  - `cp7_feature_diagnostics_project/09_final_lock/final_methods_and_captions.md`
- 핵심 결과
  - Interaction check:
    - `a_FP_RHCP_rx1 x gamma_CP_rx2` 쌍의 RF H-statistic은 0.4828
    - 그러나 Logistic에서는 additive 0.8816 -> interaction 포함 0.8711로 오히려 하락
    - full-7 Logistic도 additive 0.8430 -> interaction 포함 0.8167로 하락
  - `fp_idx_diff_rx12` drop ablation:
    - `geometric / B+C`: Logistic delta 0.0081, RF delta -0.0037
    - `material / C`: Logistic delta 0.0062, RF delta -0.0039
    - 일부 scope에서는 제거 손실이 거의 없었다.
  - Two-RX diversity:
    - B: Pearson -0.6144, Spearman -0.6758, opposite-sign 0.8393
    - C: Pearson -0.3716, Spearman -0.4023, opposite-sign 0.6964
    - B+C: Pearson -0.4452, Spearman -0.4980, opposite-sign 0.7143

- 최종 lock
  - 최종 특징 집합은 아래 6개로 고정되었다.
  - `gamma_CP_rx1`, `gamma_CP_rx2`
  - `a_FP_RHCP_rx1`, `a_FP_LHCP_rx1`
  - `a_FP_RHCP_rx2`, `a_FP_LHCP_rx2`
  - `fp_idx_diff_rx12`는 최종 모델 feature set에서 제외되었다.

## Step 7. 별도 LoS/NLoS baseline 프로젝트 구성

- 핵심 코드
  - `los_nlos_baseline_project/run_los_nlos_baseline.m`
  - `los_nlos_baseline_project/run_los_nlos_feature_diagnostics.m`
  - `los_nlos_baseline_project/run_cp7_reviewer_diagnostics.m`
  - `los_nlos_baseline_project/run_cp7_priority_validations.m`
  - `los_nlos_baseline_project/run_cp7_followup_validations.m`
- 구현 내용
  - 기존 2-feature 중심 경로와 별개로, richer CIR feature baseline을 별도 프로젝트로 구성
  - baseline feature set과 CP7 channel-resolved feature set의 incremental gain을 reviewer 관점으로 비교
  - priority validation, bootstrap, mechanism subgroup 검증까지 추가
- 주요 산출물
  - `los_nlos_baseline_project/results/material/`
  - `los_nlos_baseline_project/results/geometric/`
  - `los_nlos_baseline_project/results/diagnostics/diagnostics_summary.md`
  - `los_nlos_baseline_project/results/cp7_reviewer_diagnostics/diagnostics_summary.md`
  - `los_nlos_baseline_project/results/cp7_priority_validations/`
  - `los_nlos_baseline_project/results/cp7_followup_validations/`
- baseline 전체 성능

| target | AUC | accuracy | balanced accuracy | Brier |
|---|---:|---:|---:|---:|
| material | 0.9079 | 0.8571 | 0.8683 | 0.1073 |
| geometric | 0.7965 | 0.6815 | 0.6875 | 0.1838 |

- reviewer diagnostics 핵심 결과
  - geometric overall에서는 baseline 대비 CP7 추가 모델이 꾸준히 개선되었다.
    - B: 0.8490 -> 0.9007
    - C: 0.8082 -> 0.8735
    - B+C: 0.8495 -> 0.9072
  - geometric hard-case (`0.4~0.6`)에서는 개선 폭이 더 컸다.
    - B+C: 0.4286 -> 0.9429
  - material overall에서는 baseline이 오히려 더 강했다.
    - C: 0.9375 -> 0.9141
    - B+C: 0.9474 -> 0.9282

- priority validation 핵심 결과
  - geometric에서는 `full_proposed`가 baseline보다 강했다.
    - B: 0.8599 -> 0.9020
    - C: 0.7796 -> 0.8653
    - B+C: 0.8348 -> 0.9024
  - material에서는 baseline 5-feature가 full proposed보다 강했다.
    - C: 0.9375 vs 0.9141
    - B+C: 0.9474 vs 0.9282

- permutation importance 핵심 결과
  - material logistic에서 가장 큰 평균 AUC drop은 `a_FP_LHCP_rx1`(0.0104), `gamma_CP_rx1`(0.0088)
  - material RF에서는 `a_FP_RHCP_rx1`이 가장 컸다(0.0153)
  - geometric logistic에서는 `a_FP_LHCP_rx1`(0.0748), `gamma_CP_rx2`(0.0419)가 컸다
  - geometric RF에서는 `gamma_CP_rx2`(0.0432), `a_FP_LHCP_rx2`(0.0188)가 컸다

- dual-RX follow-up 핵심 결과
  - geometric에서는 dual-RX가 단일 RX 최고값보다 약간 유리했다.
    - C: +0.0136
    - B+C: +0.0099
  - material에서는 dual-RX가 best single보다 낮았다.
    - C: -0.0094
    - B+C: -0.0056

## 현재 기준 정리

- 메인 파이프라인은 `r_CP + a_FP` 기반 2-feature baseline을 안정적으로 제공한다.
- 4-port 확장 이후에는 case별, label별로 class imbalance 차이가 매우 커졌고, 특히 `material / B`는 사실상 학습 불가 수준이다.
- CP3는 compact 비교용 경로로 의미가 있지만, 핵심 분리력은 여전히 `a_FP` 계열이 주도한다.
- CP7 진단에서는 공간적/채널적 역할 분리가 확인되었고, 최종적으로 `fp_idx_diff_rx12`를 제외한 6-feature lock으로 수렴했다.
- reviewer/validation 관점에서는 geometric target에서 CP7의 이득이 분명하지만, material target에서는 기존 baseline이 더 강한 구간이 존재한다.

## 테스트 및 검증 메모

- 통과
  - `test_build_cp7_analysis_table`
  - `test_cp7_binary_feature_metrics`
  - `test_cp7_local_knn_auc`
  - `test_run_cp7_feature_diagnostics_smoke`
  - `test_extract_rcp`
- 확인된 이슈
  - `test_phase2_smoke`는 현재 실패한다.
  - 원인: 테스트는 `run_ml_benchmark` 결과 row 수가 4개라고 가정하지만, 현재 구현은 Logistic/SVM/RandomForest/DNN 외 추가 모델까지 반환하여 row 수가 증가했다.
  - 즉, 현 시점 실패는 core benchmark 로직 붕괴보다는 테스트 기대값이 현재 구현과 맞지 않는 문제에 가깝다.
