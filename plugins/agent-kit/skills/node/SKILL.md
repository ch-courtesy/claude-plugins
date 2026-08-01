---
name: node
description: "파이프라인에서 재사용할 노드 타입(입출력 스키마 + 실행법)을 만들고 검증할 때 사용. 사용자가 노드 생성, 노드 테스트, 노드 목록, 파이프라인 부품 정의를 요청할 때 활성화."
allowed-tools:
  - AskUserQuestion
  - Agent
  - Read
  - Write(.pipelines/**)
  - Glob
  - Grep
  - Bash(ls:*)
  - Bash(find:*)
  - Bash(mkdir -p .pipelines/**)
  - Bash(jq:*)
  - Bash(date:*)
---

# node

파이프라인의 부품인 **노드 타입**을 만들고 검증한다. 노드 타입은 입출력 스키마와 실행법을 선언한 재사용 단위이며, `.pipelines/nodes/<이름>.yaml` 파일 하나로 저장된다. 파이프라인은 이 타입을 참조해 인스턴스(설정 주입)로 사용한다.

## 호출

`node create` / `node test <이름> [--input '<json>']` / `node list` — 인자가 없으면 `create`로 간주한다. 노드 이름은 kebab-case, 같은 이름 파일이 있으면 덮어쓰지 말고 다른 이름 또는 갱신 여부를 선택받는다.

## 노드 타입 계약

- 파일: `.pipelines/nodes/<이름>.yaml` **단일 파일 1개**. 스키마는 `references/node-schema.md`를 따른다.
- `kind`는 `llm | script | http | mcp` 넷 중 하나. kind별 `run` 형식은 `references/run-kinds.md`를 따른다.
- `inputs`/`outputs`는 JSON Schema식 필드 선언(`type`, `required`, `default`, `description`)이 필수다. 스키마 없는 노드는 만들지 않는다.

## create 워크플로

1. **인터뷰.** 노드의 목적, kind, 입출력 필드를 AskUserQuestion으로 한 주제씩 확정한다. 사용자가 준 정보로 충분하면 질문을 생략하고 확인만 받는다.
2. **run 정의.** kind별 형식(`references/run-kinds.md`)에 따라 실행법을 작성한다. script는 명령과 입출력 방식(stdin-json/stdout-json), http는 메서드·URL·본문 템플릿, mcp는 도구 이름·인자 매핑, llm은 프롬프트 템플릿을 정의한다.
3. **저장.** `.pipelines/nodes/<이름>.yaml`로 저장하고 요약(이름, kind, 입출력)을 보고한다.
4. **테스트 제안.** 저장 직후 `node test <이름>` 실행 여부를 묻는다.

## test 워크플로

1. **입력 준비.** `--input` JSON이 없으면 inputs 스키마에서 필드별 모의 값을 사용자에게 받거나 default를 쓴다. required 필드가 비면 실행하지 않는다.
2. **실행.** kind별로 실행한다:
   - `script`/`http`: 실행할 명령(또는 curl)을 사용자에게 먼저 보여주고 확인받은 뒤 Bash로 실행한다.
   - `mcp`: 해당 MCP 도구를 인자 매핑대로 직접 호출한다.
   - `llm`: 프롬프트에 입력을 치환해 서브에이전트로 실행하고, outputs 스키마 형태의 JSON만 반환하게 한다.
3. **검증.** 출력 JSON을 outputs 스키마와 대조한다 — 누락 필드, 타입 불일치를 보고한다. 통과/실패와 실제 출력을 그대로 보여준다.

## list 워크플로

`.pipelines/nodes/*.yaml`을 읽어 이름, kind, 한 줄 설명, 입출력 필드 요약을 표로 보고한다. 파일을 생성·수정하지 않는다.

## 참조 파일

| 파일 | 읽는 시점 |
|---|---|
| `references/node-schema.md` | 노드 YAML 작성·검증 |
| `references/run-kinds.md` | kind별 run 섹션 작성과 test 실행 |

## 안전 경계

- 쓰기는 `.pipelines/**` 안으로 제한한다.
- `test`는 노드에 선언된 명령을 실제 실행한다 — 실행 전 명령 전문을 사용자에게 보여주고 확인 없이는 실행하지 않는다.
- llm 노드 test의 서브에이전트 brief는 자기완결적으로 작성하고 중첩 Agent 호출을 하지 않는다고 명시한다. 민감 정보는 brief에 넣지 않는다.
