---
scope:
  include:
    - .github/workflows/codex-review.yml
    - .github/workflows/claude-review.yml
    - .github/scripts/**
    - tests/codex/**
    - tests/claude/**
    - docs/codex/pr-review-workflow.md
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# Review Workflow Phase 4 Token Optimization

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
Codex/Claude PR 리뷰 자동화의 Phase 4(Token Optimized Review)를 완성한다. 현재 두 워크플로는 큰 diff를 한 번에 모델에 넘기고, 모델이 `needs_context`를 반환할 때만 요청 파일(최대 5개)을 붙여 한 차례 재시도하는 2-pass만 갖췄다. 여기에 세 가지 동작을 더한다:

1. **토큰 예산 청크링** — 추정 입력 토큰이 예산을 넘으면 변경 파일을 여러 그룹으로 나눠 각 그룹을 독립 리뷰로 처리하고, 그 결과를 합쳐 하나의 리뷰로 제출한다.
2. **저우선 파일 강등** — 문서 전용·lockfile 전용·생성물 전용 변경을 낮은 우선순위로 다뤄, 총 예산을 넘길 때 리뷰 대상에서 먼저 제외한다.
3. **부분 findings 병합** — 청크별로 흩어진 findings를 fingerprint 기준으로 중복 제거·병합해 단일 제출 본문을 만든다.

이 세 동작은 codex-review.yml과 claude-review.yml에서 **대칭으로** 동작하며, 두 워크플로가 공유하는 새 로직은 한 곳에서만 정의한다.

## 목적 (왜)
<!-- 완료 조건의 종속 앵커일 뿐 검증 기준이 아니다. -->
큰 PR에서 diff가 모델 입력 한계를 넘으면 현재는 컨텍스트가 잘린 채(diff truncate) 리뷰가 진행되어 리뷰 품질이 떨어지고, 잘린 입력으로는 안전하게 승인할 수 없다. 변경을 예산 단위로 쪼개 빠짐없이 검토하고, 검토 가치가 낮은 파일에 예산을 낭비하지 않게 해 큰 PR에서도 신뢰할 수 있는 자동 리뷰를 유지하는 것이 목적이다.

## 완료 조건
<!-- 5문장 패턴. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- **항상** 두 리뷰 워크플로(`codex-review.yml`·`claude-review.yml`)는 청크링·파일 우선순위 분류·부분 findings 병합 로직을 `.github/scripts` 아래 단일 공유 모듈에서 가져와 동일하게 사용한다 — 각 워크플로에 같은 로직을 복사해 넣은 인라인 사본이 존재하지 않는다.
- **조립된 diff의 추정 토큰이 청크 임계(기본 80k)를 넘을 때** 변경 파일을 각 청크의 추정 토큰이 임계 이하가 되도록 그룹으로 나누고, 각 그룹을 별도 리뷰 모델 호출로 처리한다.
- **여러 청크를 리뷰한 뒤에는** 각 청크의 findings를 fingerprint 기준으로 중복 제거·병합해 단일 `createReview` 호출로 제출한다(청크마다 별도 리뷰를 쌓지 않는다).
- **추정 총 입력이 총 예산(기본 250k)을 넘을 때** 문서 전용·lockfile 전용·생성물 전용으로 분류된 저우선 파일을 리뷰 대상에서 제외하고, 제외된 파일 목록과 제외 사실을 로그로 남긴다.
- **추정 총 입력이 총 예산 이하인 동안에는** 저우선 파일도 리뷰 대상에 포함한다.
- **각 청크가 `needs_context`를 반환하면** 그 청크에 한해 요청 파일(최대 5개)을 붙여 follow-up 패스를 한 번 수행한다.
- 리뷰 이벤트는 **모든 청크의 verdict가 `approve`이고, 병합된 findings가 비어 있고, `automation_safety.may_approve=true`이며, 어떤 청크의 입력도 truncate되지 않았을 때만** `APPROVE`로 제출되고, 그 외에는 `COMMENT`로 제출된다.
- **추정 diff 토큰이 청크 임계 이하인 동안에는** 청크링이 발동하지 않고 기존 단일 패스 리뷰 동작이 그대로 유지된다(회귀 없음).
- **제출할 in-diff finding이 있었는데도 병합·제출이 최종 실패하면** job을 실패시킨다(false-green 가드 유지). 저우선 제외로 제출할 finding이 없어진 경우나 zero-finding `APPROVE`→`COMMENT` 강등은 실패로 취급하지 않는다.
- **항상** 공유 단위(`diff-anchor-filter.js`·`pr-review-context.sh`·fingerprint 정규화)의 기존 동작과 byte-identical 보장이 보존된다.

## 범위
포함:
- `.github/workflows/codex-review.yml`, `.github/workflows/claude-review.yml` — 청크링·강등·병합 호출 배선(대칭)
- `.github/scripts/**` — 토큰 추정·파일 우선순위 분류·청크 그룹핑·부분 findings 병합 공유 모듈(신규)
- `docs/codex/pr-review-workflow.md` — Phase 4 진행 표기를 "구현됨"으로 갱신

비-목표 / 제외:
- `rules/**`, `milestones/**`, `CLAUDE.md`
- verdict 모델·schema(`codex-pr-review.schema.json`) 변경 — Phase 4는 게이트 enum을 바꾸지 않는다
- Phase 5(다중 관점 병렬 리뷰)·플랫폼 공통화(review-core/adapters 분리)
- confidence 필터의 워크플로 하드 게이트화(별도 후속)
- 모델·reasoning effort·action SHA 변경

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- **토큰 추정**: 셸/Actions 런타임에 토크나이저가 없으므로 추정 토큰은 **문자수 / 4** 휴리스틱으로 계산한다(조립된 프롬프트·diff 텍스트 기준).
- **권장 기본값(상수)**: max total input 250k, max diff before chunking 80k, max single file content 30k, max related files per changed file 5, max unchanged context expansion depth 2, max output 16k 토큰. 이 값들은 권장 기본값으로 워크플로/공유 모듈에 상수로 둔다.
- **공유 방식**: 신규 로직은 `.github/scripts` 아래 CommonJS 모듈(`module.exports` + `require`)로 두고, 두 워크플로의 `github-script` 인라인 단계에서 `require`로 소비한다(`diff-anchor-filter.js`와 동일 패턴). 두 워크플로의 동작은 대칭이어야 한다.
- **청크링 메커니즘(결정됨): dynamic-matrix 멀티잡 파이프라인**. GHA `uses:` 스텝은 루프 불가하므로 가변 횟수 모델 호출은 잡을 세 단계로 재구성해 구현한다: (1) **prep 잡** — 컨텍스트 수집·저우선 강등·청크 그룹핑을 수행하고 청크 목록을 `strategy.matrix`용 출력으로 내보낸다(청크 없음/단일 청크면 matrix-of-1 → 기존 단일 패스와 동치). (2) **review 잡(matrix)** — 청크별로 모델 action(+청크당 needs_context follow-up 1회)을 호출해 청크별 결과를 아티팩트로 올린다. (3) **merge+submit 잡** — 모든 청크 결과를 fingerprint 기준 병합하고 단일 `createReview`로 제출한다. **모델 action `uses:` 소스 라인 수는 런타임 matrix 확장과 무관하게 불변**이므로 기존 카운트 계약(`codex_action_count` 등)을 깨지 않는다.
- **보안·권한 로직 재배치(승인됨)**: App 토큰 발급·anchor 검증·false-green 가드·idempotency·self thread-resolve를 merge+submit 잡으로 이전한다. **로직·동작은 보존하고 잡 경계만 이동**하며, 토큰 권한 범위·승인 게이트·degrade 경로는 기존과 동일하게 유지한다(권한 확대 금지).
- **계약 테스트(scope 내 tests/\*\*)**: 멀티잡 구조를 검증하는 계약 테스트를 `tests/codex`·`tests/claude`에 **추가**한다(prep/review-matrix/merge 잡 존재, 모델 action 소스 카운트 불변, 병합-단일제출, 보안 로직의 merge 잡 소재). 기존 계약 테스트는 **약화·삭제하지 않으며**, 구조 변경으로 갱신이 불가피한 단언은 새 구조의 동치 보장을 유지하는 방향으로만 수정한다(안전 의도 보존).
- **저우선 파일 분류 기준(기본 집합)**: 문서 전용(`*.md`, `docs/**`), lockfile 전용(`package-lock.json`·`yarn.lock`·`pnpm-lock.yaml`·`Cargo.lock`·`poetry.lock`·`go.sum`·`composer.lock` 등), 생성물 전용(`.gitattributes`의 `linguist-generated`, `*.min.js`, `dist/**` 등). 한 PR이 저우선 분류 파일만 바꾼 경우에도 분류가 동작해야 한다.
- **청크 그룹핑**: 변경 파일을 추정 토큰 기준 greedy 묶기로 각 청크가 청크 임계 이하가 되도록 그룹화한다. 단일 파일이 임계를 단독으로 넘으면 자체 청크에 두되 max single file content(30k) 한도로 내용을 truncate하고 truncate 플래그를 세운다.
- **공유 단위 불변**: `diff-anchor-filter.js`·`pr-review-context.sh`·fingerprint 정규화는 byte-identical로 유지하고, 청크링은 이들의 입력(diff.patch / anchor.patch)·anchor 검증을 우회하지 않는다 — anchor 검증과 false-green 가드는 병합·제출 직전 기존 위치에서 그대로 적용된다(anchor 검증은 청크별이 아니라 전체 PR 정본 anchor.patch 기준 그대로).
- **thread resolve 기준**: self thread resolve의 2차 fallback("이번 회차 findings에서 사라진 fingerprint")은 청크별 findings가 아니라 **모든 청크를 병합한 findings 집합** 기준으로 판정한다 — 한 청크에만 있고 다른 청크에 없는 finding이 잘못 resolve되지 않도록 한다.
- **trusted-base require 주의**: 공유 모듈을 도입·수정하는 바로 그 PR에서는 trusted base 체크아웃에 모듈이 없어 `require`가 실패할 수 있다 — 이때는 기존 `diff-anchor-filter.js` 패턴처럼 명시적 경고와 함께 단일 패스로 loud degrade한다(청크링은 머지 후부터 효력).

## 위험
- 문자수/4 휴리스틱은 CJK·유니코드 다바이트 텍스트에서 실제 토큰을 과소추정할 수 있어, 추정상 임계 이하인데도 실제 모델 입력이 한계를 넘을 수 있다 — 임계에 보수적 마진을 두는 것을 고려한다.
- 청크 경계가 파일 단위이므로, 여러 파일에 걸쳐서만 드러나는 cross-file finding은 서로 다른 청크에 흩어진 파일을 한 번에 보지 못해 놓칠 수 있다.
- 청크당 `needs_context` follow-up은 모델 호출 수와 비용을 청크 수만큼 곱으로 늘린다.
- 생성물·lockfile 오분류로 실제 검토가 필요한 파일이 제외될 수 있다 — 제외는 항상 로그로 가시화해 사후 추적을 보장한다.
