# CP7 Geometric 결과 수렴본 + 추가 개선 반영

Date: 2026-04-12

## 검토 대상 보고서

| 구분 | 문서 | 성격 |
|---|---|---|
| 보고서 1 | `docs/REVIEW_geometric_cp7_report1_20260412.md` | 코드 무결성, 수치 재현, leakage, LOSO, calibration, 계수 안정성 중심 독립 검증 |
| 보고서 2 | `docs/REVIEW_geometric_cp7_report2_20260412.md` | 논문 본문 framing, baseline 정의, source of truth, claim scope 중심 평가 |
| 추가 개선 | `docs/REVIEW_geometric_cp7_report3_20260412.md` | 주장 축 전환, baseline 분리 재강조, robustness와 LoS 교정 효과 강화 |

교차 확인 산출물:

- `los_nlos_baseline_project/results/geometric_story_bundle/06_report/geometric_cp7_story_report.md`
- `los_nlos_baseline_project/results/cp7_reviewer_diagnostics/diagnostics_summary.md`
- `los_nlos_baseline_project/results/geometric_story_bundle/04_priority_validations/cp7_priority_validation_report.md`
- `los_nlos_baseline_project/results/geometric_story_bundle/05_followup_validations/cp7_followup_validation_report.md`
- `los_nlos_baseline_project/results/cp7_reviewer_diagnostics/cp7_abc_report.md`

## 1. 2가지 보고서 수렴

두 보고서는 서로 다른 층위를 검토했지만 결론은 같은 방향으로 수렴한다.

- 보고서 1은 `결과가 실제로 맞는지`, `코드와 검증 절차가 건전한지`, `추가 검증에서도 결론이 유지되는지`를 본다.
- 보고서 2는 `이 결과를 논문 본문에서 어떻게 써야 reviewer 공격을 줄일 수 있는지`를 본다.

수렴 결론은 다음과 같다.

1. CP7 geometric 결과의 중심 메시지는 유지 가능하다.
2. main claim은 `평균 성능 향상`보다 `geometric ambiguity reduction`에 두는 편이 더 강하다.
3. full baseline과 paired subset baseline을 구분하지 않으면 reviewer가 가장 먼저 지적할 가능성이 높다.
4. hard-case와 rescue는 본문 중심 증거로 올릴 가치가 크다.
5. robustness 문단으로 spatial CV, GroupKFold, LOSO를 묶어 제시하면 reviewer 방어력이 크게 올라간다.
6. LoS 교정 효과와 baseline redundancy는 discussion/supplement에서 방어 논리로 적극 활용할 수 있다.

## 2. 공통 지적

두 보고서가 공통으로 지적한 사항은 다음과 같다.

| 공통 지적 | 정리 |
|---|---|
| baseline 정의 혼동 가능성 | full baseline과 paired subset baseline을 반드시 분리 표기해야 함 |
| main claim의 초점 | CP7가 geometric ambiguity를 줄인다는 방향으로 고정하는 것이 적절 |
| hard-case와 rescue의 중요성 | 평균 AUC보다 reviewer 설득력이 높으므로 결과 본문에서 강조 필요 |
| 과도한 해석 위험 | orthogonality, calibration, mechanism 관련 표현은 완화 필요 |
| robustness 필요성 | spatial CV, GroupKFold, LOSO를 한 묶음으로 제시하는 편이 방어력이 높음 |

## 3. 개별 지적

### 3.1 보고서 1 개별 지적

R1-1. 수치 재현은 소수점 4자리까지 완전히 일치한다.

R1-2. CV 구현은 stratified split, seed 고정, fold별 normalization, ridge 설정 측면에서 건전하다.

R1-3. spatial leakage 가능성은 존재한다. 다만 GroupKFold에서도 Delta AUC가 유지되어 결론 자체는 흔들리지 않는다.

R1-4. LOSO에서 B->C, C->B 모두 개선이 나타나 scenario-specific overfitting 해석을 약화시킨다.

R1-5. calibration은 일부 개선되지만, 이를 main claim으로 쓰기에는 근거가 약하다.

R1-6. rescued 12건 중 FN 복구가 FP 복구보다 많아, LoS 쪽 교정 효과를 시사한다.

R1-7. `a_FP_RHCP_rx2`는 B/C에서 계수 부호가 반전되어 안정성이 약하다.

R1-8. baseline 내부 VIF는 높고 CP7 내부 VIF는 상대적으로 낮아, baseline 쪽 공선성이 더 문제다.

R1-9. permutation importance와 ablation이 다르게 보이므로 feature 역할 설명을 더 조심스럽게 써야 한다.

### 3.2 보고서 2 개별 지적

R2-1. full 6-case reference baseline과 CP7 paired subset baseline은 본문에서 반드시 다른 이름으로 써야 한다.

R2-2. `0.7959 -> 0.9139`를 직접 연결해 쓰면 안 된다. 비교축이 다르기 때문이다.

R2-3. source of truth는 2026-04-10 rerun bundle과 그에 맞는 reviewer/priority/follow-up output으로 제한해야 한다.

R2-4. `cp7_abc_report.md` 같은 구버전 수치는 본문 인용 대상이 아니다.

R2-5. Brier 감소를 calibration improvement라고 단정하지 말고, probability quality 개선으로 쓰는 편이 안전하다.

R2-6. 가장 설득력 있는 메인 메시지는 `geometric ambiguity reduction`이다.

R2-7. hard-case는 conditional subset이라는 설명과 함께 supporting evidence로 두는 것이 적절하다.

R2-8. `strict orthogonality`보다 `low redundancy` 또는 `complementarity`가 더 적절하다.

R2-9. feature 역할은 `gamma main + LHCP support + RHCP weak/inconsistent` 정도로 정리하는 것이 가장 안전하다.

R2-10. `5-feature baseline을 일부러 약하게 잡은 것 아니냐`는 reviewer 질문에는 post-hoc subset readout `~0.847`을 보조 근거로만 쓰는 것이 좋다.

R2-11. branch-specific polarization distortion 해석은 hypothesis 수준 discussion으로 제한해야 한다.

R2-12. scenario B/C 차이는 observed tendency로만 쓰고 mechanism proof처럼 쓰지 말아야 한다.

R2-13. dual-RX diversity와 subgroup mechanism은 main contribution으로 두지 않는 편이 맞다.

R2-14. spatial CV `0.8406 -> 0.9066`은 position memorization 반박에 매우 유용하므로 robustness에 넣는 것이 좋다.

### 3.3 추가 개선 보고서 개별 지적

R3-1. 주장 축을 `평균 성능 향상`에서 `geometric ambiguity reduction`으로 명시적으로 전환해야 한다.

R3-2. baseline 정의 문제는 여전히 가장 위험한 reviewer 공격 포인트이므로, full reference와 paired subset comparison을 본문 첫 문단에서 분리 선언해야 한다.

R3-3. 핵심 결과 체인은 `AUC + Brier + McNemar + hard-case + rescue` 순으로 제시하는 것이 가장 설득력 있다.

R3-4. GroupKFold는 leakage 반박용, LOSO는 scenario generalization 반박용으로 본문 또는 robustness subsection에 반드시 반영할 가치가 있다.

R3-5. feature 해석은 `gamma main complementary axis + LHCP support`까지가 안전하고, RHCP 쪽은 main claim에서 내리는 편이 적절하다.

R3-6. 물리적 해석은 hypothesis 수준까지만 허용해야 하며 mechanism proof처럼 쓰면 안 된다.

R3-7. FN 복구가 FP 복구보다 많다는 점은 LoS 교정 효과를 시사하는 discussion 자원이다.

R3-8. calibration improvement, strict orthogonality, dual-RX diversity, subgroup mechanism analysis는 main claim에서 제외해야 한다.

## 4. 각 지적 별 검토 후 수용 여부 평가

| ID | 지적 사항 | 검토 | 수용 여부 | 반영 방향 |
|---|---|---|---|---|
| R1-1 | 수치 재현 완전 일치 | 핵심 숫자의 신뢰도 근거로 매우 중요 | 수용 | 통합 보고서 서두에 무결성 근거로 반영 |
| R1-2 | CV 구현 건전 | 구현 결함이 main issue가 아님을 보여줌 | 수용 | 방법론 신뢰성 설명에 반영 |
| R1-3 | spatial leakage 가능성 + GroupKFold 유지 | reviewer 방어에 매우 유용 | 수용 | robustness 문단과 supplement에 반영 |
| R1-4 | LOSO 양방향 개선 | cross-environment generalization 근거 | 수용 | robustness 문단에 반영 |
| R1-5 | calibration은 main claim 아님 | 현재 데이터 강도로는 과도한 주장 위험 | 수용 | calibration은 보조 근거로만 유지 |
| R1-6 | FN 복구가 더 많음 | discussion의 핵심 고리로 가치가 큼 | 수용 | discussion 첫 문장 수준의 hypothesis 연결 문장으로 반영 |
| R1-7 | `a_FP_RHCP_rx2` 부호 불안정 | feature 안정성 논의에 필요 | 수용 | discussion 또는 supplement 표에 반영 |
| R1-8 | baseline 내부 공선성 높음 | 약한 baseline 공격에 대한 선제 반박 근거 | 수용 | supplement rebuttal 문단에 명시 반영 |
| R1-9 | permutation과 ablation 불일치 | feature 역할 문장 정교화 필요 | 수용 | 단일 1위 주장 대신 조합형 설명 사용 |
| R2-1 | baseline 이름 분리 | 가장 중요한 reviewer 방어 포인트 | 수용 | 본문 첫 문단과 표 제목 수정 |
| R2-2 | `0.7959 -> 0.9139` 직접 연결 금지 | 다른 비교축이므로 직접 연결은 부정확 | 수용 | 두 단계 서술로 분리 |
| R2-3 | source of truth 제한 | 구버전 숫자 혼재 방지 | 수용 | rerun bundle만 공식 인용 |
| R2-4 | `cp7_abc_report.md` 본문 인용 금지 | legacy output 관리 필요 | 수용 | archive 취급, 본문 제외 |
| R2-5 | Brier 해석 완화 | 과장 방지 | 수용 | `probability error decreased`로 수정 |
| R2-6 | main message를 ambiguity reduction으로 | 현재 증거 구조와 가장 잘 맞음 | 수용 | 결과 절 headline 수정 |
| R2-7 | hard-case는 supporting evidence | 표본 수가 작아 headline으로는 과함 | 수용 | overall 다음 supporting evidence로 배치 |
| R2-8 | orthogonality 용어 완화 | reviewer 공격 면적 감소 | 수용 | `complementarity/low redundancy`로 변경 |
| R2-9 | gamma/LHCP/RHCP 역할 문장 정리 | 여러 분석을 동시에 만족하는 안전한 표현 | 수용 | 본문 해석 문장으로 채택 |
| R2-10 | post-hoc 0.847은 보조 근거만 | rebuttal에는 좋지만 본문 main number는 아님 | 부분 수용 | supplement 또는 rebuttal용 메모 유지 |
| R2-11 | branch-specific 해석은 hypothesis 수준 | 직접 입증은 아직 부족 | 수용 | discussion에 제한적으로 사용 |
| R2-12 | B/C 차이는 observed tendency로만 | mechanism proof 과장 방지 | 수용 | discussion 표현 제한 |
| R2-13 | dual-RX/subgroup은 main claim 제외 | 현재 근거 강도 부족 | 수용 | appendix/discussion 이동 |
| R2-14 | spatial CV 수치 반영 | memorization 반박에 가장 직접적 | 수용 | robustness 문단 추가 |
| R3-1 | 주장 축을 ambiguity reduction으로 전환 | 세 보고서가 모두 이 방향으로 수렴 | 수용 | 결과 절 headline과 결론 문장 교체 |
| R3-2 | baseline 정의를 첫 문단에서 선제 분리 | reviewer가 가장 먼저 물을 포인트 | 수용 | 본문 첫 2문장 구조 수정 |
| R3-3 | 핵심 결과 체인을 AUC/Brier/McNemar -> hard-case -> rescue 순으로 | reviewer 설득 순서상 가장 적절 | 수용 | 결과 절 문단 순서 재배치 |
| R3-4 | GroupKFold/LOSO를 robustness로 반영 | leakage와 generalization 모두 방어 가능 | 수용 | robustness subsection 추가 |
| R3-5 | gamma main + LHCP support, RHCP는 내리기 | 분석 결과를 가장 무리 없이 포괄 | 수용 | feature 해석 문장 교체 |
| R3-6 | 물리적 해석은 hypothesis 수준 유지 | 과장 방지 | 수용 | discussion 문장 완화 |
| R3-7 | FN 복구 방향성 활용 | LoS 교정 효과를 설명하는 고리 | 수용 | discussion 첫 문장 후보로 반영 |
| R3-8 | calibration/strict orthogonality/dual-RX/subgroup은 main claim 제외 | 증거 강도 대비 과함 | 수용 | discussion/appendix로 이동 |

## 5. 본문 수정 우선순위 지도

### Tier 1: 즉시 수정

이 항목들은 reviewer가 가장 먼저 지적할 가능성이 높다.

- R2-1, R2-2:
  - baseline 이름 분리
  - `0.7959 -> 0.9139` 직접 연결 제거
- R2-6:
  - main claim을 `ambiguity reduction`으로 고정
- R2-3, R2-4:
  - source of truth 단일화
  - `cp7_abc_report.md` archive 처리
- R3-2:
  - 본문 첫 문단에서 full reference와 paired comparison을 구조적으로 분리

### Tier 2: 본문 반영 필요

이 항목들은 reviewer 2차 공격을 방어하는 데 중요하다.

- R2-14 + R1-3 + R1-4:
  - spatial CV
  - GroupKFold
  - LOSO
  - 위 세 개를 하나의 robustness 문단으로 묶어 제시
- R3-3:
  - 결과 제시 순서를 `overall paired metrics -> hard-case -> rescue`로 재배치
- R2-8, R2-9:
  - feature 역할 문장을 `gamma main + LHCP support + RHCP weak/inconsistent` 형식으로 교체
- R2-7:
  - hard-case를 `conditional subset`으로 명시하고 supporting evidence로 재배치

### Tier 3: Supplement / Discussion

- R1-6:
  - FN 복구 방향성
- R1-7:
  - `a_FP_RHCP_rx2` 불안정성
- R1-8:
  - baseline VIF
- R2-11, R2-12, R2-13:
  - branch-specific 해석
  - B/C 차이
  - dual-RX / subgroup mechanism
- R3-6, R3-7, R3-8:
  - 물리적 해석 완화
  - LoS 교정 효과
  - main claim에서 내려야 할 항목 정리

## 6. 아직 남아 있는 residual risk

현재 synthesis에 없었던 reviewer 질문 하나는 다음이다.

> `112개 샘플에 6개 feature를 추가한 logistic regression이 과적합된 것 아니냐? 왜 L1 regularization이나 feature selection을 쓰지 않았느냐?`

현재 답변 자원은 이미 일부 있다.

- ridge `lambda = 1e-2`
- CP7 내부 VIF `2.4-4.5`
- spatial CV, GroupKFold, LOSO에서도 결론 유지

하지만 가장 깔끔한 차단 방법은 간단한 L1 보조 실험을 supplement에 추가하는 것이다.

권장 실험:

- logistic regularization을 `lasso`로 바꿔 재실행
- `gamma_CP_rx1`, `gamma_CP_rx2`, `a_FP_LHCP_rx1`, `a_FP_LHCP_rx2`가 non-zero로 유지되는지 확인

권장 반영 문장:

- `A supplementary L1-regularized logistic check retained the main gamma and LHCP channels as non-zero terms, indicating that the reported gain is not driven solely by over-parameterization.`

## 7. 향후 수정 및 반영 계획

### A. 즉시 적용할 본문 수정

- 첫 문단에서 baseline을 두 층으로 분리:
  - `full 6-case reference baseline`
  - `paired 5-feature subset baseline`
- overall B+C paired result를 headline으로 배치
- hard-case 결과는 supporting evidence로 두 번째 문단에 배치
- rescue 분석을 별도 짧은 문단으로 분리
- 핵심 주장 문장을 `average improvement`가 아니라 `ambiguity reduction` 중심으로 교체

### B. 즉시 적용할 표현 수정

- `0.7959 -> 0.9139 directly improved`류 표현 삭제
- `calibration improvement` -> `probabilistic prediction quality improved` 또는 `probability error decreased`
- `strict orthogonality` -> `complementarity` 또는 `low redundancy`
- `structural recovery` -> `consistent pattern of recovery`

### C. discussion에 바로 넣을 수 있는 연결 문장

다음 문장은 R1-6, R2-11, R2-9를 동시에 연결하므로 discussion 첫 문장 후보로 적합하다.

> CP7가 FN (LoS→NLoS 오판)을 FP보다 더 많이 교정한다는 관찰은, LoS 경로에서 보존되는 polarization purity가 NLoS 경로의 depolarization 대비 feature space에서 더 구별 가능한 signature를 남긴다는 해석과 일관된다.

### D. robustness 보강

- spatial CV 결과 추가:
  - baseline `0.8406`
  - proposed `0.9066`
- fixed-seed paired CV, 20-repeat mean, spatial CV를 한 묶음으로 제시
- LOSO 결과 추가
- GroupKFold 결과를 leakage 대응 보조자료로 제시
- 가능하면 robustness subsection을 별도 1문단으로 독립 배치

### E. supplement / rebuttal 보강

- baseline VIF를 별도 문단으로 정리
- post-hoc subset readout `~0.847`은 rebuttal 또는 supplement 보조 근거로만 사용
- L1 regularization 보조 실험 추가 검토
- `a_FP_RHCP_rx2` 부호 불안정성과 dual-RX, subgroup mechanism은 supplement/discussion 배치
- LoS 교정 효과는 supplementary table 또는 discussion 보조 문장으로 반영

## 최종 정리

개별 사항 기준으로 보면, 보고서 1은 `결과와 코드의 신뢰성`을 강화하고, 보고서 2는 `논문 서술의 방어력`을 강화하며, 추가 개선 보고서는 `주장 축과 우선순위`를 정렬한다. 따라서 세 문서를 함께 반영할 때 가장 적절한 최종 방향은 다음과 같다.

> CP7 channel-resolved feature는 CP7-capable paired subset에서 geometric LoS/NLoS ambiguity를 감소시키며, 그 효과는 paired AUC/Brier/McNemar 개선, ambiguity band에서의 대폭적 향상, baseline error rescue, GroupKFold 및 LOSO robustness에서 일관되게 지지된다. 다만 이 주장은 full 6-case reference baseline과 구별된 paired subset comparison이라는 전제를 분명히 해야 하며, 물리적 메커니즘 해석은 hypothesis 수준에 머문다.
