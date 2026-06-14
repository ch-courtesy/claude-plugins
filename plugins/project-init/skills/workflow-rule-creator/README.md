# workflow-rule-creator

프로젝트의 워크플로 sub-룰을 워크플로 카테고리 디렉터리 아래 `rules/workflow/<sub>.md` 파일로 생성·갱신하는 스킬.

- **무엇** — `templates/*.md`의 각 sub-룰(SPEC 설계 산출물 레이아웃·단계 게이트 등)을 고정 순서로 하나씩 별도 파일로 기록.
- **언제** — project-init 초기화 흐름 중 호출되거나, 사용자가 워크플로 sub-룰 지침을 새로 만들고 싶을 때.
- **호출** — `Skill(skill="project-init:workflow-rule-creator")`.

생성 절차·템플릿 frontmatter 파싱·입력 수집·파일 기록 규칙 등 동작 명세는 단일 출처인 [`SKILL.md`](./SKILL.md)를 참조한다.
