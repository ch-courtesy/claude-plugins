---
scope:
  include:
    - .github/workflows/claude-review.yml
    - .github/workflows/codex-review.yml
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
ears_language: ko
---

# Review workflow PR approve via GitHub App token

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

리뷰 GitHub Actions 워크플로(`claude-review.yml`, `codex-review.yml`)가 기본 `GITHUB_TOKEN`(github-actions[bot]) 대신 **GitHub App에서 발급한 설치 토큰**으로 PR을 공식 승인(APPROVE)할 수 있게 한다. 기본 토큰은 자기 워크플로가 만든 PR 리뷰를 self-approve할 수 없는 GitHub 제약(APPROVE 시 403/422)을 받기 때문에, 현재 두 워크플로는 APPROVE가 실패하면 COMMENT로만 강등(fallback)된다. 본 변경은 App 설치 토큰을 사용해 그 제약 없이 실제 APPROVE 리뷰를 제출하도록 한다.

App 토큰은 리뷰 게시 경로(공식 리뷰 제출, inline 코멘트, managed 코멘트, self inline thread resolve) **전반**에서 쓰여 게시 주체의 identity를 하나의 App 봇으로 통일한다. App 토큰을 쓸 수 없는 환경(App 시크릿 미구성, 포크 PR 등)에서는 기존과 동일하게 기본 토큰으로 동작해 워크플로가 깨지지 않는다.

두 워크플로는 토큰·게시·식별 로직 구조가 동일하므로, 동일한 변경 패턴을 양쪽에 똑같이 적용한다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. App 토큰 발급에 필요한 시크릿이 구성된 환경에서 리뷰 판정이 approve이고 승인 안전조건(지적 0건·`may_approve` 참·diff 미절단)이 충족될 때, 워크플로는 App 설치 토큰을 사용해 해당 PR에 공식 **APPROVE** 리뷰를 제출하며 기본 토큰의 self-approve 제약(403/422)에 걸리지 않는다.

2. 워크플로가 App 토큰으로 리뷰를 게시하는 동안, 공식 리뷰 제출·inline 코멘트·managed 코멘트·self inline thread resolve는 모두 동일한 App 봇 identity로 이뤄진다 (게시 주체가 두 계정으로 분리되지 않는다).

3. 워크플로가 App 토큰으로 동작하는 동안, 중복 리뷰 감지(idempotency)와 self inline thread 식별에 쓰는 봇 로그인은 하드코딩된 `github-actions[bot]`이 아니라 **인증된 App 봇 로그인으로 동적 해석**되어, 같은 head SHA·verdict의 중복 제출 방지와 자기 소유 thread의 fingerprint 단위 resolve가 App identity 기준으로 정확히 동작한다.

4. App 봇 identity로 게시된 리뷰·코멘트 이벤트는 이 리뷰 워크플로를 다시 트리거하지 않는다 (self-trigger 루프가 생기지 않는다).

5. App 토큰 발급에 필요한 시크릿이 없거나 토큰 발급에 실패하면, 워크플로는 기본 `GITHUB_TOKEN`으로 동작을 이어가 리뷰를 계속 게시하고(APPROVE 시도가 막히면 기존처럼 COMMENT로 fallback) 실패로 중단하지 않는다.

6. 위 1~5의 동작은 `claude-review.yml`과 `codex-review.yml` 양쪽에서 동일하게 성립한다.

## 범위
포함:
- `.github/workflows/claude-review.yml` — App 설치 토큰 발급 단계 추가, 리뷰 게시 스텝들의 토큰을 App 토큰(없으면 기본 토큰)로 전환, 봇 로그인 동적 해석, self-trigger 차단 게이트에 App 봇 포함.
- `.github/workflows/codex-review.yml` — 위와 동일 패턴 적용.

비-목표 / 제외:
- GitHub App 자체의 생성·설치, 시크릿(App ID·private key) 값의 등록 — 레포 설정·운영 작업이며 워크플로 코드 변경 범위 밖.
- 리뷰 판정 로직(verdict·findings·may_approve 산정)·프롬프트·결과 스키마 변경.
- inline-only 정책, REQUEST_CHANGES 폐지 등 기존 리뷰 동작 규약 변경.
- `rules/`·`milestones/`·`CLAUDE.md` 등 워크플로 외 문서.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- **토큰 발급 방식**: GitHub의 공식 액션 `actions/create-github-app-token`을 사용해, App ID와 private key 시크릿으로 매 실행마다 단명(short-lived) 설치 토큰을 발급한다. 장기 PAT를 단일 시크릿에 저장하는 방식은 쓰지 않는다.
- **시크릿 부재 시 graceful degradation**: 토큰 발급 스텝은 시크릿이 없으면 건너뛰고(또는 무해하게 종료하고), 후속 게시 스텝은 발급된 App 토큰이 있으면 그것을, 없으면 `github.token`을 사용한다(예: `${{ steps.<id>.outputs.token || github.token }}`). 시크릿을 직접 워크플로 레벨 `if` 표현식에서 참조할 수 없으므로 필요 시 env로 노출해 판정한다.
- **identity 통일**: 리뷰를 게시·식별·resolve하는 모든 `github-script` 스텝(공식 리뷰 제출, managed comment, self thread resolve)은 동일한 토큰(App 토큰 우선, 없으면 기본 토큰)을 쓴다.
- **봇 로그인 동적 해석**: 현재 `botLogin = 'github-actions[bot]'` 하드코딩과 그 GraphQL 변형(`botLoginGql`), managed comment 작성자 비교(`'github-actions[bot]'` 리터럴)는 실제 인증된 토큰의 봇 로그인을 기준으로 동작해야 한다. App 토큰 사용 시 인증 주체(`getAuthenticated` 류)로 로그인을 해석하고, 기본 토큰 사용 시 기존 `github-actions[bot]`을 유지한다.
- **self-trigger 차단**: 워크플로 상단 `if:` 게이트에서 `issue_comment`·`pull_request_review_comment`·`pull_request_review` 이벤트의 작성자가 `github-actions[bot]`이면 무시하던 동작을, App 봇 identity가 게시한 이벤트도 무시하도록 확장한다(또는 기존 `@claude` 멘션 요구가 App 자동 게시를 이미 배제함을 보장한다).
- 기존 idempotency·inline thread fingerprint resolve·managed comment supersede 동작은 보존한다 — 토큰·identity 교체로 인해 깨지지 않아야 한다.
- 두 워크플로에 동일 패턴을 적용해 동작·구조 차이를 만들지 않는다.

## 위험 (있을 때만)
- **봇 로그인 동적 해석 실패 시 idempotency·thread resolve 오작동**: 로그인 해석이 잘못되면 중복 리뷰가 쌓이거나 self thread를 식별 못 해 resolve가 멈출 수 있다. 해석 경로와 fallback(기본 토큰 시 `github-actions[bot]`)을 명확히 분기해야 한다.
- **self-trigger 루프**: App 봇 게시 이벤트를 게이트가 배제하지 못하면 워크플로가 자기 자신을 재트리거할 수 있다.
- **시크릿 미구성 환경 회귀**: graceful fallback이 부정확하면 포크 PR·미설정 레포에서 워크플로가 실패하거나 토큰 발급 스텝에서 멈출 수 있다.
- **App 설치 권한 부족**: 발급된 설치 토큰에 `pull_requests: write` 권한이 없으면 APPROVE가 여전히 실패한다 — 이는 App 설치 설정의 책임(범위 밖)이나, 실패 시 COMMENT fallback으로 안전하게 강등되어야 한다.
