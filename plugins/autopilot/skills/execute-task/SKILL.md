---
name: execute-task
description: 등록된 단일 태스크를 격리 작업공간에서 자율 구현하고 리뷰·머지까지 완료하려 할 때 사용 — 태스크 본문을 임시 spec으로 떠 랄프 루프로 구현하고, origin 호스트(PR/MR/로컬)에 맞춰 리뷰·ff-only 머지한 뒤 백엔드 상태를 done으로 전이한다. 호출 'Skill(skill="execute-task", args="start <task-id> [--stop-at review] | status|stop|logs <task-id>")'.
allowed-tools:
  - Bash(bash * execute-task.sh:*)
  - Bash(bash * adapter.sh:*)
  - Bash(bash * forge.sh:*)
  - Bash(bash * loop.sh:*)
  - Bash(git rev-parse:*)
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
bash "$EXEC" start <task-id> [--stop-at review]
bash "$EXEC" status|stop|logs <task-id>
```

`status|stop|logs`는 task-id를 spec 경로로 해석해 loop 엔진에 위임한다.

## 재사용 엔진 (런타임 호출, 그대로 둠)

- **loop 엔진**(랄프 루프) — 격리 워크트리에서 RED→GREEN→검증 이터레이션.
- **forge 어댑터** — origin 호스트별 integrate/review/merge. 내부적으로 검증된 워커 헬퍼를 감싼다.
- **task-backend 어댑터** — 상태 전이·lease·materialize.

엔진의 환경변수 override(`LOOP_CMD`/`FORGE_CMD`/`ADAPTER_CMD`/`HEARTBEAT_INTERVAL`/`REVIEW_MAX`)로 치환·튜닝한다.

## 규칙

- **무인 실행**: 드레인 경로에서 호출되므로 대화형 호출(AskUserQuestion 등)을 하지 않는다. 차단은 `blocked`
  상태 + 진행 로그로 표현한다.
- 플러그인 자기완결 — `rules/`나 다른 스킬을 doc-link하지 않는다. 상태 집합·전이의 단일 출처는 플러그인
  `task-backend/contract.md`.
- 의존성·DAG는 다루지 않는다 — 단일 태스크만. 여러 태스크의 fan-out은 `workflow-task`가 한다.
