# Track 2-1: CP vs LP 단일 앵커 위치추정 시스템 비교 — 코드 설계 요청

## 너의 역할
코드 아키텍트. 코드를 직접 작성하지 않는다. 
출력물: DESIGN.md (Codex가 읽고 구현할 설계서)

## 프로젝트 개요
6.5 GHz UWB 실내 환경에서 CP vs LP 단일 앵커 위치추정 성능 비교.
HFSS SBR+ 시뮬레이션 데이터 사용. MATLAB 구현.

## 시스템 정의
- 시스템1 (CP): Anchor 1개(RHCP) + 틸티드 태그(RHCP × 2)
- 시스템2 (LP): Anchor 1개(LP) + 틸티드 태그(LP × 2)

## 데이터 입력
- data/ 폴더 내 CSV/MAT 파일
- 6개 케이스: CP_caseA, CP_caseB, CP_caseC, LP_caseA, LP_caseB, LP_caseC
- 각 케이스별 S-parameter 또는 CIR 데이터 포함
- Scenario A: All LoS (56 태그)
- Scenario B: LoS+NLoS (34/22)
- Scenario C: LoS+NLoS (21/35)

## 파이프라인 4단계 — 각 단계를 독립 함수/스크립트로 설계할 것

### Stage 1: Ranging Error
- 입력: CIR 데이터 (IFFT 기반 합성 또는 직접 로드)
- 처리: ToA 추출 (first-path detection), 거리 산출, ground truth 대비 오차
- 출력: ranging_error 벡터 (각 태그별), RMSE, CDF

### Stage 2: DoA Error  
- 입력: 틸티드 태그의 안테나1, 안테나2 RSS 값
- 처리: RSSD = RSS1 - RSS2, RSSD→DoA 변환 (IoT-J 2025 방법론)
- 출력: doa_error 벡터, RMSE, CDF

### Stage 3: Multipath Rejection Ratio
- 입력: CIR 데이터
- 처리: E_fp / E_total (first-path energy / total energy)
- 출력: rejection_ratio 벡터, CP vs LP 비교

### Stage 4: 2D Positioning Error
- 입력: Stage 1의 range, Stage 2의 DoA
- 처리: (range, DoA) → 2D 좌표 변환, ground truth 대비 오차
- 출력: positioning_error 벡터, RMSE, CEP67, CEP95, CDF

## 출력 요구사항
- 비교 plot: CP vs LP를 동일 그래프에 표시 (시나리오별)
- 요약 테이블: 시나리오 × 편파 × 지표 매트릭스

## DESIGN.md에 포함할 것
1. 파일 구조 (어떤 .m 파일이 필요한지)
2. 각 함수의 시그니처 (입력, 출력, 파라미터)
3. 데이터 흐름도 (Stage 1→2→3→4)
4. 데이터 파일 로딩 규칙 (naming convention → 케이스 매핑)
5. 핵심 수식 (ToA 추출, RSSD→DoA, 좌표 변환)
