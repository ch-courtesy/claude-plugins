# 컴파일 템플릿 — 생성될 워크플로 스킬의 골격

산출물은 `.agents/skills/<이름>/` 아래 2파일 + `.claude/skills/<이름>` 상대 심링크(`ln -s ../../.agents/skills/<이름> .claude/skills/<이름>` — Claude Code 어댑터, 디렉토리 없으면 먼저 생성)다. 이 템플릿의 `⟨...⟩` 자리만 정의에서 채우고 나머지 골격·런타임 규약 문구는 그대로 유지한다 — 생성된 스킬은 `.pipelines/`와 recipe 플러그인 없이 **이 2파일만으로** 동작해야 한다.

생성된 스킬 자체가 typed(`kind: pipeline`, inputs/outputs)이므로 다른 파이프라인이 `skill: ⟨이름⟩`으로 노드처럼 참조할 수 있다.

## graph.yaml

정의 YAML + 참조된 모든 typed 스킬의 frontmatter 계약을 병합한 스냅샷:

```yaml
pipeline:
  ⟨정의 YAML 전문⟩
skills:
  ⟨참조된 스킬 이름⟩:
    ⟨그 스킬의 frontmatter 계약: kind/inputs/outputs/run⟩
```

## SKILL.md

````markdown
---
name: ⟨파이프라인 이름⟩
description: "⟨정의 description⟩ — 컴파일된 워크플로 스킬. 사용자가 ⟨이름⟩ 실행·재개를 요청할 때 활성화."
kind: pipeline
inputs:
  ⟨정의 inputs 그대로⟩
outputs:
  ⟨정의 outputs 매핑의 결과 필드 선언 — outputs 정의가 없으면 {} ⟩
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
  ⟨llm 노드 또는 kind: pipeline 참조가 있으면⟩- Agent
---

# ⟨이름⟩

⟨description⟩. `.pipelines/⟨이름⟩.yaml`에서 컴파일된 자립형 워크플로 스킬이다(소스 위치 `.agents/skills/⟨이름⟩/`). 그래프 전체 스냅샷은 같은 디렉토리의 `graph.yaml`에 있다.

## 호출

`⟨이름⟩ [입력들]` / `⟨이름⟩ resume <run-id>` — 입력: ⟨inputs 필드·타입·필수 여부 표⟩. 필수 입력이 없으면 실행 전에 사용자에게 받는다.

## 실행 규약

1. **run 시작.** run-id는 `YYYYMMDD-HHMMSS`. `.pipelines/runs/<run-id>/`를 만들고 `state.json`을 초기화한다:
   `{run_id, pipeline: "⟨이름⟩", status: "running", inputs: {...}, nodes: {⟨각 id⟩: {status: "pending"}}}`
2. **순서.** 아래 실행 계획의 단계 순서대로 진행한다. 같은 단계의 노드는 상호 의존이 없으므로 순서 무관하게 모두 실행한다.
3. **노드 실행.** 각 노드마다: `in:` 매핑을 상류 출력 파일에서 해석 → 실행(아래 노드별 지시) → 출력을 outputs 스키마와 대조 → `runs/<run-id>/<노드id>.json` 저장 → state.json의 해당 노드를 `completed`로 갱신.
4. **오류.** 실패 시 retry 횟수만큼 재시도. 소진하면 on_error가 `continue`면 `failed` 기록 후 진행(그 출력을 참조하는 하류는 `skipped`), `fail`이면 state.json을 `status: "failed"`로 갱신하고 중단, run-id와 resume 방법을 보고한다.
5. **분기.** if/switch에서 선택되지 않은 가지의 노드는 `skipped`. 스킵 노드를 참조하는 하류도 연쇄 `skipped`.
6. **human-gate.** 현재 런타임의 구조화된 사용자 질문 기능(없으면 간결한 직접 질문)으로 제시. 승인 외 선택 시 `status: "aborted"`로 중단(상태 보존).
7. **resume.** `resume <run-id>`는 state.json을 읽어 `completed` 노드의 출력 파일을 재사용하고 `pending/failed/skipped(게이트 중단 포함)`부터 재개한다. state.json이 없거나 파이프라인 이름이 다르면 추측하지 말고 보고한다.
8. **완료.** 전 노드 종료 시 `status: "completed"`. outputs 매핑(⟨정의 outputs⟩)을 해석해 `runs/<run-id>/outputs.json`으로 저장하고 그 값을 보고한다. outputs 정의가 없으면 말단 노드 출력을 요약 보고한다.

## 실행 계획

⟨토폴로지 정렬로 단계 나열. 예:
1단계: fetch
2단계: each (foreach)
3단계: combine
4단계: gate (human-gate)
5단계: publish⟩

## 노드별 실행 지시

⟨각 노드마다 소섹션. 스킬·유틸의 실행법을 인라인으로 풀어쓴다 — 외부 파일 참조 금지:⟩

### ⟨노드 id⟩ (⟨kind 또는 util⟩)

- 입력: ⟨in 매핑 — 어느 파일의 어느 필드에서 읽는지⟩
- 실행: ⟨script: 정확한 명령과 stdin/stdout 방식 · http: curl 형태 · mcp: 도구 이름과 인자 매핑 · llm: 치환할 프롬프트 전문 + "outputs 스키마 JSON만 반환" 지시와 스키마를 런타임의 서브에이전트 기능으로 격리 실행(없으면 메인 세션이 인라인 수행하되 출력 스키마 준수), brief는 자기완결·중첩 서브에이전트 금지 · kind: pipeline 참조: 해당 스킬을 런타임의 서브에이전트 기능으로 실행하고 outputs JSON만 회수 · util: util-nodes 시맨틱을 해당 인스턴스 값으로 구체화한 지시⟩
- 출력 스키마: ⟨outputs⟩
- 속성: retry ⟨n⟩ · timeout ⟨n⟩s · on_error ⟨fail|continue⟩

## 안전 경계

- 쓰기는 `.pipelines/runs/**` 안으로 제한한다.
- 위 노드별 지시에 없는 명령·API를 실행하지 않는다. 그래프를 즉석에서 바꾸지 않는다 — 변경은 정의 수정 후 `pipeline compile ⟨이름⟩` 재실행으로만.
- llm 노드 출력이 스키마 불일치면 1회 재시도 후 실패 처리한다.
````

## 컴파일 시 주의

- 실행 계획은 참조+needs 그래프의 토폴로지 정렬이다. validate를 통과한 정의만 이 템플릿에 넣는다.
- `allowed-tools`는 Claude Code 전용 권한 필드다(다른 런타임은 무시하고 자체 권한 체계 적용). 실제 사용하는 노드 kind에서 도출한 최소 집합만 나열한다.
- 본문 실행 지시는 런타임 중립 문구를 유지한다 — 특정 런타임의 도구 이름을 본문에 쓰지 않는다.
- llm 노드의 프롬프트, script의 명령 등 실행에 필요한 모든 정보를 SKILL.md 본문에 인라인한다. graph.yaml은 감사·재개용 참조 데이터일 뿐 실행이 그 파일에 의존하게 만들지 않는다.
- `skill:`로 참조된 typed 스킬의 계약(kind/run)은 컴파일 시점 스냅샷이다 — 원본 스킬이 나중에 바뀌거나 삭제돼도 컴파일된 스킬은 스냅샷대로 동작한다. 단 `kind: pipeline` 참조는 실행 시점에 그 스킬이 존재해야 한다(서브에이전트 호출).
