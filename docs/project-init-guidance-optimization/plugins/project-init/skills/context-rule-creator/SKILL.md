---
name: context-rule-creator
description: 프로젝트 컨텍스트 관리 지침을 만들거나 project-init 템플릿으로 `rules/context.md`를 갱신할 때 사용합니다.
---

# context-rule-creator

`templates/*.md` 중 하나를 `rules/context.md`로 기록합니다. 선택지, 입력값, 사후 작업은 템플릿 frontmatter에서 도출합니다.

## 생성 절차

1. **템플릿 열거.** 이 파일 옆 `templates/*.md`만 읽습니다. 다른 경로를 탐색하지 않습니다.

2. **frontmatter 파싱.**
   - `label` 필수, 옵션 라벨입니다.
   - `description` 선택, 옵션 설명입니다.
   - `recommended: true` 선택, 라벨에 `(Recommended)`를 붙이고 맨 앞으로 둡니다. 하나만 허용합니다.
   - `inputs` 선택, `name`, `header`, `question`, `options[{label, description, value?}]`를 가진 placeholder 입력입니다.
   - `on_create` 선택, 파일 기록 후 수행할 지시입니다.

   필수 필드가 없는 템플릿은 후보에서 제외하고 사용자에게 알립니다.

3. **선택.** 후보가 하나면 자동 선택하고, 둘 이상이면 `AskUserQuestion` single-select로 묻습니다.

4. **입력 수집.** `inputs`가 있으면 순서대로 묻습니다. 값은 `value` 또는 `label`을 사용하고, "Other"도 허용합니다. 수집된 값만 `{{name}}`에 치환하고 누락은 보존합니다.

5. **파일 기록 및 사후 작업.**
   - 선택된 템플릿의 frontmatter를 제거하고 본문을 `rules/context.md`로 기록합니다. 상위 디렉토리는 필요 시 생성합니다.
   - 이미 `rules/context.md`가 있으면 덮어쓰지 않고 diff를 보여 사용자에게 확인합니다.
   - `on_create`가 있으면 그대로 수행합니다.

## 규칙

- 템플릿 본문은 그대로 복사합니다. SKILL.md에 본문별 로직을 추가하지 않습니다.
- 한 번에 하나의 템플릿만 기록합니다. 두 템플릿을 합치지 않습니다.
- 사용자의 명시적 요청이 있을 때만 기존 `rules/context.md` 덮어쓰기를 검토합니다. 단순 재실행으로 백엔드를 바꾸지 않습니다.
