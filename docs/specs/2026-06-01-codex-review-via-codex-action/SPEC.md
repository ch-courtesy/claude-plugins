---
scope:
  include:
    - .github/workflows/codex-review.yml
    - tests/codex/test-codex-review-workflow.sh
    - docs/codex/pr-review-workflow.md
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# codex-review 워크플로를 openai/codex-action 기반으로 재작성

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
Codex PR 리뷰 워크플로의 모델 호출을 codex CLI 직접 실행에서 공식 GitHub Action 호출로 바꾸고, 리뷰 결과 게시 구조를 자매 워크플로(Claude PR 리뷰)와 동일하게 통일한다. 인증은 ChatGPT 계정 auth.json 방식을 그대로 유지한다. codex만의 독자 게시 경로(인라인 코멘트, fingerprint 기반 thread 자동 resolve, GitHub App 토큰을 통한 정식 approve)는 제거하고, Claude 리뷰와 같은 게시 방식(정식 리뷰 verdict 제출 + 마커 기반 관리형 PR 코멘트 1개)으로 대체한다. 공유 자산(리뷰 context 수집 스크립트, codex 리뷰 프롬프트, 공유 출력 스키마)과 추가 context 요청 2-pass 흐름, @codex 멘션 트리거 게이트는 보존한다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- PR 리뷰가 트리거되어 codex가 실행될 때, 모델 호출은 공식 GitHub Action(`openai/codex-action`)을 통해 이뤄지며, 워크플로에는 `npm install -g @openai/codex` 설치 스텝과 셸에서 직접 호출하는 `codex exec` 명령이 존재하지 않는다.
- codex가 실행될 때, 인증은 ChatGPT 계정 auth.json 방식을 유지한다 — `CODEX_AUTH_JSON` 시크릿이 codex home 디렉터리의 `auth.json`으로 기록되고 그 디렉터리가 action에 전달되며, `OPENAI_API_KEY`(또는 동등 API 키 입력)는 요구되지 않는다.
- `CODEX_AUTH_JSON` 시크릿이 비어 있으면, 워크플로는 인증 부재를 알리는 명확한 오류로 실패한다.
- 리뷰가 실행되어 결과를 게시할 때, 게시 구조는 Claude PR 리뷰 워크플로와 동일하다 — verdict를 정식 리뷰(approve / comment / request-changes) body로 제출하고, findings를 담은 관리형 PR 코멘트를 마커 기준으로 최대 1개만 생성하거나 갱신한다.
- 항상, 워크플로에는 인라인 리뷰 코멘트 게시 경로, fingerprint 기반 self thread 자동 resolve 경로, GitHub App 설치 토큰 발급·App 토큰을 통한 정식 approve 경로가 존재하지 않는다.
- 리뷰가 실행될 때, 모델 출력은 공유 출력 스키마(`.github/prompts/codex-pr-review.schema.json`)로 강제되고, 결과 JSON이 파일로 저장되어 유효한 JSON임이 검증된다.
- 모델이 추가 context(needs_context)를 요청하면, 요청 파일을 수집해 2차 호출로 최종 verdict를 받는 2-pass 흐름이 Claude 리뷰와 동일하게 동작한다.
- @codex 멘션으로 트리거될 때, 작성자 association 제한(OWNER/MEMBER/COLLABORATOR)과 봇 self-trigger 차단 게이트가 유지된다.
- 워크플로 contract 테스트가 새 구조를 검증하도록 갱신된다 — 공식 action 사용·auth.json codex-home 부트스트랩·Claude 동일 게시 구조의 존재를 단언하고, 인라인/fingerprint/App-approve 경로와 codex CLI 직접 호출의 부재를 단언하며, 전체 테스트가 통과한다.
- 항상, codex 리뷰 워크플로 설계 문서(`docs/codex/pr-review-workflow.md`)는 codex CLI 직접 실행이 아니라 공식 action 기반 접근과 Claude 동일 게시 구조를 반영한다.

## 범위
포함:
- `.github/workflows/codex-review.yml` 전면 재작성 — 모델 호출을 `openai/codex-action`으로, 게시 단계를 `claude-review.yml`과 동일 구조로 교체, auth.json codex-home 부트스트랩 스텝 추가.
- `tests/codex/test-codex-review-workflow.sh` 갱신 — 새 구조 단언으로 전환(공식 action·auth.json codex-home·동일 게시 구조 존재; CLI 직접 호출·인라인·fingerprint·App approve 부재).
- `docs/codex/pr-review-workflow.md` 갱신 — action 기반 접근·Claude 동일 게시 구조 반영.

비-목표 / 제외:
- `.github/prompts/codex-pr-review.ko.md`·`.github/prompts/codex-pr-review.schema.json` 내용 변경(모델 비종속 리뷰 코어·공유 스키마는 그대로).
- `.github/scripts/pr-review-context.sh` 변경(두 워크플로 공유, 벤더 무관).
- `claude-review.yml` 동작 변경.
- 기존 열린 PR에 이미 남은 codex 인라인 코멘트·resolved thread의 사후 정리.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- 공식 action 호출은 커밋 SHA로 핀하고(레포 컨벤션: 모든 GitHub Action을 SHA 핀), codex CLI 버전도 action의 버전 입력으로 핀한다.
- action 입력 매핑: 공유 스키마를 스키마 파일 입력으로, 조립된 프롬프트를 프롬프트 파일 입력으로, 샌드박스는 read-only, reasoning effort는 medium(기존 동작 동치), 결과는 출력 파일 입력으로 수신, auth.json 디렉터리는 codex-home 입력으로 전달한다.
- auth.json 부트스트랩은 `CODEX_AUTH_JSON`을 codex-home 디렉터리의 `auth.json`(권한 600)으로 기록하고, 그 시크릿 값을 모델 호출 스텝의 환경으로 노출하지 않는다.
- 게시 단계는 `claude-review.yml`의 'Submit … review verdict' + 'Post … review comment' 스텝 구조를 codex 라벨·마커로 치환해 사용한다(예: 'Codex PR Review' 헤더, codex 전용 정식 리뷰 마커·관리형 코멘트 마커).
- 자기 트리거 게이트는 @codex 멘션을 유지하되, App 봇 식별(`REVIEW_APP_BOT_LOGIN`) 분기는 제거한다(Claude 구조에 없음).
- 워크플로 권한은 게시에 필요한 범위(contents:read, pull-requests:write, issues:write)로 두며, App/OIDC 전용 권한은 두지 않는다.

## 위험 (있을 때만)
- App 토큰 approve 제거로 `github-actions[bot]`이 자기 워크플로 PR에 정식 APPROVE를 못 해 COMMENT로 강등될 수 있다(Claude 리뷰와 동일한 한계). — 사용자 수용됨.
- 기존 열린 PR에 남아 있던 codex 인라인 코멘트·자동 resolve된 thread는 새 구조에서 더 이상 관리·정리되지 않고 잔존한다(과도기). — 사용자 수용됨.
- action의 출력 파일이 스키마 강제 JSON(마지막 메시지)을 그대로 담는지는 기존 `--output-last-message`와 동치이나, 저장 직후 JSON 유효성 가드(예: jq empty)로 계약 위반을 조기 검출한다.
