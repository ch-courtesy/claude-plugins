---
scope:
  include: ["plugins/autopilot/skills/loop/SKILL.md", "tests/autopilot/test-skill-allow-tools.sh"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash tests/autopilot/test-skill-allow-tools.sh"
request_review: true
test_sweep_paths:
  - "tests/autopilot/test-skill-allow-tools.sh"
---

# loop SKILL.md allow-tools 확장 + 테스트 LOOP_REQ 싱크

## 무엇을 만들 것인가
loop 스킬 운용 중 사용자 세션에서 권한 prompt를 일으키는 명령 패턴을 `plugins/autopilot/skills/loop/SKILL.md` frontmatter `allowed-tools` 배열에 추가하고, 그 새 패턴들을 `tests/autopilot/test-skill-allow-tools.sh`의 `LOOP_REQ` 상수 배열에도 동일하게 반영해 AC8 검증이 누락을 catch하게 한다. 추가 대상 3 범주: (1) sub-phase 스크립트 직호출 (review-fix-phase·rebase-phase·cleanup-phase) — loop.sh가 보통 자동 호출하지만 user manual invocation 시 prompt 발생을 차단, (2) loop 오케스트레이션·복구에 필요한 일반 git 명령 (fetch·push·rebase·switch·cherry-pick·worktree·branch·reset·revert·stash·checkout·diff·log·show·status·rev-parse·rev-list·merge-base·show-ref·ls-files·ls-remote·commit·pull), (3) python3 inline (issue body sync 등 보조 작업). gh 관련은 메모리 규약 `feedback_allowlist_exclude_github`에 따라 `gh pr view`·`gh pr checks` read-only만 예외 허용하고 그 외는 제외. 다른 파일(loop.sh·다른 스킬·user-scope settings)은 변경하지 않는다.

## 수용 기준 (EARS)
- **AC1 (Ubiquitous)**: `plugins/autopilot/skills/loop/SKILL.md` frontmatter `allowed-tools` 배열에 sub-phase 직호출 패턴 3개 (review-fix-phase·rebase-phase·cleanup-phase)가 포함된다.
- **AC2 (Ubiquitous)**: 동 배열에 일반 git 명령 패턴 (fetch·push·rebase·switch·cherry-pick·worktree·branch·reset·revert·stash·checkout·diff·log·show·status·rev-parse·rev-list·merge-base·show-ref·ls-files·ls-remote·commit·pull)이 SPEC 170 형식 `:*` trailing wildcard로 포함된다.
- **AC3 (Ubiquitous)**: 동 배열에 `Bash(python3 -c:*)` 또는 동등 패턴이 포함된다.
- **AC4 (Unwanted/조건)**: 동 배열은 `Bash(gh pr view:*)`·`Bash(gh pr checks:*)` 이외의 `Bash(gh:*)` 패턴을 포함하지 않는다.
- **AC5 (Ubiquitous)**: `tests/autopilot/test-skill-allow-tools.sh`의 `LOOP_REQ` 또는 동등 상수 배열에 AC1·AC2·AC3의 새 패턴들이 모두 등재되어 AC8 검증이 누락을 catch한다.
- **AC6 (Ubiquitous)**: `bash tests/autopilot/test-skill-allow-tools.sh`가 0 exit으로 끝난다 (기존 AC1–AC8 전부 통과 — catch-all 금지·gh 제외·중복 없음·기존 기준 패턴 존재).

## 범위
포함:
- `plugins/autopilot/skills/loop/SKILL.md` — frontmatter `allowed-tools` 배열에 3 범주 패턴 추가.
- `tests/autopilot/test-skill-allow-tools.sh` — `LOOP_REQ` 상수 배열에 새 패턴들 추가해 AC8이 누락을 catch하도록 강제.

비-목표 / 제외:
- `plugins/autopilot/skills/loop/references/*.sh` 수정 (loop.sh·review-fix-phase.sh·rebase-phase.sh·cleanup-phase.sh 등 명령 로직 불변).
- `plugins/autopilot/skills/spec/SKILL.md` 또는 다른 스킬 frontmatter 변경.
- gh 일반 명령 (`gh issue *`·`gh project *`·`gh pr create`·`gh pr merge` 등) 허용 — `gh pr view`·`gh pr checks` read-only만 예외.
- user-scope `~/.claude/settings.json` 변경.
- `.claude/settings.json` 또는 `.claude/settings.local.json` 변경 (project skill-scope만 대상).

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```
bash tests/autopilot/test-skill-allow-tools.sh
```

## 제약 (있을 때만)
- 패턴 형식: SPEC 170 정규화 `:*` trailing wildcard. 공백+별표 ` *` 형식 금지 (정규화 이전 형식).
- gh 관련 제외·허용 규칙: 메모리 `feedback_allowlist_exclude_github` 명시 — settings.json scope는 모든 gh 제외, skill-scope에서는 `gh pr view`·`gh pr checks` read-only만 예외.
- `LOOP_REQ` 배열 동일 항목·철자로 동기화 필수 — AC8이 ID 비교로 일대일 매칭하므로 drift 시 fail.
- 자체-재귀 (`feedback_no_self_apply_during_spec`): 본 SPEC을 작성·수행하는 세션은 새 권한이 아직 머지되지 않은 상태라 prompt가 발생할 수 있다 — 새 권한은 본 SPEC PR 머지 이후의 다음 spec/loop 호출부터 적용된다.

## 위험 (있을 때만)
- **와일드카드 투과 이슈**: 예) `Bash(git push:*)`이 `git push --force`도 매칭 — 의도된 동작이나 보안 surface 증가. 필요 시 더 세분화된 패턴으로 후속 갱신 가능.
- **`Bash(python3 -c:*)` 임의 실행 허용**: inline 스크립트가 파일시스템 변경 가능. loop 세션 운영 범주 내 필요해 수용.
- **SKILL.md ↔ 테스트 drift**: `LOOP_REQ`와 SKILL.md `allowed-tools`가 어긋나면 AC5/AC6 fail. 동시 수정·single commit으로 완화.
- **테스트의 frozen reference**: `LOOP_REQ`는 issue #113 시점 패턴을 기준으로 했음. 새 패턴은 추가되는 것이지 기존을 교체하는 것이 아님 — 하위 호환 유지.
