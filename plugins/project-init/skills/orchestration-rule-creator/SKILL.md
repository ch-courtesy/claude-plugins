---
name: orchestration-rule-creator
description: 현재 프로젝트에 맞는 오케스트레이션(subagent 구성·위임) 지침을 `rules/orchestration.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 오케스트레이션 지침을 새로 만들고 싶어 할 때.
---

# orchestration-rule-creator

같은 디렉토리의 `templates/` 아래에 있는 템플릿 중 하나를 사용자에게 선택받아 `rules/orchestration.md`로 생성합니다.

선택지·라벨·사후 작업은 모두 **템플릿 파일에서** 도출합니다. 새 옵션을 추가하려면 `templates/` 아래에 새 마크다운 파일을 두면 되고, 이 SKILL.md는 변경하지 않습니다.

## 생성 절차

1. **템플릿 열거.** 이 SKILL.md가 위치한 디렉토리의 `templates/` 아래 `*.md` 파일 목록을 가져옵니다. 다른 디렉토리를 추측·탐색하지 않습니다.

2. **메타데이터 파싱.** 각 템플릿의 YAML frontmatter를 읽어 다음 필드를 사용합니다.
   - `label` (필수): `AskUserQuestion` 옵션 라벨로 사용.
   - `description` (선택): 옵션 설명.
   - `recommended` (선택, boolean): `true`이면 라벨 끝에 `(Recommended)`를 붙이고 옵션 목록의 가장 앞에 둡니다. 한 템플릿에만 둡니다.
   - `inputs` (선택, 리스트): 본문에 채워 넣을 입력값들의 선언적 스펙. 4단계 입력 수집에서 사용. 각 항목은 `name` (placeholder 키), `header` (`AskUserQuestion` header, ≤12자), `question` (질문 텍스트), `options` (`{label, description, value?}` 2~4개) 필드를 가집니다. `value`가 없으면 `label`을 값으로 사용합니다.
   - `on_create` (선택, 자유 문자열): 5단계의 파일 기록 후 수행할 사후 작업 지시. 자연어 명령으로 작성하며, 예: "추가 파일은 만들지 않는다", "입력에 따라 TODO 마커가 남았으면 사용자에게 직접 채울 항목을 안내한다", "관련 디렉토리·빈 파일을 함께 생성한다". 누락이거나 빈 문자열이면 후속 작업 없이 종료합니다.

   필수 필드가 없는 템플릿은 후보에서 제외하고 사용자에게 알립니다.

3. **선택.** 위에서 만든 옵션을 `AskUserQuestion`(single-select)로 사용자에게 묻습니다. 후보가 한 개뿐이면 묻지 않고 그대로 선택합니다.

4. **입력 수집.** 선택된 템플릿의 frontmatter에 `inputs`가 있으면 각 항목을 순서대로 `AskUserQuestion`(single-select)로 묻습니다.
   - 사용자가 옵션을 선택하면 그 옵션의 `value`(없으면 `label`)가 placeholder 값이 됩니다.
   - 사용자가 "Other"로 **비어 있지 않은** 자유 텍스트를 입력하면 그 텍스트가 placeholder 값이 됩니다.
   - 수집된 값들로 본문의 `{{name}}` placeholder를 일괄 치환합니다.
   - **다음 경우는 "응답하지 않음"으로 취급해 치환하지 않고 `{{name}}`을 그대로 남깁니다** — 질문 건너뛰기, "Other"에 빈 문자열 입력, `AskUserQuestion`이 해당 항목에 응답을 반환하지 않음. 빈 값으로 silent 치환하지 않습니다 — 미응답은 사용자가 본문에서 시각적으로 인지하고 직접 채울 수 있어야 합니다.

5. **파일 기록 및 사후 작업.**
   - 선택된 템플릿의 frontmatter를 제거하고 placeholder 치환이 끝난 본문을 `rules/orchestration.md`로 기록합니다. 상위 디렉토리 부재 시 함께 생성합니다.
   - 이미 `rules/orchestration.md`가 있으면 **그대로 덮어쓰지 않습니다**. 새 본문과 기존 파일의 diff를 사용자에게 보여주고, 사용자가 **명시적으로 "덮어쓴다"·"교체한다"·"yes"** 등으로 응답한 경우에만 덮어씁니다. "확인했다"·"봤다"·침묵은 동의가 아닙니다 — 의심스러우면 묻지 않고 보존합니다.
   - 템플릿에 `on_create`가 있으면 그 지시를 그대로 수행합니다 (디렉토리·빈 파일 생성, 안내 메시지 출력 등).

## 규칙

- 템플릿 본문은 **그대로 복사**합니다. SKILL.md가 본문의 내용을 알 필요가 없습니다.
- 한 번에 하나의 템플릿만 기록합니다. 두 템플릿을 합치지 않습니다.
- 단순 재실행으로 템플릿 선택을 바꾸지 않습니다 — 모델 변경은 사용자의 명시적 의도가 있을 때만. (덮어쓰기 동의 형식은 5단계 참조.)
