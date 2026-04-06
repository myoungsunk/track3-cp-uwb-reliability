# FIGURE_REVIEW.md — 논문 Figure 검수 및 서술 제안

> 대상: Track 3 — ISAP 2026 (2–4 pages)
> 작성일: 2026-04-05
> 상태: **결과 없이 spec 수준 사전 검수**. 실제 결과 생성 후 §C (결과 해석)를 채울 것.

---

## A. ISAP 템플릿 기준 Figure 적합성 검수

### A.1 공통 요구사항

| 항목 | ISAP 2026 기준 | 현재 spec 상태 |
|------|--------------|---------------|
| 용지 크기 | IEEE 2-column, A4 | — |
| 1-column Figure 폭 | 8.5 cm (약 3.35 in) | spec 언급 있음 ✅ |
| 2-column Figure 폭 | 17.6 cm | 해당 Figure 없음 |
| 폰트 | Times New Roman 또는 동등 serif | spec 미명시 → 구현 시 추가 |
| 축 레이블 폰트 | 최소 8pt (인쇄 후 가독성) | spec 미명시 |
| 해상도 | 최소 300 dpi (EPS/PDF 권장) | spec에 300 dpi EPS 명시 ✅ |
| 색상 | 흑백 인쇄 호환 권장 | spec 미명시 → 구현 시 추가 |

### A.2 흑백 호환 색상 전략

ISAP 논문은 컬러 인쇄가 허용되나 흑백 복사 시에도 판독 가능해야 함:

```matlab
% 권장 색상 + 마커 조합
LoS_color  = [0.000, 0.447, 0.741]   % 파란색
NLoS_color = [0.850, 0.325, 0.098]   % 빨간색
LoS_marker  = 'o'
NLoS_marker = '^'
% 흑백 구분: 마커 모양이 달라야 흑백에서도 분리 가능
```

---

## B. Figure별 상세 사양 및 Caption 초안

### Fig. 1 — Feature Scatter + Decision Boundary

**목적**: r_CP와 a_FP의 LoS/NLoS 분리도 시각화 + Logistic 결정 경계 표시

**MATLAB 구현 가이드**:
```matlab
figure('Units','centimeters','Position',[0 0 8.5 7.5])

% 유효 샘플만 사용
valid = feature_table.valid_flag
x_los  = log10(feature_table.r_CP(valid & feature_table.label))
y_los  = feature_table.a_FP(valid & feature_table.label)
x_nlos = log10(feature_table.r_CP(valid & ~feature_table.label))
y_nlos = feature_table.a_FP(valid & ~feature_table.label)

scatter(x_los,  y_los,  25, [0 0.447 0.741], 'o', 'filled', ...
        'DisplayName', 'LoS')
hold on
scatter(x_nlos, y_nlos, 25, [0.85 0.325 0.098], '^', ...
        'DisplayName', 'NLoS')

% Decision boundary (logistic 0.5 등고선)
% 그리드 생성 후 predict → contour at 0.5
[gx, gy] = meshgrid(linspace(xmin, xmax, 200), linspace(0, 1, 200))
X_grid = [(gx(:) - mu(1)) / sigma(1), (gy(:) - mu(2)) / sigma(2)]
P_grid = predict(model.mdl_object, X_grid)
P_grid = reshape(P_grid, 200, 200)
contour(gx, gy, P_grid, [0.5 0.5], 'k--', 'LineWidth', 1.5, ...
        'DisplayName', 'Decision Boundary')

xlabel('$\log_{10}(r_\mathrm{CP})$', 'Interpreter','latex', 'FontSize',11)
ylabel('$\alpha_\mathrm{FP}$', 'Interpreter','latex', 'FontSize',11)
legend('Location','best', 'FontSize',9)
grid on; box on
exportgraphics(gcf, 'figures/fig1_scatter.pdf', 'ContentType','vector')
```

**Caption 초안 (영문)**:
> *Fig. 1. Two-dimensional feature space of the CP-UWB physical indicators $r_\mathrm{CP}$ (log-scale) and $\alpha_\mathrm{FP}$ for LoS (blue circles) and NLoS (red triangles) positions. The dashed line indicates the logistic regression decision boundary at $P(\mathrm{LoS}) = 0.5$.*

---

### Fig. 2 — ROC Curves

**목적**: 4개 모델의 분류 성능 비교

**MATLAB 구현 가이드**:
```matlab
figure('Units','centimeters','Position',[0 0 8.5 7.5])

colors = {[0 0.447 0.741], [0.85 0.325 0.098], ...
          [0.466 0.674 0.188], [0.494 0.184 0.556]}
styles = {'-', '--', '-.', ':'}
models = {'logistic', 'svm', 'rf', 'dnn'}
labels_disp = {'Logistic', 'SVM (RBF)', 'Random Forest', 'DNN [2-16-8-2]'}

hold on
for k = 1:4
    plot(results.(models{k}).roc_fpr, results.(models{k}).roc_tpr, ...
         'Color', colors{k}, 'LineStyle', styles{k}, 'LineWidth', 1.5, ...
         'DisplayName', sprintf('%s (AUC = %.3f)', labels_disp{k}, results.(models{k}).auc))
end
plot([0 1],[0 1],'Color',[0.6 0.6 0.6],'LineStyle',':','HandleVisibility','off')

xlabel('False Positive Rate', 'FontSize', 11)
ylabel('True Positive Rate', 'FontSize', 11)
legend('Location','southeast', 'FontSize', 8)
grid on; box on
xlim([0 1]); ylim([0 1])
exportgraphics(gcf, 'figures/fig2_roc.pdf', 'ContentType','vector')
```

**Caption 초안 (영문)**:
> *Fig. 2. Receiver operating characteristic (ROC) curves for four classification models using $r_\mathrm{CP}$ and $\alpha_\mathrm{FP}$ as input features. AUC values are reported in the legend. The logistic regression achieves comparable accuracy with significantly lower computational complexity.*

---

### Fig. 3 — Accuracy vs. FLOPs

**목적**: 연산 복잡도 대비 분류 정확도 trade-off 시각화 (논문 핵심 기여 강조)

**MATLAB 구현 가이드**:
```matlab
figure('Units','centimeters','Position',[0 0 8.5 7.0])

flops_vals = [results.logistic.flops, results.svm.flops, ...
              results.rf.flops, results.dnn.flops]
auc_vals   = [results.logistic.auc, results.svm.auc, ...
              results.rf.auc, results.dnn.auc]
labels_disp = {'Logistic', 'SVM', 'RF', 'DNN'}
markers = {'o', 's', '^', 'd'}
colors  = {[0 0.447 0.741], [0.85 0.325 0.098], ...
           [0.466 0.674 0.188], [0.494 0.184 0.556]}

hold on
for k = 1:4
    scatter(flops_vals(k), auc_vals(k), 80, colors{k}, markers{k}, ...
            'filled', 'LineWidth', 1.5)
    text(flops_vals(k)*1.15, auc_vals(k), labels_disp{k}, ...
         'FontSize', 9, 'Color', colors{k})
end

set(gca, 'XScale', 'log')
xlabel('FLOPs (per inference)', 'FontSize', 11)
ylabel('AUC', 'FontSize', 11)
xlim([1, max(flops_vals)*10])
ylim([0.7, 1.0])
grid on; box on
exportgraphics(gcf, 'figures/fig3_flops_auc.pdf', 'ContentType','vector')
```

**Caption 초안 (영문)**:
> *Fig. 3. Classification accuracy (AUC) versus computational complexity (FLOPs per inference) for four models. The proposed logistic regression achieves comparable AUC to SVM, RF, and DNN with 1–2 orders of magnitude lower complexity.*

---

### Fig. 4 — Calibration Reliability Diagram (지면 허용 시)

**목적**: 확률 출력의 보정 품질 시각화 → 빔 관리 직접 활용 가능성 근거

**MATLAB 구현 가이드**:
```matlab
figure('Units','centimeters','Position',[0 0 8.5 7.0])

% 10-bin reliability diagram
cal = results.logistic.cal_bins   % [10 × 2]: [mean_conf, mean_acc]
valid_bins = ~isnan(cal(:,1))

bar(cal(valid_bins,1), cal(valid_bins,2), 0.08, ...
    'FaceColor',[0 0.447 0.741], 'EdgeColor','k')
hold on
plot([0 1],[0 1],'k--','LineWidth',1.2)   % perfect calibration

xlabel('Mean Predicted Probability', 'FontSize', 11)
ylabel('Fraction of Positives (LoS)', 'FontSize', 11)
xlim([0 1]); ylim([0 1])
text(0.05, 0.9, sprintf('ECE = %.3f', results.logistic.ece), ...
     'FontSize', 10)
grid on; box on
exportgraphics(gcf, 'figures/fig4_calibration.pdf', 'ContentType','vector')
```

**Caption 초안 (영문)**:
> *Fig. 4. Calibration reliability diagram of the logistic regression model. Each bar represents the fraction of LoS samples within a confidence bin. The dashed diagonal indicates perfect calibration. The expected calibration error (ECE) is [value].*

---

### Fig. P1 — LoS-only Preview (중간 검증용)

**목적**: NLoS 데이터 없어도 생성 가능한 중간 점검 Figure

**포함 내용**:
1. r_CP와 a_FP 분포 히스토그램 (caseA/B/C 별 색상)
2. (guide 데이터 있을 경우) 위치추정 오차 scatter

**Caption 초안 (영문)**:
> *Fig. P1. (Validation) Distribution of CP-UWB physical indicators $r_\mathrm{CP}$ and $\alpha_\mathrm{FP}$ across [N] LoS measurement positions in caseA/B/C scenarios.*

---

## C. Results 섹션 핵심 서술 문장 (영문, 결과 생성 후 수치 채울 것)

> ⚠️ 현재 결과 없음. 아래는 **템플릿**이며, 실제 수치 획득 후 `[X.XX]` 부분을 채울 것.

### C.1 Feature 분리도

```
"Fig. 1 shows that $r_\mathrm{CP}$ and $\alpha_\mathrm{FP}$ exhibit complementary
discrimination between LoS and NLoS conditions: $r_\mathrm{CP}$ captures the
polarization imbalance at the first path, while $\alpha_\mathrm{FP}$ reflects
the energy concentration of the direct component. The Pearson correlation
between the two indicators is $\rho = [X.XX]$, confirming their complementarity."
```

> **Note**: |ρ| < 0.5이면 "complementary" 강하게 주장 가능. |ρ| > 0.7이면 "partially correlated, yet individually informative" 로 표현 조정.

### C.2 분류 성능

```
"The logistic regression achieves an AUC of [X.XX] ± [X.XX] (5-fold CV),
comparable to SVM ([X.XX]), RF ([X.XX]), and DNN ([X.XX]), with an AUC
degradation of less than [X.XX]."
```

> **Note**: AUC 차이 < 0.03 → "equivalent performance". 0.03–0.05 → "marginal degradation". > 0.05 → "with a slight accuracy trade-off of [X]%".

### C.3 연산 복잡도

```
"As shown in Fig. 3, the proposed logistic regression requires only [7] FLOPs
per inference, representing a [XX]× reduction compared to DNN ([~260] FLOPs)
and [XX]× compared to RBF-SVM ([6N_sv+7] FLOPs with N_sv=[X]).
This [1–2] order-of-magnitude complexity reduction is achieved without
significant accuracy loss, making it suitable for real-time deployment."
```

### C.4 Calibration

```
"The logistic regression yields an ECE of [X.XX], indicating [well-calibrated /
moderately calibrated] probability outputs. This enables the predicted LoS
probability to be directly used as a spatial reliability score for beam
management without additional recalibration."
```

> **Note**: ECE < 0.05 → "well-calibrated, directly usable". ECE 0.05–0.10 → "adequate for practical use". ECE > 0.10 → Platt scaling 적용 후 재평가 권장.

### C.5 Ablation

```
"The ablation study (Table II) demonstrates that combining both indicators
improves AUC by Δ[X.XX] over $r_\mathrm{CP}$ alone and Δ[X.XX] over
$\alpha_\mathrm{FP}$ alone, confirming their complementary contributions to
LoS/NLoS discrimination."
```

---

## D. Discussion 서술 제안 (Track 1 연결)

```
"The proposed lightweight LoS/NLoS classifier can be seamlessly integrated
into Track 1's beam management framework: the logistic regression outputs
a calibrated probability $\hat{p}_\mathrm{LoS}(k)$ for each spatial position $k$,
which directly serves as the spatial reliability weight in the RSSD-based
DoA estimator [cite IoT-J 2025]. This O(1) integration incurs negligible
additional latency compared to the O(1) DoA estimation itself."

"Future work will extend the classifier to NLoS subtype identification
(single-bounce vs. double-bounce), leveraging the parity information embedded
in the circular polarization ratio $r_\mathrm{CP}$: odd-bounce NLoS
($r_\mathrm{CP} < 1$) and even-bounce NLoS ($r_\mathrm{CP} \approx 1$) exhibit
distinct patterns that a two-class logistic model can further exploit."
```

---

## E. 결과 생성 후 확인 체크리스트

- [ ] Fig. 1: LoS/NLoS 클러스터가 시각적으로 분리되는가? (논문의 핵심 근거)
- [ ] Fig. 1: Decision boundary가 두 클러스터 사이를 통과하는가?
- [ ] Fig. 2: Logistic ROC가 DNN/SVM 곡선과 0.03 이내 범위에 있는가?
- [ ] Fig. 3: Logistic 점이 왼쪽 아래에 위치하고 DNN 점이 오른쪽에 위치하는가?
- [ ] Fig. 3: x축 range가 적어도 2 decades(10배 범위)인가?
- [ ] Fig. 4: ECE 값이 0.10 미만인가?
- [ ] Pearson ρ 계산: `corr(log10(r_CP), a_FP)` → |ρ| 확인
- [ ] 수치 채우기: §C.1–C.5의 [X.XX] 플레이스홀더 모두 채우기

---

*최종 수정: 2026-04-05 | 작성자: Claude Code (Architecture Agent)*
*결과 생성 후 §C 수치 채우기 및 Figure EPS 검수 예정*
