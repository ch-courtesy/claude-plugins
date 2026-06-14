# review-rule-creator

프로젝트의 리뷰 지침을 리뷰 카테고리 디렉터리 아래 두 sub-룰 파일(`rules/review/principles.md`·`rules/review/change-adoption.md`)로 생성·갱신하는 스킬.

- **무엇** — 공통 리뷰 원칙(principles)과 거기서 나온 지적의 반영 판단(change-adoption)을 설계된 페어로 함께 기록.
- **언제** — project-init 초기화 흐름 중 호출되거나, 사용자가 리뷰 지침을 새로 만들고 싶을 때.
- **호출** — `Skill(skill="project-init:review-rule-creator")`.

페어로 함께 기록하는 이유·템플릿 레이아웃·생성 절차·확인 게이트 등 동작 명세는 단일 출처인 [`SKILL.md`](./SKILL.md)를 참조한다.
