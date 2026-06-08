---
name: dispatch
description: "하나 이상의 SPEC 파일을 구현·머지 단계로 넘기고 싶을 때 사용 — depends_on 준비도를 풀어 **준비된 SPEC마다 서브에이전트를 1개 띄우는 모델 주도 오케스트레이터**. 각 서브에이전트가 자기 컨텍스트에서 그 SPEC 의 구현→리뷰→머지를 소유하고, dispatch 는 의존성·동시성·실패 격리만 총괄해 머지(=done)되면 의존자를 해제한다. fan-out 드라이버는 실행 환경 자동 감지 또는 DISPATCH_DRIVER override(strong-parallel|background|foreground-batch)로 선택되며 안전 강등 사슬(강한 병렬→백그라운드→포그라운드 배치)을 따른다. 호출 'Skill(skill=\"dispatch\", args=\"<subcommand> [<args>]\")' (start/list/status/stop/watch/driver)."
allowed-tools:
  - Read
  - Bash(bash * dispatch.sh start:*)
  - Bash(bash * dispatch.sh list)
  - Bash(bash * dispatch.sh status:*)
  - Bash(bash * dispatch.sh stop:*)
  - Bash(bash * dispatch.sh watch:*)
  - Bash(bash * dispatch.sh driver:*)
  - Bash(bash * dispatch.sh selftest:*)
---

# dispatch

`dispatch` 는 SPEC 파일 묶음을 받아 depends_on 의존성을 풀고, **준비된(모든 dep 이 done) SPEC마다 서브에이전트를 1개 띄우는 모델 주도 오케스트레이터**다. 각 SPEC 서브에이전트는 자기 컨텍스트에서 `loop`(구현)·`review`(리뷰) 스킬을 공개 인터페이스로 승인까지 반복 호출하고 대상 브랜치로 머지하기까지 그 SPEC 의 전 생애를 소유한다(서브에이전트 절차 계약: `references/spec-subagent.md`). dispatch 자신은 준비도 스케줄링·동시성 상한·서브에이전트 spawn/reap·done(=머지)이면 의존자 해제·실패 이행 격리만 책임지며, **통합·리뷰·머지를 더 이상 bash 드레인 파이프라인으로 직접 수행하지 않는다**. SPEC 작성 도구·작성 형식에 비결합 — **파일로 존재하고 읽을 수 있는 SPEC 이면** 무엇이든 입력으로 받는다.

## 호출

`Skill(skill: "dispatch", args: "<subcommand> [<args>]")`

## 모델

- 입력: 1 개 이상의 SPEC 파일 경로 (가변 인자).
- DAG: 각 SPEC frontmatter 의 `depends_on:` (sibling slug 또는 경로) 항목으로 의존 관계를 구성한다. 외부 DAG 명세 파일을 요구하지 않는다. 위상정보(`WAVES.txt`)는 진단용으로 남기되, 실제 실행은 wave 배리어가 아니라 SPEC별 준비도로 구동한다.
- cycle 이 발견되면 cycle 구성 요소를 보고하고 실행을 시작하지 않는다(비-0 종료).
- **준비도 스트리밍**: 각 SPEC 은 자신의 `depends_on` 이 모두 `done` 이 되는 즉시 — 같은 위상의 무관한 SPEC 이 아직 실행 중이어도 기다리지 않고 — 동시성 상한 이내에서 시작된다. 기본 동시 실행 상한은 없으며 `--max-parallel N`(전역 동시 실행 상한) 으로 줄 수 있다.
- 각 서브에이전트의 결과(머지됨/비완료)는 **구조화된(기계 판독) 보고**로 받아 판정한다 — 자유 텍스트 부분 문자열 일치에 의존하지 않는다. 서브에이전트가 그 안에서 호출하는 `loop`·`review` 의 내부 신호 파일·worktree·하니스를 dispatch 가 직접 들여다보지 않는다(블랙박스 경계). 서브에이전트 자신은 `loop status --json` 의 `.state`·`.signals[]` 같은 공개 구조화 상태로 loop 종료를 판정한다.
- **이행적 실패 전파**: 한 SPEC 이 `failed` 로 끝나면 그 SPEC 의 **이행적 의존자만** `skipped` 로 차단하고, 의존 관계가 없는 가지는 끝까지 실행한다(기존 wave fail-fast 와 다름).
- 호출마다 결정성 있는 `run-id`(타임스탬프 + 입력 SPEC 집합 sha7)를 만들고 진행 상태를 `<project_root>/.dispatch/runs/<run-id>/` 아래에 보관한다.
- 기존 `run-id` 로 재호출되면 보관된 상태를 읽어 이미 `done` 인 SPEC 은 재실행하지 않고, 미완 SPEC 만 스트리밍 스케줄에 따라 이어 수행한다.

## 서브에이전트 위임 — 준비된 SPEC당 1개

준비된(모든 dep 이 done) SPEC마다 서브에이전트를 **정확히 1개** 띄우고, 그 서브에이전트가 한 컨텍스트에서 그 SPEC 의 구현→리뷰→재구현→머지를 닫는다. **서브에이전트 절차의 단일 출처는 `references/spec-subagent.md`**(완료 조건 2–8: loop/review 블랙박스 호출·forge/direct 서브모드·무한루프 가드·approve 후 머지 게이트·force 금지·동시 머지 직렬화·에스컬레이션). dispatch 는 그 내부를 들여다보지 않고 결과(머지됨/비완료)만 받는다.

dispatch 자신의 책임은 **결정적 오케스트레이션**뿐이며 `dispatch.sh` 헬퍼로 분리되어 selftest 로 검증된다:

- **준비도·격리**: depends_on 준비도 스케줄링·동시성 상한·서브에이전트 spawn/reap·실패 이행 격리(spawn 은 Agent 도구를 쓰는 살아있는 컨텍스트가 수행 — bash 무인 파이프라인 아님).
- **머지=done 전이**: 서브에이전트가 머지를 보고한 SPEC 만 `done`(=대상 브랜치 머지됨)으로 전이해 의존자를 해제하므로, 의존자는 의존성이 머지된 뒤에야 갱신된 대상 브랜치 위에서 분기한다. 비완료 보고는 `failed` 로 두고 **그 이행적 의존자만** `skipped`(독립 가지는 계속).
- **대상 브랜치**: `--target-branch <branch>`(미지정 시 기본 브랜치 또는 주입된 `DEFAULT_BRANCH`). run 전역으로 결정돼 모든 서브에이전트의 base 동기화·리뷰·ff 머지에 일관 적용되고, run-dir 마커(`TARGET_BRANCH`)로 영속해 `--resume` 에서 sticky 하다(마커가 현재 env·플래그보다 우선).
- **주입 가능 인터페이스(mock 검증)**: 결정적 헬퍼의 외부 인터페이스(`LOOP_CMD`·`GIT_CMD`·`FORGE_CMD`(기본 gh)·`FORGE_BIN`(서브모드 판정)·`DEFAULT_BRANCH`·`REVIEW_ROUNDS_MAX`(3)·`WATCH_DIRS`(plugins/) 등)는 주입 가능해 실제 PR·머지 없이 mock 으로 독립 검증된다.

## fan-out 드라이버

dispatch 의 fan-out 단계(준비된 SPEC마다 워커를 진행시키는 부분)는 실행 환경의 역량에 따라 세 가지 드라이버 중 하나로 구동된다. 드라이버 선택은 dispatch 내부에서 일어나며 기존 시작 인터페이스는 변하지 않는다.

| 드라이버 | 설명 |
|---|---|
| `strong-parallel` | dynamic Workflow 실행 메커니즘 — 임의 depends_on DAG를 promise 기반으로 표현, 의존성 충족 즉시 워커 시작(준비도 스트리밍 완전). |
| `background` | 워커를 비동기로 띄우고 개별 완료 신호에 반응해 의존자를 즉시 해제. 완료 신호가 오케스트레이터를 재호출 못하면 `foreground-batch` 로 강등. |
| `foreground-batch` | 한 턴에 동시 시작 → 배리어 → 준비도 재평가. 안전 폴백(기본값). |

**드라이버 선택 방법**:
1. `DISPATCH_DRIVER` 환경 변수로 override(`strong-parallel`|`background`|`foreground-batch`).
2. 미설정이면 자동 감지: `DISPATCH_STRONG_PARALLEL=1` → `strong-parallel`, `DISPATCH_BACKGROUND=1` → `background`, 그 외 → `foreground-batch`.
3. 선택된 드라이버는 `DRIVER` run-dir 마커로 영속해 `--resume` 에서 sticky 하다.
4. `dispatch driver <run-id>` 로 실제 선택된 드라이버를 관찰할 수 있다.

**안전 강등 사슬**: `strong-parallel` → `background` → `foreground-batch`. 환경 판정에 따라 강등된 드라이버는 `driver` 서브커맨드로 관찰 가능하다. 어느 드라이버에서든 결정적 코어(의존성 그래프·준비도·상태 전이·skip 전파·머지/리뷰 게이트)와 안전 불변식(승인 후에만 머지·force 금지·ff-only)은 동일하게 성립한다.

## Subcommands

### dispatch start `<spec...>` [--max-parallel N] [--resume `<run-id>`] [--target-branch `<branch>`]

1 개 이상의 SPEC 파일 경로를 받아 새 run 을 시작한다. 준비된 SPEC마다 서브에이전트를 1개 띄워 그 서브에이전트가 구현→리뷰→머지를 소유하고(위 "서브에이전트 위임" 절), `done` 은 "대상 브랜치에 머지됨"을 뜻한다(서브에이전트의 머지 보고로 전이). `--target-branch` 로 머지·동기화 대상 브랜치를 지정한다(미지정 시 기본 브랜치). 하위 호환을 위해 `--no-integrate`·`--integrate` 를 받되 무시한다(no-op).

- 입력 검증: 각 경로가 파일로 존재하고 읽을 수 있어야 한다. 하나라도 누락이면 보고 후 즉시 abort.
- DAG 구성: 각 SPEC frontmatter 의 `depends_on` 을 읽어 의존 인덱스를 만든다. cycle 이면 abort. 진단용 `WAVES.txt` 도 함께 기록(실행 스케줄은 준비도 기반).
- `<project_root>/.dispatch/runs/<run-id>/MANIFEST.txt` · `WAVES.txt` · `state.<slug>-<sha7>` · `LOG.md` 생성. (`<slug>` 는 가독용, `<sha7>` 는 SPEC abspath 해시로 다른 날짜·디렉토리 동명 SPEC 충돌 방지.) state 값: `pending`/`running`/`done`/`failed`/`skipped`.
- 준비도 스트리밍: 각 SPEC 의 모든 dep 이 done 이 되는 즉시 동시성 상한 이내에서 서브에이전트 1개를 띄운다. 한 SPEC 이 failed 면 그 이행적 의존자만 `skipped`, 독립 가지는 계속.
- `--resume <run-id>` 이면 보관된 manifest 로 재개. `done` 인 SPEC 은 재호출하지 않고 나머지(미완)만 다시 스케줄한다. 서브모드(forge/direct)와 대상 브랜치는 run-dir 마커로 보존되어 재개 시 현재 env·플래그보다 우선한다(sticky).
- 한 child 가 `DISPATCH_WAVE_TIMEOUT_SECONDS`(기본 7200) 를 초과하면(per-SPEC runtime cap) 그 child 를 SIGTERM→SIGKILL 으로 정리하고 `failed` 로 마킹한다(이미 done 이면 보존).
- exit code: `0`=전부 done, `1`=failed/skipped 있음, `2`=timeout.

### dispatch driver `<run-id>`

run 의 fan-out 드라이버(`strong-parallel`|`background`|`foreground-batch`)를 출력한다. 안전 강등 결과를 포함해 어느 드라이버로 실행 중인지 관찰할 때 사용한다.

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
| `dispatch.sh` | run-id 디렉토리·의존 인덱스·준비도 스케줄링·동시성·드라이버 감지/마커·구조화 종료 판정(결정적 오케스트레이션 헬퍼) |
| `spec-subagent.md` | **SPEC 서브에이전트 계약** — 한 컨텍스트에서 loop·review 반복→머지→보고(완료 조건 2–8 단일 출처) |
| `lib-integration.sh` | per-SPEC 통합 상태 헬퍼(run-dir + 키: branch/pr/head/review-round/verdict/phase) — 서브에이전트 공유 |
| `integration.sh` | base sync → push → PR 생성/재사용(forge) / PR 없이 작업 브랜치 식별(direct) — 서브에이전트 호출 헬퍼 |
| `review-loop.sh` | 리뷰 반복 가드(라운드 상한·무진전·핑퐁) 결정적 판정 헬퍼 — 서브에이전트가 재구현 반복 제어에 사용 |
| `merge.sh` | 승인 게이트(forge)·버전 범프 게이트·직렬화 ff-only 머지(대상 브랜치) 결정적 헬퍼 — 서브에이전트가 머지에 사용 |

각 헬퍼 모듈은 `bash <module>.sh selftest` 로 mock 인터페이스 기반 독립 검증을 제공한다(실제 PR·머지 미수행). 결정적 스케줄링 검증은 `bash dispatch.sh selftest`.

## 의존성

- **결정적 헬퍼(`dispatch.sh`)**: `git`, `bash` 3.2+, `sha256sum` 또는 `shasum`, `yq`(mikefarah). `yq` 는 SPEC frontmatter 의 `depends_on` 파싱(DAG 구성)에 쓰며 `start` 가 요구한다(없으면 awk 폴백이 있으나 신·구 레이아웃·인라인/블록 형식의 견고한 파싱을 위해 명시 요구). `ready`/`mark`/`status`/`stop`/`watch`/`driver` 는 결정적 상태 헬퍼로 yq 비의존. 드라이버 감지는 `DISPATCH_DRIVER`(override), `DISPATCH_STRONG_PARALLEL`=1, `DISPATCH_BACKGROUND`=1 환경 변수로 제어한다.
- **서브에이전트가 호출하는 스킬·도구**: `autopilot:loop`·`autopilot:review`(판정 JSON 파싱에 `jq`). forge 서브모드는 추가로 forge CLI(`gh`, 주입 가능)를 쓰고, direct 서브모드는 forge CLI·원격 push 가 필요 없다. 서브모드 절차는 `references/spec-subagent.md`.

## 규칙

- 자체 작성·갱신 영역은 `<project_root>/.dispatch/runs/<run-id>/` 안의 파일들(SPEC 델타·백로그·통합 상태 포함)과 본 스킬 정의 파일뿐이다. 작업 브랜치·PR·머지 같은 forge 부수효과를 제외하면 이 외 경로를 만들지 않으며, run 디렉토리는 git 추적에서 제외한다(`.gitignore` 권장).
- **통합·리뷰·머지 소유권은 SPEC 서브에이전트**(SPEC당 한 컨텍스트, `references/spec-subagent.md`)에 있다 — dispatch 는 의존성·동시성·실패 격리만 총괄하고, 통합·리뷰·머지를 bash 드레인 파이프라인으로 직접 수행하지 않는다.
- 분해(여러 SPEC 작성) 책임은 SPEC 작성 도구(`autopilot:spec` 등)에 있고, dispatch 는 이미 만들어진 SPEC 들만 받는다.
