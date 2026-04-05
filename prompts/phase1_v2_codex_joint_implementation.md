# Phase 1 v2: Codex — 통합 구현 프롬프트

## 역할
너는 MATLAB 코드 구현 전문가이다. 아래 명세를 정확히 따라 구현하라.
명세에 없는 설계 판단은 하지 마라. 불명확한 부분은 `% TODO: spec 확인 필요` 주석으로 표시하라.

## 구현 환경
- MATLAB R2021b 이상
- 허용 Toolbox: Signal Processing Toolbox
- 코딩 컨벤션: snake_case 변수명, camelCase 함수명, 모든 함수에 docstring
- magic number 금지 (모든 상수는 params 경유)

## 구현 순서 (의존성 순)

### 1. src/private/detect_first_path.m (M03)

specs/spec_extract_features_v2.md §3.1 그대로 구현.

핵심:
- search_window 옵션: 비어있으면 전체 탐색, [start, end]이면 해당 범위만
- fp_info 구조체 반환
- edge case: 모든 샘플이 threshold 미만 → fp_idx = NaN

### 2. src/load_sparam_table.m (M01)

specs/spec_load_and_build.md §2.1 그대로 구현.

핵심:
- CSV: readtable, MAT: load + fieldnames
- input_format 'ri' vs 'mp' 분기
- group_id 생성: 동일 좌표/각도 행 → 같은 group
- complex 변환: S21 = re + 1j*im 또는 mag.*exp(1j*phase)

### 3. src/build_sim_data_from_table.m (M02)

specs/spec_load_and_build.md §2.2 그대로 구현.

핵심:
- group_id별 for loop
- freq_range 필터링
- Hanning window: w = hanning(N_freq_used)
- zero-padding: N_fft = N_freq_used * params.zeropad_factor
- IFFT: cir = ifft(S21_win_padded, N_fft)
- 시간축: dt = 1 / (N_fft * df_hz), t_ns = (0:N_fft-1) * dt * 1e9
  - df_hz = (freq(2) - freq(1)) * 1e9  (GHz → Hz 변환 주의)
- RSS: 10*log10(sum(abs(cir).^2)) (단위: 상대 dB, 교정 없음)
- label 처리: params.label_csv 있으면 readtable+join, 없으면 true+warning
- sim_data.data_role = params.data_role

### 4. src/extract_rcp.m (M04)

specs/spec_extract_features_v2.md §3.2 그대로 구현.
- 내부에서 detect_first_path 호출 (RHCP, LHCP 독립 검출)
- edge case 3분기: both_zero→NaN, lhcp_zero→clip, rhcp_zero→0

### 5. src/extract_afp.m (M05)

specs/spec_extract_features_v2.md §3.3 그대로 구현.
- params.afp_cir_source에 따라 CIR 선택
- 내부에서 detect_first_path 호출

### 6. src/extract_features_batch.m (M06)

specs/spec_extract_features_v2.md §3.4 그대로 구현.
- 두 번째 출력: sim_data (입력 그대로 pass-through)
- feature_table: pos_id, r_CP, a_FP, label, valid_flag, fp_idx_RHCP, fp_idx_LHCP, RSS_RHCP, RSS_LHCP

### 7. src/build_rssd_lut.m (M07)

specs/spec_rssd_localization.md §4.1 그대로 구현.
- RSSD = RSS_ant1 - RSS_ant2 (dB)
  - 안테나 pair 선택: params.rssd_antenna_pair = [1, 2] → RHCP=ant1, LHCP=ant2
  - 또는 RSS_RHCP - RSS_LHCP (기본)
- sortrows by inc_ang
- griddedInterpolant(ang_sorted, rssd_sorted, 'pchip')
- monotonic_range 식별: diff(rssd)의 부호 변화 확인

### 8. src/estimate_doa_rssd.m (M08)

specs/spec_rssd_localization.md §4.2 그대로 구현.
- LUT 역참조: 보간된 RSSD 곡선에서 측정값에 가장 가까운 각도 탐색
- monotonic 구간 내에서만 탐색 → 구간 밖이면 ambiguity_flag = true

### 9. src/estimate_position.m (M09)

specs/spec_rssd_localization.md §4.3 그대로 구현.
- DoA + ranging → (x, y) 변환
- ranging: detect_first_path → t_fp_ns → range = t_fp_ns * 1e-9 * c0 / 2
  - TODO: single-sided vs round-trip 확인 필요 (주석으로 명시)

### 10. src/run_joint_phase1.m (M10)

specs/spec_run_joint.md §6.1 그대로 구현.
- 세 가지 entry point 함수:
  ```matlab
  function results = run_features_only(sim_data, params)
  function results = run_localization_only(sim_data_guide, sim_data_test, params)
  function results = run_joint_phase1(sim_data_guide, sim_data_test, params)
  ```
- run_joint_phase1은 위 두 함수를 순서대로 호출

## 단위 테스트

### tests/test_detect_first_path.m
1. 단일 delta peak → fp_idx = peak 위치
2. 다중 peak (첫 peak이 작음) → leading-edge 정확성 확인
3. search_window 적용 → 범위 밖 peak 무시 확인
4. 전부 0 → fp_idx = NaN

### tests/test_build_sim_data.m
1. 단일 주파수 tone → IFFT 결과 = sinc-like CIR
2. 두 개 tone → 두 개 peak 분리 확인
3. Hanning window 적용 → sidelobe 억제 확인

### tests/test_rssd_lut.m
1. 선형 RSSD 곡선 → 역참조 정확도 < 0.1°
2. 비단조 구간 → ambiguity_flag = true 확인

## 코드 품질 요구사항
- 모든 함수 첫 줄에 one-line summary
- 입출력 변수에 단위 명시 (Hz, ns, dBm, linear, deg 등)
- magic number 금지
- 배열 인덱스 경계 체크 (min/max clamp)
- progress 출력: fprintf로 매 100 위치마다 진행률
- 재현성: rng(params.random_seed) 모든 랜덤 연산 앞
