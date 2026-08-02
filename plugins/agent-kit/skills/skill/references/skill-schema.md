# typed 스킬 스키마

파일 위치: `.claude/skills/<이름>/SKILL.md` (이름 = kebab-case, 디렉토리명과 `name` 필드 일치)

typed 스킬 = 일반 스킬 frontmatter(name, description) + 기계 가독 계약 확장 필드(kind, inputs, outputs, run). 확장 필드는 harness가 무시하고 pipeline 스킬의 validate·compile이 읽는다. frontmatter가 계약의 정본이고 본문은 그 계약의 실행 지시다.

## frontmatter 필드

| 필드 | 필수 | 설명 |
|---|---|---|
| `name` | ✔ | 스킬 이름 (kebab-case) |
| `description` | ✔ | 단독 발동 조건을 담은 한 줄 설명 |
| `kind` | ✔ | `llm` \| `script` \| `http` \| `mcp` — `pipeline`은 compile 전용 |
| `inputs` | ✔ | 입력 필드 선언 맵 (없으면 `{}` 명시) |
| `outputs` | ✔ | 출력 필드 선언 맵 |
| `run` | ✔ | kind별 실행법 — `run-kinds.md` 참조 (`kind: pipeline`은 run 없음) |

## 입출력 필드 선언

```yaml
inputs:
  text: {type: string, required: true, description: 원문}
  max_words: {type: number, default: 100}
outputs:
  summary: {type: string}
```

- `type`: `string | number | boolean | array | object`
- `required`: 기본 false. `default`가 있으면 required 불필요.
- `default`: 미제공 시 채울 값.
- `description`: 선택. llm kind 출력 스키마 강제 시 그대로 사용되므로 모호한 필드에는 쓰는 것을 권장.

## 예시 (전문)

```markdown
---
name: summarize
description: "텍스트를 지정 단어 수 이내로 요약할 때 사용."
kind: llm
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

텍스트 요약 typed 스킬. 파이프라인 노드로도 쓰인다 — 계약은 frontmatter가 정본.

## 실행

1. inputs 스키마대로 입력을 수집한다 (required 미충족 시 사용자에게 받는다).
2. run.prompt에 입력을 치환해 수행한다.
3. outputs 스키마를 만족하는 JSON(`{"summary": "..."}`)으로 결과를 보고한다.
```

## 본문 골격

본문은 위 예시처럼 세 단계(입력 수집 → kind별 실행 → outputs JSON 보고)를 그 스킬의 값으로 구체화해 생성한다. script/http는 실행할 명령을, mcp는 도구 이름을 본문에 그대로 적는다. frontmatter와 본문이 어긋나면 frontmatter를 따른다.

## 규칙

- 템플릿 치환 문법은 `{{입력이름}}` — inputs에 선언된 필드만 치환 대상.
- outputs가 여러 필드면 실행 결과는 그 필드들을 키로 가진 JSON 객체 하나다.
- typed 스킬은 파이프라인을 몰라야 한다 — 특정 파이프라인 전용 로직·경로를 하드코딩하지 않는다.
