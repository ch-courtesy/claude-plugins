---
scope:
  include: ["plugins/autopilot/skills/spec/**"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "! grep -qE '^(verify|request_review):' plugins/autopilot/skills/spec/references/spec-template.md && ! grep -q 'test_sweep_paths' plugins/autopilot/skills/spec/references/spec-template.md && grep -q 'dispatch' plugins/autopilot/skills/spec/SKILL.md"
# test_sweep_paths: reviewed-no-sweep
# ears_language: ko
request_review: true
---

# spec: 저작 전용 경량화

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
autopilot:spec 스킬을 "의도 문서 저작 전용"으로 재정의한다. spec은 SPEC 문서(들)를 만드는 단일 책임만 갖고, 구현·구현 검증·실행은 다른 스킬에 맡긴다. 세 가지 spec-side 변경을 정의한다:

1. **구현-검증 필드 제거.** spec이 산출하는 SPEC 문서에서 구현-검증 관심사(검증 진입 명령·테스트 sweep 화이트리스트·리뷰 트리거 기본값)를 더 이상 생성하지 않는다. 검증 가능한 수용 기준(EARS AC)이 인수 바의 단일 출처가 되고, 검증 진입 명령은 SPEC이 아니라 프로젝트 규칙에서 온다고 명시한다.
2. **1..N 문서 발행.** 범위 분해 게이트가 다중 독립 서브시스템을 판정하면, spec이 한 번의 명확화 인터뷰에서 1개 또는 N개의 SPEC 문서를 발행한다. N개를 발행할 때는 단위 간 의존성 메타데이터를 함께 기록한다.
3. **추천 단일화.** 구현 스킬 추천을 문서 개수와 무관하게 항상 dispatch로 단일화한다(기존 "단일이면 loop / 다중이면 dispatch" 볼륨 분기를 제거). 볼륨 게이트는 추천을 가르지 않고 발행 문서 개수만 결정한다.

## 수용 기준 (EARS)
<!-- 각 기준은 verify에서 fail 가능해야 함. 구현 방법·파일·클래스명은 피한다. -->
- **AC1 (Ubiquitous):** 시스템은 spec이 산출하는 SPEC 문서 템플릿에 구현-검증 필드(검증 진입 명령 키·테스트 sweep 화이트리스트 키·리뷰 트리거 기본값 키)를 포함하지 않아야 한다.
- **AC2 (Ubiquitous):** 시스템은 SPEC 문서의 검증 기준을 검증 가능한 수용 기준(EARS AC)으로만 표현하고, 검증 진입 명령의 출처가 프로젝트 규칙임을 문서에 명시해야 한다.
- **AC3 (Event-driven):** 범위 분해 게이트가 다중 독립 서브시스템을 감지하면, 시스템은 한 번의 spec 호출에서 둘 이상의 SPEC 문서를 발행해야 한다.
- **AC4 (State-driven):** 둘 이상의 SPEC 문서를 발행하는 동안, 시스템은 단위 간 의존성 메타데이터를 함께 기록해야 한다.
- **AC5 (Ubiquitous):** 시스템은 구현 스킬 추천 단계에서 발행 문서 개수와 무관하게 항상 dispatch를 추천해야 한다.
- **AC6 (Unwanted behavior):** 만약 분해가 감지되지 않으면, 시스템은 정확히 하나의 SPEC 문서를 발행하고 동일하게 dispatch를 추천해야 한다.

## 범위
포함:
- spec 스킬 문서(SKILL.md)와 references(SPEC 문서 템플릿, 범위 분해 게이트, 구현 스킬 추천 단계 서술)의 spec-side 변경.
- SPEC 문서 템플릿에서 구현-검증 필드 제거.
- 분해 시 1..N SPEC 발행 워크플로의 spec-side 정의(단위 간 의존성 메타 기록 포함).
- 구현 스킬 추천을 dispatch 단일화로 변경.

비-목표 / 제외 (모두 별도 task — 의존 관계 명시):
- **[선행 의존]** loop이 검증 진입 명령을 프로젝트 규칙에서 소싱하도록 하는 변경. 이것이 없으면 AC1의 검증 필드 제거가 loop의 Runtime 게이트를 파손한다 — 본 SPEC 단독 배포 금지.
- **[소비측 의존]** dispatch가 PRD 대신 SPEC set을 수용하고 N=1 degenerate fast-path를 갖도록 하는 변경. 1..N 발행(AC3/AC4)의 소비처.
- loop의 RED→GREEN 기계적 게이트 신설.
- prd 스킬의 spec multi 모드 흡수/폐기.
- 검증 진입 명령을 선언하는 프로젝트 규칙 작성.

## 검증
이 명령이 0 exit으로 끝나야 합니다:
`! grep -qE '^(verify|request_review):' plugins/autopilot/skills/spec/references/spec-template.md && ! grep -q 'test_sweep_paths' plugins/autopilot/skills/spec/references/spec-template.md && grep -q 'dispatch' plugins/autopilot/skills/spec/SKILL.md`

## 제약 (있을 때만)
- WHAT/HOW 방어선: SPEC은 의도(검증 가능한 AC)만 싣고, 검증 진입 명령은 프로젝트 규칙에 둔다.
- self-referential 면제: 본 SPEC을 적용하는 변경은 default branch 반영 후 *다음* spec 호출부터 새 contract를 적용한다. 변경 작업 중인 현재 호출의 산출물에 새 동작을 선행 적용하지 않는다.
- 시퀀싱: AC1(검증 필드 제거)은 loop의 규칙-소싱 동반 변경이 머지된 *후에만* 배포 가능하다.

## 위험 (있을 때만)
- 검증 필드를 loop 동반 변경 전에 제거하면 loop의 Runtime 게이트가 검증 명령을 찾지 못해 파손된다 → scope-out의 선행 의존 명시 + 단독 배포 금지로 완화.
- 1..N 발행은 dispatch가 SPEC set을 수용하지 못하면 소비처가 없어 무용지물 → dispatch 동반 task에 의존.
- 분해 로직을 spec으로 이전하면 spec이 무거워진다. 컨텍스트-윈도우 fit 등 실행 성격이 섞인 분해 기준은 저작 휴리스틱으로만 적용하고, 런타임 실측은 실행 측(loop/dispatch)에 잔류시킨다.
- 설치 플러그인(0.5.6, GitHub Issue·feat 브랜치·milestones 경로)과 repo 작업본(#220 경량화)이 divergence 상태다. 본 SPEC은 #220 방향을 더 밀어붙이므로, 0.5.6 재릴리스 전까지 설치본과 어긋난다.
