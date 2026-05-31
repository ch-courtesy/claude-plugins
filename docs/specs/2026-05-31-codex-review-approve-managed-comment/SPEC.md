---
scope:
  include:
    - .github/workflows/codex-review.yml
    - tests/codex/test-codex-review-workflow.sh
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# codex-review approve 중복 managed comment 제거

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
Codex PR 리뷰 워크플로가 승인(approve) verdict를 낼 때, 봇이 같은 PR에 두 개의 "Codex PR Review" 항목을 남기는 중복을 없앤다. 현재 정식 리뷰(① — `createReview`)와 별도의 관리형 이슈 코멘트(② — `issues.createComment`)가 각각 게시되는데, 봇 토큰이 자기 승인을 못 해 ①이 COMMENT로 강등되면 ②와 겹쳐 사용자에게 중복 코멘트로 보인다. 정식 리뷰 본문과 인라인 코멘트가 이미 승인·지적을 전달하므로 관리형 이슈 코멘트(②) 채널을 완전히 없앤다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- 리뷰 워크플로가 실행되어 승인(approve) verdict를 낼 때, 봇은 정식 리뷰(① — APPROVE 또는 토큰 한계 시 COMMENT 폴백) 외에 어떤 issue-level 관리형 코멘트도 새로 만들지 않는다.
- 리뷰 워크플로가 실행되어 비승인(non-approve) verdict를 낼 때, 봇은 issue-level 관리형 코멘트를 새로 만들거나 기존 코멘트를 supersede 문구로 갱신하지 않는다.
- 항상, `.github/workflows/codex-review.yml`에는 'Post Codex review comment' 스텝과, 그 스텝이 쓰던 `issues.createComment`/`issues.updateComment` 기반 관리형 코멘트 게시·갱신 경로가 존재하지 않는다.
- 항상, 기존 'Submit Codex review verdict' 스텝의 동작(정식 리뷰 제출, 인라인 코멘트 게시, approve 시 옛 CHANGES_REQUESTED 리뷰 dismiss, 자기 인라인 thread resolve, `approval-failed` 마커 사용)은 변경되지 않는다.
- 항상, 워크플로 테스트(`tests/codex/test-codex-review-workflow.sh`)는 관리형 코멘트 스텝의 존재를 더 이상 요구하지 않고 그 부재를 검증하도록 갱신되며, 전체 테스트가 통과한다.

## 범위
포함:
- `.github/workflows/codex-review.yml`에서 'Post Codex review comment' 스텝 전체 제거
- `tests/codex/test-codex-review-workflow.sh`에서 관리형 코멘트 관련 단언(존재·게이트·supersede·inline-only 렌더 검사)을 부재 검증으로 전환하거나 제거하여 갱신된 워크플로와 정합

비-목표 / 제외:
- 'Submit Codex review verdict' 스텝의 verdict 게이팅·인라인 코멘트·dismiss·thread resolve 로직 변경
- 정식 리뷰(①) 본문 문구 변경
- GitHub App/PAT를 통한 정식 APPROVE 가능화 (별도 SPEC `codex-review github app token 정식 approve 가능화` 소관)
- `claude-review.yml`의 동등 관리형 코멘트 패턴 (별도 작업)

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 대상 파일은 `.github/workflows/codex-review.yml`과 `tests/codex/test-codex-review-workflow.sh`로 한정한다.
- `approval-failed` 마커 파일은 'Submit Codex review verdict' 스텝 내부 dismiss 로직에서 계속 사용되므로, 관리형 코멘트 스텝 제거가 그 사용을 깨뜨리지 않아야 한다.

## 위험 (있을 때만)
- 기존에 열려 있는 PR에 이미 남아 있는 과거 관리형 승인 코멘트는 더 이상 supersede 정리되지 않고 그대로 남는다. (사용자 수용됨 — 일회성·과도기 코멘트로 간주)
