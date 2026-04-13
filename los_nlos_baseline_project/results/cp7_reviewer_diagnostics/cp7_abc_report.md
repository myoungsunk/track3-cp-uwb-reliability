# CP7 6-Feature A/B/C Report

## Scope

- Target feature set:
  - `gamma_CP_rx1`, `gamma_CP_rx2`
  - `a_FP_RHCP_rx1`, `a_FP_LHCP_rx1`
  - `a_FP_RHCP_rx2`, `a_FP_LHCP_rx2`
- Baseline literature feature set:
  - `fp_energy_db`, `skewness_pdp`, `kurtosis_pdp`, `mean_excess_delay_ns`, `rms_delay_spread_ns`
- Proposed model:
  - `Baseline ∪ {gamma_CP_rx1, gamma_CP_rx2, a_FP_RHCP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2}`
- Evaluation scope:
  - `CP_caseB`, `CP_caseC` only
  - total joined samples `112`
  - join success `112/112`, label mismatch `0`
- Label split:
  - `material`: `95 LoS / 17 NLoS`
  - `geometric`: `56 LoS / 56 NLoS`

## (a) Feature Correlation / Redundancy

### Objective

기존 top feature(`fp_energy_db`, `skewness_pdp`, `kurtosis_pdp`)와의 상관을 통해, 6개 CP7 feature 중 어떤 항이 실제로 orthogonal information을 제공하는지 확인한다.

### Key finding

- `gamma_CP_rx2`가 가장 낮은 중복성을 보였다.
- `gamma_CP_rx1`는 부분적으로는 orthogonal하지만 완전히 독립적이지는 않았다.
- `a_FP_*` 계열은 기존 energy / shape feature와 상관이 높아, 독립 정보보다는 보강 또는 재표현에 가깝다.

### Orthogonality summary

`mean |Spearman rho|` against `{fp_energy_db, skewness_pdp, kurtosis_pdp}`:

| CP7 feature | mean \|rho\| | max \|rho\| | interpretation |
|---|---:|---:|---|
| `gamma_CP_rx2` | 0.1301 | 0.3314 | strongest orthogonality |
| `gamma_CP_rx1` | 0.3163 | 0.3929 | partial orthogonality |
| `a_FP_LHCP_rx2` | 0.4302 | 0.5326 | moderate redundancy |
| `a_FP_RHCP_rx2` | 0.4467 | 0.5924 | moderate-high redundancy |
| `a_FP_LHCP_rx1` | 0.4917 | 0.5724 | high redundancy |
| `a_FP_RHCP_rx1` | 0.5012 | 0.5418 | high redundancy |

### Representative pairwise values

- `gamma_CP_rx2` vs `fp_energy_db`: Pearson `0.3243`, Spearman `0.3314`
- `gamma_CP_rx2` vs `skewness_pdp`: Pearson `0.0432`, Spearman `0.0236`
- `gamma_CP_rx2` vs `kurtosis_pdp`: Pearson `0.1120`, Spearman `0.0353`

- `gamma_CP_rx1` vs `fp_energy_db`: Pearson `0.3474`, Spearman `0.1839`
- `gamma_CP_rx1` vs `skewness_pdp`: Pearson `0.3828`, Spearman `0.3929`
- `gamma_CP_rx1` vs `kurtosis_pdp`: Pearson `0.2407`, Spearman `0.3720`

- `a_FP_RHCP_rx1` vs `fp_energy_db`: Pearson `0.5897`, Spearman `0.4739`
- `a_FP_RHCP_rx1` vs `skewness_pdp`: Pearson `0.5811`, Spearman `0.5418`
- `a_FP_LHCP_rx1` vs `fp_energy_db`: Pearson `0.4574`, Spearman `0.5724`

### Interpretation

- Orthogonal information 주장은 **6개 전체에 대해 균일하게 성립하지 않는다**.
- 더 정확한 표현은 다음과 같다:
  - `gamma_CP_rx2` is the most orthogonal channel-specific CP feature.
  - `gamma_CP_rx1` provides partially complementary information.
  - `a_FP_*` channels overlap substantially with conventional energy/shape descriptors.

## (b) Incremental AUC / Feature Fusion Gain

### Objective

동일한 cross-validation fold에서 `Baseline`과 `Baseline + 6 CP7 features`를 비교해, AUC / Brier / McNemar 기준으로 실제 fusion gain을 확인한다.

### Main result

결과는 label target에 따라 갈렸다.

- `material` 기준에서는 전반적으로 이득이 없었다.
- `geometric` 기준에서는 일관된 이득이 있었고, 특히 hard-case에서 개선 폭이 컸다.

### Overall comparison

| Target | Scope | Baseline AUC | Proposed AUC | Delta AUC | Baseline Brier | Proposed Brier | Delta Brier | McNemar p |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `material` | `C` | 0.9375 | 0.9141 | -0.0234 | 0.1010 | 0.1147 | +0.0137 | 1.0000 |
| `material` | `B+C` | 0.9474 | 0.9282 | -0.0192 | 0.0853 | 0.0948 | +0.0095 | 0.6875 |
| `geometric` | `B` | 0.8490 | 0.9007 | +0.0517 | 0.1634 | 0.1247 | -0.0387 | 0.7744 |
| `geometric` | `C` | 0.8082 | 0.8735 | +0.0653 | 0.1800 | 0.1339 | -0.0461 | 1.0000 |
| `geometric` | `B+C` | 0.8495 | 0.9072 | +0.0577 | 0.1570 | 0.1163 | -0.0408 | 0.0127 |

### Hard-case comparison

Hard case is defined by baseline confidence in `[0.4, 0.6]`.

| Target | Scope | n | Baseline AUC | Proposed AUC | Delta AUC | Delta Brier | McNemar p |
|---|---|---:|---:|---:|---:|---:|---:|
| `material` | `C` | 4 | 0.0000 | 1.0000 | +1.0000 | -0.1233 | 0.5000 |
| `material` | `B+C` | 9 | 1.0000 | 0.6667 | -0.3333 | +0.0059 | 1.0000 |
| `geometric` | `B` | 13 | 0.9000 | 0.9667 | +0.0667 | -0.1392 | 0.6250 |
| `geometric` | `C` | 11 | 0.5833 | 1.0000 | +0.4167 | -0.1732 | 0.5000 |
| `geometric` | `B+C` | 12 | 0.4286 | 0.9429 | +0.5143 | -0.1535 | 0.0313 |

### Interpretation

- `material`:
  - CP7 6-feature fusion은 ceiling effect를 깨지 못했다.
  - `B`는 `55 LoS / 1 NLoS`라 inferential comparison 자체가 불안정해서 skip됐다.
  - 따라서 material 기준에서 6-feature gain 주장은 설득력이 약하다.

- `geometric`:
  - `B`, `C`, `B+C` 모두 AUC와 Brier가 개선됐다.
  - 특히 `B+C overall`에서 `ΔAUC = +0.0577`, `ΔBrier = -0.0408`, McNemar `p = 0.0127`.
  - hard-case `B+C`에서 `ΔAUC = +0.5143`, McNemar `p = 0.0313`.
  - 따라서 geometric label 기준에서는 6-feature fusion gain이 분명하다.

## (c) Misclassification Disambiguation

### Objective

Baseline이 틀린 샘플 중 몇 개를 6-feature model이 복구하는지 확인해, reviewer가 가장 직관적으로 이해할 수 있는 rescue statistic을 제시한다.

### Overall rescue summary

| Target | Baseline errors | Proposed errors | Rescued | Harmed | Net gain | Rescue rate |
|---|---:|---:|---:|---:|---:|---:|
| `material` | 11 | 13 | 2 | 4 | -2 | 18.18% |
| `geometric` | 27 | 16 | 14 | 3 | +11 | 51.85% |

### Case-wise rescue summary

#### Material

| Case | Baseline errors | Proposed errors | Rescued | Harmed | Net gain |
|---|---:|---:|---:|---:|---:|
| `CP_caseB` | 3 | 3 | 1 | 1 | 0 |
| `CP_caseC` | 8 | 10 | 1 | 3 | -2 |

#### Geometric

| Case | Baseline errors | Proposed errors | Rescued | Harmed | Net gain |
|---|---:|---:|---:|---:|---:|
| `CP_caseB` | 12 | 6 | 7 | 1 | +6 |
| `CP_caseC` | 15 | 10 | 7 | 2 | +5 |

### Interpretation

- `material`:
  - baseline이 틀린 `11`개 중 `2`개만 복구했고, 오히려 `4`개를 새로 망쳤다.
  - disambiguation benefit이 있다고 보기 어렵다.

- `geometric`:
  - baseline이 틀린 `27`개 중 `14`개를 복구했다.
  - rescue rate는 `51.85%`.
  - `CP_caseB`, `CP_caseC` 모두에서 rescue가 발생했다.
  - 따라서 6개 feature는 geometric ambiguity 해소에는 실질적인 보조 신호로 작동한다.

## Conclusion

### What is supported

- `a)` 6개 feature 중에서는 `gamma_CP_rx2`, 일부 `gamma_CP_rx1`가 top baseline feature와 비교적 낮은 상관을 보여 orthogonal information 가능성을 뒷받침한다.
- `b)` geometric label 기준에서는 6-feature fusion이 전체 성능과 hard-case 성능을 모두 개선한다.
- `c)` geometric label 기준에서는 baseline 오분류의 절반 이상을 복구했다.

### What is not supported

- material label 기준에서는 6-feature fusion gain이 재현되지 않았다.
- 따라서 "6개 CP7 feature가 보편적으로 LoS/NLoS 분류를 개선한다"는 문장은 과장이다.

### Recommended paper claim

가장 방어적인 서술은 다음과 같다.

> Channel-resolved CP features provide complementary information primarily for geometric LoS/NLoS discrimination. The strongest orthogonal contribution arises from the `gamma` channels, while the `a_FP` channels are more correlated with conventional energy and shape descriptors. Their benefit is especially pronounced on hard or ambiguous samples, where they rescue a substantial fraction of baseline misclassifications.

## (d) Scenario B Focused Interpretation

### Objective

Scenario B에서 왜 CP 기반 feature가 유독 강하게 동작하는지, 그리고 왜 동일한 현상이 Scenario C에서는 약화되는지를 geometry / material 관점에서 물리적으로 설명한다.

### Scenario B geometry and material regime

Scenario B object layout:

- `glass_partition_1`
  - material: `glass`
  - role: partial LoS blocker near room center
  - intended effect: mixed reflection / transmission behavior
- `metal_cabinet_1`
  - material: `metal`
  - role: high-reflectivity side-wall object
  - intended effect: strong specular interaction
- `wood_desk_1`
  - material: `wood`
  - role: low-height weak reflector
  - intended effect: secondary multipath enrichment

Scenario C object layout is much denser:

- 2 glass partitions
- 2 metal cabinets
- 4 wood objects

즉, Scenario B는 소수의 지배적 interaction으로 설명 가능한 반면, Scenario C는 다중 산란체가 공존하는 cluttered regime이다.

### What actually happens in Scenario B

`CP_caseB`의 label structure는 매우 비대칭적이다.

- `material` 기준:
  - `55 LoS / 1 NLoS`
  - 유일한 material-NLoS 샘플은 `(5.25, -1.75)`, tag `T49`
  - hit object: `metal_cabinet_1`
  - hit material: `metal`
  - criterion: `hard_block_material`
  - reported penetration loss: `160674.598`

- `geometric` 기준:
  - `35 LoS / 21 NLoS`
  - geometric-NLoS 21개 중 `20`개는 `glass_partition_1`
  - `1`개만 `metal_cabinet_1`

이 구성이 의미하는 바는 명확하다.

- `material` Scenario B는 사실상 **single metallic hard-block regime**이다.
- `geometric` Scenario B는 대부분 **thin glass obstruction regime**이다.

따라서 reviewer가 본 기존 `r_CP @ CP_B = 1.000`은 “Scenario B 전체에서 parity가 보편적으로 완벽하다”는 뜻이 아니라, **매우 희소한 metal-dominated material split를 averaged feature가 극단적으로 잘 집어낸 결과**로 해석해야 한다.

### 6-feature view: refinement of the earlier `r_CP=1.000` claim

평균 `r_CP`로 보면 `CP_caseB` material에서 완벽 분리가 나타났지만, channel-resolved 6-feature로 풀어보면 다음처럼 더 미세한 그림이 나온다.

#### Material labels, `CP_caseB`

| Feature | AUC |
|---|---:|
| `gamma_CP_rx1` | 0.9091 |
| `gamma_CP_rx2` | 0.6909 |
| `a_FP_RHCP_rx1` | 0.9818 |
| `a_FP_LHCP_rx1` | 0.6000 |
| `a_FP_RHCP_rx2` | 0.7273 |
| `a_FP_LHCP_rx2` | 0.7818 |

중요한 점은:

- channel별로는 `1.000`이 재현되지 않는다.
- strongest single-channel cue는 `a_FP_RHCP_rx1`이고, parity cue 중에서는 `gamma_CP_rx1`가 더 유효하다.
- 즉, 이전의 perfect `r_CP` 결과는 **receiver/channel aggregation 효과**까지 포함된 결과였고, 실제 정보는 특정 채널에 더 집중돼 있다.

따라서 6-feature 관점에서의 더 정확한 문장은 다음과 같다.

> In Scenario B under material labels, the CP-based signal is not uniformly perfect across channels; rather, one metallic hard-block sample induces a highly separable regime in which selected parity and first-path polarization channels become unusually discriminative.

### Why Scenario B can look strong

Scenario B의 metal sample은 `metal_cabinet_1`에 의한 hard block이다. 이 경우:

- direct-path dominance가 무너지고,
- specular interaction이 한두 개의 dominant mechanism으로 압축되며,
- channel-specific CP response가 상대적으로 안정된 구조를 가진다.

이런 regime에서는 parity-related `gamma` feature가 “odd/even bounce parity” 또는 dominant specular path structure를 반영하는 진단 지표처럼 작동할 수 있다. 동시에 일부 `a_FP` 채널은 first-path polarization concentration 변화를 강하게 반영한다.

즉, Scenario B의 강한 결과는

- universally strong feature
  가 아니라,
- **specular / hard-block / low-clutter regime에서만 강한 regime-selective diagnostic**

으로 보는 것이 타당하다.

### Why the same logic weakens in Scenario C

Scenario C는 다음 이유로 다르다.

- 산란체 수가 많다.
- glass / metal / wood가 동시에 존재한다.
- direct, reflected, transmitted, late scattered components가 중첩된다.
- parity 정보가 개별 dominant path에 묶이지 않고 여러 경로에 의해 섞인다.

결과적으로:

- `CP_caseC` material에서 `gamma_CP_rx1 = 0.7703`, `gamma_CP_rx2 = 0.5828`
- `CP_caseC` geometric에서 `gamma_CP_rx1 = 0.7102`, `gamma_CP_rx2 = 0.6259`

즉, parity 정보는 완전히 사라지지는 않지만, **Scenario B의 hard specular regime만큼 날카로운 binary discriminator로 유지되지 않는다**.

이 점은 reviewer 문장으로 아래처럼 쓰는 것이 가장 자연스럽다.

> The Scenario B advantage should not be interpreted as a universal strength of parity cues. Instead, it reflects a regime in which a small number of dominant interactions, including a metallic hard-block path, preserve channel-specific CP structure. In Scenario C, denser clutter and mixed materials diffuse this structure, so parity information degrades from a near-binary cue into a weaker complementary descriptor.

### Link back to classification results

이 물리 해석은 실제 classification behavior와도 맞는다.

- `material`
  - sparse metal hard-block sample 때문에 single-feature AUC는 높게 보일 수 있다.
  - 하지만 global fusion gain은 재현되지 않았다.
  - 즉, highly selective but not generalizable.

- `geometric`
  - glass-driven obstruction이 많아 single parity cue는 moderate 수준이다.
  - 대신 6개 채널을 함께 쓰면 ambiguity resolution에 실질적 도움이 된다.
  - `CP_caseB` rescue: baseline error `12` 중 `7`개 복구, `1`개만 악화

### Recommended paper wording

가장 방어적인 결론은 다음과 같다.

> Scenario B reveals that CP-channel features are regime-sensitive rather than uniformly strong. The strongest response appears when the link is governed by a small number of dominant interactions, especially the metallic hard-block sample in the material-label setting. Under such conditions, parity-related channels behave like diagnostic indicators. In denser and more diffuse environments such as Scenario C, this channel-specific structure is partially destroyed, so the same cues remain useful only as complementary features rather than standalone binary discriminators.
