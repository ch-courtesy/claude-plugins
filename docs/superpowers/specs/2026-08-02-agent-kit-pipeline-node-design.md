# agent-kit: /pipeline + /skill 스킬 설계

날짜: 2026-08-02 · 상태: 승인됨 (brainstorming + grill-me 인터뷰 Q1–Q12, 설계 전 섹션 사용자 승인)
개정: 같은 날 Q12(노드=스킬 전환)로 /node를 /skill로 대체 — 노드 정의가 YAML 라이브러리에서 typed SKILL.md로 바뀜.

## 목적

n8n처럼 입출력이 있는 노드를 연결해 실행 흐름을 만들고, 그 정의를 독립 실행 가능한 워크플로 스킬로 컴파일하는 스킬 쌍.

**핵심 원칙: 정의 = 소스, 생성된 스킬 = 바이너리.** `/pipeline`이 YAML 그래프 정의를 만들고 자립형 SKILL.md로 컴파일. 실행은 생성된 스킬이 담당(`/pipeline run` 없음).

## 확정 결정

| # | 결정 |
|---|------|
| Q1 | 산출물: 정의 파일 + 자립형 SKILL.md 컴파일 |
| Q2 | 파이프라인 정의 형식: YAML |
| Q3 | 노드 = 재사용 "타입" + 파이프라인 내 "인스턴스"(설정 주입), 일회용 인라인 허용 → Q12가 타입의 저장 형태를 typed 스킬로 대체 |
| Q4 | 혼합 실행: script/http→Bash(curl), MCP→도구 직접 호출, LLM→서브에이전트. 오케스트레이터 = 스킬 읽는 Claude 세션 |
| Q5 | 노드마다 JSON Schema식 inputs/outputs 선언, 출력은 `runs/<run-id>/<노드id>.json` 영속화, LLM 노드는 출력 스키마 강제 |
| Q6 | 유틸 노드 v1: if/switch, foreach, merge, transform(jq), human-gate. retry·timeout·on_error는 모든 노드 공통 속성. 의존 없는 노드 자동 병렬. delay/trigger 제외(v2) |
| Q7 | 배포: `plugins/agent-kit/` 신설(첫 스킬로 pipeline·skill), marketplace.json 등록, thinktank 규약 준수 |
| Q8 | 레이아웃: typed 스킬 `.claude/skills/<이름>/SKILL.md`, 정의 `.pipelines/<이름>.yaml`, 컴파일 결과 `.claude/skills/<이름>/`, 런 기록 `.pipelines/runs/<run-id>/`(gitignore) |
| Q9 | 인터페이스 — /skill: create/test/list, /pipeline: create/compile/list. validate는 compile 내장 |
| Q10 | 공통 속성 `retry`(기본 0)·`timeout`·`on_error: fail(기본)\|continue`. state.json 기반 `resume <run-id>` — 완료 노드 스킵. human-gate 거부 시 중단(상태 보존) |
| Q11 | 생성 스킬 = 자립형 스냅샷(전부 임베드), 헤더에 `compiled-from: <경로> @<해시>`로 드리프트 감지 |
| Q12 | **노드 = 스킬.** /node → /skill. 노드 정의 = typed frontmatter(kind/inputs/outputs/run)를 가진 `.claude/skills/<이름>/SKILL.md` — 단독 호출과 파이프라인 편입이 같은 계약 공유. 노드에는 컴파일 없음(SKILL.md가 소스이자 실행체). 컴파일된 파이프라인도 typed(`kind: pipeline`)라 다른 파이프라인의 노드로 참조 가능 → sub-pipeline v2 항목 소멸. 확장 필드는 harness가 무시, pipeline validate만 읽음 |

## typed 스킬 (노드)

`.claude/skills/summarize/SKILL.md`:

```markdown
---
name: summarize
description: "텍스트를 지정 단어 수 이내로 요약할 때 사용."
kind: llm              # llm | script | http | mcp (pipeline은 compile 전용)
inputs:
  text: {type: string, required: true}
  max_words: {type: number, default: 100}
outputs:
  summary: {type: string}
run:
  prompt: |
    다음 텍스트를 {{max_words}} 단어 이내로 요약: {{text}}
---
# summarize
(본문 = frontmatter 계약의 실행 지시: 입력 수집 → kind별 실행 → outputs 스키마 JSON 보고.
 frontmatter가 정본.)
```

- script: `run: {command, input: stdin-json|env|args, output: stdout-json|stdout-text}`
- http: `run: {method, url, headers, body}` (curl 실행)
- mcp: `run: {tool, args, output?}`
- `/skill test <이름>`이 모의 입력 단독 실행 + 출력 스키마 대조 담당(직접 호출은 스키마 검증 없음).

## 파이프라인 YAML

`.pipelines/daily-report.yaml`:

```yaml
name: daily-report
description: 이슈 수집→요약→승인→발행
inputs:
  repo: {type: string, required: true}
outputs:                          # 선택 — 컴파일된 스킬의 출력 계약(합성 시 필수)
  summaries: $combine.summaries
nodes:
  - id: fetch
    skill: fetch-issues           # typed 스킬 참조 (컴파일된 파이프라인도 가능)
    in: {repo: $pipeline.repo}
    retry: 2
    timeout: 60
  - id: each
    util: foreach                 # 스킬 하나를 배열에 map, 출력 results 배열
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
    inline: {kind: script, inputs: {...}, outputs: {...}, run: {command: "sh publish.sh"}}
    in: {content: $combine.summaries}
    needs: [gate]
    on_error: continue
```

- edge 별도 선언 없음 — `$노드id.출력` 참조에서 의존성 자동 도출. `util: if`는 `then:/else:`에 후속 노드 id 나열.
- 참조 문법: `$pipeline.<입력>`, `$<노드id>.<출력>`, foreach 내부 한정 `$item`. 데이터 없는 순서 의존은 `needs:`.
- validate(컴파일 내장): 구조, 참조 무결성, 필수 입력·타입 일치, 순환(자기 포함 포함), 실행 안전(미해석 치환자·시크릿 하드코딩).

## 컴파일 산출물 `.claude/skills/<이름>/`

- `SKILL.md` — frontmatter(`kind: pipeline`, inputs/outputs, `compiled-from: <경로> @<해시>`) + 실행 지시: 토폴로지 순서, 노드별 실행법 인라인, 데이터 매핑, 오류·재개 규칙. `.pipelines/` 없어도 단독 동작.
- `graph.yaml` — 정의 + 참조된 typed 스킬 frontmatter 계약 스냅샷(감사·재개용). 참조 스킬이 나중에 바뀌거나 삭제돼도 컴파일된 스킬은 스냅샷대로 동작(단 `kind: pipeline` 참조는 실행 시점에 해당 스킬 필요 — 서브에이전트 호출).

## 생성 스킬 런타임

- 호출 `/<이름> [입력]`, `/<이름> resume <run-id>`.
- 노드 완료마다 `runs/<run-id>/<노드id>.json` + `state.json` 갱신. resume은 state.json 기준 실패·중단 지점부터 완료 노드 스킵.
- human-gate는 AskUserQuestion, 거부 시 중단(상태 보존 — resume 가능).
- LLM 노드·`kind: pipeline` 노드: 서브에이전트 실행(+출력 스키마 강제). script/http: Bash/curl. MCP: 도구 직접 호출.
- 완료 시 outputs 매핑 해석 → `runs/<run-id>/outputs.json` + 보고.

## v2 이월

delay, trigger(cron — 기존 schedule 스킬 영역), fallback edge(오류 전용 분기).
