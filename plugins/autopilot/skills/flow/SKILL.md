---
name: flow
description: "내장 dynamic Workflow(멀티에이전트 오케스트레이션) 도구가 막힌 환경에서도 임의 depends_on DAG를 스트리밍 fan-out·동시성 상한·실패 이행 격리·저널 resume·결과 전달로 실행하고 싶을 때 사용 — Python 표준 라이브러리만으로 동작하는 독립 오케스트레이터 하니스의 진입점. 호출 'Skill(skill=\"flow\", args=\"<subcommand> [<args>]\")' (run/selftest/deps)."
allowed-tools:
  - Read
  - Bash(bash * flow.sh run:*)
  - Bash(bash * flow.sh selftest)
  - Bash(bash * flow.sh deps)
---

# flow

`flow` 는 내장 **dynamic Workflow 도구가 미가용**인 환경에서도 그 오케스트레이션을 재현하는 **독립 범용 하니스**(Workflow Replica)의 진입점이다. 임의의 의존성 그래프(DAG)를 받아, 각 노드를 **그 의존성이 끝나는 즉시** 동시성 상한 안에서 실행하고(스트리밍 fan-out), 노드 결과를 후속 노드로 전달하며, 실패를 이행적으로 격리하고, 중단된 실행을 저널로 재개한다. 엔진은 **Python 표준 라이브러리만** 사용한다(외부 패키지·네트워크 없음). 다른 스킬이 strong-parallel 불가 환경의 폴백으로 프로그램적으로 호출할 수 있도록, 러너의 입력→구조화(JSON) 출력 계약은 자기완결적이다.

## 호출

`Skill(skill: "flow", args: "<subcommand> [<args>]")`

또는 직접: `bash ${CLAUDE_PLUGIN_ROOT}/skills/flow/references/flow.sh <subcommand> [<args>]`

## Subcommands

### flow run `<workflow-definition.py>`

워크플로 정의 파일 하나를 받아 엔진으로 실행하고, **기계 판독 가능한 단일 JSON 결과**를 stdout 에 출력한다. 경로가 없거나 읽을 수 없으면 실행하지 않고 오류를 보고한다(비-0 종료).

- 노드 모드(`NODES`) 출력: `{"ok":true,"mode":"nodes","succeeded":[...],"failed":[...],"skipped":[...],"cached":[...],"results":{...}}`.
- 워크플로 모드(`WORKFLOW`) 출력: `{"ok":true,"mode":"workflow","result":<값>,"events":[...],"max_concurrency":N}`.
- 실패 시: `{"ok":false,"error":"..."}`.

### flow selftest

엔진의 자체 테스트 묶음을 실행해 통과 여부를 JSON 으로 보고한다 — `{"ok":true,"tests":N}` (실패 시 `ok:false` + stderr 로 상세).

### flow deps

런타임 의존성(`python3` 3.9+)의 가용 여부를 보고한다 — `{"python3":"<version>","available":true}`.

> 명시된 위 서브커맨드만 실행한다. 다른 서브커맨드는 추론하지 않고 오류로 종료한다.

## 워크플로 정의 (workflow definition)

`run` 이 받는 파일은 평범한 Python 파일이다. `workflow_replica` 가 import 가능한 상태로 로드되며, 다음 **진입점 중 정확히 하나**를 모듈 최상위에 노출한다:

- **`NODES`** — `Node` 리스트(선언적 DAG).
- **`WORKFLOW`** — `async def WORKFLOW(wf)` 스크립트(명령형 작성; 런타임 결정 그래프 가능).

선택 노브: `CONCURRENCY`(int, 기본 4), 선언적 모드에서 `JOURNAL`(resume 저널 경로).

### 사용 계약 (engine API)

import: `from workflow_replica import Node, run, command_node, callable_node, JsonlJournal, SubprocessAgentCaller, workflow`.

- **노드·의존성**: `Node(id, deps=(), runner=fn, meta=None)`. `runner` 는 `fn(inputs)`(sync/async)이고 `inputs` 는 `{의존노드id: 결과}`. 의존성이 모두 끝나는 즉시 노드가 시작된다(웨이브 배리어 없음).
- **노드 팩토리**: `command_node(id, argv, deps=())` 는 임의 외부 명령(종료 코드로 성공/실패 판정, LLM 비의존). `callable_node(id, fn, deps=())` 는 Python 콜러블.
- **동시성 상한**: `run(nodes, concurrency=N, journal=None)` — 동시에 실행 중인 노드 수 ≤ N. 명령형은 `workflow(script, concurrency=N)`; leaf(`wf.call`/`wf.command`/`wf.agent`)가 동시성의 bound 단위다.
- **실패 이행 격리**: 한 노드가 실패하면 그 **이행적 의존자만** skip 되고, 무관한 가지는 끝까지 실행된다.
- **결과 전달**: 노드 결과값은 그 노드에 의존하는 후속 노드의 `inputs`(또는 명령형 체인)로 전달된다.
- **저널 resume**: `run(..., journal=JsonlJournal("path.jsonl"))` — 재실행 시 **성공한 노드는 재실행하지 않고 캐시 결과를 사용**(키는 노드 정의 + 의존성 키를 fold 한 transitive 키라, 상위 변경 시 하위도 무효화). `CommandResult` 는 타입 보존 round-trip.
- **순환 검출**: 그래프에 순환이 있으면 어떤 노드도 실행하지 않고 `CyclicGraphError` 로 보고한다.
- **명령형 훅**: `wf.call(fn)`·`wf.command(argv)`·`wf.agent(prompt, caller, schema=...)`·`wf.parallel([thunk,...])`(배리어)·`wf.pipeline(items, *stages)`(스테이지 간 배리어 없음)·`wf.phase(title)`·`wf.log(msg)`. 스크립트가 결과를 `await` 한 뒤 다음 노드를 정할 수 있다(런타임 결정 그래프).
- **에이전트 노드(LLM)**: `SubprocessAgentCaller(argv=["claude","--print"])` 같은 caller 를 `wf.agent(prompt, caller, schema=<JSON-schema>)` 에 주면, LLM 서브에이전트가 프롬프트를 처리하고 스키마가 있으면 검증된 구조화 객체를 반환한다(불일치 시 재시도). 엔진 코어는 LLM 비의존이며 이 어댑터만 LLM 을 쓴다.

### 예시

```python
# workflow-definition (declarative)
from workflow_replica import Node, command_node
async def fetch(i):  return 21
async def double(i): return i["fetch"] * 2
NODES = [
    Node("fetch",  deps=(),        runner=fetch),
    Node("double", deps=("fetch",), runner=double),
    command_node("echo", ["echo", "hi"]),
]
CONCURRENCY = 4
```

```python
# workflow-definition (imperative, runtime-determined graph)
async def WORKFLOW(wf):
    seed = await wf.call(lambda i: 7)
    fan  = 3 if seed % 2 else 1            # 결과로 다음 노드 수 결정
    return await wf.parallel([(lambda n=n: wf.call(lambda i, n=n: n*n)) for n in range(fan)])
```

`bash references/flow.sh run <위 파일>` → 단일 JSON 결과.

## references

각 파일은 아래 "언제 읽나"의 상황이 올 때만 연다 — 평소엔 본문만으로 충분하다.

| 파일 | 역할 | 언제 읽나 |
|---|---|---|
| `flow.sh` | CLI 라우터 — `run`/`selftest`/`deps`. 명시된 서브커맨드만 실행, 구조화 JSON 출력 | 서브커맨드 라우팅·인자 파싱·종료 코드 동작을 확인하거나, 직접 `bash flow.sh ...` 로 호출하기 전에 읽는다 |
| `runner.py` | `run` 의 실행 로직 — 워크플로 정의를 import 해 엔진으로 실행하고 JSON 방출 | `run` 의 JSON 출력 스키마(필드·모드별 형태)를 프로그램적으로 소비하거나, import·실행 실패를 진단할 때 읽는다 |
| `workflow_replica/` | 엔진 패키지 — 스케줄러·노드·저널·에이전트 어댑터·스키마(stdlib only) | 워크플로 정의 파일을 작성하며 `Node`/`run`/`workflow`/팩토리 등 engine API 시그니처·동작을 확인할 때 읽는다 |
| `tests/` | 엔진 자체 테스트(`selftest` 가 실행) | engine API의 사용 예·기대 동작을 실동작 예시로 확인하거나, `selftest` 실패 원인을 좁힐 때 읽는다 |

## 의존성

`python3` 3.9+ 표준 라이브러리(graphlib·asyncio·subprocess·json). 외부 패키지·네트워크·내장 Workflow 도구 불필요. 가용 여부는 `flow deps` 로 확인.

## 규칙

- 명시된 subcommand(`run`/`selftest`/`deps`)만 실행한다. 다른 subcommand 를 추론하지 않는다.
- 엔진 동작은 수정하지 않는다(이 스킬은 래퍼다). 엔진 자체 변경은 별도 작업이다.
- 러너 출력은 기계 판독 가능한 JSON 이며, 호출자는 자유 텍스트 부분 문자열 일치에 의존하지 않는다.
- subcommand 의 JSON 출력·종료 코드를 그대로 던지지 말고 **사용자에게 요약한다** — `run` 은 성공/실패/스킵 노드와 결과값을, `selftest` 는 통과 테스트 수를, 오류면 사유를 자연어로 전달한다(다른 스킬이 프로그램적으로 호출할 때는 JSON 원문을 그대로 소비한다).
