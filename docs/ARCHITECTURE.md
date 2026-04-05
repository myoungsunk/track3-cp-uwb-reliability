# Track 3 — CP-UWB 신뢰도 점수 산출: 전체 아키텍처 v2

> 투고처: ISAP 2026 (2–4 pages) | 마감: 2026.06.26
> 언어: MATLAB R2021b 이상
> 변경 이력:
> v1.0 — 초기 설계 (SIM1/SIM2 가정 구조)
> v1.1 — 실제 데이터 포맷 반영 (주파수 도메인 S-파라미터, IFFT, d_sym 레이블)
> v2.0 — Phase 0 v2 반영: 실 CSV 포맷 확정, CP/LP 파일 분리, 16개 모듈 전면 재설계,
>         Joint Phase 1 (Feature + Localization), LoS-only Gate, v1 Placeholder 제거

---

## 1. 실 데이터 포맷 (확정)

### 1.1 파일 명명 규칙

```
{polarization}_case{scenario}.csv

polarization : lp  (Linear Polarization, 비교 베이스라인)
             | cp  (Circular Polarization, 연구 핵심)
scenario     : A | B | C  (시나리오 종류)

파일 목록 (총 6개):
  lp_caseA.csv   lp_caseB.csv   lp_caseC.csv
  cp_caseA.csv   cp_caseB.csv   cp_caseC.csv
```

- **CP 파일**: rx1=RHCP, rx2=LHCP → r_CP, a_FP 계산 대상
- **LP 파일**: rx1=LP1, rx2=LP2 → 비교 베이스라인 (선택 실험)
- **caseA/B/C**: 시나리오 종류. LoS/NLoS 대응은 아래 §1.3 참조

### 1.2 CSV 열 구조 (실측)

| 원본 열 이름 | MATLAB readtable 자동 변환명 | 단위 | 설명 |
|------------|---------------------------|------|------|
| `x_coord [n]` | `x_coord_n_` | mm (PLACEHOLDER: 단위 확인) | Rx 위치 x 좌표 |
| `y_coord [n]` | `y_coord_n_` | mm | Rx 위치 y 좌표 |
| `Freq [GHz]` | `Freq_GHz_` | GHz | 주파수 포인트 |
| `mag(S(rx1,p1,tx_p1)) []` | `mag_S_rx1_p1_tx_p1___` | — | rx1 S21 진폭 |
| `ang_deg(S(rx1,p1,tx_p1)) [deg]` | `ang_deg_S_rx1_p1_tx_p1___deg_` | deg | rx1 S21 위상 |
| `mag(S(rx2,p1,tx_p1)) []` | `mag_S_rx2_p1_tx_p1___` | — | rx2 S21 진폭 |
| `ang_deg(S(rx2,p1,tx_p1)) [deg]` | `ang_deg_S_rx2_p1_tx_p1___deg_` | deg | rx2 S21 위상 |

**예시 행** (cp_caseA.csv):
```
x_coord=750, y_coord=-1750, Freq=6.24 GHz,
  mag_rx1=0.00082, ang_rx1=-54.14°, mag_rx2=0.000701, ang_rx2=34.60°
```

> **PLACEHOLDER**: `x_coord [n]`의 단위 `n` 확인 필요.
> 예시값(750, -1750)이 mm이라면 0.75m, 1.75m → 실내 시나리오로 타당.
> `load_sparam_table.m`에 `coord_unit_mm2m = true` 옵션으로 자동 변환.

### 1.3 LoS/NLoS 레이블 (caseA/B/C 매핑)

레이블이 CSV 내에 직접 포함되어 있지 않음. 파일명의 case 식별자로 유추.

```matlab
% PLACEHOLDER: 연구자가 실제 시나리오 정의에 따라 확정
CASE_LABEL_MAP = containers.Map(...
    {'caseA', 'caseB', 'caseC'}, ...
    {true,    true,    false  }  ...  % true=LoS, false=NLoS (예시, 확인 필요)
);
```

> 현재 보유 데이터는 **LoS only** (caseA/B/C 모두 LoS 시나리오일 가능성).
> NLoS 시나리오 데이터 생성 후 동일 파이프라인에 투입.
> LoS-only 상태에서는 §5.2의 Gate 로직이 자동으로 분류 실험을 skip.

---

## 2. 모듈 목록 및 의존성 DAG

### 2.1 모듈 목록

```
M01  load_sparam_table.m         — CSV/MAT 로드, 열 이름 정규화
M02  build_sim_data_from_table.m  — Hanning windowing + IFFT → CIR + sim_data 구조체
M03  detect_first_path.m         — Leading-edge first-path 검출 (공용)
M04  extract_rcp.m               — r_CP 계산 (RHCP/LHCP first-path 전력비)
M05  extract_afp.m               — a_FP 계산 (first-path 에너지 집중도)
M06  extract_features_batch.m    — 전 위치 feature 일괄 추출 + sim_data 반환
M07  build_rssd_lut.m            — guide(inc_ang) 데이터 → RSSD LUT 생성
M08  estimate_doa_rssd.m         — RSSD LUT 역참조 → DoA 추정
M09  estimate_position.m         — DoA + ranging → 2D 위치 추정
M10  run_joint_phase1.m          — Feature 추출 + 위치추정 통합 실행
M11  train_logistic.m            — Logistic Regression 학습
M12  eval_roc_calibration.m      — ROC, Calibration, ECE 평가
M13  run_ml_benchmark.m          — 4개 모델 비교 (SVM/RF/DNN/Logistic)
M14  run_ablation.m              — r_CP/a_FP 조합·정의·파라미터 sensitivity 비교
M15  generate_figures.m          — 논문용 Figure 일괄 생성
M16  main_run_all.m              — 전체 파이프라인 마스터 스크립트
```

### 2.2 의존성 DAG

```
[CSV 파일: cp_caseA/B/C, lp_caseA/B/C]
             │
             ▼ M01
        [freq_table]
             │
             ▼ M02
         [sim_data]
        ┌────┴─────────────────────────┐
        │                             │
        ▼ M03→M04, M05               ▼ (RSS 포함)
   M06: extract_features_batch    M07: build_rssd_lut
        │                             │
        │                             ▼ M08
        │                        M09: estimate_position
        │                             │
        └──────────┬──────────────────┘
                   ▼ M10: run_joint_phase1
              [joint_results]
                   │
         ┌────────┬┴───────────┐
         │        │            │
    [LoS gate]   M11          M14
    skip if      │            │
    n_nlos<10   M12          │
         │        │            │
         └────────┴────────────┤
                               ▼ M13 (benchmark)
                               │
                               ▼ M15 (figures)
                               │
                               ▼ M16 (main)
```

---

## 3. 데이터 흐름도

```
CSV 파일 (cp_caseA.csv 예시)
  행: (x_coord, y_coord, Freq, mag_rx1, ang_rx1, mag_rx2, ang_rx2)
  그룹 단위: 동일 (x_coord, y_coord) → 하나의 위치
  N_pos 위치 × N_freq 주파수 포인트 = 전체 행 수
        │
        ▼  M01: load_sparam_table
freq_table  (MATLAB table)
  .x_coord_mm   [N_pos×N_freq rows]  double  [mm]
  .y_coord_mm   [N_pos×N_freq rows]  double  [mm]
  .freq_ghz     [N_pos×N_freq rows]  double  [GHz]
  .S21_rx1      [N_pos×N_freq rows]  complex double  (mag*exp(j*ang*pi/180))
  .S21_rx2      [N_pos×N_freq rows]  complex double
  .group_id     [N_pos×N_freq rows]  uint32  (동일 위치 → 동일 ID)
  .pol_type     scalar string        'CP' | 'LP'
  .case_id      scalar string        'caseA' | 'caseB' | 'caseC'
        │
        ▼  M02: build_sim_data_from_table
        │       [위치별 group_id 그룹핑]
        │       H(f) = S21_rx1 (or rx2)
        │       H_win(f) = H(f) .* hanning(N_freq)
        │       H_pad = [H_win; zeros(N_fft-N_freq, 1)]
        │       cir = ifft(H_pad, N_fft)
        │       t_axis_ns = (0:N_fft-1) / (N_fft*df_Hz) * 1e9
        │       RSS_dBm = 10*log10(sum(|cir|²))  [TODO: 교정 상수]
        ▼
sim_data  (struct)
  .CIR_rx1    [N_pos × N_fft] complex   rx1 CIR (CP→RHCP, LP→LP1)
  .CIR_rx2    [N_pos × N_fft] complex   rx2 CIR (CP→LHCP, LP→LP2)
  .t_axis     [1 × N_fft]     double    [ns]
  .fs_eff     scalar          double    [Hz]  = N_fft * df_Hz
  .pos_id     [N_pos × 1]     uint32
  .labels     [N_pos × 1]     logical   (case_id 기반 매핑, LoS-only 시 all true)
  .x_coord_m  [N_pos × 1]     double    [m]   (mm에서 변환)
  .y_coord_m  [N_pos × 1]     double    [m]
  .RSS_rx1    [N_pos × 1]     double    [dBm]
  .RSS_rx2    [N_pos × 1]     double    [dBm]
  .pol_type   string                    'CP' | 'LP'
  .case_id    string                    'caseA' | ...
  .data_role  string                    'test' (좌표 기반) | 'guide' (각도 기반)
        │
        ├────────────────────────────────────┐
        ▼  M06: extract_features_batch       ▼  M07~M09: RSSD Localization
feature_table  (MATLAB table)            [CP 데이터 전용]
  .pos_id         [uint32]                 lut        ← M07 (RSS 차이 LUT)
  .r_CP           [double]   [0, clip]     doa_est    ← M08 (DoA 추정)
  .a_FP           [double]   [0, 1]        pos_est    ← M09 (2D 위치)
  .label          [logical]
  .valid_flag     [logical]
  .fp_idx_rx1     [uint32]
  .fp_idx_rx2     [uint32]
  .RSS_rx1        [double]   [dBm]
  .RSS_rx2        [double]   [dBm]
        │                                        │
        └──────────────┬─────────────────────────┘
                       ▼  M10: run_joint_phase1
                  joint_results
                       │
              LoS-only Gate (n_nlos < 10 → skip)
                       │
         ┌─────────────┴──────────────────────┐
    [skip_classification=true]        [skip_classification=false]
         │                                    │
    M15: Fig P1 only                M11 train_logistic
    (위치추정 결과 시각화)            M12 eval_roc_calibration
                                    M13 run_ml_benchmark
                                    M14 run_ablation
                                    M15 generate_figures (Fig 1~4, S1~S2)
```

---

## 4. 각 모듈 입출력 명세 요약

| 모듈 | 주요 입력 | 주요 출력 | 상세 spec |
|------|---------|---------|---------|
| M01 load_sparam_table | CSV/MAT 경로 | freq_table | spec_load_and_build.md §2.1 |
| M02 build_sim_data_from_table | freq_table | sim_data | spec_load_and_build.md §2.2 |
| M03 detect_first_path | cir_abs [N_tap×1] | fp_idx, fp_info | spec_extract_features_v2.md §3.1 |
| M04 extract_rcp | cir_rx1, cir_rx2 [N_tap×1] | r_CP, rcp_info | spec_extract_features_v2.md §3.2 |
| M05 extract_afp | cir_rx1, cir_rx2, t_axis | a_FP, afp_info | spec_extract_features_v2.md §3.3 |
| M06 extract_features_batch | sim_data | feature_table, sim_data | spec_extract_features_v2.md §3.4 |
| M07 build_rssd_lut | sim_data_guide | lut | spec_rssd_localization.md §4.1 |
| M08 estimate_doa_rssd | rssd_measured, lut | doa_est, doa_info | spec_rssd_localization.md §4.2 |
| M09 estimate_position | sim_data_test, lut | pos_est | spec_rssd_localization.md §4.3 |
| M10 run_joint_phase1 | sim_data_guide, sim_data_test | joint_results | spec_run_joint.md §6.1 |
| M11 train_logistic | features, labels | model | spec_logistic_model_v2.md §1 |
| M12 eval_roc_calibration | model, features, labels | results | spec_logistic_model_v2.md §3 |
| M13 run_ml_benchmark | features, labels | benchmark | spec_logistic_model_v2.md §4 |
| M14 run_ablation | features_all, labels | ablation_results | spec_ablation_v2.md |
| M15 generate_figures | joint_results, results, benchmark, ablation | EPS/PDF files | §5 |
| M16 main_run_all | params | (모든 결과 저장) | spec_run_joint.md §6.2 |

---

## 5. 파라미터 테이블

모든 파라미터는 `params` 구조체로 일원 관리.

### 5.1 데이터 로딩 / 열 이름 매핑

| 파라미터 | 기본값 | 설명 |
|---------|--------|------|
| `params.col_x` | `'x_coord_n_'` | MATLAB readtable 자동 변환된 x좌표 열 이름 |
| `params.col_y` | `'y_coord_n_'` | y좌표 열 이름 |
| `params.col_freq` | `'Freq_GHz_'` | 주파수 열 이름 |
| `params.col_mag_rx1` | `'mag_S_rx1_p1_tx_p1___'` | rx1 S21 진폭 열 |
| `params.col_ang_rx1` | `'ang_deg_S_rx1_p1_tx_p1___deg_'` | rx1 S21 위상 열 |
| `params.col_mag_rx2` | `'mag_S_rx2_p1_tx_p1___'` | rx2 S21 진폭 열 |
| `params.col_ang_rx2` | `'ang_deg_S_rx2_p1_tx_p1___deg_'` | rx2 S21 위상 열 |
| `params.coord_unit` | `'mm'` | 좌표 단위 (PLACEHOLDER: 확인 필요) |
| `params.phase_unit` | `'deg'` | 위상 단위 |
| `params.case_label_map` | containers.Map | case 식별자 → LoS/NLoS 매핑 (PLACEHOLDER) |

> **PLACEHOLDER**: `params.col_*` 기본값은 MATLAB R2021b readtable의 `VariableNamingRule='modify'`
> 기준. R2023a 이상에서는 다를 수 있음. 실제 값은 `T.Properties.VariableNames` 확인.

### 5.2 CIR 합성

| 파라미터 | 기본값 | 단위 | 근거 |
|---------|--------|------|------|
| `params.window_type` | `'hanning'` | — | sidelobe 억제 (-31 dB), false multipath peak 방지. Kaiser(β=6) 대안은 -44 dB, ablation 대상 |
| `params.zeropad_factor` | `4` | — | 시간 해상도 4배 향상. BW=7.5 GHz 기준 Δt ≈ 33 ps (T_w=2 ns 윈도우 내 ~60 샘플) |
| `params.freq_range_ghz` | `[3.1, 10.6]` | GHz | UWB Ch5–Ch9, IEEE 802.15.4a 호환 (실제 범위는 데이터 확인 후 조정) |

### 5.3 First-path 검출

| 파라미터 | 기본값 | 단위 | 근거 |
|---------|--------|------|------|
| `params.fp_threshold_ratio` | `0.20` | — | Dardari et al., *IEEE Trans. Commun.*, 2009 |
| `params.fp_search_window_ns` | `[]` (전체) | ns | 빈 배열 = 전체 CIR; ranging용: `[0, 100]` 등 |

### 5.4 Feature 추출

| 파라미터 | 기본값 | 단위 | 근거 |
|---------|--------|------|------|
| `params.T_w` | `2.0` | ns | IEEE 802.15.4a CM3 first cluster ≈ 1–2 ns |
| `params.min_power_dbm` | `-120` | dBm | noise floor 추정 |
| `params.r_CP_clip` | `10000` | linear (= 40 dB) | Inf 방지 |
| `params.afp_cir_source` | `'RHCP'` | — | 초기값; ablation A4에서 최종 확정 |

### 5.5 RSSD / 위치추정

| 파라미터 | 기본값 | 단위 | 근거 |
|---------|--------|------|------|
| `params.rssd_interp_method` | `'pchip'` | — | 단조 보간, IoT-J(2025) 동일 방법론 |
| `params.c0` | `299792458` | m/s | 광속 |

### 5.6 분류 실험

| 파라미터 | 기본값 | 설명 |
|---------|--------|------|
| `params.cv_folds` | `5` | Stratified K-fold |
| `params.random_seed` | `42` | 재현성 |
| `params.normalize` | `true` | z-score 정규화 |
| `params.skip_classification` | `false` | LoS-only 시 자동 `true` |
| `params.nlos_min_count` | `10` | gate threshold |

---

## 5.2 LoS-only Gate 로직

```matlab
% main_run_all.m 내 Phase 1C에서 수행
n_valid = sum(feature_table.valid_flag);
n_nlos  = sum(feature_table.label(feature_table.valid_flag) == false);

if n_nlos < params.nlos_min_count
    params.skip_classification = true;
    warning('[Gate] NLoS samples: %d (threshold: %d). Classification SKIPPED.', ...
            n_nlos, params.nlos_min_count);
    % → Phase 2 전체 skip, Fig P1만 생성
end
```

---

## 6. Figure 목록 (ISAP 2–4 pages)

| Fig # | 제목 | 데이터 조건 | 내용 |
|-------|------|-----------|------|
| **1** | Feature Scatter + Decision Boundary | LoS+NLoS 필수 | `log10(r_CP)` vs `a_FP` 2D scatter, LoS/NLoS 색상 구분, Logistic 결정 경계 |
| **2** | ROC Curves | LoS+NLoS 필수 | Logistic / SVM / RF / DNN 4개 ROC 곡선 + AUC 범례 |
| **3** | Accuracy vs FLOPs | LoS+NLoS 필수 | FLOPs(x축, log scale) vs AUC(y축) 산점도, 1~2 orders of magnitude 차이 강조 |
| **4** | Calibration Reliability Diagram | LoS+NLoS 필수 | Logistic 10-bin reliability diagram |
| **S1** | Feature Distribution | LoS+NLoS 필수 | r_CP, a_FP 히스토그램 (LoS/NLoS 중첩) |
| **S2** | Ablation AUC Bar Chart | LoS+NLoS 필수 | r_CP only / a_FP only / combined AUC 비교 |
| **P1** | LoS-only Preview | LoS only 가능 | r_CP·a_FP 분포 + 위치추정 오차 scatter (중간 검증용) |

> Fig 1–3이 2-page 논문의 핵심. Fig 4, S1, S2는 지면에 따라 배치.
> Fig P1은 NLoS 데이터 확보 전 중간 발표용.

---

## 7. 디렉토리 구조 (v2)

```
track3-cp-uwb-reliability/
├── docs/
│   └── ARCHITECTURE.md              ← 이 파일
├── specs/
│   ├── spec_load_and_build.md        ← M01, M02
│   ├── spec_extract_features_v2.md  ← M03–M06
│   ├── spec_rssd_localization.md    ← M07–M09
│   ├── spec_logistic_model_v2.md    ← M11–M13
│   ├── spec_run_joint.md            ← M10, M16
│   ├── spec_ablation_v2.md          ← M14
│   └── (archive) spec_extract_features.md   ← v1 (참조용)
│   └── (archive) spec_logistic_model.md     ← v1 (참조용)
├── src/
│   ├── load_sparam_table.m
│   ├── build_sim_data_from_table.m
│   ├── detect_first_path.m
│   ├── extract_rcp.m
│   ├── extract_afp.m
│   ├── extract_features_batch.m
│   ├── build_rssd_lut.m
│   ├── estimate_doa_rssd.m
│   ├── estimate_position.m
│   ├── run_joint_phase1.m
│   ├── train_logistic.m
│   ├── eval_roc_calibration.m
│   ├── run_ml_benchmark.m
│   ├── run_ablation.m
│   ├── generate_figures.m
│   └── main_run_all.m
├── data/
│   ├── cp_caseA.csv                 ← 실데이터 (.gitignore)
│   ├── cp_caseB.csv
│   ├── cp_caseC.csv
│   ├── lp_caseA.csv
│   ├── lp_caseB.csv
│   └── lp_caseC.csv
├── results/                         ← 자동 생성
├── figures/                         ← 자동 생성
└── prompts/
```

---

*최종 수정: 2026-04-05 | 작성자: Claude Code (Architecture Agent) v2*
