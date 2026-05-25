---
name: loop
description: 자율 수행 루프(랄프 루프) 운영 인터페이스. start/status/stop/list/cleanup/logs 서브커맨드로 자율 task의 lifecycle을 관리합니다. SPEC 작성은 별도 'autopilot:spec' 스킬을 사용.
allowed-tools:
  - Monitor
  - Read
  - Bash(bash * loop.sh start:*)
  - Bash(bash * loop.sh status:*)
  - Bash(bash * loop.sh stop:*)
  - Bash(bash * loop.sh list)
  - Bash(bash * loop.sh cleanup:*)
  - Bash(bash * loop.sh logs:*)
  - Bash(bash * review-fix-phase.sh:*)
  - Bash(bash * rebase-phase.sh:*)
  - Bash(bash * cleanup-phase.sh:*)
  - Bash(git -C * stash list)
  - Bash(git -C * stash pop:*)
  - Bash(git -C * stash show:*)
  - Bash(git fetch:*)
  - Bash(git push:*)
  - Bash(git rebase:*)
  - Bash(git switch:*)
  - Bash(git cherry-pick:*)
  - Bash(git worktree:*)
  - Bash(git branch:*)
  - Bash(git reset:*)
  - Bash(git revert:*)
  - Bash(git stash:*)
  - Bash(git checkout:*)
  - Bash(git diff:*)
  - Bash(git log:*)
  - Bash(git show:*)
  - Bash(git status:*)
  - Bash(git rev-parse:*)
  - Bash(git rev-list:*)
  - Bash(git merge-base:*)
  - Bash(git show-ref:*)
  - Bash(git ls-files:*)
  - Bash(git ls-remote:*)
  - Bash(git commit:*)
  - Bash(git pull:*)
  - Bash(python3 -c:*)
  - Bash(ps -p:*)
  - Bash(cat */*.lock)
  - Bash(gh pr view:*)
  - Bash(gh pr checks:*)
---

# loop

자율 task lifecycle을 관리한다. 상태·락·워크트리·SPEC은 target 프로젝트의 `milestones/<m>/loops/<c>/` 아래에 둔다. 단일 컴포넌트 task-id는 `regular/<id>`로 정규화한다. 워커 헌법은 `references/constitution.md`, 셸 드라이버는 `references/loop.sh`, 백엔드 매핑은 target의 `rules/context.md`가 단일 출처다.

## 호출

`Skill(skill: "loop", args: "<subcommand> [<args>]")`

SPEC 작성은 `autopilot:spec`에서 한다: `Skill(skill: "spec", args: "<task-id>")`.

## Subcommands

### start <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>] [--no-monitor] [--events-only] [--no-pr]

반드시 `Bash(bash $SKILL_DIR/references/loop.sh start <task-id> [...flags], run_in_background: true)`로 실행한다. 동기 실행은 Monitor 가설을 막으므로 금지.

driver 검증·동작: `--spec` 파일 복사, canonical SPEC 존재, `[NEEDS CLARIFICATION]`·placeholder 부재, lock 미보유, lock 획득, 이터레이션 루프. 주 작업트리에서는 nested `.worktree/`를 만들고 헌법을 CLAUDE.md로 복사한다. 보조 worktree 안에서는 nested worktree 생성을 생략/skip하고 현재 cwd를 작업 공간으로 쓴다. 안전 검사는 동일하다.

#### Monitor

기본 ON. `--no-monitor`가 없으면 start 직후 `Monitor`를 붙인다. 기본 필터는 빈 줄과 단독 dot만 제외하고 stdout raw 라인을 통과시킨다. `--events-only`는 SKILL.md 차원 옵션이며 `loop.sh`로 전달하지 않는다. 이 플래그는 핵심 이벤트(`이터 #`, HALT, WARN, FAIL, ERROR, rate limit, claude 비정상, 에스컬레이션, 완료 신호)만 알림한다. `--no-monitor`와 함께 있으면 `--no-monitor`가 우선한다.

### 완료 후 PR phase (default)

DONE 라벨 감지 후 `--no-pr`가 없으면 같은 worktree에서 PR 생성 또는 동일 head branch open PR 재사용을 실행한다. 흐름은 default branch 감지, base sync(`references/rebase-phase.sh`), force push 금지, push, PR create/edit, PR URL과 `PR state: open` stdout 출력, worktree·local branch 보존이다. reviewer·label·assignee는 설정하지 않는다. PR body 자동 영역은 `<!-- autopilot:pr-body:begin --> ... <!-- autopilot:pr-body:end -->` fence 안에만 쓴다.

PR check Monitor는 OPEN이고 reviewDecision이 없으며 모든 checks가 완료된 stuck 상태면 `gh pr checks <num> --rerun`을 최대 3회 호출한다. MERGED/CLOSED 또는 reviewDecision set이면 종료한다. MERGED/CLOSED 감지 시 cleanup 후보를 안내하고, 본 스킬 호출자는 사용자 명시 승인 후에만 `cleanup`을 호출한다. 자동 삭제 금지.

### review-fix phase (`request_review: true`)

SPEC frontmatter `request_review: true`일 때 PR 생성·재사용 후 review-fix를 실행한다. 단계: pre-PR sync(`rebase-phase.sh`) -> review-fix polling(`review-fix-phase.sh`) -> 승인 또는 owner 종료 코멘트(`/done`, `합격`, `통과`) 시 자동 머지(auto-merge) -> merged 후 cleanup(`cleanup-phase.sh`). 상태 전이: PR 생성·재사용 성공 후 `review`, cleanup 성공 후 `done`. 구체 명령·라벨 매핑은 `rules/context.md`.

게시 제약: 리뷰어가 틀린 경우 dispute 코멘트 1개만 허용한다. inline reply, summary comment, title/body 편집 등 다른 GitHub 게시 금지.

review-fix 워커 allowed-tools는 `loop.sh`의 `AUTOPILOT_REVIEW_FIX_ALLOWED_TOOLS`와 `AUTOPILOT_REBASE_ALLOWED_TOOLS` 상수를 따른다. silent-fail 관련 환경변수: `LOOP_REVIEW_IDLE_THRESHOLD` 기본 3/floor 3, `LOOP_REVIEW_PR_GRACE_SECS` 기본 300/floor 0. checks 수가 0이면 ESCALATION하지 않고 카운터를 리셋한다.

### status / stop / list / cleanup / logs

각각 `Bash(bash $SKILL_DIR/references/loop.sh <subcommand> [args])`로 위임하고 결과를 요약한다. `status` 형식은 `references/status-format.md`.

## 첫 호출 setup

start 첫 호출은 `.gitignore`에 `milestones/**/loops/**/.worktree/`, `milestones/**/loops/**/.lock`을 보장하고 legacy `.loops/locks/` 라인을 제거한다. 이 변경은 `.gitignore` 단독 chore commit으로 격리한다. 실패하면 worktree·lock 생성을 중단한다.

## references

| 파일 | 역할 |
|---|---|
| `constitution.md` | 워커 헌법 |
| `loop.sh` | 핵심 driver |
| `task-storage.sh` | task 저장소 라벨 헬퍼 |
| `pr-phase.sh` | PR 생성·재사용 |
| `rebase-phase.sh` | base sync |
| `review-fix-phase.sh` | 리뷰 자동 fix·auto-merge |
| `cleanup-phase.sh` | merged 후 cleanup |
| `operational-guide.md` | 운영 가이드 |
| `status-format.md` | status 출력 |
| `troubleshooting.md` | 차단 처리 |
| `agent-prompts.md` | 이터 내 Agent brief |

## 의존성

`git`, `bash` 4+, `yq`(mikefarah), `claude` CLI, 선택적으로 `gitleaks`, PR phase에는 인증된 `gh` CLI.

## 규칙

- 명시된 subcommand만 실행한다. 다른 subcommand를 자동 추론하지 않는다.
- target의 `milestones/<m>/loops/<c>/` nested tree 외 파일은 setup의 `.gitignore`를 제외하고 만들지 않는다.
- subcommand exit code를 그대로 던지지 말고 사용자에게 요약한다.
- 프로젝트별 constitution override는 아직 미지원이다.
