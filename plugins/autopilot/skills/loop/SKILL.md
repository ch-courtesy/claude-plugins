---
name: loop
description: 단일 SPEC 파일을 격리 작업 공간에서 자율적으로 구현(랄프 루프)하고 싶을 때 사용. 호출 'Skill(skill="loop", args="<subcommand> [<args>]")' (start/status/stop/list/cleanup/logs).
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
  - Bash(git -C * status:*)
  - Bash(git -C * log:*)
  - Bash(git -C * diff:*)
  - Bash(git -C * stash list)
  - Bash(git -C * stash show:*)
  - Bash(git -C * stash pop:*)
---

# loop

스펙 파일 하나를 받아 로컬에서 자율 구현하는 최소 실행기다. 정체성은 **스펙 파일의 절대 경로**다. 작업 공간은 스펙 디렉토리 아래(보조 worktree 안이면 현재 cwd) — 정확한 경로는 `loop.sh paths <spec>`. **terminal 의도는 `.loop/signals/` 디렉토리**에 워커가 파일을 만들어 표현하고, driver 는 `signals/` 비어있는지만 본다.

워커 헌법은 `references/constitution.md`, 셸 드라이버는 `references/loop.sh`가 단일 출처다.

## 호출

`Skill(skill: "loop", args: "<subcommand> [<args>]")`

loop은 어떤 도구가 만든 스펙이든 **임의의 스펙 파일 경로**를 받는다.

## Subcommands

### start <spec-path> [--max-iterations N] [--wall-clock-minutes N] [--no-monitor] [--events-only]

반드시 `Bash(bash $SKILL_DIR/references/loop.sh start <spec-path> [...flags], run_in_background: true)`로 실행한다. 동기 실행은 Monitor 가설을 막으므로 금지.

driver 동작: 검증 → lock 획득 → 작업 공간 준비(헌법을 `CLAUDE.md`로 복사) → 이터레이션 루프. 매 이터는 새 `claude --print` 프로세스. 계산된 경로는 `loop.sh paths <spec>`.

#### Monitor

기본 ON. `--no-monitor`가 없으면 start 직후 `Monitor`를 붙인다. 기본 필터는 빈 줄과 단독 dot만 제외하고 stdout raw 라인을 통과시킨다. `--events-only`는 SKILL.md 차원 옵션이며 `loop.sh`로 전달하지 않는다 — 핵심 이벤트(`이터 #`, HALT, WARN, FAIL, ERROR, rate limit, claude 비정상, terminal 신호 감지)만 알림한다. `--no-monitor`가 함께 있으면 `--no-monitor`가 우선한다.

### 신호 계약

워커 계약(노트·`.loop/signals/` 디렉토리 규칙·권장 컨벤션 DONE/BLOCKED + category 값)의 SoT 는 `references/constitution.md §작업 매체`. driver 는 `signals/` 가 비어있는지만 보고 내용을 파싱하지 않는다. 호출자는 종료 후 `signals/` 내용을 직접 검사한다.

### status / stop / list / cleanup / logs

각각 `Bash(bash $SKILL_DIR/references/loop.sh <subcommand> [args])`로 위임하고 결과를 요약한다. `status` 형식은 `references/status-format.md`. lock은 워크트리 생성 전에 획득해 race 보호. 경로 상세는 `loop.sh paths <spec>`. `list`는 작업트리를 스캔해 실행을 열거한다. `cleanup`은 `signals/` 비어있지 않음 확인 후(또는 `--force`) 워크트리와 lock을 제거한다.

### env / gates / paths / deps

driver 인터페이스의 self-emit 단일 출처: `loop.sh env`(환경 변수) · `loop.sh gates`(객관 게이트) · `loop.sh paths <spec>`(계산된 경로) · `loop.sh deps`(의존성 + 설치 상태). 지침은 본문에 중복 열거하지 않고 이 subcommand 를 가리킨다.

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
- 작업 공간·lock·신호 파일 외 파일은 만들지 않는다(경로는 `loop.sh paths`).
- subcommand exit code를 그대로 던지지 말고 사용자에게 요약한다.
- 프로젝트별 constitution override는 아직 미지원이다.
