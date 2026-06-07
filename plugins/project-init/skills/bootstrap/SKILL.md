---
name: bootstrap
description: 새 프로젝트를 시작할 때 공통 AGENTS.md와 선택한 벤더 골격을 설정합니다. 사용자가 새 프로젝트 준비를 요청하거나 공통 지침·벤더 골격이 누락된 프로젝트에서 활성화됩니다. 카테고리 지침 생성은 형제 `*-rule-creator`에 위임합니다.
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - Skill
  - Glob
  - Bash(ls:*)
  - Bash(mkdir:*)
  - Bash(diff:*)
  - Bash(git diff:*)
---

# bootstrap

공통 `AGENTS.md`, 사용자가 선택한 벤더 골격, 선택한 `rules/` 카테고리를 설치합니다.

## 진행 순서

1. **루트와 기존 파일 확인.** 프로젝트 루트에서 `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `.codex/config.toml`, `rules/` 존재 여부를 확인합니다. 기존 파일은 절대 덮어쓰지 않습니다.

2. **벤더 선택 필수 질문.** 정확히 하나의 구조화된 사용자 질문 기능의 multiSelect 질문으로 설치할 벤더 골격을 묻습니다.
   - `Claude Code (Recommended)`
   - `Codex (Recommended)`
   - 두 벤더를 모두 선택하는 구성을 권장하지만, **최소 1개**만 선택하면 유효합니다.
   - 무선택이면 어떤 파일도 생성·변경하지 않고 같은 질문을 다시 제시합니다. 최대 **3회** 연속 무선택이면 아무 파일도 생성·변경하지 않은 채 bootstrap을 중단합니다.

3. **공통 선택 블록 질문.** 루트에 `AGENTS.md`가 없어 새로 생성할 때만, 카파시 코딩 룰과 사용자 상호작용 규칙 포함 여부를 정확히 하나의 구조화된 사용자 질문 기능의 multiSelect 질문으로 묻습니다. 둘 다 `(Recommended)`로 제시하며 선택하지 않은 블록은 생성물에 포함하지 않습니다.

4. **공통 `AGENTS.md` 생성.** `AGENTS.md`가 없을 때만 `../../shared/bootstrap/`의 단일 출처를 조립해 생성합니다.
   - 베이스: `../../shared/bootstrap/AGENTS.md`
   - 선택 자산: `../../shared/bootstrap/assets/karpathy-rules.ko.md`, `../../shared/bootstrap/assets/interaction-rules.ko.md`
   - 순서: `[카파시 룰(선택 시)] → [사용자 상호작용 규칙(선택 시)] → [카테고리별 지침]`
   - 각 블록은 형제 H1으로 시작하며 네트워크 접근 없이 동봉 자산만 사용합니다.

5. **선택 벤더 골격 생성.** 선택한 벤더의 누락 파일만 `../../shared/bootstrap/vendors/`에서 복사합니다.
   - Claude Code: `CLAUDE.md`, `.claude/settings.json`
   - Codex: `.codex/config.toml`
   - 기존 설정 파일은 내용과 무관하게 보존합니다.
   - 기존 `CLAUDE.md`에 `@AGENTS.md`가 없으면, 기존 내용을 보존한 import 추가 diff를 보여주고 승인받은 경우에만 `@AGENTS.md`를 첫 줄에 추가하고 빈 줄 뒤에 기존 내용을 보존합니다. 거부하면 수정하지 않고 요약에 경고합니다.
   - 선택하지 않은 벤더의 기존 파일은 수정하거나 삭제하지 않습니다.

6. **카테고리 선택.** 부모 `skills/`에서 `*-rule-creator/`만 열거해 접미사를 제거합니다. 후보를 일반 메시지로 한 번 출력한 다음 구조화된 사용자 질문 기능으로 전체 생성, 일부 선택, 아무것도 생성하지 않음 중 하나를 받습니다. 일부 선택 multiSelect는 질문당 최대 4개입니다.

7. **생성기 호출과 요약.** 선택된 형제 생성기만 호출하고, 생성·보존·승인 거절로 생략된 파일을 구분해 요약합니다.

## 규칙

- 이 오케스트레이터가 직접 만드는 파일은 `AGENTS.md`와 선택한 벤더의 누락 골격뿐입니다. `rules/<category>.md`는 각 생성기가 책임집니다.
- 공통 지침과 생성 자산의 단일 출처는 `../../shared/bootstrap/`입니다.
- 벤더 골격에는 Hook·모델·권한·MCP 기본값을 넣지 않습니다.
- `git init`, 의존성 설치, 패키지 매니저 실행을 하지 않습니다.
