# SPEC 서브에이전트 계약 (per-SPEC implement·review·merge owner)

`dispatch` 가 준비된(모든 `depends_on` 이 `done`) SPEC마다 **정확히 1개** 띄우는 서브에이전트의
절차 계약이다. 한 서브에이전트는 **한 컨텍스트에서 그 SPEC 의 전 생애**(구현→리뷰→재구현→
머지→보고)를 소유한다. dispatch 는 이 절차의 내부를 들여다보지 않고 결과(머지됨/비완료)만 받는다.

이 문서는 완료 조건 2–8 의 단일 출처다. dispatch 의 결정적 책임(DAG 준비도·동시성·spawn/reap·
done 시 의존자 해제·실패 이행 격리)은 SKILL.md 와 `dispatch.sh` 가 소유한다.

## dispatch 가 서브에이전트에 넘기는 입력 (계약 경계)

- `spec` — 구현할 SPEC 파일 경로(준비됨이 보장된 상태로 위임).
- `target-branch` — 머지·동기화 대상 브랜치(run 전역, dispatch 가 일관 주입).
- `run-dir`·`key` — 통합 상태(branch/pr/head/review-round/verdict/phase) 영속 위치(결정적 헬퍼 공유).

서브에이전트는 이 입력만으로 자기 컨텍스트에서 전 생애를 닫고, 종료 시 **머지됨(done)** 또는
**비완료(escalated/blocked)** 를 dispatch 에 보고한다.

## 절차

### 1. 구현 — `loop` 스킬 (완료 조건 2)

서브에이전트는 `Skill(skill="loop", ...)` **공개 인터페이스로** 그 SPEC 을 격리 작업 브랜치
(`feat/<run-id>-<slug>`) 위에서 구현한다. loop 의 내부 신호 파일·워크트리·하니스를 직접 들여다보지
않는다(블랙박스 경계). 구현·리뷰를 위해 **별도의 추가 서브에이전트로 나누지 않는다** — 한 컨텍스트가
loop·review 를 직접 호출한다.

- loop 이 `unavailable`/실패/판정 불가로 끝나면 거짓 머지 대신 그 SPEC 을 **에스컬레이션**한다(완료 조건 8).
- loop 의 종료 의도(DONE/BLOCKED)는 그 공개 구조화 상태(`loop status --json` 의 `.state`·`.signals[]`)로만 읽는다.
  `spec-gap`/하드 BLOCKED 는 머지 없이 비완료 종착(스펙 보강 재개 안내 / 사람 에스컬레이션).

### 2. 리뷰 — `review` 스킬 (완료 조건 2)

구현이 DONE 이면 `Skill(skill="review", ...)` **공개 인터페이스로** 변경을 다관점 적대 리뷰해
머신리더블 단일 판정(`approve`/`request_changes`/`unavailable`)을 받는다.

- **리뷰 대상은 통합 서브모드로 갈린다**(forge 백엔드 가용 여부로 판정):
  - **forge**(forge CLI 사용 가능): 작업 브랜치를 push 하고 같은 head 의 open PR 을 재사용/생성해
    **PR 을 대상으로** 리뷰. 분리 승인 신원(approver) 구성은 요구하지 않는다.
  - **direct**(forge 백엔드 미가용): 원격 push·PR 없이 **작업 브랜치 변경(base..head)** 을 대상으로 로컬 적대 리뷰.
- 판정이 `unavailable`(리뷰 producer 실패·판정 불가)이면 거짓 승인 대신 **에스컬레이션**한다(완료 조건 8).

### 3. 반복 — request_changes → 재구현→재리뷰 (완료 조건 3·4)

판정이 `request_changes` 면 그 지적(`must_adopt`)을 반영해 **같은 작업 브랜치 위에서** 다시 `loop`
으로 재구현하고 다시 `review` 하기를 `approve` 판정이 날 때까지 반복한다(새 작업 브랜치/새 PR 미생성).

반복은 **무한루프 가드**(결정적 헬퍼가 판정 — 라운드 상한 기본 3·무진전·동일 지적 핑퐁)에 걸리면
**머지 없이 종료(에스컬레이션)** 한다(완료 조건 4). 이 가드 판정 로직은 `review-loop.sh` 의 결정적
헬퍼에 있고 selftest 로 검증된다(서브에이전트는 그 판정을 호출해 반복을 멈춘다 — 라운드 카운트·
직전 지적 집합은 `run-dir` 키로 영속). 한 SPEC 이 가드로 종료돼도 **무관한 SPEC 가지는 계속 진행**한다
(그 격리는 dispatch 의 실패 이행 격리가 보장).

### 4. 머지 — approve 후에만 (완료 조건 5·6·7)

`approve` 판정 **이후에만** 대상 브랜치로 머지한다. 머지는 **결정적 게이트**(`merge.sh`)를 통과한다:

1. **버전 범프 게이트** — `plugins/` 변경이면 `plugin.json` SemVer 범프를 강제(완료 조건 11 의 일부).
2. **머지(분리 승인 신원 불필요)** — 머지는 **가용한 forge 토큰**(예: gh 인증)으로 수행한다. 별도의
   분리 승인 신원(`APPROVER`)의 정식 APPROVED 리뷰를 머지 전제로 두지 않는다 — 리뷰 수렴(`approve`)
   판정은 위 적대 리뷰가 이미 책임졌고, 머지 단계는 버전·ff 게이트만 더한다. forge 서브모드는 통합이
   PR 을 통하며(작업 브랜치 push→PR), direct 서브모드는 PR 없이 로컬 작업 브랜치를 머지한다. 두 경로
   모두 버전·ff 게이트는 동일 적용.
3. **fast-forward 전용 머지** — `git merge --ff-only`. **force push·force merge·force rebase 를 어떤
   경로에서도 쓰지 않는다**(완료 조건 6).

#### 동시 머지의 git 직렬화 (완료 조건 6)

여러 서브에이전트가 같은 대상 브랜치로 동시에 머지할 때 **전역 락이나 dispatch 의 머지 순번 통제 없이**
git 자체 메커니즘이 직렬성을 제공한다. 한 서브에이전트의 머지가 대상 브랜치를 전진시켜 다른
서브에이전트의 머지가 더 이상 fast-forward 가 아니게 되면, 그 서브에이전트는 **갱신된 대상 브랜치에
동기화(non-force rebase/merge)하고 충돌을 해결한 뒤** 다시 ff 머지한다. 해결 불가면 거짓 green 대신
에스컬레이션한다. 누가 먼저 머지하든 결과는 같다.

### 5. 보고 (완료 조건 5)

- **머지 완료** → dispatch 에 done 보고. dispatch 가 그 SPEC 을 `done`(=대상 브랜치에 머지됨)으로
  전이하고 의존자를 해제한다. 의존자는 **갱신된 대상 브랜치 위에서** 분기한다.
- **비완료**(가드 소진·loop/review unavailable·승인 불가·충돌 해결 불가) → 에스컬레이션 보고.
  dispatch 가 그 SPEC 을 `failed` 로 두고 **그 이행적 의존자만** `skipped` 한다(독립 가지는 계속).

## 안전 불변식 (요약)

- approve 없이 머지 없음. 적대 리뷰가 approve 판정을 낸 이후에만 머지(완료 조건 5).
- 거짓 green 금지: loop/review unavailable·충돌 해결 불가 → 에스컬레이션(완료 조건 7·8).
- force 금지: 어떤 경로에서도 force push/merge/rebase 미사용(완료 조건 6).
- 블랙박스 경계: loop·review 는 공개 스킬 인터페이스로만 호출, 내부 신호 파일·워크트리 미열람.
- 결정적 가드·게이트(라운드 상한·무진전·핑퐁·버전 범프·ff 머지)는 헬퍼가 판정하며 selftest 로 검증된다.
</content>
