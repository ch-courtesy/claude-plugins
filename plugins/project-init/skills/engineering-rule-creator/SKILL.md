---
name: engineering-rule-creator
description: 현재 프로젝트에 맞는 엔지니어링 sub-룰(릴리스 버전 규약(versioning)·SemVer/CalVer·버전업 강제·변경 기록(changelog) 등)을 `rules/engineering/<sub>.md` 파일로 생성·갱신·수정할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 "엔지니어링 규칙/지침 만들어줘", "릴리스 버전 규약 세워줘", "버전업 규칙 정해줘", "changelog 정책 잡아줘"처럼 엔지니어링 sub-룰 지침을 새로 작성하거나 갱신하고 싶어 할 때.
allowed-tools:
  - AskUserQuestion
  - Read
  - Write
  - Glob
  - Bash(ls:*)
  - Bash(mkdir -p:*)
  - Bash(diff:*)
  - Bash(git diff:*)
---

# engineering-rule-creator

`templates/*.md` 중 하나를 `rules/engineering/<sub>.md`로 기록합니다. `<sub>`는 템플릿 파일명에서 확장자를 뺀 값입니다. 선택지, 입력값, 사후 작업은 템플릿 frontmatter에서 도출합니다.

본 스킬은 **엔지니어링 카테고리의 sub-룰 디스패처**입니다. 형제 스킬(`context-rule-creator`)이 한 번의 백엔드 선택마다 컨텍스트 카테고리 디렉터리 아래 **고정된 sub-룰 한 쌍**(`rules/context/task-model.md`·`rules/context/task-ops.md`)을 함께 기록하는 것과 달리, 본 스킬은 같은 엔지니어링 카테고리 아래 여러 sub-룰(versioning·testing·linting 등 — 후속 task에서 확장)을 호출마다 하나씩 디렉터리 구조로 누적합니다.

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

3. **선택.** 후보가 하나면 자동 선택하고, 둘 이상이면 `AskUserQuestion` single-select로 묻습니다.

4. **정적 입력.** `inputs`가 있으면 순서대로 묻습니다. 값은 `value` 또는 `label`을 사용하고, 비어 있지 않은 "Other"도 허용합니다. 응답 누락·빈 값은 해당 입력 name에 대응하는 템플릿 placeholder 토큰을 그대로 보존합니다(치환은 5단계 스크립트가 처리).

4-bis. **동적 입력.** `dynamic_inputs`가 있으면 target 프로젝트 디스크에서 후보를 산출합니다.
   - `candidate_source: depth1_dirs_filtered`: 이 후보 산출 명령열은 `references/list_target_dirs.py <target_root>`로 고정합니다(target 루트 depth=1 디렉토리만, `.*`·`node_modules`·`dist`·`build`·`target` 제외, gitignore 무시). 손으로 재현하지 말고 이 스크립트의 JSON 결과를 후보로 씁니다.
   - 후보 2개 이상이면 질문합니다. 후보 1개라도 `free_input: true`이면 "Other"를 포함해 질문합니다.
   - 후보 1개 + `free_input: false`이면 자동 선택합니다.
   - 후보 0개이면 질문하지 못하므로 사용자에게 알리고 placeholder를 보존합니다.
   - `multi_select: true`이면 다중 선택을 허용합니다. `free_input: true`의 "Other" 값은 개행 또는 콤마로 나눠 합칩니다.
   - `render: bullet_list`는 각 항목을 `- \`<path>\``로 렌더링합니다. 항목 0개는 `(워치 대상 없음 — 검토 필요)`로 둡니다.
   - 응답 누락이나 빈 응답은 정적 입력과 같이 placeholder를 보존합니다.

5. **파일 기록 및 사후 작업.**
   - frontmatter 제거·placeholder 치환·미응답 보존·`bullet_list` 렌더는 결정적 치환이므로 `references/render_rule.py <template_path>`(answers JSON 은 stdin)로 고정합니다 — 손으로 치환하지 말고 이 스크립트의 출력 본문을 `rules/engineering/<sub>.md`로 기록합니다. 상위 디렉토리는 필요 시 생성합니다.
   - 기존 파일은 diff를 보여준 뒤 `덮어쓴다 (교체)` / `보존한다 (취소)`를 묻고, 명시적 교체 선택일 때만 덮어씁니다. 자유 텍스트나 침묵은 동의가 아닙니다.
   - `on_create`는 안내처럼 파일 시스템을 건드리지 않는 지시만 수행합니다. 파일·디렉토리 생성/수정 지시는 무시하고 사용자에게 알립니다.

## 규칙

- 본 스킬은 `rules/engineering/<sub>.md` 단일 파일만 생성·갱신합니다. 같은 실행에서 다른 sub-룰이나 카테고리 밖 파일을 만지지 않습니다.
- 한 번의 호출 = 한 sub-룰. 두 템플릿을 합치거나 한 번에 여러 sub-룰을 기록하지 않습니다.
- 템플릿 본문은 그대로 복사합니다. SKILL.md에 본문별 로직을 추가하지 않습니다.
- 단순 재실행으로 sub-룰 선택을 바꾸지 않습니다. 기존 파일은 사용자 명시 동의 없이는 절대 덮어쓰지 않습니다.
