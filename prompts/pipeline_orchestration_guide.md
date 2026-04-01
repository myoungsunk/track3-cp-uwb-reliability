# Track 3 파이프라인 오케스트레이션 가이드

## 전체 흐름 (MSK가 직접 조율)

```
Phase 0                Phase 1              Phase 2              Phase 3
Claude Code            Codex                Codex                Claude Code
아키텍처 설계    →     Feature 구현    →    Model+Bench 구현  →  리뷰+해석
    ↓                     ↓                     ↓                    ↓
ARCHITECTURE.md      src/extract_*.m      src/train_*.m        REVIEW_*.md
specs/*.md           tests/test_*.m       src/run_*.m          FIGURE_REVIEW.md
                     data/processed/      results/             논문 서술 제안
```

---

## 단계별 실행 매뉴얼

### Step 1: GitHub 레포 초기화
```bash
mkdir track3-cp-uwb-reliability && cd $_
git init
mkdir -p docs specs src tests data/{raw,processed} results/figures
# prompts/ 디렉토리에 phase0~3 프롬프트 파일 복사
git add . && git commit -m "init: project structure"
```

### Step 2: Phase 0 실행 (Claude Code)
1. Claude Code 세션 시작
2. prompts/phase0_claude_code_architecture.md 전체를 입력
3. 출력된 ARCHITECTURE.md, spec_*.md 파일들을 해당 디렉토리에 저장
4. **MSK 검수**: spec의 물리 지표 정의가 본인 의도와 일치하는지 확인
   - 특히 SIM1/SIM2의 실제 .mat 구조와 spec의 PLACEHOLDER 부분 대조
   - r_CP가 linear인지 dB인지, a_FP의 window 크기가 적절한지
5. git commit -m "phase0: architecture and specs"

### Step 3: Phase 1 실행 (Codex)
1. Codex 세션에서 레포 연결
2. prompts/phase1_codex_feature_extraction.md 전체를 입력
   + specs/spec_extract_features.md를 컨텍스트로 추가
3. 구현된 .m 파일들을 src/, tests/에 커밋
4. **MSK 검수 (필수)**: SIM1/SIM2 .mat 파일을 실제로 로드해서
   - fieldnames 확인 → extract_features_batch.m의 PLACEHOLDER 수정
   - CIR 샘플 1개를 plot하여 first-path 검출이 합리적인지 시각적 확인
5. tests/ 실행하여 pass 확인
6. git commit -m "phase1: feature extraction implemented"

### Step 4: MSK 데이터 검증 (사람이 직접)
```matlab
% SIM1 데이터 로드 후 sanity check
load('data/raw/SIM1.mat');
disp(fieldnames(sim_data));  % → specs의 PLACEHOLDER 갱신

% feature 추출 테스트 (1개 위치)
params = struct('fp_threshold_ratio', 0.2, 'fp_window_ns', 2.0, ...
                'min_power_dbm', -120, 'r_CP_clip', 10000);
r_test = extract_rcp(cir_rhcp_sample, cir_lhcp_sample, fs, params);
a_test = extract_afp(cir_rhcp_sample, fs, params);
fprintf('r_CP = %.2f, a_FP = %.4f\n', r_test, a_test);

% Batch 추출
ft = extract_features_batch('data/raw/SIM1.mat', params);
summary(ft)  % → NaN, Inf 없는지 확인
```

### Step 5: Phase 2 실행 (Codex)
1. prompts/phase2_codex_model_benchmark.md 입력
2. data/processed/features_SIM1.mat을 입력 데이터로 지정
3. 구현 후 main_run_all.m 실행 (전체 파이프라인 한 번에)
4. git commit -m "phase2: model training and benchmark"

### Step 6: Phase 3 실행 (Claude Code)
1. prompts/phase3_claude_code_review.md 입력
2. src/ 전체 코드 + results/ 전체 결과를 컨텍스트로 제공
3. 출력된 REVIEW, FIGURE_REVIEW 파일 저장
4. **FAIL 항목이 있으면**: Codex에게 수정 지시 → 재구현 → 재리뷰 루프
5. git commit -m "phase3: review complete"

### Step 7: 반복 (필요 시)
- Claude Code 리뷰 → FAIL → Codex 수정 → Claude Code 재리뷰
- 통상 1~2회 반복이면 충분

---

## 하네스 프롬프팅의 핵심 원칙

### 1. Spec이 곧 계약서
Claude Code가 쓴 spec = Codex에 대한 계약서.
spec에 없는 것은 구현하지 말라고 Codex에게 명시적으로 지시.
→ Codex가 "자체 판단"으로 설계를 변경하는 것을 방지.

### 2. PLACEHOLDER 패턴
모르는 것은 정직하게 PLACEHOLDER로 표시.
MSK가 직접 실제 데이터를 보고 채워넣음.
→ AI가 없는 데이터를 "추측"하는 hallucination 방지.

### 3. 검증 가능한 단위
모든 출력에 단위 테스트 또는 sanity check 포함.
→ "돌아가는 코드"가 아니라 "검증된 코드"를 목표.

### 4. 결과 해석은 Claude Code에게
Codex는 숫자를 만들고, Claude Code는 숫자의 의미를 해석.
→ "AUC 0.92가 논문에서 어떤 톤으로 서술되어야 하는가"는 연구 맥락이 필요한 판단.

### 5. MSK가 교차점 (Choke Point)
Phase 간 전환은 반드시 MSK가 결과를 확인한 후 진행.
특히 Step 4 (데이터 검증)는 AI에게 위임 불가.
→ SIM1/SIM2의 실제 구조는 MSK만 알고 있음.

---

## 예상 소요 시간

| Phase | 주체 | 예상 시간 | 비고 |
|-------|------|----------|------|
| 0 | Claude Code | 30분 | 프롬프트 입력 + 출력 검수 |
| 1 | Codex | 1~2시간 | 구현 + 테스트 |
| MSK 검증 | MSK | 2~3시간 | 실제 데이터 로드, PLACEHOLDER 수정, sanity check |
| 2 | Codex | 2~3시간 | 4개 모델 학습 + 벤치마크 |
| 3 | Claude Code | 1시간 | 코드 리뷰 + 결과 해석 |
| 수정 루프 | Codex+Claude | 1~2시간 | FAIL 항목 수정 |
| **합계** | | **~10시간** | 1~2일 내 완료 가능 |

---

## Troubleshooting

| 문제 | 원인 | 해결 |
|------|------|------|
| Codex가 spec을 무시하고 자체 설계 | 프롬프트 상단의 역할 지시가 약함 | "명세에 없는 설계 판단은 하지 마라" 문장 강화 |
| SIM1/SIM2 구조가 예상과 다름 | PLACEHOLDER가 실제와 불일치 | Step 4에서 MSK가 직접 fieldnames 확인 후 spec 갱신 |
| ML 벤치마크에서 Logistic이 압도적으로 낮음 | 특징 공간이 비선형 | r_CP에 log 변환 외 추가 비선형 변환 고려, 또는 2차 항 추가 |
| FLOPs 차이가 3자릿수 미달 | SVM의 N_sv가 매우 작음 | RF/DNN과의 비교에 집중, SVM은 "중간 복잡도"로 재포지셔닝 |
| ECE가 높음 (>0.10) | Logistic이 miscalibrated | Platt scaling 또는 isotonic regression 후처리 추가 |
