# CP7 Geometric 결과 보고서 검토 보고서 2

Date: 2026-04-12

## 검토 범위

- `geometric_story_bundle`
- `cp7_reviewer_diagnostics`
- `cp7_priority_validations`
- `cp7_followup_validations`
- `CP_caseA_4port.csv`
- `CP_caseB_4port.csv`
- `CP_caseC_4port.csv`

## 1. 종합 판단

결론부터 정리하면, 현재 geometric 결과 보고서의 중심 메시지는 타당하다. 다만 논문 본문으로 들어갈 때는 `무엇이 reference baseline인지`와 `무엇이 CP7 paired comparison인지`를 지금보다 더 엄격하게 분리해야 reviewer가 문제를 삼기 어렵다.

현재 가장 설득력 있는 주장은 `평균 성능이 조금 올랐다`가 아니라 `CP7 feature가 geometric ambiguity를 줄였다`는 점이다. 따라서 본문 메인 메시지는 다음 세 축으로 정리하는 것이 가장 강하다.

- same-fold paired comparison에서 AUC, Brier, McNemar가 모두 개선됨
- 개선이 hard-case에 집중됨
- baseline error를 실제로 복구함

## 2. 확인된 핵심 수치

현재 rerun bundle과 일치하는 핵심 수치는 다음과 같다.

| 항목 | 값 |
|---|---:|
| Full 6-case geometric reference baseline AUC | 0.7959 |
| CP7-capable subset size | 112 |
| CP7-capable subset LoS/NLoS | 56 / 56 |
| Paired 5-feature subset baseline AUC | 0.8498 |
| Proposed AUC | 0.9139 |
| Delta AUC | +0.0641 |
| Delta Brier | -0.0430 |
| Exact McNemar p | 0.0352 |
| Hard-case AUC | 0.4286 -> 0.9286 |
| Baseline errors | 26 |
| Rescued | 12 |
| Harmed | 3 |
| Rescue rate | 46.2% |
| Harm rate | 3.5% |
| Join success | 112 / 112 |
| Unmatched | 0 |
| Label mismatch | 0 |

Hard-case 내부에서도 해석력이 좋다.

- hard-case 17개 중 baseline error는 9개
- proposed는 그중 6개를 복구
- hard-case 내부 신규 harm은 0개

이것은 `ambiguous subset에서 CP7가 실제 decision을 뒤집어 준다`는 가장 직관적인 증거로 볼 수 있다.

## 3. 가장 중요한 수정점

### 3.1 baseline 정의를 반드시 분리해야 함

현재 서술만 보면 full 6-case baseline과 CP7 reviewer baseline이 같은 baseline처럼 읽힐 수 있다. 그러나 실제 구성은 다르다.

- full 6-case stage:
  - 원래의 16-feature baseline 사용
  - `r_CP`, `a_FP`, 여러 CIR descriptor 포함
- CP7 reviewer comparison:
  - `fp_energy_db`
  - `skewness_pdp`
  - `kurtosis_pdp`
  - `mean_excess_delay_ns`
  - `rms_delay_spread_ns`
  - 위 5-feature baseline 위에 6개 CP7 feature 추가

따라서 본문에서는 반드시 이름을 나눠 써야 한다.

- `full 6-case reference baseline`
- `paired 5-feature subset baseline`

피해야 할 표현:

- `0.7959에서 0.9139로 직접 좋아졌다`

권장 표현:

- `full reference 성능은 0.7959였다`
- `CP7 contribution은 CP7-capable subset에서 별도 paired comparison으로 평가했다`

### 3.2 source of truth를 단일화해야 함

bundle 안에는 서로 다른 시점의 산출물이 섞여 있다. 특히 `cp7_abc_report.md`에는 `0.9072` 같은 이전 숫자가 남아 있다. 현재 본문에는 2026-04-10 rerun의 다음 결과만 source of truth로 쓰는 편이 안전하다.

- `geometric_story_bundle`
- reviewer rerun
- priority rerun
- follow-up rerun

`03_reviewer_geometric` 아래에 material helper output이 같이 들어 있는 점은 재현성 노트나 appendix에 한 줄 남기면 충분하다. 본문 결과 서술은 geometric output만 인용하는 것이 안전하다.

## 4. metric 조합과 서술 방식 평가

현재 metric 조합 자체는 적절하다.

- ROC AUC: prediction score 기반 분리 성능 요약
- Brier score loss: 예측확률과 실제 outcome 사이 mean squared difference
- exact McNemar: paired 2x2 decision change 비교에 적합

참고:

- [roc_auc_score](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.roc_auc_score.html?utm_source=chatgpt.com)
- [brier_score_loss](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.brier_score_loss.html)

다만 Brier 감소를 곧바로 `calibration improvement`라고 단정하는 표현은 피하는 편이 낫다. Brier는 calibration과 refinement가 함께 섞인 양이므로, 다음과 같은 표현이 더 방어적이다.

- `probabilistic prediction quality improved`
- `probability error decreased`

## 5. strongest claim 정리

현재 보고서에서 가장 설득력 있는 주장은 `geometric ambiguity를 줄였다`는 것이다. reviewer는 보통 다음 세 가지를 함께 본다.

- AUC
- paired decision change
- hard-case behavior

따라서 메인 메시지는 다음 구조가 가장 강하다.

1. same-fold paired comparison에서 AUC, Brier, McNemar가 모두 개선되었다.
2. 개선이 hard-case에 집중되었다.
3. baseline error를 실제로 복구했다.

특히 rescue 관점은 매우 좋다.

- baseline error 26개 중 12개 복구
- baseline이 맞췄던 86개 중 새 harm은 3개
- rescue rate 46.2%
- harm rate 3.5%

## 6. hard-case 결과 해석 가이드

hard-case AUC가 baseline에서 0.4286으로 0.5 아래라는 점 자체는 치명적 문제가 아니다. 이 subset은 baseline의 uncertain-score band `[0.4, 0.6]`로 조건부 선택된 샘플이기 때문이다. 따라서 이는 전체 데이터의 global ranking problem이 아니라 conditional ranking problem으로 설명하는 것이 맞다.

권장 명칭:

- `conditional hard-case analysis`
- `ambiguity band analysis`

권장 배치:

- headline은 overall B+C result
- hard-case는 ambiguity 해석을 뒷받침하는 supporting evidence

## 7. feature 역할 분담에 대한 권장 표현

현재 방향은 맞지만, `직교성` 표현은 조금 더 조심스럽게 쓰는 편이 좋다. correlation 분석이 직접 보여주는 것은 strict orthogonality가 아니라 다음에 가깝다.

- `low redundancy`
- `complementarity`

현재 데이터 기준에서 가장 방어적인 정리는 다음과 같다.

- `gamma_CP_rx2`는 기존 top baseline feature 대비 평균 absolute Spearman이 가장 낮아 가장 강한 complementary candidate이다.
- `gamma_CP_rx1`는 부분적으로 독립적이지만 완전히 새로운 축이라고 말하기는 어렵다.
- `a_FP_*` 계열은 기존 energy/shape descriptor와의 상관이 더 높아 보조 축 또는 channel-resolved refinement에 가깝다.

## 8. feature importance 해석 통합

분석 방법마다 ranking은 조금 다르다.

- logistic permutation:
  - `a_FP_LHCP_rx1` 1위
  - `gamma_CP_rx2` 2위
- RF permutation:
  - `gamma_CP_rx2` 1위
- 20-repeat ablation, B+C 평균:
  - full proposed `0.9059`
  - `drop_gamma_both = 0.8787`
  - `drop_lhcp_pair = 0.8893`
  - `drop_rhcp_pair = 0.9040`

따라서 가장 안전한 표현은 다음이다.

> gamma가 주된 complementary axis를 이루고, LHCP 기반 first-path amplitude가 이를 보강하며, RHCP contribution은 상대적으로 약하고 일관성이 낮다.

이 문장은 correlation, permutation, ablation을 함께 만족한다.

## 9. reviewer 방어용 보조 논리

reviewer가 `5-feature baseline을 일부러 약하게 잡은 것 아니냐`라고 물을 가능성은 있다. 여기에 대한 보조 논리는 다음과 같다.

- full 6-case OOF score를 `CP_caseB/C`로 post-hoc 제한했을 때 AUC가 약 `0.847`
- paired 5-feature subset baseline은 `0.8498`

즉 CP7 gain이 baseline 약화에만 의존해 생긴 것으로 보이지는 않는다. 다만 이 숫자는 공식 rerun table이 아니라 post-hoc subset readout이므로, 본문 메인 숫자보다는 rebuttal 또는 supplement 보조 근거로 두는 편이 더 안전하다.

## 10. 물리적 discussion에 대한 권고

setup을 반영한 물리적 해석은 가능하지만, 이 단계에서는 가설 수준으로만 유지해야 한다.

- tilted tag-anchor 구조
- tag 쪽 두 개의 antenna branch
- RHCP/LHCP-resolved port

이 점을 고려하면 channel-resolved CP7 feature는 단순 scalar CIR energy가 아니라 branch별 polarization imbalance 또는 path-dependent polarization conversion을 더 직접적으로 반영했을 가능성이 있다.

관찰 패턴:

- rescued NLoS 샘플:
  - `gamma_CP_rx2` 높음
  - LHCP amplitude 낮음
- rescued LoS 샘플:
  - `gamma_CP_rx2` 낮거나 음수에 가까움
  - LHCP amplitude 상대적으로 높음
- B+C proposed coefficient:
  - `gamma_CP_rx1` positive
  - `gamma_CP_rx2` negative
  - `a_FP_LHCP_rx1` 가장 큰 positive coefficient
- harmed 3개:
  - 모두 LoS
  - `gamma_CP_rx2`가 유난히 크게 나타나 obstruction 쪽 과보정 흔적

따라서 물리적 discussion에서는 다음 정도까지는 가능하다.

- `CP7가 branch-specific polarization distortion pattern을 반영해 ambiguity를 푼다`

하지만 다음은 과장이다.

- `특정 반사 메커니즘을 직접 식별했다`

## 11. scenario별 차이에 대한 권고

이득은 B와 C 둘 다에서 보이지만 더 강한 쪽은 B다.

- case-wise rescue:
  - B: `7 rescue / 1 harm`
  - C: `5 rescue / 2 harm`

환경 차이:

- B:
  - glass partition
  - metal cabinet
  - wood desk
- C:
  - glass 2개
  - metal 2개
  - wood 4개

권장 문장:

> CP7 gain is larger in the sparser, more structured regime and becomes diluted in dense clutter.

다만 이것 역시 mechanism proof가 아니라 observed tendency로만 써야 한다.

## 12. main claim으로 두지 말아야 할 것

다음 항목은 본문 main contribution으로 두지 않는 편이 맞다.

- dual-RX diversity
- subgroup mechanism analysis
- universal gain for both geometric and material targets

근거:

- dual-RX:
  - best single 대비 Delta AUC `+0.0099`
  - bootstrap CI가 0 포함
- subgroup mechanism:
  - underpowered subset 다수

따라서 둘 다 discussion 보조 해석에 두는 것이 적절하다.

## 13. 추가하면 좋은 robustness

현재 draft에 추가하면 좋은 robustness는 spatial CV다.

| 설정 | Baseline | Proposed |
|---|---:|---:|
| fixed-seed paired CV | 0.8498 | 0.9139 |
| 20-repeat mean | 0.8358 | 0.9059 |
| spatial CV | 0.8406 | 0.9066 |

절대값은 조금 달라도 방향은 세 설정에서 일관된다. reviewer가 `position memorization 아니냐`를 물을 경우 가장 강한 답이 된다.

## 14. 본문 문단 구조 권고

현재 단계에서 가장 우선해야 할 수정은 본문 첫 두 문단을 다음 구조로 재정렬하는 것이다.

> 전체 6-case geometric rerun에서 original reference baseline의 OOF AUC는 0.7959였다. 그러나 channel-resolved CP7 feature는 CP_caseB와 CP_caseC의 CP measurements에 대해서만 계산 가능하므로, 그 기여도는 CP7-capable subset에서 별도의 paired comparison으로 평가하였다. 이 subset은 총 112개 샘플로 구성되었으며 LoS/NLoS가 56/56으로 균형되어 있었다. 동일한 cross-validation fold를 유지한 상태에서 5-feature CIR baseline의 AUC는 0.8498이었고, 여기에 6개의 CP7 feature를 추가한 proposed model은 0.9139를 기록하였다. 동시에 Brier score는 0.0430 감소하였고, exact McNemar test는 p=0.0352를 보여, 성능 향상이 단순한 score fluctuation이 아니라 paired decision quality의 개선과 연결됨을 확인하였다.

> 이 이득은 특히 baseline이 애매하게 판단한 샘플에서 집중되었다. baseline score가 [0.4, 0.6]에 위치한 ambiguity band에서 AUC는 0.4286에서 0.9286으로 상승하였다. 또한 baseline이 오분류한 26개 샘플 중 12개는 proposed model이 올바르게 복구한 반면, baseline이 맞췄으나 proposed model이 새롭게 틀린 샘플은 3개에 그쳤다. Correlation, permutation, and ablation analyses further indicate that the gain is mainly associated with channel-resolved gamma information, with LHCP first-path amplitude features providing additional support. These findings support the interpretation that CP7 features reduce geometric ambiguity by providing complementary polarization-resolved information beyond conventional CIR descriptors.
