# Track 2-1: 구현 지시서

## 너의 역할
MATLAB 코드 구현자. DESIGN.md를 읽고 그대로 구현한다.
설계를 변경하지 않는다. 불명확한 점은 코드 내 TODO 주석으로 남긴다.

## 규칙
1. DESIGN.md의 파일 구조, 함수 시그니처를 정확히 따를 것
2. 모든 코드는 src/ 폴더에 생성
3. 메인 스크립트: main_track2_1.m (전체 파이프라인 순차 실행)
4. 각 Stage는 독립 함수 파일로 분리
5. 하드코딩 금지 — 모든 경로, 파라미터는 config 구조체로 관리
6. 각 함수 상단에 입출력 설명 주석 필수
7. 데이터 로딩 시 파일 존재 여부 체크 + 에러 메시지
8. plot 저장: results/ 폴더에 .fig + .png

## 데이터 규칙
- data/ 폴더 참조
- 파일 네이밍: DESIGN.md의 naming convention 따를 것
- CP_caseA, CP_caseB, CP_caseC, LP_caseA, LP_caseB, LP_caseC

## 구현 순서
1. config 구조체 + 데이터 로딩 함수
2. Stage 1 (ranging)
3. Stage 2 (DoA)
4. Stage 3 (rejection ratio)
5. Stage 4 (positioning)
6. 비교 plot + 요약 테이블 생성
7. main_track2_1.m 통합

## 완료 기준
- main_track2_1.m 실행 시 results/ 에 모든 plot + summary_table.csv 생성
- 에러 없이 6개 케이스 전체 처리 
