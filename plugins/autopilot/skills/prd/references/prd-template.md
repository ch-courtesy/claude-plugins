# {{prd_title}}

**Milestone**: {{milestone}}

## 문제

<!-- 이 milestone이 해결하는 사용자/시스템 문제를 자유 산문으로. 누구의 어떤 어려움이 어떤 형태로 나타나는지. dispatch가 child SPEC들로 분해할 때 각 단위가 어느 문제의 부분 해결인지 분명히 보이도록. -->
{{problem}}

## 목표·비전

<!-- 이 milestone이 완료되면 어떤 상태가 되는지. 측정 가능하면 가장 좋지만 산문도 허용. -->
{{goals}}

## 성공 기준

<!-- 어떻게 "이 milestone 완료"를 판정하는지. EARS 강제 아님 — dispatch가 분해 후 child SPEC에서 EARS로 정밀화한다.
  자유 산문 + bullet 허용. 다만 각 기준이 *원리적으로* verifiable해야. -->
{{success_criteria}}

## 범위

포함:
{{scope_in}}

비-목표 / 제외:
{{scope_out}}

## 제약 (있을 때만)

<!-- 환경·도구·호환성·시간 등 알려진 제약. dispatch 분해 시 각 child가 이 제약을 받음. -->
{{constraints}}

## 위험 (있을 때만)

<!-- 이미 알려진 dead-end·함정·금지 영역. dispatch가 child SPEC의 Risks로 전파한다. -->
{{risks}}

## 분해 힌트 (선택)

<!-- dispatch가 자동 분해하지만, 사용자가 명시적 단위 후보를 미리 제시할 수 있다.
  형식 예:
  - child-a: <한 줄> | 영향 파일 [src/a/**] | 의존성 [없음]
  - child-b: <한 줄> | 영향 파일 [src/b/**] | 의존성 [child-a 후]
  비워도 됨 — dispatch가 PRD 본문에서 분해 후보 추출. -->
{{decomposition_hints}}
