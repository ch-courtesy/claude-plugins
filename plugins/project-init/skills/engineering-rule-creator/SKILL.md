---
name: engineering-rule-creator
description: 엔지니어링 지침과 에이전트 정의 템플릿을 프로젝트에 설치할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 엔지니어링 지침을 새로 만들고 싶어 할 때.
---

# engineering-rule-creator

같은 디렉토리의 템플릿을 프로젝트의 해당 위치로 복사합니다.

## 복사 매핑

| 스킬 내 위치 | 복사 대상 | 모드 |
|---|---|---|
| `engineering/agents.md` | `rules/engineering/agents.md` | 항상 |
| `agents/work-agent.md` | `.claude/agents/work-agent.md` | 항상 |
| `agents/verifier.md` | `.claude/agents/verifier.md` | Mode B 선택 시만 |
| `workflows/verify.yml` | `.github/workflows/verify.yml` | Mode A 선택 시만 |

Mode A = `anthropics/claude-code-action@v1` workflow (PR 이벤트 자동 트리거).
Mode B = 로컬 서브에이전트 (작업 에이전트가 Task 도구로 호출).

## 절차

1. **모드 확인**: 사용자에게 검증 에이전트 구현 모드(A 또는 B)를 명시하도록 묻습니다. default 없음, PR 단위 override 불가.
2. **복사**: 위 표대로 모드에 해당하는 파일을 복사합니다.
   - 대상 디렉토리(`rules/engineering/`, `.claude/agents/`, `.github/workflows/`)가 없으면 함께 생성.
   - 이미 존재하는 파일은 덮어쓰지 않고 diff를 보여 사용자에게 확인.
3. **후속 안내**:
   - Mode A 선택 시: `ANTHROPIC_API_KEY` GitHub secret 설정 필요. 안내 메시지로 알림.
   - Mode B 선택 시: 작업 에이전트가 PR 생성 후 `Task` 도구로 verifier를 호출하는 흐름이라는 안내.
4. **검증**: 복사 후 `rules/engineering/agents.md`가 프로젝트에 존재하는지 확인. 사용자에게 본문 검토를 권합니다 — 이 파일이 협업 모델의 단일 출처입니다.
