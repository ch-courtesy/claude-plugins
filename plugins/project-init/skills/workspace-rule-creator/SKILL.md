---
name: workspace-rule-creator
description: 현재 프로젝트에 맞는 작업공간 위생 sub-룰(workspace hygiene rule — 임시 파일·temp 관리·빌드 산출물·스크래치 데이터·clean 정책 등)을 `rules/workspace/<sub>.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 작업공간 위생 sub-룰 지침을 새로 만들고 싶어 할 때 — "임시 파일 정리 규칙 만들어줘", "temp 관리 지침 세팅", "workspace 위생 규칙", "스크래치 파일 정책 정해줘", "clean 규칙 만들기" 같은 표현을 포함합니다.
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - Glob
  - Bash(ls:*)
  - Bash(mkdir -p:*)
  - Bash(diff:*)
  - Bash(git diff:*)
  - Bash(python3:*)
---

# workspace-rule-creator

`templates/*.md` 중 하나를 `rules/workspace/<sub>.md`로 기록합니다. `<sub>`는 템플릿 파일명에서 확장자를 뺀 값입니다. 선택지, 입력값, 사후 작업은 템플릿 frontmatter에서 도출합니다.

본 스킬은 **작업공간 위생 카테고리의 sub-룰 디스패처**입니다. 형제 스킬(`engineering-rule-creator`)과 동형으로, 같은 작업공간 카테고리 아래 여러 sub-룰(임시 파일·빌드 산출물·스크래치 데이터 등 — 후속 task에서 확장)을 호출마다 하나씩 디렉터리 구조로 누적합니다.

본 스킬이 만드는 것은 작업공간 위생 sub-룰뿐입니다. 빌드 시스템·릴리스 산출물 위치(engineering)나 태스크 기록(context)의 기존 지침은 건드리지 않습니다.

새 sub-룰을 추가하려면 `templates/` 아래에 새 마크다운 파일을 두면 되고, 이 SKILL.md는 변경하지 않습니다.

## 생성 절차

1. **템플릿 열거.** 이 파일 옆 `templates/*.md`만 읽습니다. 다른 경로를 탐색하지 않습니다. 파일명에서 확장자를 뺀 값이 sub-룰 ID입니다.

2. **frontmatter 파싱.** 1단계의 열거와 이 파싱은 결정적 작업이므로 `references/scan_templates.py <skill_dir>`로 고정합니다 — 손으로 재현하지 말고 이 스크립트를 실행해 정규화된 후보 JSON(`candidates`/`skipped`)을 받습니다. 각 후보는 아래 필드로 구성됩니다.
   - `label` 필수, 옵션 라벨입니다.
   - `description` 선택, 옵션 설명입니다.
   - `recommended: true` 선택, 라벨에 `(Recommended)`를 붙이고 맨 앞으로 둡니다. 하나만 허용합니다.
   - `inputs` 선택, `name`, `header`, `question`, `options[{label, description, value?}]`를 가진 정적 입력입니다.
   - `dynamic_inputs` 선택, target 디스크에서 후보를 산출하는 입력입니다. 항목은 `name`, `header`, `question`, `multi_select`, `candidate_source`, `free_input`, `render`입니다.
   - `on_create` 선택, 파일 기록 후 지시입니다. 파일 시스템 변경 지시는 5단계에서 제한합니다.

   필수 필드가 없는 템플릿은 후보에서 제외하고 사용자에게 알립니다.

3. **선택.** 후보가 하나면 자동 선택하고, 둘 이상이면 현재 런타임의 구조화된 사용자 질문 기능으로 single-select 질문을 제시합니다.

4. **정적 입력.** `inputs`가 있으면 정의된 순서대로 입력 메뉴를 **먼저 제시**합니다. 메뉴 제시와 기본값 적용은 별개 단계이며, 질문을 건너뛰고 곧바로 기본값·placeholder로 진행하지 않습니다.
   - **메뉴 제시(항상).** 각 입력은 현재 런타임의 구조화된 사용자 질문 기능으로 묻습니다. 템플릿의 `options`(추천 옵션은 `(Recommended)`를 붙여 맨 앞)와 함께 임의 경로를 직접 적을 수 있는 자유 입력 "Other"를 포함합니다. 예로 `temp-files`의 `temp_path` 입력은 추천 `.tmp/`를 첫 선택지로, `.scratch/`, 자유 입력 "Other"를 반드시 제시합니다.
   - **값 사용.** 응답은 `value` 또는 `label`을 사용하고, 비어 있지 않은 "Other"(임의 경로 직접 입력 포함)도 허용합니다.
   - **기본값·placeholder 적용(무응답·거절에 한해).** 사용자가 제시된 질문에 응답을 비우거나 거절한 **경우에만** 치환합니다 — 질문을 제시하지 않고 기본값을 적용하지 않습니다. (템플릿 본문은 이중 중괄호 표기의 placeholder 토큰을 사용하며, 이 SKILL.md 본문에서는 그 토큰을 중괄호 없이 이름으로 — 예: `name` placeholder — 지칭합니다.) 일반 입력은 응답 누락·빈 값이면 해당 `name` placeholder를 보존하고, `temp-files`의 `temp_path`는 응답 누락·빈 값이면 placeholder 대신 기본값 `.tmp/`로 치환합니다.
   - **비대화 맥락.** 질문을 제시할 수 없는 비대화(자율 오케스트레이션) 맥락이면, 그 사실을 알리고 무응답과 동일하게 기본값 `.tmp/`(일반 입력은 해당 `name` placeholder 보존)로 진행합니다.
   - **경로 정규화.** `temp_path` 입력값("Other" 자유 입력 포함)은 치환 전에 `references/normalize_path.py <path>`로 고정합니다 — 손으로 후행 슬래시를 붙이지 말고 이 스크립트를 실행해 정규화된 경로를 받습니다(예: `.scratch` → `.scratch/`). 이래야 템플릿 본문의 `temp_path` placeholder 연결 패턴이 선택한 디렉터리의 하위 경로로 바르게 결합됩니다.

4-bis. **동적 입력.** `dynamic_inputs`가 있으면 target 프로젝트 디스크에서 후보를 산출합니다.
   - `candidate_source: depth1_dirs_filtered`: target 루트 depth=1 디렉토리만 후보로 삼고 `.*`, `node_modules`, `dist`, `build`, `target`은 제외합니다. gitignore는 무시합니다.
   - 후보 2개 이상이면 질문합니다. 후보 1개라도 `free_input: true`이면 "Other"를 포함해 질문합니다.
   - 후보 1개 + `free_input: false`이면 자동 선택합니다.
   - 후보 0개이면 질문하지 못하므로 사용자에게 알리고 placeholder를 보존합니다.
   - `multi_select: true`이면 다중 선택을 허용합니다. `free_input: true`의 "Other" 값은 개행 또는 콤마로 나눠 합칩니다.
   - `render: bullet_list`는 각 항목을 `- \`<path>\``로 렌더링합니다. 항목 0개는 `(대상 없음 — 검토 필요)`로 둡니다.
   - 응답 누락이나 빈 응답은 정적 입력과 같이 placeholder를 보존합니다.

5. **파일 기록 및 사후 작업.**
   - frontmatter 제거·placeholder 치환·미응답 보존·temp_path 기본값 적용은 결정적 치환이므로 `references/render_rule.py <template_path>`(answers JSON 은 stdin)로 고정합니다 — 손으로 치환하지 말고 이 스크립트의 출력 본문을 `rules/workspace/<sub>.md`로 기록합니다. 상위 디렉토리는 필요 시 생성합니다.
   - 기존 파일은 diff를 보여준 뒤 `덮어쓴다 (교체)` / `보존한다 (취소)`를 묻고, 명시적 교체 선택일 때만 덮어씁니다. 자유 텍스트나 침묵은 동의가 아닙니다.
   - `on_create`는 안내처럼 파일 시스템을 건드리지 않는 지시만 수행합니다. 파일·디렉토리 생성/수정 지시는 무시하고 사용자에게 알립니다.

## 규칙

- 사용자에게 선택·승인·해명을 요청할 때는 현재 런타임의 구조화된 사용자 질문 기능을 우선 사용합니다. 구조화된 사용자 질문 기능을 사용할 수 없으면 동일 선택지를 간결한 직접 질문으로 제시합니다. 기능 부재 자체를 이유로 추천값을 임의로 적용하거나 무응답을 동의로 간주하지 않으며, 스킬이 별도로 정의한 명시적 누락 응답 계약은 그대로 따릅니다.

- 본 스킬은 `rules/workspace/<sub>.md` 단일 파일만 생성·갱신합니다. 같은 실행에서 다른 sub-룰이나 카테고리 밖 파일을 만지지 않습니다.
- 한 번의 호출 = 한 sub-룰. 두 템플릿을 합치거나 한 번에 여러 sub-룰을 기록하지 않습니다.
- 템플릿 본문은 그대로 복사합니다. SKILL.md에 본문별 로직을 추가하지 않습니다.
- 단순 재실행으로 sub-룰 선택을 바꾸지 않습니다. 기존 파일은 사용자 명시 동의 없이는 절대 덮어쓰지 않습니다.
