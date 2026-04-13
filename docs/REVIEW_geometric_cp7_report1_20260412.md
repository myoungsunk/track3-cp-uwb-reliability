# CP7 Feature 결과 보고서 독립 검증 및 평가 보고서 1

Date: 2026-04-12

## 검토 범위

- 업로드된 결과 데이터
- 업로드된 코드
- CP7 geometric 결과 보고서 전반

## 1. 코드 무결성 검토

### 1.1 수치 재현

OOF prediction CSV를 Python으로 독립 검증한 결과, 보고서의 모든 핵심 수치가 소수점 4자리까지 정확히 재현되었다.

| 지표 | 보고서 | 독립 재현 | 일치 |
|---|---:|---:|---|
| Baseline AUC (B+C) | 0.8498 | 0.8498 | PASS |
| Proposed AUC (B+C) | 0.9139 | 0.9139 | PASS |
| Delta AUC | +0.0641 | +0.0641 | PASS |
| Delta Brier | -0.0430 | -0.0430 | PASS |
| McNemar b/c | 3/12 | 3/12 | PASS |
| McNemar p | 0.0352 | 0.0352 | PASS |
| Hard-case AUC (baseline) | 0.4286 | 0.4286 | PASS |
| Hard-case AUC (proposed) | 0.9286 | 0.9286 | PASS |
| Rescue/Harm | 12/3 | 12/3 | PASS |

판정:

- 수치 재현은 완전히 일치한다.
- 핵심 수치 무결성에는 결정적 결함이 없다.

### 1.2 CV 구현 검토

검토 결과 다음 요소들은 정석적 구현으로 판단되었다.

- `build_cv_plan -> cvpartition(labels, 'KFold', folds)` 기반 stratified split
- `rng(seed)` 고정
- fold별 normalization: train fit 후 test transform
- class-weight balanced
- ridge `lambda = 1e-2`

판정:

- CV 구현은 건전하다.

### 1.3 잠재적 문제: Spatial Leakage

가장 중요한 잠재 이슈는 공간 위치 교차 오염 가능성이다.

- Case B와 Case C는 동일한 56개 `(x, y)` 좌표를 공유한다.
- 현재 stratified k-fold는 scenario를 인지하지 않으므로, 같은 물리적 위치가 서로 다른 fold에 배정될 수 있다.
- 위치 간 CP7 feature 상관이 높다.
  - `gamma_CP_rx2` cross-case `r = 0.70`
  - `a_FP_LHCP_rx2` cross-case `r = 0.72`

그러나 GroupKFold 재실험 결과는 다음과 같다.

| 방법 | Baseline AUC | Proposed AUC | Delta AUC |
|---|---:|---:|---:|
| 원본 standard CV | 0.8498 | 0.9139 | +0.0641 |
| GroupKFold | 0.8313 | 0.8970 | +0.0657 |

해석:

- leakage 가능성은 이론적으로 존재한다.
- 하지만 baseline feature 역시 동일 leakage를 공유하므로 delta 자체는 편향되지 않는다.
- GroupKFold에서 결론은 유지되며, 오히려 `Delta AUC`가 미세하게 상승했다.

권고:

- 논문 supplementary에 GroupKFold 결과를 병기하면 reviewer 방어력이 크게 높아진다.

## 2. 결론의 논리적 타당성 평가

### 2.1 강점

- Subset 재정의 논리인 `B+C에서만 비교`는 fair comparison 원칙에 부합한다.
- Hard-case 분석은 단순 평균 AUC 상승을 넘어선 mechanism-level 근거를 제공한다.
- Rescue 분석 `12 복구 vs 3 악화`는 decision boundary 보완을 구체적으로 보여준다.
- Ablation에서 `gamma` 제거 시 최대 저하, `LHCP` 쌍 제거 시 차순위 저하가 나타나 직교성 분석 및 역할 분담 해석과 대체로 일관된다.

### 2.2 주의가 필요한 점

#### 1) Permutation importance와 ablation의 불일치

- Logistic permutation에서는 `a_FP_LHCP_rx1`가 1위이고, `gamma_CP_rx2`가 2위이다.
- 반면 ablation에서는 `gamma` 쌍 제거가 최대 영향을 보인다.

해석:

- 이는 multicollinearity와 feature interaction의 영향으로 볼 수 있다.
- 따라서 `gamma가 주된 complementary axis`라고 단정하기보다, `gamma와 LHCP가 complementary pair로 공동 기여한다`고 쓰는 편이 더 안전하다.

#### 2) Case 간 label 비대칭

- Case B는 LoS-dominant `35:21`
- Case C는 NLoS-dominant `21:35`
- Rescue 분포는 `B=7`, `C=5`
- class별 복구는 `LoS=8`, `NLoS=4`

해석:

- CP7가 LoS 판별에 더 효과적일 가능성이 있다.
- 현재 보고서에는 이 분석이 빠져 있으므로 보완 가치가 있다.

#### 3) 작은 표본

- 전체 `n = 112`
- hard-case `n = 17`

해석:

- McNemar `p = 0.035`는 통계적으로 유의하지만, 이를 곧바로 구조적 일반화로 확장하는 표현은 조심해야 한다.
- effect size와 confidence interval 중심으로 기술하는 편이 더 설득력 있다.

## 3. 추가 검증 제안 및 가치 극대화 방향

### 3.1 반드시 추가할 것

#### 1) GroupKFold 결과 병기

- 이미 검증 결과 `Delta AUC` 유지가 확인되었다.
- `spatial-position-aware CV에서도 동일 결론`이라는 문장을 넣을 수 있다.

#### 2) Per-case separate CV 해석 강화

- B only: `+0.033`
- C only: `+0.088`

권고:

- `다른 NLoS 환경에서도 일관되게 개선`된다는 해석을 본문에 적극 활용할 필요가 있다.

#### 3) Feature importance 표현 통합

현재는 reviewer가 다음처럼 혼동할 수 있다.

- permutation에서는 `LHCP_rx1`이 1위
- ablation에서는 `gamma`가 핵심

권고 문장:

> Single-feature contribution is largest for `a_FP_LHCP_rx1`, while the `gamma` pair provides the most independent axis relative to the baseline and therefore functions as the main complementary information source.

### 3.2 가치를 높일 전략적 제안

#### 4) Calibration plot 추가

- reliability diagram을 제시하면 Brier 개선을 시각적으로 보여줄 수 있다.
- Track 1의 confidence-based pruning 또는 beam management narrative와 직접 연결된다.

#### 5) Leave-one-scenario-out validation 추가

- Train on B -> Test on C
- Train on C -> Test on B

이 검증은 cross-environment generalization 근거가 된다.

#### 6) 결론 문구 강도 조정

현재보다 더 방어적인 표현이 적절하다.

- `structurally recover` -> `consistent pattern of recovery`
- `gamma가 주된 축` -> `gamma와 LHCP가 공동으로 주된 상보적 정보 형성`

## 4. 추가 독립 검증 결과

### 4.1 LOSO validation

교차 환경 일반화 검증 결과는 다음과 같다.

| Train -> Test | Baseline AUC | Proposed AUC | Delta AUC |
|---|---:|---:|---:|
| B -> C | 0.7578 | 0.8299 | +0.0721 |
| C -> B | 0.8327 | 0.8735 | +0.0408 |

해석:

- 두 방향 모두에서 CP7가 baseline을 개선한다.
- 특히 `B -> C`에서 개선폭이 더 크다.
- 이는 CP7 정보가 특정 scenario에 overfitting된 것이 아님을 시사하는 강한 근거다.

### 4.2 Calibration 분석

| 모델 | Brier | ECE (5-bin) |
|---|---:|---:|
| Baseline | 0.1556 | 0.0427 |
| Proposed | 0.1126 | 0.0409 |

해석:

- Proposed는 discrimination뿐 아니라 calibration도 소폭 개선한다.
- 다만 일부 mid-range bin에서는 calibration gap이 증가하는 구간이 있어, calibration 개선을 핵심 주장으로 쓰기보다는 보조 근거로 제한하는 것이 안전하다.

### 4.3 Error type 분석

| 항목 | Baseline | Proposed | 감소 |
|---|---:|---:|---:|
| FP | 14 | 10 | -4 |
| FN | 12 | 7 | -5 |

Rescued 12건 구성:

- `FN -> 정답` 8건
- `FP -> 정답` 4건

해석:

- CP7는 `LoS를 NLoS로 오판하는 경우`를 더 많이 교정한다.
- 이는 LoS에서 polarization purity가 더 잘 보존된다는 물리적 설명과 연결될 수 있다.

### 4.4 계수 부호 안정성

| CP7 Feature | Case B | Case C | B+C | 부호 일관 |
|---|---:|---:|---:|---|
| gamma_CP_rx1 | +0.67 | +0.89 | +0.53 | PASS |
| gamma_CP_rx2 | -0.52 | -1.02 | -0.81 | PASS |
| a_FP_LHCP_rx1 | +1.07 | +1.18 | +1.00 | PASS |
| a_FP_LHCP_rx2 | +0.79 | +0.31 | +0.33 | PASS |
| a_FP_RHCP_rx1 | -0.26 | -1.11 | -0.64 | PASS |
| a_FP_RHCP_rx2 | -0.83 | +1.03 | +0.09 | FLIP |

핵심 발견:

- `a_FP_RHCP_rx2`만 부호가 불안정하다.
- 이는 B+C 결합 시 계수가 거의 0에 가깝다는 점과도 일치한다.
- 이 feature를 제외한 5-feature 모델도 검토 가치가 있다.

### 4.5 VIF

| Feature group | VIF 범위 | 판정 |
|---|---:|---|
| Baseline features | 6.5-17.5 | HIGH |
| CP7 features | 2.4-4.5 | GOOD |

해석:

- baseline 내부 공선성은 높다.
- CP7 feature는 baseline과 비교적 독립적인 축을 이룬다.
- CP7 내부 redundancy는 상대적으로 낮다.

## 5. 종합 판정

### 5.1 안전하게 주장할 수 있는 것

1. CP7 feature는 geometric LoS/NLoS 분류를 유의하게 개선한다.
2. 개선은 hard-case에서 특히 강하게 나타난다.
3. `gamma`와 `LHCP` 계열은 안정적 기여를 한다.

이를 지지하는 독립 검증 경로:

- standard CV
- GroupKFold
- LOSO B -> C
- LOSO C -> B

### 5.2 표현을 완화해야 하는 것

- `구조적 복구` -> `일관된 복구 패턴`
- `gamma가 주된 축` -> `gamma와 LHCP가 공동으로 주된 상보적 정보 형성`
- `a_FP_RHCP_rx2`는 불안정성이 있음을 명시

### 5.3 추가하면 가치가 큰 요소

- GroupKFold 결과 1줄
- LOSO 결과
- FN/FP 복구 방향성
- 계수 부호 안정성 표
- Calibration plot

## 6. 전략적 가치 극대화 방향

현재 핵심 주장인 `CP7 feature가 geometric ambiguity를 감소시킨다`는 데이터에 의해 충분히 지지된다. 코드에 결정적 결함은 없고, 수치는 완전히 재현되며, 추가 검증에서도 결론이 유지된다.

권장 narrative 재구성 순서는 다음과 같다.

1. CP7의 물리적 동기
2. LOSO를 통한 일반화 가능성
3. Hard-case에서의 개선
4. Overall metric
5. Feature 역할 분담과 안정성

이 순서의 장점은 다음과 같다.

- 왜 도움이 되는가
- 실제로 도움이 되는가
- 어디서 도움이 되는가
- 얼마나 도움이 되는가
- 어떤 feature가 도움이 되는가

즉, reviewer 관점에서 더 자연스러운 인과적 스토리라인을 형성할 수 있다.

## 최종 결론

- 코드 무결성: 결정적 결함 없음
- 수치 재현: 소수점 4자리까지 완전 일치
- Spatial leakage: 존재 가능성은 있으나 결론에 영향 없음
- 추가 검증: GroupKFold와 LOSO 모두 결론 지지
- 최종 주장: `CP7가 geometric ambiguity를 감소시킨다`는 핵심 방향은 견실함
- 단, 표현 강도는 약간 완화하는 것이 reviewer 방어에 유리함
