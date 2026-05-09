# 자율 루프 운영 가이드

autopilot `loop` 스킬의 sibling 워크트리 기반 외부 셸 드라이버 운영 가이드입니다. 드라이버(`loop.sh`)와 헌법·템플릿은 모두 `references/` 안에 있으며, target 프로젝트에는 런타임 상태만 생성됩니다.

## 핵심 가정

- 매 이터는 새 `claude --print` 프로세스 (콜드 스타트). 기억은 LLM이 아닌 파일에 있습니다.
- 작업은 `<project>/../<project-name>-loops/<task-id>/` (sibling 워크트리)에서 일어납니다.
- 격리: 워크트리는 프로젝트 트리 밖에 있어 프로젝트 `CLAUDE.md`·hooks가 자동 차단됩니다.
- 사용자 레벨 `~/.claude/CLAUDE.md`·`~/.claude/settings.json`은 차단 불가 — **루프 시작 전 본인 환경을 검토**하시는 것을 권장합니다.

## 디렉토리 구조

target 프로젝트 런타임 상태 (스킬이 생성):
```
.loops/
├── locks/                     # 동시 실행 락 (gitignored)
└── <task-id>/                 # task별 통합 디렉토리
    ├── SPEC.md                # prepare 생성, start 후 워크트리로 복사
    └── (cleanup 후) PLAN/NOTES/HANDOFF/RUN_LOG.md  # 아카이브
```

스킬 패키지 (변경 불요):
```
autopilot/skills/loop/references/
├── constitution.md            # 워커 헌법 (워크트리 CLAUDE.md로 복사)
├── loop.sh                    # 외부 드라이버 (subcommand 기반)
├── spec-template.md           # 새 task SPEC.md 시드
├── plan-template.md           # 메모리 파일 스텁
├── notes-template.md
├── handoff-template.md
├── runlog-template.md
├── escalation-template.md
└── operational-guide.md       # 본 문서
```

런타임 워크트리:
```
<project>/../<project-name>-loops/<task-id>/
├── CLAUDE.md                  # 헌법 (references/constitution.md 복사본)
├── .loop/                     # 메타 파일 (워크트리 .git/info/exclude로 비추적)
│   ├── SPEC.md                # 작업 정의 (prepare에서 복사)
│   ├── PLAN.md                # 마일스톤 (모델 갱신)
│   ├── NOTES.md               # 학습 누적 (모델 갱신)
│   ├── HANDOFF.md             # 직전 → 다음 편지 (모델 매 이터 덮어쓰기)
│   ├── RUN_LOG.md             # 한 줄 요약 누적
│   ├── iterations/<n>.log     # 매 이터 stdout 캡처
│   └── ESCALATION.md          # 정지 사유 (있을 때만)
└── (프로젝트 파일들 — autonomous-loop/<task-id> 브랜치 체크아웃)
```

## Subcommand 일람

LOOP_SH는 `$SKILL_DIR/references/loop.sh` 경로로 호출합니다. 아래에서는 `loop.sh`로 줄여씁니다.

```
loop.sh prepare <task-id>             # SPEC.md 시드 생성
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

# 1. SPEC.md 시드 생성 (인터랙티브 prepare는 loop 스킬 호출 권장)
bash "$LOOP_SH" prepare auth-refactor
# 출력: "준비 완료. 다음 파일을 편집하세요: .loops/auth-refactor/SPEC.md"

# 2. SPEC.md에 작업 정의 채움
$EDITOR .loops/auth-refactor/SPEC.md
# - YAML frontmatter: scope.include / scope.exclude / verify
# - 본문 placeholder: {{task_title}}, {{task_description}}, {{acceptance_criteria}}, ...

# 3. 루프 시작
bash "$LOOP_SH" start auth-refactor

# 4. 진행 모니터링 (별도 터미널)
bash "$LOOP_SH" logs auth-refactor --tail

# 5. 정지: Ctrl+C, 또는 DONE/ESCALATION.md가 생기면 자동 종료
```

## 외부 SPEC 파일 전달 (--spec 플래그)

```bash
# 외부에서 SPEC.md 작성 후 전달
cat > /tmp/my-spec.md <<'EOF'
---
scope:
  include:
    - src/**
    - tests/**
  exclude:
    - rules/**
    - .loops/**
    - CLAUDE.md
verify: "pnpm test"
---

# auth-refactor: JWT 갱신 흐름 개선

## 무엇을 만들 것인가
...
EOF
bash "$LOOP_SH" start auth-refactor --spec /tmp/my-spec.md

# 또는 다른 도구가 SPEC.md를 만들고 전달
some-spec-generator > /tmp/spec.md
bash "$LOOP_SH" start my-task --spec /tmp/spec.md
```

`--spec`을 쓰면 prepare 단계 없이 start만으로 시작할 수 있습니다. 지정한 파일이 `.loops/<task-id>/SPEC.md`로 복사된 후 일반 start 흐름(placeholder 검사·워크트리 생성·루프)으로 진행됩니다.

## 상태 조회

```bash
bash "$LOOP_SH" status               # 모든 task 상태 테이블
bash "$LOOP_SH" status auth-refactor # 단일 task 상태
```

상태 값:
- `prepared`: SPEC.md 준비됨, start 전
- `running`: 루프 실행 중 (락 파일 있음)
- `idle`: 워크트리 있음, 락 없음 (일시 정지)
- `escalated`: ESCALATION.md 있음 (사람 개입 필요)
- `done`: DONE 파일 있음 (cleanup 대기)
- `archived`: 워크트리 정리됨, 메타 파일 보관됨

## 정지

```bash
bash "$LOOP_SH" stop auth-refactor   # SIGTERM + 5초 대기 + 락 해제
```

## DONE 후 머지 및 정리

```bash
# 워크트리에서 검토
cd ../<project>-loops/auth-refactor
git log autonomous-loop/auth-refactor

# 메인 프로젝트로 돌아와 머지 (또는 PR 생성)
cd <project>
git merge autonomous-loop/auth-refactor    # 또는 PR 생성

# 정리 (메타 파일 아카이브 + 워크트리 제거 + 브랜치 삭제)
bash "$LOOP_SH" cleanup auth-refactor
```

cleanup 후 메타 파일은 `.loops/auth-refactor/`에 보관됩니다 — 회고·재학습용.

## 로그 조회

```bash
bash "$LOOP_SH" logs auth-refactor             # RUN_LOG.md 출력
bash "$LOOP_SH" logs auth-refactor --tail      # RUN_LOG.md 실시간 스트림
bash "$LOOP_SH" logs auth-refactor --iter 3    # 이터 #3 로그 출력
```

## DONE_WITH_CONCERNS 처리

이터가 verify는 통과했으나 self-review에서 의심점을 발견하면 `DONE` 대신 HANDOFF.md의 `## 의심점` 섹션을 작성하고 정상 종료합니다. 사용자 개입은 보통 불필요 — 다음 이터가 의심점을 읽고 검증·해소한 후 깨끗한 `DONE`을 작성합니다.

## ESCALATION 처리

**카테고리**: ESCALATION.md에 카테고리(config-gap/spec-gap/architecture-gap/environment-gap/other)가 표시되어 처리 방향을 빠르게 식별 가능

```bash
cat ../<project>-loops/<task-id>/.loop/ESCALATION.md
cd ../<project>-loops/<task-id>
$EDITOR .loop/SPEC.md             # 명세 조정
$EDITOR .loop/NOTES.md            # 학습 보강
rm .loop/ESCALATION.md            # 보고 해제
cd <project>
bash "$LOOP_SH" start <task-id>  # 재시작
```

```bash
# --watch 모드면 사용자는 ESCALATION.md 정리만 하면 자동 재시작:
bash "$LOOP_SH" start <task-id> --watch
# (ESCALATION 발생 시 driver는 60초마다 polling. 사용자가 ESCALATION.md 정리하면 즉시 재개)
```

## 동시 실행

```bash
bash "$LOOP_SH" start auth-refactor &
bash "$LOOP_SH" start schema-migration &

bash "$LOOP_SH" status                        # 모든 task 상태
git worktree list                              # 모든 워크트리

MAX_CONCURRENT=5 bash "$LOOP_SH" start new-task &   # 캡 상향
```

`MAX_CONCURRENT` 환경 변수 (기본 3)로 동시 실행 캡 조정. 같은 task-id 이중 실행은 락으로 차단됩니다.

## 환경 변수

- `LOOP_WORKTREE_BASE` — 워크트리 부모 디렉토리. 기본 `<project>/../<project-name>-loops/`. 외부 위치(`~/.claude-loops/<project>/` 등)로 변경 가능
- `MAX_CONCURRENT` — 동시 실행 task 수. 기본 3
- `MAX_ITERATIONS` — 한 task의 이터 상한. 기본 30
- `WALL_CLOCK_MINUTES` — 한 task의 시계 캡. 기본 120

## start CLI 플래그

- `--max-iterations N` — 이터 상한 (기본 30, 환경 변수 우선)
- `--wall-clock-minutes N` — 시계 캡 (기본 120, 환경 변수 우선)
- `--watch` — durable wake 모드. ESCALATION.md 감지 시 정지 대신 polling으로 재개 신호 대기. 사용자가 워크트리에서 ESCALATION.md 정리하면 자동 재시작

## 객관 게이트

드라이버가 매 이터 후 다음을 검사합니다. 위반 시 자동 halt + ESCALATION 자동 작성:

| 가드 | 기준 |
|---|---|
| 이터 상한 | `MAX_ITERATIONS` (기본 30) |
| 시계 캡 | `WALL_CLOCK_MINUTES` (기본 120) |
| 테스트 약화 | `tests/**` 해시 변경 감지 |
| 의존성 동결 | `package.json`·`requirements.txt`·`Cargo.toml` 등 매니페스트 해시 |
| Scope 위반 | git diff vs SPEC.md frontmatter의 scope.include·exclude |
| Suppressor 신규 | `noqa`·`@ts-ignore`·`eslint-disable`·`#pragma warning disable` 신규 추가 |
| Secrets | `gitleaks detect --staged` (gitleaks 설치 시) |
| fix:symptom streak | git log의 최근 2 커밋이 모두 `fix:symptom` |
| 진동 | 최근 4 커밋의 변경 파일 셋 토글 |

## 의존성

- `bash` 4+
- `git` (worktree 지원)
- `yq` ([mikefarah/yq](https://github.com/mikefarah/yq))
- `claude` CLI
- `gitleaks` (선택, secrets 게이트용)

## 안전 정지

- Ctrl+C: 진행 중 이터까지 완료 후 락 해제
- `bash "$LOOP_SH" stop <task-id>`: SIGTERM + 락 해제
- `kill <PID>`: SIGTERM. 락은 trap으로 해제됨
- 모든 `loop.sh` 종료: 각자의 락 파일이 자동 정리

## stale 락 정리

크래시로 락이 남은 경우:

```bash
ls .loops/locks/                                 # 남은 락 확인
cat .loops/locks/<task-id>.lock                  # PID 확인
kill -0 <pid> 2>/dev/null || rm .loops/locks/<task-id>.lock   # 프로세스 없으면 제거
```
