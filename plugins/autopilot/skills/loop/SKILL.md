---
name: loop
description: 단일 SPEC 파일을 격리된 전용 워크트리(워크트리 격리) 작업 공간에서 자율적으로 구현(랄프 루프, ralph loop)하고 싶을 때 사용 — SPEC 실행·자율 구현을 사람 개입 없이 백그라운드 에이전트로 위임. 호출 'Skill(skill="loop", args="<subcommand> [<args>]")' (start/status/stop/list/cleanup/logs).
allowed-tools:
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

스펙 파일 하나를 받아 로컬에서 자율 구현하는 최소 실행기다. 정체성은 **스펙 파일의 절대 경로**다. 작업 공간은 스펙 디렉토리 아래 전용 워크트리(`<spec_dir>/.worktree`)로, 호출 위치와 무관하게 항상 새로 생성한다(보조 worktree 안에서 호출돼도 재사용하지 않음) — 정확한 경로는 `loop.sh paths <spec>`. **terminal 의도는 `.loop/signals/` 디렉토리**에 워커가 파일을 만들어 표현하고, driver 는 `signals/` 비어있는지만 본다.

워커 헌법은 `references/constitution.md`, 셸 드라이버는 `references/loop.sh`가 단일 출처다.

## 호출

`Skill(skill: "loop", args: "<subcommand> [<args>]")`

loop은 어떤 도구가 만든 스펙이든 **임의의 스펙 파일 경로**를 받는다.

## Subcommands

### start <spec-path> [--max-iterations N] [--wall-clock-minutes N]

> 위 bracket의 플래그(`--max-iterations`·`--wall-clock-minutes`)는 `loop.sh`가 받는 인자다.

`Bash(bash $SKILL_DIR/references/loop.sh start <spec-path> [...flags])`로 **포그라운드(동기)**로 실행한다. start 는 이터레이션 루프가 끝날 때까지 블로킹하고, 종료 후 호출자가 `signals/` 내용을 직접 검사한다.

**비차단(non-blocking)이 필요하면** loop 을 `run_in_background`로 직접 띄우지 말고, loop 스킬을 **백그라운드 서브에이전트로 dispatch**하고 그 서브에이전트가 위 명령으로 loop 을 **포그라운드**로 실행하게 한다. 이유: 서브에이전트 안에서 loop 을 백그라운드 프로세스로 띄우면 서브에이전트 턴이 끝나는 순간 그 백그라운드 프로세스가 kill 되어 워커가 산출물 없이 실패한다(통제 실험으로 확인). 같은 서브에이전트라도 포그라운드 실행은 루프 종료까지 살아남아 정상 완료한다.

driver 동작: 검증 → lock 획득 → 작업 공간 준비(헌법을 `CLAUDE.md`와 `AGENTS.md`로 복사) → 이터레이션 루프. 매 이터는 선택된 worker CLI의 새 비대화형 프로세스. 계산된 경로는 `loop.sh paths <spec>`.

#### 진행 관찰

포그라운드 start 는 종료까지 블로킹하므로 실시간 진행을 보려면 loop 이 디스크에 남기는 실행 아티팩트를 따로 관찰한다 — 이터레이션 로그는 `loop.sh logs <spec>`, terminal 신호는 `signals/` 디렉토리(경로는 `loop.sh paths <spec>`)다. 백그라운드 서브에이전트 경유로 돌릴 때도 호출 세션은 이 아티팩트를 폴링해 진행을 확인한다.

### 신호 계약

워커 계약(노트·`.loop/signals/` 디렉토리 규칙·권장 컨벤션 DONE/BLOCKED + category 값)의 SoT 는 `references/constitution.md §작업 매체`. driver 는 `signals/` 가 비어있는지만 보고 내용을 파싱하지 않는다. 호출자는 종료 후 `signals/` 내용을 직접 검사한다.

### status / stop / list / cleanup / logs

각각 `Bash(bash $SKILL_DIR/references/loop.sh <subcommand> [args])`로 위임하고 결과를 요약한다. `status` 형식은 `references/status-format.md`. `status --json [<spec>]`은 기계 판독 가능한 구조화 상태(JSON)를 출력해 호출 레이어(dispatch 등)가 컬럼 위치·부분 문자열 일치 없이 종료 상태를 판정하게 한다. lock은 워크트리 생성 전에 획득해 race 보호. 경로 상세는 `loop.sh paths <spec>`. `list`는 작업트리를 스캔해 실행을 열거한다. `cleanup`은 `signals/` 비어있지 않음 확인 후(또는 `--force`) 워크트리와 lock을 제거한다.

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
