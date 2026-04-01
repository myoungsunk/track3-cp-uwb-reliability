# Track 3 — CP-UWB 신뢰도 점수 산출: 전체 아키텍처

> 투고처: ISAP 2026 (2–4 pages) | 마감: 2026.06.26
> 언어: MATLAB R2021b 이상
> 변경 이력: v1.1 — SIM1/SIM2 실제 포맷 반영 (주파수 도메인 S-파라미터 테이블, IFFT, d_sym 레이블)

---

## 1. 모듈 의존성 DAG

```
[SIM1/SIM2 데이터 파일]
 주파수 도메인 S-파라미터 테이블
 (d_sym, x_coord, y_coord, Freq, mag/ang S(rx1), mag/ang S(rx2))
        │
        ▼
┌─────────────────────┐
│  M01: data_loader   │  테이블 파싱 + H(f)→h(t) IFFT 합성 + d_sym 레이블 매핑
└─────────┬───────────┘
          │  sim_data (struct)
          ▼
┌─────────────────────┐
│ M02: extract_features│  r_CP, a_FP 계산
└─────────┬───────────┘
          │  feature_table [N×4]
          ▼
┌─────────────────────┐
│  M03: split_dataset │  Stratified 5-fold CV 분할
└─────────┬───────────┘
          │  folds {train/test splits}
          ▼
┌──────────────────────────────────────────────────┐
│  M04: train_models                               │
│   ├─ train_logistic  (핵심 기여 모델)             │
│   ├─ train_svm                                   │
│   ├─ train_rf                                    │
│   └─ train_dnn                                   │
└─────────┬────────────────────────────────────────┘
          │  model structs
          ▼
┌─────────────────────┐
│  M05: eval_model    │  ROC AUC, Accuracy, F1, ECE, FLOPs
└─────────┬───────────┘
          │  results struct
          ▼
┌─────────────────────┐
│  M06: plot_figures  │  논문 Figure 생성
└─────────────────────┘
```

**의존 관계 요약**

| 모듈 | 의존하는 모듈 |
|------|-------------|
| M01 data_loader | (없음) |
| M02 extract_features | M01 |
| M03 split_dataset | M02 |
| M04 train_models | M03 |
| M05 eval_model | M04 |
| M06 plot_figures | M05 |

---

## 2. 데이터 흐름도

```
SIM1/SIM2 원본 테이블  (행: N_pos × N_freq 개)
  ├─ d_sym      scalar  double  [mm]    시나리오 식별자 (LoS/NLoS 유추용)
  ├─ x_coord    scalar  double  [mm]    Rx 위치 x
  ├─ y_coord    scalar  double  [mm]    Rx 위치 y
  ├─ Freq       scalar  double  [GHz]   UWB Ch.5 주파수 포인트
  ├─ mag_rx1    scalar  double  [–]     S21 진폭 (rx1 = RHCP 포트)
  ├─ ang_rx1    scalar  double  [deg]   S21 위상 (rx1 = RHCP 포트)
  ├─ mag_rx2    scalar  double  [–]     S21 진폭 (rx2 = LHCP 포트)
  └─ ang_rx2    scalar  double  [deg]   S21 위상 (rx2 = LHCP 포트)
        │
        ▼  M01: data_loader
        │  ① (d_sym, x, y)별 H(f) 구성
        │  ② H_RHCP(f), H_LHCP(f) = mag·exp(j·ang·π/180)
        │  ③ IFFT(H, N_fft) → CIR_RHCP, CIR_LHCP  (복소 해석신호)
        │  ④ t_axis = (0:N_fft-1) / (N_fft·df) [ns]
        │  ⑤ labels from DSYM_LABEL_MAP(d_sym)
        ▼
sim_data struct
  ├─ CIR_RHCP  [N_pos × N_fft]  complex double  (RHCP CIR, IFFT 출력)
  ├─ CIR_LHCP  [N_pos × N_fft]  complex double  (LHCP CIR, IFFT 출력)
  ├─ labels    [N_pos × 1]      uint8            (0=NLoS, 1=LoS, d_sym 매핑)
  ├─ pos_id    [N_pos × 1]      uint32           (위치 인덱스)
  ├─ t_axis    [1 × N_fft]      double  [ns]     (시간축)
  └─ positions [N_pos × 3]      table            (d_sym, x_coord, y_coord)
        │
        ▼  M02: extract_features
feature_table  [N_pos × 4]  table
  ├─ r_CP      [N_pos × 1]  double  [linear, dimensionless]
  ├─ a_FP      [N_pos × 1]  double  [0–1, dimensionless]
  ├─ label     [N_pos × 1]  logical (0=NLoS, 1=LoS)
  └─ pos_id    [N_pos × 1]  uint32
        │
        ▼  M03: split_dataset  →  5-fold struct array
folds(k).X_train  [N_train × 2]  double   (r_CP, a_FP, 정규화 전)
folds(k).y_train  [N_train × 1]  logical
folds(k).X_test   [N_test  × 2]  double
folds(k).y_test   [N_test  × 1]  logical
        │
        ▼  M04: train_models
model.logistic   struct  (계수 β, 정규화 파라미터 μ/σ)
model.svm        ClassificationSVM object
model.rf         ClassificationEnsemble object
model.dnn        network object (Deep Learning Toolbox)
        │
        ▼  M05: eval_model
results.(model_name)
  ├─ auc        scalar  double
  ├─ accuracy   scalar  double  [0–1]
  ├─ f1         scalar  double  [0–1]
  ├─ ece        scalar  double  [0–1]
  ├─ flops      scalar  double  [부동소수점 연산 수]
  ├─ roc_fpr    [K × 1] double  (ROC curve false positive rate)
  ├─ roc_tpr    [K × 1] double  (ROC curve true positive rate)
  └─ cal_bins   [10 × 2] double (calibration: mean_conf, mean_acc)
```

---

## 3. 각 모듈 입출력 명세

### M01: data_loader

```matlab
function sim_data = data_loader(filepath, params)
```

**입력**

| 인자 | 타입 | 설명 |
|------|------|------|
| `filepath` | char/string | SIM1/SIM2 데이터 파일 경로 (.mat 또는 .csv) |
| `params.dsym_label_map` | containers.Map | d_sym 값 → LoS/NLoS 레이블 매핑 (필수) |
| `params.n_fft` | uint32 | IFFT 포인트 수 (기본값: `2^(nextpow2(N_freq)+2)`) |
| `params.rx1_pol` | char | rx1 포트 편파 식별자 (기본값: `'RHCP'`) |
| `params.rx2_pol` | char | rx2 포트 편파 식별자 (기본값: `'LHCP'`) |

**출력**

| 인자 | 타입 | 차원 | 단위 | 설명 |
|------|------|------|------|------|
| `sim_data.CIR_RHCP` | complex double | [N_pos × N_fft] | — | RHCP CIR (IFFT 결과, 복소 해석신호) |
| `sim_data.CIR_LHCP` | complex double | [N_pos × N_fft] | — | LHCP CIR (IFFT 결과) |
| `sim_data.labels` | uint8 | [N_pos × 1] | — | 0=NLoS, 1=LoS (d_sym 매핑) |
| `sim_data.pos_id` | uint32 | [N_pos × 1] | — | 위치 인덱스 (1-based) |
| `sim_data.t_axis` | double | [1 × N_fft] | ns | 시간축 (`dt = 1/(N_fft·df_Hz)`) |
| `sim_data.positions` | table | [N_pos × 3] | mm | 열: d_sym, x_coord, y_coord |

**내부 처리 요약**

1. 테이블 로드: `readtable(filepath)` 또는 `load(filepath)`
2. 열 이름 표준화: `mag(S(rx1_p1,tx_p1))` → `mag_rx1` 등 (공백/괄호 제거)
3. 고유 위치 그룹화: `unique(T(:,{'d_sym','x_coord','y_coord'}), 'rows')`
4. 위치별 복소 전달함수 구성: `H = mag .* exp(1j * ang * pi/180)`
5. IFFT: `cir = ifft(H, N_fft)` → `sim_data.CIR_RHCP(i,:)`
6. 시간축: `dt_ns = 1e9 / (N_fft * df_Hz)`, `t_axis = (0:N_fft-1) * dt_ns`
7. 레이블: `labels(i) = params.dsym_label_map(d_sym_i)`

> **PLACEHOLDER**: `params.dsym_label_map`의 실제 d_sym 값과 LoS/NLoS 대응은
> 연구자가 `unique(T.d_sym)` 결과를 시나리오 정의 문서와 대조하여 확정.
> 확정 전까지 `data_loader.m` 실행 시 경고 메시지 출력하도록 구현.

---

### M02: extract_features

→ 상세 명세: `specs/spec_extract_features.md`

---

### M03: split_dataset

```matlab
function folds = split_dataset(feature_table, params)
```

| 항목 | 타입 | 차원 | 설명 |
|------|------|------|------|
| **입력** feature_table | table | [N_pos × 4] | r_CP, a_FP, label, pos_id |
| **입력** params.n_folds | uint8 | scalar | Cross-validation fold 수 (기본값: 5) |
| **출력** folds | struct array | [1 × n_folds] | train/test split 구조체 배열 |

---

### M04: train_models / M05: eval_model

→ 상세 명세: `specs/spec_logistic_model.md`

---

## 4. 파라미터 테이블

| 파라미터 | 기본값 | 단위 | 근거 |
|----------|--------|------|------|
| `n_fft` | `2^(nextpow2(N_freq)+2)` | samples | 주파수 포인트 수 대비 4배 zero-padding → 시간 해상도 향상 및 시간축 aliasing 방지 |
| `threshold_ratio` | 0.20 | dimensionless | Dardari et al., "Threshold-Based Time-of-Arrival Estimators in UWB Dense Multipath Channels," *IEEE Trans. Commun.*, 2009 |
| `T_w` | 2.0 | ns | IEEE 802.15.4a CM3 (indoor office NLOS) 첫 번째 클러스터 RMS delay spread ≈ 1–2 ns; 윈도우는 양방향이므로 총 4 ns 커버 |
| `n_folds` | 5 | dimensionless | Stratified k-fold CV 표준 설정 (Hastie et al., *ESL*, 2009, §7.10) |
| `svm_kernel` | 'rbf' | — | 비선형 경계 대응; RBF = Gaussian kernel |
| `svm_bayesopt_iter` | 30 | iterations | MATLAB 권장 최소 탐색 횟수 |
| `rf_n_trees` | 100 | trees | Breiman (2001): 100 트리에서 오차 수렴 확인 |
| `dnn_hidden` | [16, 8] | neurons | 입력 차원(2) 대비 과적합 방지를 위한 경량 구조 |
| `dnn_lr` | 1e-3 | — | Adam optimizer 기본값 (Kingma & Ba, ICLR 2015) |
| `dnn_epochs` | 200 | — | Early stopping 기준 validation loss |
| `cal_n_bins` | 10 | bins | ECE 계산 표준 bin 수 (Guo et al., ICML 2017) |

---

## 5. Figure 목록 (논문 사양)

| Fig# | 제목 | 내용 | 데이터 소스 | 크기 (col) |
|------|------|------|-------------|-----------|
| Fig. 1 | System Concept | CP-UWB LoS/NLoS 구분 개념도, r_CP & a_FP 정의 | 수작업 벡터 | 1-column |
| Fig. 2 | Feature Distribution | r_CP vs a_FP 2D scatter, LoS/NLoS 색상 구분 | SIM1 + SIM2 feature_table | 1-column |
| Fig. 3 | ROC Curves | Logistic / SVM / RF / DNN 4개 ROC 곡선 중첩, AUC 범례 | results.(model) | 1-column |
| Fig. 4 | Complexity vs Accuracy | FLOPs(x축, log scale) vs AUC(y축) 산점도 | results.(model).flops, .auc | 1-column |
| Fig. 5 | Calibration Diagram | Logistic 10-bin reliability diagram (confidence vs accuracy) | results.logistic.cal_bins | 1-column (optional) |

> 2-column IEEE 양식 기준. 각 Figure는 300 dpi 이상 EPS/PDF 형식으로 저장.
> Fig. 5는 페이지 제한에 따라 본문 또는 부록으로 배치.

---

## 6. 디렉토리 구조

```
track3-cp-uwb-reliability/
├── docs/
│   └── ARCHITECTURE.md          ← 이 파일
├── specs/
│   ├── spec_extract_features.md
│   └── spec_logistic_model.md
├── src/
│   ├── data_loader.m
│   ├── extract_features.m
│   ├── split_dataset.m
│   ├── train_logistic.m
│   ├── train_svm.m
│   ├── train_rf.m
│   ├── train_dnn.m
│   ├── eval_model.m
│   └── plot_figures.m
├── data/
│   ├── SIM1.mat                 ← PLACEHOLDER (미포함, .gitignore)
│   └── SIM2.mat                 ← PLACEHOLDER (미포함, .gitignore)
├── results/
│   └── (자동 생성)
├── figures/
│   └── (자동 생성)
├── prompts/
└── main_pipeline.m              ← 전체 파이프라인 진입점
```

---

*최종 수정: 2026-04-01 | 작성자: Claude Code (Architecture Agent)*
