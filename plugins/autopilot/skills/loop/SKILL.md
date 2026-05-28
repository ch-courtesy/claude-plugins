---
name: loop
description: 스펙 파일 기반 로컬 자율 수행 루프(랄프 루프) 운영 인터페이스. 스펙 파일 경로를 받아 격리 작업 공간에서 자율 구현하고 DONE/BLOCKED 파일로 신호한다. start/status/stop/list/cleanup/logs 서브커맨드로 lifecycle을 관리한다.
allowed-tools:
  - Monitor
  - Read
  - Bash(bash * loop.sh start:*)
  - Bash(bash * loop.sh status:*)
  - Bash(bash * loop.sh stop:*)
  - Bash(bash * loop.sh list)
  - Bash(bash * loop.sh cleanup:*)
  - Bash(bash * loop.sh logs:*)
  - Bash(bash * loop.sh env)
  - Bash(bash * loop.sh gates)
  - Bash(bash * loop.sh paths:*)
  - Bash(bash * loop.sh deps)
  - Bash(bash * loop.sh signals)
  - Bash(git -C * status:*)
  - Bash(git -C * log:*)
  - Bash(git -C * diff:*)
  - Bash(git -C * stash list)
  - Bash(git -C * stash show:*)
  - Bash(git -C * stash pop:*)
---

# loop

스펙 파일 하나를 받아 로컬에서 자율 구현하는 최소 실행기다. 정체성은 **스펙 파일의 절대 경로**다. 작업 공간은 스펙 파일 디렉토리 아래 `.worktree`(이미 보조 worktree 안이면 현재 cwd), 이터 간 노트는 작업 공간 안에, 완료·차단은 **DONE·BLOCKED 신호 파일**로 표현한다.

워커 헌법은 `references/constitution.md`, 셸 드라이버는 `references/loop.sh`가 단일 출처다.

## 호출

`Skill(skill: "loop", args: "<subcommand> [<args>]")`

loop은 어떤 도구가 만든 스펙이든 **임의의 스펙 파일 경로**를 받는다.

## Subcommands

### start <spec-path> [--max-iterations N] [--wall-clock-minutes N] [--no-monitor] [--events-only]

반드시 `Bash(bash $SKILL_DIR/references/loop.sh start <spec-path> [...flags], run_in_background: true)`로 실행한다. 동기 실행은 Monitor 가설을 막으므로 금지.

driver 동작: 스펙 파일 존재 검증, lock 획득, 작업 공간 준비(주 작업트리면 `<spec_dir>/.worktree` git worktree 생성 + 헌법을 CLAUDE.md로 복사; 보조 worktree 안이면 현재 cwd 사용), 이터레이션 루프. 매 이터는 새 `claude --print` 프로세스다.

#### Monitor

기본 ON. `--no-monitor`가 없으면 start 직후 `Monitor`를 붙인다. 기본 필터는 빈 줄과 단독 dot만 제외하고 stdout raw 라인을 통과시킨다. `--events-only`는 SKILL.md 차원 옵션이며 `loop.sh`로 전달하지 않는다 — 핵심 이벤트(`이터 #`, HALT, WARN, FAIL, ERROR, rate limit, claude 비정상, DONE/BLOCKED 신호)만 알림한다. `--no-monitor`가 함께 있으면 `--no-monitor`가 우선한다.

### 신호 계약

워커 신호(DONE/BLOCKED) 경로·category 분류·driver 반응(예: 1회차 `spec-gap` BLOCKED → exit 3 "스펙 강화 필요")의 단일 출처: `loop.sh signals`. 동일 텍스트가 start 시 워커의 CLAUDE.md 끝에 append 된다.

### status / stop / list / cleanup / logs

각각 `Bash(bash $SKILL_DIR/references/loop.sh <subcommand> [args])`로 위임하고 결과를 요약한다. `status` 형식은 `references/status-format.md`. lock은 `<spec_dir>/.loop-lock`(워크트리 생성 전 획득해 race 보호), 노트·신호·이터 로그는 `<spec_dir>/.worktree/.loop/` 안에 둔다. `list`는 작업트리를 스캔해 실행을 열거한다. `cleanup`은 DONE 확인 후(또는 `--force`) 워크트리와 lock을 제거한다.

### env / gates / paths / deps / signals

driver 인터페이스의 self-emit 단일 출처: `loop.sh env`(환경 변수) · `loop.sh gates`(객관 게이트) · `loop.sh paths <spec>`(계산된 경로) · `loop.sh deps`(의존성 + 설치 상태) · `loop.sh signals`(워커 신호·driver 반응 계약). 지침은 본문에 중복 열거하지 않고 이 subcommand 를 가리킨다.

## references

| 파일 | 역할 |
|---|---|
| `constitution.md` | 워커 헌법 |
| `loop.sh` | 핵심 driver |
| `operational-guide.md` | 운영 가이드 |
| `status-format.md` | status 출력 |
| `troubleshooting.md` | 차단 처리 |
| `agent-prompts.md` | 이터 내 Agent brief |

## 의존성

필수·선택 의존성과 현재 설치 상태는 `loop.sh deps` 로 확인.

## 규칙

- 명시된 subcommand만 실행한다. 다른 subcommand를 자동 추론하지 않는다.
- 작업 공간(`<spec_dir>/.worktree`)·lock·신호 파일 외 파일은 만들지 않는다.
- subcommand exit code를 그대로 던지지 말고 사용자에게 요약한다.
- 프로젝트별 constitution override는 아직 미지원이다.
