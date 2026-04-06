# 구현 명세: load_sparam_table.m / build_sim_data_from_table.m / load_los_nlos_labels.m

> 모듈: M01, M02, M01b | 버전: 1.1
> v1.1 변경: 좌표 단위 mm 확정, 레이블 로딩을 좌표별 외부 파일 방식으로 전면 변경,
>            guide 데이터(inc_ang 기반) 존재 확정 → RSSD 위치추정 활성화

---

## 1. 실 데이터 포맷 요약

CSV 파일 (`cp_caseA.csv` 예시):

```
x_coord [n],y_coord [n],Freq [GHz],mag(S(rx1,p1,tx_p1)) [],ang_deg(S(rx1,p1,tx_p1)) [deg],mag(S(rx2,p1,tx_p1)) [],ang_deg(S(rx2,p1,tx_p1)) [deg]
750,-1750,6.24,0.00082,-54.1408,0.000701,34.60152
...
```

MATLAB `readtable` 자동 변환 후 열 이름 (`VariableNamingRule='modify'` 기준):

| 원본 | 변환 후 |
|------|--------|
| `x_coord [n]` | `x_coord_n_` | **단위 = mm 확정** |
| `y_coord [n]` | `y_coord_n_` | **단위 = mm 확정** |
| `Freq [GHz]` | `Freq_GHz_` |
| `mag(S(rx1,p1,tx_p1)) []` | `mag_S_rx1_p1_tx_p1___` |
| `ang_deg(S(rx1,p1,tx_p1)) [deg]` | `ang_deg_S_rx1_p1_tx_p1___deg_` |
| `mag(S(rx2,p1,tx_p1)) []` | `mag_S_rx2_p1_tx_p1___` |
| `ang_deg(S(rx2,p1,tx_p1)) [deg]` | `ang_deg_S_rx2_p1_tx_p1___deg_` |

> **파일 형식**: Ansys 시뮬레이션 출력 CSV (ASCII, 헤더 1행 포함).
> MATLAB 버전별 readtable 변환 이름 차이 있을 수 있음.
> 최초 실행 시 `T = readtable('cp_caseA.csv'); disp(T.Properties.VariableNames)` 로 확인.
> 확인 후 `params.col_*` 기본값 업데이트.

---

## 2. M01: load_sparam_table

### 2.1 함수 시그니처

```matlab
function freq_table = load_sparam_table(filepath, params)
% LOAD_SPARAM_TABLE  S-parameter CSV 로드 및 표준 freq_table 변환
%
% 입력:
%   filepath  — string, CSV 파일 전체 경로
%   params    — struct (아래 §2.2 참조)
%
% 출력:
%   freq_table — MATLAB table, 열:
%     x_coord_mm  [double]   Rx x 좌표 [mm]
%     y_coord_mm  [double]   Rx y 좌표 [mm]
%     freq_ghz    [double]   주파수 [GHz]
%     S21_rx1     [complex]  rx1 복소 전달함수 (mag*exp(j*ang*pi/180))
%     S21_rx2     [complex]  rx2 복소 전달함수
%     group_id    [uint32]   동일 (x,y) 위치 → 동일 ID
%     pol_type    [string]   'CP' | 'LP'  (파일명에서 파싱)
%     case_id     [string]   'caseA' | 'caseB' | 'caseC'
```

### 2.2 params 필드

| 필드 | 기본값 | 설명 |
|------|--------|------|
| `params.col_x` | `'x_coord_n_'` | x좌표 열 이름 (readtable 변환 후) |
| `params.col_y` | `'y_coord_n_'` | y좌표 열 이름 |
| `params.col_freq` | `'Freq_GHz_'` | 주파수 열 이름 |
| `params.col_mag_rx1` | `'mag_S_rx1_p1_tx_p1___'` | rx1 진폭 열 |
| `params.col_ang_rx1` | `'ang_deg_S_rx1_p1_tx_p1___deg_'` | rx1 위상 열 |
| `params.col_mag_rx2` | `'mag_S_rx2_p1_tx_p1___'` | rx2 진폭 열 |
| `params.col_ang_rx2` | `'ang_deg_S_rx2_p1_tx_p1___deg_'` | rx2 위상 열 |
| `params.coord_unit` | `'mm'` | 좌표 단위 (`'mm'` → 내부적으로 mm 유지, M02에서 m 변환) |
| `params.phase_unit` | `'deg'` | 위상 단위 (`'deg'` 또는 `'rad'`) |
| `params.case_label_map` | containers.Map (PLACEHOLDER) | case_id → LoS/NLoS 레이블 매핑 |

### 2.3 Pseudocode

```
function freq_table = load_sparam_table(filepath, params)

    % 1. 파일 유형 판별
    [~, fname, ext] = fileparts(filepath)
    if ext == '.csv'
        T_raw = readtable(filepath, 'VariableNamingRule', 'modify')
    elseif ext == '.mat'
        S = load(filepath)
        T_raw = struct2table(S)   % TODO: MAT 구조에 따라 수동 매핑 필요
        warning('MAT 파일: 열 자동 매핑 확인 필요')
    else
        error('지원하지 않는 파일 형식: %s', ext)
    end

    % 2. 열 이름 검증
    required_cols = {params.col_x, params.col_y, params.col_freq,
                     params.col_mag_rx1, params.col_ang_rx1,
                     params.col_mag_rx2, params.col_ang_rx2}
    missing = setdiff(required_cols, T_raw.Properties.VariableNames)
    if ~isempty(missing)
        error('열 이름 불일치: %s\n실제 열: %s', ...
              strjoin(missing,', '), strjoin(T_raw.Properties.VariableNames,', '))
    end

    % 3. 복소 전달함수 계산
    if params.phase_unit == 'deg'
        ang_rx1_rad = T_raw.(params.col_ang_rx1) * pi/180
        ang_rx2_rad = T_raw.(params.col_ang_rx2) * pi/180
    else
        ang_rx1_rad = T_raw.(params.col_ang_rx1)
        ang_rx2_rad = T_raw.(params.col_ang_rx2)
    end
    S21_rx1 = T_raw.(params.col_mag_rx1) .* exp(1j * ang_rx1_rad)
    S21_rx2 = T_raw.(params.col_mag_rx2) .* exp(1j * ang_rx2_rad)

    % 4. group_id 생성 (동일 (x,y) → 동일 ID)
    coords = [T_raw.(params.col_x), T_raw.(params.col_y)]
    [~, ~, group_id] = unique(coords, 'rows', 'stable')
    group_id = uint32(group_id)

    % 5. 파일명에서 pol_type, case_id 파싱
    %    파일명 규칙: {lp|cp}_case{A|B|C}.csv
    fname_lower = lower(fname)
    if startsWith(fname_lower, 'cp')
        pol_type = 'CP'
    elseif startsWith(fname_lower, 'lp')
        pol_type = 'LP'
    else
        pol_type = 'UNKNOWN'
        warning('파일명에서 편파 타입 파싱 실패: %s', fname)
    end

    tok = regexp(fname_lower, 'case([abc])', 'tokens')
    if ~isempty(tok)
        case_id = ['case', upper(tok{1}{1})]   % 'caseA', 'caseB', 'caseC'
    else
        case_id = 'UNKNOWN'
        warning('파일명에서 case 식별자 파싱 실패: %s', fname)
    end

    % 6. NaN 검사
    if any(isnan(S21_rx1)) || any(isnan(S21_rx2))
        n_nan = sum(isnan(S21_rx1) | isnan(S21_rx2))
        warning('%d개 행에 NaN 값 포함 → 제거', n_nan)
        valid_rows = ~(isnan(S21_rx1) | isnan(S21_rx2))
        T_raw = T_raw(valid_rows, :)
        S21_rx1 = S21_rx1(valid_rows)
        S21_rx2 = S21_rx2(valid_rows)
        group_id = group_id(valid_rows)
    end

    % 7. 출력 테이블 조립
    freq_table = table(...)
        'VariableNames', {'x_coord_mm','y_coord_mm','freq_ghz',
                          'S21_rx1','S21_rx2','group_id','pol_type','case_id'}
end
```

---

## 3. M02: build_sim_data_from_table

### 3.1 함수 시그니처

```matlab
function sim_data = build_sim_data_from_table(freq_table, params)
% BUILD_SIM_DATA_FROM_TABLE  S-param 주파수 도메인 → 시간 도메인 CIR 변환
%
% 입력:
%   freq_table — M01 출력
%   params     — struct (§3.2 참조)
%
% 출력:
%   sim_data — struct (ARCHITECTURE.md §3 참조)
```

### 3.2 params 필드

| 필드 | 기본값 | 단위 | 설명 |
|------|--------|------|------|
| `params.window_type` | `'hanning'` | — | `'hanning'` 또는 `'kaiser'` |
| `params.kaiser_beta` | `6` | — | Kaiser window beta (window_type='kaiser'시 사용) |
| `params.zeropad_factor` | `4` | — | IFFT 포인트 = N_freq × factor |
| `params.freq_range_ghz` | `[3.1, 10.6]` | GHz | 사용할 주파수 범위 |
| `params.case_label_map` | containers.Map | — | case_id → LoS/NLoS 매핑 |

### 3.3 IFFT 알고리즘 상세

**입력**: 위치 i의 S21(f) 벡터 (N_freq × 1 complex)

**처리 흐름**:

```
① 주파수 범위 필터링
   mask = freq_ghz >= freq_range_ghz(1) & freq_ghz <= freq_range_ghz(2)
   f_sel = freq_ghz(mask)          % [N_f × 1] GHz
   H_sel = S21(mask)               % [N_f × 1] complex

② 주파수 균일성 검증
   df_all = diff(f_sel)            % 주파수 간격 벡터
   if std(df_all) / mean(df_all) > 0.01
       warning('주파수 불균일 (std/mean = %.3f). 보간 필요 가능성.', ...)
   end
   df = mean(df_all)               % [GHz] 평균 주파수 간격

③ Windowing
   if window_type == 'hanning'
       win = hann(N_f)             % MATLAB hann() 함수
   elseif window_type == 'kaiser'
       win = kaiser(N_f, kaiser_beta)
   end
   H_win = H_sel .* win            % element-wise

④ Zero-padding
   N_fft = N_f * zeropad_factor    % zero-padding 후 총 포인트 수
   H_pad = [H_win; zeros(N_fft - N_f, 1)]

⑤ IFFT
   cir = ifft(H_pad, N_fft)        % [N_fft × 1] complex
   % 결과: 복소 해석신호 (bandpass 단측 스펙트럼 입력이므로)
   % 포락선 사용: abs(cir)

⑥ 시간축 생성
   BW_hz = (max(f_sel) - min(f_sel)) * 1e9   % Hz
   dt_sec = 1 / (N_fft * df * 1e9)           % 1/(N_fft × df_Hz)
   t_axis_ns = (0 : N_fft-1) * dt_sec * 1e9  % [ns]

   % BW = 7.5 GHz, zeropad=4, N_fft ≈ N_f×4
   % 예: N_f=200, N_fft=800, df=37.5 MHz
   %     dt = 1/(800 × 37.5e6) ≈ 33.3 ps → 시간 해상도

⑦ CIR은 causal part만 사용 (t ≥ 0, 이미 ifft 출력이 t=0~(N_fft-1)*dt)
   → 별도 truncation 불필요. 단, 최초 few samples 이전에 신호가 있으면
     이는 IFFT 기준점 문제이며, first-path 검출은 상대적 peak만 사용하므로 영향 없음.
```

**RSS 계산**:

```
RSS_rx1_dBm(i) = 10 * log10(sum(abs(cir_rx1(i,:)).^2))
               % TODO: 절대 전력 교정 상수 필요 (안테나 이득, 케이블 손실 등)
               % 현재는 상대값으로 사용 (RSSD = RSS_rx1 - RSS_rx2 에서 상수 상쇄)
```

### 3.4 LoS/NLoS 레이블 처리 (v1.1 전면 변경)

**확정된 레이블 구조**:
- caseA: 전체 위치 LoS
- caseB, caseC: 위치별로 LoS/NLoS 혼재
- 레이블 파일 위치: `LOS_NLOS_EXPORT_20260405/` 디렉토리
- 레이블은 case 단위가 아닌 **좌표(x_mm, y_mm)별로 개별 지정**
- → `case_label_map` 방식 폐기, 좌표 기반 join 방식으로 대체

```
% 레이블 로딩 방식 (M01b: load_los_nlos_labels.m 별도 함수)
label_table = load_los_nlos_labels(params.label_dir, case_id, params)
% label_table 열: x_mm, y_mm, label (logical)

% build_sim_data 내부에서 좌표 기반 join
labels = match_labels_by_coord(positions_mm, label_table, params.coord_tol_mm)
% coord_tol_mm: 좌표 매칭 허용 오차 (기본값 1e-3 mm, 부동소수점 비교용)

if any(isnan(labels))
    n_unmatched = sum(isnan(labels))
    warning('[build_sim_data] %d개 위치에 레이블 매칭 실패 → LoS로 가정', n_unmatched)
    labels(isnan(labels)) = true
end
```

### 3.5 sim_data 구조체 출력

```matlab
sim_data.CIR_rx1    = CIR_rx1      % [N_pos × N_fft] complex
sim_data.CIR_rx2    = CIR_rx2      % [N_pos × N_fft] complex
sim_data.t_axis     = t_axis_ns    % [1 × N_fft] double [ns]
sim_data.fs_eff     = 1/(dt_sec)   % scalar [Hz] 유효 샘플링 주파수
sim_data.pos_id     = (1:N_pos)'   % [N_pos × 1] uint32
sim_data.labels     = labels       % [N_pos × 1] logical
sim_data.x_coord_m  = x_mm / 1e3  % [N_pos × 1] double [m] (coord_unit='mm' 가정)
sim_data.y_coord_m  = y_mm / 1e3  % [N_pos × 1] double [m]
sim_data.RSS_rx1    = RSS_rx1_dBm  % [N_pos × 1] double [dBm, 상대값]
sim_data.RSS_rx2    = RSS_rx2_dBm  % [N_pos × 1] double [dBm, 상대값]
sim_data.pol_type   = pol_type     % string: 'CP' | 'LP'
sim_data.case_id    = case_id      % string: 'caseA' | ...
sim_data.data_role  = 'test'       % 좌표 기반 → 'test'
                                   % (inc_ang 기반 데이터 있으면 'guide')
```

> **CP vs LP 처리**: M02는 편파 타입을 구분하지 않고 동일하게 처리.
> CP 파일이면 `CIR_rx1` = RHCP CIR, `CIR_rx2` = LHCP CIR.
> LP 파일이면 `CIR_rx1` = LP1 CIR, `CIR_rx2` = LP2 CIR.
> M04(extract_rcp)에서 CP 파일에만 r_CP 계산이 의미 있음을 호출자가 인지해야 함.

### 3.6 Pseudocode (전체)

```
function sim_data = build_sim_data_from_table(freq_table, params)

    groups = unique(freq_table.group_id)
    N_pos = length(groups)
    % 첫 그룹으로 N_fft 결정
    mask0 = freq_table.group_id == groups(1)
    f0    = freq_table.freq_ghz(mask0)
    N_f0  = sum(mask0)
    N_fft = N_f0 * params.zeropad_factor

    CIR_rx1 = zeros(N_pos, N_fft, 'like', 1+1j)
    CIR_rx2 = zeros(N_pos, N_fft, 'like', 1+1j)
    x_mm = zeros(N_pos, 1)
    y_mm = zeros(N_pos, 1)

    for i = 1 : N_pos
        mask = freq_table.group_id == groups(i)
        f    = freq_table.freq_ghz(mask)
        H1   = freq_table.S21_rx1(mask)
        H2   = freq_table.S21_rx2(mask)
        x_mm(i) = freq_table.x_coord_mm(find(mask, 1))
        y_mm(i) = freq_table.y_coord_mm(find(mask, 1))

        % 주파수 범위 필터
        in_range = f >= params.freq_range_ghz(1) & f <= params.freq_range_ghz(2)
        f = f(in_range); H1 = H1(in_range); H2 = H2(in_range)
        N_f = length(f)
        N_fft_i = N_f * params.zeropad_factor

        % Window
        if strcmp(params.window_type, 'hanning')
            win = hann(N_f)
        else
            win = kaiser(N_f, params.kaiser_beta)
        end

        % IFFT
        H1_pad = [H1 .* win; zeros(N_fft_i - N_f, 1)]
        H2_pad = [H2 .* win; zeros(N_fft_i - N_f, 1)]
        CIR_rx1(i, 1:N_fft_i) = ifft(H1_pad, N_fft_i)
        CIR_rx2(i, 1:N_fft_i) = ifft(H2_pad, N_fft_i)

        % 진행률
        if mod(i, 50) == 0
            fprintf('  build_sim_data: %d/%d 완료\n', i, N_pos)
        end
    end

    % 시간축 (마지막 그룹 기준 — 모두 동일하다고 가정)
    df_hz = mean(diff(f)) * 1e9
    dt_sec = 1 / (N_fft * df_hz)
    t_axis_ns = (0 : N_fft-1) * dt_sec * 1e9

    % RSS
    RSS_rx1 = 10*log10(sum(abs(CIR_rx1).^2, 2))
    RSS_rx2 = 10*log10(sum(abs(CIR_rx2).^2, 2))

    % 레이블
    [labels] = assign_labels(freq_table.case_id(1), N_pos, params)

    % 출력 조립
    sim_data.CIR_rx1   = CIR_rx1
    sim_data.CIR_rx2   = CIR_rx2
    sim_data.t_axis    = t_axis_ns
    sim_data.fs_eff    = 1 / dt_sec
    sim_data.pos_id    = uint32(1:N_pos)'
    sim_data.labels    = labels
    sim_data.x_coord_m = x_mm / 1e3
    sim_data.y_coord_m = y_mm / 1e3
    sim_data.RSS_rx1   = RSS_rx1
    sim_data.RSS_rx2   = RSS_rx2
    sim_data.pol_type  = freq_table.pol_type(1)
    sim_data.case_id   = freq_table.case_id(1)
    sim_data.data_role = 'test'
end
```

---

## 4. M01b: load_los_nlos_labels (신규)

### 4.1 시그니처

```matlab
function label_table = load_los_nlos_labels(label_dir, case_id, params)
% LOAD_LOS_NLOS_LABELS  좌표별 LoS/NLoS 레이블 로드
%
% 입력:
%   label_dir — string, LOS_NLOS_EXPORT_20260405/ 디렉토리 경로
%   case_id   — string, 'caseA' | 'caseB' | 'caseC'
%   params    — struct:
%     .label_col_x      열 이름 (x 좌표)  TODO: 실제 파일 확인 후 기본값 설정
%     .label_col_y      열 이름 (y 좌표)  TODO
%     .label_col_flag   열 이름 (LoS 플래그)  TODO
%     .label_los_value  LoS를 나타내는 값 (예: 1, 'LoS', true)  TODO
%
% 출력:
%   label_table — table:
%     .x_mm     [double]  x 좌표 [mm]
%     .y_mm     [double]  y 좌표 [mm]
%     .label    [logical] true=LoS, false=NLoS
%
% 파일명 규칙 (TODO: 실제 파일명 패턴 확인 후 업데이트):
%   예상: label_dir/caseB_los_nlos.csv 또는 label_dir/caseB/*.csv 등
```

### 4.2 TODO 목록 (연구자 확인 필요)

> `LOS_NLOS_EXPORT_20260405/` 디렉토리의 실제 내용을 확인하고 아래 항목을 채울 것:
>
> - [ ] 파일 구조: 하나의 파일에 모든 case? 또는 case별 파일 분리?
> - [ ] 열 이름: x좌표, y좌표, LoS/NLoS 플래그 열의 실제 이름
> - [ ] LoS 값: 플래그 값이 `1`/`0`인가, `'LoS'`/`'NLoS'`인가, `true`/`false`인가?
> - [ ] 좌표 단위: mm인가 m인가? (S-param CSV는 mm 확정이므로 동일하게 mm 가정)
> - [ ] 위치 커버리지: S-param CSV의 모든 (x,y) 위치가 레이블 파일에 존재하는가?

### 4.3 match_labels_by_coord 헬퍼

```
function labels = match_labels_by_coord(pos_mm, label_table, tol_mm)
% 부동소수점 좌표 매칭 (완전 일치가 아닌 허용 오차 내 매칭)
%
%   pos_mm      [N_pos × 2] double [x_mm, y_mm]
%   label_table [M × 3] table [x_mm, y_mm, label]
%   tol_mm      scalar, 기본값 1e-3

    labels = NaN(N_pos, 1)
    for i = 1 : N_pos
        dx = abs(label_table.x_mm - pos_mm(i,1))
        dy = abs(label_table.y_mm - pos_mm(i,2))
        match_idx = find(dx < tol_mm & dy < tol_mm, 1)
        if ~isempty(match_idx)
            labels(i) = label_table.label(match_idx)
        end
    end
    labels = logical(labels)   % NaN → true (warning 발생 후 fallback)
end
```

---

## 6. 검증 체크리스트 (v1.1 업데이트)

- [ ] `T.Properties.VariableNames` 확인 → `params.col_*` 기본값과 일치하는가?
- [ ] `unique(freq_table.group_id)` 수 == 예상 위치 수 (`N_pos`)인가?
- [ ] 위치별 주파수 포인트 수가 균일한가? `groupcounts(freq_table, 'group_id')`
- [ ] IFFT 후 `t_axis_ns` 최댓값: BW=7.5 GHz, N_fft=N_f×4이면 ~수십 ns (reasonable?)
- [ ] `abs(sim_data.CIR_rx1(1,:))` 플롯: 명확한 첫 번째 peak 존재하는가?
- [ ] RSS 분포: 같은 case 내에서 위치에 따라 RSS가 합리적으로 변하는가?
- [ ] `params.coord_unit = 'mm'` 가정 하에 `x_coord_m` 범위가 실내(< 20m)인가?

---

*최종 수정: 2026-04-05 | 작성자: Claude Code (Architecture Agent) v2*
