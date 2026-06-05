---
name: dispatch
description: "하나 이상의 SPEC 파일을 구현 단계로 넘기고 싶을 때 사용 — 의존성(depends_on)을 풀어 각 SPEC 을 준비되는 즉시 자율 실행기에 스트리밍 위임하고 결과를 취합. 통합(리뷰·머지)은 항상 활성이라 구현 완료 SPEC 을 대상 브랜치로 머지한다(forge 구성이면 push→PR→리뷰→ff-only 머지, 미구성이면 PR 없는 로컬 적대적 리뷰 게이트 후 ff-only 직접 머지). 대상 브랜치는 --target-branch 로 지정(기본: 기본 브랜치). 호출 예: `dispatch <subcommand> [<args>]` (start/list/status/stop/watch)."
---

# dispatch

`dispatch` 는 SPEC 파일 묶음을 받아 의존성을 풀고, 각 SPEC 을 그 의존성이 모두 끝나는 즉시(준비도 기반 스트리밍) 자율 실행기(`autopilot:loop`)에 위임하는 오케스트레이터다. SPEC 작성 도구·작성 형식에 비결합 — **파일로 존재하고 읽을 수 있는 SPEC 이면** 무엇이든 입력으로 받는다.

## 호출

`dispatch <subcommand> [<args>]`

## 모델

- 입력: 1 개 이상의 SPEC 파일 경로 (가변 인자).
- DAG: 각 SPEC frontmatter 의 `depends_on:` (sibling slug 또는 경로) 항목으로 의존 관계를 구성한다. 외부 DAG 명세 파일을 요구하지 않는다. 위상정보(`WAVES.txt`)는 진단용으로 남기되, 실제 실행은 wave 배리어가 아니라 SPEC별 준비도로 구동한다.
- cycle 이 발견되면 cycle 구성 요소를 보고하고 실행을 시작하지 않는다(비-0 종료).
- **준비도 스트리밍**: 각 SPEC 은 자신의 `depends_on` 이 모두 `done` 이 되는 즉시 — 같은 위상의 무관한 SPEC 이 아직 실행 중이어도 기다리지 않고 — 동시성 상한 이내에서 시작된다. 기본 동시 실행 상한은 없으며 `--max-parallel N`(전역 동시 실행 상한) 으로 줄 수 있다.
- 각 child 의 종료·차단 여부는 자율 실행기의 **공개 인터페이스가 제공하는 구조화된(기계 판독) 상태**(`loop status --json` 의 `.state`·`.signals[]`)로만 판정한다 — 출력 표의 컬럼 위치나 자유 텍스트 부분 문자열 일치에 의존하지 않는다. 자율 실행기 내부 신호 파일·worktree 를 직접 읽지 않는다.
- **이행적 실패 전파**: 한 SPEC 이 `failed` 로 끝나면 그 SPEC 의 **이행적 의존자만** `skipped` 로 차단하고, 의존 관계가 없는 가지는 끝까지 실행한다(기존 wave fail-fast 와 다름).
- 호출마다 결정성 있는 `run-id`(타임스탬프 + 입력 SPEC 집합 sha7)를 만들고 진행 상태를 `<project_root>/.dispatch/runs/<run-id>/` 아래에 보관한다.
- 기존 `run-id` 로 재호출되면 보관된 상태를 읽어 이미 `done` 인 SPEC 은 재실행하지 않고, 미완 SPEC 만 스트리밍 스케줄에 따라 이어 수행한다.

## 통합(리뷰·머지) — 항상 활성

통합은 dispatch 의 단일 동작이다(토글 없음). dispatch 는 loop 가 DONE 으로 끝나면 그 결과를 대상 브랜치로 머지하고, 그 SPEC 의 **완료를 "대상 브랜치에 머지됨"으로 재정의**한다. loop DONE 시점의 코드는 격리 워크트리에만 있으므로, 통합이 의존자를 푸는 게이트가 되어 의존자는 의존성이 대상 브랜치에 머지된 뒤에만 실행된다.

- **항상 ON**: `dispatch start` 는 별도 플래그 없이 통합으로 시작한다. 비통합(레거시) 동작 경로는 없다. 하위 호환을 위해 `--no-integrate`·`--integrate` 플래그를 받아들이되 **아무 효과 없이 조용히 무시**한다(no-op).
- **대상 브랜치**: 머지·동기화 대상 브랜치는 `--target-branch <branch>` 로 지정한다. 미지정이면 기본 브랜치(`main`, 또는 주입된 `DEFAULT_BRANCH`)를 대상으로 삼는다. 지정한 대상은 그 run 의 모든 base 동기화·승인 요청(PR) base·fast-forward 머지·base push 에 일관되게 적용되며, run-dir 마커(`TARGET_BRANCH`)로 영속해 `--resume` 에서 sticky 하다(재개 시 마커가 현재 env·플래그보다 우선).
- **서브모드(forge / direct)**: forge 구성 여부로 갈린다 — 분리 승인 신원(`APPROVER`)이 설정되고 forge CLI 가 사용 가능하면 **forge**(풀 파이프라인), 아니면 **direct**(PR 없이 로컬 적대적 리뷰 게이트 후 대상 브랜치로 직접 머지). 두 서브모드 모두 적대적 리뷰·fast-forward 전용 머지·버전 범프 게이트를 통과해야 한다.
- **per-SPEC 파이프라인**: loop 가 DONE 으로 끝나면 그 SPEC 은 `done` 이 아니라 중간 상태 `integrating` 으로 두고, 폴링 틱당 한 스텝씩 다음을 멱등 전진(드레인)시킨다.
  - **forge 서브모드**:
    1. **통합**(`integration.sh`): base sync(rebase, ff 가능 시) → 작업 브랜치(`feat/<run-id>-<slug>`) push → 같은 head 의 open PR 재사용/생성. `spec-gap` BLOCKED 면 push·PR 없이 스펙 보강 재개 안내, 하드 BLOCKED 면 push·PR 없이 사람 에스컬레이션(둘 다 비완료 종착).
    2. **리뷰**(`review-loop.sh run`): `autopilot:review` 생산자를 1회 호출해 단일 판정(approve/request_changes/unavailable). `request_changes` 면 `must_adopt` 를 run-dir 하위 SPEC 델타로 만들어 **같은 head 브랜치 위에서** 재구현·재푸시(새 PR 미생성). `defer` 는 현 PR 에 섞지 않고 별도 기록. 세 가드(라운드 상한 기본 3·무진전·핑퐁)와 사람/head 게이트로 무한루프를 막는다.
    3. **승인+머지**(`merge.sh`): 분리된 자율 approver 신원으로 PR 승인 제출·확인(리뷰 봇 self-approve 무효) → 버전 범프 게이트(`plugins/` 변경 시 `plugin.json` 범프 강제) → `--ff-only` 머지(+base push) → `merged`.
  - **direct 서브모드**: `integration.sh integrate-direct` 로 작업 브랜치(`feat/<run-id>-<slug>`)만 식별하고(push·PR 우회) **적대적 리뷰 게이트**(`review-loop.sh run-direct`)로 넘긴다 — PR·원격 push 없이 로컬 작업 브랜치 diff 로 `autopilot:review` 생산자를 호출한다. 판정이 `approve` 면 `merge.sh finish`(승인 게이트만 우회)로 넘어가고, `request_changes` 면 forge 와 동일한 리뷰 루프(변경 요구분을 SPEC 델타로 같은 작업 브랜치 위 재구현 → 다음 틱 재리뷰)를 동일한 세 가드(라운드 상한·무진전·핑퐁) 안에서 수행한다(원격 push 없음). 세 가드 중 하나에 걸려 approve 없이 종료되면 그 SPEC 은 머지하지 않고 비완료(escalated)로 기록된다. **버전 범프 게이트와 `--ff-only` 머지·작업 공간 정리는 forge 서브모드와 동일하게 적용**된다. BLOCKED 분기(spec-gap/하드)는 forge 서브모드와 동일 헬퍼를 공유한다.
- **머지 게이트**: `merged` 에 도달한 SPEC 만 `done` 으로 전이한다. 따라서 **의존자는 의존성이 대상 브랜치에 머지된 뒤에만** 실행 큐에 풀리고, 갱신된 대상 브랜치 위에서 분기한다. 통합·리뷰가 비완료 종착(`blocked`/`escalated`)이면 그 SPEC 은 `failed` 이고 그 **이행적 의존자만** `skipped` 된다.
- **서브모드·대상 브랜치 sticky**: 최초 시작 때 결정된 서브모드(forge/direct)와 대상 브랜치는 run-dir 마커(`INTEGRATE` 내용=서브모드 / `TARGET_BRANCH`)로 보존되어 `--resume` 에서 동일하게 재개된다(재개 시 현재 env·플래그보다 마커 우선).
- **불변식**: 어떤 경로(forge·direct)에서도 force(강제) push·rebase·merge 를 쓰지 않는다(머지는 `git merge --ff-only` 만). 대상 브랜치 체크아웃+머지 구간은 run-dir 락으로 **직렬화**되어 동시 머지 레이스가 없다.
- **주입 가능한 인터페이스(mock 검증)**: `LOOP_CMD` `GIT_CMD` `FORGE_CMD`(기본 gh) `FORGE_BIN`(서브모드 판정용 forge CLI, 기본 gh) `DEFAULT_BRANCH`(대상 브랜치, 기본 main) `APPROVER` `REVIEW_BOT` `APPROVE_CMD` `REVIEW_ROUNDS_MAX`(3) `WATCH_DIRS`(plugins/) `REVIEW_PRODUCE_CMD` `INTEGRATION_CMD` `REVIEW_CMD` `MERGE_CMD`. 모든 외부 인터페이스가 주입 가능해 각 모듈을 mock 으로 독립 검증한다(실제 PR·머지 미수행).

## Subcommands

### dispatch start `<spec...>` [--max-parallel N] [--resume `<run-id>`] [--target-branch `<branch>`]

1 개 이상의 SPEC 파일 경로를 받아 새 run 을 시작한다. 통합(리뷰·머지)은 **항상 활성**이며(위 "통합" 절), forge 구성 여부로 forge/direct 서브모드가 갈린다. state 에 중간 상태 `integrating` 이 추가되고 `done` 은 "대상 브랜치에 머지됨"을 뜻한다. `--target-branch` 로 머지·동기화 대상 브랜치를 지정한다(미지정 시 기본 브랜치). 하위 호환을 위해 `--no-integrate`·`--integrate` 를 받되 무시한다(no-op).

- 입력 검증: 각 경로가 파일로 존재하고 읽을 수 있어야 한다. 하나라도 누락이면 보고 후 즉시 abort.
- DAG 구성: 각 SPEC frontmatter 의 `depends_on` 을 읽어 의존 인덱스를 만든다. cycle 이면 abort. 진단용 `WAVES.txt` 도 함께 기록(실행 스케줄은 준비도 기반).
- `<project_root>/.dispatch/runs/<run-id>/MANIFEST.txt` · `WAVES.txt` · `state.<slug>-<sha7>` · `LOG.md` 생성. (`<slug>` 는 가독용, `<sha7>` 는 SPEC abspath 해시로 다른 날짜·디렉토리 동명 SPEC 충돌 방지.) state 값: `pending`/`running`/`done`/`failed`/`skipped`.
- 준비도 스트리밍: 각 SPEC 의 모든 dep 이 done 이 되는 즉시 동시성 상한 이내에서 위임 시작. 한 SPEC 이 failed 면 그 이행적 의존자만 `skipped`, 독립 가지는 계속.
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
| `dispatch.sh` | run-id 디렉토리 관리·의존 인덱스 구성·준비도 스트리밍 위임·구조화 종료 판정·통합 드레인 driver |
| `lib-integration.sh` | per-SPEC 통합 상태 헬퍼(run-dir + 키: branch/pr/head/review-round/verdict/phase) |
| `integration.sh` | loop 종료신호 → base sync → push → PR 생성/재사용(forge) / PR 없이 작업 브랜치 식별(direct) |
| `review-loop.sh` | 리뷰 생산자 판정 → SPEC 델타 재구현(3가드). `run`=forge(PR·push), `run-direct`=PR 없는 로컬 리뷰 |
| `merge.sh` | 승인 게이트(forge) → 버전 범프 게이트 → 직렬화 ff-only 머지(대상 브랜치) |

각 통합 모듈은 `bash <module>.sh selftest` 로 mock 인터페이스 기반 독립 검증을 제공한다(실제 PR·머지 미수행). 스케줄러 통합 검증은 `bash dispatch.sh selftest`.

## 의존성

`git`, `bash` 3.2+, `sha256sum` 또는 `shasum`, `autopilot:loop` 스킬, `yq`(mikefarah). `yq` 는 depends_on 파싱(없으면 awk 폴백)뿐 아니라 **loop 구조화 상태(`status --json`) 판정의 단일 출처**이므로 `start`/`status`/`stop`/`watch` 에서 필수다(부재 시 명확히 정지 — 텍스트 컬럼으로 silent fallback 하지 않음). **forge 서브모드**는 추가로 `jq`(리뷰 판정 JSON 파싱)와 forge CLI(`gh`, 주입 가능)·리뷰 생산자(`autopilot:review`)를 쓴다. **direct 서브모드**(forge 미구성)는 forge CLI 없이 동작하지만, 적대적 리뷰 게이트를 위해 `jq` 와 리뷰 생산자(`autopilot:review`)는 쓴다(PR·원격 push 없이 로컬 작업 브랜치 diff 로 리뷰).

## 규칙

- 자체 작성·갱신하는 영역은 `<project_root>/.dispatch/runs/<run-id>/` 디렉토리 안의 파일들(SPEC 델타·백로그·통합 상태 포함)과 본 스킬의 정의 파일뿐이다. 작업 브랜치·PR·머지 같은 forge 부수효과를 제외하면 이 외 경로를 만들지 않는다.
- 자율 실행기 인터페이스(`loop.sh start|status|stop|cleanup|logs`) 외 child 워크트리·신호 파일을 직접 들여다보지 않는다.
- **통합·머지 소유권**: 통합이 항상 활성이므로 **dispatch 가 통합·리뷰·머지를 직접 소유**한다 — 머지가 의존자를 푸는 게이트는 본질적으로 dispatch 의 웨이브 스케줄링에 속하기 때문이다. 모든 forge·git·loop·리뷰 인터페이스는 주입 가능한 명령으로 두어 mock 검증되며, force 는 어떤 경로(forge·direct)에서도 쓰지 않는다.
- 분해(여러 SPEC 작성) 책임은 SPEC 작성 도구(`autopilot:spec` 등)에 있고, dispatch 는 이미 만들어진 SPEC 들만 받는다.
- child 의 종료 의도(완료/차단)는 자율 실행기가 신호로 표현하고, dispatch 는 그 공개 인터페이스가 제공하는 **구조화된 상태**(`loop.sh status --json` 의 `.state`·`.signals[]`)로만 읽는다 — 표 컬럼 위치·부분 문자열 일치에 의존하지 않는다. `signals` 의 의미(`DONE`/`BLOCKED`)는 워커 컨벤션이며 dispatch 는 정확 일치 멤버십으로 판정한다.
- run 디렉토리는 git 추적에서 제외한다(`.gitignore` 처리 권장).
