---
name: engineering-rule-creator
description: 엔지니어링 지침을 `rules/engineering/`에 생성·갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 엔지니어링 지침을 새로 만들고 싶어 할 때.
---

# engineering-rule-creator

같은 디렉토리의 `engineering/` 내용을 `rules/engineering/`에 복사합니다. 사용자가 원하면 일부 파일만 선택 복사할 수 있습니다 (예: GitHub workflow 또는 로컬 에이전트 중 한 모드의 내용).

`rules/engineering/` 디렉토리가 없으면 함께 생성합니다. 이미 존재하는 파일은 덮어쓰지 않고 사용자에게 확인합니다.
