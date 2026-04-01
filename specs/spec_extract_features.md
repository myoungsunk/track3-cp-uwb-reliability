# 구현 명세: extract_features.m

> 모듈: M02 | 의존: M01 (data_loader) | 버전: 1.0

---

## 1. 함수 시그니처

```matlab
[r_CP, a_FP, labels, metadata] = extract_features(sim_data, params)
```

### 입력

| 인자 | 타입 | 차원 | 단위 | 설명 |
|------|------|------|------|------|
| `sim_data.CIR_RHCP` | complex double | [N_pos × N_tap] | V | RHCP 채널 임펄스 응답 |
| `sim_data.CIR_LHCP` | complex double | [N_pos × N_tap] | V | LHCP 채널 임펄스 응답 |
| `sim_data.labels` | uint8 | [N_pos × 1] | — | 0=NLoS, 1=LoS |
| `sim_data.pos_id` | uint32 | [N_pos × 1] | — | 위치 인덱스 |
| `sim_data.t_axis` | double | [1 × N_tap] | ns | 시간축 |
| `params.threshold_ratio` | double | scalar | — | First-path 검출 임계값 비율 (기본값: 0.20) |
| `params.T_w` | double | scalar | ns | First-path 에너지 윈도우 반폭 (기본값: 2.0) |

### 출력

| 인자 | 타입 | 차원 | 단위 | 설명 |
|------|------|------|------|------|
| `r_CP` | double | [N_pos × 1] | dimensionless (linear) | RHCP/LHCP first-path 전력비 |
| `a_FP` | double | [N_pos × 1] | dimensionless [0–1] | First-path 에너지 집중도 |
| `labels` | logical | [N_pos × 1] | — | 0=NLoS, 1=LoS |
| `metadata` | table | [N_pos × 1] | — | pos_id, fp_idx_RHCP, fp_idx_LHCP, valid_flag |

---

## 2. SIM1/SIM2 .mat 파일 구조

> **PLACEHOLDER**: 실제 .mat 파일 로드 후 `fieldnames(load('SIM1.mat'))` 로 확인 필요.
> 아래는 가정된 구조이며, 실제 필드명이 다를 경우 `data_loader.m`의 매핑 테이블 수정.

```matlab
% 예상 필드 (확인 필요)
% SIM1.mat (실내 LoS/NLoS 혼재 시나리오)
%   .h_RHCP   : [N_pos × N_tap] complex  — RHCP CIR
%   .h_LHCP   : [N_pos × N_tap] complex  — LHCP CIR
%   .label    : [N_pos × 1]    uint8    — 1=LoS, 0=NLoS
%   .pos_idx  : [N_pos × 1]    uint32
%   .time_ns  : [1 × N_tap]    double   — 단위: ns
%
% SIM2.mat (다중 반사 NLoS 강조 시나리오)
%   — 동일한 필드 구조 가정
```

data_loader.m은 이 필드명을 표준 sim_data 구조체로 변환하는 책임을 가짐.

---

## 3. First-Path 검출 알고리즘

### 3.1 개요

Leading-edge detection: CIR 절대값이 최대값의 일정 비율(`threshold_ratio`)을 **최초로** 초과하는 샘플 인덱스를 first-path로 정의.

### 3.2 수식

```
fp_idx = min{ k : |CIR(k)| > threshold_ratio × max(|CIR|) }
```

### 3.3 근거

`threshold_ratio = 0.20` (기본값)
- 출처: Dardari, D., Conti, A., Ferner, U., Giorgetti, A., & Win, M. Z., "Ranging With Ultrawide Bandwidth Signals in Multipath Environments," *IEEE Trans. Commun.*, vol. 57, no. 4, pp. 1861–1874, Apr. 2009.
- 해당 논문은 dense multipath UWB 환경에서 threshold = 0.15–0.25 범위에서 first-path 검출 오류가 최소화됨을 실험적으로 확인.
- 0.20은 sensitivity-specificity 균형점으로 권장됨.

### 3.4 Pseudocode

```
function fp_idx = detect_first_path(cir_abs, threshold_ratio)
    peak_val   = max(cir_abs)
    threshold  = threshold_ratio * peak_val
    candidates = find(cir_abs > threshold)
    if isempty(candidates)
        fp_idx = NaN   % edge case: 모든 샘플이 임계값 미만
    else
        fp_idx = candidates(1)
    end
end
```

---

## 4. r_CP 계산

### 4.1 수식

```
P_RHCP_fp = |CIR_RHCP(fp_idx_RHCP)|^2
P_LHCP_fp = |CIR_LHCP(fp_idx_LHCP)|^2
r_CP = P_RHCP_fp / P_LHCP_fp          % linear scale
```

### 4.2 Linear vs dB Scale 선택 근거

**Linear scale 채택 이유:**
- Logistic Regression의 sigmoid 함수는 선형 결합 `β₀ + β₁·x₁ + β₂·x₂`에 적용되므로, x₁ = r_CP가 대칭적 분포를 갖는 것이 수렴 안정성에 유리.
- dB scale (`r_CP_dB = 10·log10(r_CP)`)은 LoS 조건에서 r_CP >> 1 구간을 압축하여 정보 손실이 발생할 수 있음.
- 단, linear r_CP는 분포 skewness가 크므로 z-score 정규화로 보정 (train_logistic 단계에서 처리).

> 대안 검토: dB scale 모델도 ablation study로 비교 (Fig. 3 또는 보조 자료).

### 4.3 Edge Case: P_LHCP_fp = 0

```
if P_LHCP_fp == 0
    if P_RHCP_fp == 0
        r_CP = NaN      % 두 극성 모두 신호 없음 → valid_flag = false
    else
        r_CP = Inf      % LHCP 완전 소멸 → LoS 극단 케이스
    end
end
```

`valid_flag = false`인 샘플은 학습/평가에서 제외하고 `metadata.valid_flag`에 기록.

---

## 5. a_FP 계산

### 5.1 수식

```
% First-path 윈도우 인덱스 결정
win_idx = find(t_axis >= t_axis(fp_idx) - T_w  &  t_axis <= t_axis(fp_idx) + T_w)

% CIR은 RHCP와 LHCP 평균 사용 (또는 RHCP만 사용, 선택 명시 필요)
CIR_combined = (CIR_RHCP + CIR_LHCP) / 2

E_fp    = sum(|CIR_combined(win_idx)|^2)
E_total = sum(|CIR_combined|^2)
a_FP    = E_fp / E_total
```

> **설계 결정 PLACEHOLDER**: a_FP 계산 시 RHCP만 사용할지, LHCP만 사용할지, 또는 양극 평균을 사용할지 실험적으로 결정 필요. 초기 구현은 RHCP 단독 사용 권장 (CIR_RHCP의 first-path가 더 강하므로 a_FP 분리도 높을 가능성).

### 5.2 T_w 윈도우 크기 근거

`T_w = 2.0 ns` (양방향 윈도우 총 4 ns)
- IEEE 802.15.4a Channel Model CM3 (indoor office, NLOS): first cluster RMS delay spread ≈ 1–2 ns (IEEE 802.15.4a standard, Annex A, 2007).
- 윈도우를 ±T_w로 설정하면 first cluster 에너지의 ~95%를 포착 (Gaussian cluster 가정 시 2σ 범위).
- T_w가 너무 크면 multipath 에너지가 E_fp에 포함되어 a_FP 분별력 저하.
- T_w가 너무 작으면 first-path 검출 오차에 민감해짐.

### 5.3 Edge Case: E_total = 0

```
if E_total == 0
    a_FP = NaN        % 채널 응답 없음 → valid_flag = false
end
```

---

## 6. 출력 데이터 형식

```matlab
% 출력 테이블 구조: [N_pos × 4]
feature_table = table(r_CP, a_FP, labels, pos_id, ...
    'VariableNames', {'r_CP', 'a_FP', 'label', 'pos_id'});

% metadata 구조체
metadata = table(pos_id, fp_idx_RHCP, fp_idx_LHCP, valid_flag, ...
    'VariableNames', {'pos_id', 'fp_idx_RHCP', 'fp_idx_LHCP', 'valid_flag'});
```

| 열 | 타입 | 범위 | 설명 |
|----|------|------|------|
| `r_CP` | double | [0, ∞) | RHCP/LHCP first-path 전력비 (linear) |
| `a_FP` | double | [0, 1] | First-path 에너지 집중도 |
| `label` | logical | {0, 1} | 0=NLoS, 1=LoS |
| `pos_id` | uint32 | — | 원본 위치 인덱스 |
| `valid_flag` | logical | {0, 1} | Edge case 제외 여부 |

---

## 7. 전체 Pseudocode

```
function [r_CP, a_FP, labels, metadata] = extract_features(sim_data, params)

    % 파라미터 기본값 설정
    if ~isfield(params, 'threshold_ratio'), params.threshold_ratio = 0.20; end
    if ~isfield(params, 'T_w'),             params.T_w = 2.0;              end

    N_pos = size(sim_data.CIR_RHCP, 1)
    r_CP  = zeros(N_pos, 1)
    a_FP  = zeros(N_pos, 1)
    fp_idx_RHCP  = zeros(N_pos, 1, 'uint32')
    fp_idx_LHCP  = zeros(N_pos, 1, 'uint32')
    valid_flag   = true(N_pos, 1)

    for i = 1 : N_pos
        cir_r = sim_data.CIR_RHCP(i, :)   % [1 × N_tap] complex
        cir_l = sim_data.CIR_LHCP(i, :)

        % --- First-path 검출 ---
        fp_r = detect_first_path(abs(cir_r), params.threshold_ratio)
        fp_l = detect_first_path(abs(cir_l), params.threshold_ratio)

        if isnan(fp_r) || isnan(fp_l)
            valid_flag(i) = false
            r_CP(i) = NaN; a_FP(i) = NaN
            continue
        end

        fp_idx_RHCP(i) = fp_r
        fp_idx_LHCP(i) = fp_l

        % --- r_CP 계산 ---
        P_r = abs(cir_r(fp_r))^2
        P_l = abs(cir_l(fp_l))^2

        if P_l == 0
            if P_r == 0
                valid_flag(i) = false; r_CP(i) = NaN
            else
                r_CP(i) = Inf        % LoS 극단; 정규화 후 클리핑 필요
            end
        else
            r_CP(i) = P_r / P_l
        end

        % --- a_FP 계산 ---
        t      = sim_data.t_axis
        t_fp   = t(fp_r)
        win    = (t >= t_fp - params.T_w) & (t <= t_fp + params.T_w)
        E_fp   = sum(abs(cir_r(win)).^2)
        E_tot  = sum(abs(cir_r).^2)

        if E_tot == 0
            valid_flag(i) = false; a_FP(i) = NaN
        else
            a_FP(i) = E_fp / E_tot
        end
    end

    labels   = logical(sim_data.labels)
    pos_id   = sim_data.pos_id
    metadata = table(pos_id, fp_idx_RHCP, fp_idx_LHCP, valid_flag, ...)

end
```

---

## 8. 검증 체크리스트

- [ ] r_CP 분포 히스토그램: LoS 그룹과 NLoS 그룹이 시각적으로 분리되는가?
- [ ] a_FP 분포: LoS에서 a_FP > 0.5 비율이 NLoS보다 유의미하게 높은가?
- [ ] NaN/Inf 비율: valid_flag = false 샘플이 전체의 1% 미만인가?
- [ ] T_w sensitivity: T_w = 1.0, 2.0, 3.0 ns 변화에 따른 AUC 변화 < 0.02인가?

---

*최종 수정: 2026-04-01 | 작성자: Claude Code (Architecture Agent)*
