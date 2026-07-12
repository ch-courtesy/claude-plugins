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

`templates/*.md` 중 하나를 `rules/workspace/<sub>.md`로 기록하는 **작업공간 위생 카테고리의 sub-룰 디스패처**입니다. 형제 스킬(`engineering-rule-creator`)과 동형으로, 같은 작업공간 카테고리 아래 여러 sub-룰(임시 파일·빌드 산출물·스크래치 데이터 등 — 후속 task에서 확장)을 호출마다 하나씩 디렉터리 구조로 누적하고, 확장은 `templates/` 아래 파일 추가만으로 합니다(이 SKILL.md 무변경).

본 스킬이 만드는 것은 작업공간 위생 sub-룰뿐입니다. 빌드 시스템·릴리스 산출물 위치(engineering)나 태스크 기록(context)의 기존 지침은 건드리지 않습니다.

## 생성 절차

절차(열거·파싱·선택·입력·기록)와 공통 규칙은 공유 프로토콜 문서 `../../shared/rule-creator/protocol.md`가 단일 출처입니다. 절차 시작 직전에 그 문서를 읽고 따르되, 아래 고유 사항을 대입합니다. 고정 스크립트(`scan_templates.py`·`list_target_dirs.py`·`render_rule.py`)는 그 문서 옆 `../../shared/rule-creator/`에 있습니다.

- **대상 디렉터리**: `rules/workspace/` — 산출 파일은 `rules/workspace/<sub>.md`.
- **빈 목록 문구**: `render: bullet_list` 항목 0개의 대체 문구는 `(대상 없음 — 검토 필요)`이며, 프로토콜 5단계에서 `render_rule.py`의 두 번째 인자로 전달합니다.
- **정적 입력 계약**: 프로토콜 4단계 대신 아래 **메뉴-우선 계약**을 적용합니다.

### 정적 입력 — 메뉴-우선 계약

`inputs`가 있으면 정의된 순서대로 입력 메뉴를 **먼저 제시**합니다. 메뉴 제시와 기본값 적용은 별개 단계이며, 질문을 건너뛰고 곧바로 기본값·placeholder로 진행하지 않습니다.

- **메뉴 제시(항상).** 각 입력은 현재 런타임의 구조화된 사용자 질문 기능으로 묻습니다. 템플릿의 `options`(추천 옵션은 `(Recommended)`를 붙여 맨 앞)와 함께 임의 경로를 직접 적을 수 있는 자유 입력 "Other"를 포함합니다. 예로 `temp-files`의 `temp_path` 입력은 추천 `.tmp/`를 첫 선택지로, `.scratch/`, 자유 입력 "Other"를 반드시 제시합니다.
- **값 사용.** 응답은 `value` 또는 `label`을 사용하고, 비어 있지 않은 "Other"(임의 경로 직접 입력 포함)도 허용합니다.
- **기본값·placeholder 적용(무응답·거절에 한해).** 사용자가 제시된 질문에 응답을 비우거나 거절한 **경우에만** 치환합니다 — 질문을 제시하지 않고 기본값을 적용하지 않습니다. (placeholder 토큰 지칭 표기는 프로토콜과 같습니다.) 일반 입력은 응답 누락·빈 값이면 해당 `name` placeholder를 보존하고, `temp-files`의 `temp_path`는 응답 누락·빈 값이면 placeholder 대신 기본값 `.tmp/`로 치환합니다.
- **비대화 맥락.** 질문을 제시할 수 없는 비대화(자율 오케스트레이션) 맥락이면, 그 사실을 알리고 무응답과 동일하게 기본값 `.tmp/`(일반 입력은 해당 `name` placeholder 보존)로 진행합니다.
- **경로 정규화.** `temp_path` 입력값("Other" 자유 입력 포함)은 치환 전에 `references/normalize_path.py <path>`로 고정합니다 — 손으로 후행 슬래시를 붙이지 말고 이 스크립트를 실행해 정규화된 경로를 받습니다(예: `.scratch` → `.scratch/`). 이래야 템플릿 본문의 `temp_path` placeholder 연결 패턴이 선택한 디렉터리의 하위 경로로 바르게 결합됩니다.
