# 구현 명세: extract_features.m

> 모듈: M02 | 의존: M01 (data_loader) | 버전: 1.2
> 변경 이력:
> v1.1 — FAIL-1 .mat 구조 확인 절차 보강, FAIL-2 a_FP CIR 선택 근거 명확화,
>         WARNING-1 r_CP 단일샘플 vs 윈도우 ablation 추가, WARNING-2 T_w sensitivity 기준 완화
> v1.2 — FAIL-1 재수정: 실제 데이터 포맷 반영 (주파수 도메인 S-파라미터 테이블, IFFT 변환, d_sym 레이블)

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

## 2. SIM1/SIM2 실제 데이터 포맷 (v1.2 확정)

### 2.1 원본 데이터 구조 — 주파수 도메인 S-파라미터 테이블

SIM1/SIM2는 **시간 도메인 CIR이 아닌, 주파수 도메인 S-파라미터 테이블**이다.
각 행은 하나의 `(d_sym, x_coord, y_coord, Freq)` 조합을 나타낸다.

| 열 이름 | 단위 | 타입 | 설명 |
|---------|------|------|------|
| `d_sym` | mm | double | **시나리오 식별자** (거리/장애물 종류 등 시나리오 구분용) |
| `x_coord` | mm | double | Rx 위치 x 좌표 |
| `y_coord` | mm | double | Rx 위치 y 좌표 |
| `Freq` | GHz | double | 측정 주파수 (UWB Ch.5, ~6–9 GHz) |
| `mag(S(rx1_p1,tx_p1))` | — | double | rx1 포트(RHCP) S21 진폭 |
| `ang_deg(S(rx1_p1,tx_p1))` | deg | double | rx1 포트(RHCP) S21 위상 |
| `mag(S(rx2_p1,tx_p1))` | — | double | rx2 포트(LHCP) S21 진폭 |
| `ang_deg(S(rx2_p1,tx_p1))` | deg | double | rx2 포트(LHCP) S21 위상 |

**예시 행** (SIM1.mat에서 발췌):
```
d_sym=1000, x=-400mm, y=200mm, Freq=6.24GHz,
  mag_rx1=0.02106, ang_rx1=128.54°,
  mag_rx2=0.00184, ang_rx2=-4.80°
```

> **포트 매핑 PLACEHOLDER**: rx1=RHCP, rx2=LHCP로 가정. 안테나 설계 문서에서 포트-편파 대응 확인 필요.

### 2.2 위치 인덱스 정의

하나의 **측정 위치(position)** = `(d_sym, x_coord, y_coord)` 삼중쌍.
동일 위치에서 여러 Freq 행이 존재 → UWB Ch.5 주파수 스윕.

```
N_pos  = 고유한 (d_sym, x_coord, y_coord) 조합 수
N_freq = 위치당 주파수 포인트 수 (모든 위치에서 동일하다고 가정)
원본 테이블 행 수 = N_pos × N_freq
```

### 2.3 LoS/NLoS 레이블 — d_sym 기반 유추

레이블이 데이터 파일에 직접 포함되어 **있지 않다**.
`d_sym` 값이 시나리오 종류를 지칭하므로, 아래 매핑 테이블을 `data_loader.m`에 정의한다.

```matlab
% PLACEHOLDER: 실제 d_sym 값과 LoS/NLoS 대응 연구자 확인 후 입력
DSYM_LABEL_MAP = containers.Map(...
    {1000,  2000,  3000, ...},  ...  % d_sym 값 (예시)
    {1,     1,     0,    ...}   ...  % 1=LoS, 0=NLoS
);
```

> d_sym의 실제 값 목록은 `unique(T.d_sym)` 으로 확인. 시나리오 정의 문서와 대조하여 매핑 완성.

### 2.4 data_loader.m 추가 책임: H(f) → h(t) 변환 (IFFT)

원본이 주파수 도메인이므로 `data_loader.m`에서 **CIR 합성** 단계를 담당한다.
`extract_features.m`은 완성된 시간 도메인 CIR을 입력으로 받는 인터페이스를 유지한다.

```
[data_loader.m 내부 처리 흐름]

① 원본 테이블 로드
   T = readtable('SIM1.csv')  또는  load('SIM1.mat')

② 고유 위치 추출
   positions = unique(T(:, {'d_sym','x_coord','y_coord'}), 'rows')
   N_pos = height(positions)

③ 위치별 H(f) 구성 및 IFFT
   for i = 1 : N_pos
       mask = (T.d_sym == positions.d_sym(i)) & ...
              (T.x_coord == positions.x_coord(i)) & ...
              (T.y_coord == positions.y_coord(i))
       f_vec = T.Freq(mask)               % [N_freq × 1] GHz

       % 복소 전달함수 (S21)
       H_rx1 = T.mag_rx1(mask) .* exp(1j * T.ang_rx1(mask) * pi/180)  % RHCP
       H_rx2 = T.mag_rx2(mask) .* exp(1j * T.ang_rx2(mask) * pi/180)  % LHCP

       % 주파수 간격 확인 (균일 샘플링 가정)
       df = mean(diff(f_vec))   % GHz

       % Zero-padding: N_fft = 2^nextpow2(N_freq) 또는 더 큰 2의 거듭제곱
       N_fft = 2^(nextpow2(N_freq) + 2)   % 시간 해상도 향상

       % IFFT → CIR  (ifft는 H(f)를 [0, f_max] 정의된 단측 스펙트럼으로 가정)
       % 양측 스펙트럼 없이 단측만 있으므로 실수 CIR 보장 불가 → 복소 CIR 사용
       CIR_RHCP(i, :) = ifft(H_rx1, N_fft)
       CIR_LHCP(i, :) = ifft(H_rx2, N_fft)

       % 시간축 계산
       dt = 1 / (N_fft * df * 1e9)        % seconds, df는 GHz → Hz 변환
       t_axis = (0 : N_fft-1) * dt * 1e9  % ns
   end

④ 레이블 할당 (d_sym 매핑)
   labels(i) = DSYM_LABEL_MAP(positions.d_sym(i))

⑤ 표준 sim_data 구조체 출력
   sim_data.CIR_RHCP = CIR_RHCP    % [N_pos × N_fft] complex
   sim_data.CIR_LHCP = CIR_LHCP    % [N_pos × N_fft] complex
   sim_data.labels   = labels       % [N_pos × 1] uint8
   sim_data.pos_id   = (1:N_pos)'   % [N_pos × 1] uint32
   sim_data.t_axis   = t_axis       % [1 × N_fft] double (ns)
   sim_data.positions = positions   % [N_pos × 3] table (d_sym, x, y)
```

> **IFFT 주의사항**:
> - UWB Ch.5 대역 (~6–9 GHz)만 스윕된 경우, CIR의 시간 영점(t=0)은 **전파 지연이 아닌 주파수 윈도우의 역변환 기준점**임. First-path 검출 알고리즘(§3)은 절대 지연이 아닌 **상대적 earliest peak** 위치만 필요하므로 문제 없음.
> - 밴드패스 신호를 IFFT하면 복소 해석신호(analytic signal)가 얻어짐 → `abs(CIR)`로 포락선 사용 (§3 알고리즘과 일치).
> - 주파수 포인트가 균일하지 않으면 NUFFT(Non-Uniform FFT) 또는 보간 후 IFFT 필요. `mean(diff(f_vec))` ≈ `min(diff(f_vec))` 이면 균일로 판단.

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

### 4.1 수식 — 단일 샘플 방식 (기본값)

```
P_RHCP_fp = |CIR_RHCP(fp_idx_RHCP)|^2    % 단일 샘플 전력
P_LHCP_fp = |CIR_LHCP(fp_idx_LHCP)|^2
r_CP = P_RHCP_fp / P_LHCP_fp             % linear scale
```

### 4.2 Linear vs dB Scale 선택 근거

**Linear scale 채택 이유:**
- Logistic Regression의 sigmoid 함수는 선형 결합 `β₀ + β₁·x₁ + β₂·x₂`에 적용되므로, x₁ = r_CP가 대칭적 분포를 갖는 것이 수렴 안정성에 유리.
- LoS 조건에서 r_CP는 10~1000+ 범위를 가질 수 있으므로, dB scale(`10·log10(r_CP)`)로 log-압축한 뒤 z-score를 적용하는 것도 가능. 단, **log 변환은 train_logistic 단계가 아닌 이 함수에서 수행**하면 파이프라인 일관성이 깨짐.
- **채택**: linear 추출 후 train_logistic 단계에서 z-score 정규화 (현행 구조 유지).
- **ablation**: dB scale 모델과 AUC 비교 (보조 자료).

### 4.2a 단일 샘플 vs 윈도우 에너지 비교 (WARNING-1 대응)

**현행 r_CP**: 단일 샘플 `|CIR(fp_idx)|²`
- 장점: 연산 O(1), FLOPs 카운트 일관성 (논문의 경량성 주장에 유리).
- 단점: 단일 샘플이 noise spike일 경우 분산 증가.

**대안 r_CP (윈도우 에너지)**:
```
E_RHCP_fp = sum(|CIR_RHCP(fp_idx ± W)|^2)
E_LHCP_fp = sum(|CIR_LHCP(fp_idx ± W)|^2)
r_CP_win  = E_RHCP_fp / E_LHCP_fp
```
- 장점: noise에 robust.
- 단점: 윈도우 내 인접 multipath 포함 가능 → LoS/NLoS 경계 흐려짐.

**조치**: 초기 구현은 단일 샘플 방식. ablation에서 W = T_w/2 윈도우 에너지 방식과 AUC 비교.
두 방식의 AUC 차이 < 0.02이면 단일 샘플 방식 채택 (복잡도 유지).

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
% First-path 윈도우 인덱스 결정 (fp_idx = fp_idx_RHCP 사용, §5.2b 참조)
win_idx = find(t_axis >= t_axis(fp_idx) - T_w  &  t_axis <= t_axis(fp_idx) + T_w)

% CIR: RHCP 단독 사용 (초기 구현 기본값, 근거는 §5.2b)
E_fp    = sum(|CIR_RHCP(win_idx)|^2)
E_total = sum(|CIR_RHCP|^2)
a_FP    = E_fp / E_total
```

### 5.2b a_FP 계산 CIR 선택 근거 (FAIL-2 대응)

**초기 구현: RHCP 단독 채택**

물리적 근거:
- CP-UWB에서 LoS 직접 경로는 RHCP로 송신된 신호가 반사 없이 도달 → Rx RHCP 채널에서 first-path 전력 dominant.
- LHCP 채널에는 홀수 반사 에너지가 섞여 있어, first-path 주변 ±T_w 윈도우 내에도 multipath 에너지가 포함될 가능성이 높음.
- 따라서 **RHCP 채널의 a_FP가 LoS/NLoS 분리도(AUC 기여도)가 더 높을 것으로 예상**.

> 단, 이것은 사전 가설이며 반드시 ablation으로 검증해야 함.

**Ablation 계획** (eval_model 이후 추가 실험):

| 구성 | 설명 |
|------|------|
| `a_FP_R` | RHCP 단독 (기본값) |
| `a_FP_L` | LHCP 단독 |
| `a_FP_avg` | (RHCP + LHCP) / 2 에너지 평균 |

세 구성의 AUC를 비교하여 최종 선택을 확정하고 이 spec을 v1.2로 갱신.

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

### data_loader.m 단계 (extract_features 호출 전)
- [ ] `unique(T.d_sym)` 결과를 확인하고 DSYM_LABEL_MAP 완성했는가?
- [ ] IFFT 후 `t_axis` 최댓값이 합리적인가? (UWB Ch.5 스윕 폭 ~3 GHz → 시간 해상도 ~0.33 ns, N_fft=256이면 최대 ~85 ns)
- [ ] `mean(diff(f_vec))` ≈ `min(diff(f_vec))` 인가? (주파수 균일 샘플링 확인)
- [ ] 위치별 `N_freq`가 모두 동일한가? `groupcounts(T, {'d_sym','x_coord','y_coord'})` 로 확인

### extract_features.m 단계
- [ ] r_CP 분포 히스토그램: LoS 그룹과 NLoS 그룹이 시각적으로 분리되는가?
- [ ] a_FP 분포: LoS에서 a_FP > 0.5 비율이 NLoS보다 유의미하게 높은가?
- [ ] NaN/Inf 비율: valid_flag = false 샘플이 전체의 1% 미만인가?
- [ ] T_w sensitivity: T_w = 1.0, 2.0, 3.0 ns 변화에 따른 AUC 변화 **< 0.05** (WARNING-2: NLoS에서 first cluster 확산 고려하여 허용 오차 완화)
  - AUC 변화 ≥ 0.05이면 CV로 최적 T_w 선택 (`params.T_w = optimizeT_w(folds)` 추가)
- [ ] Ablation 완료 후 a_FP CIR 선택(RHCP/LHCP/avg) 최종 확정 및 spec v1.3 갱신

---

*최종 수정: 2026-04-01 | 작성자: Claude Code (Architecture Agent)*
