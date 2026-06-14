# context-rule-creator

프로젝트의 컨텍스트 관리 지침을 컨텍스트 카테고리 디렉터리 아래 두 sub-룰 파일(`rules/context/task-model.md`·`rules/context/task-ops.md`)로 생성·갱신하는 스킬.

- **무엇** — 선택한 컨텍스트 백엔드를 백엔드 결합도 기준으로 task-model(백엔드 결합)·task-ops(백엔드 무관 운영)로 갈라 기록.
- **언제** — project-init 초기화 흐름 중 호출되거나, 사용자가 컨텍스트 지침을 새로 만들고 싶을 때.
- **호출** — `Skill(skill="project-init:context-rule-creator")`.

절차·템플릿 레이아웃·백엔드 선택·이벤트 카탈로그 등 동작 명세는 단일 출처인 [`SKILL.md`](./SKILL.md)를 참조한다.
