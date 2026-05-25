---
scope:
  include: ["plugins/autopilot/skills/spec/SKILL.md", "plugins/autopilot/skills/spec/references/clarification.md", "plugins/autopilot/skills/spec/references/pre-clarification.md"]
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
verify: "bash plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh && test -f plugins/autopilot/skills/spec/references/clarification.md && grep -q references/clarification.md plugins/autopilot/skills/spec/SKILL.md && grep -Eqi 'relentless|집요|결정 트리|decision tree' plugins/autopilot/skills/spec/references/clarification.md && grep -Eqi '코드 탐색|codebase' plugins/autopilot/skills/spec/references/clarification.md && grep -Eqi '추천|recommend' plugins/autopilot/skills/spec/references/clarification.md && grep -q references/clarification.md plugins/autopilot/skills/spec/references/pre-clarification.md"
# test_sweep_paths: reviewed-no-sweep
# test_paths: optional git pathspec override for weakening gate.
# ears_language: optional "ko" | "en" | "hybrid"; default "ko".
# request_review: true enables review-fix auto loop after PR create/reuse. Use --no-pr to skip PR phase.
request_review: true
---

# Spec adaptive clarification round and clarification module

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
autopilot:spec의 명확화 라운드를, 고정된 평면 질문 목록(목적·성공기준·제약·위험)에서 **결정 트리를 따라 내려가는 적응적 인터뷰**로 격상한다. 인터뷰는 네 원칙을 따른다:

1. **집요함(relentless)** — 공유 이해에 도달할 때까지 캐묻되, "충분" 종결 조건을 둔다.
2. **결정 트리(decision-tree)** — 결정 간 의존성을 따라 한 가지씩 해소하고, 선행 답이 후속 질문을 가지치기한다.
3. **추천 답(recommended-answer)** — 매 질문에 추천 답과 한 줄 근거를 함께 제시한다.
4. **코드 우선(codebase-first)** — 코드 탐색으로 답할 수 있는 질문은 사용자에게 묻지 않고 직접 탐색해 해소한다.

이 방법론을 **단일 참조 모듈**로 분리해, 명확화 라운드와 그 메커니즘을 재사용하는 다른 지점들이 한 출처를 가리키게 한다. 전달 매체는 기존 구조화 질문 규율을 그대로 유지한다(자유 텍스트 질문 도입 금지).

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 verify에서 fail 가능해야 함. -->
- 시스템은 명확화 라운드 방법론을 단일 참조 모듈로 제공해야 한다 — 그 모듈은 집요함·결정 트리·추천 답·코드 우선 네 원칙을 모두 명시한다.
- 명확화 라운드 지침과, 그 메커니즘을 재사용하는 재진입 지점들은 이 단일 방법론 모듈을 참조해야 한다 — 방법론이 한 곳에만 존재한다.
- When 한 명확화 질문이 코드 탐색만으로 답할 수 있을 때, 시스템은 사용자에게 묻지 않고 코드 탐색으로 답을 확보해야 한다.
- 시스템은 각 명확화 질문을 제시할 때 추천 답과 한 줄 근거를 구조화 질문의 첫 선택지로 포함해야 한다.
- 시스템은 결정 간 의존성을 따라 한 번에 한 질문으로 진행하며, 선행 답에 따라 후속 질문을 조정해야 한다.
- If 결정·선택·승인을 사용자에게 요청해야 할 때, 시스템은 자유 텍스트 질문 종결구 대신 구조화 질문 도구를 사용해야 한다.

## 범위
포함:
- 명확화 라운드 지침 본문을 적응적 인터뷰 + 네 원칙으로 개정
- 명확화 방법론 단일 참조 모듈 신설
- 명확화 메커니즘을 재사용하는 재진입 지점들이 새 모듈을 참조하도록 연결
- 변경된 모듈 구성을 references 표에 반영

비-목표 / 제외:
- 도메인 glossary·ADR 같은 별도 문서 체계 도입(grill-with-docs 식 확장)
- 구조화 질문 도구를 자유 텍스트 질문으로 대체
- 명확화 라운드 외 다른 워크플로 단계의 동작 변경
- loop·dispatch·prd 등 형제 스킬 변경

## 검증
이 명령이 0 exit으로 끝나야 합니다:
bash plugins/autopilot/skills/spec/references/test-spec-loop-contract.sh && test -f plugins/autopilot/skills/spec/references/clarification.md && grep -q references/clarification.md plugins/autopilot/skills/spec/SKILL.md && grep -Eqi 'relentless|집요|결정 트리|decision tree' plugins/autopilot/skills/spec/references/clarification.md && grep -Eqi '코드 탐색|codebase' plugins/autopilot/skills/spec/references/clarification.md && grep -Eqi '추천|recommend' plugins/autopilot/skills/spec/references/clarification.md && grep -q references/clarification.md plugins/autopilot/skills/spec/references/pre-clarification.md

위 정적 게이트와 별개로, 동작 검증은 writing-skills의 RED→GREEN 방법론을 따른다: 변경 전 baseline(개정 없이 명확화를 시키면 평면 질문에 그침)을 subagent로 관찰(RED)하고, 개정 후 같은 시나리오에서 결정 트리·코드 우선·추천 답이 나타나는지(GREEN) 확인한다. 이 행동 테스트는 구현 워커가 수행하며, 정적 게이트가 loop 통과 조건이다.

## 제약 (있을 때만)
- 모든 결정·선택·승인은 구조화 질문 도구로 한다. 자유 텍스트 질문 종결구 금지(CLAUDE.md 규칙).
- grill-me의 방법론(네 원칙)만 흡수하고 전달 매체는 기존 구조화 질문 규율을 유지한다.
- self-referential 변경이다 — 이 contract를 도입하는 현재/직후 spec 호출의 산출물에 새 동작을 선행 적용하지 않고, 변경이 기본 브랜치에 반영된 다음 호출부터 적용한다.
- 스킬 description은 "트리거 조건만, 워크플로 요약 금지" 규칙을 유지한다.
- 자체 검증은 verify 0 exit + 정적 grep으로 하며, 변경 대상 스킬을 구동해 runtime 산출물을 직접 검사하지 않는다(self-referential 검증 가드).

## 위험 (있을 때만)
- over-grilling: 명확화가 과도하게 길어져 사용자 피로 → "충분" 종결 조건과 한 번에 한 질문 규율로 완화.
- 역할 중복: 코드 우선 원칙이 기존 컨텍스트 탐색 단계와 혼선 → 모듈에서 두 지점의 역할 경계를 명시.
- self-referential 오적용: 현재 호출이 새 규칙을 자기 산출물에 선행 적용 → 현재 호출 면제를 명문화.
