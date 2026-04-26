---
name: search-rule-creator
description: 현재 프로젝트에 맞는 검색 지침을 `rules/search.md`로 생성하거나 갱신할 때 활성화됩니다. project-init 초기화 흐름 중 호출되거나, 사용자가 검색 지침을 새로 만들고 싶어 할 때.
---

# search-rule-creator

현재 프로젝트에 맞는 검색 지침 문서를 `rules/search.md`에 생성·갱신합니다.

## 생성 절차

1. **프로젝트 스캔** — 검색 맥락을 파악합니다.
   - 프로젝트 크기(파일 수, 주요 언어).
   - `.rgignore` / `.gitignore` — 검색 제외 대상 힌트.
   - 코드 생성 도구 산출물(제외 대상).
   - LSP·언어 도구 설정 여부(`tsconfig.json`, `pyrightconfig.json` 등).
2. **내용 구성**
   - 같은 디렉토리의 `search.md` 전체를 기본 내용으로 사용합니다.
   - 프로젝트 고유의 인덱스·검색 도구, 제외 패턴 등을 "## 이 프로젝트의 세부 지침"에 추가합니다.
3. **파일 기록**
   - 대상: `rules/search.md`
   - 상위 디렉토리 부재 시 함께 생성.
   - 이미 존재하면 덮어쓰지 않고 diff 후 사용자에게 확인.
