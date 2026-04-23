---
name: engineering-rule-creator
description: 현재 프로젝트에 맞는 엔지니어링 지침을 `rules/engineering.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 엔지니어링 지침을 새로 만들고 싶어 할 때.
---

# engineering-rule-creator

현재 프로젝트에 맞는 엔지니어링 지침 문서를 `rules/engineering.md`에 생성·갱신합니다.

## 생성 절차

1. **프로젝트 스캔** — 엔지니어링 맥락을 파악합니다.
   - 주요 언어·프레임워크, 린터·포매터 설정.
   - 테스트 러너와 테스트 디렉토리 구조.
   - 타입 시스템 설정(`tsconfig`, `mypy`, `pyright` 등).
2. **내용 구성**
   - 같은 디렉토리의 `engineering.md` 전체를 기본 내용으로 사용합니다.
   - 프로젝트 고유의 코드 스타일, 테스트 관례, 완료 확인 체크리스트를 "## 이 프로젝트의 세부 지침"에 추가합니다.
3. **파일 기록**
   - 대상: `rules/engineering.md`
   - 상위 디렉토리 부재 시 함께 생성.
   - 이미 존재하면 덮어쓰지 않고 diff 후 사용자에게 확인.
