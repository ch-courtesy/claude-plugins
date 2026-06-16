# workflow-task

**무엇** — 백엔드에서 준비된(의존 충족) 태스크를 모아 `execute-task`를 병렬 fan-out하는 **DAG 없는 1회
드레이너**. 의존 순서 해결은 백엔드 `list_ready`가 틱 간에 담당하므로 오케스트레이터가 DAG를 들지 않는다.

**언제** — 무인 폴링 에이전트가 주기적으로 backlog를 드레인할 때, 또는 지금 준비된 태스크를 한 번에 자동
실행하고 싶을 때. 주기 반복은 외부 스케줄러(cron/ScheduleWakeup)가 담당한다.

**호출** — `Skill(skill="workflow-task", args="start [--max-parallel N]")`.

**자기완결** — `rules/`나 다른 스킬에 doc-link하지 않는다. flow 병렬 러너와 execute-task를 런타임으로 재사용한다.
상세는 `SKILL.md`를 따른다.
