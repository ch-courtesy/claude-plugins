---
scope:
  include:
    - .github/workflows/codex-review.yml
    - .github/workflows/claude-review.yml
    - .github/prompts/codex-pr-review.ko.md
    - .github/prompts/claude-pr-review.ko.md
    - .github/prompts/codex-pr-review.schema.json
    - tests/codex/test-codex-review-workflow.sh
    - tests/claude/test-claude-review-workflow.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# PR 리뷰 inline thread resolve 결정론적 fingerprint 안정화

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
Claude·Codex 두 PR 리뷰 워크플로의 self inline thread 자동 resolve가 신뢰성 없이 깨지는 두 원인을 제거한다.

(1) **fingerprint 결정론화.** 현재 finding의 fingerprint는 모델이 매 리뷰 실행마다 자유 문자열로 새로 생성한다. resolve는 이 fingerprint의 교차-실행 문자열 일치에 의존하는데, 모델이 같은 finding에 매번 동일한 문자열을 재현한다는 보장이 없어, 아직 해결되지 않은 thread가 오-resolve되거나 중복 thread가 생기거나 해결된 thread가 남는다. 이를 워크플로가 finding의 **안정 속성**(파일 경로 + 리뷰 관점 + 정규화한 제목)으로부터 fingerprint를 **결정론적으로 계산**하도록 바꿔, 같은 finding이 PR 진화(줄 이동 포함) 중에도 실행 간 동일 fingerprint를 갖게 한다. 모델의 자유 fingerprint 생성 의존을 제거한다.

(2) **마커 형식 일치.** 프롬프트는 모델에게 "기존 self thread의 마커에 fingerprint가 들어 있으니 그것을 근거로 resolved_threads를 채우라"고 안내하면서, resolve 코드가 실제 게시·매칭하는 마커 형식과 **다른 형식**의 마커를 가리킨다. 이 어긋남 때문에 모델이 기존 thread의 fingerprint를 정확히 읽어 resolved_threads에 기록하는 1차 경로가 동작하지 못한다. 프롬프트가 가리키는 self-식별 마커 형식을, 워크플로가 실제 게시하고 resolve 시 매칭하는 마커 형식과 일치시킨다.

resolve의 기존 2단 구조 — 1차(모델이 resolved_threads로 지목한 self thread) + 2차(이번 라운드 findings의 fingerprint 집합에 더 이상 없는 self thread를 fallback) — 는 그대로 유지하되, 두 경로 모두 이 결정론적 fingerprint를 기준으로 동작한다. 두 워크플로에 동일하게 적용하고 회귀 가드를 둔다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
1. 항상, 시스템은 self inline thread의 fingerprint를 finding의 파일 경로·리뷰 관점·정규화한 제목으로부터 결정론적으로 계산해야 하며, 줄 번호에는 의존하지 않아야 한다.
2. 동일한 미해결 finding이 PR 진화로 줄 위치가 바뀐 채 다시 보고될 때, 시스템은 그 finding에 직전 실행과 동일한 fingerprint를 부여해야 한다.
3. 모델이 기존 self thread 마커의 fingerprint를 resolved_threads에 기록할 때, 시스템은 그 fingerprint를 가진 미해결 self thread를 resolved 상태로 전환해야 한다.
4. self thread의 fingerprint가 이번 실행 findings의 fingerprint 집합에 더 이상 없을 때, 시스템은 그 thread를 resolved 상태로 전환해야 하고, 여전히 findings에 있는 fingerprint의 thread는 그대로 두어야 한다.
5. 항상, 프롬프트가 모델에게 기존 self thread fingerprint의 출처로 안내하는 마커 형식은, 워크플로가 실제 게시하고 resolve 시 매칭하는 마커 형식과 동일해야 한다.
6. 시스템은 Claude·Codex 두 리뷰 워크플로에서 동일한 결정론적 fingerprint 계산과 self inline thread resolve 동작을 제공해야 한다.
7. 시스템은 두 워크플로 테스트 스위트에, fingerprint 계산이 줄 번호에 의존하지 않음과 프롬프트 안내 마커 형식이 실제 매칭 마커와 일치함을 강제하는 회귀 가드를 포함해야 한다.

## 범위
포함:
- 두 워크플로의 fingerprint 산정 — 모델 자유 생성에서 워크플로 결정론 계산(파일+리뷰 관점+정규화 제목)으로 전환
- 게시 inline 코멘트 self-식별 마커가 이 결정론적 fingerprint를 운반하도록 유지
- 두 프롬프트(`codex-pr-review.ko.md`·`claude-pr-review.ko.md`)의 마커 안내를 실제 게시·매칭 마커 형식과 일치시키는 수정
- 리뷰 출력 스키마에서 fingerprint 산정 주체 전환에 따라 필요한 조정(공유 `codex-pr-review.schema.json`)
- 1차(resolved_threads) + 2차(fallback) resolve 경로를 결정론적 fingerprint 기준으로 동작시키기
- 두 워크플로 테스트의 fingerprint·마커 일치 회귀 가드

비-목표 / 제외:
- approve/토큰 관련 변경 (별도 SPEC `pr-review-approve-via-github-app-token` 소관)
- `resolveReviewThread` 외 thread lifecycle(재-open 등) 추가
- 봇 작성자 식별·이미 resolved skip·다른 리뷰어 thread 미접촉·verdict 무관 매 실행 resolve 같은 기존 resolve 동작의 변경
- 모델이 finding을 생성·표면화하는 기준(confidence_score 게이트 등)의 변경
- 레거시(결정론적 fingerprint 이전에 게시된) 마커 thread를 소급 재계산해 강제 resolve

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- fingerprint 입력은 파일 경로 + 리뷰 관점(`review_perspective`) + 정규화한 제목으로 한정하고, 줄 번호·시작줄은 포함하지 않는다.
- 제목 정규화 방식(대소문자·공백·문장부호 처리)은 두 워크플로에서 동일해야 한다.
- 게시 inline 코멘트의 기존 self-식별 마커 substring(자기 식별 보존)은 유지하고, 그 마커가 결정론적 fingerprint를 운반한다. 워크플로별 마커 prefix(claude-review-inline·codex-review-inline)는 각자 유지한다.
- resolve의 봇 작성자 식별·이미 resolved thread skip·다른 리뷰어 thread 미접촉 동작과, verdict 무관 매 실행 resolve(approve 게이트 부재)는 변경하지 않는다.
- 두 워크플로(`claude-review.yml`·`codex-review.yml`)에 동일하게 적용한다.

## 위험 (있을 때만)
- 파일+리뷰 관점+제목이 같은 서로 다른 finding이 동일 fingerprint를 받을 가능성 — 제목이 finding을 충분히 구별하므로 낮으며, 충돌 시 한 thread 단위로만 resolve가 추적되는 정도의 영향에 그친다.
- 결정론적 fingerprint 도입 이전에 게시된 thread는 새 계산식과 매칭되지 않아 레거시로 남을 수 있다 — 2차 fallback이 "현재 findings에 없음"으로 결국 resolve하거나 미접촉으로 남으며(수용), 소급 강제 resolve는 비-목표다.
