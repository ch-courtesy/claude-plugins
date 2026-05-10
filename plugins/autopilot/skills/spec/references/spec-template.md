---
scope:
  include: {{scope_include}}
  exclude:
    - rules/**
    - .loops/**
    - CLAUDE.md
verify: "{{verify_command}}"
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
<!-- WHAT/HOW 방어선: 이 섹션은 *무엇을* 만드는지만 적습니다. 기술 스택·파일 경로·라이브러리·클래스명 등 구현 결정은 "제약" 섹션으로 옮기세요. loop이 자율적으로 접근법을 조정할 수 있도록 의도를 기술-중립적으로. -->
{{task_description}}

## 수용 기준 (EARS)
<!-- 5개 EARS 패턴 중 하나로 작성. 자세한 사례는 references/ears-patterns.md 참조.
  - Ubiquitous: "The system shall <응답>"
  - Event-driven: "When <트리거>, the system shall <응답>"
  - State-driven: "While <상태>, the system shall <지속 응답>"
  - Optional: "Where <조건>, the system shall <응답>"
  - Unwanted: "If <불가용/오류>, then the system shall <복구·거부>"
각 기준이 verify 명령 안에서 *어떤 형태로든* fail 가능해야 합니다 (Independent-Test 규칙). 불가능한 기준은 [NEEDS CLARIFICATION: <질문>]으로 표시. -->
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
<!-- 환경·도구·호환성·성능 등 알려진 제약. 워커가 이를 모르면 잘못된 가정으로 시간 낭비.
  WHAT/HOW 방어선 결과 "무엇을 만들 것인가"에서 빠진 기술 스택·라이브러리·테스트 스타일 가이드도 여기에. -->
{{constraints}}

## 위험 (있을 때만)
<!-- 이미 알려진 dead-end·함정·금지 영역. 워커의 NOTES.md "실패한 접근"의 사전 시드. -->
{{risks}}
