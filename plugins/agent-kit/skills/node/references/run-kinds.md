# kind별 run 스펙

노드 실행의 공통 계약: **입력은 inputs 스키마를 만족하는 JSON 객체, 출력은 outputs 스키마를 만족하는 JSON 객체.** kind는 그 사이의 실행 방법만 다르다.

## script

```yaml
run:
  command: "python summarize.py"   # 실행 명령
  input: stdin-json                 # stdin-json | env | args
  output: stdout-json               # stdout-json | stdout-text
```

- `input: stdin-json`(기본): 입력 객체를 JSON으로 stdin에 전달.
- `input: env`: 각 입력을 대문자 환경변수로 전달 (`text` → `TEXT`).
- `input: args`: `{{입력이름}}` 치환된 command를 그대로 실행.
- `output: stdout-json`(기본): stdout 전체를 JSON으로 파싱해 출력 객체로 사용.
- `output: stdout-text`: stdout 전문을 outputs의 **유일한** string 필드에 담는다 (outputs 필드 2개 이상이면 stdout-text 금지).
- 종료 코드 0이 아니면 실패로 처리한다.

## http

```yaml
run:
  method: POST                      # GET | POST | PUT | PATCH | DELETE
  url: "https://api.example.com/v1/items/{{id}}"
  headers: {Authorization: "Bearer {{token}}"}
  body: {text: "{{text}}"}          # POST/PUT/PATCH만
```

- 실행은 curl. 응답 본문을 JSON 파싱해 출력 객체로 사용하고, outputs에 선언된 필드만 추린다.
- HTTP 4xx/5xx는 실패로 처리한다.
- 시크릿은 값 하드코딩 대신 `{{token}}`처럼 입력으로 받아 주입한다.

## mcp

```yaml
run:
  tool: "mcp__github__create_issue"  # MCP 도구 전체 이름
  args: {title: "{{title}}", body: "{{body}}"}   # 도구 인자 ← 입력 매핑
  output: result                     # 선택: 도구 결과에서 출력으로 쓸 경로 (jq path)
```

- 도구 결과가 outputs 스키마와 다르면 `output` 경로로 추출·재매핑한다.
- 실행 환경에 해당 MCP 서버가 없으면 실패로 처리하고 어떤 서버가 필요한지 보고한다.

## llm

```yaml
run:
  prompt: |
    다음 텍스트를 {{max_words}} 단어 이내로 요약: {{text}}
```

- 서브에이전트로 실행한다. brief에는 치환된 프롬프트 + outputs 스키마를 명시하고 "스키마를 만족하는 JSON만 반환, 다른 텍스트 금지"를 포함한다.
- 반환 JSON이 outputs 스키마와 불일치하면 1회 재시도 후 실패로 처리한다.
- 비결정성은 이 경계(출력 스키마 강제) 안에 봉쇄한다 — 하류 노드는 스키마만 믿는다.
