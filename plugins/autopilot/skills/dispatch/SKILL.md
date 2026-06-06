---
name: dispatch
description: "하나 이상의 SPEC 파일을 구현·머지 단계로 넘기고 싶을 때 사용 — depends_on 준비도를 풀어 **준비된 SPEC마다 서브에이전트를 1개 띄우는 모델 주도 오케스트레이터**. 각 SPEC 서브에이전트는 자기 컨텍스트에서 loop(구현)·review(리뷰)를 승인까지 반복하고 대상 브랜치로 직접 머지한다(forge 구성이면 PR 적대 리뷰→분리 승인→ff-only 머지, 미구성이면 로컬 적대 리뷰 게이트→ff-only 직접 머지). dispatch 는 의존성·웨이브·동시성·실패 격리만 총괄하고, 머지(=done)되면 의존자를 해제한다. 대상 브랜치는 --target-branch 로 지정(기본: 기본 브랜치). 호출 'Skill(skill=\"dispatch\", args=\"<subcommand> [<args>]\")' (start/list/status/stop/watch)."
allowed-tools:
  - Read
  - Bash(bash * dispatch.sh start:*)
  - Bash(bash * dispatch.sh list)
  - Bash(bash * dispatch.sh status:*)
  - Bash(bash * dispatch.sh stop:*)
  - Bash(bash * dispatch.sh watch:*)
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

dispatch 는 준비된(모든 dep 이 done) SPEC마다 서브에이전트를 **정확히 1개** 띄우고, 그 서브에이전트가 자기 컨텍스트에서 그 SPEC 의 구현→리뷰→재구현→머지를 닫는다. 서브에이전트 절차의 단일 출처는 **`references/spec-subagent.md`**(완료 조건 2–8)다. dispatch 는 그 내부를 들여다보지 않고 결과(머지됨/비완료)만 받아, 머지를 보고한 SPEC 을 `done`(="대상 브랜치에 머지됨")으로 전이하고 의존자를 해제한다.

- **dispatch 의 책임(결정적)**: depends_on 준비도 스케줄링·동시성 상한·서브에이전트 spawn/reap·done(=대상 브랜치에 머지됨)이면 의존자 해제·실패 이행 격리. 이 부분은 결정적 헬퍼(`dispatch.sh`)로 분리되어 selftest 로 검증된다(서브에이전트 spawn 은 Agent 도구를 쓰는 살아있는 에이전트 컨텍스트가 수행 — bash 무인 파이프라인이 아님).
- **서브에이전트의 책임(모델 주도)**: 한 컨텍스트에서 `loop`(구현)·`review`(리뷰)를 **공개 스킬 인터페이스로** 호출하고(별도 추가 서브에이전트로 나누지 않음), `request_changes` 면 같은 작업 브랜치(`feat/<run-id>-<slug>`) 위에서 재구현→재리뷰를 `approve` 까지 반복(무한루프 가드 안), `approve` 후 대상 브랜치로 머지, dispatch 에 보고. 상세는 `references/spec-subagent.md`.
- **대상 브랜치**: `--target-branch <branch>` 로 지정(미지정 시 기본 브랜치 `main` 또는 주입된 `DEFAULT_BRANCH`). run 전역으로 결정돼 모든 서브에이전트의 base 동기화·리뷰 대상·ff 머지에 일관 적용되며, run-dir 마커(`TARGET_BRANCH`)로 영속해 `--resume` 에서 sticky 하다(재개 시 마커가 현재 env·플래그보다 우선).
- **서브모드(forge / direct)**: 서브에이전트가 리뷰·머지 대상을 정한다 — 분리 승인 신원(`APPROVER`)이 설정되고 forge CLI 가 사용 가능하면 **forge**(작업 브랜치 push→같은 head PR 재사용/생성→PR 적대 리뷰→분리 승인→ff 머지), 아니면 **direct**(PR·원격 push 없이 작업 브랜치 변경 base..head 를 로컬 적대 리뷰→ff 직접 머지). forge 구성 판정 규칙은 불변. 두 서브모드 모두 적대 리뷰·버전 범프 게이트·fast-forward 전용 머지를 통과한다.
- **머지 게이트(done=머지)**: 서브에이전트가 머지를 보고한 SPEC 만 `done` 으로 전이한다. 따라서 **의존자는 의존성이 대상 브랜치에 머지된 뒤에만** 실행 큐에 풀리고, 갱신된 대상 브랜치 위에서 분기한다. 서브에이전트가 비완료(가드 소진·loop/review `unavailable`·분리 승인 신원 부재·충돌 해결 불가)로 끝나면 거짓 green 대신 에스컬레이션하고, 그 SPEC 은 `failed` 이며 그 **이행적 의존자만** `skipped` 된다. 무관한 가지는 계속 진행한다.
- **무한루프 가드·안전 강등(결정적 헬퍼)**: 재구현→재리뷰 반복은 결정적 가드(라운드 상한 기본 3·무진전·동일 지적 핑퐁 — `review-loop.sh` 헬퍼가 판정, selftest 검증)에 걸리면 머지 없이 에스컬레이션한다. 승인 게이트(forge: 분리 승인 신원, 리뷰봇 self-approve 무효)·버전 범프 게이트(`plugins/` 변경 시 `plugin.json` 범프 강제)·ff-only 머지(`merge.sh` 헬퍼, selftest 검증)를 통과하지 못하면 안전 강등한다.
- **동시 머지 직렬화**: 여러 서브에이전트가 같은 대상 브랜치로 머지할 때 **전역 락·dispatch 머지 순번 통제 없이** git 자체 메커니즘이 직렬성을 제공한다. 한 머지가 대상 브랜치를 전진시켜 다른 서브에이전트의 머지가 더 이상 fast-forward 가 아니게 되면, 그 서브에이전트는 갱신된 대상 브랜치에 동기화·충돌 해결 후 머지한다. **어떤 경로(forge·direct)에서도 force(push·merge·rebase)를 쓰지 않는다.**
- **주입 가능한 인터페이스(mock 검증)**: 결정적 헬퍼의 외부 인터페이스(`LOOP_CMD` `GIT_CMD` `FORGE_CMD`(기본 gh) `FORGE_BIN`(서브모드 판정용 forge CLI) `DEFAULT_BRANCH`(대상 브랜치) `APPROVER` `REVIEW_BOT` `APPROVE_CMD` `REVIEW_ROUNDS_MAX`(3) `WATCH_DIRS`(plugins/) `REVIEW_PRODUCE_CMD` 등)는 주입 가능해 실제 PR·머지 없이 mock 으로 독립 검증된다.

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
| `dispatch.sh` | run-id 디렉토리·의존 인덱스·준비도 스케줄링·동시성·구조화 종료 판정(결정적 오케스트레이션 헬퍼) |
| `spec-subagent.md` | **SPEC 서브에이전트 계약** — 한 컨텍스트에서 loop·review 반복→머지→보고(완료 조건 2–8 단일 출처) |
| `lib-integration.sh` | per-SPEC 통합 상태 헬퍼(run-dir + 키: branch/pr/head/review-round/verdict/phase) — 서브에이전트 공유 |
| `integration.sh` | base sync → push → PR 생성/재사용(forge) / PR 없이 작업 브랜치 식별(direct) — 서브에이전트 호출 헬퍼 |
| `review-loop.sh` | 리뷰 반복 가드(라운드 상한·무진전·핑퐁) 결정적 판정 헬퍼 — 서브에이전트가 재구현 반복 제어에 사용 |
| `merge.sh` | 승인 게이트(forge)·버전 범프 게이트·직렬화 ff-only 머지(대상 브랜치) 결정적 헬퍼 — 서브에이전트가 머지에 사용 |

각 헬퍼 모듈은 `bash <module>.sh selftest` 로 mock 인터페이스 기반 독립 검증을 제공한다(실제 PR·머지 미수행). 결정적 스케줄링 검증은 `bash dispatch.sh selftest`.

## 의존성

`git`, `bash` 3.2+, `sha256sum` 또는 `shasum`, `autopilot:loop` 스킬, `yq`(mikefarah). `yq` 는 depends_on 파싱(없으면 awk 폴백)뿐 아니라 **loop 구조화 상태(`status --json`) 판정의 단일 출처**이므로 `start`/`status`/`stop`/`watch` 에서 필수다(부재 시 명확히 정지 — 텍스트 컬럼으로 silent fallback 하지 않음). **forge 서브모드**는 추가로 `jq`(리뷰 판정 JSON 파싱)와 forge CLI(`gh`, 주입 가능)·리뷰 생산자(`autopilot:review`)를 쓴다. **direct 서브모드**(forge 미구성)는 forge CLI 없이 동작하지만, 적대적 리뷰 게이트를 위해 `jq` 와 리뷰 생산자(`autopilot:review`)는 쓴다(PR·원격 push 없이 로컬 작업 브랜치 diff 로 리뷰).

## 규칙

- 자체 작성·갱신하는 영역은 `<project_root>/.dispatch/runs/<run-id>/` 디렉토리 안의 파일들(SPEC 델타·백로그·통합 상태 포함)과 본 스킬의 정의 파일뿐이다. 작업 브랜치·PR·머지 같은 forge 부수효과를 제외하면 이 외 경로를 만들지 않는다.
- 서브에이전트는 `loop`·`review` 를 공개 스킬 인터페이스로만 호출하고, 그들의 내부 워크트리·신호 파일·하니스를 직접 들여다보지 않는다(블랙박스 경계). dispatch 는 서브에이전트의 결과 보고만 받는다.
- **통합·머지 소유권**: 통합·리뷰·머지는 **SPEC 서브에이전트가 SPEC당 한 컨텍스트에서 소유**한다(`references/spec-subagent.md`). dispatch 는 의존성·웨이브·동시성·실패 격리만 총괄하고, 서브에이전트가 머지(=done)를 보고하면 의존자를 해제한다 — dispatch 는 통합·리뷰·머지를 bash 드레인 파이프라인으로 직접 수행하지 않는다. 결정적 부분(DAG 준비도·동시성·라운드 상한·무진전·핑퐁·버전 범프 게이트·ff 머지 메커니즘)은 헬퍼로 분리되어 주입 가능한 인터페이스로 mock·selftest 검증되며, force 는 어떤 경로(forge·direct)에서도 쓰지 않는다.
- 분해(여러 SPEC 작성) 책임은 SPEC 작성 도구(`autopilot:spec` 등)에 있고, dispatch 는 이미 만들어진 SPEC 들만 받는다.
- loop 의 종료 의도(완료/차단)는 자율 실행기가 신호로 표현하고, **서브에이전트**는 그 공개 인터페이스가 제공하는 **구조화된 상태**(`loop.sh status --json` 의 `.state`·`.signals[]`)로만 읽는다 — 표 컬럼 위치·부분 문자열 일치에 의존하지 않는다. `signals` 의 의미(`DONE`/`BLOCKED`)는 워커 컨벤션이며 정확 일치 멤버십으로 판정한다. dispatch 는 서브에이전트의 결과(머지됨/비완료) 보고만 구조화로 받는다.
- run 디렉토리는 git 추적에서 제외한다(`.gitignore` 처리 권장).
