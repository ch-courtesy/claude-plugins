# version-control-rule-creator

프로젝트의 변경 제안(PR/MR) 심사·승인 등 버전 관리(VCS) 지침을 `rules/version-control/<sub>.md`로 생성·갱신하는 스킬.

- **무엇** — `templates/` 아래 sub-룰을 `rules/version-control/`로 기록. 백엔드 변형을 가진 sub-룰(예: `review-approval`)은 git origin remote에서 자동 판별한 백엔드(GitHub/GitLab)의 변형 본문을 쓰고, 백엔드가 git 계열이면 git 공통 지침(`git`)을 동반 산출.
- **언제** — project-init 초기화 흐름 중 호출되거나, 사용자가 버전 관리(VCS) 워크플로 지침을 새로 만들고 싶을 때.
- **호출** — `Skill(skill="project-init:version-control-rule-creator")`.

절차·템플릿 레이아웃·백엔드 판별·입력 치환 등 동작 명세는 단일 출처인 [`SKILL.md`](./SKILL.md)와 그것이 가리키는 참조 파일을 본다.
