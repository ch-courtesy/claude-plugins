---
name: dispatch
description: "하나 이상의 SPEC 파일을 구현 단계로 넘기고 싶을 때 사용 — 의존성(depends_on)을 풀어 wave 단위로 자율 실행기에 병렬 위임하고 결과를 취합. 호출 'Skill(skill=\"dispatch\", args=\"<subcommand> [<args>]\")' (start/list/status/stop/watch)."
---

# dispatch

`dispatch` 는 SPEC 파일 묶음을 받아 의존성을 풀고 wave 단위로 자율 실행기(`autopilot:loop`)에 병렬 위임하는 오케스트레이터다. SPEC 작성 도구·작성 형식에 비결합 — **파일로 존재하고 읽을 수 있는 SPEC 이면** 무엇이든 입력으로 받는다.

## 호출

`Skill(skill: "dispatch", args: "<subcommand> [<args>]")`

## 모델

- 입력: 1 개 이상의 SPEC 파일 경로 (가변 인자).
- DAG: 각 SPEC frontmatter 의 `depends_on:` (sibling slug 또는 경로) 항목으로 위상정렬해 wave 를 자동 구성한다. 외부 DAG 명세 파일을 요구하지 않는다.
- cycle 이 발견되면 cycle 구성 요소를 보고하고 실행을 시작하지 않는다.
- wave 안 SPEC 들은 자율 실행기에 병렬 위임한다. 기본 동시 시작 상한은 없으며 `--max-parallel N` 으로 줄 수 있다.
- 각 child 의 종료·차단 여부는 자율 실행기의 공개 인터페이스만으로 판단한다. 자율 실행기 내부 신호 파일 포맷·외부 task 저장소 라벨·issue 상태에 직접 결합하지 않는다.
- 한 wave 에서 어떤 child 라도 실패·차단으로 끝나면 다음 wave 진입을 차단한다. 같은 wave 에서 이미 시작된 다른 child 의 진행은 계속한다.
- 호출마다 결정성 있는 `run-id`(타임스탬프 + 입력 SPEC 집합 sha7)를 만들고 진행 상태를 `<project_root>/.dispatch/runs/<run-id>/` 아래에 보관한다.
- 기존 `run-id` 로 재호출되면 보관된 상태를 읽어 이미 done 인 child 는 재실행하지 않고 미완 wave 부터 이어 수행한다.

## Subcommands

### dispatch start `<spec...>` [--max-parallel N] [--resume `<run-id>`]

1 개 이상의 SPEC 파일 경로를 받아 새 run 을 시작한다.

- 입력 검증: 각 경로가 파일로 존재하고 읽을 수 있어야 한다. 하나라도 누락이면 보고 후 즉시 abort.
- DAG 구성: 각 SPEC frontmatter 의 `depends_on` 을 읽어 위상정렬. cycle 이면 abort.
- `<project_root>/.dispatch/runs/<run-id>/MANIFEST.txt` · `WAVES.txt` · `state.<slug>-<sha7>` · `LOG.md` 생성. (`<slug>` 는 가독용, `<sha7>` 는 SPEC abspath 해시로 다른 날짜·디렉토리 동명 SPEC 충돌 방지.)
- wave 순서대로 자율 실행기에 위임 호출하며 각 wave 의 모든 child 종료를 기다린 뒤 다음 wave 로 진입.
- `--resume <run-id>` 이면 보관된 manifest 로 재개. done 인 child 는 재호출하지 않는다.
- 한 wave 가 `DISPATCH_WAVE_TIMEOUT_SECONDS`(기본 7200) 를 초과하면 미종료 child 를 SIGTERM→SIGKILL 으로 정리하고 해당 SPEC 들을 failed 로 마킹한 뒤 다음 wave 진입을 차단한다.
- exit code: `0`=전부 done, `1`=child 실패로 wave 차단, `2`=timeout.

### dispatch list

`<project_root>/.dispatch/runs/` 아래의 모든 run-id 와 요약을 표시한다.

### dispatch status `<run-id>`

run-id 단위로 per-SPEC wave 와 현재 state(`pending`/`running`/`done`/`failed`) 를 표로 출력한다. loop driver 의 라이브 state 도 함께 보인다.

### dispatch stop `<run-id>`

run-id 안에서 진행 중(`running`)인 child 들에 대해 자율 실행기에 stop 을 위임한다.

### dispatch watch `<run-id>`

per-SPEC 상태를 주기적으로 refresh 하며, 모든 child 가 terminal 에 도달하면 exit code 로 결과를 대표한다. `0`=전부 done, `1`=하나라도 failed, `2`=timeout.

## references

| 파일 | 역할 |
|---|---|
| `dispatch.sh` | run-id 디렉토리 관리·DAG 구성·wave 위임·child 종료 판정 driver |

## 의존성

`git`, `bash` 3.2+, `sha256sum` 또는 `shasum`, `autopilot:loop` 스킬. `yq` 가 있으면 depends_on 파싱이 더 견고하다(없으면 awk 폴백).

## 규칙

- 자체 작성·갱신하는 영역은 `<project_root>/.dispatch/runs/<run-id>/` 디렉토리 안의 파일들과 본 스킬의 정의 파일뿐이다. 이 외 경로를 만들지 않는다.
- 자율 실행기 인터페이스(`loop.sh start|status|stop`) 외 child 워크트리·신호 파일을 직접 들여다보지 않는다.
- 분해(여러 SPEC 작성) 책임은 SPEC 작성 도구(`autopilot:spec` 등)에 있고, dispatch 는 이미 만들어진 SPEC 들만 받는다.
- child 의 종료 의도(완료/차단)는 자율 실행기가 신호로 표현하고, dispatch 는 그 공개 인터페이스(`loop.sh status` 의 STATE·FILES 컬럼)로만 읽는다.
- run 디렉토리는 git 추적에서 제외한다(`.gitignore` 처리 권장).
