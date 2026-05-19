---
name: loop
description: 자율 수행 루프(랄프 루프) 운영 인터페이스. start/status/stop/list/cleanup/logs 서브커맨드로 자율 task의 lifecycle을 관리합니다. SPEC 작성은 별도 'autopilot:spec' 스킬을 사용. 본 스킬은 자기완결적이며 헌법·드라이버를 모두 references/에 포함합니다.
allowed-tools:
  - Monitor
  - Read
  # SPEC 113 — issue #113 본문 `autopilot:loop` 섹션 (직전 세션 실측)
  # SPEC 170 — trailing wildcard 형식을 ` *`(공백+별표) → `:*` 로 정규화
  - Bash(bash * loop.sh start:*)
  - Bash(bash * loop.sh status:*)
  - Bash(bash * loop.sh stop:*)
  - Bash(bash * loop.sh list)
  - Bash(bash * loop.sh cleanup:*)
  - Bash(bash * loop.sh logs:*)
  - Bash(tail -F /private/tmp/* | grep -E --line-buffered:*)
  - Bash(tail -F /tmp/* | grep -E --line-buffered:*)
  # SPEC 113 — issue #113 본문 `공통·보조` 섹션
  - Bash(git -C * stash list)
  - Bash(git -C * stash pop:*)
  - Bash(git -C * stash show:*)
  - Bash(rm */ESCALATION.md)
  - Bash(ps -p:*)
  - Bash(cat */*.lock)
  # SPEC 183 — 세션에서 자주 프롬프되던 패턴 보강 (cache-path 드라이버·bg output tail·PR read-only·git inspect)
  - Bash(bash /Users/*/.claude/plugins/cache/*/autopilot/*/skills/loop/references/*.sh *)
  - Bash(tail -F /private/tmp/claude-* 2>/dev/null | grep -E --line-buffered *)
  - Bash(gh pr view *)
  - Bash(gh pr checks *)
  - Bash(git status --porcelain*)
  # NOTE: `git checkout HEAD -- *` 는 자동 승인 제외 — 미커밋 변경을 무음 파기하는 write 연산이라 destructive 위험
---

# loop

자율 수행 루프의 통합 운영 인터페이스. 인자로 subcommand와 sub args를 받아 자율 task lifecycle을 관리합니다.

본 스킬은 **자기완결적**입니다 — 워커 헌법(`references/constitution.md`)과 외부 셸 드라이버(`references/loop.sh`)가 이 스킬 패키지에 포함됩니다. target 프로젝트에는 런타임 상태가 모두 `milestones/<m>/loops/<c>/` 단일 nested 트리 안에 생성됩니다 (워크트리 `.worktree/`, lock `.lock`, SPEC). 이터간 메모(계획·교훈·인계·차단·완료)는 **task 메모리**의 계획 섹션과 누적된 **task 신호**(`handoff`·`notes`·`blocked`·`done`)에 모입니다 — 워크트리에는 메타 파일을 두지 않습니다. 추상 어휘는 헌법 §추상 어휘를 단일 출처로 따르고, 본 프로젝트의 백엔드 매핑(메시지 매체·식별자·필드 등)은 `rules/context.md`가 책임집니다. ad-hoc 단일 task는 `regular` milestone(catch-all)로 자동 정규화됩니다.

## 호출 방법

`Skill(skill: "loop", args: "<subcommand> [<args>]")`

또는 사용자가 자연어로 의도 전달 시 모델이 자동 호출.

## SPEC.md 생성

새 task의 SPEC.md는 별도 스킬 `autopilot:spec`에서 대화형으로 생성합니다:

```
Skill(skill: "spec", args: "<task-id>")
```

자세한 흐름은 `plugins/autopilot/skills/spec/SKILL.md` 참조. SPEC 작성이 끝나면 본 스킬의 `start` 서브커맨드로 이어 호출.

## Subcommand

### start <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>] [--no-monitor] [--no-pr]

검증 후 워크트리·락 생성 + 이터레이션 루프 시작.

`Bash(bash $SKILL_DIR/references/loop.sh start <task-id> [...flags], run_in_background: true)` 호출 — `run_in_background: true`는 필수다. 동기 호출하면 loop.sh의 이터레이션 루프가 메인 대화를 블록해 아래 "자동 Monitor 가설" 자체가 불가능해진다. task-id가 단일 컴포넌트면 `regular/<input>`로 자동 정규화. loop.sh는 다음을 검증·수행:
- `--spec <path>` 지정 시 외부 파일을 `milestones/<m>/loops/<c>/SPEC.md`로 복사 (prepare 대체)
- `milestones/<m>/loops/<c>/SPEC.md` 존재 + `[NEEDS CLARIFICATION]` 마커 없음 + placeholder 모두 치환됨 (legacy `.loops/<task-id>/SPEC.md` fallback 없음 — v0.2 cutover)
- 락 미보유 — lock 파일은 `milestones/<m>/loops/<c>/.lock`
- 워크트리 없으면 생성 (메인 레포 내부 nested 위치 `milestones/<m>/loops/<c>/.worktree/` — `.gitignore`로 추적 차단)
- 헌법(`references/constitution.md`)을 워크트리의 CLAUDE.md로 복사
- 락 획득 + 이터레이션 루프

#### 자동 Monitor 가설 (기본 동작)

`--no-monitor`를 명시하지 않은 경우, 백그라운드로 띄운 `loop.sh start`의 stdout 스트림 위에 `Monitor` 도구를 즉시 가설하여 핵심 이벤트(이터 시작·종료, halt, escalation, done 등)를 사용자에게 자동 알림한다. 매 시작마다 별도 결정 질문을 묻지 않는다 — 기본 ON이며 비활성화는 호출 시 `--no-monitor` 플래그로만.

권장 기본값:
- `persistent: true`
- `timeout_ms: 3600000` (1시간)
- 필터 정규식: `이터 #|HALT|WARN|FAIL|ERROR|rate limit|claude 비정상|에스컬레이션|완료 신호`

`--no-monitor` 플래그는 **SKILL.md 차원 옵션**이다 — 모델이 args 파싱 시 이 토큰을 분리·소비하여 `Monitor` 가설 자체를 생략하고, `loop.sh`로는 **전달하지 않는다** (셸 드라이버는 본 플래그를 모름). 따라서 본 플래그는 **본 스킬을 통한 호출 시점에만** 작용하며, 사용자가 셸 드라이버 `loop.sh start`를 직접 호출하는 경우엔 효력이 없다.

`spec` 스킬 단계 9의 "지금 loop start 호출" 결정으로 자동 연계되는 경우에도 추가 모니터 결정 질문 없이 본 기본 동작(Monitor 가설 포함)이 그대로 적용된다.

#### 완료 라벨 부착 이후 PR 생성·재사용 phase (default)

task 가 완료 신호(`LOOP_DONE_LABEL` 라벨 부착)에 도달한 직후 같은 워크트리에서 PR 생성(또는 동일 브랜치의 open PR 재사용) 단계가 **default로 자동 실행**됩니다 (SPEC 103 AC1). 건너뛰려면 `--no-pr` 플래그를 명시(SPEC 103 AC2).

활성화 시 동작:
- default 브랜치 자동 감지 (`gh repo view` → `git symbolic-ref refs/remotes/origin/HEAD`)
- push 직전에 `origin/<base>`로부터 `git fetch` + 단일 sync helper(`references/rebase-phase.sh`)로 base 동기화 (SPEC 169) — helper가 `git ls-remote --heads origin <branch>`로 원격 트래킹 브랜치 존재 여부를 판정해 두 경로로 분기한다:
  - **부재 → rebase 경로**: `git rebase origin/<base>`로 history 재배치 (첫 PR 진입 전 깨끗한 linear history)
  - **존재 → merge 경로**: `git merge --ff-only` → 실패 시 non-ff `git merge --no-edit`로 base 변경분만 흡수 (자기 commit SHA 보존, force push 회피)
- 어떤 경로에서도 force push(`--force`·`--force-with-lease` 포함)는 도입되지 않는다 (SPEC 169 AC4). 충돌 시 claude CLI 세션 1회로 자동 해소 시도(SPEC 169 AC5), 실패 시 해당 모드의 `--abort`로 워크트리 복구 + non-zero exit (보수적 좌절, SPEC 169 AC6)
- 현재 브랜치를 `origin`으로 push
- 동일 head 브랜치에 open PR이 없으면 **새 PR 생성**, 있으면 **기존 PR을 in-place로 갱신** (제목·body 동기화)
- PR 제목 = SPEC 문서의 H1, body = SPEC "무엇을 만들 것인가" 본문 + base..HEAD commit log
- task-id가 `^[0-9]+$`이면 body 마지막에 `Closes #<id>` 자동 추가
- reviewer·label·assignee는 일체 설정 안 함
- 성공 시 PR URL·state(open)를 stdout으로 출력, worktree·local 브랜치 보존
- push·pr create·pr edit 중 하나라도 실패하면 non-zero exit으로 단계 중단 (워크트리는 유지)
- default 브랜치 감지 실패 시 push·pr 호출 전 abort
- PR 생성·갱신 직후 **Monitor 단계** 진입 (SPEC 103 AC5): PR check가 모두 완료(success/failure)됐는데 PR state가 OPEN이고 reviewDecision이 없는 "stuck" 패턴을 감지하면 `gh pr checks <num> --rerun`을 호출. 최대 **3회** 재트리거하고 상한 도달 시 stderr에 사용자 개입 안내. MERGED·CLOSED 상태 전이 또는 리뷰 활동(reviewDecision set) 감지 시 즉시 종료. check 진행 중·정보 없음도 stuck 아닌 것으로 간주해 종료. 상한 도달은 경고이며 loop 자체는 정상 종료
- **Cleanup 안내 단계** (SPEC 103 AC6): Monitor가 PR state를 MERGED 또는 CLOSED로 감지해 종료할 때 셸 드라이버는 "cleanup 후보" 안내(=PR 번호·상태·자동 삭제 차단·수동 cleanup 명령 위치)를 stdout에 명시 출력하고 worktree·feat 브랜치는 그대로 보존한다. 본 스킬을 통한 호출에서 cleanup 안내가 감지되면 `AskUserQuestion`으로 "worktree·feat 브랜치 cleanup 승인?"을 명시 확인하고 사용자의 명시 승인이 있을 때만 `cleanup` 서브커맨드를 호출한다 — 승인 없이 자동 삭제 금지

`--no-pr` 플래그는 셸 드라이버(`loop.sh`)에 직접 전달되며, PR phase 진입 자체를 차단합니다. 이전 버전에서 `request_review: true`로 opt-in을 사용하던 호출자는 별도 마이그레이션이 필요 없습니다(default가 ON으로 변경됐으므로 동일 동작). 이전 버전에서 `request_review: false`(또는 키 미지정)로 PR을 차단하던 호출자는 `--no-pr`로 동일 동작을 재현해야 합니다.

기존 PR body의 사용자 수기 편집 보호를 위해 자동 영역은 `<!-- autopilot:pr-body:begin --> ... <!-- autopilot:pr-body:end -->` marker fence 안에만 작성됩니다.

#### 완료 라벨 부착 이후 PR 리뷰 자동 fix 루프 (SPEC 123, `request_review: true` opt-in)

SPEC frontmatter에 `request_review: true`가 지정된 task만 본 흐름을 진입합니다. PR 생성·재사용이 성공한 직후 다음 sub-phase가 차례·일부 background로 실행됩니다:

| 단계 | 스크립트 | 역할 |
|---|---|---|
| pre-PR sync | `references/rebase-phase.sh` | default 브랜치로부터 워크트리 feat 브랜치 동기화 (SPEC 169). 원격 트래킹 부재면 rebase, 존재면 merge 경로. 충돌 시 claude CLI 1회 자동 해소, 실패 시 해당 모드의 `--abort`로 복구 + ESCALATION abort. |
| review-fix 루프 (background) | `references/review-fix-phase.sh` | 30초 주기 폴링 (PR comments · review threads · summary). 새 이벤트마다 base 재동기화(sync helper — merge 경로) → claude CLI fix → commit+push → (필요 시) 1개 반박 코멘트. |
| 자동 머지 (auto-merge) | `references/review-fix-phase.sh` 내부 | reviewDecision `APPROVED` 또는 owner의 종료 코멘트(`/done`·`합격`·`통과`)로 `gh pr merge --squash` 수행. PR이 이미 `merged`이면 자동 머지 건너뜀. |
| cleanup | `references/cleanup-phase.sh` | PR `merged` 후 worktree 제거 + 로컬 feat `branch -D` + origin feat `push --delete`. |

##### 상태 전이

헌법 §추상 어휘의 **task 상태** 어휘에 따라 다음 시점에 전이합니다:

- PR 생성·재사용 성공 직후 → task 상태를 `review`로 전이 (review-fix-phase 진입 시점)
- cleanup 성공 직후 → task 상태를 `done`으로 전이

전이의 구체 명령·환경 변수·라벨 매핑(필요 설정 부재 시 무음 skip 포함)은 `rules/context.md` 단일 출처에 위임됩니다 — phase 자체는 매핑 부재 시에도 진행됩니다.

##### 종료 조건

review-fix 루프는 다음 중 하나가 감지되면 종료합니다:

1. PR `merged` → cleanup 진입 (자동 머지 skip — 이미 merged)
2. PR `closed` (unmerged) → cleanup·상태 전이 모두 skip (사용자 판단 대기)
3. reviewDecision `APPROVED` → 자동 머지 → cleanup
4. owner 코멘트 `/done`·`합격`·`통과` → 자동 머지 → cleanup

##### 게시 제약

리뷰어가 틀렸다고 판명된 경우 1개의 반박(dispute) 코멘트만 PR에 게시합니다. inline reply, summary comment, title/description 편집 등 다른 어떤 GitHub 게시도 수행하지 않습니다.

##### allowed-tools

본 phase 그룹은 autopilot 워커의 새 claude CLI 세션 호출에 다음 도구만 허용합니다 (범위 최소화, 와일드카드 금지):

- GitHub CLI: `gh pr merge`, `gh pr comment`, `gh pr view`, `gh api repos/.../pulls/*`·`repos/.../issues/*/comments`, `gh project item-edit`
- Git: `git rebase`, `git push --delete`, `git branch -D`, `git worktree remove`, `git add`/`git commit`/`git status`/`git diff` (fix iter 본 작업)
- Read·Edit·Write·Glob·Grep

상수는 `loop.sh`의 `AUTOPILOT_REVIEW_FIX_ALLOWED_TOOLS` / `AUTOPILOT_REBASE_ALLOWED_TOOLS` 에 정의되며, 환경 변수로 자식 phase 스크립트에 export됩니다. 사용자 대화형 세션의 `settings.json`은 본 등록의 영향을 받지 않습니다 — autopilot 워커 컨텍스트에만 한정됩니다.

##### silent-fail 검출기 환경변수

review-fix-phase의 silent-fail 검출기(연속 idle 폴링 후 stuck 패턴 escalate)는 다음 환경변수로 조절됩니다.

| 환경변수 | 기본값 | floor | 의미 |
|---|---|---|---|
| `LOOP_REVIEW_IDLE_THRESHOLD` | 3 | 3 | 새 이벤트 0건이 N회 연속 폴링되면 silent-fail 패턴 평가 |
| `LOOP_REVIEW_PR_GRACE_SECS` | 300 (5분) | 0 | PR 생성 직후 N초 동안은 silent-fail 검출기 평가 자체를 skip — GitHub Actions check 등록 지연·큐 지연 흡수 (SPEC 181). 0으로 설정 시 grace 비활성화 |

검출기는 `statusCheckRollup`의 전체 check 수가 0이면(check 미등록·정보 부족) 해당 폴링 회차의 ESCALATION을 발동하지 않고 카운터만 리셋합니다 (SPEC 181 AC2). 전체 check 수가 0보다 크고 pending 0 + 다른 활동(리뷰·코멘트·inline·owner cmd) 모두 0일 때만 진짜 stuck으로 escalate합니다 (AC3).

요구: `gh` CLI 설치 + OAuth 인증.

### status [<task-id>] / stop <task-id> / list / cleanup <task-id> [--force] / logs <task-id> [--tail | --iter N]

각각 `Bash(bash $SKILL_DIR/references/loop.sh <subcommand> [args])`로 위임. 결과를 사용자에게 형식화 출력.

`status` 출력 형식 상세는 `references/status-format.md` 참조.

### 인자 없는 호출

사용법 안내 + 사용 가능한 subcommand 목록 출력.

## 첫 호출 시 setup

start 첫 호출에 자동:
- `.gitignore`에 다음 패턴이 없으면 추가: `milestones/**/loops/**/.worktree/`, `milestones/**/loops/**/.lock`
- 기존 `.loops/locks/` 라인이 있으면 제거 (v0.1 → v0.2 마이그레이션)
- 변경분을 `.gitignore` 단독 chore commit으로 격리 — 사용자의 staged/unstaged 변경과 commit 단위를 침범하지 않는다
- `.gitignore` 갱신·commit 실패 시 워크트리·lock 생성 중단 후 비-zero exit

설치 단계가 별도로 필요 없음 — 스킬 첫 호출이 알아서 setup.

## 모듈 구성 (references/)

| 파일 | 역할 |
|---|---|
| `constitution.md` | 워커 헌법. start 시점에 워크트리 CLAUDE.md로 복사 |
| `loop.sh` | 외부 셸 드라이버. 모든 subcommand의 핵심 로직 |
| `task-storage.sh` | task 저장소 라벨 검출 공통 헬퍼 (loop.sh·dispatch.sh 공유, SPEC 175) |
| `pr-phase.sh` | 완료 라벨 부착 이후 PR 생성·재사용 단계 |
| `operational-guide.md` | 사용자용 운영 가이드 (워크플로·환경 변수·객관 게이트 표·의존성) |
| `status-format.md` | status 출력 형식 가이드 |
| `troubleshooting.md` | 차단 신호 카테고리별 처리 가이드 |
| `agent-prompts.md` | 이터 내 Agent dispatch 브리프 양식 3종 (spec-compliance-reviewer · code-quality-reviewer · parallel-hypothesis-tester). 헌법 §11.6 참조 |

## 의존성 (target 프로젝트)

- `git` (worktree 지원)
- `bash` 4+
- `yq` (mikefarah)
- `claude` CLI
- `gitleaks` (선택, secrets 게이트용)

## 헌법 customization

기본 헌법은 `references/constitution.md`. 프로젝트별 override는 향후 `milestones/<m>/loops/<c>/constitution.override.md`(target) 메커니즘으로 추가 예정 (현재 미지원).

## 규칙

- 본 스킬은 target 프로젝트의 `milestones/<m>/loops/<c>/` nested 트리(워크트리 `.worktree/`, lock `.lock`, SPEC·메타 파일)만 다룬다. `rules/`나 다른 디렉토리에 파일 생성하지 않음.
- subcommand 위임 시 결과 코드를 그대로 사용자에게 보여주지 않고 형식화·요약.
- 사용자가 명시적 요청한 subcommand만 실행. 다른 subcommand 자동 추론하지 않음.
