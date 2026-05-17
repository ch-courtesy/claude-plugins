---
scope:
  include: ["plugins/autopilot/skills/loop/references/review-fix-phase.sh"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash -c 'set -e; F=plugins/autopilot/skills/loop/references/review-fix-phase.sh; test -f \"$F\" && bash -n \"$F\" && ! grep -qE \"reviewThreads\" \"$F\" && grep -qE \"stuck|consecutive[-_]idle|silent[-_]fail\" \"$F\"'"
ears_language: ko
---

# review-fix-phase: reviewThreads 의존 제거 + silent-fail 감지

## 무엇을 만들 것인가

`autopilot:loop`의 review-fix-phase는 PR 리뷰 이벤트 세 소스(PR-level conversation comments, review summaries, review thread inline comments)를 폴링으로 수집해 새 이벤트마다 fix 이터를 dispatch한다. 현재 구현은 단일 `gh pr view --json reviews,reviewThreads,comments` 호출로 세 소스를 동시에 fetch하지만, `reviewThreads` JSON 필드는 일부 gh CLI 버전(현재 사용자 환경 포함)에서 지원되지 않아 호출 전체가 비-zero exit으로 실패한다. 실패 시 코드는 `|| echo '{}'` 패턴으로 빈 JSON으로 대체하므로 `collect_new_events`는 모든 이벤트 ID를 0개로 판정하고, 폴링 루프는 silent로 계속 돌면서 fix를 영원히 시작하지 않는다.

본 task는 두 가지를 함께 변경한다:

1. **reviewThreads JSON 필드 의존 제거** — review thread inline comments 수집을 `gh pr view --json reviewThreads`가 아닌 다른 gh CLI 호환 매체로 우회한다. PR-level comments와 review summaries 수집은 호환성 영향이 없으므로 그대로 유지하되, 세 소스를 *각각 독립 호출*로 분리해 한 소스의 fetch 실패가 다른 소스 수집을 차단하지 않게 한다.

2. **silent-fail 감지·escalation** — review-fix-phase 폴링이 의도하지 않게 silent로 도는 패턴(예: gh CLI 호출 실패가 fallback으로 묻혀 새 이벤트 0건으로 잘못 판정되거나, PR check가 완료됐는데도 리뷰 코멘트·완료 코멘트 모두 부재 상태로 연속 폴링이 idle)을 명시적으로 감지해 `ESCALATION` 토큰을 stdout으로 emit한다. 한 번이 아닌 *연속 N회* 임계로 false positive를 줄인다.

두 변경은 같은 의도다 — review-fix-phase가 silent로 머물지 않고 fix 흐름을 시작하거나 명시적으로 실패를 보고하도록 만든다.

## 수용 기준 (EARS)

1. `plugins/autopilot/skills/loop/references/review-fix-phase.sh`가 존재할 때, 시스템은 본 파일 내 `reviewThreads` JSON 필드 참조를 모두 제거하고, `gh pr view --json reviewThreads` 호출 의존을 본문에서 모두 없앤다.
2. review-fix-phase가 폴링하는 동안 연속 N회(N은 본 task 내부에서 결정, 최소 3 이상) 새 이벤트가 0건이면, 시스템은 stuck 진단을 수행해 silent-fail 패턴(세 이벤트 fetch 호출 중 어느 하나라도 비-zero exit으로 실패한 경우 또는 PR check 완료 + 리뷰 코멘트 부재 + owner cmd 부재) 감지 시 `ESCALATION` 토큰을 stdout으로 emit한다.

## 범위

포함:

- `review-fix-phase.sh`의 `collect_new_events` 재구성 — `reviewThreads` JSON 필드 의존 제거, 세 소스(PR-level comments·review summaries·review thread inline comments)를 *각각 독립 호출*로 분리
- `review-fix-phase.sh` 폴링 루프에 silent-fail 감지·`ESCALATION` emit 로직 추가

비-목표 / 제외:

- 다른 phase script(`pr-phase.sh`·`rebase-phase.sh`·`cleanup-phase.sh`) 변경
- 워커 헌법(`constitution.md`) 변경
- `loop.sh`의 검출 로직 (SPEC 134·150 그대로)
- gh CLI 버전 자동 감지·강제 upgrade
- review thread 수집의 GraphQL 호출 신설 (`gh api graphql`) — REST endpoint로 충분
- DISPUTE 코멘트 게시 정책 변경
- silent-fail 외 escalation 채널(notification·webhook 등) 추가

## 검증

이 명령이 0 exit으로 끝나야 합니다:

```bash
bash -c 'set -e; F=plugins/autopilot/skills/loop/references/review-fix-phase.sh; test -f "$F" && bash -n "$F" && ! grep -qE "reviewThreads" "$F" && grep -qE "stuck|consecutive[-_]idle|silent[-_]fail" "$F"'
```

## 제약

- 세 이벤트 소스 수집을 *각각 독립 호출*로 분리해 한 소스 fetch 실패가 다른 소스를 차단하지 않게 한다 — verify 명령으로 직접 검증되지 않으므로 본 제약으로 보강.
- review thread inline comments 수집은 `gh pr view --json reviewThreads` 대신 gh CLI 호환 endpoint(예: `gh api repos/{owner}/{repo}/pulls/{n}/comments`)로 우회한다. `gh api graphql` 호출은 비-목표.
- silent-fail 감지의 연속 임계 N은 본 task 내부에서 결정하되 3 이상으로 설정해 false positive를 줄인다.
- 기존 SEEN_FILE의 ID prefix 컨벤션(`comment:`·`review:`·`thread:`)은 세 소스 호출 분리 후에도 유지해 dedup이 손상되지 않게 한다.
- 본 task가 `review-fix-phase.sh`를 수정하는 동안 sibling 파일(다른 phase script·헌법 등)을 수정하지 않는다 — `scope.include`가 `review-fix-phase.sh` 단일 파일이므로 다른 파일 변경은 워크플로 게이트에서 차단된다.
- `feedback_no_self_apply_during_spec` 룰: 본 SPEC을 작성하는 *현재* spec 호출은 review-fix-phase.sh를 변경하지 않는다 — 변경은 loop 실행 시점.
- `feedback_self_referential_verification` 룰: 워커는 verify·worktree source(직접 변경한 review-fix-phase.sh)만 검사하고, runtime artifact(자기 task의 PR 코멘트·자기 review-fix 실행 결과)는 검증 대상에서 제외.

## 위험

- **stuck 감지 false positive**: PR이 자연 idle(아무도 리뷰 안 함, owner도 cmd 안 보냄)인 경우도 stuck으로 분류되어 ESCALATION emit 가능. silent-fail 감지 조건을 명확히 분리해야 함 — fetch 호출 실패와 PR 자연 idle은 구분해 처리.
- **gh CLI REST endpoint 의존**: `gh api repos/.../pulls/{n}/comments`도 gh CLI 버전·토큰 권한에 따라 실패 가능. 본 SPEC은 REST 호출 실패도 silent-fail 감지의 한 패턴으로 다루며 자기 복구는 안 함.
- **dedup 의미 변화 위험**: 세 소스 호출 분리 후에도 SEEN_FILE의 ID prefix(`comment:`·`review:`·`thread:`)가 유지되지 않으면 같은 이벤트가 다른 prefix로 dedup 미스되어 재진입.
- **다른 silent-fail 패턴**: 본 SPEC은 `collect_new_events`·폴링 루프 silent-fail만 다룬다. owner cmd 검사 등 다른 위치의 silent-fail은 별도 SPEC 필요.
- **self-referential 함정 (낮음)**: 본 task의 워커가 review-fix-phase.sh를 변경하면서 같은 review-fix-phase로 자기 PR 리뷰를 처리하지는 않는다 — review-fix-phase는 `request_review: true` opt-in이며 본 SPEC frontmatter에서 별도 결정. PR 리뷰 자동 fix를 본 SPEC에서 사용할지 여부와 무관하게 verify는 정적 grep으로 fail 가능하므로 self-referential 위험은 SPEC 150보다 현저히 낮다.
