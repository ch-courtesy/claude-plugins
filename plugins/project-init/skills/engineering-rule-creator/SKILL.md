---
name: engineering-rule-creator
description: 엔지니어링 지침과 에이전트 정의 템플릿을 프로젝트에 설치할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 엔지니어링 지침을 새로 만들고 싶어 할 때.
---

# engineering-rule-creator

같은 디렉토리의 `templates/`에 있는 엔지니어링 지침 본문과, 부수적으로 동봉된 에이전트·워크플로우 정의 템플릿을 프로젝트의 해당 위치로 복사합니다.

검증 에이전트의 **백엔드** 두 가지 — GitHub Workflow(claude-code-action) 또는 로컬 서브에이전트(Claude Code Task 도구) — 중 하나를 사용자가 선택합니다.

## 생성 절차

1. **백엔드 확인.** `AskUserQuestion`(single-select)으로 검증 에이전트 백엔드를 묻습니다.
   - GitHub Workflow 백엔드 — `anthropics/claude-code-action`이 PR 이벤트로 자동 트리거.
   - 로컬 서브에이전트 백엔드 — 작업 에이전트가 `Task` 도구로 `verifier` 서브에이전트 호출.

   default 없음. 백엔드는 프로젝트 단위로만 전환하며 PR 단위 override는 허용하지 않습니다.

2. **지침 본문 복사.** `templates/agents.md` 전체를 `rules/engineering/agents.md`로 복사합니다. 상위 디렉토리(`rules/engineering/`)가 없으면 함께 생성합니다.

3. **에이전트 정의 복사.** 백엔드 무관 + 백엔드 의존 파일을 복사합니다.

   | 스킬 내 위치 | 복사 대상 | 조건 |
   |---|---|---|
   | `agents/work-agent.md` | `.claude/agents/work-agent.md` | 항상 |
   | `agents/verifier.md` | `.claude/agents/verifier.md` | 로컬 서브에이전트 백엔드 선택 시 |
   | `workflows/verify.yml` | `.github/workflows/verify.yml` | GitHub Workflow 백엔드 선택 시 |

   상위 디렉토리(`.claude/agents/`, `.github/workflows/`)가 없으면 함께 생성합니다.

4. **후속 안내.**
   - GitHub Workflow 백엔드 선택 시: `ANTHROPIC_API_KEY` GitHub secret 설정이 필요함을 사용자에게 알립니다.
   - 로컬 서브에이전트 백엔드 선택 시: 작업 에이전트가 PR 생성 후 `Task` 도구로 verifier를 호출하는 흐름임을 사용자에게 알립니다.

5. **검증.** `rules/engineering/agents.md`가 프로젝트에 존재하는지 확인하고, 사용자에게 본문 검토를 권합니다 — 이 파일이 협업 모델의 단일 출처입니다.

## 규칙

- 템플릿 본문·정의는 **그대로 복사**합니다. SKILL.md가 본문 내용을 알 필요가 없습니다.
- 이미 존재하는 파일은 **덮어쓰지 않고** diff를 보여 사용자에게 확인합니다. 단순 재실행으로 백엔드를 바꾸지 않습니다.
- 사용자의 명시적 요청이 있을 때만 기존 파일 덮어쓰기를 검토합니다.
- 백엔드별로 필요하지 않은 정의 파일은 복사하지 않습니다 (예: GitHub Workflow 백엔드를 선택하면 `.claude/agents/verifier.md`는 복사 안 함).
