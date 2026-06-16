---
name: workflow-task
description: 백엔드에서 준비된(의존 충족) 태스크들을 무인으로 한 번에 자동 실행하려 할 때 사용 — list_ready로 준비 태스크를 모아 execute-task를 병렬 fan-out하는 DAG 없는 1회 드레이너. 주기 반복은 외부 스케줄러가 담당한다. 호출 'Skill(skill="workflow-task", args="start [--max-parallel N]")'.
allowed-tools:
  - Bash(bash * workflow-task.sh:*)
  - Bash(bash * adapter.sh:*)
  - Bash(bash * flow.sh:*)
  - Bash(bash * execute-task.sh:*)
  - Bash(git rev-parse:*)
  - Read
---

# workflow-task

**DAG 없는 1회 드레이너**다. `references/workflow-task.sh`가 다음을 수행한다:

1. `adapter list_ready` — 준비된(모든 `depends_on`이 done, 또는 lease가 stale한 in_progress 회수분) 태스크를 모은다.
2. **flow 평면 병렬 fan-out** — 의존 없는 노드 집합으로 각 태스크에 `execute-task start <id>`를 동시성 상한 내
   병렬 실행한다(`--max-parallel N`, 기본=준비 태스크 수). flow가 동시성·실패 격리·resume을 제공한다.
3. 한 패스 종료. done/blocked 상태 전이는 execute-task가 이미 수행하므로 별도 동기화가 없다.

**DAG를 갖지 않는다**: `list_ready`가 의존 충족분만 반환하므로 한 패스의 태스크들은 상호 독립이고, 의존 순서
해결은 백엔드가 **틱 간**에 한다(다음 스케줄러 호출의 `list_ready`가 새로 ready된 후행을 잡는다).

## 호출

```
WT="$(git rev-parse --show-toplevel)/plugins/autopilot/skills/workflow-task/references/workflow-task.sh"
bash "$WT" start [--max-parallel N]
```

출력은 한 줄 JSON(`{ready,succeeded,failed,flow_ok}`). 준비 태스크가 없으면 `{"ready":0,...}`로 즉시 종료.

## 무인 폴링 레시피

주기 반복은 **외부 스케줄러**(cron / ScheduleWakeup / 상위 에이전트)가 담당한다. 1패스 드레인이라 재시작·중복
호출에 안전하다(다음 호출이 새로 ready된 것만 집어든다).

```
*/10 * * * *  bash <plugin>/skills/workflow-task/references/workflow-task.sh start
```

## 재사용 엔진 (런타임 호출)

- **flow** — 평면 병렬 러너(동시성 상한·실패 격리·저널 resume). DAG 기능은 쓰지 않는다.
- **execute-task** — 각 준비 태스크의 전체 생애(구현→리뷰→머지→done).
- **task-backend 어댑터** — `list_ready`(depends_on + lease 회수 판정).

환경변수 override(`FLOW_CMD`/`EXECUTE_CMD`/`ADAPTER_CMD`)로 치환한다.

## 규칙

- **무인 실행**: 대화형 호출을 하지 않는다. DAG·준비도 스케줄링을 자체 구현하지 않는다(백엔드 list_ready가 SoT).
- 플러그인 자기완결 — `rules/`나 다른 스킬을 doc-link하지 않는다.
