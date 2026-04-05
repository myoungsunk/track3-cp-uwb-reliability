# 구현 명세: run_ablation

> 모듈: M14 | 버전: 2.0
> 전제: LoS + NLoS 데이터 모두 존재 시에만 의미 있음 (skip_classification=false 조건)

---

## 1. Ablation 항목 전체 목록

| 항목 | 구성 | 논문 포함 여부 |
|------|------|--------------|
| **A1** | r_CP only | 본문 필수 |
| **A2** | a_FP only | 본문 필수 |
| **A3** | r_CP + a_FP (combined) | 본문 필수 (기준 모델) |
| A4 | a_FP 소스: RHCP / LHCP / combined / power_sum | 데이터에 따라 선택 |
| A5 | r_CP 정의: single-sample / window-energy | 데이터에 따라 선택 |
| A6 | T_w sensitivity: 1.0 / 1.5 / 2.0 / 2.5 / 3.0 ns | 데이터에 따라 선택 |
| A7 | r_CP scale: linear+zscore / log10+zscore | 선택 |

A1–A3은 ISAP 논문 본문에 포함 필수. A4–A7은 실험 결과에 따라 선택적 포함.

---

## 2. M14 시그니처

```matlab
function ablation_results = run_ablation(sim_data_test, labels, params)
% RUN_ABLATION  r_CP/a_FP 조합·정의·파라미터 sensitivity 비교
%
% 입력:
%   sim_data_test — M06 반환된 sim_data (CIR 포함, ablation 재계산용)
%   labels        — [N_valid × 1] logical, valid_flag=true 샘플 기준
%   params        — 전체 params + ablation 전용 params (§3 참조)
%
% 출력:
%   ablation_results — MATLAB table (§4 참조)
%
% 전제조건:
%   sum(labels==false) >= params.nlos_min_count
%   (LoS-only 상태에서 호출 금지)
```

---

## 3. Ablation 전용 params

```matlab
% main_run_all.m에서 run_ablation 호출 전 설정
params.ablation_items   = {'A1','A2','A3','A4','A5','A6'}  % 수행할 항목
params.ablation_T_w_list = [1.0, 1.5, 2.0, 2.5, 3.0]      % A6용 [ns]
params.ablation_afp_sources = {'RHCP','LHCP','combined','power_sum'}  % A4용
params.ablation_n_repeats   = 1   % CV 반복 횟수 (시간 제약 시 1)
```

---

## 4. 출력 형식

```matlab
% ablation_results: MATLAB table
% 열:
%   item        [string]  'A1' ~ 'A7'
%   config      [string]  'r_CP_only', 'a_FP(LHCP)', 'T_w=1.5ns', ...
%   sub_config  [string]  세부 설정 설명
%   auc         [double]  ROC AUC (5-fold mean)
%   auc_std     [double]  5-fold std
%   accuracy    [double]
%   f1          [double]
%   ece         [double]
%   delta_auc   [double]  A3(combined) 대비 AUC 차이 (A3=0 기준)

% 예시:
%   'A1', 'r_CP_only',    '',         0.82, 0.02, 0.78, 0.77, 0.09, -0.06
%   'A2', 'a_FP_only',    '',         0.79, 0.03, 0.75, 0.74, 0.10, -0.09
%   'A3', 'combined',     '',         0.88, 0.02, 0.84, 0.83, 0.07,  0.00  ← 기준
%   'A4', 'a_FP(RHCP)',   'default',  0.88, 0.02, 0.84, 0.83, 0.07,  0.00
%   'A4', 'a_FP(LHCP)',   '',         0.85, 0.02, 0.81, 0.80, 0.08, -0.03
%   'A4', 'a_FP(comb)',   '',         0.87, 0.02, 0.83, 0.82, 0.07, -0.01
%   'A6', 'T_w=1.0ns',   '',         0.86, 0.03, 0.82, 0.81, 0.08, -0.02
%   'A6', 'T_w=2.0ns',   'default',  0.88, 0.02, 0.84, 0.83, 0.07,  0.00
%   'A6', 'T_w=3.0ns',   '',         0.87, 0.02, 0.83, 0.82, 0.08, -0.01
```

---

## 5. Pseudocode

```
function ablation_results = run_ablation(sim_data_test, labels, params)

    rows = {}

    % --- A1: r_CP only ---
    if ismember('A1', params.ablation_items)
        feats_A1 = extract_features_batch_rcp_only(sim_data_test, params)
        % r_CP 열만 사용: feats = [r_CP, zeros(N,1)] → 실제로는 r_CP 단독 모델
        feats_single = feats_A1(:, 1)   % [N × 1]
        row = run_single_ablation(feats_single, labels, params)
        row.item = 'A1'; row.config = 'r_CP_only'; row.sub_config = ''
        rows{end+1} = row
    end

    % --- A2: a_FP only ---
    if ismember('A2', params.ablation_items)
        feats_A2 = extract_features_batch_afp_only(sim_data_test, params)
        feats_single = feats_A2(:, 2)   % [N × 1] a_FP
        row = run_single_ablation(feats_single, labels, params)
        row.item = 'A2'; row.config = 'a_FP_only'; row.sub_config = ''
        rows{end+1} = row
    end

    % --- A3: combined (기준) ---
    if ismember('A3', params.ablation_items)
        [feat_table, ~] = extract_features_batch(sim_data_test, params)
        feats_A3 = [feat_table.r_CP(feat_table.valid_flag), ...
                    feat_table.a_FP(feat_table.valid_flag)]
        row_A3 = run_single_ablation(feats_A3, labels, params)
        row_A3.item = 'A3'; row_A3.config = 'combined'; row_A3.sub_config = ''
        rows{end+1} = row_A3
        auc_baseline = row_A3.auc   % delta_auc 기준
    else
        auc_baseline = NaN
    end

    % --- A4: a_FP 소스 비교 ---
    if ismember('A4', params.ablation_items)
        for s = params.ablation_afp_sources
            p_a4 = params
            p_a4.afp_cir_source = s{1}
            [ft_a4, ~] = extract_features_batch(sim_data_test, p_a4)
            feats_a4 = [ft_a4.r_CP(ft_a4.valid_flag), ft_a4.a_FP(ft_a4.valid_flag)]
            row = run_single_ablation(feats_a4, labels, p_a4)
            row.item = 'A4'
            row.config = ['a_FP(' s{1} ')']
            row.sub_config = ''
            if strcmp(s{1}, params.afp_cir_source), row.sub_config = 'default'; end
            rows{end+1} = row
        end
    end

    % --- A5: r_CP 정의 (single-sample vs window-energy) ---
    if ismember('A5', params.ablation_items)
        for def = {'single', 'window'}
            p_a5 = params
            p_a5.rcp_definition = def{1}
            [ft_a5, ~] = extract_features_batch(sim_data_test, p_a5)
            feats_a5 = [ft_a5.r_CP(ft_a5.valid_flag), ft_a5.a_FP(ft_a5.valid_flag)]
            row = run_single_ablation(feats_a5, labels, p_a5)
            row.item = 'A5'; row.config = ['r_CP(' def{1} ')']
            row.sub_config = ''
            if strcmp(def{1}, 'single'), row.sub_config = 'default'; end
            rows{end+1} = row
        end
    end

    % --- A6: T_w sensitivity ---
    if ismember('A6', params.ablation_items)
        for tw = params.ablation_T_w_list
            p_a6 = params; p_a6.T_w = tw
            [ft_a6, ~] = extract_features_batch(sim_data_test, p_a6)
            feats_a6 = [ft_a6.r_CP(ft_a6.valid_flag), ft_a6.a_FP(ft_a6.valid_flag)]
            row = run_single_ablation(feats_a6, labels, p_a6)
            row.item = 'A6'; row.config = sprintf('T_w=%.1fns', tw)
            row.sub_config = ''
            if tw == params.T_w, row.sub_config = 'default'; end
            rows{end+1} = row
        end
    end

    % --- A7: r_CP scale ---
    if ismember('A7', params.ablation_items)
        for sc = {'linear', 'log10'}
            p_a7 = params; p_a7.rcp_scale = sc{1}
            [ft_a7, ~] = extract_features_batch(sim_data_test, p_a7)
            feats_a7 = [ft_a7.r_CP(ft_a7.valid_flag), ft_a7.a_FP(ft_a7.valid_flag)]
            row = run_single_ablation(feats_a7, labels, p_a7)
            row.item = 'A7'; row.config = ['r_CP_scale(' sc{1} ')']
            row.sub_config = ''
            if strcmp(sc{1}, 'linear'), row.sub_config = 'default'; end
            rows{end+1} = row
        end
    end

    % delta_auc 계산
    for k = 1:length(rows)
        rows{k}.delta_auc = rows{k}.auc - auc_baseline
    end

    % table 변환
    ablation_results = struct2table(vertcat(rows{:}))
    fprintf('[run_ablation] 완료: %d 구성\n', height(ablation_results))
end
```

### 5.1 run_single_ablation 헬퍼

```
function row = run_single_ablation(features, labels, params)
% Stratified 5-fold CV로 단일 feature 구성의 AUC 등 계산

    cv = cvpartition(labels, 'KFold', params.cv_folds, 'Stratify', true)
    auc_vec = zeros(cv.NumTestSets, 1)
    for k = 1 : cv.NumTestSets
        X_tr = features(training(cv,k), :)
        y_tr = labels(training(cv,k))
        X_te = features(test(cv,k), :)
        y_te = labels(test(cv,k))
        [X_tr_norm, mu, sig] = zscore(X_tr)
        X_te_norm = (X_te - mu) ./ sig
        mdl_k = fitglm(X_tr_norm, y_tr, 'Distribution','binomial','Link','logit')
        P_k = predict(mdl_k, X_te_norm)
        [~,~,~, auc_vec(k)] = perfcurve(y_te, P_k, true)
    end

    row.auc      = mean(auc_vec)
    row.auc_std  = std(auc_vec)
    % accuracy, f1, ece는 전체 데이터 기준 (최종 모델)
    [X_norm, mu, sig] = zscore(features)
    mdl_full = fitglm(X_norm, labels, 'Distribution','binomial','Link','logit')
    P_all = predict(mdl_full, X_norm)
    y_pred = P_all >= 0.5
    row.accuracy = mean(y_pred == labels)
    TP = sum(y_pred & labels); FP = sum(y_pred & ~labels); FN = sum(~y_pred & labels)
    prec = TP/(TP+FP+eps); rec = TP/(TP+FN+eps)
    row.f1 = 2*prec*rec/(prec+rec+eps)
    row.ece = compute_ece(P_all, labels, 10)
    row.delta_auc = 0   % 나중에 기준 대비 계산
end
```

---

## 6. 논문 포함 판단 기준

| 항목 | 포함 조건 | 논문 위치 |
|------|---------|---------|
| A1, A2, A3 | 항상 포함 | Table II 또는 Fig S2 |
| A4 (a_FP 소스) | RHCP vs 최선 소스 간 ΔAUC > 0.02이면 포함 | 보조 자료 |
| A5 (r_CP 정의) | single vs window 간 ΔAUC > 0.02이면 포함 | 보조 자료 |
| A6 (T_w) | T_w=1.0 vs 3.0 간 ΔAUC > 0.05이면 포함 | 보조 자료 |
| A7 (r_CP scale) | AUC 차이가 의미있을 때 | 보조 자료 |

**A3(combined) 대비 ΔAUC 해석 지침**:
- `|ΔAUC| < 0.02`: 두 구성 간 통계적 유의미한 차이 없음 → 단순한 구성 채택
- `ΔAUC < -0.05`: 해당 ablation 구성이 combined보다 유의미하게 열위 → 논문에서 combined의 우위로 기술

---

## 7. 검증 체크리스트

- [ ] A3 (combined) AUC > A1 (r_CP only) AND A2 (a_FP only): 두 지표의 상호 보완성 검증
- [ ] A4에서 RHCP가 최선 소스인가? (기본값 검증)
- [ ] A6에서 T_w=2.0 ns가 최적 또는 최적에 근접한가? (ΔAUC < 0.05 vs 1.0/3.0)
- [ ] A1, A2, A3 bar chart (Fig S2): AUC 차이가 시각적으로 명확한가?

---

*최종 수정: 2026-04-05 | 작성자: Claude Code (Architecture Agent) v2*
