---
scope:
  include:
    - plugins/autopilot/skills/dispatch/references/dispatch.sh
    - plugins/autopilot/skills/dispatch/references/merge.sh
    - plugins/autopilot/skills/dispatch/references/integration.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
---

# dispatch 통합 서브모드 정상화 — forge 백엔드 가용 시 approver 없이 토큰 머지

## 무엇을 만들 것인가
dispatch 가 통합 서브모드(forge / direct)를 가르는 기준을, "분리 승인 신원(approver)
구성 여부"가 아니라 **forge 백엔드 가용 여부**로 바꾼다.

- forge 백엔드가 가용하면 분리 approver 가 없어도 **forge 서브모드**(작업 브랜치 push →
  PR 생성/재사용)를 쓴다.
- forge 서브모드의 머지는 **분리 approver 의 승인을 전제하지 않고**, 가용한 forge 토큰으로
  생성된 PR 을 통해 수행한다. 분리 approver 신원 요구·그 신원의 승인 제출·그 신원의 APPROVED
  리뷰를 머지 전제로 두던 게이트를 제거한다.
- forge 백엔드가 **가용하지 않을 때만** 기존 direct 서브모드(PR 없는 로컬 적대적 리뷰 게이트
  후 로컬 머지)로 폴백한다.

forge 서브모드의 나머지 통합 흐름(작업 브랜치 push, PR 생성/재사용, 적대적 리뷰 판정으로의
수렴, 버전 범프 게이트, fast-forward 전용·force 금지·직렬화 머지, 머지 후 done 전이로 의존자
해제)은 그대로 유지한다 — 이 변경은 **서브모드 판정 기준과 분리-approver 요구 제거**에만
국한된다.

## 목적 (왜)
forge 백엔드(GitHub 등)가 있는 정상 상황인데도 분리 approver 가 구성되지 않았다는 이유만으로
direct 서브모드(PR·원격 리뷰 없이 대상 브랜치로 직접 머지)로 떨어지던 것을 바로잡는다.
백엔드가 있으면 PR 을 통해 통합하고 머지는 가용 토큰으로 수행하는 것이 정상 동작이며,
분리 approver 부재가 그 정상 경로를 막아서는 안 된다.

## 완료 조건
- 항상 forge 백엔드(forge CLI = FORGE_BIN)가 가용이면 통합 서브모드는 forge 다 — 분리
  approver 구성 여부와 무관하다.
- 항상 forge 백엔드(FORGE_BIN)가 가용하지 않으면 통합 서브모드는 direct 다.
- forge 서브모드에서 분리 approver 가 구성되지 않아도 통합이 멈추지 않는다 — 머지가 분리
  approver 의 APPROVED 리뷰를 전제로 차단되지 않고, 가용한 forge 토큰으로 수행된다.
- forge 서브모드의 머지는 생성된 PR 을 통해 이뤄지며, 대상 브랜치에 force(강제) push·rebase 를
  쓰지 않는다(기존 fast-forward 전용·force 금지 불변식과 merge-via-PR 정합 보존).
- 항상 머지 전 적대적 리뷰 판정이 approve 이고 버전 범프 게이트를 통과해야 한다(기존 리뷰·
  버전 게이트는 분리 approver 제거와 무관하게 그대로 적용).
- 통합 서브모드 결정은 run-dir 마커로 영속되어 `--resume` 에서 동일하게 재개된다(기존 sticky
  동작 보존).
- 기존 mock selftest 가 갱신된 서브모드 판정(FORGE_BIN 기준)과 approver 없는 forge 머지
  경로를 검증하며 통과한다(실제 PR·머지 미수행).

## 범위
포함:
- `dispatch.sh` — 서브모드 판정(현 `forge_configured`)을 forge 백엔드 가용 판정으로 바꾸고,
  approver 기반 분기를 제거. 관련 selftest 갱신.
- `merge.sh` — 분리 approver 요구(그 신원의 승인 확인·APPROVE_CMD 승인 제출)를 제거하고,
  forge 머지를 가용 토큰 + PR 경로로 수행. 관련 selftest 갱신.
- `integration.sh` — 위 변경에 필요한 범위에서만(예: 서브모드 호출 경로) 조정. 관련 selftest
  갱신.

비-목표 / 제외:
- direct 서브모드의 로컬 리뷰·로컬 머지 동작 자체 변경(폴백 조건만 "백엔드 미가용"으로 좁힌다).
- 적대적 리뷰(`autopilot:review`) 판정 로직·라운드 가드·버전 범프 게이트의 의미 변경.
- forge 머지가 `.github` CI 리뷰(claude/codex) 체크 통과를 기다리도록 만드는 것(이 SPEC 밖 —
  머지 게이트는 기존 적대적 리뷰 판정 + 버전 게이트를 유지한다).
- fast-forward 전용·force 금지·직렬화 락 불변식 변경.

## 검증
이 SPEC 의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로
본다. 검증을 실행하는 진입 명령은 SPEC 이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로
정의한다.

## 제약
- 머지는 가용한 forge 토큰으로 **생성된 PR 을 통해** 수행한다. 대상 브랜치로의 직접 force
  push·rebase 는 쓰지 않는다(기존 불변식 + merge-via-PR 보존).
- 기존 mock 주입 인터페이스(`FORGE_BIN`/`FORGE_CMD`/`APPROVE_CMD`/`GIT_CMD`/`MERGE_CMD` 등)와
  selftest 구조를 깨지 않고 갱신한다 — 실제 PR·머지를 수행하지 않는 self-referential 검증을
  유지한다.
- 서브모드·대상 브랜치의 run-dir 마커 영속과 `--resume` sticky 동작을 보존한다.
- 코드 주석·문서 문구(서브모드 판정 설명)를 "forge 백엔드 가용 여부" 기준으로 갱신한다.

## 위험
- 분리 approver 제거로 forge 머지가 적대적 리뷰 판정만으로 진행되므로, `.github` CI 리뷰를
  머지 게이트로 기대하는 독자에게 오해가 있을 수 있다 — 서브모드 판정 주석과 머지 게이트
  설명에 "분리 approver 없이 가용 토큰으로 PR 머지, 머지 게이트=적대적 리뷰 판정+버전 게이트"
  를 명확히 적어 완화한다.
- selftest 가 APPROVER 로 서브모드를 제어하던 기존 케이스가 깨질 수 있다 — FORGE_BIN 기준으로
  재구성하고 approver-없는-forge 머지 케이스를 추가해 회귀를 막는다.
