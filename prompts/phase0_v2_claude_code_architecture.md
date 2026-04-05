# Phase 0 v2: Claude Code — 통합 아키텍처 설계 프롬프트

## 컨텍스트 (Claude Code 세션 시작 시 그대로 붙여넣기)

```
너는 POSTECH EEE 박사과정 연구자의 연구 코드 아키텍트 역할을 수행한다.

## 연구 배경
- 프로젝트: Track 3 — CP-UWB 물리 지표 기반 초경량 공간 신뢰도 점수 산출
- 투고처: ISAP 2026 (2~4 pages), 마감 2026.06.26
- 핵심 기여: r_CP와 a_FP 두 물리 지표의 Logistic Regression 결합으로
  ML 대비 동등 정확도 + 1~2 orders of magnitude 낮은 연산 복잡도 달성 입증
- 언어: MATLAB (R2021b 이상)
- 선행 논문: IEEE IoT-J (2025) — RSSD 기반 O(1) DoA 추정
              IEEE TAP (2025) — Multi-Pose Field-of-View Compensation

## v1 대비 변경 사항 (v2에서 반영 필수)
1. Feature 추출 + 위치추정을 Phase 1에서 통합 수행 (Joint Phase 1)
2. SIM1/SIM2 placeholder 폐기 → CSV/MAT 실데이터 로더 + IFFT 기반 CIR 합성
3. CP/LP 데이터 역할 분리: guide(inc_ang) → LUT 생성, test(x_y_coord) → 추정
4. RSSD 기반 각도추정 모듈 추가 (선행 논문 방법론 재사용)
5. extract_features_batch가 sim_data도 반환 (localization 재사용)
6. 현재 데이터는 LoS only → 분류 실험 gate 필요, NLoS 시나리오는 별도 진행 중
7. valid_flag, fp_idx를 feature_table에 직접 포함
8. detect_first_path에 search_window 옵션 추가 (ranging에도 재사용)
9. r_CP edge case: both below noise floor → NaN + TODO

## 물리 지표 정의 (v1과 동일, 변경 없음)
1. r_CP = P_RHCP_fp / P_LHCP_fp  (linear scale)
   - LoS: r_CP >> 1, NLoS(홀수반사): r_CP ≈ 1 또는 < 1
2. a_FP = E_fp / E_total  ∈ [0, 1]
   - LoS: a_FP → 1, dense multipath: a_FP → 0

## 데이터 구조 (v2: 실데이터 기반)
현재 보유 데이터는 S-parameter 측정 테이블 형태:
- CSV 또는 MAT 파일, 주파수 도메인 데이터
- RHCP/LHCP 각각의 S21 (복소수, mag+phase 또는 real+imag)
- 주파수 축: 예) 3.1~10.6 GHz, N_freq 포인트
- 위치/각도 정보: inc_ang (입사각, guide용) 또는 x_y_coord (좌표, test용)
- 현재 LoS only, NLoS 시나리오는 별도 시뮬레이션 진행 중 (추후 동일 파이프라인 투입)

CIR 합성 방법:
- S21(freq) → windowing(Hanning) → zero-padding → IFFT → CIR(time)
- 시간 해상도: Δt = 1/BW_padded

## 프로젝트 구조
GitHub 레포로 관리. 코드 구현은 Codex가 담당.
너의 역할:
(1) 전체 코드 아키텍처 설계 → ARCHITECTURE.md
(2) 각 모듈 구현 명세(spec) 작성 → specs/ 디렉토리
(3) Codex 구현 코드 리뷰 → REVIEW_*.md
(4) 시뮬레이션 결과 분석 → 논문 Figure 사양 정의

## 출력 규칙
- 모든 출력은 Markdown, GitHub 커밋 가능 형태
- 코드 구현 금지 (함수 시그니처 + pseudocode만)
- 모든 수치 파라미터에 근거 명시
- 모르는 것은 PLACEHOLDER, 확인 필요한 것은 TODO
```

---

## 태스크: 아래 7개 파일을 생성하라

---

### 파일 1: docs/ARCHITECTURE.md

전체 파이프라인을 다음 구조로 설계:

#### 1.1 모듈 목록 및 의존성 DAG

```
M01  load_sparam_table.m        — S-param CSV/MAT 로드
M02  build_sim_data_from_table.m — IFFT → CIR 합성 → sim_data 구조체 생성
M03  detect_first_path.m        — Leading-edge first-path 검출 (공용)
M04  extract_rcp.m              — r_CP 계산
M05  extract_afp.m              — a_FP 계산
M06  extract_features_batch.m   — 전체 위치에 대한 feature 일괄 추출 + sim_data 반환
M07  build_rssd_lut.m           — guide(inc_ang) 데이터로 RSSD LUT 생성
M08  estimate_doa_rssd.m        — RSSD LUT 기반 DoA 추정
M09  estimate_position.m        — DoA + ranging → 2D 위치 추정
M10  run_joint_phase1.m         — Feature 추출 + 위치추정 통합 실행
M11  train_logistic.m           — Logistic Regression 학습
M12  eval_roc_calibration.m     — ROC, Calibration, ECE 평가
M13  run_ml_benchmark.m         — 4개 모델 비교 벤치마크
M14  run_ablation.m             — r_CP only / a_FP only / combined 비교
M15  generate_figures.m         — 논문용 Figure 일괄 생성
M16  main_run_all.m             — 전체 파이프라인 마스터 스크립트
```

의존성:
```
M01 → M02 → M06 → M10
                      ↗
M03 → M04, M05 → M06
M07 → M08 → M09 → M10
M06 → M11 → M12
M06 → M13, M14
M12, M13, M14 → M15
M10, M15 → M16
```

#### 1.2 데이터 흐름도

```
[S-param CSV/MAT]
      │  M01: load_sparam_table
      ▼
[freq_table: freq, S21_RHCP, S21_LHCP, inc_ang/x_y, ...]
      │  M02: build_sim_data_from_table
      │       - windowing (Hanning)
      │       - zero-padding (factor: params.zeropad_factor, 기본 4)
      │       - IFFT
      │       - 시간축 생성
      ▼
[sim_data 구조체]
  .CIR_RHCP  [N_pos × N_tap] complex
  .CIR_LHCP  [N_pos × N_tap] complex
  .t_axis    [1 × N_tap] ns
  .fs        scalar Hz (= BW × zeropad_factor)
  .pos_id    [N_pos × 1] uint32
  .labels    [N_pos × 1] logical (현재: all true, 추후 NLoS CSV 결합)
  .inc_ang   [N_pos × 1] double deg (guide 데이터인 경우)
  .x_y_coord [N_pos × 2] double m  (test 데이터인 경우)
  .data_role 'guide' | 'test'
  .RSS_RHCP  [N_pos × 1] double dBm (CIR 전체 에너지로 계산)
  .RSS_LHCP  [N_pos × 1] double dBm
      │
      ├──────────────────────────────┐
      │                              │
      ▼  M06: extract_features       ▼  M07~M09: RSSD localization
[feature_table]                  [position_estimates]
  .r_CP, .a_FP, .label,           .doa_est, .range_est,
  .pos_id, .valid_flag,            .x_est, .y_est,
  .fp_idx_RHCP, .fp_idx_LHCP      .doa_error, .range_error
      │                              │
      ▼  M10: run_joint_phase1       │
[joint_results: features + positions]◄┘
      │
      ├── (LoS/NLoS 라벨 있을 때만) ──┐
      ▼                               ▼
  M11~M14: 분류 실험              M15: Figure 생성
```

#### 1.3 파라미터 테이블

아래 파라미터 전체를 params 구조체로 관리:

**데이터 로딩 / CIR 합성:**
| 파라미터 | 기본값 | 단위 | 근거 |
|---------|--------|------|------|
| params.window_type | 'hanning' | — | sidelobe 억제, UWB CIR 합성 표준 |
| params.zeropad_factor | 4 | — | 시간 해상도 4배 향상, 통상적 선택 |
| params.freq_range_ghz | [3.1, 10.6] | GHz | UWB Ch5~Ch9 커버, IEEE 802.15.4a 호환 |

**First-path 검출:**
| 파라미터 | 기본값 | 단위 | 근거 |
|---------|--------|------|------|
| params.fp_threshold_ratio | 0.20 | — | Dardari et al., IEEE Trans. Commun., 2009 |
| params.fp_search_window_ns | [] (전체) | ns | 빈 배열 = 전체 CIR 탐색, ranging용: [0, 100] 등 |

**Feature 추출:**
| 파라미터 | 기본값 | 단위 | 근거 |
|---------|--------|------|------|
| params.T_w | 2.0 | ns | IEEE 802.15.4a CM3 first cluster ≈ 1-2 ns |
| params.min_power_dbm | -120 | dBm | noise floor |
| params.r_CP_clip | 10000 | linear | = 40 dB, Inf 방지 |
| params.afp_cir_source | 'RHCP' | — | 초기값 RHCP, ablation에서 최종 확정 |

**RSSD / 위치추정:**
| 파라미터 | 기본값 | 단위 | 근거 |
|---------|--------|------|------|
| params.rssd_interp_method | 'pchip' | — | 단조 보간, IoT-J(2025) 동일 |
| params.c0 | 299792458 | m/s | 광속 |

**분류 실험:**
| 파라미터 | 기본값 | 단위 | 근거 |
|---------|--------|------|------|
| params.cv_folds | 5 | — | Stratified K-fold |
| params.random_seed | 42 | — | 재현성 |
| params.normalize | true | — | z-score |
| params.skip_classification | false | — | LoS-only 데이터 시 자동 true |

#### 1.4 Figure 목록 (ISAP 2~4p 기준)

| Fig # | 내용 | 데이터 요구 | 비고 |
|-------|------|-----------|------|
| 1 | 2D Scatter (log10(r_CP) vs a_FP, LoS/NLoS 색상) + decision boundary | LoS+NLoS 필수 | 핵심 Figure |
| 2 | ROC Curve (4개 모델 비교) | LoS+NLoS 필수 | |
| 3 | Accuracy vs FLOPs (log scale) | LoS+NLoS 필수 | |
| 4 | Calibration Reliability Diagram | LoS+NLoS 필수 | 지면 허용 시 |
| S1 | r_CP 분포 히스토그램 (LoS vs NLoS) | LoS+NLoS 필수 | 보조 자료 |
| S2 | Ablation bar chart (AUC: r_CP only / a_FP only / combined) | LoS+NLoS 필수 | |
| P1 | LoS-only 가용: r_CP, a_FP 분포 + 위치추정 오차 scatter | LoS only 가능 | 중간 검증용 |

#### 1.5 LoS-only Gate 로직

```
main_run_all.m 시작 시:
  n_nlos = sum(labels == false)
  if n_nlos == 0
    warning('NO NLoS samples. Classification skipped.')
    params.skip_classification = true
    → M06, M10만 실행 (feature 추출 + 위치추정)
    → Fig P1만 생성
  else
    → 전체 파이프라인 실행
    → Fig 1~4, S1~S2 생성
  end
```

---

### 파일 2: specs/spec_load_and_build.md

M01 (load_sparam_table) + M02 (build_sim_data_from_table) 구현 명세.

#### 2.1 M01: load_sparam_table

```matlab
function freq_table = load_sparam_table(filepath, params)
% LOAD_SPARAM_TABLE  S-parameter CSV 또는 MAT 파일 로드
%
% 입력:
%   filepath - string, .csv 또는 .mat 경로
%   params   - struct:
%     .freq_col       = 'freq_ghz'     (주파수 열 이름)
%     .s21_rhcp_cols  = {'S21_RHCP_re', 'S21_RHCP_im'}  또는 {'S21_RHCP_mag', 'S21_RHCP_phase'}
%     .s21_lhcp_cols  = {'S21_LHCP_re', 'S21_LHCP_im'}
%     .coord_cols     = {'inc_ang'}     (guide) 또는 {'x_m', 'y_m'} (test)
%     .data_role      = 'guide' | 'test'
%     .input_format   = 'ri' | 'mp'    (real/imag 또는 mag/phase)
%     .phase_unit     = 'deg' | 'rad'  (mp일 때)
%
% 출력:
%   freq_table - MATLAB table:
%     freq_ghz   [N_freq × 1]
%     S21_RHCP   [N_freq × 1] complex
%     S21_LHCP   [N_freq × 1] complex
%     group_id   [N_freq × 1] uint32 (같은 위치/각도 → 같은 group)
%     inc_ang    또는 x_m, y_m
%
% TODO: 실제 CSV 열 이름은 파일 확인 후 params 기본값 갱신
%       MAT 파일인 경우 fieldnames 기반 자동 탐지 시도
```

구현 요구사항:
- CSV: readtable → 열 이름 매핑 → complex 변환
- MAT: load → fieldnames → 자동 매핑 시도 + 실패 시 에러
- input_format='mp'일 때: S21 = mag .* exp(1j * phase_rad)
- group_id: 동일 위치/각도 데이터를 그룹핑 (주파수 sweep 한 세트 = 1 group)
- 빈 열, NaN 체크 → 경고 출력

#### 2.2 M02: build_sim_data_from_table

```matlab
function sim_data = build_sim_data_from_table(freq_table, params)
% BUILD_SIM_DATA_FROM_TABLE  주파수 도메인 S-param → 시간 도메인 CIR 변환
%
% 입력:
%   freq_table - M01 출력
%   params     - struct:
%     .window_type     = 'hanning'
%     .zeropad_factor  = 4
%     .freq_range_ghz  = [3.1, 10.6]  (사용할 주파수 범위)
%
% 출력:
%   sim_data - struct (ARCHITECTURE.md §1.2의 sim_data 구조체)
%
% 알고리즘:
%   1. group_id별로 그룹핑 → N_pos개 그룹
%   2. 각 그룹에서:
%      a. freq_range 내 주파수만 선택
%      b. Hanning window 적용: S21_win = S21 .* hanning(N_freq)
%      c. zero-padding: N_fft = N_freq × zeropad_factor
%      d. IFFT: cir = ifft(S21_win_padded, N_fft)
%      e. 시간축: t = (0 : N_fft-1) / (BW_padded) → ns 변환
%         BW_padded = (freq_max - freq_min) × zeropad_factor
%         실제: dt = 1 / (N_fft × df), df = freq(2) - freq(1)
%   3. RSS 계산: RSS_dBm = 10*log10(sum(|cir|^2)) + 30 (TODO: 교정 상수 확인)
%   4. 라벨 처리:
%      - params.label_csv 경로가 있으면 → 외부 CSV에서 pos_id 기준 join
%      - 없으면 → labels = true(N_pos, 1) + warning('All LoS assumed')
%   5. sim_data 구조체 조립
%
% IFFT 파라미터 근거:
%   - Hanning window: mainlobe 폭 2배 증가 vs sidelobe -31 dB 억제 trade-off
%     UWB CIR 합성에서 sidelobe가 false multipath peak으로 오인되는 것 방지
%   - zeropad_factor=4: BW=7.5GHz 기준 Δt = 1/(7.5e9×4) ≈ 33 ps
%     T_w=2ns 윈도우 내 ~60 샘플 확보 → first-path 에너지 계산 충분
%   - Hanning 대신 Kaiser(β=6) 사용 시 sidelobe -44 dB로 개선 가능
%     → TODO: sensitivity 비교 후 최종 선택
```

구현 요구사항:
- group_id가 없는 경우: 단일 위치로 가정 (N_pos=1)
- 주파수 간격 불균일 시: warning 후 보간 또는 에러
- CIR 출력은 causal part만 사용 (t ≥ 0)
- progress: fprintf로 매 그룹 진행률 출력

---

### 파일 3: specs/spec_extract_features_v2.md

M03~M06 구현 명세. v1 대비 변경점 명시.

#### 3.1 M03: detect_first_path (v2 변경: search_window 추가)

```matlab
function [fp_idx, fp_info] = detect_first_path(cir_abs, params)
% DETECT_FIRST_PATH  Leading-edge first-path 검출
%
% 입력:
%   cir_abs - [N_tap × 1] double, |CIR|
%   params  - struct:
%     .fp_threshold_ratio  = 0.20
%     .fp_search_window    = [] (전체) 또는 [start_idx, end_idx]
%
% 출력:
%   fp_idx  - scalar uint32, first-path 인덱스 (NaN if not found)
%   fp_info - struct:
%     .peak_idx    = peak 위치
%     .peak_val    = peak 절대값
%     .threshold   = 사용된 임계값
%     .search_range = [start, end] 실제 탐색 범위
%
% v2 변경점:
%   - search_window 옵션 추가: ranging용으로 탐색 범위 제한 가능
%   - fp_info 구조체 반환: 디버깅/시각화 지원
%
% 알고리즘:
%   1. search_window 적용 (비어있으면 전체)
%   2. cir_search = cir_abs(start:end)
%   3. peak_val = max(cir_search)
%   4. threshold = fp_threshold_ratio × peak_val
%   5. fp_idx = min{k : cir_search(k) > threshold} + start - 1
```

#### 3.2 M04: extract_rcp (v1과 동일, edge case 보강)

```matlab
function [r_CP, rcp_info] = extract_rcp(cir_rhcp, cir_lhcp, params)
% 입력: [N_tap × 1] complex 각각
% 출력: r_CP scalar (linear), rcp_info struct
%
% Edge case 처리 (v2 보강):
%   P_RHCP == 0 && P_LHCP == 0 → r_CP = NaN, rcp_info.flag = 'both_below_floor'
%   P_LHCP == 0 && P_RHCP > 0  → r_CP = params.r_CP_clip
%   P_RHCP == 0 && P_LHCP > 0  → r_CP = 0 (NLoS 극단)
%
% TODO: 'both_below_floor' 케이스의 최종 처리 방식은 데이터 확인 후 확정
```

#### 3.3 M05: extract_afp (v2 변경: cir_source 선택)

```matlab
function [a_FP, afp_info] = extract_afp(cir_rhcp, cir_lhcp, t_axis, params)
% v2 변경: params.afp_cir_source에 따라 CIR 선택
%   'RHCP'    → cir = cir_rhcp (기본값, 초기 구현)
%   'LHCP'    → cir = cir_lhcp
%   'combined' → cir = (cir_rhcp + cir_lhcp) / 2
%   'power_sum' → cir_power = |cir_rhcp|^2 + |cir_lhcp|^2, sqrt로 복원
%
% 초기값 RHCP 선택 근거:
%   RHCP 채널에서 LoS 직접경로가 dominant → a_FP 분리도 높을 것으로 예상
%   단, 이것은 ablation에서 검증할 가설임
%
% ablation 항목 (M14에서 수행):
%   a_FP(RHCP) vs a_FP(LHCP) vs a_FP(combined) vs a_FP(power_sum)
```

#### 3.4 M06: extract_features_batch (v2 변경: sim_data 반환 + valid_flag 포함)

```matlab
function [feature_table, sim_data] = extract_features_batch(sim_data, params)
% v2 변경점:
%   1. sim_data를 두 번째 출력으로 반환 (localization 재사용)
%   2. feature_table에 valid_flag, fp_idx_RHCP, fp_idx_LHCP 직접 포함
%   3. r_CP = Inf → params.r_CP_clip으로 클리핑
%   4. label fallback: labels가 없거나 모두 NaN → false + warning
%
% 출력 feature_table 컬럼:
%   pos_id      [uint32]   위치 인덱스
%   r_CP        [double]   linear, [0, r_CP_clip]
%   a_FP        [double]   [0, 1]
%   label       [logical]  true=LoS, false=NLoS
%   valid_flag  [logical]  true=유효 (NaN/Inf edge case 아님)
%   fp_idx_RHCP [uint32]   RHCP first-path 인덱스
%   fp_idx_LHCP [uint32]   LHCP first-path 인덱스
%   RSS_RHCP    [double]   dBm
%   RSS_LHCP    [double]   dBm
```

---

### 파일 4: specs/spec_rssd_localization.md

M07~M09 구현 명세 (신규).

#### 4.1 M07: build_rssd_lut

```matlab
function lut = build_rssd_lut(sim_data_guide, params)
% BUILD_RSSD_LUT  guide(inc_ang) 데이터로 RSSD vs 입사각 LUT 생성
%
% 입력:
%   sim_data_guide - sim_data 구조체 (data_role='guide')
%     .RSS_RHCP  [N_ang × 1]  dBm
%     .RSS_LHCP  [N_ang × 1]  dBm  (또는: 안테나 2개 RSS)
%     .inc_ang   [N_ang × 1]  deg, 0~360 (또는 -180~180)
%   params - struct:
%     .rssd_interp_method = 'pchip'
%     .rssd_antenna_pair  = [1, 2]  (어느 두 안테나의 RSS 차이를 사용할지)
%
% 출력:
%   lut - struct:
%     .ang_axis    [M × 1] deg, 보간된 각도 축 (0.1° 간격)
%     .rssd_curve  [M × 1] dB, RSSD = RSS_ant1 - RSS_ant2
%     .rssd_raw    [N_ang × 1] dB, 원본 RSSD
%     .ang_raw     [N_ang × 1] deg, 원본 각도
%     .interp_obj  griddedInterpolant 객체
%
% RSSD 정의:
%   RSSD(θ) = RSS_ant1(θ) - RSS_ant2(θ)  [dB]
%   IoT-J(2025) 선행 논문의 RSSD Slope 기반 O(1) DoA 추정과 동일
%
% 알고리즘:
%   1. 각도 정렬 (오름차순)
%   2. RSSD = RSS(:,1) - RSS(:,2) 계산
%   3. pchip 보간 → 0.1° 해상도 LUT 생성
%   4. 단조성 검증: RSSD_slope이 단조 구간 식별 → monotonic_range 저장
```

#### 4.2 M08: estimate_doa_rssd

```matlab
function [doa_est, doa_info] = estimate_doa_rssd(rssd_measured, lut, params)
% ESTIMATE_DOA_RSSD  측정된 RSSD 값으로 DoA 추정 (LUT 역참조)
%
% 입력:
%   rssd_measured - scalar 또는 [N × 1], 측정된 RSSD [dB]
%   lut           - M07 출력
%
% 출력:
%   doa_est  - [N × 1] deg, 추정 입사각
%   doa_info - struct:
%     .ambiguity_flag  [N × 1] logical (LUT 비단조 구간에서 모호성 존재)
%     .residual        [N × 1] dB (RSSD 잔차)
%
% 알고리즘:
%   1. LUT의 monotonic 구간에서 역보간 (interp1 with 'pchip')
%   2. 비단조 구간: 최소 잔차 후보 선택 + ambiguity_flag = true
%   3. O(1) 복잡도: LUT 크기 고정 → 보간 연산만
```

#### 4.3 M09: estimate_position

```matlab
function [pos_est, pos_info] = estimate_position(sim_data_test, lut, params)
% ESTIMATE_POSITION  DoA + ranging → 2D 위치 추정
%
% 입력:
%   sim_data_test - sim_data 구조체 (data_role='test')
%     .CIR_RHCP, .CIR_LHCP  (ranging용)
%     .RSS_RHCP, .RSS_LHCP   (RSSD DoA용)
%     .x_y_coord [N × 2]     (ground truth, 오차 계산용)
%   lut - M07 출력
%
% 출력:
%   pos_est - table:
%     .pos_id      [uint32]
%     .doa_est     [double] deg
%     .range_est   [double] m (CIR first-path ToA 기반)
%     .x_est       [double] m
%     .y_est       [double] m
%     .doa_error   [double] deg (ground truth 대비)
%     .range_error [double] m
%     .pos_error   [double] m (유클리드 거리)
%
% 알고리즘:
%   1. RSS 계산: sim_data의 CIR에서 RSS 추출 (이미 sim_data에 포함)
%   2. RSSD = RSS_ant1 - RSS_ant2
%   3. DoA = estimate_doa_rssd(RSSD, lut)
%   4. Ranging: first-path ToA × c0 / 2
%      - detect_first_path 호출 (RHCP CIR 사용)
%      - range = (t_axis(fp_idx) × 1e-9) × params.c0 / 2
%      - TODO: single-sided vs round-trip 확인 필요
%   5. 위치: x = range × cos(doa), y = range × sin(doa)
%      - TODO: 좌표계 정의 확인 (앵커 원점, 각도 기준)
```

---

### 파일 5: specs/spec_logistic_model_v2.md

M11~M12 구현 명세. v1 대비 변경점:

#### 5.1 변경점 요약

- DNN 구조: sigmoidLayer → softmaxLayer + classificationLayer (R2021b 호환)
- 추론 시간 측정: warm-up 10회 추가 + 수동 연산 버전 병렬 측정
- FLOPs 표현: "1~2 orders of magnitude" (3~4자릿수 → 하향 조정)
- AUC 하한: 0.85 → 0.80 (경계 조건 허용)
- 비교군 확장 (선택): CIR 전체 입력 CNN baseline 추가 시 3자릿수 달성 가능

나머지 내용은 v1과 동일. v1 spec의 §1~§7 전체를 포함하되, 위 변경점만 수정.

#### 5.2 DNN 구조 수정 (R2021b 호환)

```matlab
layers = [
    featureInputLayer(2)
    fullyConnectedLayer(16)
    reluLayer
    fullyConnectedLayer(8)
    reluLayer
    fullyConnectedLayer(2)          % 1이 아닌 2 (2-class)
    softmaxLayer
    classificationLayer
];
% FLOPs 재계산:
%   FC(2→16): 64, ReLU(16): 16, FC(16→8): 144, ReLU(8): 8,
%   FC(8→2): 18, Softmax(2): ~10
%   총: ~260 FLOPs (v1의 265와 유사)
```

#### 5.3 추론 시간 측정 수정

```matlab
% Warm-up (측정 제외)
for i = 1:10, predict(mdl, X(1,:)); end

% MATLAB predict 호출
tic; for i = 1:1000, predict(mdl, X(1,:)); end; t1 = toc;
infer_time_predict_us = t1 / 1000 * 1e6;

% Logistic 수동 연산 (실제 O(1) 구현)
coeffs = model.coeffs;
x_norm = (X(1,:) - model.norm_mu) ./ model.norm_sigma;
tic;
for i = 1:1000
    z = coeffs(1) + coeffs(2)*x_norm(1) + coeffs(3)*x_norm(2);
    p = 1 / (1 + exp(-z));
end
t2 = toc;
infer_time_manual_us = t2 / 1000 * 1e6;

% 논문에서는 FLOPs 비교를 주 지표로 사용 (실행 환경 의존성 제거)
```

---

### 파일 6: specs/spec_run_joint.md

M10 (run_joint_phase1) + M16 (main_run_all) 구현 명세.

#### 6.1 M10: run_joint_phase1

```matlab
function joint_results = run_joint_phase1(sim_data_guide, sim_data_test, params)
% RUN_JOINT_PHASE1  Feature 추출 + 위치추정 통합 실행
%
% 입력:
%   sim_data_guide - guide(inc_ang) 데이터 (LUT 생성용)
%   sim_data_test  - test(x_y_coord) 데이터 (추정 대상)
%   params         - 전체 파라미터
%
% 출력:
%   joint_results - struct:
%     .feature_table  — M06 출력 (test 데이터 기반)
%     .sim_data_test  — CIR/RSS 포함 sim_data
%     .lut            — M07 출력 (guide 기반 RSSD LUT)
%     .pos_est        — M09 출력 (위치추정 결과)
%     .params         — 사용된 파라미터 기록
%
% 실행 흐름:
%   1. guide 데이터 feature 추출 (LUT 생성용 RSS 확보)
%   2. build_rssd_lut(sim_data_guide, params)
%   3. test 데이터 feature 추출
%   4. estimate_position(sim_data_test, lut, params)
%   5. 결과 조립
%
% 독립 호출 가능:
%   - run_features_only: M06만 실행 (guide/test 구분 없이)
%   - run_localization_only: M07~M09만 실행
%   - run_joint: 위 전체 실행
```

#### 6.2 M16: main_run_all (v2)

```matlab
%% main_run_all.m — Track 3 전체 분석 파이프라인 v2
%
% 실행 흐름:
%   Phase 1A: 데이터 로드 + CIR 합성
%   Phase 1B: Feature 추출 + 위치추정 (Joint)
%   Phase 1C: 라벨 분포 검증 (LoS-only gate)
%   Phase 2:  분류 실험 (gate 통과 시에만)
%   Phase 3:  Figure 생성
%
% 핵심 gate 로직:
%   n_nlos = sum(feature_table.label == false & feature_table.valid_flag == true);
%   if n_nlos < 10
%     params.skip_classification = true;
%     warning('Insufficient NLoS samples (%d). Classification skipped.', n_nlos);
%   end

%% Phase 1A: 데이터 로드
freq_table_guide = load_sparam_table(params.guide_filepath, params_guide);
freq_table_test  = load_sparam_table(params.test_filepath, params_test);
sim_data_guide   = build_sim_data_from_table(freq_table_guide, params);
sim_data_test    = build_sim_data_from_table(freq_table_test, params);

%% Phase 1B: Joint Feature + Localization
joint_results = run_joint_phase1(sim_data_guide, sim_data_test, params);
feature_table = joint_results.feature_table;
pos_est       = joint_results.pos_est;

%% Phase 1C: Label gate
labels = feature_table.label(feature_table.valid_flag);
n_los  = sum(labels == true);
n_nlos = sum(labels == false);
fprintf('Labels: LoS=%d, NLoS=%d, Invalid=%d\n', n_los, n_nlos, sum(~feature_table.valid_flag));

if n_nlos < 10
    params.skip_classification = true;
    warning('Classification skipped (NLoS=%d < 10)', n_nlos);
end

%% Phase 2: Classification (conditional)
if ~params.skip_classification
    features_valid = [feature_table.r_CP(feature_table.valid_flag), ...
                      feature_table.a_FP(feature_table.valid_flag)];
    labels_valid   = labels;
    
    [model, norm_params] = train_logistic(features_valid, labels_valid, params);
    results    = eval_roc_calibration(model, norm_params, features_valid, labels_valid, params);
    benchmark  = run_ml_benchmark(features_valid, labels_valid, params);
    ablation   = run_ablation(features_valid, labels_valid, params);
end

%% Phase 3: Figures
if params.skip_classification
    generate_figures_losonly(feature_table, pos_est, params);   % Fig P1
else
    generate_figures(feature_table, model, results, benchmark, ablation, params);
end

%% Save all
save(fullfile('results', 'all_results_v2.mat'), ...
    'joint_results', 'params', '-v7.3');
if ~params.skip_classification
    save(fullfile('results', 'classification_results.mat'), ...
        'model', 'norm_params', 'results', 'benchmark', 'ablation');
end
```

---

### 파일 7: specs/spec_ablation_v2.md

M14 구현 명세. v1 대비 추가된 ablation 항목:

```
기존 (v1):
  A1. r_CP only
  A2. a_FP only
  A3. r_CP + a_FP combined

추가 (v2):
  A4. a_FP source comparison: RHCP / LHCP / combined / power_sum
  A5. r_CP definition: single-sample / window-energy
  A6. T_w sensitivity: 1.0 / 1.5 / 2.0 / 2.5 / 3.0 ns
  A7. (선택) r_CP scale: linear+zscore / log10+zscore / dB

A1~A3은 논문 본문 필수.
A4~A7은 데이터에 따라 선택적 수행, 논문에는 유의미한 것만 포함.
```

#### Ablation 출력 형식

```matlab
ablation_results = table:
  config         [string]   — 'r_CP_only', 'a_FP_only', 'combined', ...
  sub_config     [string]   — 'RHCP', 'LHCP', 'T_w=1.0', ...
  auc            [double]
  accuracy       [double]
  f1             [double]
  ece            [double]
  delta_auc      [double]   — combined 대비 차이
```
