# 구현 명세: run_joint_phase1 / main_run_all

> 모듈: M10, M16 | 버전: 2.0

---

## 1. M10: run_joint_phase1

### 1.1 시그니처

```matlab
function joint_results = run_joint_phase1(sim_data_guide, sim_data_test, params)
% RUN_JOINT_PHASE1  Feature 추출 + 위치추정 통합 실행
%
% 입력:
%   sim_data_guide — M02 출력, data_role='guide' (inc_ang 기반, RSSD LUT 생성용)
%                    ※ 현재 데이터에 guide 타입 없을 수 있음 → §1.4 fallback 참조
%   sim_data_test  — M02 출력, data_role='test' (x_y_coord 기반, 추정 대상)
%   params         — 전체 params 구조체
%
% 출력:
%   joint_results — struct:
%     .feature_table   M06 출력 (test 데이터 기반)
%     .sim_data_test   CIR/RSS 포함 sim_data (M06 반환값)
%     .lut             M07 출력 (guide → RSSD LUT)
%     .pos_est         M09 출력 (2D 위치추정 결과)
%     .params          사용된 파라미터 스냅샷
%     .timestamp       실행 시각 (datetime)
```

### 1.2 실행 흐름

```
1. (guide 데이터가 있는 경우)
   sim_data_guide feature 추출 (RSS 확보 목적)
   lut = build_rssd_lut(sim_data_guide, params)

2. test 데이터 feature 추출
   [feature_table, sim_data_test] = extract_features_batch(sim_data_test, params)

3. 위치추정 (guide/lut 사용 가능한 경우)
   pos_est = estimate_position(sim_data_test, lut, params)

4. joint_results 조립
```

### 1.3 Pseudocode

```
function joint_results = run_joint_phase1(sim_data_guide, sim_data_test, params)

    fprintf('[Joint Phase 1] 시작: %s\n', datetime('now'))

    % --- 1. RSSD LUT 생성 ---
    if ~isempty(sim_data_guide) && isfield(sim_data_guide, 'inc_ang')
        fprintf('  [M07] RSSD LUT 생성 중...\n')
        [~, sim_data_guide] = extract_features_batch(sim_data_guide, params)
        lut = build_rssd_lut(sim_data_guide, params)
    else
        lut = []
        warning('[run_joint_phase1] guide 데이터 없음. 위치추정 skipped.')
    end

    % --- 2. Test 데이터 Feature 추출 ---
    fprintf('  [M06] Feature 추출 중 (N_pos=%d)...\n', size(sim_data_test.CIR_rx1,1))
    [feature_table, sim_data_test] = extract_features_batch(sim_data_test, params)

    % --- 3. 위치추정 ---
    if ~isempty(lut)
        fprintf('  [M09] 위치추정 중...\n')
        [pos_est, ~] = estimate_position(sim_data_test, lut, params)
    else
        pos_est = table()   % 빈 테이블
    end

    % --- 4. 결과 조립 ---
    joint_results.feature_table  = feature_table
    joint_results.sim_data_test  = sim_data_test
    joint_results.lut            = lut
    joint_results.pos_est        = pos_est
    joint_results.params         = params
    joint_results.timestamp      = datetime('now')

    fprintf('[Joint Phase 1] 완료. valid=%d/%d, pos_est=%d\n', ...
        sum(feature_table.valid_flag), height(feature_table), height(pos_est))
end
```

### 1.4 Guide 데이터 없는 경우 Fallback

> 현재 보유 데이터(`cp_caseA/B/C.csv`)는 모두 (x_coord, y_coord) 기반으로,
> RSSD LUT 생성에 필요한 inc_ang 기반 guide 데이터가 확인되지 않음.
>
> **Fallback 옵션** (guide 데이터 확보 전):
> 1. `sim_data_guide = []` 로 전달 → 위치추정 skip, feature 추출만 수행
> 2. Test 데이터 일부(예: 10%)를 pseudo-guide로 사용 → 자가 보정 방식
>    (각도 = atan2d(y_coord - anchor_y, x_coord - anchor_x) 로 inc_ang 계산)
> 3. 시뮬레이션 기반 LUT 사용 (별도 MATLAB ray-tracing 결과)
>
> **현재 권장**: 옵션 1 (feature 추출만). guide 데이터 확보 시 옵션 2 또는 3으로 전환.

### 1.5 독립 호출 모드

```matlab
% Feature만 추출 (위치추정 없이)
function [feature_table, sim_data] = run_features_only(sim_data_test, params)
    [feature_table, sim_data] = extract_features_batch(sim_data_test, params)
end

% 여러 case 파일 통합 처리
function feature_table_all = run_all_cases(data_dir, pol_type, params)
    % pol_type: 'CP' | 'LP' | 'both'
    cases = {'caseA', 'caseB', 'caseC'}
    feature_table_all = table()
    for c = cases
        if strcmp(pol_type, 'both') || strcmp(pol_type, 'CP')
            fp = fullfile(data_dir, ['cp_' c{1} '.csv'])
            ft = load_sparam_table(fp, params)
            sd = build_sim_data_from_table(ft, params)
            [ft_feat, ~] = extract_features_batch(sd, params)
            feature_table_all = [feature_table_all; ft_feat]
        end
        if strcmp(pol_type, 'both') || strcmp(pol_type, 'LP')
            fp = fullfile(data_dir, ['lp_' c{1} '.csv'])
            % ... (동일 처리)
        end
    end
end
```

---

## 2. M16: main_run_all (v2)

### 2.1 params 초기화 블록

```matlab
%% params 설정 (모든 모듈 공유)
params = struct()

% 데이터 경로
params.data_dir       = fullfile(pwd, 'data')
params.results_dir    = fullfile(pwd, 'results')
params.figures_dir    = fullfile(pwd, 'figures')

% CSV 열 이름 (readtable 변환 후)
params.col_x          = 'x_coord_n_'
params.col_y          = 'y_coord_n_'
params.col_freq       = 'Freq_GHz_'
params.col_mag_rx1    = 'mag_S_rx1_p1_tx_p1___'
params.col_ang_rx1    = 'ang_deg_S_rx1_p1_tx_p1___deg_'
params.col_mag_rx2    = 'mag_S_rx2_p1_tx_p1___'
params.col_ang_rx2    = 'ang_deg_S_rx2_p1_tx_p1___deg_'
params.coord_unit     = 'mm'
params.phase_unit     = 'deg'

% 레이블 매핑 (PLACEHOLDER: 연구자 확정 필요)
params.case_label_map = containers.Map( ...
    {'caseA', 'caseB', 'caseC'}, ...
    {true,    true,    true   })   % 현재: 전부 LoS → gate 자동 발동

% CIR 합성
params.window_type     = 'hanning'
params.zeropad_factor  = 4
params.freq_range_ghz  = [3.1, 10.6]

% Feature 추출
params.fp_threshold_ratio    = 0.20
params.fp_search_window_ns   = []
params.T_w                   = 2.0
params.min_power_dbm         = -120
params.r_CP_clip             = 10000
params.afp_cir_source        = 'RHCP'

% 위치추정
params.c0                    = 299792458
params.anchor_x_m            = 0.0     % TODO: 확인 필요
params.anchor_y_m            = 0.0     % TODO: 확인 필요
params.doa_reference_deg     = 0.0     % TODO: 확인 필요
params.rssd_interp_method    = 'pchip'
params.lut_ang_step          = 0.1

% 분류 실험
params.cv_folds              = 5
params.random_seed           = 42
params.normalize             = true
params.skip_classification   = false
params.nlos_min_count        = 10
```

### 2.2 전체 실행 흐름 Pseudocode

```matlab
%% main_run_all.m — Track 3 전체 파이프라인 v2
% ─────────────────────────────────────────────
rng(params.random_seed)
if ~exist(params.results_dir, 'dir'), mkdir(params.results_dir); end
if ~exist(params.figures_dir, 'dir'), mkdir(params.figures_dir); end

%% Phase 1A: 데이터 로드 + CIR 합성
% CP 데이터 (핵심, r_CP 계산 대상)
fprintf('=== Phase 1A: 데이터 로드 ===\n')
cp_tables = cell(3,1)
cp_sim    = cell(3,1)
case_ids  = {'caseA', 'caseB', 'caseC'}
for k = 1:3
    fp = fullfile(params.data_dir, ['cp_' case_ids{k} '.csv'])
    cp_tables{k} = load_sparam_table(fp, params)
    cp_sim{k}    = build_sim_data_from_table(cp_tables{k}, params)
    fprintf('  cp_%s: N_pos=%d, N_fft=%d\n', ...
        case_ids{k}, size(cp_sim{k}.CIR_rx1,1), size(cp_sim{k}.CIR_rx1,2))
end

% LP 데이터 (비교 베이스라인, 선택)
if params.run_lp_comparison   % 기본값 false
    for k = 1:3
        fp = fullfile(params.data_dir, ['lp_' case_ids{k} '.csv'])
        lp_tables{k} = load_sparam_table(fp, params)
        lp_sim{k}    = build_sim_data_from_table(lp_tables{k}, params)
    end
end

%% Phase 1B: Joint Phase 1 (Feature + Localization)
fprintf('=== Phase 1B: Joint Phase 1 ===\n')
% 모든 CP case 통합
sim_data_all = merge_sim_data(cp_sim)   % 헬퍼: 여러 sim_data 수직 결합
joint_results = run_joint_phase1([], sim_data_all, params)
                                         % guide=[] (현재 미보유)
feature_table = joint_results.feature_table
pos_est       = joint_results.pos_est

%% Phase 1C: Label Gate
fprintf('=== Phase 1C: Label 검증 ===\n')
valid_mask = feature_table.valid_flag
labels_v   = feature_table.label(valid_mask)
n_los      = sum(labels_v)
n_nlos     = sum(~labels_v)
n_invalid  = sum(~valid_mask)
fprintf('Labels: LoS=%d, NLoS=%d, Invalid=%d (총 %d)\n', ...
        n_los, n_nlos, n_invalid, height(feature_table))

if n_nlos < params.nlos_min_count
    params.skip_classification = true
    warning('[Gate] NLoS=%d < %d → 분류 실험 SKIPPED', n_nlos, params.nlos_min_count)
end

%% Phase 2: 분류 실험 (LoS-only gate 통과 시에만)
if ~params.skip_classification
    fprintf('=== Phase 2: 분류 실험 ===\n')
    features_v = [feature_table.r_CP(valid_mask), feature_table.a_FP(valid_mask)]

    % Logistic Regression (핵심 모델)
    [model, norm_p] = train_logistic(features_v, labels_v, params)
    results = eval_roc_calibration(model, norm_p, features_v, labels_v, params)
    fprintf('  Logistic AUC=%.3f (±%.3f), ECE=%.3f\n', ...
            model.cv_auc_mean, model.cv_auc_std, results.ece)

    % 비교 ML 모델
    benchmark = run_ml_benchmark(features_v, labels_v, params)

    % Ablation
    ablation = run_ablation(joint_results.sim_data_test, labels_v, params)
else
    fprintf('=== Phase 2: SKIPPED (LoS-only) ===\n')
    model = []; results = []; benchmark = []; ablation = []
end

%% Phase 3: Figure 생성
fprintf('=== Phase 3: Figure 생성 ===\n')
if params.skip_classification
    generate_figures_losonly(feature_table, pos_est, params)   % Fig P1
else
    generate_figures(feature_table, model, results, benchmark, ablation, params)
end

%% 결과 저장
fprintf('=== 결과 저장 ===\n')
save(fullfile(params.results_dir, 'joint_results_v2.mat'), ...
    'joint_results', 'params', '-v7.3')
if ~params.skip_classification
    save(fullfile(params.results_dir, 'classification_results.mat'), ...
        'model', 'norm_p', 'results', 'benchmark', 'ablation')
end
fprintf('=== 완료 ===\n')
```

### 2.3 merge_sim_data 헬퍼 (간단 버전)

```matlab
function sim_merged = merge_sim_data(sim_cell)
% 여러 sim_data를 수직 결합 (pos_id 재인덱싱)
    sim_merged = sim_cell{1}
    offset = size(sim_cell{1}.CIR_rx1, 1)
    for k = 2 : length(sim_cell)
        sd = sim_cell{k}
        sim_merged.CIR_rx1   = [sim_merged.CIR_rx1;   sd.CIR_rx1]
        sim_merged.CIR_rx2   = [sim_merged.CIR_rx2;   sd.CIR_rx2]
        sim_merged.labels    = [sim_merged.labels;    sd.labels]
        sim_merged.x_coord_m = [sim_merged.x_coord_m; sd.x_coord_m]
        sim_merged.y_coord_m = [sim_merged.y_coord_m; sd.y_coord_m]
        sim_merged.RSS_rx1   = [sim_merged.RSS_rx1;   sd.RSS_rx1]
        sim_merged.RSS_rx2   = [sim_merged.RSS_rx2;   sd.RSS_rx2]
        sim_merged.pos_id    = [sim_merged.pos_id;    uint32((1:size(sd.CIR_rx1,1))' + offset)]
        offset = offset + size(sd.CIR_rx1, 1)
    end
    % t_axis, fs_eff는 첫 번째 파일 기준 유지 (동일 주파수 범위 가정)
end
```

---

## 3. 검증 체크리스트

- [ ] `params.col_*` 기본값이 실제 readtable 출력과 일치하는가? (`T.Properties.VariableNames`)
- [ ] `params.case_label_map` 확정 후 `n_los`, `n_nlos` 출력 확인
- [ ] `merge_sim_data` 후 `N_pos` = 세 case의 합인가?
- [ ] Phase 1A에서 각 CP case 로드 시 에러 없이 완료되는가?
- [ ] LoS-only Gate: 현재 `params.case_label_map` 설정으로 Gate 발동 예상 → warning 출력 확인
- [ ] results/ 및 figures/ 디렉토리 자동 생성 확인

---

*최종 수정: 2026-04-05 | 작성자: Claude Code (Architecture Agent) v2*
