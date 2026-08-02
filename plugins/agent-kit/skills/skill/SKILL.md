---
name: skill
description: "단독 호출과 파이프라인 노드 편입이 모두 가능한 typed 스킬(입출력 스키마 + 실행법)을 만들고 검증할 때 사용. 사용자가 typed 스킬 생성, 노드 생성, 스킬 테스트, typed 스킬 목록을 요청할 때 활성화."
allowed-tools:
  - AskUserQuestion
  - Agent
  - Read
  - Write(.agents/skills/**)
  - Glob
  - Grep
  - Bash(ls:*)
  - Bash(find:*)
  - Bash(mkdir -p .agents/skills/**)
  - Bash(mkdir -p .claude/skills)
  - Bash(ln:*)
  - Bash(jq:*)
  - Bash(date:*)
---

# skill

파이프라인의 부품이자 단독 스킬인 **typed 스킬**을 만들고 검증한다. typed 스킬은 frontmatter에 기계 가독 계약(kind, inputs, outputs, run)을 선언한 SKILL.md 파일이다. 사용자가 직접 호출하면 스킬로 동작하고, 파이프라인이 `skill: <이름>`으로 참조하면 노드로 동작한다 — 같은 계약 하나를 공유한다.

**벤더 중립 저장 규약**: 소스는 `.agents/skills/<이름>/SKILL.md` **단일 파일 1개**(런타임 중립 위치), Claude Code 어댑터로 `.claude/skills/<이름>` → `../../.agents/skills/<이름>` 상대 심링크를 함께 만든다. 다른 런타임은 `.agents/skills/`를 직접 읽는다.

## 호출

`skill create` / `skill test <이름> [--input '<json>']` / `skill list` — 인자가 없으면 `create`로 간주한다. 스킬 이름은 kebab-case, 같은 이름 스킬이 있으면 덮어쓰지 말고 다른 이름 또는 갱신 여부를 선택받는다.

## typed 스킬 계약

- frontmatter 스키마와 본문 골격은 `references/skill-schema.md`를 따른다.
- `kind`는 `llm | script | http | mcp` 넷 중 하나. kind별 `run` 형식은 `references/run-kinds.md`를 따른다. (`kind: pipeline`은 pipeline 스킬의 compile이 만드는 값 — 이 스킬은 생성하지 않는다.)
- `inputs`/`outputs`는 JSON Schema식 필드 선언(`type`, `required`, `default`, `description`)이 필수다. 스키마 없는 typed 스킬은 만들지 않는다.
- 본문은 frontmatter 계약에서 생성하는 실행 지시(입력 수집 → kind별 실행 → outputs 스키마 JSON 보고)다. 본문과 frontmatter가 어긋나면 frontmatter가 정본이다.

## create 워크플로

1. **인터뷰.** 스킬의 목적, kind, 입출력 필드를 현재 런타임의 구조화된 사용자 질문 기능(없으면 간결한 직접 질문)으로 한 주제씩 확정한다. 사용자가 준 정보로 충분하면 질문을 생략하고 확인만 받는다.
2. **run 정의.** kind별 형식(`references/run-kinds.md`)에 따라 실행법을 작성한다. script는 명령과 입출력 방식(stdin-json/stdout-json), http는 메서드·URL·본문 템플릿, mcp는 도구 이름·인자 매핑, llm은 프롬프트 템플릿을 정의한다.
3. **작성.** frontmatter를 확정하고 `references/skill-schema.md`의 본문 골격대로 실행 지시 본문을 생성해 `.agents/skills/<이름>/SKILL.md`로 저장한 뒤, `.claude/skills/<이름>` 상대 심링크(`ln -s ../../.agents/skills/<이름> .claude/skills/<이름>`, 디렉토리 없으면 먼저 생성)를 만든다. description에는 단독 발동 조건을 담는다.
4. **테스트 제안.** 저장 직후 `skill test <이름>` 실행 여부를 묻는다.

## test 워크플로

1. **입력 준비.** `--input` JSON이 없으면 inputs 스키마에서 필드별 모의 값을 사용자에게 받거나 default를 쓴다. required 필드가 비면 실행하지 않는다.
2. **실행.** frontmatter의 kind·run대로 실행한다:
   - `script`/`http`: 실행할 명령(또는 curl)을 사용자에게 먼저 보여주고 확인받은 뒤 셸로 실행한다.
   - `mcp`: 해당 MCP 도구를 인자 매핑대로 직접 호출한다.
   - `llm`: 프롬프트에 입력을 치환해 런타임의 서브에이전트 기능으로 격리 실행하고(없으면 메인 세션이 인라인 수행하되 출력 스키마 준수), outputs 스키마 형태의 JSON만 반환하게 한다.
3. **검증.** 출력 JSON을 outputs 스키마와 대조한다 — 누락 필드, 타입 불일치를 보고한다. 통과/실패와 실제 출력을 그대로 보여준다. 직접 호출은 스키마 검증을 하지 않으므로 파이프라인 편입 전 검증은 test가 담당한다.

## list 워크플로

`.agents/skills/*/SKILL.md` 중 frontmatter에 `kind`가 있는 typed 스킬만 골라 이름, kind, 한 줄 설명, 입출력 필드 요약을 표로 보고한다. `kind: pipeline`(컴파일된 파이프라인)도 포함해 표시한다. 파일을 생성·수정하지 않는다.

## 참조 파일

| 파일 | 읽는 시점 |
|---|---|
| `references/skill-schema.md` | typed 스킬 frontmatter·본문 작성·검증 |
| `references/run-kinds.md` | kind별 run 작성과 test 실행 |

## 안전 경계

- 쓰기는 `.agents/skills/**` 안으로 제한한다. `.claude/skills/`에는 심링크 생성만 한다.
- `test`는 스킬에 선언된 명령을 실제 실행한다 — 실행 전 명령 전문을 사용자에게 보여주고 확인 없이는 실행하지 않는다.
- kind 없는 기존 일반 스킬을 수정·삭제하지 않는다.
- llm test의 서브에이전트 brief는 자기완결적으로 작성하고 중첩 서브에이전트 호출을 하지 않는다고 명시한다. 민감 정보는 brief에 넣지 않는다.
