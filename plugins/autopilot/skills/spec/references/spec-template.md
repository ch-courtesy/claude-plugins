---
scope:
  include: {{scope_include}}
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
{{depends_on}}
# depends_on: optional list of sibling SPEC slugs this unit depends on.
#   분해 발행(1..N)에서만 채운다. 단일 문서면 이 줄을 제거한다.
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
---

# {{task_title}}

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
{{task_description}}

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. 완료 조건의 종속 앵커일 뿐 검증 기준이 아니다 — 목적을 완료 조건(트리거·조건·응답)에 인코딩하지 않는다. 목적이 모호하면 [NEEDS CLARIFICATION: 왜 ...] 마커를 남긴다. -->
{{purpose}}

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 plugins/autopilot/shared/spec/references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
{{acceptance_criteria}}

## 범위
포함:
{{scope_in}}

비-목표 / 제외:
{{scope_out}}

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
{{constraints}}

## 위험 (있을 때만)
{{risks}}
