# Phase 1: Codex — Feature Extraction 구현 프롬프트

## 역할
너는 MATLAB 코드 구현 전문가이다. 아래 명세(spec)를 정확히 따라 구현하라.
명세에 없는 설계 판단은 하지 마라. 불명확한 부분은 `% TODO: spec 확인 필요` 주석으로 표시하라.

## 구현 환경
- MATLAB R2021b 이상
- 외부 toolbox 의존 최소화 (Signal Processing Toolbox만 허용)
- 코딩 컨벤션: snake_case 변수명, camelCase 함수명, 모든 함수에 docstring

## 구현 명세

### 파일 1: src/extract_rcp.m

```
function r_CP = extract_rcp(cir_rhcp, cir_lhcp, fs, params)
% EXTRACT_RCP  RHCP/LHCP 첫 경로 전력비 계산
%
% 입력:
%   cir_rhcp - [N_samples × 1] complex, RHCP 채널 CIR
%   cir_lhcp - [N_samples × 1] complex, LHCP 채널 CIR
%   fs       - scalar, 샘플링 주파수 [Hz]
%   params   - struct with fields:
%     .fp_threshold_ratio  = 0.2  (first-path 검출 임계치, peak 대비 비율)
%     .fp_window_ns        = 2.0  (first-path 에너지 윈도우 [ns])
%     .min_power_dbm       = -120 (최소 유효 전력 [dBm], 이하는 noise floor)
%
% 출력:
%   r_CP - scalar, RHCP/LHCP 첫 경로 전력비 (linear scale, ≥ 0)
%          edge case: LHCP fp power < noise floor → r_CP = Inf로 표기 후
%                     호출측에서 clipping 처리
%
% 알고리즘:
%   1. |cir_rhcp|에서 peak 위치 찾기
%   2. peak × fp_threshold_ratio를 초과하는 최초 인덱스 = first_path_idx
%   3. first_path_idx 기준 ±fp_window_samples 구간의 에너지 합산
%   4. LHCP에 대해 동일 수행
%   5. r_CP = P_rhcp_fp / P_lhcp_fp
```

구현 요구사항:
- first-path 검출은 leading-edge 방식 (peak 이전 방향으로 탐색)
- 에너지 = sum(abs(cir_window).^2)
- fp_window_samples = round(params.fp_window_ns * 1e-9 * fs)
- LHCP의 first-path도 독립적으로 검출 (RHCP의 fp_idx를 공유하지 않음)
- 단위 테스트용 synthetic CIR 생성 함수도 함께 구현: tests/test_extract_rcp.m

### 파일 2: src/extract_afp.m

```
function a_FP = extract_afp(cir, fs, params)
% EXTRACT_AFP  첫 경로 에너지 집중도 계산
%
% 입력:
%   cir    - [N_samples × 1] complex, CIR (RHCP 또는 co-pol 채널)
%   fs     - scalar, 샘플링 주파수 [Hz]
%   params - struct with fields:
%     .fp_threshold_ratio  = 0.2
%     .fp_window_ns        = 2.0
%
% 출력:
%   a_FP - scalar, E_fp / E_total ∈ [0, 1]
%          edge case: E_total = 0 → a_FP = 0
%
% 알고리즘:
%   1. first-path 검출 (extract_rcp과 동일 leading-edge 방식)
%   2. E_fp = sum(abs(cir(fp_idx-W:fp_idx+W)).^2)
%   3. E_total = sum(abs(cir).^2)
%   4. a_FP = E_fp / E_total
%   5. 경계 처리: fp_idx-W < 1이면 1부터, fp_idx+W > N이면 N까지
```

구현 요구사항:
- first-path 검출 로직을 별도 private 함수로 분리: src/private/detect_first_path.m
  - extract_rcp과 extract_afp 양쪽에서 호출
- 단위 테스트: LoS-like CIR (단일 sharp peak) → a_FP ≈ 1.0 확인

### 파일 3: src/extract_features_batch.m

```
function feature_table = extract_features_batch(sim_data_path, params)
% EXTRACT_FEATURES_BATCH  SIM1/SIM2 전체 데이터에서 feature 일괄 추출
%
% 입력:
%   sim_data_path - string, .mat 파일 경로
%   params        - struct (위 params + 추가 필드)
%     .dataset_name = 'SIM1' 또는 'SIM2'
%
% 출력:
%   feature_table - MATLAB table with columns:
%     position_id  [int]     - 측정 위치 고유 ID
%     r_CP         [double]  - RHCP/LHCP 첫 경로 전력비
%     a_FP         [double]  - 첫 경로 에너지 집중도
%     label        [logical] - true=LoS, false=NLoS (ground truth)
%     scenario     [string]  - 시나리오 이름
%     distance_m   [double]  - Tx-Rx 거리 [m] (가용 시)
%
% 주의사항:
%   SIM1/SIM2의 .mat 파일 내부 구조를 모르므로,
%   이 함수의 data loading 부분은 PLACEHOLDER로 구현하고
%   실제 fieldname은 데이터 확인 후 수정할 것.
```

구현 요구사항:
- data loading 부분: `% PLACEHOLDER: 아래 fieldname은 실제 데이터 확인 후 수정`
- r_CP = Inf인 경우 → params.r_CP_clip (기본값 40 dB → linear 10000)으로 clipping
- 결과를 .mat와 .csv 양쪽으로 저장: data/processed/features_SIM1.mat, .csv
- progress bar: fprintf로 매 100 위치마다 진행률 출력

## 단위 테스트 요구사항

### tests/test_extract_rcp.m
다음 3가지 시나리오에 대해 테스트:
1. Pure LoS: CIR = delta(t-t0), RHCP만 강함 → r_CP >> 1
2. Single-bounce NLoS: LHCP가 RHCP보다 강함 → r_CP < 1  
3. Equal power: RHCP ≈ LHCP → r_CP ≈ 1
- synthetic CIR 생성: Gaussian pulse + exponential decay multipath
- assert 조건을 명시적으로 작성

## 코드 품질 요구사항
- 모든 함수 첫 줄에 one-line summary
- 입출력 변수에 단위 명시 (Hz, ns, dBm, linear 등)
- magic number 금지 (모든 상수는 params 구조체 경유)
- 배열 인덱스 경계 체크 (min/max로 clamp)
