# REVIEW_phase1.md — Phase 1 코드 구현 후 검수

> 검수 대상: M01–M10 (데이터 로딩, CIR 합성, Feature 추출, 위치추정)
> 검수 시점: **코드 구현 완료 후 실제 코드 기준 검수**
> 작성일: 2026-04-07 (최초 사전 검수: 2026-04-05)

---

## 요약

| 모듈 | 파일 | Spec 일치 | Edge Case | 수치 안정성 | 재현성 | 단위 일관성 | 판정 |
|------|------|----------|-----------|-----------|--------|-----------|------|
| M01 | load_sparam_table.m | ✅ | ⚠️ | ✅ | N/A | ✅ | PASS |
| M02 | build_sim_data_from_table.m | ✅ | ⚠️ | ⚠️ | N/A | ✅ | PASS (WARNING) |
| M03 | detect_first_path.m | ✅ | ✅ | ✅ | N/A | ✅ | PASS |
| M04 | extract_rcp.m | ✅ | ✅ | ✅ | N/A | ✅ | PASS |
| M05 | extract_afp.m | ✅ | ✅ | ✅ | N/A | ✅ | PASS |
| M06 | extract_features_batch.m | ✅ | ✅ | ✅ | N/A | ✅ | PASS |
| M07 | build_rssd_lut.m | ✅ | ⚠️ | ⚠️ | N/A | ✅ | PASS (WARNING) |
| M08 | estimate_doa_rssd.m | ✅ | ✅ | ✅ | N/A | ✅ | PASS |
| M09 | estimate_position.m | ⚠️ | ✅ | ✅ | N/A | ✅ | WARNING |
| M10 | run_joint_phase1.m | ✅ | N/A | N/A | N/A | N/A | PASS |

---

## M03: detect_first_path.m

### PASS 항목
- [x] 함수 시그니처 `[fp_idx, fp_info] = detect_first_path(cir_abs, params)` — spec 일치
- [x] Leading-edge threshold 검출: `threshold = fp_threshold_ratio * peak_val` (L72) — 정확
- [x] 탐색 윈도우 `fp_search_window_ns` + `t_axis` 연동 정상 (L32–65)
- [x] 빈 CIR 처리: `n_tap == 0` → `fp_idx = NaN` (L17–19)
- [x] 비정상 peak 처리: `peak_val <= 0` 또는 `~isfinite(peak_val)` → `fp_idx = NaN` (L78–80)
- [x] `fp_info` 구조체 반환 (peak_idx, peak_val, threshold, search_range, found)
- [x] `search_window_ns` 사용 시 `t_axis` 없으면 error 발생 (L36–38) — W7 해결 확인

### WARNING 항목
- **W-M03-1**: `fp_threshold_ratio` 상한 검증 미비 (L22–25). `ratio > 1.0` 허용 시 `threshold > peak_val` → `find(cir_search >= threshold)` 가 peak 자체만 반환. 물리적으로는 무의미하나 crash하지 않음.
  - 심각도: Low
  - 수정 제안: `if fp_threshold_ratio > 1.0, warning('...'); end` 추가 (선택)

### FAIL 항목
없음.

---

## M04: extract_rcp.m

### PASS 항목
- [x] 함수 시그니처 `[r_CP, rcp_info] = extract_rcp(cir_rx1, cir_rx2, params)` — spec 일치
- [x] Edge case 4종 완비 (L46–63):
  - `both_zero` → `r_CP = NaN` ✅
  - `lhcp_zero` (P_rx2=0, P_rx1>0) → `r_CP = r_CP_clip` ✅
  - `rhcp_zero` (P_rx1=0, P_rx2>0) → `r_CP = 0` ✅
  - `clipped` (r_CP > r_CP_clip) → `r_CP = r_CP_clip` ✅
- [x] `r_CP_clip` 기본값 `1e4` (= 40 dB) — spec 일치
- [x] `min_power_dbm` 기반 노이즈 플로어 처리 (L18–23)
- [x] Division by zero 방지: `p_rx2 == 0` 시 분기 처리로 나눗셈 자체 회피 ✅
- [x] `r_CP_clip` 유효성 검증: positive finite 체크 (L14–16)
- [x] First-path 각 채널 독립 검출 (L25–26) — 물리적으로 올바름

### WARNING 항목
- **W-M04-1**: `min_power_dbm - 30` (L20) dBm → linear 변환에서 `-30` 상수 하드코딩. `10^((dBm - 30)/10)` = `10^(dBm/10) / 1000` 으로 정확한 dBm → Watt 변환이지만, 이 코드에서 RSS가 상대값(dBm relative)이므로 절대 참조 불일치 가능.
  - 심각도: Low (현재 `min_power_dbm = -inf` 기본값이므로 실행에 영향 없음)
  - 수정 제안: 주석으로 `% dBm to Watt: P_linear = 10^((P_dBm - 30)/10)` 의도 명시

### FAIL 항목
없음.

---

## M05: extract_afp.m

### PASS 항목
- [x] 함수 시그니처 `[a_FP, afp_info] = extract_afp(cir_rx1, cir_rx2, t_axis, params)` — spec 일치
- [x] CIR 소스 4종 선택 (L16–27): RHCP, LHCP, COMBINED, POWER_SUM — spec 일치
- [x] 에너지 비율 계산: `a_FP = E_fp / E_total` (L55) — 정확
- [x] First-path NaN 시 `a_FP = NaN` 반환 (L38–43)
- [x] `E_total <= 0` edge case → `a_FP = NaN` (L52–53)
- [x] a_FP 클램핑 `min(max(a_FP, 0), 1)` (L56)
- [x] 시간 윈도우: `[t_fp - T_w, t_fp + T_w]` (L46–48) — spec 일치, T_w = 2.0 ns 기본값

### WARNING 항목
- **W-M05-1**: COMBINED 모드(L22)에서 `(cir_rx1 + cir_rx2) / 2` 는 복소 진폭 평균. 두 CIR의 위상이 다르면 상쇄간섭 발생. 의도적 설계인지 확인 필요.
  - 심각도: Low (기본값 RHCP이므로 대부분의 경우 영향 없음)
- **W-M05-2**: POWER_SUM 모드(L24)에서 `sqrt(|rx1|^2 + |rx2|^2)` 는 전력 합산의 제곱근으로, 명칭이 혼동 가능 (`power_sum`이지만 실제로는 magnitude of vector sum). 
  - 심각도: Low (문서화 이슈)

### FAIL 항목
없음.

---

## M06: extract_features_batch.m

### PASS 항목
- [x] 함수 시그니처 `[feature_table, sim_data] = extract_features_batch(sim_data, params)` — spec 일치
- [x] Feature table 9개 열: pos_id, r_CP, a_FP, label, valid_flag, fp_idx_RHCP, fp_idx_LHCP, RSS_RHCP, RSS_LHCP — spec 일치
- [x] `valid_flag`: r_CP 또는 a_FP가 NaN이면 false (L47–49)
- [x] r_CP 이중 클리핑 (L57–58): `extract_rcp` 내부 클리핑 후 배치 레벨에서 재클리핑 — 중복이지만 안전
- [x] 라벨 미존재 시 fallback `true(n_pos, 1)` + warning (L63–65)
- [x] 진행률 출력 매 100 샘플 (L51–53)
- [x] CIR 크기 일치 검증 (L19–21)

### WARNING 항목
없음.

### FAIL 항목
없음.

---

## M01: load_sparam_table.m

### PASS 항목
- [x] CSV/MAT 로드 지원
- [x] 복소 전달함수 변환: `H = mag * exp(1j * ang_rad)` — 정확
- [x] NaN/Inf 검사 후 경고 출력
- [x] 좌표 단위 변환 (mm/m) 지원
- [x] 위상 단위 변환 (deg/rad) 지원
- [x] `find_column_name()` 헬퍼로 MATLAB 버전 간 열 이름 차이 대응

### WARNING 항목
- **W-M01-1**: 비정상 행 필터링 시 silent drop (warning만 출력, 복구 불가). 데이터 손실 추적 어려움.
  - 심각도: Low (warning 존재)
- **W-M01-2**: 주파수 축 정렬이 M01 내부에서 보장되지 않음. 정렬은 M02에서 수행되나, M01 출력이 비정렬 상태로 다른 곳에 사용될 경우 문제 가능.
  - 심각도: Low (현재 파이프라인에서는 M01 → M02 순차 호출)

### FAIL 항목
없음.

---

## M02: build_sim_data_from_table.m

### PASS 항목
- [x] Hanning window + zero-padding + IFFT 파이프라인 구현
- [x] 시간축 계산: `dt = 1/(N_fft * df_Hz)`, 나노초 변환 정확
- [x] RSS 계산: `10*log10(sum(|cir|^2))` — 상대값 (dB)
- [x] 레이블 CSV 매칭 (좌표 기반 join)
- [x] mm → m 변환 (`/1e3`) 정상

### WARNING 항목
- **W-M02-1**: `interp1()` 에서 'linear' + 'extrap' 사용. 주파수 대역 외 외삽은 비물리적 값 생성 가능.
  - 심각도: Medium
  - 수정 제안: `'extrap'` 대신 `'none'` 사용 후 NaN 구간 zero-fill. 또는 대역 외 데이터를 사전 제거.
- **W-M02-2**: 좌표 매칭 시 `sprintf('%.3f', ...)` 로 3자리 반올림. 부동소수점 표현 차이로 1mm 미만의 좌표 불일치 발생 가능.
  - 심각도: Medium (현재 데이터에서 실제 불일치 없었으나, 다른 데이터셋 적용 시 위험)
  - 수정 제안: `round(coord, 3)` 대신 `abs(coord_a - coord_b) < tol` 방식 사용

### FAIL 항목
없음.

---

## M07: build_rssd_lut.m

### PASS 항목
- [x] RSSD = RSS_ant1 - RSS_ant2 계산 — spec 일치
- [x] 보간 기반 LUT 생성
- [x] 단조 구간 자동 검출

### WARNING 항목
- **W-M07-1**: `sign()` 이 0을 반환하는 경우 (기울기=0 구간) 단조성 판단이 불안정 (fragile slope detection).
  - 심각도: Medium
- **W-M07-2**: 단조 구간이 존재하지 않는 패턴에서 빈 범위 반환 가능.
  - 심각도: Medium (현재 localization 미사용이므로 실행에 영향 없음)

### FAIL 항목
없음. (Guide 데이터 미사용으로 실행 경로 미도달)

---

## M09: estimate_position.m

### WARNING 항목
- **W-M09-1**: One-way vs two-way ranging 미확정 (F4 사전 검수 항목 유지).
  - `range = t_fp_ns * 1e-9 * c0` (one-way) — S21은 일반적으로 one-way이므로 올바를 가능성 높음.
  - 그러나 spec에 명시적 확인 미완료.
- **W-M09-2**: Tx 앵커 좌표 (`anchor_x_m`, `anchor_y_m`) 기본값 `(0, 0)`. 실제 시뮬레이션 설정과 일치 여부 미확인.
  - 심각도: Medium (현재 localization 미사용)

### FAIL 항목
없음. (Localization 미실행이므로 실제 영향 없음)

---

## M10: run_joint_phase1.m

### PASS 항목
- [x] 함수 시그니처 `results = run_joint_phase1(sim_data_guide, sim_data_test, params)` — spec 일치
- [x] Feature 추출 → Localization 순차 호출 구조 — 간결하고 명확
- [x] Localization 선택적 실행 (guide 데이터 유무에 따라)

### FAIL 항목
없음.

---

## 사전 검수 (2026-04-05) 대비 변경 사항

| 사전 검수 항목 | 상태 | 비고 |
|--------------|------|------|
| F1 (M01b): LoS/NLoS 파일 구조 미확인 | ✅ 해결 | `LOS_NLOS_EXPORT_20260405/` CSV 기반 좌표 매칭 구현 완료 |
| F3 (M09): 좌표계 미확정 | ⚠️ 미완 | Localization 미사용이므로 현재 영향 없음. 향후 guide 데이터 확보 시 재확인 필요 |
| F4 (M09): One-way vs two-way | ⚠️ 미완 | 상동 |
| W1: 열 이름 버전 차이 | ✅ 해결 | `find_column_name()` 헬퍼로 유연 매칭 구현 |
| W2: freq_table 정렬 | ✅ 해결 | M02에서 정렬 보장 |
| W5: `hann()` vs `hanning()` | ✅ 해결 | 코드에서 적절히 처리 |
| W7: search_window + t_axis | ✅ 해결 | L36–38에서 error 발생 |
| W8: noise floor fp_idx | ✅ 해결 | `peak_val <= 0` 검사 (L78) |

---

## Phase 1 전체 결론

**구현 품질: PASS (4 WARNING)**

코드가 spec을 충실히 구현함. Feature 추출 핵심 모듈 (M03–M06)은 edge case 처리 완비, 수치 안정성 확보. Localization (M07–M09)은 현재 미사용이므로 실행 검증 불가하나, 코드 구조상 큰 문제 없음.

**잔여 리스크:**
1. M02 좌표 매칭의 부동소수점 허용 오차 (W-M02-2) — 다른 데이터셋 적용 시 주의
2. M02 외삽 (W-M02-1) — 대역 외 주파수 데이터 존재 시 비물리적 CIR 생성 가능
3. M09 ranging convention 미확정 — Localization 활성화 시 반드시 확인

---

*최종 수정: 2026-04-07 | 작성자: Claude Code — 구현 후 코드 검수*
