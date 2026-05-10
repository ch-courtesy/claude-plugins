# DAG — {{milestone}}

`milestones/{{milestone}}/prd/PRD.md`의 분해 결과. dispatch가 게이트 ① 승인 후 작성.

생성 시각: {{created_at}}

## 단위 목록

{{children}}

<!--
형식 예:
- child-a: <한 줄 요약>
  - 영향 파일: src/a/**
  - verify: pytest tests/a
  - 의존성: 없음
- child-b: ...
-->

## 의존성·wave 정렬

{{waves}}

<!--
형식 예:
- wave 1 (parallel-safe): [child-a, child-b]
- wave 2 (depends on wave 1): [child-c]
- wave 3 (depends on wave 2): [child-d]
-->

## 메모

{{notes}}

<!--
사용자 피드백·재분해 사유·예외 케이스 등 자유 산문.
-->
