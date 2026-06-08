# SPEC 서브에이전트 계약 (per-SPEC implement·review·merge owner)

`dispatch` 가 준비된(모든 `depends_on` 이 `done`) SPEC마다 **정확히 1개** 띄우는 서브에이전트의 절차 계약. 한 서브에이전트가 **한 컨텍스트에서** 그 SPEC 의 전 생애(구현→리뷰→재구현→머지→보고)를 소유한다. 이 문서가 완료 조건 2–8 의 단일 출처다 — dispatch 의 결정적 책임(DAG 준비도·동시성·spawn/reap·done 시 의존자 해제·실패 이행 격리)은 `SKILL.md`·`dispatch.sh` 가 소유한다.

## 입력 (dispatch → 서브에이전트, 계약 경계)

- `spec` — SPEC 파일 경로(준비 보장).
- `target-branch` — 머지·동기화 대상(run 전역 주입).
- `run-dir`·`key` — 통합 상태(branch/pr/head/review-round/verdict/phase) 영속 위치(결정적 헬퍼 공유).

이 입력만으로 전 생애를 닫고, 종료 시 **머지됨(done)** 또는 **비완료(escalated/blocked)** 를 보고한다.

## 절차

**불변 경계(전 단계 공통)**: `loop`·`review` 는 **공개 스킬 인터페이스로만** 호출하고 내부 신호 파일·워크트리·하니스는 들여다보지 않는다(블랙박스). 구현·리뷰를 별도 서브에이전트로 나누지 않는다. 어느 단계든 `unavailable`·판정 불가·해결 불가는 거짓 green 대신 **에스컬레이션**한다.

### 1. 구현 — `loop` (완료 조건 2)

- `Skill(skill="loop", ...)` 로 격리 작업 브랜치 `feat/<run-id>-<slug>` 위에서 구현.
- 종료 의도는 공개 구조화 상태(`loop status --json` 의 `.state`·`.signals[]`)로만 판정. `spec-gap`/하드 BLOCKED 는 머지 없이 종착(스펙 보강 재개 안내 / 사람 에스컬레이션).

### 2. 리뷰 — `review` (완료 조건 2)

- 구현 DONE 이면 `Skill(skill="review", ...)` 로 다관점 적대 리뷰 → 머신리더블 단일 판정(`approve`/`request_changes`/`unavailable`).
- **리뷰 대상은 서브모드로 갈린다**(forge CLI 가용 여부로 판정):
  - **forge**: 작업 브랜치 push → 같은 head 의 open PR 재사용/생성 → **PR 대상** 리뷰. 분리 승인 신원(approver) 불요.
  - **direct**(forge 미가용): 원격 push·PR 없이 **작업 브랜치 변경(base..head)** 로컬 적대 리뷰.

### 3. 반복 — request_changes (완료 조건 3·4)

- `request_changes` 면 지적(`must_adopt`)을 반영해 **같은 작업 브랜치 위에서** 재구현→재리뷰를 `approve` 까지 반복(새 브랜치/새 PR 미생성).
- **무한루프 가드**(`review-loop.sh` 결정적 판정, selftest 검증 — 라운드 상한 기본 3·무진전·동일 지적 핑퐁)에 걸리면 **머지 없이 에스컬레이션**. 라운드 카운트·직전 지적 집합은 `run-dir` 키로 영속. 가드 종료는 그 SPEC 만 끝내고 무관한 가지는 계속 진행한다.

### 4. 머지 — approve 후에만 (완료 조건 5·6·7)

`approve` **이후에만** 대상 브랜치로 머지하며 결정적 게이트(`merge.sh`)를 통과한다:

1. **버전 범프** — `plugins/` 변경이면 `plugin.json` SemVer 범프 강제.
2. **머지(분리 승인 신원 불요)** — 가용 forge 토큰(예: gh 인증)으로 수행. approve 판정은 위 적대 리뷰가 이미 책임졌고 이 단계는 버전·ff 게이트만 더한다. forge=PR 경유, direct=로컬 작업 브랜치 머지, 게이트는 동일.
3. **fast-forward 전용** — `git merge --ff-only`. **force push/merge/rebase 를 어떤 경로에서도 쓰지 않는다.**

**동시 머지 직렬화**: 전역 락·dispatch 머지 순번 통제 없이 git 자체가 직렬성을 제공한다. 한 머지가 대상 브랜치를 전진시켜 ff 가 깨지면, 갱신된 대상에 **non-force 동기화**(rebase/merge)·충돌 해결 후 다시 ff 머지한다. 해결 불가면 에스컬레이션. 누가 먼저 머지하든 결과는 같다.

### 5. 보고 (완료 조건 5)

- **머지 완료** → done 보고. dispatch 가 `done`(=대상 브랜치 머지됨)으로 전이하고 의존자를 **갱신된 대상 브랜치 위에서** 해제.
- **비완료**(가드 소진·unavailable·승인 불가·충돌 해결 불가) → 에스컬레이션. dispatch 가 `failed` 로 두고 **그 이행적 의존자만** `skipped`(독립 가지는 계속).
