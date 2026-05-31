---
scope:
  include:
    - .github/workflows/codex-review.yml
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# codex-review github app token 정식 approve 가능화

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
Codex PR 리뷰 워크플로가 승인(approve) verdict를 낼 때, 봇이 PR을 **정식 APPROVE**로 제출할 수 있게 한다. 현재는 워크플로 기본 토큰(`github-actions[bot]`)이 자기 자신을 승인할 수 없어 APPROVE 시도가 422로 실패하고 COMMENT로 강등된다. 이 강등을 없애기 위해, 'Submit Codex review verdict' 스텝이 별도의 GitHub App installation 토큰으로 인증하여 정식 APPROVE 리뷰를 제출하도록 한다. App 자격이 없거나 발급/제출이 실패하는 환경에서는 기존 COMMENT 폴백 경로를 그대로 사용해 워크플로가 깨지지 않게 한다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- GitHub App 자격(앱 ID·private key 등 secret)이 설정된 상태에서 리뷰 워크플로가 approve verdict를 낼 때, 봇은 정식 APPROVE 리뷰를 제출하고 PR 리뷰 섹션에 승인으로 표시된다(코멘트로 강등되지 않는다).
- GitHub App 자격이 없는 동안, 워크플로는 실패하지 않고 기존 기본 토큰 + 'APPROVE 실패 → COMMENT 폴백' 경로로 동작한다.
- 정식 APPROVE 제출이 토큰 한계·API 오류로 실패하면(오류), 기존 COMMENT 폴백과 `approval-failed` 마커 처리가 그대로 수행된다.
- 항상, 발급된 App 토큰은 리뷰 제출(`createReview`) 등 필요한 호출에만 사용되고 secret(앱 private key·토큰)은 워크플로 로그에 노출되지 않는다.

## 범위
포함:
- `.github/workflows/codex-review.yml`에 GitHub App installation 토큰을 발급하는 단계 추가(앱 ID·private key secret 사용)
- 'Submit Codex review verdict' 스텝이 발급된 App 토큰으로 인증하여 정식 APPROVE 제출
- App 자격 미설정·발급 실패 시 기존 기본 토큰 + COMMENT 폴백 경로로의 graceful fallback

비-목표 / 제외:
- 관리형 이슈 코멘트(②) 제거 (별도 SPEC `codex-review approve 중복 managed comment 제거` 소관)
- 'APPROVE 실패 → COMMENT 폴백' 안전망 로직 자체의 제거 (유지 결정)
- Classic PAT 방식 (인증 수단은 GitHub App으로 확정)
- GitHub App의 조직/레포 설치, secret 등록 같은 레포 외부 운영 작업 (SPEC 본문에서 안내는 하되 자동화 대상 아님)
- `claude-review.yml`에의 동일 적용 (별도 작업)

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 인증 수단은 GitHub App installation 토큰을 사용한다(Classic PAT 아님).
- 기존 'APPROVE 실패 → COMMENT 폴백' 안전망 로직은 유지한다.
- App 자격 secret이 없는 환경(예: 포크에서 온 PR, secret 미설정 CI)에서도 워크플로가 실패하지 않아야 한다.

## 위험 (있을 때만)
- App private key secret이 유출되면 봇 승인 권한이 오남용될 수 있다 — App 권한 스코프를 최소(필요한 pull-request write 수준)로 제한해야 한다.
- 포크에서 온 PR은 secret에 접근할 수 없어 자동으로 폴백 경로로 떨어진다 — 이 PR들은 정식 APPROVE가 되지 않는다(수용된 동작).
