# 컴파일 템플릿 — 생성될 워크플로 스킬의 골격

산출물은 `.claude/skills/<이름>/` 아래 2파일이다. 이 템플릿의 `⟨...⟩` 자리만 정의에서 채우고 나머지 골격·런타임 규약 문구는 그대로 유지한다 — 생성된 스킬은 `.pipelines/`와 agent-kit 플러그인 없이 **이 2파일만으로** 동작해야 한다.

## graph.yaml

정의 YAML + 참조된 모든 노드 타입 YAML을 병합한 스냅샷:

```yaml
pipeline:
  ⟨정의 YAML 전문⟩
node_types:
  ⟨참조된 타입 이름⟩:
    ⟨그 타입 YAML 전문⟩
```

## SKILL.md

````markdown
---
name: ⟨파이프라인 이름⟩
description: "⟨정의 description⟩ — 컴파일된 워크플로 스킬. 사용자가 ⟨이름⟩ 실행·재개를 요청할 때 활성화."
compiled-from: ".pipelines/⟨이름⟩.yaml @⟨shasum-256 앞 12자리⟩"
allowed-tools:
  - AskUserQuestion
  - Read
  - Write(.pipelines/runs/**)
  - Bash(mkdir -p .pipelines/runs/**)
  - Bash(jq:*)
  - Bash(date:*)
  ⟨script 노드가 있으면⟩- Bash(⟨해당 command 패턴⟩)
  ⟨http 노드가 있으면⟩- Bash(curl:*)
  ⟨llm 노드가 있으면⟩- Agent
---

# ⟨이름⟩

⟨description⟩. `.pipelines/⟨이름⟩.yaml`에서 컴파일된 자립형 워크플로 스킬이다. 그래프 전체 스냅샷은 같은 디렉토리의 `graph.yaml`에 있다.

## 호출

`⟨이름⟩ [입력들]` / `⟨이름⟩ resume <run-id>` — 입력: ⟨inputs 필드·타입·필수 여부 표⟩. 필수 입력이 없으면 실행 전에 사용자에게 받는다.

## 실행 규약

1. **run 시작.** run-id는 `YYYYMMDD-HHMMSS`. `.pipelines/runs/<run-id>/`를 만들고 `state.json`을 초기화한다:
   `{run_id, pipeline: "⟨이름⟩", status: "running", inputs: {...}, nodes: {⟨각 id⟩: {status: "pending"}}}`
2. **순서.** 아래 실행 계획의 단계 순서대로 진행한다. 같은 단계의 노드는 상호 의존이 없으므로 순서 무관하게 모두 실행한다.
3. **노드 실행.** 각 노드마다: `in:` 매핑을 상류 출력 파일에서 해석 → 실행(아래 노드별 지시) → 출력을 outputs 스키마와 대조 → `runs/<run-id>/<노드id>.json` 저장 → state.json의 해당 노드를 `completed`로 갱신.
4. **오류.** 실패 시 retry 횟수만큼 재시도. 소진하면 on_error가 `continue`면 `failed` 기록 후 진행(그 출력을 참조하는 하류는 `skipped`), `fail`이면 state.json을 `status: "failed"`로 갱신하고 중단, run-id와 resume 방법을 보고한다.
5. **분기.** if/switch에서 선택되지 않은 가지의 노드는 `skipped`. 스킵 노드를 참조하는 하류도 연쇄 `skipped`.
6. **human-gate.** AskUserQuestion으로 제시. 승인 외 선택 시 `status: "aborted"`로 중단(상태 보존).
7. **resume.** `resume <run-id>`는 state.json을 읽어 `completed` 노드의 출력 파일을 재사용하고 `pending/failed/skipped(게이트 중단 포함)`부터 재개한다. state.json이 없거나 파이프라인 이름이 다르면 추측하지 말고 보고한다.
8. **완료.** 전 노드 종료 시 `status: "completed"`, 말단 노드 출력을 요약 보고한다.

## 실행 계획

⟨토폴로지 정렬로 단계 나열. 예:
1단계: fetch
2단계: each (foreach)
3단계: combine
4단계: gate (human-gate)
5단계: publish⟩

## 노드별 실행 지시

⟨각 노드마다 소섹션. 타입·유틸의 실행법을 인라인으로 풀어쓴다 — 외부 파일 참조 금지:⟩

### ⟨노드 id⟩ (⟨kind 또는 util⟩)

- 입력: ⟨in 매핑 — 어느 파일의 어느 필드에서 읽는지⟩
- 실행: ⟨script: 정확한 명령과 stdin/stdout 방식 · http: curl 형태 · mcp: 도구 이름과 인자 매핑 · llm: 치환할 프롬프트 전문 + "outputs 스키마 JSON만 반환" 지시와 스키마, 서브에이전트 brief는 자기완결·중첩 Agent 금지 · util: util-nodes 시맨틱을 해당 인스턴스 값으로 구체화한 지시⟩
- 출력 스키마: ⟨outputs⟩
- 속성: retry ⟨n⟩ · timeout ⟨n⟩s · on_error ⟨fail|continue⟩

## 안전 경계

- 쓰기는 `.pipelines/runs/**` 안으로 제한한다.
- 위 노드별 지시에 없는 명령·API를 실행하지 않는다. 그래프를 즉석에서 바꾸지 않는다 — 변경은 정의 수정 후 `pipeline compile ⟨이름⟩` 재실행으로만.
- llm 노드 출력이 스키마 불일치면 1회 재시도 후 실패 처리한다.
````

## 컴파일 시 주의

- 실행 계획은 참조+needs 그래프의 토폴로지 정렬이다. validate를 통과한 정의만 이 템플릿에 넣는다.
- allowed-tools는 실제 사용하는 노드 kind에서 도출한 최소 집합만 나열한다.
- llm 노드의 프롬프트, script의 명령 등 실행에 필요한 모든 정보를 SKILL.md 본문에 인라인한다. graph.yaml은 감사·재개용 참조 데이터일 뿐 실행이 그 파일에 의존하게 만들지 않는다.
