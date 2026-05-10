# ESCALATION 카테고리별 처리 가이드

ESCALATION.md의 `**카테고리**` 필드 별 사람의 처리 권장 흐름.

## config-gap (환경 설정·도구 부재)

증상: 도구 미설치, 자격증명 부재, 환경 변수 누락 등.

처리:
1. ESCALATION.md 본문 읽고 missing item 식별
2. target 프로젝트 환경 조정 (도구 설치, env var 설정 등)
3. `rm .loops/<task-id>/.../ESCALATION.md` 또는 워크트리 안으로 들어가서 정리
4. `start <task-id>` 또는 watch 모드면 자동 재개

## spec-gap (SPEC.md 결함)

증상: 모호한 수용 기준, 검증 명령 부적합, scope 정의 미흡 등.

처리:
1. ESCALATION.md의 "필요한 결정" 섹션 검토
2. `<worktree>/.loop/SPEC.md` 직접 수정 (prepare 서브커맨드는 deprecated이며 SPEC 작성은 spec 스킬 사용: Skill(skill: "spec", args: "<task-id>"))
3. ESCALATION.md 정리 후 재시작

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

처리: ESCALATION.md 본문 내용 검토 후 사람의 판단.

## halt 발생 시 stash 확인

drive가 자동 정지(halt)할 때 워크트리의 미커밋 변경은 자동 stash됨. 워크트리 들어가서 `git stash list`로 확인, 필요 시 `git stash pop`으로 복원.
