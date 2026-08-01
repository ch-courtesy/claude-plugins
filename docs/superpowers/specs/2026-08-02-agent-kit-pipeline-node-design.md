# agent-kit: /pipeline + /node 스킬 설계

날짜: 2026-08-02 · 상태: 승인됨 (brainstorming + grill-me 인터뷰 Q1–Q11, 설계 전 섹션 사용자 승인)

## 목적

n8n처럼 입출력이 있는 노드를 연결해 실행 흐름을 만들고, 그 정의를 독립 실행 가능한 워크플로 스킬로 컴파일하는 스킬 쌍.

**핵심 원칙: 정의 = 소스, 생성된 스킬 = 바이너리.** `/pipeline`이 YAML 그래프 정의를 만들고 자립형 SKILL.md로 컴파일. 실행은 생성된 스킬이 담당(`/pipeline run` 없음).

## 확정 결정

| # | 결정 |
|---|------|
| Q1 | 산출물: 정의 파일 + 자립형 SKILL.md 컴파일 |
| Q2 | 정의 형식: YAML |
| Q3 | 노드 = 재사용 "타입"(라이브러리 파일) + 파이프라인 내 "인스턴스"(설정 주입), 일회용 인라인 허용 |
| Q4 | 혼합 실행: script/http→Bash(curl), MCP→도구 직접 호출, LLM→서브에이전트. 오케스트레이터 = 스킬 읽는 Claude 세션 |
| Q5 | 노드 타입마다 JSON Schema식 inputs/outputs 선언, 출력은 `runs/<run-id>/<노드id>.json` 영속화, LLM 노드는 출력 스키마 강제 |
| Q6 | 유틸 노드 v1: if/switch, foreach, merge, transform(jq), human-gate. retry·timeout·on_error는 모든 노드 공통 속성. 의존 없는 노드 자동 병렬. delay/trigger/sub-pipeline 제외(v2) |
| Q7 | 배포: `plugins/agent-kit/` 신설(첫 스킬로 pipeline·node), marketplace.json 등록, thinktank 규약 준수 |
| Q8 | 레이아웃: 정의 `.pipelines/<이름>.yaml`, 노드 `.pipelines/nodes/<이름>.yaml`, 컴파일 결과 `.claude/skills/<이름>/`, 런 기록 `.pipelines/runs/<run-id>/`(gitignore) |
| Q9 | 인터페이스 — /node: create/test/list, /pipeline: create/compile/list. validate는 compile 내장 |
| Q10 | 공통 속성 `retry`(기본 0)·`timeout`·`on_error: fail(기본)\|continue`. state.json 기반 `resume <run-id>` — 완료 노드 스킵. human-gate 거부 시 중단(상태 보존) |
| Q11 | 생성 스킬 = 자립형 스냅샷(전부 임베드), 헤더에 `compiled-from: <경로> @<해시>`로 드리프트 감지 |

## 노드 타입 YAML

`.pipelines/nodes/summarize.yaml`:

```yaml
name: summarize
kind: llm              # llm | script | http | mcp
description: 텍스트 요약
inputs:
  text: {type: string, required: true}
  max_words: {type: number, default: 100}
outputs:
  summary: {type: string}
run:                   # kind별 상이
  prompt: |
    다음 텍스트를 {{max_words}} 단어 이내로 요약: {{text}}
# script: run: {command: "python summarize.py", input: stdin-json, output: stdout-json}
# http:   run: {method: POST, url: "...", body: {...템플릿}}
# mcp:    run: {tool: "mcp__server__tool", args: {...매핑}}
```

## 파이프라인 YAML

`.pipelines/daily-report.yaml`:

```yaml
name: daily-report
description: 이슈 수집→요약→승인→발행
inputs:
  repo: {type: string, required: true}
nodes:
  - id: fetch
    type: fetch-issues            # 라이브러리 참조
    in: {repo: $pipeline.repo}
    retry: 2
    timeout: 60
  - id: each
    util: foreach                 # 노드 하나를 배열에 map, 출력 results 배열
    items: $fetch.issues
    node: summarize
    in: {text: $item.body}
  - id: combine
    util: transform
    in: {items: $each.results}
    expr: '{summaries: [.items[].summary]}'
  - id: gate
    util: human-gate
    message: "발행할까요?"
  - id: publish
    inline: {kind: script, run: {command: "sh publish.sh"}}
    in: {content: $combine.summaries}
    on_error: continue
```

- edge 별도 선언 없음 — `$노드id.출력` 참조에서 의존성 자동 도출. `util: if`는 `then:/else:`에 후속 노드 id 나열.
- 참조 문법: `$pipeline.<입력>`, `$<노드id>.<출력>`, foreach 내부 한정 `$item`.
- validate(컴파일 내장): 참조 무결성, 필수 입력 미매핑, 타입 불일치, 순환 감지.

## 컴파일 산출물 `.claude/skills/<이름>/`

- `SKILL.md` — frontmatter(name, description, `compiled-from: <경로> @<해시>`) + 실행 지시: 토폴로지 순서, 노드별 실행법 인라인, 데이터 매핑, 오류·재개 규칙. `.pipelines/` 없어도 단독 동작·타 프로젝트 복사 가능.
- `graph.yaml` — 정의+노드 전체 스냅샷(감사·재개 참조용).

## 생성 스킬 런타임

- 호출 `/<이름> [입력]`, `/<이름> resume <run-id>`.
- 노드 완료마다 `runs/<run-id>/<노드id>.json` + `state.json` 갱신. resume은 state.json 기준 실패 지점부터 완료 노드 스킵.
- human-gate는 AskUserQuestion, 거부 시 중단(상태 보존 — resume 가능).
- LLM 노드: 서브에이전트 실행 + 출력 스키마 강제. script/http: Bash/curl. MCP: 도구 직접 호출.

## v2 이월

delay, trigger(cron — 기존 schedule 스킬 영역), sub-pipeline 호출, fallback edge(오류 전용 분기).
