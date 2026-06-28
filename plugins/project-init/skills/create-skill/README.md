# create-skill

인터뷰 기반으로 새 스킬(SKILL.md)을 설계·작성하는 `project-init` 스킬.

## 무엇을

루브릭 30항목 품질 기준을 작성 단계에 내장해 BLOCKER·MAJOR 0을 목표로
SKILL.md와 README.md를 완성한다.

## 언제

사용자가 새 스킬 작성·설계·제작·초안 생성을 요청하거나,
SKILL.md 품질 개선이 필요할 때 활성화된다.
정확한 트리거 표현은 `SKILL.md`의 `description`이 단일 출처다.

## 어떻게 호출

에이전트가 위 트리거를 감지하면 자동 활성화된다. 별도 인자는 없다.

## 진입점·포인터

- 동작 명세(절차·규칙)의 단일 출처: [`SKILL.md`](./SKILL.md)
- 루브릭 30항목 자가점검 체크리스트: [`references/quality-criteria.md`](./references/quality-criteria.md)
- SKILL.md 구조 틀: [`references/skill-template.md`](./references/skill-template.md)

> 이 문서는 폴더 진입점용 요약이다. 진행 순서·규칙 본문은 `SKILL.md`에만 두며 여기서 복제하지 않는다.
