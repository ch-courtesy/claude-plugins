# ESCALATION 카테고리별 처리 가이드

정지된 task의 `[blocked]` prefix comment 본문 `**카테고리**` 필드 별 사람의 처리 권장 흐름. comment 본문은 `gh issue view <task-issue> --comments`로 읽고, Blocked 해제는 GitHub Projects UI에서 task의 Status field를 "In Progress"로 수동 변경합니다(또는 `gh project item-edit --id <item-id> --project-id <project-id> --field-id <status-field-id> --single-select-option-id <in-progress-option-id>` — Projects v2 CLI의 정식 호출 형태는 field·option node ID를 사전 조회해야 하므로 UI가 더 단순).

## config-gap (환경 설정·도구 부재)

증상: 도구 미설치, 자격증명 부재, 환경 변수 누락 등.

처리:
1. `[blocked]` comment 본문 읽고 missing item 식별 (`gh issue view <task-issue> --comments`)
2. target 프로젝트 환경 조정 (도구 설치, env var 설정 등)
3. GitHub Projects UI에서 task의 Status를 "In Progress"로 변경해 Blocked 해제
4. `start <task-id>` 또는 watch 모드면 자동 재개

## spec-gap (SPEC.md 결함)

증상: 모호한 수용 기준, 검증 명령 부적합, scope 정의 미흡 등.

처리:
1. `[blocked]` comment 본문의 "필요한 결정" 섹션 검토
2. 워크트리의 SPEC.md 직접 수정. 워크트리 루트는 `milestones/<m>/loops/<c>/.worktree`이고 그 안 SPEC 위치는 `milestones/<m>/loops/<c>/SPEC.md`. (SPEC 작성은 spec 스킬 사용: Skill(skill: "spec", args: "<task-id>"))
3. Project Status를 Blocked에서 In Progress로 전이 후 재시작

## architecture-gap (코드 구조 변경 필요)

증상: 현재 코드 구조로 task 해결 불가. 더 큰 design 결정 필요.

처리:
1. 본 task는 정지하고 사람이 architecture 작업 (별도 task로 분리)
2. architecture 작업 완료 후 본 task의 SPEC.md scope 조정
3. 또는 본 task를 cleanup하고 새 task로 재시작

## environment-gap (외부 시스템 일시 문제)

증상: API rate limit, 네트워크, 외부 서비스 다운 등.

처리:
1. 외부 시스템 상태 확인
2. 일시적 문제면 시간 후 재시작
3. 영구적 문제면 mock·테스트 더블로 우회 또는 spec 조정

## other

증상: 위 4종에 안 맞는 케이스.

처리: `[blocked]` comment 본문 내용 검토 후 사람의 판단.

## halt 발생 시 stash 확인

drive가 자동 정지(halt)할 때 워크트리의 미커밋 변경은 자동 stash됨. 워크트리 들어가서 `git stash list`로 확인, 필요 시 `git stash pop`으로 복원.

## v0.1 → v0.2 마이그레이션 (`.loops/` 잔존 정리)

v0.2 cutover로 워크트리·lock·SPEC이 모두 `milestones/<m>/loops/<c>/` 단일 트리로 이동했습니다. 기존 `.loops/` 디렉터리에 in-flight SPEC·stale lock이 남아 있을 수 있으나, 새 코드는 이를 감지·자동 이동하지 않습니다 — 사용자가 수동으로 처리:

1. **활성 task 정지·머지**: 진행 중이던 task가 있으면 v0.1 환경(`loop stop <task-id>` 후 그 시점 워크트리에서 변경 머지)에서 종결합니다.
2. **SPEC 이전**: `.loops/<task-id>/SPEC.md` 내용을 `milestones/regular/loops/<task-id>/SPEC.md`로 이동 (`mkdir -p milestones/regular/loops/<task-id> && mv .loops/<task-id>/SPEC.md $_/`)
3. **stale lock 제거**: `.loops/locks/*.lock`는 모두 안전하게 삭제 (`rm -f .loops/locks/*.lock`)
4. **빈 디렉터리 제거**: `rm -rf .loops/`
5. **외부 sibling 워크트리**: 기존 `<project>-loops/` 가 있다면 `git worktree list`로 확인 후 `git worktree remove`로 정리하고 디렉터리 삭제

`.gitignore`의 새 패턴은 첫 `loop start` 호출 시 자동 정렬됩니다.
