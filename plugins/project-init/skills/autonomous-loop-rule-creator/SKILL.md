---
name: autonomous-loop-rule-creator
description: 현재 프로젝트에 맞는 자율 루프(랄프) 운영 지침을 `rules/autonomous-loop.md`로 생성하고, sibling 워크트리 드라이버·PROMPT 템플릿·메모리 파일 스텁을 `.loops/` 아래에 함께 설치할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 자율 루프 지침을 새로 만들고 싶어 할 때.
---

# autonomous-loop-rule-creator

같은 디렉토리의 `templates/` 아래에 있는 템플릿 중 하나를 사용자에게 선택받아 `rules/autonomous-loop.md`로 생성하고, 템플릿의 `on_create` 지시에 따라 `assets/`의 드라이버·메모리 스텁을 대상 프로젝트의 `.loops/` 아래로 복사합니다.

선택지·라벨·사후 작업은 모두 **템플릿 파일에서** 도출합니다. 새 옵션을 추가하려면 `templates/` 아래에 새 마크다운 파일을 두면 되고, 이 SKILL.md는 변경하지 않습니다.

## 생성 절차

1. **템플릿 열거.** 이 SKILL.md가 위치한 디렉토리의 `templates/` 아래 `*.md` 파일 목록을 가져옵니다. 다른 디렉토리를 추측·탐색하지 않습니다.

2. **메타데이터 파싱.** 각 템플릿의 YAML frontmatter를 읽어 다음 필드를 사용합니다.
   - `label` (필수): `AskUserQuestion` 옵션 라벨로 사용.
   - `description` (선택): 옵션 설명.
   - `recommended` (선택, boolean): `true`이면 라벨 끝에 `(Recommended)`를 붙이고 옵션 목록의 가장 앞에 둡니다. 한 템플릿에만 둡니다.
   - `on_create` (선택, 자유 문자열): 본문 기록 후 수행할 사후 작업 지시. 자연어 명령으로 작성하며 `assets/`의 파일을 어디로 복사할지·`.gitignore` 갱신 등을 포함합니다.

   필수 필드가 없는 템플릿은 후보에서 제외하고 사용자에게 알립니다.

3. **선택.** 위에서 만든 옵션을 `AskUserQuestion`(single-select)로 사용자에게 묻습니다. 후보가 한 개뿐이면 묻지 않고 그대로 선택합니다.

4. **파일 기록.**
   - 선택된 템플릿의 frontmatter를 제거한 본문을 `rules/autonomous-loop.md`로 기록합니다. 상위 디렉토리 부재 시 함께 생성합니다.
   - 이미 `rules/autonomous-loop.md`가 있으면 **그대로 덮어쓰지 않습니다**. 새 본문과 기존 파일의 diff를 사용자에게 보여주고, 사용자가 **명시적으로 "덮어쓴다"·"교체한다"·"yes"** 등으로 응답한 경우에만 덮어씁니다.

5. **사후 작업.** 템플릿의 `on_create` 지시를 그대로 수행합니다. 일반적으로 다음을 포함합니다.
   - `assets/` 아래의 드라이버 스크립트·메모리 스텁·README 등을 대상 프로젝트의 지정 경로로 복사
   - `loop.sh`에 chmod +x
   - `.gitignore` 갱신
   - 사용자에게 워크플로 안내 메시지 출력

## 규칙

- 템플릿 본문은 **그대로 복사**합니다. SKILL.md가 본문 내용을 알 필요가 없습니다.
- 한 번에 하나의 템플릿만 기록합니다. 두 템플릿을 합치지 않습니다.
- `on_create`가 복사할 자산은 모두 같은 스킬의 `assets/` 아래에서 가져옵니다. 다른 디렉토리·다른 스킬·외부 URL을 참조하지 않습니다.
- 단순 재실행으로 템플릿 선택을 바꾸지 않습니다 — 모델 변경은 사용자의 명시적 의도가 있을 때만.
