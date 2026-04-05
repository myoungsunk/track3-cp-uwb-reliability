# 구현 명세: detect_first_path / extract_rcp / extract_afp / extract_features_batch

> 모듈: M03, M04, M05, M06 | 버전: 2.0
> v1 대비 변경점:
> - M03: search_window 옵션 추가, fp_info 구조체 반환
> - M04: edge case 정책 확정 (both_below_floor = NaN + TODO)
> - M05: afp_cir_source 선택 옵션 ('RHCP'/'LHCP'/'combined'/'power_sum')
> - M06: sim_data 두 번째 출력으로 반환, valid_flag/fp_idx를 feature_table에 직접 포함
>         r_CP Inf → r_CP_clip 클리핑, label fallback 경고

---

## 1. M03: detect_first_path

### 1.1 시그니처

```matlab
function [fp_idx, fp_info] = detect_first_path(cir_abs, params)
% DETECT_FIRST_PATH  Leading-edge first-path 검출
%
% 입력:
%   cir_abs  — [N_tap × 1] double, |CIR| (절대값)
%   params   — struct:
%     .fp_threshold_ratio    = 0.20       (기본값)
%     .fp_search_window_ns   = []         (빈 배열 = 전체 탐색)
%                             또는 [t_start_ns, t_end_ns]
%     .t_axis                = []         (search_window_ns 사용 시 필수)
%
% 출력:
%   fp_idx   — scalar uint32, first-path 인덱스 (탐색 실패 시 NaN)
%   fp_info  — struct:
%     .peak_idx       peak 위치 (인덱스)
%     .peak_val       peak 절대값
%     .threshold      사용된 임계값 (= ratio × peak_val)
%     .search_range   실제 탐색 인덱스 범위 [start, end]
%     .found          logical, 검출 성공 여부
```

### 1.2 search_window 옵션 (v2 추가)

```
% 기본 (전체 탐색):
%   search_range = [1, N_tap]
%
% ranging 용도 (예: 0~100 ns 범위만):
%   params.fp_search_window_ns = [0, 100]
%   → t_axis에서 해당 범위의 인덱스를 추출
%   → peak 및 first-path를 그 범위 내에서만 탐색
%
% 주의: first-path 인덱스(fp_idx)는 전체 CIR 기준 절대 인덱스로 반환
```

### 1.3 Pseudocode

```
function [fp_idx, fp_info] = detect_first_path(cir_abs, params)

    N_tap = length(cir_abs)

    % search window 결정
    if isempty(params.fp_search_window_ns)
        s_start = 1; s_end = N_tap
    else
        t = params.t_axis
        s_start = find(t >= params.fp_search_window_ns(1), 1, 'first')
        s_end   = find(t <= params.fp_search_window_ns(2), 1, 'last')
        if isempty(s_start), s_start = 1; end
        if isempty(s_end),   s_end = N_tap; end
    end

    cir_search = cir_abs(s_start : s_end)
    peak_val   = max(cir_search)
    [~, peak_rel] = max(cir_search)
    peak_idx   = peak_rel + s_start - 1     % 절대 인덱스

    threshold  = params.fp_threshold_ratio * peak_val

    candidates = find(cir_search > threshold)

    if isempty(candidates)
        fp_idx = NaN
        fp_info.found = false
    else
        fp_rel = candidates(1)              % 탐색 범위 내 상대 인덱스
        fp_idx = uint32(fp_rel + s_start - 1)  % 절대 인덱스
        fp_info.found = true
    end

    fp_info.peak_idx     = uint32(peak_idx)
    fp_info.peak_val     = peak_val
    fp_info.threshold    = threshold
    fp_info.search_range = [s_start, s_end]
end
```

---

## 2. M04: extract_rcp

### 2.1 시그니처

```matlab
function [r_CP, rcp_info] = extract_rcp(cir_rx1, cir_rx2, params)
% EXTRACT_RCP  r_CP = P_rx1_fp / P_rx2_fp (linear scale)
%
% 입력:
%   cir_rx1, cir_rx2  — [N_tap × 1] complex, CIR (CP 파일: rx1=RHCP, rx2=LHCP)
%   params            — struct:
%     .fp_threshold_ratio  = 0.20
%     .fp_search_window_ns = []
%     .t_axis              = []
%     .r_CP_clip           = 10000  (= 40 dB, Inf 방지)
%     .min_power_dbm       = -120
%
% 출력:
%   r_CP     — scalar double, [0, r_CP_clip]
%   rcp_info — struct:
%     .P_rx1        rx1 first-path 전력 [linear]
%     .P_rx2        rx2 first-path 전력 [linear]
%     .fp_idx_rx1   uint32
%     .fp_idx_rx2   uint32
%     .flag         'ok' | 'rx2_zero' | 'rx1_zero' | 'both_below_floor'
```

### 2.2 Edge Case 처리 정책 (v2 확정)

| 조건 | r_CP 값 | flag | 설명 |
|------|---------|------|------|
| 정상 | `P_rx1/P_rx2` | `'ok'` | — |
| `P_rx2 == 0`, `P_rx1 > 0` | `r_CP_clip` | `'rx2_zero'` | LHCP 완전 소멸, LoS 극단 케이스 |
| `P_rx1 == 0`, `P_rx2 > 0` | `0` | `'rx1_zero'` | RHCP 소멸, NLoS 극단 케이스 |
| `P_rx1 == 0` && `P_rx2 == 0` | `NaN` | `'both_below_floor'` | 두 채널 모두 noise floor 이하 → valid_flag = false |
| `r_CP > r_CP_clip` | `r_CP_clip` | `'clipped'` | Inf 방지 클리핑 |

> **TODO (both_below_floor)**: 실제 데이터에서 이 케이스가 발생하는지 확인.
> 발생 빈도가 높으면 noise floor 추정 방법 재검토 필요.
> 현재 방침: NaN으로 표시 + valid_flag=false로 학습/평가에서 제외.

### 2.3 Pseudocode

```
function [r_CP, rcp_info] = extract_rcp(cir_rx1, cir_rx2, params)

    % first-path 검출
    [fp1, ~] = detect_first_path(abs(cir_rx1), params)
    [fp2, ~] = detect_first_path(abs(cir_rx2), params)

    if isnan(fp1) || isnan(fp2)
        r_CP = NaN
        rcp_info.flag = 'both_below_floor'   % TODO: 확인 필요
        rcp_info.P_rx1 = NaN; rcp_info.P_rx2 = NaN
        rcp_info.fp_idx_rx1 = uint32(0); rcp_info.fp_idx_rx2 = uint32(0)
        return
    end

    P_rx1 = abs(cir_rx1(fp1))^2
    P_rx2 = abs(cir_rx2(fp2))^2

    if P_rx2 == 0 && P_rx1 > 0
        r_CP = params.r_CP_clip
        rcp_info.flag = 'rx2_zero'
    elseif P_rx1 == 0 && P_rx2 > 0
        r_CP = 0
        rcp_info.flag = 'rx1_zero'
    elseif P_rx1 == 0 && P_rx2 == 0
        r_CP = NaN
        rcp_info.flag = 'both_below_floor'
    else
        r_CP = P_rx1 / P_rx2
        if r_CP > params.r_CP_clip
            r_CP = params.r_CP_clip
            rcp_info.flag = 'clipped'
        else
            rcp_info.flag = 'ok'
        end
    end

    rcp_info.P_rx1      = P_rx1
    rcp_info.P_rx2      = P_rx2
    rcp_info.fp_idx_rx1 = uint32(fp1)
    rcp_info.fp_idx_rx2 = uint32(fp2)
end
```

---

## 3. M05: extract_afp

### 3.1 시그니처

```matlab
function [a_FP, afp_info] = extract_afp(cir_rx1, cir_rx2, t_axis, params)
% EXTRACT_AFP  a_FP = E_fp / E_total
%
% 입력:
%   cir_rx1, cir_rx2 — [N_tap × 1] complex
%   t_axis           — [N_tap × 1] double [ns]
%   params           — struct:
%     .T_w              = 2.0       [ns] first-path 에너지 윈도우 반폭
%     .fp_threshold_ratio = 0.20
%     .fp_search_window_ns = []
%     .afp_cir_source   = 'RHCP'   (초기값; 'RHCP'|'LHCP'|'combined'|'power_sum')
%
% 출력:
%   a_FP     — scalar double [0, 1]
%   afp_info — struct:
%     .cir_used     사용된 CIR 소스 식별자
%     .E_fp         first-path 윈도우 에너지
%     .E_total      전체 CIR 에너지
%     .fp_idx       first-path 인덱스 (선택된 CIR 기준)
%     .win_range    [t_start, t_end] ns
```

### 3.2 CIR 선택 옵션 (v2 추가)

| `afp_cir_source` | 사용 CIR | 설명 |
|-----------------|---------|------|
| `'RHCP'` | `cir_rx1` | **기본값**. LoS에서 rx1(RHCP) dominant → a_FP 분리도 높을 것으로 예상 |
| `'LHCP'` | `cir_rx2` | ablation용 |
| `'combined'` | `(cir_rx1 + cir_rx2) / 2` | 복소 평균 |
| `'power_sum'` | `sqrt(\|cir_rx1\|² + \|cir_rx2\|²)` | 편파 다이버시티 에너지 합산 |

> **LP 파일 입력 시**: `afp_cir_source='RHCP'`로 설정해도 실제로는 LP1 CIR을 사용.
> M05는 파일 타입을 인식하지 않음. 호출자(M06)가 적절히 파라미터 설정.

### 3.3 Pseudocode

```
function [a_FP, afp_info] = extract_afp(cir_rx1, cir_rx2, t_axis, params)

    % CIR 선택
    switch params.afp_cir_source
        case 'RHCP',      cir = cir_rx1
        case 'LHCP',      cir = cir_rx2
        case 'combined',  cir = (cir_rx1 + cir_rx2) / 2
        case 'power_sum', cir = sqrt(abs(cir_rx1).^2 + abs(cir_rx2).^2 + 0j)
        otherwise,        error('Unknown afp_cir_source: %s', params.afp_cir_source)
    end

    % first-path 검출 (선택된 CIR 기준)
    [fp_idx, ~] = detect_first_path(abs(cir), params)

    if isnan(fp_idx)
        a_FP = NaN
        afp_info.E_fp = NaN; afp_info.E_total = NaN
        afp_info.fp_idx = NaN; afp_info.win_range = [NaN, NaN]
        afp_info.cir_used = params.afp_cir_source
        return
    end

    t_fp = t_axis(fp_idx)
    win  = (t_axis >= t_fp - params.T_w) & (t_axis <= t_fp + params.T_w)

    E_fp    = sum(abs(cir(win)).^2)
    E_total = sum(abs(cir).^2)

    if E_total == 0
        a_FP = NaN
    else
        a_FP = E_fp / E_total
    end

    afp_info.cir_used  = params.afp_cir_source
    afp_info.E_fp      = E_fp
    afp_info.E_total   = E_total
    afp_info.fp_idx    = fp_idx
    afp_info.win_range = [t_fp - params.T_w, t_fp + params.T_w]
end
```

---

## 4. M06: extract_features_batch

### 4.1 시그니처

```matlab
function [feature_table, sim_data] = extract_features_batch(sim_data, params)
% EXTRACT_FEATURES_BATCH  전 위치 feature 일괄 추출
%
% 입력:
%   sim_data — M02 출력 (또는 동일 구조체)
%   params   — (§4.2 참조)
%
% 출력:
%   feature_table — MATLAB table [N_pos × 9 columns]
%   sim_data      — 입력과 동일 (localization 재사용 위해 반환)
```

### 4.2 feature_table 컬럼 (v2: valid_flag, fp_idx 포함)

| 열 | 타입 | 범위 | 설명 |
|----|------|------|------|
| `pos_id` | uint32 | — | 위치 인덱스 |
| `r_CP` | double | [0, r_CP_clip] | RHCP/LHCP first-path 전력비 (linear) |
| `a_FP` | double | [0, 1] | First-path 에너지 집중도 |
| `label` | logical | {0,1} | true=LoS, false=NLoS |
| `valid_flag` | logical | {0,1} | false = NaN/Inf edge case (학습 제외) |
| `fp_idx_rx1` | uint32 | — | rx1 first-path 인덱스 |
| `fp_idx_rx2` | uint32 | — | rx2 first-path 인덱스 |
| `RSS_rx1` | double | [dBm] | rx1 전체 에너지 (상대값) |
| `RSS_rx2` | double | [dBm] | rx2 전체 에너지 (상대값) |

> **LP 파일 입력 시**: `r_CP`는 LP1/LP2 전력비 (r_LP). 열 이름은 동일하게 유지하고,
> `sim_data.pol_type = 'LP'`로 구분.

### 4.3 Pseudocode

```
function [feature_table, sim_data] = extract_features_batch(sim_data, params)

    N_pos = size(sim_data.CIR_rx1, 1)
    r_CP_arr     = zeros(N_pos, 1)
    a_FP_arr     = zeros(N_pos, 1)
    valid_flag   = true(N_pos, 1)
    fp_idx_rx1   = zeros(N_pos, 1, 'uint32')
    fp_idx_rx2   = zeros(N_pos, 1, 'uint32')

    for i = 1 : N_pos
        cir1 = sim_data.CIR_rx1(i, :)'    % [N_fft × 1]
        cir2 = sim_data.CIR_rx2(i, :)'

        % r_CP
        [r_CP_i, rcp_info] = extract_rcp(cir1, cir2, params)
        r_CP_arr(i) = r_CP_i
        fp_idx_rx1(i) = rcp_info.fp_idx_rx1
        fp_idx_rx2(i) = rcp_info.fp_idx_rx2

        % a_FP
        [a_FP_i, ~] = extract_afp(cir1, cir2, sim_data.t_axis', params)
        a_FP_arr(i) = a_FP_i

        % valid_flag
        if isnan(r_CP_i) || isnan(a_FP_i)
            valid_flag(i) = false
        end
    end

    % label fallback
    if ~isfield(sim_data, 'labels') || all(isnan(double(sim_data.labels)))
        labels = true(N_pos, 1)
        warning('[extract_features_batch] labels 없음 → 전체 LoS로 가정')
    else
        labels = logical(sim_data.labels)
    end

    % r_CP Inf 클리핑 (safety)
    r_CP_arr(r_CP_arr > params.r_CP_clip) = params.r_CP_clip

    % 출력 테이블 조립
    feature_table = table(sim_data.pos_id, r_CP_arr, a_FP_arr, labels, ...
                          valid_flag, fp_idx_rx1, fp_idx_rx2, ...
                          sim_data.RSS_rx1, sim_data.RSS_rx2, ...
        'VariableNames', {'pos_id','r_CP','a_FP','label','valid_flag', ...
                          'fp_idx_rx1','fp_idx_rx2','RSS_rx1','RSS_rx2'})

    fprintf('[extract_features_batch] 완료: N_pos=%d, valid=%d, NaN=%d\n', ...
            N_pos, sum(valid_flag), sum(~valid_flag))
end
```

---

## 5. CP vs LP 처리 방침

| 파일 타입 | `CIR_rx1` | `CIR_rx2` | `r_CP` 의미 | `a_FP` 계산 |
|---------|-----------|-----------|------------|------------|
| `cp_case*.csv` | RHCP | LHCP | **r_CP** (핵심 지표) | RHCP 기반 (기본) |
| `lp_case*.csv` | LP1 | LP2 | r_LP (비교 베이스라인) | LP1 기반 |

- 논문 Table에서 CP의 r_CP 분리도와 LP의 r_LP 분리도를 비교하면 CP의 우위를 입증 가능.
- M06는 `sim_data.pol_type`을 변경하지 않고 feature_table을 동일 구조로 출력.

---

## 6. 검증 체크리스트

- [ ] `valid_flag = false` 비율이 전체의 1% 미만인가? (초과 시 threshold_ratio 재검토)
- [ ] CP 파일의 r_CP 분포: LoS에서 r_CP > 1이 지배적인가?
- [ ] a_FP 분포: LoS에서 a_FP > 0.5 비율이 높은가?
- [ ] `both_below_floor` flag 발생 빈도 확인 (`sum(strcmp({rcp_info.flag},'both_below_floor'))`)
- [ ] LP 파일과 CP 파일의 r_CP 분포 비교: CP가 더 넓은 범위를 보이는가?

---

*최종 수정: 2026-04-05 | 작성자: Claude Code (Architecture Agent) v2*
