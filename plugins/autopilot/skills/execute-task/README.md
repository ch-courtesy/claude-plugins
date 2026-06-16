# execute-task

**무엇** — 등록된 단일 태스크의 전체 생애(구현→리뷰→머지→done)를 소유하는 실행기. 태스크 본문을 임시
spec으로 떠 랄프 루프로 구현하고, origin 호스트에 맞춰(PR/MR/로컬) 리뷰·ff-only 머지한 뒤 백엔드 상태를
`done`으로 전이한다. heartbeat lease로 크래시 워커를 회수 가능하게 한다.

**언제** — `create-task`로 등록된 태스크 하나를 끝까지 실행하고 싶을 때. 여러 태스크의 무인 드레인은
`workflow-task`가 이 스킬을 fan-out한다.

**호출** — `Skill(skill="execute-task", args="start <task-id> [--stop-at review] | status|stop|logs <task-id>")`.

**자기완결** — `rules/`나 다른 스킬에 doc-link하지 않는다. 검증된 엔진(랄프 루프·forge 워커 헬퍼)은 런타임으로
재사용한다. 상세는 `SKILL.md`를 따른다.
