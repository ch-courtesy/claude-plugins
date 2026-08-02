# 파이프라인 YAML 스키마

파일 위치: `.pipelines/<이름>.yaml` (이름 = kebab-case, 파일명과 `name` 필드 일치)

## 최상위 필드

| 필드 | 필수 | 설명 |
|---|---|---|
| `name` | ✔ | 파이프라인 이름 — 컴파일된 스킬 이름이 된다 |
| `description` | ✔ | 한 줄 목적 — 컴파일된 스킬 description의 바탕 |
| `inputs` | ✔ | 파이프라인 호출 시 받는 입력 (typed 스킬과 같은 필드 선언, 없으면 `{}`) |
| `nodes` | ✔ | 노드 인스턴스 목록 |
| `outputs` | | 출력 매핑 (예: `{report: $combine.summaries}`) — 컴파일된 스킬의 outputs 계약. 다른 파이프라인에 노드로 편입하려면 필수 |

## 노드 인스턴스

셋 중 정확히 하나로 정의한다:

```yaml
- id: fetch
  skill: fetch-issues       # ① typed 스킬 참조: .agents/skills/fetch-issues/SKILL.md
  in: {repo: $pipeline.repo}   #    kind: pipeline(컴파일된 파이프라인)도 참조 가능 — 합성

- id: gate
  util: human-gate          # ② 유틸 노드: util-nodes.md 참조
  message: "발행할까요?"

- id: publish
  inline:                   # ③ 일회용 인라인: typed 계약의 kind/inputs/outputs/run
    kind: script
    inputs: {content: {type: string, required: true}}
    outputs: {ok: {type: boolean}}
    run: {command: "sh publish.sh", input: stdin-json, output: stdout-json}
  in: {content: $combine.summaries}
```

공통 필드:

| 필드 | 필수 | 설명 |
|---|---|---|
| `id` | ✔ | 파이프라인 내 유일, kebab-case |
| `in` | 계약에 inputs 있으면 ✔ | 입력 매핑 — 값은 `$참조` 또는 리터럴 |
| `retry` | | 실패 시 재시도 횟수, 기본 0 |
| `timeout` | | 초 단위 제한, 기본 없음 |
| `on_error` | | `fail`(기본) \| `continue` — continue면 실패를 기록하고 하류 진행 (해당 노드 출력을 참조하는 노드는 스킵) |

## 참조 문법

| 형태 | 의미 |
|---|---|
| `$pipeline.<입력>` | 파이프라인 호출 입력 |
| `$<노드id>.<출력>` | 상류 노드의 출력 필드 |
| `$item` | foreach body 안에서만 — 현재 순회 항목 |

- edge는 선언하지 않는다. `in:`(및 유틸 노드의 `items:`, `cond` 입력 등)의 `$노드id` 참조가 곧 의존성이다.
- 순서만 필요하고 데이터가 불필요하면 `needs: [노드id]`로 명시 의존을 건다 (예: human-gate 뒤에만 실행).
- 참조가 없는 노드끼리는 병렬 실행 대상이다.

## 예시

```yaml
name: daily-report
description: 이슈 수집→요약→승인→발행
inputs:
  repo: {type: string, required: true}
outputs:
  summaries: $combine.summaries
nodes:
  - id: fetch
    skill: fetch-issues
    in: {repo: $pipeline.repo}
    retry: 2
    timeout: 60
  - id: each
    util: foreach
    items: $fetch.issues
    skill: summarize
    in: {text: $item.body}
  - id: combine
    util: transform
    in: {items: $each.results}
    expr: '{summaries: [.items[].summary]}'
  - id: gate
    util: human-gate
    message: "발행할까요?"
  - id: publish
    inline: {kind: script, inputs: {content: {type: array, required: true}}, outputs: {ok: {type: boolean}}, run: {command: "sh publish.sh"}}
    in: {content: $combine.summaries}
    needs: [gate]
    on_error: continue
```
