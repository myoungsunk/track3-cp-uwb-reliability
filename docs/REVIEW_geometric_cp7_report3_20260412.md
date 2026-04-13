# CP7 Geometric 추가 개선 보고서

Date: 2026-04-12

## 핵심 결론

현재 데이터가 가장 강하게 지지하는 것은 `평균 성능이 올랐다`보다 `CP7가 geometric LoS/NLoS ambiguity를 줄였다`는 해석이다. 따라서 논문의 주장 축 자체를 이 방향으로 맞추는 것이 가장 안전하다.

## 1. 가장 먼저 바로잡아야 할 점

### baseline 정의

지금 문안에서 가장 위험한 부분은 full 6-case baseline과 CP7 paired comparison baseline이 같은 축의 비교처럼 읽힐 수 있다는 점이다. 실제로는 다음처럼 다르다.

- full 6-case stage:
  - 16-feature reference baseline
- CP7 comparison:
  - B+C subset에서 5-feature CIR baseline 위에 6개 CP7 feature를 추가한 paired comparison

따라서 다음 표현은 피해야 한다.

- `0.7959에서 0.9139로 직접 향상`

권장 표현은 다음과 같다.

- `full reference는 0.7959`
- `CP7 contribution은 CP7-capable subset에서 별도 평가`

## 2. 핵심 결과 체인

현재 가장 설득력 있는 결과 구조는 다음이다.

- B+C subset 112개
- baseline AUC `0.8498`
- proposed AUC `0.9139`
- `Delta AUC = +0.0641`
- `Delta Brier = -0.0430`
- `McNemar p = 0.0352`
- hard-case `0.4286 -> 0.9286`
- baseline error 26개 중 12개 복구, 새 harm 3개

이 구조는 reviewer 관점에서 `decision boundary가 실제로 보완되었는가`를 가장 직접적으로 보여준다.

## 3. 추가 검증의 의미

독립 검증 보고서 기준으로 수치 재현은 소수점 넷째 자리까지 완전히 일치했고, CV 구현도 정석적으로 판단되었다.

spatial leakage 가능성은 제기되었지만 GroupKFold에서도 결론은 유지되었다.

| 설정 | Baseline | Proposed | Delta AUC |
|---|---:|---:|---:|
| GroupKFold | 0.8313 | 0.8970 | +0.0657 |

즉 `같은 위치를 외운 것 아니냐`는 질문에 대해 반박 재료가 이미 확보된 상태다.

LOSO에서도 양방향 모두 개선된다.

| Train -> Test | Baseline | Proposed |
|---|---:|---:|
| B -> C | 0.7578 | 0.8299 |
| C -> B | 0.8327 | 0.8735 |

따라서 CP7가 특정 scenario에만 맞춘 편향된 feature라는 해석도 약화된다.

## 4. feature 해석 방향

feature 해석은 지금보다 더 보수적으로 써야 한다.

- ablation은 `gamma` 쌍 제거 시 저하가 가장 큼
- permutation에서는 `a_FP_LHCP_rx1`가 1위

이 불일치는 multicollinearity와 interaction으로 설명 가능하므로, 가장 안전한 표현은 다음이다.

> gamma가 main complementary axis를 형성하고, LHCP first-path amplitude가 이를 보강한다.

반면 RHCP 쪽은 특히 `a_FP_RHCP_rx2`의 계수 부호가 B/C 사이에서 뒤집히므로, 본문 main claim보다 supplement나 discussion으로 내리는 편이 적절하다.

## 5. 물리적 해석의 선

물리적 해석은 가능하지만 아직 hypothesis 수준으로만 두는 것이 안전하다.

- tilted tag-anchor setup
- tag 쪽 두 antenna branch
- RHCP/LHCP-resolved port

이 구조를 고려하면 CP7가 단순 CIR energy가 아니라 branch-specific polarization distortion이나 path-dependent conversion을 더 직접 반영했을 가능성은 있다.

하지만 다음 수준은 넘지 않는 것이 좋다.

- `가능한 해석`까지는 가능
- `특정 반사 메커니즘을 직접 식별했다`는 주장은 과장

## 6. LoS 교정 효과

error type 분석에서 다음 변화가 관찰되었다.

- FP: `14 -> 10`
- FN: `12 -> 7`
- rescued 12건 중 8건이 FN 복구

따라서 다음 정도의 discussion은 가능하다.

- `CP7가 특히 LoS를 NLoS로 잘못 보던 샘플을 더 잘 교정한다`

다만 이것도 mechanism proof가 아니라 observed tendency로 두는 편이 적절하다.

## 7. main claim으로 두지 말아야 할 것

다음 항목은 main claim으로 두지 않는 편이 맞다.

- calibration improvement
- strict orthogonality
- dual-RX diversity
- subgroup mechanism analysis

적절한 배치는 discussion 또는 appendix다.

## 8. 최종 권고 문장

지금 보고서의 최종 논의 방향은 다음이 가장 적절하다.

> CP7 channel-resolved feature는 CP7-capable paired subset에서 geometric LoS/NLoS ambiguity를 감소시켰다. 이 효과는 paired AUC/Brier/McNemar 개선, ambiguity band에서의 대폭적 향상, baseline error rescue, GroupKFold 및 LOSO robustness에서 일관되게 지지된다. 다만 이 주장은 full 6-case reference baseline과 구별된 paired subset comparison이라는 전제를 분명히 해야 하며, 물리적 메커니즘 해석은 hypothesis 수준에 머문다.
