# decomposition algorithm (optimized)

PRD를 child SPEC 단위로 나누는 휴리스틱.

## 입력 검증

`milestones/<m>/prd/PRD.md`가 있어야 하고 `[NEEDS CLARIFICATION` 마커가 0개여야 한다. 실패 시 abort + `prd <m> --resume` 안내.

## 단위 후보 조건

각 후보는 세 조건을 모두 만족해야 한다.

1. 단일 컨텍스트 윈도우 fit: spec 9-step + loop 30 iter 안에 끝날 크기.
2. 테스트 폐쇄성: 자체 verify 명령으로 완료 판정 가능.
3. 격리성: 같은 wave 후보끼리 같은 파일을 동시에 수정하지 않음.

## hard cap

- 1차 분해 <= 8 단위
- 재귀 분해 깊이 <= 2
- 최종 child <= 20

초과 시 abort하고 PRD 자체 분해를 권고한다.

## dependency / wave

파일·산출물 의존성을 뽑아 DAG를 만든다. cycle이면 abort. 토포 정렬 후 서로 파일 충돌이 없고 의존성이 없는 child를 같은 wave로 묶는다. wave는 순차, wave 내부 child는 병렬 가능.

## 출력

게이트 1에는 wave별 child 표를 제시한다: child 이름/한 줄 요약/예상 파일/verify/의존성. 승인 후 `dag-template.md`로 DAG.md 작성.
