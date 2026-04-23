---
name: bash-rule-creator
description: 현재 프로젝트에 맞는 bash/셸 지침을 `rules/bash.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 셸 지침을 새로 만들고 싶어 하는 의도를 보일 때.
---

# bash-rule-creator

현재 프로젝트에 맞는 bash/셸 지침 문서를 `rules/bash.md`에 생성·갱신합니다.

## 생성 절차

1. **프로젝트 스캔** — 셸 사용 맥락을 파악합니다.
   - `package.json`의 `scripts`, `Makefile`, `scripts/`·`bin/` 디렉토리, shebang 기반 실행 파일.
   - 언어·런타임 힌트: `.nvmrc`, `.python-version`, `pyproject.toml`, `Gemfile`, `go.mod` 등.
2. **내용 구성**
   - 같은 디렉토리의 `bash.md` 전체를 기본 내용으로 사용합니다.
   - 스캔 결과 기반으로 "## 이 프로젝트의 세부 지침" 섹션을 본문 맨 아래에 추가합니다(해당 사항 없으면 생략).
3. **파일 기록**
   - 대상: `rules/bash.md`
   - 상위 디렉토리(`rules/`)가 없으면 함께 생성합니다.
   - 이미 존재하면 덮어쓰지 않습니다. diff를 보여주고 사용자에게 확인합니다.
