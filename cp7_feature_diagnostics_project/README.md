# CP7 Feature Diagnostics Project

이 폴더는 현재 스레드에서 진행한 CP7 diagnostics 산출물을 별도로 모아둔 작업 폴더입니다.

## 포함 내용

- `00_summary` ~ `05_baselines`: 실행 결과
- `run_cp7_project.m`: 이 폴더를 결과 루트로 다시 실행하는 launcher

## 실행

MATLAB에서 아래처럼 실행하면 결과가 이 폴더 아래에 다시 생성됩니다.

```matlab
run('cp7_feature_diagnostics_project/run_cp7_project.m')
```

## 코드 위치

실제 구현 코드는 프로젝트 루트의 `src` 아래에 있습니다.

- `src/run_cp7_feature_diagnostics.m`
- `src/build_cp7_analysis_table.m`
- `src/cp7_binary_feature_metrics.m`
- `src/cp7_local_knn_auc.m`

## CP6 Final Lock (2026-04-08)

- Final model feature set is locked to 6 features:
  - gamma_CP_rx1, gamma_CP_rx2,
  - a_FP_RHCP_rx1, a_FP_LHCP_rx1,
  - a_FP_RHCP_rx2, a_FP_LHCP_rx2
- Removed from model feature set: fp_idx_diff_rx12
- Measurement wording to keep in methods/captions:
  - RHCP transmission, dual-CP reception

### Re-run commands

```matlab
run(''cp7_feature_diagnostics_project/run_cp7_project.m'')
```

This command re-runs diagnostics and then builds final draft figures under:
`cp7_feature_diagnostics_project/09_final_lock/`
