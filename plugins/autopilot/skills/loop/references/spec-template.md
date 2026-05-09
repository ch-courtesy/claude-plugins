---
scope:
  include:
    - src/**
    - tests/**
  exclude:
    - rules/**
    - .loops/**
    - CLAUDE.md
verify: "<실행 가능한 명령. 예: pnpm test --filter=feature-x. 0 exit이면 검증 통과>"
# test_paths (선택): 테스트 약화 게이트가 추적할 경로/파일명 패턴 (git pathspec).
#   미지정 시 기본 컨벤션(tests/·test/·__tests__/·spec/·src/test/ 디렉토리 +
#   *.test.{js,ts,jsx,tsx,py}·*.spec.{js,ts,rb}·*_test.{go,py,rb}·test_*.py·*_spec.rb)
#   비표준 컨벤션·언어(예: C++ *.t.cpp, Elixir test/) 시 명시.
# test_paths:
#   - "custom/test/**"
#   - "**/*.t.cpp"
---

# {{task_title}}

## 무엇을 만들 것인가
{{task_description}}

## 수용 기준
{{acceptance_criteria}}

## 범위
포함:
{{scope_in}}

비-목표 / 제외:
{{scope_out}}

## 검증
이 명령이 0 exit으로 끝나야 합니다:
{{verify_command}}

## 제약 (있을 때만)
환경·도구·호환성·성능 등 알려진 제약. 워커가 이를 모르면 잘못된 가정으로 시간 낭비.
{{constraints}}

## 위험 (있을 때만)
이미 알려진 dead-end·함정·금지 영역. 워커의 NOTES.md "실패한 접근"의 사전 시드.
{{risks}}
