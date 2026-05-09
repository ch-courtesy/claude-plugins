# 자율 루프 (`.loops/`)

이 디렉토리는 sibling 워크트리 기반 외부 셸 드라이버를 가진 단일 task 자율 수행 환경입니다.

## 핵심 가정

- 매 이터는 새 `claude --print` 프로세스 (콜드 스타트). 기억은 LLM이 아닌 파일에 있습니다.
- 작업은 `<project>/../<project-name>-loops/<task-id>/` (sibling 워크트리)에서 일어납니다.
- 격리: 워크트리는 프로젝트 트리 밖에 있어 프로젝트 `CLAUDE.md`·hooks가 자동 차단됩니다.
- 사용자 레벨 `~/.claude/CLAUDE.md`·`~/.claude/settings.json`은 차단 불가 — **루프 시작 전 본인 환경을 검토**하시는 것을 권장합니다.

## 디렉토리 구조

```
.loops/
├── README.md                  # 본 문서
├── PROMPT.template.md         # 새 task의 PROMPT.md 시드
├── loop.sh                    # 외부 드라이버
├── templates/                 # 메모리 파일 스텁
├── locks/                     # 동시 실행 락 (gitignored)
└── archive/                   # DONE된 task의 메타 파일 보관
```

런타임 워크트리:
```
<project>/../<project-name>-loops/<task-id>/
├── CLAUDE.md                  # 헌법 (rules/autonomous-loop.md 복사본)
├── .loop/                     # 메타 파일 (워크트리 .git/info/exclude로 비추적)
│   ├── PROMPT.md              # 작업 정의 (사용자 작성)
│   ├── PLAN.md                # 마일스톤 (모델 갱신)
│   ├── NOTES.md               # 학습 누적 (모델 갱신)
│   ├── HANDOFF.md             # 직전 → 다음 편지 (모델 매 이터 덮어쓰기)
│   ├── RUN_LOG.md             # 한 줄 요약 누적
│   ├── iterations/<n>.log     # 매 이터 stdout 캡처
│   └── ESCALATION.md          # 정지 사유 (있을 때만)
└── (프로젝트 파일들 — autonomous-loop/<task-id> 브랜치 체크아웃)
```

## 새 task 시작

```bash
# 1. 첫 호출 — 워크트리 + 메타 파일 생성
./.loops/loop.sh auth-refactor
# 출력: "워크트리 생성: ../<project>-loops/auth-refactor"
#       "다음 파일을 채워 주세요: ../<project>-loops/auth-refactor/.loop/PROMPT.md"

# 2. PROMPT.md에 작업 정의 채움
$EDITOR ../<project>-loops/auth-refactor/.loop/PROMPT.md
# - YAML frontmatter: scope.include / scope.exclude / verify
# - 본문 placeholder: {{task_description}}, {{acceptance_criteria}}, ...

# 3. 두 번째 호출 — 실제 루프 시작
./.loops/loop.sh auth-refactor

# 4. 진행 모니터링 (별도 터미널)
tail -f ../<project>-loops/auth-refactor/.loop/RUN_LOG.md

# 5. 정지: Ctrl+C, 또는 DONE/ESCALATION.md가 생기면 자동 종료
```

## DONE 후 머지

```bash
cd ../<project>-loops/auth-refactor
git log autonomous-loop/auth-refactor

cd <project>
git merge autonomous-loop/auth-refactor    # 또는 PR 생성
git worktree remove ../<project>-loops/auth-refactor
git branch -d autonomous-loop/auth-refactor
```

archive 메타 파일은 `.loops/archive/auth-refactor/`에 보관됩니다 — 회고·재학습용.

## DONE_WITH_CONCERNS 처리

이터가 verify는 통과했으나 self-review에서 의심점을 발견하면 `DONE` 대신 HANDOFF.md의 `## 의심점` 섹션을 작성하고 정상 종료합니다. 사용자 개입은 보통 불필요 — 다음 이터가 의심점을 읽고 검증·해소한 후 깨끗한 `DONE`을 작성합니다.

다음 이터가 의심점을 해소하지 못하면:
- 의심점이 NOTES.md의 "확정된 사실"·"실패한 접근"으로 옮겨가 누적
- 의심이 fix:symptom 누적이나 architecture-gap ESCALATION으로 발전 가능

## ESCALATION 처리

**카테고리**: ESCALATION.md에 카테고리(config-gap/spec-gap/architecture-gap/environment-gap/other)가 표시되어 처리 방향을 빠르게 식별 가능

```bash
cat ../<project>-loops/<task-id>/.loop/ESCALATION.md
cd ../<project>-loops/<task-id>
$EDITOR .loop/PROMPT.md           # 명세 조정
$EDITOR .loop/NOTES.md            # 학습 보강
rm .loop/ESCALATION.md            # 보고 해제
cd <project>
./.loops/loop.sh <task-id>        # 재시작
```

```bash
# --watch 모드면 사용자는 ESCALATION.md 정리만 하면 자동 재시작:
./.loops/loop.sh <task-id> --watch         # 처음 시작 시 watch 모드
# (ESCALATION 발생 시 driver는 60초마다 polling. 사용자가 ESCALATION.md 정리하면 즉시 재개)
```

## 동시 실행

```bash
./.loops/loop.sh auth-refactor &
./.loops/loop.sh schema-migration &

tail -f ../<project>-loops/*/.loop/RUN_LOG.md

MAX_CONCURRENT=5 ./.loops/loop.sh new-task &   # 캡 상향

git worktree list                              # 모든 워크트리
ls .loops/locks/                                # 모든 RUNNING 락
```

`MAX_CONCURRENT` 환경 변수 (기본 3)로 동시 실행 캡 조정. 같은 task-id 이중 실행은 락으로 차단됩니다.

## 환경 변수

- `LOOP_WORKTREE_BASE` — 워크트리 부모 디렉토리. 기본 `<project>/../<project-name>-loops/`. 외부 위치(`~/.claude-loops/<project>/` 등)로 변경 가능
- `MAX_CONCURRENT` — 동시 실행 task 수. 기본 3
- `MAX_ITERATIONS` — 한 task의 이터 상한. 기본 30
- `WALL_CLOCK_MINUTES` — 한 task의 시계 캡. 기본 120

## CLI 플래그

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
| Scope 위반 | git diff vs PROMPT.md frontmatter의 scope.include·exclude |
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
- `kill <PID>`: SIGTERM. 락은 trap으로 해제됨
- 모든 `loop.sh` 종료: 각자의 락 파일이 자동 정리
