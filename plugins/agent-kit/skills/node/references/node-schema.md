# 노드 타입 YAML 스키마

파일 위치: `.pipelines/nodes/<이름>.yaml` (이름 = kebab-case, 파일명과 `name` 필드 일치)

## 필드

| 필드 | 필수 | 설명 |
|---|---|---|
| `name` | ✔ | 노드 타입 이름 (kebab-case) |
| `kind` | ✔ | `llm` \| `script` \| `http` \| `mcp` |
| `description` | ✔ | 한 줄 목적 |
| `inputs` | ✔ | 입력 필드 선언 맵 (없으면 `{}` 명시) |
| `outputs` | ✔ | 출력 필드 선언 맵 |
| `run` | ✔ | kind별 실행법 — `run-kinds.md` 참조 |

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
- `description`: 선택. LLM 노드 출력 스키마 강제 시 그대로 사용되므로 모호한 필드에는 쓰는 것을 권장.

## 예시

```yaml
name: summarize
kind: llm
description: 텍스트 요약
inputs:
  text: {type: string, required: true}
  max_words: {type: number, default: 100}
outputs:
  summary: {type: string}
run:
  prompt: |
    다음 텍스트를 {{max_words}} 단어 이내로 요약하고,
    {"summary": "..."} JSON만 출력: {{text}}
```

## 규칙

- 템플릿 치환 문법은 `{{입력이름}}` — inputs에 선언된 필드만 치환 대상.
- outputs가 여러 필드면 실행 결과는 그 필드들을 키로 가진 JSON 객체 하나다.
- 노드 타입은 파이프라인을 몰라야 한다 — 특정 파이프라인 전용 로직·경로를 하드코딩하지 않는다.
