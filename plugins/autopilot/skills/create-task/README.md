# create-task

**무엇** — 자연어 의도를 명확화 인터뷰로 탐색해 **태스크 본문**(목표·배경·제안·검증 계획·완료 기준)으로 떠서
선택된 백엔드(filesystem/github-project/beads)에 태스크로 **등록**하는 진입점. 본문이 곧 SPEC이며 별도 SPEC
파일은 만들지 않는다.

**언제** — 새 기능·변경·지침을 시작하며, 그 의도를 무인 실행 가능한 태스크로 백로그에 올리고 싶을 때.
등록된 태스크는 `execute-task`(단일 실행)나 `workflow-task`(무인 드레인)가 실행한다.

**호출** — `Skill(skill="create-task", args="<자연어 task 설명>")`.

**자기완결** — 컨슈밍 프로젝트 `rules/`나 다른 스킬에 의존하지 않는다. 방법론은 `references/`, 백엔드 계약은
플러그인 `task-backend/contract.md`가 단일 출처. 상세는 `SKILL.md`를 따른다.
