---
name: dispatch
description: "하나 이상의 SPEC 파일을 구현 단계로 넘기고 싶을 때 사용 — 의존성(depends_on)을 풀어 각 SPEC 을 준비되는 즉시 자율 실행기에 스트리밍 위임하고 결과를 취합. 호출 'Skill(skill=\"dispatch\", args=\"<subcommand> [<args>]\")' (start/list/status/stop/watch)."
---

# dispatch

`dispatch` 는 SPEC 파일 묶음을 받아 의존성을 풀고, 각 SPEC 을 그 의존성이 모두 끝나는 즉시(준비도 기반 스트리밍) 자율 실행기(`autopilot:loop`)에 위임하는 오케스트레이터다. SPEC 작성 도구·작성 형식에 비결합 — **파일로 존재하고 읽을 수 있는 SPEC 이면** 무엇이든 입력으로 받는다.

## 호출

`Skill(skill: "dispatch", args: "<subcommand> [<args>]")`

## 모델

- 입력: 1 개 이상의 SPEC 파일 경로 (가변 인자).
- DAG: 각 SPEC frontmatter 의 `depends_on:` (sibling slug 또는 경로) 항목으로 의존 관계를 구성한다. 외부 DAG 명세 파일을 요구하지 않는다. 위상정보(`WAVES.txt`)는 진단용으로 남기되, 실제 실행은 wave 배리어가 아니라 SPEC별 준비도로 구동한다.
- cycle 이 발견되면 cycle 구성 요소를 보고하고 실행을 시작하지 않는다(비-0 종료).
- **준비도 스트리밍**: 각 SPEC 은 자신의 `depends_on` 이 모두 `done` 이 되는 즉시 — 같은 위상의 무관한 SPEC 이 아직 실행 중이어도 기다리지 않고 — 동시성 상한 이내에서 시작된다. 기본 동시 실행 상한은 없으며 `--max-parallel N`(전역 동시 실행 상한) 으로 줄 수 있다.
- 각 child 의 종료·차단 여부는 자율 실행기의 **공개 인터페이스가 제공하는 구조화된(기계 판독) 상태**(`loop status --json` 의 `.state`·`.signals[]`)로만 판정한다 — 출력 표의 컬럼 위치나 자유 텍스트 부분 문자열 일치에 의존하지 않는다. 자율 실행기 내부 신호 파일·worktree 를 직접 읽지 않는다.
- **이행적 실패 전파**: 한 SPEC 이 `failed` 로 끝나면 그 SPEC 의 **이행적 의존자만** `skipped` 로 차단하고, 의존 관계가 없는 가지는 끝까지 실행한다(기존 wave fail-fast 와 다름).
- 호출마다 결정성 있는 `run-id`(타임스탬프 + 입력 SPEC 집합 sha7)를 만들고 진행 상태를 `<project_root>/.dispatch/runs/<run-id>/` 아래에 보관한다.
- 기존 `run-id` 로 재호출되면 보관된 상태를 읽어 이미 `done` 인 SPEC 은 재실행하지 않고, 미완 SPEC 만 스트리밍 스케줄에 따라 이어 수행한다.

## Subcommands

### dispatch start `<spec...>` [--max-parallel N] [--resume `<run-id>`]

1 개 이상의 SPEC 파일 경로를 받아 새 run 을 시작한다.

- 입력 검증: 각 경로가 파일로 존재하고 읽을 수 있어야 한다. 하나라도 누락이면 보고 후 즉시 abort.
- DAG 구성: 각 SPEC frontmatter 의 `depends_on` 을 읽어 의존 인덱스를 만든다. cycle 이면 abort. 진단용 `WAVES.txt` 도 함께 기록(실행 스케줄은 준비도 기반).
- `<project_root>/.dispatch/runs/<run-id>/MANIFEST.txt` · `WAVES.txt` · `state.<slug>-<sha7>` · `LOG.md` 생성. (`<slug>` 는 가독용, `<sha7>` 는 SPEC abspath 해시로 다른 날짜·디렉토리 동명 SPEC 충돌 방지.) state 값: `pending`/`running`/`done`/`failed`/`skipped`.
- 준비도 스트리밍: 각 SPEC 의 모든 dep 이 done 이 되는 즉시 동시성 상한 이내에서 위임 시작. 한 SPEC 이 failed 면 그 이행적 의존자만 `skipped`, 독립 가지는 계속.
- `--resume <run-id>` 이면 보관된 manifest 로 재개. `done` 인 SPEC 은 재호출하지 않고 나머지(미완)만 다시 스케줄한다.
- 한 child 가 `DISPATCH_WAVE_TIMEOUT_SECONDS`(기본 7200) 를 초과하면(per-SPEC runtime cap) 그 child 를 SIGTERM→SIGKILL 으로 정리하고 `failed` 로 마킹한다(이미 done 이면 보존).
- exit code: `0`=전부 done, `1`=failed/skipped 있음, `2`=timeout.

### dispatch list

`<project_root>/.dispatch/runs/` 아래의 모든 run-id 와 요약을 표시한다.

### dispatch status `<run-id>`

run-id 단위로 per-SPEC state(`pending`/`running`/`done`/`failed`/`skipped`) 를 표로 출력한다(진단용 wave 번호 포함). loop driver 의 라이브 state 도 함께 보인다.

### dispatch stop `<run-id>`

run-id 안에서 진행 중(`running`)인 child 들에 대해 자율 실행기에 stop 을 위임한다.

### dispatch watch `<run-id>`

per-SPEC 상태를 주기적으로 refresh 하며, 모든 child 가 terminal(`done`/`failed`/`skipped`)에 도달하면 exit code 로 결과를 대표한다. `0`=전부 done, `1`=failed/skipped 있음, `2`=timeout.

## references

| 파일 | 역할 |
|---|---|
| `dispatch.sh` | run-id 디렉토리 관리·의존 인덱스 구성·준비도 스트리밍 위임·구조화 종료 판정 driver |

## 의존성

`git`, `bash` 3.2+, `sha256sum` 또는 `shasum`, `autopilot:loop` 스킬, `yq`(mikefarah). `yq` 는 depends_on 파싱(없으면 awk 폴백)뿐 아니라 **loop 구조화 상태(`status --json`) 판정의 단일 출처**이므로 `start`/`status`/`stop`/`watch` 에서 필수다(부재 시 명확히 정지 — 텍스트 컬럼으로 silent fallback 하지 않음).

## 규칙

- 자체 작성·갱신하는 영역은 `<project_root>/.dispatch/runs/<run-id>/` 디렉토리 안의 파일들과 본 스킬의 정의 파일뿐이다. 이 외 경로를 만들지 않는다.
- 자율 실행기 인터페이스(`loop.sh start|status|stop`) 외 child 워크트리·신호 파일을 직접 들여다보지 않는다.
- 분해(여러 SPEC 작성) 책임은 SPEC 작성 도구(`autopilot:spec` 등)에 있고, dispatch 는 이미 만들어진 SPEC 들만 받는다.
- child 의 종료 의도(완료/차단)는 자율 실행기가 신호로 표현하고, dispatch 는 그 공개 인터페이스가 제공하는 **구조화된 상태**(`loop.sh status --json` 의 `.state`·`.signals[]`)로만 읽는다 — 표 컬럼 위치·부분 문자열 일치에 의존하지 않는다. `signals` 의 의미(`DONE`/`BLOCKED`)는 워커 컨벤션이며 dispatch 는 정확 일치 멤버십으로 판정한다.
- run 디렉토리는 git 추적에서 제외한다(`.gitignore` 처리 권장).
