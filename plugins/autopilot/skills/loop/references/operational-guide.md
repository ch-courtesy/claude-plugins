# 자율 루프 운영 가이드

autopilot `loop` 스킬의 nested 워크트리 기반 외부 셸 드라이버 운영 가이드입니다. 드라이버(`loop.sh`)와 헌법·템플릿은 모두 `references/` 안에 있으며, target 프로젝트에는 런타임 상태가 모두 `milestones/<m>/loops/<c>/` 단일 트리 안에 생성됩니다.

## 핵심 가정

- 매 이터는 새 `claude --print` 프로세스 (콜드 스타트). 기억은 LLM이 아닌 파일에 있습니다.
- 작업은 `<project>/milestones/<m>/loops/<c>/.worktree/` (메인 레포 내부 nested 워크트리)에서 일어납니다.
- 격리: 워크트리 경로는 `.gitignore`로 git 추적이 차단됩니다. 같은 부모 디렉터리(`milestones/<m>/loops/<c>/`)에 SPEC.md·메타 파일과 워크트리가 함께 위치하므로 IDE에서 한눈에 보입니다.
- 워크트리의 자체 `CLAUDE.md`(헌법)는 워크트리 로컬 git exclude에 등록되어 main 트리로 새지 않습니다. 사용자 레벨 `~/.claude/CLAUDE.md`·`~/.claude/settings.json`은 차단 불가 — **루프 시작 전 본인 환경을 검토**하시는 것을 권장합니다.

## 보안 경계

자율 루프는 워커가 무인 동작하기 위해 `claude --dangerously-skip-permissions`로 호출됩니다. 이는 워커가 sibling 워크트리(`--add-dir .`로 부여) 내의 모든 파일을 자유롭게 읽고 쓸 수 있다는 의미입니다.

**주의:**
- 워크트리에 `.env`·credentials·SSH 키 등 secrets 파일을 두지 마세요. 워커가 의도치 않게 읽어 commit 메시지·로그·`[handoff]` comment에 노출할 수 있습니다.
- SPEC.md에 secrets 값을 인라인으로 적지 마세요. 워커가 그 내용을 다른 파일에 그대로 복사할 수 있습니다.
- 워크트리는 사용자 본인 권한으로 동작합니다. 시스템 디렉토리(`/etc`·`/usr` 등)에 대한 영향은 워크트리 격리(`<project>/milestones/<m>/loops/<c>/.worktree/` 경로 안)와 `--add-dir .` 범위로 제한됩니다 — 외부 경로 쓰기는 일반적으로 발생하지 않으나, 워커가 명시적으로 호출한 명령(예: `npm install`)은 사용자 홈에 부수효과를 만들 수 있습니다.
- 권장: 외부 SPEC(`--spec`)을 사용할 때 신뢰하지 못한 출처의 SPEC을 그대로 받지 마세요. SPEC은 워커의 행동을 직접 지시합니다.

## 디렉토리 구조

```
# target 프로젝트 — 모든 산출물이 milestones/<m>/loops/<c>/ 단일 트리 (v0.2 cutover)
milestones/<m>/loops/<c>/
├── SPEC.md                    # spec 스킬로 생성, feat 브랜치 commit
├── .lock                      # 동시 실행 락 (gitignored)
└── .worktree/                 # git 워크트리 (gitignored)
    ├── CLAUDE.md              # 헌법 복사본
    ├── DONE                   # 정상 완료 신호 (있을 때만)
    ├── .iterations/<n>.log    # 매 이터 stdout 캡처 (gitignored, worktree-local)
    └── milestones/<m>/loops/<c>/
        └── SPEC.md            # feat 브랜치 commit으로 자연 노출
# 이터간 상태(계획·교훈·인계·차단·완료)는 워크트리에 두지 않고 task issue body·prefix comments로 위임 (헌법 §11)
```

단일 task는 `<m>=regular`로 정규화 — `regular/<task-id>`. `.gitignore` 무시 패턴은 `milestones/**/loops/**/.worktree/`와 `milestones/**/loops/**/.lock`.

스킬 패키지 파일 목록: `SKILL.md`의 모듈 구성 표 참조.

## Subcommand 일람

LOOP_SH는 `$SKILL_DIR/references/loop.sh` 경로로 호출합니다. 아래에서는 `loop.sh`로 줄여씁니다.

```
loop.sh prepare <task-id>             # (deprecated → spec 스킬) Skill(skill: "spec", args: "<task-id>")
loop.sh start   <task-id> [옵션]      # 검증 후 워크트리·락 생성 + 루프 시작
loop.sh status  [<task-id>]           # 상태 조회 (전체 또는 단일)
loop.sh stop    <task-id>             # 실행 중 정지 (SIGTERM)
loop.sh list                          # 전체 task 상태 (status 별칭)
loop.sh cleanup <task-id> [--force]   # DONE 후 정리
loop.sh logs    <task-id> [옵션]      # 로그 조회
```

## 새 task 시작 워크플로

```bash
LOOP_SH="$HOME/.claude/plugins/autopilot/skills/loop/references/loop.sh"

Skill(skill: "spec", args: "auth-refactor")   # 대화형 SPEC.md 생성
bash "$LOOP_SH" start auth-refactor           # 루프 시작
bash "$LOOP_SH" logs auth-refactor --tail  # 별도 터미널에서 모니터링
# 정지: Ctrl+C, DONE 파일 생성, 또는 `[done]`/`[blocked]` prefix comment 작성 시 자동 종료
```

## 외부 SPEC 파일 전달 (--spec 플래그)

spec 스킬 대신 외부에서 만든 SPEC.md를 start에 직접 넘길 수 있습니다.

```bash
bash "$LOOP_SH" start auth-refactor --spec /tmp/my-spec.md
```

지정한 파일이 `milestones/<m>/loops/<c>/SPEC.md`로 복사된 후 일반 start 흐름으로 진행됩니다 (단일 컴포넌트는 `<m>=regular`로 정규화). SPEC.md 형식: frontmatter에 `scope.include`·`scope.exclude`·`verify` 포함, 본문에 작업 정의.

## 상태 조회

```bash
bash "$LOOP_SH" status               # 모든 task 상태 테이블
bash "$LOOP_SH" status auth-refactor # 단일 task 상태
```

출력 형식 상세는 `references/status-format.md` 참조.

## 정지

```bash
bash "$LOOP_SH" stop auth-refactor   # SIGTERM + 5초 대기 + 락 해제
```

## DONE 후 머지 및 정리

```bash
# feat/<task-id>[-<slug>] 브랜치를 PR base로 — request_review opt-in 시 자동 push·PR 생성
git -C milestones/regular/loops/auth-refactor/.worktree log feat/regular/auth-refactor
bash "$LOOP_SH" cleanup auth-refactor               # 워크트리 제거 (feat 브랜치 보존)
# cleanup은 메타 파일을 메인 트리로 cp하지 않음. feat 브랜치 commit history가 정본.
```

`cleanup --force`는 실행 중 프로세스가 있으면 SIGTERM 후 5초 대기 → 무응답 시 SIGKILL → lock·워크트리 제거. 정상 종료를 원할 때는 먼저 `stop <task-id>`로 정지 후 `cleanup` (without --force).

## 로그 조회

```bash
bash "$LOOP_SH" logs auth-refactor [--tail | --iter N]
```

## DONE_WITH_CONCERNS 처리

이터가 verify는 통과했으나 self-review에서 의심점을 발견하면 `[done]` comment 대신 `[handoff]` prefix comment 본문에 `## 의심점` 섹션을 포함시켜 작성하고 정상 종료합니다. 사용자 개입은 보통 불필요 — 다음 이터가 의심점을 읽고 검증·해소한 후 깨끗한 `[done]` prefix comment를 작성합니다.

## ESCALATION 처리

카테고리별 처리 흐름: `references/troubleshooting.md` 참조.

```bash
ISSUE=<task-issue-number>                                 # task-id가 숫자면 issue number와 동일
gh issue view "$ISSUE" --comments | tail -n 60            # 최근 `[blocked]` comment 본문 확인
cd milestones/<m>/loops/<c>/.worktree
$EDITOR "milestones/<m>/loops/<c>/SPEC.md"                # 필요 시 SPEC 보정
gh issue comment "$ISSUE" --body "[notes] 후속 조치 메모"   # 결정 사항 누적
gh issue comment "$ISSUE" --body "[unblocked] 후속 조치 완료"  # Blocked 해제
#   ([resume] prefix도 동등. task_status_is_blocked가 가장 최근 매치된 prefix
#    comment를 단일 진실원으로 보므로, Projects UI에서 Status만 바꾸는 것으로는
#    fallback이 [blocked]를 계속 감지해 차단이 유지됨.)
cd <project-root> && bash "$LOOP_SH" start <task-id>      # 재시작
# --watch 모드면 [unblocked]/[resume] comment로 차단 신호가 해제되는 순간 자동 재개 (polling)
```

## 동시 실행

```bash
bash "$LOOP_SH" start auth-refactor &
bash "$LOOP_SH" start schema-migration &
bash "$LOOP_SH" status          # 모든 task 상태
MAX_CONCURRENT=5 bash "$LOOP_SH" start new-task &   # 캡 상향
```

같은 task-id 이중 실행은 락으로 차단됩니다.

## 환경 변수 / CLI 플래그

| 환경 변수 | CLI 플래그 | 기본값 | 설명 |
|---|---|---|---|
| `MAX_CONCURRENT` | — | 3 | 동시 실행 task 수 |
| `MAX_ITERATIONS` | `--max-iterations N` | 30 | 이터 상한 |
| `WALL_CLOCK_MINUTES` | `--wall-clock-minutes N` | 120 | 시계 캡(분) |
| — | `--watch` | off | 차단 신호(Status=`Blocked` 또는 `[blocked]` prefix comment) 감지 시 정지 대신 polling 재개 대기. `task_status_is_blocked`의 OR 결합과 일치. |
| `WATCH_TIMEOUT_HOURS` | — | 24 | --watch 모드에서 polling 최대 시간(시간 단위). 초과 시 exit 1 |

워크트리 위치는 v0.2부터 메인 레포 내부 `milestones/<m>/loops/<c>/.worktree/`로 고정 — 외부 sibling 경로를 지정하는 환경 변수는 더 이상 제공하지 않습니다.

## 객관 게이트

드라이버가 매 이터 후 다음을 검사합니다. 위반 시 자동 halt + 자동 `[blocked]` prefix comment 작성·Project Status=`Blocked` 전이:

| 가드 | 기준 |
|---|---|
| 이터 상한 | `MAX_ITERATIONS` (기본 30) |
| 시계 캡 | `WALL_CLOCK_MINUTES` (기본 120) |
| 테스트 약화 | 이터 시작 시점의 테스트 파일 set만 종료 후 다시 해시 비교 — **삭제·수정만 감지, 신규 추가는 통과** (TDD RED 단계 보호, 헌법 §0). 기본 추적: `tests/`·`test/`·`__tests__/`·`spec/`·`src/test/` 디렉토리 + co-located 파일명 (`*.test.{js,ts,jsx,tsx,py}`·`*.spec.{js,ts,rb}`·`*_test.{go,py,rb}`·`test_*.py`·`*_spec.rb`). 비표준 컨벤션은 SPEC.md frontmatter `test_paths` (git pathspec 배열)로 override. `git ls-files`로 추적 파일만 검사 (gitignored 제외). 합법적 sweep(rename·cleanup 등)은 SPEC frontmatter `test_sweep_paths` (git pathspec 배열) 선언으로 해시 비교 셋에서 제외 — sweep 밖 기존 테스트는 여전히 보호. 선언됐으나 매칭 파일 0건이면 stderr 경고만 (halt 없음). |
| 의존성 동결 | `package.json`·`requirements.txt`·`Cargo.toml` 등 매니페스트 해시 |
| Scope 위반 | git diff (커밋된 + working tree 미커밋) vs SPEC.md frontmatter의 scope.include·exclude. 미커밋 변경도 검사해 claude 비정상 종료 gap 차단. 미추적 신규 파일은 미커버 — halt 시 `git add -A && git stash`로 보호. |
| Suppressor 신규 | `noqa`·`@ts-ignore`·`eslint-disable`·`#pragma warning disable` 신규 추가 (커밋된 diff + working tree 미커밋 양쪽). |
| Secrets | `gitleaks detect --log-opts="HEAD~1..HEAD"` (이번 이터 커밋) + `--staged` (staged 미커밋), gitleaks 설치 시. unstaged-tracked 변경은 gitleaks API 한계로 미커버 — 헌법의 매-이터 commit 강제로 보완. |
| fix:symptom streak | git log의 최근 2 커밋이 모두 `fix:symptom` |
| 진동 | 최근 4 커밋의 변경 파일 셋 토글 |

## 의존성

- `bash` 4+
- `git` (worktree 지원)
- `yq` ([mikefarah/yq](https://github.com/mikefarah/yq))
- `claude` CLI
- `sha256sum` 또는 `shasum` (해시 게이트용 — macOS는 `shasum` 기본 제공, Linux는 보통 `sha256sum`)
- `gitleaks` (선택, secrets 게이트용)

## 안전 정지 / stale 락 정리

정지: Ctrl+C, `stop <task-id>` (SIGTERM), `kill <PID>`. SIGTERM/SIGINT 수신 시 드라이버는 자식 프로세스 트리(subshell·claude)를 모두 종료한 후 lock을 해제합니다 (orphan 방지). SIGKILL(`kill -9`)은 trap을 우회하므로 자식이 orphan으로 남을 수 있습니다 — 가급적 `stop` subcommand 사용.

크래시로 stale 락이 남은 경우 별도 작업 불필요 — 다음 `start`/`stop` 호출이 PID 유효성을 검사해 자동 정리합니다 (PID 무효·빈 파일·비숫자 모두 stale로 인식).
