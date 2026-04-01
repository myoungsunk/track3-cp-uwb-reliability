# Phase 3: Claude Code — 코드 리뷰 + 결과 해석 프롬프트

## 컨텍스트
이전 Phase에서 Codex가 구현한 코드가 GitHub에 push되었다.
너의 역할은: (1) 코드 리뷰, (2) 시뮬레이션 결과 해석, (3) 논문 서술 방향 제안

---

## Task A: 코드 리뷰

아래 파일들을 순서대로 리뷰하고, 각각에 대해 docs/REVIEW_phase1.md 또는 docs/REVIEW_phase2.md에 결과를 기록하라.

리뷰 체크리스트:
```
[ ] 1. spec과의 일치성: 함수 시그니처, 입출력 형식, 알고리즘이 spec과 정확히 일치하는가?
[ ] 2. Edge case 처리: r_CP=Inf, a_FP=0, 빈 CIR, 음수 전력 등 비정상 입력에 대한 방어 코드 존재?
[ ] 3. 수치 안정성: log(0), division by zero, very small denominator 등의 처리?
[ ] 4. 재현성: rng(seed) 호출이 모든 랜덤 연산 직전에 있는가?
[ ] 5. 단위 일관성: ns와 s 혼용 없는가? dB와 linear 혼용 없는가?
[ ] 6. 공정 비교: ML benchmark에서 모든 모델이 동일 fold split을 사용하는가?
[ ] 7. FLOPs 계산: 각 모델의 FLOPs 공식이 정확한가? (특히 SVM의 N_sv 반영)
[ ] 8. Figure 품질: 폰트 크기, 축 레이블, 범례, 해상도가 ISAP 기준 충족?
```

리뷰 출력 형식:
```markdown
## 파일: src/extract_rcp.m
### PASS 항목
- [x] 함수 시그니처 일치
- [x] leading-edge 검출 구현 정확

### FAIL 항목  
- [ ] Edge case: L102에서 fp_idx가 1 미만일 때 max(1, fp_idx) 처리 누락
  - 수정 제안: `fp_idx = max(1, fp_idx - fp_window_samples);`

### WARNING 항목
- r_CP 계산 시 log10 변환이 extract_rcp 내부가 아닌 호출측에서 수행되어야 함
  - spec에서는 "train_logistic에서 log10 변환"으로 명시 → 현재 구현과 일치하나, 
    batch 추출 시 raw linear r_CP를 저장하는 것이 맞는지 확인 필요
```

---

## Task B: 시뮬레이션 결과 해석

Codex가 생성한 results/ 디렉토리의 결과 파일을 읽고, 아래 질문에 답변하라.
결과 파일: results/benchmark_results.mat, results/ablation_results.mat

해석 질문 목록:
```
1. r_CP와 a_FP의 LoS/NLoS 분포가 실제로 상보적인가?
   - scatter plot에서 r_CP만으로 분리 어려운 영역을 a_FP가 커버하는지 시각적 확인
   - 만약 두 지표가 strongly correlated (|ρ| > 0.7)이면 상보성 주장이 약화됨
   → Pearson correlation coefficient 확인 요청

2. Logistic Regression AUC가 ML 모델 대비 어느 수준인가?
   - AUC 차이 < 0.03이면 "동등 수준"으로 주장 가능
   - AUC 차이 > 0.05이면 "약간의 정확도 희생"으로 재프레이밍 필요
   → 논문 서술 톤 조정 제안

3. Ablation 결과에서 combined > 단독의 개선폭은?
   - ΔAUC(combined - r_CP_only), ΔAUC(combined - a_FP_only)
   - 둘 다 > 0.05이면 상보성 강하게 주장 가능
   - 한쪽만 미미하면 해당 지표의 기여도를 솔직히 기술

4. ECE 값은 적절한가?
   - ECE < 0.05: well-calibrated → 빔 관리 직접 활용 가능
   - ECE > 0.10: 추가 calibration 필요 → Platt scaling 제안

5. FLOPs 비교에서 "3~4자릿수 차이"가 실제로 달성되는가?
   - Logistic: 5 FLOPs
   - SVM: 수십~수백 (N_sv 의존)
   - RF: 수백~수천
   - DNN: ~200
   → 정확한 배수를 계산하고, 논문 abstract에 쓸 수 있는 표현 제안
```

---

## Task C: 논문 Figure 검수 및 서술 제안

생성된 Figure들에 대해:
1. ISAP 템플릿 기준 적합성 검수 (column width, font size, color scheme)
2. 각 Figure의 caption 초안(영문) 작성
3. Results 섹션의 핵심 서술 문장 3~5개 제안 (영문)
4. Discussion에서 "Track 1으로의 확장" 연결 문장 1~2개 제안

출력: docs/FIGURE_REVIEW.md
