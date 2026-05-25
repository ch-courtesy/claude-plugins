---
scope:
  include: {{scope_include}}
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "{{verify_command}}"
{{test_sweep_paths}}
# test_paths: optional git pathspec override for weakening gate.
# test_sweep_paths: optional git pathspec whitelist for legitimate test rename/cleanup/delete sweep.
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
# request_review: true enables review-fix auto loop after PR create/reuse. Use --no-pr to skip PR phase.
request_review: true
---

# {{task_title}}

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
{{task_description}}

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 verify에서 fail 가능해야 함. -->
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
{{constraints}}

## 위험 (있을 때만)
{{risks}}
