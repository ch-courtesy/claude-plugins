---
scope:
  include:
    - .github/workflows/claude-review.yml
    - .github/workflows/codex-review.yml
    - tests/claude/test-claude-review-workflow.sh
    - tests/codex/test-codex-review-workflow.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# GitHub review workflow inline thread auto-resolve 봇 login 매칭 수정

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
PR 리뷰 워크플로는 최신 verdict가 approve일 때, 자신이 과거에 단 inline review thread를 자동으로 resolved 상태로 전환하려 한다. 그러나 self thread 식별이 GitHub GraphQL API가 반환하는 봇 작성자 login 형식과 어긋나, 식별이 항상 실패하고 어떤 thread도 resolve되지 않는다. 또한 resolve가 "소스 라인이 outdated인 thread"로만 제한되어, 최신 approve로 supersede된 유효 thread가 남는다.

이 두 가지를 고쳐, verdict가 approve일 때 워크플로가 자신이 단 미해결 inline thread를 안정적으로 resolve하도록 한다. self thread 식별은 워크플로가 코멘트 본문에 심는 self-식별 마커를 1차 기준으로 삼고, 작성자 봇 식별은 GraphQL이 돌려주는 login 형식과 어긋나지 않아야 한다. REST API 기반 봇 식별 경로(기존 리뷰 멱등성·이전 리뷰 dismiss)는 동작을 그대로 유지한다. 동일 동작을 두 리뷰 워크플로 모두에 적용하고, 회귀를 막는 테스트 가드를 둔다.

## 수용 기준 (EARS)
<!-- EARS 5패턴과 언어 규칙은 references/ears-patterns.md. 각 기준은 관찰 가능하고 독립 검증 가능해야 함. -->
1. When 최신 verdict가 approve이고 봇이 작성한 inline review thread가 미해결(unresolved) 상태이며 self-식별 마커를 포함할 때, 시스템은 그 thread를 resolved 상태로 전환해야 한다.
2. While 위 조건이 성립하는 thread를 식별하는 동안, 시스템은 thread의 outdated 여부와 무관하게 그 thread를 resolve 대상으로 삼아야 한다.
3. If GraphQL API가 봇 작성자의 login을 REST 형식(접미사 `[bot]` 포함)과 다른 형식으로 반환하더라도, 시스템은 해당 thread를 자신이 작성한 thread로 식별해야 한다.
4. 시스템은 REST API 기반 봇 식별 경로(기존 리뷰 멱등성 검사, 이전 CHANGES_REQUESTED 리뷰 dismiss)의 봇 식별 동작을 변경 없이 유지해야 한다.
5. 시스템은 Claude·Codex 두 리뷰 워크플로에서 동일한 self inline thread resolve 동작을 제공해야 한다.
6. 시스템은 두 워크플로 테스트 스위트에, self-thread 식별이 GraphQL이 반환하는 봇 login 형식과 어긋나면 실패하는 회귀 가드를 포함해야 하며, resolve 동작이 thread의 outdated 여부에 의존하도록 강제하는 단언을 두지 않아야 한다.

## 범위
포함:
- 두 리뷰 워크플로의 self inline thread resolve 필터 — 작성자 봇 식별과 outdated 게이트 로직
- 두 워크플로 테스트의 auto-resolve 체크 블록

비-목표 / 제외:
- resolve 전체를 가두는 verdict=approve 게이트(verdictIsApprove) 자체의 변경
- REST 비교 경로에서 쓰는 봇 login 상수의 REST 형식 값 변경
- inline 코멘트 게시 로직·self-식별 마커 문자열 변경
- resolveReviewThread 외의 thread lifecycle(재-open 등) 추가

## 검증
<!-- 검증 기준의 단일 출처는 위 "수용 기준 (EARS)"다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **수용 기준 (EARS)**이다. 각 기준이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- REST 비교(기존 리뷰 멱등성, 이전 리뷰 dismiss)에서 쓰는 봇 login 상수의 REST 형식 값은 바꾸지 않는다 — 그 경로에서는 REST 형식이 정확하다.
- self inline thread 식별은 코멘트 본문에 심은 self-식별 마커를 1차 식별자로 유지한다.
- 두 워크플로에 동일하게 적용한다.

## 위험 (있을 때만)
- GraphQL이 향후 봇 login 형식을 다시 바꿀 위험 — self-식별 마커를 1차 식별자로 유지하고 봇 login 비교를 형식 차이에 강인하게 처리하여 완화한다(구체 방식은 구현 결정).
- outdated 게이트 완화로 verdict=approve 시점에 아직 유효한 self thread까지 resolve될 가능성 — resolve 경로는 현재 라운드 inline finding이 0건인 approve에서만 진입하므로 현재 라운드 thread 오해소 위험은 없고, 과거 thread는 최신 approve가 supersede한다는 기존 dismiss-on-approve 의미와 일치한다.
