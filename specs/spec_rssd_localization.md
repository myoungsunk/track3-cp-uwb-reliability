# 구현 명세: build_rssd_lut / estimate_doa_rssd / estimate_position

> 모듈: M07, M08, M09 | 버전: 1.0
> 선행 논문: "RSSD 기반 O(1) DoA 추정", IEEE IoT-J (2025)

---

## 0. 전제 조건 및 TODO

> **현재 데이터 구조 확인 필요**:
> 보유 데이터(`cp_caseA/B/C.csv`)는 모두 (x_coord, y_coord) 기반 'test' 타입이며,
> RSSD LUT 생성에 필요한 입사각(inc_ang) 기반 'guide' 데이터가 현재 확인되지 않음.
>
> **TODO 목록**:
> - [ ] guide 데이터(inc_ang 축) 존재 여부 확인. 없으면 simulated LUT 또는
>       test 데이터 기반 자가 보정 방식 검토.
> - [ ] 좌표계 정의 확인: 앵커(Tx) 위치, 각도 기준(north=0? 동=0?), 좌/우손 방향
> - [ ] ToA 기반 ranging: single-sided vs round-trip 정의 확인
>
> 이 spec은 guide 데이터가 존재한다는 가정 하에 작성됨.
> guide 데이터 구조가 확인되면 M07 파라미터를 업데이트.

---

## 1. M07: build_rssd_lut

### 1.1 시그니처

```matlab
function lut = build_rssd_lut(sim_data_guide, params)
% BUILD_RSSD_LUT  guide(inc_ang) 데이터로 RSSD vs 입사각 LUT 생성
%
% 입력:
%   sim_data_guide — sim_data 구조체 (data_role = 'guide')
%     .RSS_rx1   [N_ang × 1]  dBm, rx1 전체 에너지
%     .RSS_rx2   [N_ang × 1]  dBm, rx2 전체 에너지
%     .inc_ang   [N_ang × 1]  deg, 입사각 (0~360 또는 -180~180)
%     (NOTE: inc_ang 필드는 현재 데이터에 없음 → TODO)
%   params — struct:
%     .rssd_interp_method  = 'pchip'    ('pchip' | 'linear' | 'spline')
%     .lut_ang_step        = 0.1        [deg] LUT 보간 해상도
%     .rssd_antenna_pair   = [1, 2]     사용할 안테나 인덱스 쌍
%
% 출력:
%   lut — struct:
%     .ang_axis     [M × 1]  deg, 보간된 각도 축
%     .rssd_curve   [M × 1]  dB, RSSD = RSS_ant1 - RSS_ant2
%     .rssd_raw     [N_ang × 1]  dB, 원본 RSSD
%     .ang_raw      [N_ang × 1]  deg, 원본 각도
%     .interp_obj   griddedInterpolant 객체
%     .monotonic_range  [2 × 1]  deg, RSSD 단조 구간 [ang_min, ang_max]
%     .params       사용된 params 기록
```

### 1.2 RSSD 정의

```
RSSD(θ) = RSS_rx1(θ) - RSS_rx2(θ)   [dB]

- CP 안테나: rx1=RHCP, rx2=LHCP
- 이상적 CP 안테나: LoS 직접 경로에서 RHCP 우세
  → 입사각에 따라 RSS_rx1과 RSS_rx2의 비율이 달라짐
- RSSD-θ 곡선이 단조 구간에서 O(1) 역참조 가능 (IoT-J 2025)
```

### 1.3 Pseudocode

```
function lut = build_rssd_lut(sim_data_guide, params)

    % 입력 검증
    if ~isfield(sim_data_guide, 'inc_ang')
        error('[build_rssd_lut] sim_data_guide에 inc_ang 필드 없음. guide 데이터 필요.')
    end

    ang_raw  = sim_data_guide.inc_ang          % [N_ang × 1] deg
    RSS1_raw = sim_data_guide.RSS_rx1          % [N_ang × 1] dBm
    RSS2_raw = sim_data_guide.RSS_rx2          % [N_ang × 1] dBm
    rssd_raw = RSS1_raw - RSS2_raw             % RSSD [dB]

    % 각도 정렬 (오름차순)
    [ang_sorted, idx] = sort(ang_raw)
    rssd_sorted = rssd_raw(idx)

    % 보간: pchip (단조 구간 보존)
    ang_axis = (min(ang_sorted) : params.lut_ang_step : max(ang_sorted))'
    interp_obj  = griddedInterpolant(ang_sorted, rssd_sorted, params.rssd_interp_method)
    rssd_curve  = interp_obj(ang_axis)

    % 단조성 검증: RSSD 기울기 부호 변화 찾기
    slope = diff(rssd_curve) ./ diff(ang_axis)
    sign_changes = find(diff(sign(slope)) ~= 0)
    if isempty(sign_changes)
        monotonic_range = [ang_axis(1), ang_axis(end)]
    else
        % 가장 긴 단조 구간 선택
        break_pts = [1; sign_changes+1; length(ang_axis)]
        seg_lens  = diff(break_pts)
        [~, max_seg] = max(seg_lens)
        monotonic_range = [ang_axis(break_pts(max_seg)), ang_axis(break_pts(max_seg+1))]
        warning('[build_rssd_lut] 비단조 구간 존재. 단조 구간: [%.1f, %.1f] deg', ...
                monotonic_range(1), monotonic_range(2))
    end

    lut.ang_axis         = ang_axis
    lut.rssd_curve       = rssd_curve
    lut.rssd_raw         = rssd_sorted
    lut.ang_raw          = ang_sorted
    lut.interp_obj       = interp_obj
    lut.monotonic_range  = monotonic_range
    lut.params           = params
end
```

---

## 2. M08: estimate_doa_rssd

### 2.1 시그니처

```matlab
function [doa_est, doa_info] = estimate_doa_rssd(rssd_measured, lut, params)
% ESTIMATE_DOA_RSSD  측정 RSSD → DoA 추정 (LUT 역참조, O(1))
%
% 입력:
%   rssd_measured — scalar 또는 [N × 1] dB
%   lut           — M07 출력
%   params        — (선택) .monotonic_only = true (단조 구간만 탐색)
%
% 출력:
%   doa_est  — [N × 1] deg
%   doa_info — struct:
%     .ambiguity_flag  [N × 1] logical (비단조 구간 모호성)
%     .residual        [N × 1] dB (RSSD 잔차)
%     .n_candidates    [N × 1] uint8 (후보 개수)
```

### 2.2 알고리즘

```
O(1) 복잡도 근거:
  - LUT 크기 M은 설계 상수 (각도 해상도 × 범위, 예: 3600 포인트)
  - 역보간은 LUT에서 RSSD 값 일치 인덱스 탐색 → O(M) but M 고정
  - 단조 구간에서는 binary search → O(log M) ≈ O(1) (M 고정)
  - 실시간 추론: LUT 조회만 수행 (학습 불필요)
```

```
function [doa_est, doa_info] = estimate_doa_rssd(rssd_measured, lut, params)

    N = length(rssd_measured)
    doa_est          = zeros(N, 1)
    ambiguity_flag   = false(N, 1)
    residual         = zeros(N, 1)
    n_candidates     = zeros(N, 1, 'uint8')

    for i = 1 : N
        rssd_i = rssd_measured(i)

        % LUT에서 RSSD 차이 최소화 위치 탐색
        dist = abs(lut.rssd_curve - rssd_i)

        if isfield(params, 'monotonic_only') && params.monotonic_only
            % 단조 구간 인덱스만 사용
            mask = lut.ang_axis >= lut.monotonic_range(1) & ...
                   lut.ang_axis <= lut.monotonic_range(2)
            dist(~mask) = Inf
        end

        [min_dist, min_idx] = min(dist)
        doa_est(i) = lut.ang_axis(min_idx)
        residual(i) = min_dist

        % 모호성 검사: 같은 RSSD 값이 단조 구간 밖에도 존재하는지
        close_thresh = 0.5   % dB
        n_close = sum(dist < close_thresh)
        n_candidates(i) = uint8(min(n_close, 255))
        if n_close > 1
            ambiguity_flag(i) = true
        end
    end

    doa_info.ambiguity_flag = ambiguity_flag
    doa_info.residual       = residual
    doa_info.n_candidates   = n_candidates
end
```

---

## 3. M09: estimate_position

### 3.1 시그니처

```matlab
function [pos_est, pos_info] = estimate_position(sim_data_test, lut, params)
% ESTIMATE_POSITION  DoA + ranging → 2D 위치 추정
%
% 입력:
%   sim_data_test — sim_data 구조체 (data_role='test')
%     .CIR_rx1, .CIR_rx2   (ranging용 CIR)
%     .RSS_rx1, .RSS_rx2    (RSSD DoA용)
%     .x_coord_m, .y_coord_m (ground truth, 오차 계산용)
%   lut — M07 출력
%   params — struct:
%     .c0                  = 299792458  [m/s]
%     .fp_threshold_ratio  = 0.20
%     .fp_search_window_ns = []
%     .anchor_x_m          = 0.0       [m]  TODO: Tx 앵커 위치
%     .anchor_y_m          = 0.0       [m]
%     .doa_reference_deg   = 0.0       [deg]  TODO: 각도 기준 방향
%
% 출력:
%   pos_est — MATLAB table:
%     pos_id, doa_est [deg], range_est [m],
%     x_est [m], y_est [m],
%     doa_error [deg], range_error [m], pos_error [m]
%   pos_info — struct:
%     .lut_used   lut 객체 참조
%     .ambiguity_flags  [N × 1] logical
```

### 3.2 Ranging 알고리즘

```
% RHCP CIR의 first-path ToA → 거리 추정

fp_idx = detect_first_path(abs(cir_rx1), params)
t_fp_ns = sim_data_test.t_axis(fp_idx)      % [ns]
t_fp_s  = t_fp_ns * 1e-9                    % [s]

range_est = t_fp_s * params.c0              % [m]
% TODO: single-sided (one-way) vs round-trip (two-way) 확인 필요
%       Two-way: range = t_fp_s * c0 / 2
%       현재는 one-way로 가정 (t=0이 Tx 전송 시점이 아닐 수 있음 → 절대값 오차 있음)
%       상대적 거리 순위는 일관성 유지 → 논문에서 주의사항으로 기술
```

### 3.3 위치 계산

```
% DoA + Range → (x, y)
% TODO: 좌표계 확인 (앵커 원점, 각도 기준) 후 수식 확정

x_est = params.anchor_x_m + range_est * cos(deg2rad(doa_est + params.doa_reference_deg))
y_est = params.anchor_y_m + range_est * sin(deg2rad(doa_est + params.doa_reference_deg))
```

### 3.4 오차 계산

```
doa_true   = atan2d(gt_y - params.anchor_y_m, gt_x - params.anchor_x_m) ...
             - params.doa_reference_deg
range_true = sqrt((gt_x - params.anchor_x_m)^2 + (gt_y - params.anchor_y_m)^2)

doa_error   = abs(doa_est   - doa_true)    [deg]
range_error = abs(range_est - range_true)  [m]
pos_error   = sqrt((x_est - gt_x)^2 + (y_est - gt_y)^2)  [m]
```

### 3.5 Pseudocode (전체)

```
function [pos_est, pos_info] = estimate_position(sim_data_test, lut, params)

    N_pos = size(sim_data_test.CIR_rx1, 1)
    doa_est_arr   = zeros(N_pos, 1)
    range_est_arr = zeros(N_pos, 1)
    x_est_arr     = zeros(N_pos, 1)
    y_est_arr     = zeros(N_pos, 1)

    % 1. RSSD 계산
    rssd_meas = sim_data_test.RSS_rx1 - sim_data_test.RSS_rx2   % [N_pos × 1] dB

    % 2. DoA 추정
    [doa_est_arr, doa_info_all] = estimate_doa_rssd(rssd_meas, lut, params)

    % 3. Ranging (위치별)
    for i = 1 : N_pos
        cir1 = sim_data_test.CIR_rx1(i, :)'
        [fp_idx, ~] = detect_first_path(abs(cir1), params)
        if isnan(fp_idx)
            range_est_arr(i) = NaN
        else
            t_fp_ns = sim_data_test.t_axis(fp_idx)
            range_est_arr(i) = t_fp_ns * 1e-9 * params.c0
        end
    end

    % 4. 위치 계산
    ang_rad = deg2rad(doa_est_arr + params.doa_reference_deg)
    x_est_arr = params.anchor_x_m + range_est_arr .* cos(ang_rad)
    y_est_arr = params.anchor_y_m + range_est_arr .* sin(ang_rad)

    % 5. 오차 계산 (ground truth 있는 경우)
    gt_x = sim_data_test.x_coord_m
    gt_y = sim_data_test.y_coord_m
    pos_error_arr   = sqrt((x_est_arr - gt_x).^2 + (y_est_arr - gt_y).^2)
    range_true_arr  = sqrt((gt_x - params.anchor_x_m).^2 + (gt_y - params.anchor_y_m).^2)
    range_error_arr = abs(range_est_arr - range_true_arr)
    doa_true_arr    = atan2d(gt_y - params.anchor_y_m, gt_x - params.anchor_x_m) ...
                      - params.doa_reference_deg
    doa_error_arr   = abs(doa_est_arr - doa_true_arr)

    % 6. 출력 테이블
    pos_est = table(sim_data_test.pos_id, doa_est_arr, range_est_arr, ...
                    x_est_arr, y_est_arr, doa_error_arr, range_error_arr, pos_error_arr, ...
        'VariableNames', {'pos_id','doa_est','range_est','x_est','y_est', ...
                          'doa_error','range_error','pos_error'})

    pos_info.lut_used         = lut
    pos_info.ambiguity_flags  = doa_info_all.ambiguity_flag
end
```

---

## 4. 검증 체크리스트

- [ ] **guide 데이터 존재 확인** (TODO, 최우선)
- [ ] LUT의 RSSD-angle 곡선 플롯: 단조 구간이 ±90° 내에 존재하는가?
- [ ] `lut.monotonic_range` 폭이 최소 30° 이상인가? (DoA 추정 유효 범위)
- [ ] 모호성 발생 비율: `mean(ambiguity_flag)` < 10%인가?
- [ ] Ranging 오차 중앙값: 실내 시나리오 기준 < 1m인가?
- [ ] 위치 추정 오차 CDF: 50th percentile < 0.5m인가? (ISAP 논문 목표)
- [ ] 좌표계 일관성: `x_est ≈ gt_x`, `y_est ≈ gt_y` (systematic offset 없는지)

---

*최종 수정: 2026-04-05 | 작성자: Claude Code (Architecture Agent) v2*
