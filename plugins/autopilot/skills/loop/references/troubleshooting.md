# ESCALATION troubleshooting (optimized)

차단 신호의 `**카테고리**`별 처리. 차단 해제는 task에 `[unblocked]` 또는 `[resume]` 신호를 발행하는 것이 정식 절차다. UI 상태만 바꾸면 차단이 유지될 수 있다.

## config-gap

도구 미설치, 자격증명, env var 누락. missing item 확인 -> 환경 조정 -> `[unblocked] <사유>` -> restart 또는 watch 자동 재개.

## spec-gap

모호한 수용 기준, verify 부적합, scope 미흡. 필요한 결정 확인 -> SPEC 보정(`Skill(skill: "spec", args: "<task-id>")` 또는 worktree SPEC 수정) -> `[unblocked] SPEC 보정 완료` -> 재시작.

## architecture-gap

현재 구조로 해결 불가. 본 task 정지, 별도 architecture task 수행, 이후 SPEC scope 조정 또는 cleanup 후 새 task.

## environment-gap

API rate limit, 네트워크, 외부 서비스 장애. 일시 문제면 대기 후 재시작, 영구 문제면 mock/test double 또는 spec 조정.

## other

차단 본문을 읽고 사람이 판단.

## halt 후 stash

driver halt 시 미커밋 변경은 자동 stash될 수 있다. 워크트리에서 `git stash list`, 필요 시 `git stash pop`.

## v0.1 -> v0.2 migration

새 경로는 `milestones/<m>/loops/<c>/`. 기존 `.loops/`는 자동 이동하지 않는다. 진행 task를 v0.1에서 종결하고, 필요한 SPEC은 `milestones/regular/loops/<task-id>/SPEC.md`로 수동 이동, stale lock 삭제, 빈 `.loops/`와 sibling worktree 정리.
