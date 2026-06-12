---
name: dispatch
description: "하나 이상의 SPEC 파일을 구현·머지 단계로 넘기고 싶을 때 사용 — depends_on 준비도를 풀어 **준비된 SPEC마다 서브에이전트를 1개 띄우는 모델 주도 오케스트레이터**. 각 서브에이전트가 자기 컨텍스트에서 그 SPEC 의 구현→리뷰→머지를 소유하고, dispatch 는 의존성·동시성·실패 격리만 총괄해 머지(=done)되면 의존자를 해제한다. 호출 'Skill(skill=\"dispatch\", args=\"<subcommand> [<args>]\")' (start/list/status/stop/watch)."
allowed-tools:
  - Read
  - Bash(bash * dispatch.sh start:*)
  - Bash(bash * dispatch.sh list)
  - Bash(bash * dispatch.sh status:*)
  - Bash(bash * dispatch.sh driver:*)
  - Bash(bash * dispatch.sh concurrency:*)
  - Bash(bash * dispatch.sh stop:*)
  - Bash(bash * dispatch.sh watch:*)
  - Bash(bash * dispatch.sh selftest:*)
---

# dispatch

`dispatch` 는 SPEC 파일 묶음을 받아 depends_on 의존성을 풀고, **준비된(모든 dep 이 done) SPEC마다 서브에이전트를 1개 띄우는 모델 주도 오케스트레이터**다. 각 SPEC 서브에이전트는 자기 컨텍스트에서 `loop`(구현)·`review`(리뷰) 스킬을 공개 인터페이스로 승인까지 반복 호출하고 대상 브랜치로 머지하기까지 그 SPEC 의 전 생애를 소유한다(서브에이전트 절차 계약: `references/subagent-prompt.md`). dispatch 자신은 준비도 스케줄링·동시성 상한·서브에이전트 spawn/reap·done(=머지)이면 의존자 해제·실패 이행 격리만 책임지며, **통합·리뷰·머지를 더 이상 bash 드레인 파이프라인으로 직접 수행하지 않는다**. SPEC 작성 도구·작성 형식에 비결합 — **파일로 존재하고 읽을 수 있는 SPEC 이면** 무엇이든 입력으로 받는다.

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

준비된(모든 dep 이 done) SPEC마다 서브에이전트를 **정확히 1개** 띄우고, 그 서브에이전트가 한 컨텍스트에서 그 SPEC 의 구현→리뷰→재구현→머지를 닫는다. **서브에이전트 절차의 단일 출처는 `references/subagent-prompt.md`**(loop/review 블랙박스 호출·forge/direct 서브모드·무한루프 가드·approve 후 머지 게이트·에스컬레이션) — dispatch 가 워커 spawn 프롬프트에 그 전문을 embed 한다. dispatch 는 그 내부를 들여다보지 않고 결과(머지됨/비완료)만 받는다.

- **워커 spawn 은 flow 서브프로세스 에이전트 + 계약 프롬프트 embed**: 준비된 SPEC 의 워커는 **`flow` 의 에이전트 노드(`wf.agent` + `SubprocessAgentCaller`)로 띄우되, 워커 절차 계약 전문(`references/subagent-prompt.md`)을 spawn 프롬프트에 그대로 embed** 한다. flow 의 서브프로세스 caller(기본 `claude --print`, caller argv 주입으로 벤더 중립)가 워커를 **독립 서브프로세스**로 실행하므로, 워커는 자기 실행 환경에서 `autopilot:loop`·결정적 헬퍼를 호출해 구현→리뷰→머지를 완수한다. spawn 시 입력으로 `spec`·`target-branch`·`run-dir`·`key` 를 넘긴다. (인세션 Agent 도구의 부모 권한 상속 전제 대신 flow 서브프로세스 워커 모델이며 — 워커의 권한·스킬 가용성은 flow agent caller 설정·벤더 CLI 실행 환경에 의존한다. dispatch 는 그 결과·격리를 관찰해 보완한다.)

- **서브프로세스 워커 진행 모니터 자동 설치**: 워커를 **flow 서브프로세스 에이전트로 띄울 때**, dispatch 는 그 워커의 진행을 **워커가 남기는 디스크 아티팩트**(구현 스킬 `autopilot:loop` 의 status/signals, 작업 브랜치 커밋, PR·리뷰 판정, dispatch SPEC state)에 기반해 관찰하는 **진행 모니터를 자동으로 설치**한다. 가용한 환경 수단(예: 주기 폴링 메커니즘)으로 설치하되 **특정 모니터링 하니스 도구에 하드 종속하지 않는다**.
  - **read-only 관찰(블랙박스 보존)**: 모니터는 디스크 아티팩트를 **읽기만** 하며 워커·loop 워크트리·신호·하니스를 변경하지 않는다. 관찰 상태가 **바뀔 때만** 진행을 표면화하고(변화 없는 동안 중복 방출하지 않음), 워커가 **산출 없이 죽거나 정지한 경우·조용한 실패**가 드러나게 한다.
  - **수명주기 종료**: dispatch run(또는 해당 SPEC)이 **종료 상태**(머지됨=done / failed / 전부 done)에 도달하면 그 진행 모니터를 **종료**한다 — 고아(orphan) 모니터를 남기지 않는다.
  - **모니터 메커니즘이 없는 환경(오류 경로)**: 자동 설치는 **안전하게 생략**되고, 워커 진행은 여전히 위 디스크 아티팩트 폴링으로 관찰 가능하다(**아티팩트가 진행의 단일 출처**).

dispatch 자신의 책임은 **결정적 오케스트레이션**뿐이며 `dispatch.sh` 헬퍼로 분리되어 selftest 로 검증된다:

- **준비도·격리**: depends_on 준비도 스케줄링·동시성 상한·서브에이전트 spawn/reap·실패 이행 격리(spawn 은 `flow` 의 서브프로세스 에이전트 caller 가 수행 — bash 무인 드레인 파이프라인 아님).
- **머지=done 전이**: 서브에이전트가 머지를 보고한 SPEC 만 `done`(=대상 브랜치 머지됨)으로 전이해 의존자를 해제하므로, 의존자는 의존성이 머지된 뒤에야 갱신된 대상 브랜치 위에서 분기한다. 비완료 보고는 `failed` 로 두고 **그 이행적 의존자만** `skipped`(독립 가지는 계속).
- **대상 브랜치**: `--target-branch <branch>`(미지정 시 기본 브랜치 또는 주입된 `DEFAULT_BRANCH`). run 전역으로 결정돼 모든 서브에이전트의 base 동기화·리뷰·ff 머지에 일관 적용되고, run-dir 마커(`TARGET_BRANCH`)로 영속해 `--resume` 에서 sticky 하다(마커가 현재 env·플래그보다 우선).
- **주입 가능 인터페이스(mock 검증)**: 결정적 헬퍼의 외부 인터페이스(`LOOP_CMD`·`GIT_CMD`·`FORGE_CMD`(기본 gh)·`FORGE_BIN`(서브모드 판정)·`DEFAULT_BRANCH`·`REVIEW_ROUNDS_MAX`(3)·`WATCH_DIRS`(plugins/) 등)는 주입 가능해 실제 PR·머지 없이 mock 으로 독립 검증된다.

## fan-out 드라이버 — 단일 `flow` 드라이버

fan-out 단계(준비된 SPEC마다 워커 1개 진행)는 **단일 `flow` 드라이버**로 구동된다 — `flow` 스킬의 **공개 계약**(`bash plugins/autopilot/skills/flow/references/flow.sh run <정의 파일>` → 단일 JSON)을 통해 임의 `depends_on` DAG를 **스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume·결과 전달**로 실행한다. flow 엔진 내부는 **블랙박스**로 두고 입력→JSON 출력 계약으로만 호출한다. 드라이버 선택·자동 감지·운영자 override·안전 강등 사슬은 없으며, 호출자에게 노출된 **시작 인터페이스는 변하지 않는다**(flow 통합은 dispatch 내부에서 일어난다). dispatch 의 결정적 코어(준비도·상태 전이·skip 전파·워커 계약·머지/리뷰 게이트)는 그대로 보존하고, fan-out 을 무엇으로 구동하느냐만 flow 로 통합한다.

- **flow 호출 경로**: `dispatch.sh start` 로 run·DAG·markers·pending 상태를 셋업한 뒤, 오케스트레이터가 준비된 SPEC 들을 flow **워크플로 정의**(각 노드의 `depends_on` 이 모두 충족되는 즉시 워커 실행, SPEC당 워커 1개)로 표현하고 `flow run` 으로 실행한다. 한 SPEC 의 dep 이 모두 done 이면 **같은 그래프의 더 느린 무관한 SPEC 이 진행 중이어도** 기다리지 않고 그 워커가 시작된다(런타임 스트리밍). 동시성 상한은 flow 정의의 `CONCURRENCY` 로 주되 그 값은 `dispatch.sh concurrency <run-id>` 가 산출한다(`0`=무제한을 SPEC 수로 결정적 변환 — 단일 출처). **fan-out 항목이 하나(N=1)여도 같은 flow 경로로 구동**한다.
- **워커 노드 = flow 서브프로세스 에이전트**: 각 SPEC 워커는 flow 의 에이전트 노드(`wf.agent` + `SubprocessAgentCaller`)로 spawn 하고, spawn 프롬프트에 **워커 계약 전문(`references/subagent-prompt.md`)을 embed** 하며 `spec`·`target-branch`·`run-dir`·`key` 를 입력으로 넘긴다. caller argv 는 주입 가능하며 기본은 Claude(`claude --print`) — 특정 벤더 CLI 에 하드 종속하지 않는다(멀티벤더). 워커가 머지를 보고하면 `dispatch.sh mark done`, 비완료면 `mark failed` 후 `ready` 재평가로 의존자를 해제한다.
  - **워커 권한(서브프로세스는 부모 권한 비상속)**: 인세션 Agent 와 달리 flow 서브프로세스 워커는 **부모 세션의 런타임 권한 grant 를 상속하지 않는다**. 워커 계약(`references/subagent-prompt.md`)이 요구하는 명령 표면을 비대화형 `--print` 으로 무인 실행해야 하므로, caller 는 **격리 워크트리 전제로 `--dangerously-skip-permissions`** 를 기본으로 한다 — 더 좁은 정책이 필요하면 `--allowedTools`/프로젝트 settings allow 로 대체한다.
- **`python3` hard-abort(폴백 없음)**: flow 는 `python3` 3.9+ 표준 라이브러리로 동작한다. **`python3` 3.9+ 가 사용 불가이면** dispatch 는 다른 드라이버로 강등하지 않고 **명확한 오류로 즉시 중단**한다(비-0 종료). 강등 사슬 자체를 두지 않는 것이 이 통합의 핵심이다(`dispatch.sh` 의 `require_python3` 가 `start` 진입부에서 강제).
- **관찰**: 단일 드라이버이므로 `dispatch driver <run-id>` 와 `dispatch status` 의 `driver:` 라인은 항상 `flow` 를 일관되게 보고한다.
- 워커 **내부 단계(구현→리뷰→재구현→머지)는 데이터 의존 순서대로 동기** 진행된다(이 내부 순서를 병렬·백그라운드로 바꾸지 않는다 — 워커 계약 `references/subagent-prompt.md` 불변). 실패 이행 격리·승인 후 ff-only 머지 같은 안전 불변식도 그대로다.

## Subcommands

### dispatch start `<spec...>` [--max-parallel N] [--resume `<run-id>`] [--target-branch `<branch>`]

1 개 이상의 SPEC 파일 경로를 받아 새 run 을 시작한다. 준비된 SPEC마다 서브에이전트를 1개 띄워 그 서브에이전트가 구현→리뷰→머지를 소유하고(위 "서브에이전트 위임" 절), `done` 은 "대상 브랜치에 머지됨"을 뜻한다(서브에이전트의 머지 보고로 전이). `--target-branch` 로 머지·동기화 대상 브랜치를 지정한다(미지정 시 기본 브랜치). 하위 호환을 위해 `--no-integrate`·`--integrate` 를 받되 무시한다(no-op).

- 입력 검증: 각 경로가 파일로 존재하고 읽을 수 있어야 한다. 하나라도 누락이면 보고 후 즉시 abort.
- DAG 구성: 각 SPEC frontmatter 의 `depends_on` 을 읽어 의존 인덱스를 만든다. cycle 이면 abort. 진단용 `WAVES.txt` 도 함께 기록(실행 스케줄은 준비도 기반).
- `<project_root>/.dispatch/runs/<run-id>/MANIFEST.txt` · `WAVES.txt` · `state.<slug>-<sha7>` · `LOG.md` 생성. (`<slug>` 는 가독용, `<sha7>` 는 SPEC abspath 해시로 다른 날짜·디렉토리 동명 SPEC 충돌 방지.) state 값: `pending`/`running`/`done`/`failed`/`skipped`.
- 준비도 스트리밍: 각 SPEC 의 모든 dep 이 done 이 되는 즉시 동시성 상한 이내에서 서브에이전트 1개를 띄운다. 한 SPEC 이 failed 면 그 이행적 의존자만 `skipped`, 독립 가지는 계속.
- `--resume <run-id>` 이면 보관된 manifest 로 재개. `done` 인 SPEC 은 재호출하지 않고 나머지(미완)만 다시 스케줄한다. 서브모드(forge/direct)와 대상 브랜치는 run-dir 마커로 보존되어 재개 시 현재 env·플래그보다 우선한다(sticky).
- 한 child 가 `DISPATCH_WAVE_TIMEOUT_SECONDS`(기본 7200) 를 초과하면(per-SPEC runtime cap) 그 child 를 SIGTERM→SIGKILL 으로 정리하고 `failed` 로 마킹한다(이미 done 이면 보존). child 를 `failed` 로 reap/timeout 종료한 직후, dispatch 는 그 SPEC 에 대해 **`integration.sh cleanup-on-fail <spec> <run-dir>` 를 호출해 실패-경로 조건부 워크트리 정리**(작업이 원격 브랜치로 보존돼 있으면 고아 워크트리 정리, 미보존이면 보존; loop 공개 cleanup 위임)를 적용한다 — 워커 자기 escalation 경로(`integration.sh integrate` 가 blocked 매핑 시 자동 수행)와 **동일 정책**이다. 정리 실패는 경고로 표면화되며 `failed` 판정을 뒤집지 않는다.
- exit code: `0`=전부 done, `1`=failed/skipped 있음, `2`=timeout.

### dispatch list

`<project_root>/.dispatch/runs/` 아래의 모든 run-id 와 요약을 표시한다.

### dispatch status `<run-id>`

run-id 단위로 per-SPEC state(`pending`/`running`/`done`/`failed`/`skipped`) 를 표로 출력한다(진단용 wave 번호 포함). 헤더에 fan-out 드라이버(`driver: flow`)도 함께 보인다. loop driver 의 라이브 state 도 함께 보인다.

### dispatch driver `<run-id>`

run 의 fan-out 드라이버를 출력한다 — 단일 드라이버이므로 항상 `flow`(관찰 진입점).

### dispatch concurrency `<run-id>`

flow `CONCURRENCY` 로 넘길 effective 동시성을 출력한다 — `--max-parallel N`(>0)이면 N, 미지정(`MAX_PARALLEL=0`=무제한)이면 SPEC 수(≥1)로 결정적 변환. 오케스트레이터가 flow 정의의 `CONCURRENCY` 를 이 값으로 채워 `0` 직전달에 의한 순차 퇴행을 막는다(변환 로직의 단일 출처).

### dispatch stop `<run-id>`

run-id 안에서 진행 중(`running`)인 child 들에 대해 자율 실행기에 stop 을 위임한다. stop 으로 한 child 가 `failed` 로 종료되면, dispatch 는 그 SPEC 에 대해 timeout 경로와 동일하게 **`integration.sh cleanup-on-fail <spec> <run-dir>`** 를 호출해 실패-경로 조건부 워크트리 정리(원격 보존 시 정리·미보존 시 보존)를 적용한다.

### dispatch watch `<run-id>`

per-SPEC 상태를 주기적으로 refresh 하며, 모든 child 가 terminal(`done`/`failed`/`skipped`)에 도달하면 exit code 로 결과를 대표한다. `0`=전부 done, `1`=failed/skipped 있음, `2`=timeout.

### dispatch sweep [--target-branch `<branch>`]

**dispatch 자신이 만든 작업 브랜치** 중 **대상 브랜치에 이미 머지된** 것을 소급해 **일괄 삭제**하는 정비 진입점이다. 머지 시점 단건 정리(머지가 삭제하는 한 브랜치)는 정책 이전·외부(수동) 머지로 원격에 누적된 dispatch 작업 브랜치를 청소하지 못하므로, **명시 요청으로만** 도는 일괄 정리를 둔다(자동 무인 파괴 아님).

- **대상 식별 = dispatch 자기 출처(provenance)**: dispatch 전용 네이밍 시그니처(`feat/<run-id>-<slug>`, `<run-id>`=`<YYYYMMDDTHHMMSS>-<sha7>`)에 맞는 브랜치만 대상으로 한다. 단순히 `feat/*` 가 비슷하다는 이유로 삭제하지 않으며, **dispatch 가 만들지 않은 브랜치(사람·타 도구 생성)는 이름이 유사해도 제외**한다.
- **머지 확인된 것만 삭제**: 대상 브랜치의 조상(=머지됨)인 것만 force 없이 일반 삭제(원격, 있으면 로컬)하고, **미머지 브랜치는 절대 삭제하지 않는다**(보존).
- **결정적 헬퍼가 삭제 소유**: 식별·삭제는 `merge.sh sweep`(결정적 공용 삭제 경로)이 수행하고, 워커·dispatch 는 raw 원격 명령으로 직접 삭제하지 않는다.
- **부분 실패 격리·관찰 가능**: 한 브랜치 삭제 실패는 경고로 표면화하되 다른 브랜치 처리를 막지 않으며, 어떤 브랜치를 지웠고 어떤 것을 건너뛰었는지(미머지·실패)를 보고한다.
- `--target-branch` 미지정 시 `DEFAULT_BRANCH`(기본 브랜치)를 대상으로 한다.

## references

| 파일 | 역할 |
|---|---|
| `dispatch.sh` | run-id 디렉토리·의존 인덱스·준비도 스케줄링·동시성·`python3` 전제 강제(단일 flow 드라이버)·구조화 종료 판정(결정적 오케스트레이션 헬퍼) |
| `subagent-prompt.md` | **per-SPEC 워커 지침(계약)** — dispatch 가 flow 서브프로세스 에이전트 spawn 프롬프트에 embed(구현=autopilot:loop·통합/리뷰/머지=헬퍼 구동·approve 후 머지·구조화 보고) |
| `lib-integration.sh` | per-SPEC 통합 상태 헬퍼(run-dir + 키: branch/pr/head/review-round/verdict/phase) — 서브에이전트 공유 |
| `integration.sh` | base sync → push → PR 생성/재사용(forge) / PR 없이 작업 브랜치 식별(direct) + 실패-경로 조건부 워크트리 정리(`cleanup-on-fail`: 원격 보존 시 loop cleanup 위임·미보존 시 보존) — 서브에이전트 호출 헬퍼 |
| `review-loop.sh` | 리뷰 반복 가드(라운드 상한·무진전·핑퐁) 결정적 판정 헬퍼 — 서브에이전트가 재구현 반복 제어에 사용 |
| `merge.sh` | 승인 게이트(forge)·버전 범프 게이트·직렬화 ff-only 머지(대상 브랜치) + 머지 확정 후 작업 브랜치 정리(원격·로컬, force 없는 일반 삭제) + `sweep`=dispatch 자기 출처 머지 누적 브랜치 일괄 정리 결정적 헬퍼 — 서브에이전트가 머지에 사용, 일괄 정비는 `dispatch sweep` 진입 |

각 헬퍼 모듈은 `bash <module>.sh selftest` 로 mock 인터페이스 기반 독립 검증을 제공한다(실제 PR·머지 미수행). 결정적 스케줄링 검증은 `bash dispatch.sh selftest`.

## 의존성

- **결정적 헬퍼(`dispatch.sh`)**: `git`, `bash` 3.2+, `sha256sum` 또는 `shasum`, `yq`(mikefarah). `yq` 는 SPEC frontmatter 의 `depends_on` 파싱(DAG 구성)에 쓰며 `start` 가 요구한다(없으면 awk 폴백이 있으나 신·구 레이아웃·인라인/블록 형식의 견고한 파싱을 위해 명시 요구). `ready`/`mark`/`status`/`stop`/`watch` 는 결정적 상태 헬퍼로 yq 비의존.
- **fan-out 드라이버(`flow`)**: `python3` 3.9+(표준 라이브러리). dispatch 의 fan-out 은 단일 `flow` 드라이버의 공개 계약으로 구동되며, `start` 진입부에서 `python3` 3.9+ 가용 여부를 강제한다 — 미가용이면 **폴백 없이 hard-abort**(다른 드라이버로 강등하지 않음). `flow` 엔진은 블랙박스 공개 계약으로만 호출한다.
- **서브에이전트가 호출하는 스킬·도구**: `autopilot:loop`·`autopilot:review`(판정 JSON 파싱에 `jq`). forge 서브모드는 추가로 forge CLI(`gh`, 주입 가능)를 쓰고, direct 서브모드는 forge CLI·원격 push 가 필요 없다. 서브모드 절차는 `references/subagent-prompt.md`.

## 규칙

- 자체 작성·갱신 영역은 `<project_root>/.dispatch/runs/<run-id>/` 안의 파일들(SPEC 델타·백로그·통합 상태 포함)과 본 스킬 정의 파일뿐이다. 작업 브랜치·PR·머지 같은 forge 부수효과를 제외하면 이 외 경로를 만들지 않으며, run 디렉토리는 git 추적에서 제외한다(`.gitignore` 권장).
- **통합·리뷰·머지 소유권은 SPEC 서브에이전트**(SPEC당 한 컨텍스트, `references/subagent-prompt.md`)에 있다 — dispatch 는 의존성·동시성·실패 격리만 총괄하고, 통합·리뷰·머지를 bash 드레인 파이프라인으로 직접 수행하지 않는다.
- 분해(여러 SPEC 작성) 책임은 SPEC 작성 도구(`autopilot:spec` 등)에 있고, dispatch 는 이미 만들어진 SPEC 들만 받는다.
- **워크트리·작업 브랜치 정리 정책(비대칭)의 단일 출처는 결정적 헬퍼**(`merge.sh`=머지 후 작업 브랜치 삭제, `integration.sh`=실패-경로 조건부 워크트리 정리)와 워커 계약(`references/subagent-prompt.md` 규칙 6)이다. 작업 브랜치는 **머지 성공 시에만** ff-머지 확정 이후 머지 헬퍼가 force 없이 삭제(실패/비완료=보존)하고, 워크트리는 터미널 도달 시 **원격 브랜치로 보존돼 있으면** loop 공개 cleanup 위임으로 정리·**미보존이면 보존**한다(비터미널=정리 금지). 워커·dispatch 모두 raw 원격 명령으로 직접 삭제하거나 워크트리를 직접 `rm` 하지 않으며, 정리 실패는 경고로 표면화하되 머지·완료 판정을 뒤집지 않는다.
- **누적 stale 브랜치 일괄 정리(`dispatch sweep`)**: 머지 시점 단건 정리가 다루지 못하고 누적된(정책 이전·외부 수동 머지) dispatch 작업 브랜치는 **명시 요청** `dispatch sweep` 으로만 소급 청소한다. 같은 안전 불변식을 따른다 — **dispatch 자기 출처(네이밍 시그니처)만** 대상(사람·타 도구 브랜치 제외), **대상 브랜치 머지 확인된 것만** 삭제(미머지 보존), 결정적 헬퍼가 force 없이 삭제, 부분 실패는 경고로 격리, 결과(삭제·건너뜀)는 보고한다.
