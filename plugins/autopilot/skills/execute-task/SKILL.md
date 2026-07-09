---
name: execute-task
description: 등록된 단일 태스크를 격리 작업공간에서 자율 구현하고 리뷰·머지까지 완료하려 할 때 사용 — 태스크 본문을 임시 spec으로 떠 랄프 루프로 구현하고, origin 호스트(PR/MR/로컬)에 맞춰 리뷰·ff-only 머지한 뒤 백엔드 상태를 done으로 전이한다. 호출 'Skill(skill="execute-task", args="start <task-id> [--stop-at review] | status|stop|logs <task-id>")'.
allowed-tools:
  - Bash(bash * execute-task.sh:*)
  - Bash(bash * adapter.sh:*)
  - Bash(bash * forge.sh:*)
  - Bash(bash * loop.sh:*)
  - Bash(git rev-parse:*)
  - Bash(git add:*)
  - Bash(git status:*)
  - Bash(tail:*)
  - Read
---

# execute-task

등록된 **단일 태스크의 전체 생애**(구현→리뷰→머지→done)를 소유하는 실행기다. 결정적 드라이버
`references/execute-task.sh`가 다음을 수행한다:

1. `adapter materialize` — 태스크 본문을 임시 spec(`.task-work/<id>/SPEC.md`)으로 뜬다(본문=SPEC).
2. `adapter set_status in_progress` + **백그라운드 heartbeat lease 갱신**(크래시·행 워커는 lease가 stale해져
   `list_ready`가 회수). 잔여 워커 자취(워크트리·lock)는 시작 전 정리(reclaim)한다.
3. **loop 엔진**(랄프 루프)으로 포그라운드 구현. 반환 후 `status --json`으로 DONE/BLOCKED 분류.
   BLOCKED·미완 → `set_status blocked`(+로그) 후 종료.
4. DONE → `set_status review` → **forge 어댑터**(origin 라우팅)로 integrate → review(승인까지 반복, 가드) →
   merge(ff-only). github→PR / gitlab→MR(확장점) / origin 없음→로컬 review + direct.
5. merged → `set_status done`(+handoff 로그). `--stop-at review`면 머지 없이 review에서 정지(수동 단일 실행용).

## 호출

```
EXEC="$(git rev-parse --show-toplevel)/plugins/autopilot/skills/execute-task/references/execute-task.sh"
bash "$EXEC" start <task-id> [--stop-at review]   # ← run_in_background: true 필수 (아래 참고)
bash "$EXEC" status|stop|logs <task-id>
```

`status|stop|logs`는 task-id를 spec 경로로 해석해 loop 엔진에 위임한다.

> **`start`는 반드시 `run_in_background: true`(또는 동등한 비동기 실행 메커니즘)로 호출한다.**
> `start`는 구현 루프 + 리뷰 승인 폴링(`APPROVAL_WAIT_MAX` 기본 360 s) + 머지를 직렬 실행하므로
> 정상 경로도 10분을 초과할 수 있다. 동기 실행 시 런타임 도구의 타임아웃에 걸려 PR 생성·머지 단계가
> 중단된다. `status`·`stop`·`logs`는 단명(短命) 조회이므로 동기 호출로 무방하다.
>
> background 완료 notification 수신 후 결과를 확인한다:
> ```
> bash "$EXEC" logs <task-id>          # 상세 실행 로그
> bash "$EXEC" status <task-id>        # DONE / BLOCKED / 진행 중 요약
> ```
> status가 `blocked`이면 태스크 백엔드의 차단 사유·category를 확인하고 자가개선 절차를 밟는다.

## blocked 재진입

`blocked`로 끝난 태스크는 차단 원인을 해결한 뒤 **`start <task-id>`로 다시 실행하면 정상 파이프라인에
재진입**한다(blocked 전이 시 claim 락이 풀려 재-claim이 성공한다). 재진입은 **막힌 지점부터 재개**한다 —
loop 단계에서 막혔으면 loop을 재실행하고, forge 단계에서 막혔으면(`review_entered` 표지 존재) loop을 건너뛰고
integrate부터 재개한다. 재진입이 merge까지 성공하면 `.task-work/<id>/`·`.autopilot/runs/<id>/` 잔재가
정리된다(성공 시에만 — blocked로 남아 있는 동안은 사후검시용으로 보존된다).

재진입은 **사람의 명시적 재실행으로만** 일어난다. 자동 드레인(`workflow-task`/`list_ready`)은 blocked를
재실행 대상으로 잡지 않는다(무한 재시도 방지).

## 재사용 엔진 (런타임 호출, 그대로 둠)

- **loop 엔진**(랄프 루프) — 격리 워크트리에서 RED→GREEN→검증 이터레이션.
- **forge 어댑터** — origin 호스트별 integrate/review/merge. 내부적으로 검증된 워커 헬퍼를 감싼다.
- **task-backend 어댑터** — 상태 전이·lease·materialize.

엔진의 환경변수 override(`LOOP_CMD`/`FORGE_CMD`/`ADAPTER_CMD`/`HEARTBEAT_INTERVAL`/`REVIEW_MAX`)로 치환·튜닝한다.

## 규칙

- **무인 실행**: 드레인 경로에서 호출되므로 대화형 호출(AskUserQuestion 등)을 하지 않는다. 차단은 `blocked`
  상태 + 진행 로그로 표현한다.
- **blocked `category` 표면화 (자가개선 seam)**: loop 워커가 차단을 쓰면 그 `signals/BLOCKED` 본문 첫 줄은
  헌법 규약상 `category:`(`config-gap`·`spec-gap`·`architecture-gap`·`environment-gap`·`other`)를 싣는다 —
  execute-task의 한 실행이 이 BLOCKED 신호를 그대로 남긴다(새 훅 없이 category가 이미 노출됨). 이 category는
  `using-autopilot` 「자가개선 정책」(단일 소유)의 카테고리→행동 매핑이 소비한다 — **단일 실행 경로에서도**
  오케스트레이팅 세션이 그 신호의 category를 읽어 매핑대로 자가개선을 발동한다(코드가 자동 발동하는 게 아니라
  신호가 category를 노출하고 세션이 정책대로 행동한다). 단, 태스크 본문에 `자가개선-비활성` 마커가 있으면
  자가개선을 재트리거하지 않는다(depth-1 상한 존중).
- 플러그인 자기완결 — `rules/`나 다른 스킬을 doc-link하지 않는다. 상태 집합·전이의 단일 출처는 플러그인
  `task-backend/contract.md`.
- 의존성·DAG는 다루지 않는다 — 단일 태스크만. 여러 태스크의 fan-out은 `workflow-task`가 한다.
