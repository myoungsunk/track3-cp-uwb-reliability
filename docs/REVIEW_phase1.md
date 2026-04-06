# REVIEW_phase1.md — Phase 1 코드 사전 검수

> 검수 대상: M01–M10 (데이터 로딩, CIR 합성, Feature 추출, 위치추정)
> 검수 시점: **코드 구현 전 spec 수준 사전 검수** (Codex 구현 완료 후 코드 검수로 업데이트 예정)
> 작성일: 2026-04-05

---

## 요약

| 모듈 | Spec 완성도 | 구현 리스크 | 우선순위 |
|------|-----------|-----------|---------|
| M01 load_sparam_table | ✅ 완성 | 낮음 (readtable 표준) | 2 |
| M01b load_los_nlos_labels | ⚠️ TODO 존재 | **높음** (파일 구조 미확인) | **1** |
| M02 build_sim_data_from_table | ✅ 완성 | 중간 (IFFT 파라미터) | 3 |
| M03 detect_first_path | ✅ 완성 | 낮음 | 4 |
| M04 extract_rcp | ✅ 완성 | 낮음 | 4 |
| M05 extract_afp | ✅ 완성 | 낮음 | 4 |
| M06 extract_features_batch | ✅ 완성 | 낮음 | 4 |
| M07 build_rssd_lut | ⚠️ guide 데이터 구조 미확인 | **높음** | **1** |
| M08 estimate_doa_rssd | ✅ 완성 | 낮음 | 5 |
| M09 estimate_position | ⚠️ 좌표계 미확정 | 중간 | 3 |
| M10 run_joint_phase1 | ✅ 완성 | 낮음 | 5 |

---

## M01: load_sparam_table

### ✅ PASS

- [x] Ansys CSV 형식 반영 완료
- [x] 파일명 파싱 (`cp`/`lp`, `caseA/B/C`) 로직 명확
- [x] 복소 전달함수 변환: `H = mag * exp(j * ang_rad)` 정확
- [x] NaN 검사 및 경고 포함
- [x] group_id 생성: `unique(coords, 'rows', 'stable')` 방식 적절

### ⚠️ WARNING

**W1**: `params.col_*` 기본값이 MATLAB 버전마다 다를 수 있음.
- readtable이 `[n]` 단위 표기를 `_n_`으로 변환하는지 `_n__` (언더스코어 2개)으로 변환하는지 R2021b에서 직접 확인 필요.
- **조치**: M01 구현 시 `T.Properties.VariableNames`를 출력하고, params.col_*과 비교하는 `validate_column_names()` 내부 헬퍼 추가.

**W2**: 주파수 축이 오름차순이 아닐 경우 IFFT 결과에 왜곡 발생.
- **조치**: M01에서 `freq_table`을 `group_id` + `freq_ghz` 기준으로 정렬 후 반환.

### ❌ FAIL (없음)

---

## M01b: load_los_nlos_labels

### ❌ FAIL (구현 전 필수 확인)

**F1**: `LOS_NLOS_EXPORT_20260405/` 파일의 실제 구조가 spec에 미반영.
- 열 이름, LoS 플래그 값, 파일명 패턴이 모두 TODO 상태.
- Codex가 구현하기 전에 **연구자가 먼저** 아래를 확인해야 함:

```matlab
% 확인 절차
files = dir('LOS_NLOS_EXPORT_20260405/*.csv')
T = readtable(files(1).name)
disp(T.Properties.VariableNames)   % 열 이름 확인
disp(T(1:5,:))                     % 첫 5행 확인
unique(T.(flag_col))               % 플래그 값 종류 확인
```

**F2**: `match_labels_by_coord()`의 `coord_tol_mm = 1e-3` 값이 임의.
- S-param CSV와 레이블 파일의 좌표가 동일한 소수점 자리를 사용하는지 확인 필요.
- 두 파일의 좌표가 독립적으로 생성된 경우 부동소수점 표현이 달라 매칭 실패 가능.
- **조치**: 매칭 전 round(x, 4) 처리 또는 좌표 최소 간격의 0.1배를 `tol_mm`으로 자동 설정.

### ⚠️ WARNING

**W3**: `caseA` 전체가 LoS임에도 불구하고 레이블 파일에서 매칭을 시도하면 오버헤드.
- **조치**: `if strcmp(case_id, 'caseA')` 시 레이블 파일 로드 없이 `labels = true(N_pos, 1)` 직접 할당하는 fast path 추가.

---

## M02: build_sim_data_from_table

### ✅ PASS

- [x] Hanning window + zero-padding + IFFT 흐름 명확
- [x] 시간축 계산: `dt = 1/(N_fft * df_Hz)` 정확
- [x] RSS 계산에 상대값임을 주석으로 명시
- [x] 레이블 로딩을 M01b에 위임 (M02는 CIR 합성만 담당)

### ⚠️ WARNING

**W4**: N_fft이 위치별로 다를 수 있음.
- 주파수 범위 필터링 후 남은 포인트 수 `N_f`가 위치마다 다를 경우 `CIR_rx1` 행렬 사전 할당 불가.
- **조치**: 첫 번째 그룹으로 `N_fft` 결정 후 모든 그룹에 동일 적용. 다른 경우 warning 출력.

**W5**: `hann(N_f)` 함수가 R2021b에서는 `hanning(N_f)`일 수 있음.
- **조치**: `if exist('hann', 'builtin'), win = hann(N_f); else, win = hanning(N_f); end`

**W6**: IFFT 출력이 복소수이므로 `abs(CIR)` 를 쓰는 모든 하류 함수에서 명시적 변환 필요.
- M03 `detect_first_path`의 입력이 `cir_abs` (이미 절대값) 형태로 설계되어 있어 ✅.
- M04, M05도 `abs()` 적용 구조이므로 ✅.

### ❌ FAIL (없음)

---

## M03: detect_first_path

### ✅ PASS

- [x] Leading-edge threshold 방식 구현 명확
- [x] `search_window` 옵션: ranging 재사용 지원
- [x] `fp_info` 구조체 반환: 디버깅 지원
- [x] 탐색 실패 시 `NaN` 반환: 하류에서 `valid_flag=false` 처리

### ⚠️ WARNING

**W7**: `search_window` 사용 시 `params.t_axis`가 없으면 에러 발생.
- **조치**: `if ~isempty(params.fp_search_window_ns) && isempty(params.t_axis), error(...), end`

**W8**: `threshold = fp_threshold_ratio × max(cir_search)` 에서 `cir_search`가 모두 0인 경우 `threshold = 0` → `candidates = find(cir_search > 0)` → 첫 번째 비-zero 샘플 반환 가능.
- 이 경우 noise floor의 첫 샘플을 first-path로 잘못 검출.
- **조치**: `if peak_val < noise_floor_linear, fp_idx = NaN; return; end` 추가. `noise_floor_linear = 10^(params.min_power_dbm/10)`.

---

## M04: extract_rcp

### ✅ PASS

- [x] edge case 4종 처리 완비 (`ok`, `rx2_zero`, `rx1_zero`, `both_below_floor`)
- [x] `r_CP_clip` 클리핑으로 Inf 방지
- [x] `fp_info` 반환으로 디버깅 지원

### ⚠️ WARNING

**W9**: LHCP first-path 인덱스(`fp_l`)와 RHCP first-path 인덱스(`fp_r`)가 다를 때, 두 채널의 first-path가 서로 다른 시각에 있음을 의미.
- 현재는 독립적으로 검출하므로 물리적으로 올바른 설계.
- 단, `fp_r`과 `fp_l`의 차이가 너무 크면 (예: 5 ns 이상) 한쪽이 noise peak를 검출했을 가능성.
- **조치**: `if abs(t_axis(fp_r) - t_axis(fp_l)) > 5 ns, rcp_info.flag = 'fp_timing_mismatch'` 경고 추가 (선택).

### ❌ FAIL (없음)

---

## M05: extract_afp

### ✅ PASS

- [x] CIR 선택 4종 (`RHCP/LHCP/combined/power_sum`) 완비
- [x] `fp_idx`는 선택된 CIR 기준으로 재검출 (일관성 ✅)
- [x] `E_total == 0` edge case 처리

### ⚠️ WARNING

**W10**: `power_sum` 모드에서 `cir = sqrt(|rx1|² + |rx2|²)` 계산 후 `detect_first_path(abs(cir), ...)` 를 호출하면 `abs(sqrt(...))` = `sqrt(...)` (이미 실수 양수).
- 문제없음. 단, 코드에서 `abs(cir)` 대신 `cir` 직접 사용 가능 → 불필요한 abs() 호출.
- **조치**: `power_sum` 케이스에서는 `cir_abs = cir` (already positive real) 주석 추가.

---

## M06: extract_features_batch

### ✅ PASS

- [x] sim_data 두 번째 출력으로 반환 (localization 재사용)
- [x] valid_flag, fp_idx를 feature_table에 포함
- [x] r_CP Inf → clip 처리
- [x] label fallback (없으면 all-LoS + warning)
- [x] 진행률 출력

### ⚠️ WARNING

**W11**: for loop 방식은 N_pos가 크면 느림.
- MATLAB에서 `parfor`로 병렬화 가능하나, `detect_first_path` 내 `params.t_axis` 참조가 있어 parfor 적용 시 주의.
- **조치**: 초기 구현은 for loop, N_pos > 1000이면 parfor 고려.

---

## M07: build_rssd_lut

### ⚠️ WARNING (guide 데이터 구조 확인 후 업데이트 필요)

**W12**: guide 데이터 존재가 확정되었으나, inc_ang 열 이름과 데이터 구조가 spec에 명시되지 않음.
- guide 파일도 Ansys CSV 형태인지, 또는 별도 측정 파일인지 확인 필요.
- **조치**: guide 파일 확인 후 M01의 `params.coord_cols = {'inc_ang'}` 설정 방법 업데이트.

**W13**: RSSD 단조성 가정이 실제 패턴과 다를 경우 DoA 추정 실패.
- CP 안테나의 RSSD-angle 곡선이 비단조일 때 `monotonic_range`가 좁아질 수 있음.
- **조치**: LUT 생성 후 `plot(lut.ang_axis, lut.rssd_curve)` 시각화 필수.

---

## M09: estimate_position

### ❌ FAIL

**F3**: 좌표계가 미확정.
- Tx 앵커 위치 (`anchor_x_m`, `anchor_y_m`), DoA 기준 방향 (`doa_reference_deg`)이 모두 TODO.
- 이 값들이 잘못되면 위치 추정 오차가 체계적으로 틀림.
- **조치**: MATLAB 시뮬레이션 설정 파일에서 Tx 위치 및 좌표계 기준 확인 후 spec 업데이트.

**F4**: ranging 시 single-sided vs round-trip이 미확정.
- Ansys S-parameter 시뮬레이션은 보통 one-way transfer (S21).
- `range = t_fp_ns * 1e-9 * c0` (one-way) vs `range = t_fp_ns * 1e-9 * c0 / 2` (round-trip).
- **조치**: Ansys 시뮬레이션 설정에서 확인. 일반적으로 S21은 one-way이므로 `range = t_fp_ns * 1e-9 * c0` 가 맞을 가능성 높음.

---

## Phase 1 전체 결론

**코드 구현 착수 전 필수 해결 항목:**
1. **F1** (M01b): `LOS_NLOS_EXPORT_20260405/` 파일 구조 확인
2. **F3** (M09): Tx 앵커 위치 및 좌표계 기준 확인
3. **F4** (M09): S21 = one-way ToA 확인
4. **W12** (M07): guide 파일 구조 확인

**구현 중 주의 항목:**
- W1: `params.col_*` 열 이름 실제 확인
- W2: freq_table 정렬 보장
- W5: `hann()` vs `hanning()` MATLAB 버전 확인
- W8: noise floor 기반 fp_idx NaN 처리

---

*최종 수정: 2026-04-05 | 작성자: Claude Code (Architecture Agent) — 사전 검수*
*코드 구현 완료 후 실제 코드 기준으로 업데이트 예정*
