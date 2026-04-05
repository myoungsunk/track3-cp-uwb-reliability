# Track 3 파이프라인 오케스트레이션 가이드 v2

## v1 → v2 변경 요약

| 항목 | v1 | v2 |
|------|----|----|
| 데이터 소스 | SIM1/SIM2 .mat (placeholder) | S-param CSV/MAT → IFFT → CIR |
| Phase 1 범위 | Feature 추출만 | Feature + 위치추정 Joint |
| 모듈 수 | 8개 (M01~M08) | 16개 (M01~M16) |
| NLoS 데이터 | 있다고 가정 | 현재 LoS only, NLoS 별도 진행 중 |
| 분류 실험 | 항상 실행 | LoS-only gate 후 조건부 실행 |
| FLOPs 주장 | 3~4자릿수 | 1~2자릿수 (보수적) |

---

## 전체 흐름

```
Phase 0                Phase 1                   Phase 2              Phase 3
Claude Code            Codex                     Codex                Claude Code
아키텍처 v2     →     Joint 구현          →    Classification    →  리뷰+해석
    ↓                     ↓                        ↓                    ↓
ARCHITECTURE.md      M01~M10 (.m files)       M11~M15            REVIEW_*.md
specs/*.md           tests/                    (LoS-only gate)    FIGURE_REVIEW.md
                     data/processed/           results/           논문 서술 제안
```

---

## 단계별 실행 매뉴얼

### Step 1: GitHub 레포 구조 (v2)
```
track3-cp-uwb-reliability/
├── docs/
│   ├── ARCHITECTURE.md          ← Phase 0 출력
│   └── REVIEW_*.md              ← Phase 3 출력
├── specs/
│   ├── spec_load_and_build.md
│   ├── spec_extract_features_v2.md
│   ├── spec_rssd_localization.md
│   ├── spec_logistic_model_v2.md
│   ├── spec_run_joint.md
│   └── spec_ablation_v2.md
├── src/
│   ├── private/
│   │   └── detect_first_path.m
│   ├── load_sparam_table.m
│   ├── build_sim_data_from_table.m
│   ├── extract_rcp.m
│   ├── extract_afp.m
│   ├── extract_features_batch.m
│   ├── build_rssd_lut.m
│   ├── estimate_doa_rssd.m
│   ├── estimate_position.m
│   ├── run_joint_phase1.m
│   ├── train_logistic.m
│   ├── eval_roc_calibration.m
│   ├── run_ml_benchmark.m
│   ├── run_ablation.m
│   ├── generate_figures.m
│   ├── generate_figures_losonly.m
│   └── main_run_all.m
├── tests/
├── data/
│   ├── raw/          ← S-param CSV/MAT 원본
│   ├── labels/       ← NLoS 라벨 CSV (추후)
│   └── processed/    ← CIR, feature table
├── results/
│   └── figures/
└── prompts/          ← Phase 0~3 프롬프트
```

### Step 2: Phase 0 실행 (Claude Code)
1. phase0_v2_claude_code_architecture.md 전체 입력
2. 7개 파일 생성 확인
3. **MSK 검수**: spec의 S-param 열 이름이 실제 CSV와 일치하는지 확인
4. git commit

### Step 3: Phase 1 실행 (Codex)
1. phase1_v2_codex_joint_implementation.md 입력 + specs/ 전체를 컨텍스트로
2. M01~M10 + tests/ 구현
3. git commit

### Step 4: MSK 데이터 검증 (사람이 직접)

```matlab
%% 4-1: S-param 파일 구조 확인
t = readtable('data/raw/guide_incang.csv');
disp(t.Properties.VariableNames);
% → params.freq_col, s21_rhcp_cols 등 기본값 갱신

%% 4-2: CIR 합성 sanity check
params = struct();
params.window_type = 'hanning';
params.zeropad_factor = 4;
params.freq_range_ghz = [3.1, 10.6];
params.data_role = 'guide';
% ... (나머지 열 이름 파라미터 설정)

freq_table = load_sparam_table('data/raw/guide_incang.csv', params);
sim_data = build_sim_data_from_table(freq_table, params);

% CIR 1개 시각화
figure;
plot(sim_data.t_axis, abs(sim_data.CIR_RHCP(1,:)));
xlabel('Time (ns)'); ylabel('|CIR|');
title('RHCP CIR - Position 1');
% → first-path이 시각적으로 합리적인지 확인

%% 4-3: Feature 추출 테스트
params.fp_threshold_ratio = 0.20;
params.T_w = 2.0;
params.afp_cir_source = 'RHCP';
params.r_CP_clip = 10000;

[ft, sd] = extract_features_batch(sim_data, params);
summary(ft);
% → NaN/Inf 비율, r_CP/a_FP 범위 확인

%% 4-4: RSSD LUT 테스트 (guide 데이터)
lut = build_rssd_lut(sim_data, params);
figure;
plot(lut.ang_raw, lut.rssd_raw, 'o', lut.ang_axis, lut.rssd_curve, '-');
xlabel('Angle (deg)'); ylabel('RSSD (dB)');
% → 단조 구간 확인, RSSD Slope 형태 확인

%% 4-5: 라벨 분포 확인
fprintf('LoS: %d, NLoS: %d\n', sum(ft.label), sum(~ft.label));
% → 현재 LoS only 확인, NLoS 데이터 도착 시 재실행
```

### Step 5: Phase 2 실행 (Codex) — 조건부

NLoS 데이터가 확보된 후에만 실행.
확보 경로:
- (A) 진행 중인 NLoS+LoS 시뮬레이션 완료 시 → 동일 파이프라인에 투입
- (B) 기존 MATLAB ray-tracing 프레임워크(시나리오 5~8) CIR 출력 → bridge 스크립트로 변환

LoS only 상태에서도 실행 가능한 것:
- Feature 분포 확인 (r_CP, a_FP 히스토그램)
- 위치추정 정확도 평가 (DoA error, ranging error)
- T_w sensitivity (A6), r_CP scale (A7) ablation

### Step 6: Phase 3 실행 (Claude Code)
phase3_claude_code_review.md 입력 (v1과 동일, 추가 리뷰 항목만 보강)

---

## 예상 소요 시간 (v2)

| Phase | 주체 | 예상 시간 | 비고 |
|-------|------|----------|------|
| 0 | Claude Code | 45분 | spec 7개 생성 |
| 1 | Codex | 3~4시간 | M01~M10 + tests (v1 대비 모듈 증가) |
| MSK 검증 | MSK | 2~3시간 | CSV 열 확인, CIR 시각화, RSSD LUT 검증 |
| 2 | Codex | 2~3시간 | M11~M15 (NLoS 데이터 확보 후) |
| 3 | Claude Code | 1시간 | 리뷰 + 해석 |
| 수정 루프 | 전체 | 1~2시간 | |
| **합계** | | **~12시간** | Phase 1까지 1~2일, Phase 2는 NLoS 의존 |

---

## 데이터 가용성 별 실행 범위

| 현재 상태 | 실행 가능 | 실행 불가 (대기) |
|----------|----------|---------------|
| LoS only CSV | M01~M10 전체, Ablation A4~A7 | M11~M14 본실험, Fig 1~4 |
| LoS + NLoS CSV | 전체 파이프라인 | — |
| LoS + NLoS + 추가 시나리오 | 전체 + 일반화 검증 | — |

현재 상태에서 즉시 착수: Phase 0 → Phase 1 → MSK 검증 → LoS-only 결과물 확보
NLoS 도착 시: Phase 2 → Phase 3 → 논문 작성
