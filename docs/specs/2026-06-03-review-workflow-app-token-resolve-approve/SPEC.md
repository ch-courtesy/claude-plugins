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

# 리뷰 워크플로 App 설치 토큰으로 inline thread resolve·PR approve 복원

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

두 PR 리뷰 워크플로(Claude·Codex)가 **GitHub App 설치 토큰**으로 리뷰를 게시·식별·resolve·approve 하도록 복원한다. 그래서 고쳐진 finding의 self inline review thread가 **실제로 resolved 상태가 되고**, 승인 안전조건을 만족할 때 PR이 **실제로 APPROVE** 된다.

해결하려는 문제: 현재 두 워크플로는 워크플로 기본 토큰만 쓴다. 이 토큰은 리뷰 thread를 resolve 하려는 GraphQL 호출과 PR을 공식 APPROVE 하려는 호출을 모두 권한 부족으로 거부당한다(라이브 증거: PR #293에서 모델이 해결된 thread의 fingerprint를 올바르게 보고했는데도 resolve가 "Resource not accessible by integration"으로 실패). 즉 fingerprint 기반 self thread 자동 resolve 기능이 코드에는 있으나 토큰 권한 때문에 한 번도 실제로 동작하지 못한 채 출하돼 있었고, 그 실패는 비치명적 경고로 삼켜져 워크플로는 green 으로 끝나 드러나지 않았다.

이력 맥락(중요): App 설치 토큰 경로는 과거에 도입됐다가 이후 일부러 제거됐고, 직전 결정(self inline thread fingerprint resolve 복원 SPEC)은 "게시·resolve는 워크플로 기본 토큰만 사용하고 App 설치 토큰 경로를 두지 않는다"를 확정하며 계약 테스트에 App 토큰 재도입을 금지하는 검사를 박았다. 그 결정은 self-approve 불가(APPROVE→COMMENT 강등)만 수용 위험으로 보았고, **같은 권한 부족이 thread resolve까지 깨뜨린다는 점은 인지하지 못했다**. 본 SPEC은 그 직전 결정의 "App 토큰 금지" 수용 기준을 **명시적으로 역전(supersede)** 하고, App 설치 토큰 경로를 두 워크플로에 다시 도입한다. App 토큰을 쓸 수 없는 환경(App 시크릿 미구성, 발급 실패, 포크 PR 등)에서는 기존처럼 기본 토큰으로 계속 동작해 워크플로가 깨지지 않는다.

이 변경에는 그 금지 검사를 박은 계약 테스트의 **갱신**이 포함된다 — App 토큰 경로를 금지하던 검사를 App 토큰 경로를 요구·허용하도록 바꾸고, 그 외 기존 보안·핀 검사는 보존한다. (이전 구현 시도는 이 테스트가 변경 범위 밖이라 금지 검사를 고치지 못해 막혔다 — 본 SPEC은 두 계약 테스트를 범위에 포함해 그 교착을 해소한다.)

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면)과 언어 규칙은 references/ears-patterns.md. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->

1. App 토큰 발급 시크릿이 구성된 환경에서, 이전 리뷰가 남긴 self inline thread의 finding이 현재 변경에서 해결됐다고 판정되면, 워크플로는 App 설치 토큰으로 그 thread를 **실제 resolved 상태로 전환**하며 기본 토큰의 권한 거부("Resource not accessible by integration")에 걸리지 않는다.

2. App 토큰 발급 시크릿이 구성된 환경에서 리뷰 판정이 approve이고 승인 안전조건(지적 0건·승인 허용 플래그 참·diff 미절단)이 충족되면, 워크플로는 App 설치 토큰으로 해당 PR에 공식 **APPROVE** 리뷰를 제출하며 기본 토큰의 self-approve 제약(403/422)에 걸리지 않는다.

3. 워크플로가 App 토큰으로 동작하는 동안, 공식 리뷰 제출·inline 코멘트·관리 코멘트·self inline thread resolve는 모두 **동일한 App 봇 identity**로 이뤄지고(게시 주체가 둘로 갈라지지 않는다), 중복 리뷰 감지와 self thread 식별에 쓰는 봇 로그인은 하드코딩 값이 아니라 **인증된 App 봇 로그인으로 동적 해석**되어 정확히 동작한다.

4. App 봇 identity로 게시된 리뷰·코멘트 이벤트는 이 리뷰 워크플로를 **다시 트리거하지 않는다**(self-trigger 루프가 생기지 않는다).

5. App 토큰 발급 시크릿이 없거나 토큰 발급에 실패하면(또는 포크 PR 등 사용할 수 없는 맥락이면), 워크플로는 기본 토큰으로 동작을 이어가 리뷰를 계속 게시하고(APPROVE 시도가 막히면 COMMENT로 fallback) 실패로 중단하지 않는다.

6. 두 워크플로의 계약 테스트가 실행될 때, 테스트는 App 설치 토큰 발급·App 봇 동적 식별·승인 경로의 **존재를 요구(또는 허용)** 하며 더 이상 그 존재를 이유로 실패하지 않고, 동시에 기존 보안 검사(third-party action SHA 고정, 신뢰 base checkout, 모델 action 전 자격증명 제거 등)는 그대로 통과를 요구한다.

7. 위 1~6의 동작은 `claude-review.yml`과 `codex-review.yml` 양쪽에서 동일하게 성립한다.

## 범위
포함:
- `.github/workflows/claude-review.yml` — App 설치 토큰 발급 단계 추가, 게시·resolve·approve 스텝 토큰을 App 토큰(없으면 기본 토큰)으로 전환, 봇 로그인 동적 해석, self-trigger 가드에 App 봇 포함.
- `.github/workflows/codex-review.yml` — 위와 동일 패턴 적용.
- `tests/codex/test-codex-review-workflow.sh` — App 토큰 경로를 금지하던 검사를 요구·허용으로 갱신(다른 보안·핀 검사는 보존).
- `tests/claude/test-claude-review-workflow.sh` — App 토큰 경로 도입에 맞춰 검사 갱신·추가(Claude가 OAuth 토큰 교환에 필요로 하는 기존 `id-token: write` 요구는 보존).

비-목표 / 제외:
- 리뷰 판정 로직(verdict·findings·승인 허용 플래그 산정)·프롬프트·결과 스키마 변경.
- inline-only 정책, fingerprint 산정 방식, idempotency·managed comment supersede 등 기존 게시 규약 변경.
- GitHub App 자체의 생성·설치, App ID·private key 시크릿 값의 등록(레포 설정·운영 작업이며 워크플로 코드 변경 범위 밖 — 시크릿은 이미 구성돼 있다고 전제).
- `rules/`·`milestones/`·`CLAUDE.md` 등 워크플로·테스트 외 문서.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)
- **직전 결정의 명시적 역전**: 본 SPEC은 직전 "App 토큰 금지(기본 토큰만 사용)" 수용 기준을 의도적으로 역전한다. 구현·테스트는 그 금지 기준을 되살리지 않는다.
- **토큰 발급 방식**: GitHub 공식 액션 `actions/create-github-app-token`을 SHA 고정으로 사용해, App ID·private key 시크릿(`REVIEW_APP_ID`·`REVIEW_APP_PRIVATE_KEY`)으로 매 실행 단명(short-lived) 설치 토큰을 발급한다. 장기 PAT를 단일 시크릿에 저장하는 방식은 쓰지 않는다.
- **시크릿 부재 시 graceful degradation**: 토큰 발급 스텝은 시크릿이 없으면 건너뛰고, 후속 게시 스텝은 App 토큰이 있으면 그것을, 없으면 기본 토큰을 쓴다(예: `${{ steps.<id>.outputs.token || github.token }}`). 시크릿을 워크플로 레벨 `if`에서 직접 참조할 수 없으면 env 로 노출해 판정한다.
- **identity 통일**: 리뷰를 게시·식별·resolve·approve 하는 모든 스텝은 동일 토큰(App 토큰 우선, 없으면 기본 토큰)을 쓴다. 봇 로그인은 인증 주체(`getAuthenticated`류) 또는 App slug 로 동적 해석하고, 기본 토큰 사용 시 기존 `github-actions[bot]`을 유지한다.
- **self-trigger 차단 보존**: 상단 `if:` 게이트가 자동 게시 이벤트를 무시하던 동작을 App 봇 identity 게시 이벤트도 무시하도록 확장한다(또는 기존 `@claude` 멘션 요구가 App 자동 게시를 이미 배제함을 보장한다).
- **OIDC 권한 구분**: `actions/create-github-app-token`은 OIDC(`id-token`)를 필요로 하지 않는다. Claude 워크플로의 기존 `id-token: write`는 claude-code-action 의 OAuth 토큰 교환을 위한 것이므로 보존하고, App 토큰 도입을 이유로 새로 추가하지 않는다.
- **third-party action 핀**: App 토큰 액션을 포함한 모든 third-party action 은 mutable 태그가 아니라 커밋 SHA 로 고정한다.
- **기존 동작 보존**: idempotency·inline thread fingerprint resolve 로직·managed comment supersede·신뢰 base checkout·모델 action 전 자격증명 제거 등 기존 보장은 토큰·identity 교체로 깨지지 않아야 한다.

## 위험 (있을 때만)
- 워크플로 파일을 수정하는 PR은 변조 방지 가드로 인해 그 PR 안에서 변경된 워크플로가 자기 자신을 실행·검증하지 못할 수 있다(머지 후 다음 리뷰 실행부터 효력). 따라서 resolve·approve 가 실제로 동작하는지는 머지 후 후속 PR에서 관찰해 확인하며, PR 단계 검증은 계약 테스트(정적)에 의존한다.
- App 봇 identity 도입이 self-trigger 가드를 우회하면 무한 리뷰 루프가 생길 수 있다(완료 조건 4 로 방어).
- App 설치 토큰 발급 실패를 치명적으로 처리하면 리뷰가 전면 중단될 수 있다(완료 조건 5 의 graceful degradation 으로 방어).
