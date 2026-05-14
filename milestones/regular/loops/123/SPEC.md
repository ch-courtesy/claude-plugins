---
scope:
  include: ["plugins/autopilot/skills/loop/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "S=plugins/autopilot/skills/loop; test -f $S/references/rebase-phase.sh && test -f $S/references/review-fix-phase.sh && test -f $S/references/cleanup-phase.sh && grep -qE 'merged|closed' $S/references/review-fix-phase.sh && grep -qE 'APPROVED' $S/references/review-fix-phase.sh && grep -qE '/done|합격|통과' $S/references/review-fix-phase.sh && grep -q 'sleep' $S/references/review-fix-phase.sh && grep -q 'rebase' $S/references/rebase-phase.sh && grep -q 'worktree remove' $S/references/cleanup-phase.sh && grep -qE 'branch -D|push --delete' $S/references/cleanup-phase.sh && grep -qE 'review-fix-phase|rebase-phase|cleanup-phase' $S/references/loop.sh && grep -q 'gh project item-edit' $S/references/loop.sh $S/references/review-fix-phase.sh $S/references/cleanup-phase.sh && grep -q 'gh pr merge' $S/references/review-fix-phase.sh && grep -q 'gh pr comment' $S/references/review-fix-phase.sh && grep -qE '반박|dispute' $S/references/review-fix-phase.sh && grep -qE 'allowed-tools|--allowed-tools' $S/references/loop.sh && grep -qE 'review-fix|rebase|cleanup' $S/SKILL.md && grep -qE '상태 전이|Status' $S/SKILL.md && grep -qE '자동 머지|auto[- ]?merge' $S/SKILL.md"
ears_language: ko
request_review: true
---

# autopilot:loop — DONE 이후 PR 리뷰 자동 fix 루프 + Monitor 가설

## 무엇을 만들 것인가

autopilot:loop의 PR 관련 phase를 확장해 DONE 이후 PR 생애주기 전체를 자동화한다.
SPEC frontmatter `request_review: true` opt-in이 활성화되면 다음 sub-phase들이
순차·일부 background로 구동된다:

1. **pre-PR rebase** — default에서 feat 브랜치 rebase. conflict 시 claude CLI
   자동 해소 시도, 실패 시 ESCALATION abort.
2. **PR 생성** — push, 신규 PR 생성 또는 동일 head의 open PR 갱신.
3. **태스크 상태 전이 (→ 리뷰 관련 상태)** — PR 생성·재사용 성공 시 외부 태스크
   추적 시스템의 *추상 상태*를 "리뷰 관련 상태"로 전이. 구체 값·백킹
   시스템·매핑은 `rules/context.md` 단일 출처에 의존.
4. **review-fix 루프 (background)** — 30초 주기 폴링 (PR-level comments ·
   review threads · review summary). 새 이벤트마다: 매 fix iter 직전 default
   재-rebase, claude CLI 세션으로 fix, 코드 변경 시 commit+push, "리뷰어 틀렸다"
   판명 시 반박 코멘트 1개 게시 (그 외 일체 게시 금지), 새 이벤트·종료 신호를
   stdout 으로 emit.
5. **자동 머지 (조건부)** — 종료 신호가 merged가 *아닌* PR 승인 또는 owner의
   종료 코멘트(`/done`·`합격`·`통과`)로 들어오면 시스템이 `gh pr merge`로
   직접 머지.
6. **cleanup** — 로컬 worktree 제거 + 로컬 feat 삭제 + origin feat 삭제.
7. **태스크 상태 전이 (→ 완료 관련 상태)** — cleanup 0 exit 이후 추상 상태를
   "완료 관련 상태"로 전이. 구체 값·매핑 `rules/context.md` 의존.

PR이 closed (merge 안 됨)로 전이한 경우 review-fix 이후 모든 단계(자동 머지·
cleanup·상태 전이)를 생략한다 — 사용자 판단 대기.

본 phase 그룹의 명령 실행에 필요한 도구 권한은 autopilot 워커의 allowed-tools에
**범위 최소화 원칙**으로 등록된다:

- **GitHub CLI**: 본 phase가 실제 호출하는 PR 관련 서브커맨드만 허용 —
  `gh pr merge`, `gh pr comment`, `gh pr view`, `gh api repos/.../pulls/*` ·
  `repos/.../issues/*/comments` (폴링용). `gh issue *`, `gh repo *` 등
  PR과 무관한 명령은 등록 안 함.
- **GitHub Project**: 본 phase가 사용하는 정확한 명령(`gh project item-edit`)
  만 포인트로 허용.
- **Git**: 본 phase가 호출하는 정확한 서브커맨드만 — `git rebase`,
  `git push --delete`, `git branch -D`, `git worktree remove`. 그 외 일체
  와일드카드 등록 금지.

등록 범위는 autopilot 워커의 실행 컨텍스트에만 한정되며 사용자 대화형
세션의 settings.json은 건드리지 않는다 (메모리 feedback_allowlist_exclude_github
유지).

## 수용 기준 (EARS)

1. (Event-driven) PR phase 진입 직전, 시스템은 default 브랜치에서 워크트리의
   현재 feat 브랜치를 rebase한다.

2. (Unwanted) rebase가 conflict로 실패하면, 시스템은 claude CLI 세션을 호출해
   자동 해소를 시도한다. 세션이 해소에 실패하면 ESCALATION을 stdout으로
   기록하고 phase를 중단한다.

3. (Event-driven) pre-PR rebase가 0 exit으로 끝나면, 시스템은 push → PR
   생성·재사용 단계를 그대로 수행한다.

4. (Event-driven) PR 생성·재사용이 성공하면, 시스템은 review-fix 루프를
   background로 시작한다.

5. (State-driven) review-fix 루프가 가동 중인 동안, 시스템은 30초 주기로
   PR-level comments · review threads (inline) · review summary 세 소스를
   폴링해 이전에 본 적 없는 항목을 새 이벤트로 분류한다.

6. (Event-driven) 새 이벤트가 분류되면, 시스템은 그 이벤트의 요약 한 줄을
   stdout으로 출력한다.

7. (Event-driven) 새 이벤트가 분류되면, 시스템은 fix iter 직전에 default
   브랜치에서 워크트리의 feat 브랜치를 재-rebase한다 (AC#1·#2 절차 동일).

8. (Event-driven) 재-rebase가 끝나면, 시스템은 수집된 입력을 claude CLI에
   전달해 fix 세션을 시작한다.

9. (Event-driven) fix 세션이 코드 변경을 남기면, 시스템은 변경을
   commit + push한다.

10. (Event-driven) fix 세션이 "리뷰어가 틀렸다" 판명 시, 시스템은 그 판단
    본문을 1개의 반박 코멘트로 PR에 게시한다.

11. (Ubiquitous) 시스템은 AC#10 외 어떤 GitHub 게시도 수행하지 않는다
    (inline reply, summary comment, title/description 편집, review reply 등).

12. (Event-driven) PR 생성·재사용 성공 시, 시스템은 외부 태스크 추적
    시스템의 *추상 상태*를 "리뷰 관련 상태"로 전이한다. 구체 값·
    시스템 매핑은 `rules/context.md` 단일 출처에 의존한다.

13. (Unwanted) PR이 merged로 전이하면, 시스템은 review-fix 루프를
    종료하고 자동 머지를 건너뛰어 cleanup으로 진입한다.

14. (Event-driven) 종료 신호가 PR 승인 상태 또는 owner 코멘트
    `/done`·`합격`·`통과` 중 하나이고 PR이 merged가 아닌 상태면,
    시스템은 `gh pr merge`로 PR을 머지한다.

15. (Unwanted) PR이 closed (merge 안 됨)로 전이하면, 시스템은 review-fix
    이후 모든 단계(자동 머지·cleanup·상태 전이)를 생략한다.

16. (Event-driven) PR이 merged 상태가 되면 (자동 머지 포함), 시스템은
    cleanup phase에서 로컬 worktree, 로컬 feat 브랜치, origin feat 브랜치를
    차례로 제거한다.

17. (Event-driven) cleanup이 0 exit으로 끝나면, 시스템은 추상 상태를
    "완료 관련 상태"로 전이한다. 구체 값·매핑은 `rules/context.md`
    단일 출처에 의존한다.

18. (Ubiquitous) 시스템은 본 phase 그룹의 도구 권한을 autopilot 워커의
    allowed-tools에 **범위 최소화 원칙**으로 등록한다 — PR 관련
    gh 서브커맨드(`gh pr merge`·`gh pr comment`·`gh pr view`·
    `gh api repos/.../pulls/*` · `repos/.../issues/*/comments`),
    `gh project item-edit`, `git rebase`·`git push --delete`·`git branch -D`·
    `git worktree remove`만 등록하고 그 외 와일드카드 등록을 금지한다.

19. (Unwanted) 본 phase 그룹의 어느 명령이 비-zero exit으로 실패하면,
    시스템은 "ESCALATION" prefix 한 줄을 stdout으로 출력하고 해당
    phase를 중단한다.

## 범위

포함:
- `plugins/autopilot/skills/loop/references/rebase-phase.sh` 신규 —
  default에서 feat 브랜치 rebase + conflict claude 자동 해소 시도.
- `plugins/autopilot/skills/loop/references/review-fix-phase.sh` 신규 —
  폴링·이벤트 분류·재-rebase 호출·fix iter dispatch·반박 코멘트
  게시·자동 머지·종료 검사·stdout event emit.
- `plugins/autopilot/skills/loop/references/cleanup-phase.sh` 신규 —
  로컬 worktree 제거 + 로컬 feat 삭제 + origin feat 삭제.
- 상태 전이 (→ 리뷰/완료 관련) 구현: 독립 스크립트로 분리하거나
  공용 셸 함수로. 구체 값·매핑은 `rules/context.md` 읽어 해석.
- `plugins/autopilot/skills/loop/references/loop.sh` 갱신 — `request_review:
  true` opt-in 시 rebase→PR→상태:리뷰→review-fix→(조건부 merge)→cleanup→
  상태:완료 자동 연결.
- `plugins/autopilot/skills/loop/references/pr-phase.sh` 갱신 — pre-PR rebase
  호출 연결 (또는 caller(loop.sh) 책임).
- `plugins/autopilot/skills/loop/SKILL.md` 갱신 — 상태 전이 규제·
  새 phase 구조·allowed-tools 목록 문서화.
- autopilot 워커의 allowed-tools 설정 소스 갱신 — 구현자가 현행
  loop.sh 구조에서 소스 위치(claude CLI 호출 플래그 또는 설정 파일)
  를 식별해 그 곳에 AC#18 목록 정확 등록.

비-목표 / 제외:
- SPEC frontmatter 추가 opt-in 키 (`request_review: true` 단일).
- 리뷰 코멘트 분류기 — 새 이벤트 일괄 fix dispatch.
- PR closed (merge 안) 자동 cleanup·상태 전이 — 사용자 판단.
- review-fix wall-clock·iter 한계 (추후 개선).
- branch protection bypass, force-push (필요 시 `--force-with-lease` 한정).
- AC#10 이외 어떤 코멘트·게시.
- 사용자 대화형 세션의 settings.json `permissions.allow` 권한 변경 —
  메모리 feedback_allowlist_exclude_github 유지 (별도 경로).
- `rules/context.md`의 상태 어휘 갱신 — 메타 상태는 이미 정의되어 있음.
- 본 저장소의 `rules/`·`milestones/`·`CLAUDE.md` (default exclude).

## 검증
이 명령이 0 exit으로 끝나야 합니다:
```bash
S=plugins/autopilot/skills/loop
test -f $S/references/rebase-phase.sh \
 && test -f $S/references/review-fix-phase.sh \
 && test -f $S/references/cleanup-phase.sh \
 && grep -qE 'merged|closed'             $S/references/review-fix-phase.sh \
 && grep -qE 'APPROVED'                  $S/references/review-fix-phase.sh \
 && grep -qE '/done|합격|통과'           $S/references/review-fix-phase.sh \
 && grep -q  'sleep'                     $S/references/review-fix-phase.sh \
 && grep -q  'rebase'                    $S/references/rebase-phase.sh \
 && grep -q  'worktree remove'           $S/references/cleanup-phase.sh \
 && grep -qE 'branch -D|push --delete'   $S/references/cleanup-phase.sh \
 && grep -qE 'review-fix-phase|rebase-phase|cleanup-phase' $S/references/loop.sh \
 && grep -q  'gh project item-edit'      $S/references/loop.sh \
       $S/references/review-fix-phase.sh \
       $S/references/cleanup-phase.sh \
 && grep -q  'gh pr merge'               $S/references/review-fix-phase.sh \
 && grep -q  'gh pr comment'             $S/references/review-fix-phase.sh \
 && grep -qE '반박|dispute'              $S/references/review-fix-phase.sh \
 && grep -qE 'allowed-tools|--allowed-tools' $S/references/loop.sh \
 && grep -qE 'review-fix|rebase|cleanup' $S/SKILL.md \
 && grep -qE '상태 전이|Status'          $S/SKILL.md \
 && grep -qE '자동 머지|auto[- ]?merge'  $S/SKILL.md
```

## 제약
- 의존성: `gh` CLI + OAuth (push:write·repo:status 스코프), `claude` CLI,
  `jq` (gh JSON 파싱 — 신규 의존성 추가 가능).
- 폴링 주기 30초; 환경 변수(예: `LOOP_REVIEW_POLL_SECS`) override 권장.
- review-fix 루프는 background process (loop.sh의 자식·disown·`&`).
- 코멘트 게시는 AC#10의 반박 1건 외 일체 금지.
- allowed-tools 등록 범위: PR 관련 gh 서브커맨드 + 명시된 gh project/git
  서브커맨드만, 와일드카드(`gh *`, `git *`) 금지.
- 메모리 갱신 (별도 follow-up 작업으로 처리):
  - `feedback_pr_review_no_reply` → "반박 1건 예외 허용"으로
  - `feedback_allowlist_exclude_github` → "사용자 대화형 세션 한정;
    autopilot 워커는 범위 최소로 허용"으로

## 위험
- **무한 루프**: 종료 4조건 모두 실패 + 새 코멘트가 계속 도착하면 무한
  fix 가능. fail-safe로 wall-clock cutoff·iter 최대치 추후 추가.
- **폴링 중복 트리거**: 동일 코멘트가 매 폴링마다 재등장하지 않도록
  last-seen ID dedup 필수.
- **conflict 자동 해소 의도 밖 변경**: claude 세션이 rebase 충돌
  해소 중 무관한 코드를 만질 가능성. 해소 후 verify 게이트 재실행 권장.
- **반박 false-positive**: claude 세션이 잘못 반박해 부적절 코멘트
  게시. owner의 명시 cancel signal 매커니즘 후속 개선.
- **자동 머지 실패**: conflict·CI 실패·branch protection 수부로 실패
  가능. 실패 시 review-fix를 그대로 유지하면 사용자가 수동 머지 가능.
- **cleanup 손실**: 워크트리에 미커밋 변경 있을 때 cleanup 손실 위험.
  cleanup 전 `git status --porcelain` 검사 후 비-empty면 abort 필요.
- **권한 확장 세고**: allowed-tools가 사용자 대화형 세션 settings.json
  으로 새지 않도록 계층 분리 명확·구현자가 수동 확인 필요.
