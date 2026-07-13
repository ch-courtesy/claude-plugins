---
name: engineering-rule-creator
description: 현재 프로젝트에 맞는 엔지니어링 sub-룰(릴리스 버전 규약(versioning)·SemVer/CalVer·버전업 강제 등)을 `rules/engineering/<sub>.md` 파일로 생성·갱신·수정할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 "엔지니어링 규칙/지침 만들어줘", "릴리스 버전 규약 세워줘", "버전업 규칙 정해줘"처럼 엔지니어링 sub-룰 지침을 새로 작성하거나 갱신하고 싶어 할 때.
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

# engineering-rule-creator

**엔지니어링 카테고리의 sub-룰 디스패처**입니다 — `templates/*.md` 중 하나를 `rules/engineering/<sub>.md`로 기록해 sub-룰(versioning 등 — 후속 task에서 확장)을 호출마다 하나씩 누적합니다.

## 생성 절차

생성 절차(열거·파싱·선택·입력·기록)와 공통 규칙(1 호출 = 1 sub-룰, `templates/` 파일 추가만으로 확장 등)의 단일 출처는 공유 프로토콜 문서 `../../shared/rule-creator/protocol.md`입니다. 절차를 시작하기 직전에 그 문서를 읽고 그대로 따릅니다 — 그 문서 하나로 절차가 완결되며, 고정된 결정적 스크립트(`scan_templates.py`·`list_target_dirs.py`·`render_rule.py`)도 그 문서 옆 `../../shared/rule-creator/`에 있습니다.

프로토콜에 대입할 본 스킬의 고유 사항:

- **대상 디렉터리**: `rules/engineering/` — 산출 파일은 `rules/engineering/<sub>.md`.
- **빈 목록 문구**: `render: bullet_list` 항목 0개의 대체 문구는 `(워치 대상 없음 — 검토 필요)`이며, 프로토콜 5단계에서 `render_rule.py`의 두 번째 인자로 이 문구를 전달합니다.
