# Phase 0: Claude Code — 전체 아키텍처 설계 프롬프트

## 컨텍스트 (이 블록을 Claude Code 세션 시작 시 그대로 붙여넣기)

```
너는 POSTECH EEE 박사과정 연구자의 연구 코드 아키텍트 역할을 수행한다.

## 연구 배경
- 프로젝트: Track 3 — CP-UWB 물리 지표 기반 초경량 공간 신뢰도 점수 산출
- 투고처: ISAP 2026 (2~4 pages), 마감 2026.06.26
- 핵심 기여: r_CP와 a_FP 두 물리 지표의 Logistic Regression 결합으로 
  ML 대비 동등 정확도 + 3~4자릿수 낮은 연산 복잡도 달성 입증
- 데이터: 기존 MATLAB 시뮬레이션 SIM1/SIM2 (CP-UWB 채널 응답 데이터)
- 언어: MATLAB (R2021b 이상)

## 물리 지표 정의
1. r_CP = P_RHCP_fp / P_LHCP_fp
   - P_RHCP_fp: RHCP 채널 CIR에서 첫 도달 경로(first path)의 수신 전력
   - P_LHCP_fp: LHCP 채널 CIR에서 첫 도달 경로의 수신 전력
   - LoS일 때 r_CP >> 1 (RHCP 우세), NLoS(홀수반사)일 때 r_CP ≈ 1 또는 < 1

2. a_FP = E_fp / E_total
   - E_fp: CIR에서 첫 도달 경로 윈도우(±T_w) 내 에너지
   - E_total: CIR 전체 에너지
   - LoS일 때 a_FP → 1 (에너지 집중), dense multipath일 때 a_FP → 0

## 프로젝트 구조
이 프로젝트는 GitHub 레포로 관리되며, 코드 구현은 별도의 AI 코딩 도구(Codex)가 담당한다.
너의 역할은:
(1) 전체 코드 아키텍처를 설계하고 ARCHITECTURE.md에 기록
(2) 각 모듈의 구현 명세(spec)를 작성하여 specs/ 디렉토리에 저장
(3) Codex가 구현한 코드를 리뷰하고 REVIEW_*.md에 피드백 기록
(4) 시뮬레이션 결과를 분석하고 논문 Figure 사양을 정의

## 출력 규칙
- 모든 출력은 Markdown 파일로 GitHub에 커밋 가능한 형태
- 코드 구현은 하지 않음 (함수 시그니처와 pseudocode만 작성)
- 모든 수치 파라미터는 근거와 함께 명시 (예: "T_w = 2ns, IEEE 802.15.4a CM3 기준 첫 클러스터 폭")
```

## 태스크

다음 3개 파일을 생성해라:

### 1. docs/ARCHITECTURE.md
전체 파이프라인을 다음 구조로 설계:
- 모듈 의존성 DAG (어떤 모듈이 어떤 모듈에 의존하는지)
- 데이터 흐름도 (SIM1/SIM2 raw → feature matrix → model → evaluation)
- 각 모듈의 입출력 데이터 형식 (변수명, 차원, dtype, 단위)
- 파라미터 테이블 (모든 하이퍼파라미터, 기본값, 근거 출처)
- Figure 목록 (논문에 들어갈 Figure 번호별 사양)

### 2. specs/spec_extract_features.md
r_CP와 a_FP 추출 모듈의 구현 명세:
- 함수 시그니처: `[r_CP, a_FP, labels, metadata] = extract_features(sim_data, params)`
- sim_data의 예상 구조 (SIM1/SIM2 .mat 파일의 필드명, 차원)
  - 만약 SIM1/SIM2의 정확한 구조를 모르면, "PLACEHOLDER: 실제 .mat 파일 로드 후 fieldnames 확인 필요"라고 명시
- First-path 검출 알고리즘 (threshold-based leading edge detection)
  - 알고리즘: CIR 절대값이 max(|CIR|) × threshold_ratio를 최초로 초과하는 인덱스
  - threshold_ratio 기본값: 0.2 (근거: Dardari et al., IEEE Trans. Commun., 2009)
- r_CP 계산 수식 (dB scale vs linear scale 선택 근거)
- a_FP 계산 수식 (T_w 윈도우 크기 선택 근거)
- Edge case 처리: r_CP = 0/0, a_FP 분모 = 0
- 출력 데이터 형식: [N_positions × 4] table (r_CP, a_FP, label, position_id)

### 3. specs/spec_logistic_model.md
Logistic Regression 학습 및 평가 모듈의 구현 명세:
- 학습 함수: `model = train_logistic(features, labels, params)`
  - features: [N × 2] (r_CP, a_FP)
  - 정규화 방법: z-score (학습 데이터 기준 mean/std 저장)
  - 학습 방법: MATLAB fitglm 또는 mnrfit
  - Cross-validation: Stratified 5-fold (LoS/NLoS 비율 유지)
- 평가 함수: `results = eval_model(model, features, labels)`
  - 출력 metrics: ROC AUC, Accuracy, F1, ECE (Expected Calibration Error)
  - Calibration curve: 10-bin reliability diagram
  - 연산 복잡도 측정: FLOPs 계산 공식 (Logistic: 2 multiply + 1 add + 1 sigmoid = 5 FLOPs)
- 비교 ML 모델 사양:
  - SVM: RBF kernel, fitcsvm, hyperparameter tuning via bayesopt
  - RF: 100 trees, fitcensemble (Method='Bag')
  - DNN: 2 hidden layers [16, 8], ReLU, Adam optimizer
  - 각 모델의 FLOPs 계산 방법 명시
