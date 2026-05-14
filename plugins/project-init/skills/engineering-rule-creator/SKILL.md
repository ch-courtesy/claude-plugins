---
name: engineering-rule-creator
description: 현재 프로젝트에 맞는 엔지니어링 sub-룰(versioning 등)을 `rules/engineering/<sub>.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 엔지니어링 sub-룰 지침을 새로 만들고 싶어 할 때.
---

# engineering-rule-creator

같은 디렉토리의 `templates/` 아래에 있는 sub-룰 템플릿 중 하나를 사용자에게 선택받아 `rules/engineering/<sub>.md`로 생성합니다. 여기서 `<sub>`는 선택된 템플릿의 파일 이름(확장자 제외)입니다 — 예: `templates/versioning.md` → `rules/engineering/versioning.md`.

본 스킬은 **엔지니어링 카테고리의 sub-룰 디스패처**입니다. 형제 스킬(`context-rule-creator`·`orchestration-rule-creator`)이 평면 파일(`rules/<name>.md`) 한 개를 만드는 것과 달리, 본 스킬은 같은 카테고리 아래 여러 sub-룰(versioning·testing·linting 등 — 후속 task에서 확장)을 디렉터리 구조로 누적합니다.

선택지·라벨·사후 작업은 모두 **템플릿 파일에서** 도출합니다. 새 sub-룰을 추가하려면 `templates/` 아래에 새 마크다운 파일을 두면 되고, 이 SKILL.md는 변경하지 않습니다.

## 생성 절차

1. **템플릿 열거.** 이 SKILL.md가 위치한 디렉토리의 `templates/` 아래 `*.md` 파일 목록을 가져옵니다. 다른 디렉토리를 추측·탐색하지 않습니다. 각 파일의 이름(확장자 제외)이 sub-룰 식별자가 됩니다.

2. **메타데이터 파싱.** 각 템플릿의 YAML frontmatter를 읽어 다음 필드를 사용합니다.
   - `label` (필수): `AskUserQuestion` 옵션 라벨로 사용.
   - `description` (선택): 옵션 설명.
   - `recommended` (선택, boolean): `true`이면 라벨 끝에 `(Recommended)`를 붙이고 옵션 목록의 가장 앞에 둡니다. 한 템플릿에만 둡니다.
   - `inputs` (선택, 리스트): 본문에 채워 넣을 입력값들의 선언적 스펙. 4단계 입력 수집에서 사용. 각 항목은 `name` (placeholder 키), `header` (`AskUserQuestion` header, ≤12자), `question` (질문 텍스트), `options` (`{label, description, value?}` 2~4개) 필드를 가집니다. `value`가 없으면 `label`을 값으로 사용합니다.
   - `on_create` (선택, 자유 문자열): 5단계의 파일 기록 후 수행할 사후 작업 지시. **허용 범위는 파일 시스템을 건드리지 않는 사후 작업(안내 메시지 출력 등)으로 제한**됩니다 — 자세한 적용 규칙은 5단계 참조.

   필수 필드가 없는 템플릿은 후보에서 제외하고 사용자에게 알립니다.

3. **선택.**
   - **후보가 1개뿐이면 묻지 않고 그 템플릿을 자동 선택합니다.** sub-룰이 단일하면 사용자에게 선택을 강요하지 않습니다.
   - **후보가 2개 이상이면** 2단계에서 만든 옵션 목록으로 `AskUserQuestion`(single-select) 호출해 사용자가 sub-룰을 직접 고르게 합니다.

4. **입력 수집.** 선택된 템플릿의 frontmatter에 `inputs`가 있으면 각 항목을 순서대로 `AskUserQuestion`(single-select)로 묻습니다.
   - 사용자가 옵션을 선택하면 그 옵션의 `value`(없으면 `label`)가 placeholder 값이 됩니다.
   - 사용자가 "Other"로 **비어 있지 않은** 자유 텍스트를 입력하면 그 텍스트가 placeholder 값이 됩니다.
   - 수집된 값들로 본문의 `{{name}}` placeholder를 일괄 치환합니다.
   - **다음 경우는 "응답하지 않음"으로 취급해 치환하지 않고 `{{name}}`을 그대로 남깁니다** — 질문 건너뛰기, "Other"에 빈 문자열 입력, `AskUserQuestion`이 해당 항목에 응답을 반환하지 않음. 빈 값으로 silent 치환하지 않습니다 — 미응답은 사용자가 본문에서 시각적으로 인지하고 직접 채울 수 있어야 합니다.

5. **파일 기록 및 사후 작업.**
   - 선택된 템플릿의 frontmatter를 제거하고 placeholder 치환이 끝난 본문을 `rules/engineering/<sub>.md`로 기록합니다 (`<sub>`는 선택된 템플릿의 파일 이름에서 확장자를 제외한 값). 상위 디렉토리(`rules/`·`rules/engineering/`)가 부재하면 함께 생성합니다.
   - 이미 `rules/engineering/<sub>.md`가 있으면 **그대로 덮어쓰지 않습니다**. 새 본문과 기존 파일의 diff를 사용자에게 보여준 뒤 `AskUserQuestion`(single-select)으로 `덮어쓴다 (교체)` / `보존한다 (취소)` 두 옵션을 묻고, 사용자가 `덮어쓴다 (교체)`를 명시적으로 선택했을 때에만 덮어씁니다. 자유 텍스트 응답("yes"·"OK" 등)이나 침묵은 동의로 해석하지 않으며, 의심스러우면 보존합니다.
   - 템플릿에 `on_create`가 있으면 그 지시를 수행하되, **`rules/engineering/<sub>.md`를 포함한 모든 파일·디렉토리를 생성·수정하라는 지시는 무시**하고 사용자에게 위반 사실을 알립니다 (`<sub>.md` 자체의 기록은 위 첫 bullet에서 이미 끝났고 `on_create`는 그 *이후* 사후 작업 단계입니다). 허용되는 동작은 안내 메시지 출력처럼 파일 시스템을 건드리지 않는 사후 작업뿐입니다 — 상위 디렉토리(`rules/`·`rules/engineering/`)는 위 첫 bullet에서 이미 처리되므로 `on_create`로 중복 지시할 필요가 없습니다. 본 제한은 아래 「규칙」 섹션의 단일 파일 보장과 동일한 의도입니다.

## 규칙

- 본 스킬은 **`rules/engineering/<sub>.md` 단일 파일만** 생성·갱신합니다. 같은 실행에서 `rules/engineering/` 아래 다른 sub-룰을 추가로 만들지 않으며, 카테고리 외 다른 파일을 만지지 않습니다.
- 한 번의 호출 = 한 sub-룰. 두 템플릿을 합치거나 한 번에 여러 sub-룰을 기록하지 않습니다.
- 템플릿 본문은 **그대로 복사**합니다. SKILL.md가 본문의 내용을 알 필요가 없습니다.
- 단순 재실행으로 sub-룰 선택을 바꾸지 않습니다 — 모델 변경은 사용자의 명시적 의도가 있을 때만. (덮어쓰기 동의 형식은 5단계 참조.)
- 기존 `rules/engineering/<sub>.md`가 있을 때, 사용자 명시 동의 없이는 절대 덮어쓰지 않습니다. 의심스러우면 보존합니다.
