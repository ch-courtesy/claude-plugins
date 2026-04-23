---
name: autonomous-loop-rule-creator
description: 현재 프로젝트에 맞는 자율 루프 지침을 `rules/autonomous-loop.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 자율 루프 지침을 새로 만들고 싶어 할 때.
---

# autonomous-loop-rule-creator

현재 프로젝트에 맞는 자율 루프(하네스 기반 에이전트) 지침 문서를 `rules/autonomous-loop.md`에 생성·갱신합니다.

## 생성 절차

1. **프로젝트 스캔** — 자율 루프 맥락을 파악합니다.
   - 수용 기준·명세 문서 위치(`docs/spec/`, 이슈 템플릿 등).
   - 테스트·CI 구성(`package.json` test scripts, `pytest.ini`, `.github/workflows/`).
   - 린터·품질 게이트 설정(`eslint`, `ruff`, `mypy` 등).
2. **내용 구성**
   - 같은 디렉토리의 `autonomous-loop.md` 전체를 기본 내용으로 사용합니다.
   - 프로젝트 고유의 이터레이션 상한, 에스컬레이션 채널, 평가 기준 파일 위치 등을 "## 이 프로젝트의 세부 지침"에 추가합니다.
3. **파일 기록**
   - 대상: `rules/autonomous-loop.md`
   - 상위 디렉토리 부재 시 함께 생성.
   - 이미 존재하면 덮어쓰지 않고 diff 후 사용자에게 확인.
