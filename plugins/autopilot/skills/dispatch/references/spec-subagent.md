# SPEC 서브에이전트 계약 (per-SPEC implement·review·merge owner)

`dispatch` 가 준비된(모든 `depends_on` 이 `done`) SPEC마다 **정확히 1개** 띄우는 서브에이전트의 절차 계약. 한 서브에이전트가 **한 컨텍스트에서** 그 SPEC 의 전 생애(구현→리뷰→재구현→머지→보고)를 소유한다. 이 문서가 완료 조건 2–8 의 단일 출처다 — dispatch 의 결정적 책임(DAG 준비도·동시성·spawn/reap·done 시 의존자 해제·실패 이행 격리)은 `SKILL.md`·`dispatch.sh` 가 소유한다.

## 입력 (dispatch → 서브에이전트, 계약 경계)

- `spec` — SPEC 파일 경로(준비 보장).
- `target-branch` — 머지·동기화 대상(run 전역 주입).
- `run-dir`·`key` — 통합 상태(branch/pr/head/review-round/verdict/phase) 영속 위치(결정적 헬퍼 공유).

이 입력만으로 전 생애를 닫고, 종료 시 **머지됨(done)** 또는 **비완료(escalated/blocked)** 를 보고한다.

## 절차

**불변 경계(전 단계 공통)**: 이 계약은 전용 워커 타입(`plugins/autopilot/agents/dispatch-worker.md`)의 시스템 프롬프트로 **강제**된다. `loop`·`review` 는 **공개 스킬 인터페이스로만** 호출하고 내부 신호 파일·워크트리·하니스는 들여다보지 않는다(블랙박스). 구현·리뷰를 별도 서브에이전트로 나누지 않는다. **통합·리뷰·머지는 결정적 헬퍼(`integration.sh`·`review-loop.sh`·`merge.sh`)를 구동해 수행하고, raw `gh pr create/merge`·`git push`·force(push/merge/rebase) 를 직접 쓰지 않는다.** 어느 단계든 `unavailable`·판정 불가·해결 불가는 거짓 green 대신 **에스컬레이션**한다(force 로 우회하려는 충동은 곧 에스컬레이션 신호다).

### 1. 구현 — `loop` (완료 조건 2)

- 구현은 **반드시 `Skill(skill="autopilot:loop", ...)`** 로만 한다 — loop 이 전용 격리 워크트리(`<spec_dir>/.worktree`)를 만들고 소유한다. 대상 파일을 **직접 편집하거나** 임의 작업 브랜치를 직접 만들어 구현하지 않으며, `loop.sh` 를 Bash 로 **직접 구동하지 않는다**(스킬로만). 워커의 cwd 워크트리(예: 세션·메인 체크아웃)를 점유하지 않는다.
- 종료 의도는 공개 구조화 상태(`loop status --json` 의 `.state`·`.signals[]`)로만 판정. `spec-gap`/하드 BLOCKED 는 머지 없이 종착(스펙 보강 재개 안내 / 사람 에스컬레이션).

### 2. 리뷰 — `review` (완료 조건 2)

구현 DONE 이면 리뷰·승인은 **서브모드(forge CLI 가용 여부)로 갈리며**, 워커는 해당 헬퍼를 구동한다:

- **forge(gh 가용)**: `integration.sh integrate`(작업 브랜치 push → 같은 head 의 open PR 재사용/생성) 후 `review-loop.sh run`. **이 경로는 로컬 `review` 스킬을 호출하지 않는다** — 적대 리뷰·승인은 PR 의 호스팅측 리뷰가 담당하고, 머지 게이트는 PR 의 **`reviewDecision==APPROVED`** 다. 분리 승인 신원 구성은 요구하지 않으나, **승인이 관찰되기 전에는 머지하지 않는다.**
- **direct(forge 미가용)**: `integration.sh integrate-direct` 후 `review-loop.sh run-direct`. 원격 push·PR 없이 작업 브랜치 변경(base..head)을 **로컬 `review` 스킬**로 다관점 적대 리뷰 → 단일 판정(`approve`/`request_changes`/`unavailable`).

### 3. 반복 — request_changes (완료 조건 3·4)

- `request_changes` 면 지적(`must_adopt`)을 반영해 **같은 작업 브랜치 위에서** 재구현→재리뷰를 `approve` 까지 반복(새 브랜치/새 PR 미생성).
- **무한루프 가드**(`review-loop.sh` 결정적 판정, selftest 검증 — 라운드 상한 기본 3·무진전·동일 지적 핑퐁)에 걸리면 **머지 없이 에스컬레이션**. 라운드 카운트·직전 지적 집합은 `run-dir` 키로 영속. 가드 종료는 그 SPEC 만 끝내고 무관한 가지는 계속 진행한다.

### 4. 머지 — approve 후에만 (완료 조건 5·6·7)

`approve` **이후에만** 대상 브랜치로 머지하며 결정적 게이트(`merge.sh`)를 통과한다:

1. **버전 범프** — `plugins/` 변경이면 `plugin.json` SemVer 범프 강제.
2. **승인 게이트** — `merge.sh finish` 가 수행한다. **forge**: 머지 직전 PR 의 **`reviewDecision==APPROVED`** 를 재확인하고, 승인 전이면 머지하지 않고 차단(에스컬레이션). **direct**: 위 로컬 review 판정이 `approve` 일 때만. 두 경로 모두 분리 승인 신원의 정식 APPROVED 리뷰를 별도로 요구하진 않으나(forge 는 호스팅 리뷰 승인 자체가 게이트), **승인 없이는 머지하지 않는다.**
3. **fast-forward 전용** — `git merge --ff-only`. **force push/merge/rebase 를 어떤 경로에서도 쓰지 않는다.**

**동시 머지 직렬화**: 전역 락·dispatch 머지 순번 통제 없이 git 자체가 직렬성을 제공한다. 한 머지가 대상 브랜치를 전진시켜 ff 가 깨지면, 갱신된 대상에 **non-force 동기화**(rebase/merge)·충돌 해결 후 다시 ff 머지한다. 해결 불가면 에스컬레이션. 누가 먼저 머지하든 결과는 같다.

### 5. 보고 (완료 조건 5)

- **머지 완료** → done 보고. dispatch 가 `done`(=대상 브랜치 머지됨)으로 전이하고 의존자를 **갱신된 대상 브랜치 위에서** 해제.
- **비완료**(가드 소진·unavailable·승인 불가·충돌 해결 불가) → 에스컬레이션. dispatch 가 `failed` 로 두고 **그 이행적 의존자만** `skipped`(독립 가지는 계속).
