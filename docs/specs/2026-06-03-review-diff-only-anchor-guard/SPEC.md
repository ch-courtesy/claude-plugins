---
scope:
  include:
    - .github/workflows/codex-review.yml
    - .github/workflows/claude-review.yml
    - .github/scripts/**
    - tests/codex/**
    - tests/claude/**
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# 리뷰 워크플로 diff-only anchor 검증과 false-green 가드

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->
PR 리뷰 워크플로(codex·claude)가 모델 finding을 inline 리뷰 코멘트로 게시하기 전에, 각 finding의 anchor가 그 PR diff에 실제로 포함된 라인인지 검증하는 단계를 추가한다. diff에 포함되지 않은 라인(또는 PR에서 변경되지 않은 파일)에 붙은 finding은 게시 대상에서 제외하고, diff에 포함된 finding만 제출한다. 또한 게시할 finding이 있는데 그 제출 자체가 실패하면 워크플로 job을 실패로 끝내, finding이 조용히 사라진 채 job이 성공으로 보이는 일(false-green)을 없앤다. 검증 동작은 두 워크플로가 공유하는 단일 검증 단위로 두어 양쪽이 동일하게 동작하게 한다.

## 목적 (왜)
<!-- 이 변경을 왜 하는가(목표·동기)를 1–3문장으로. -->
현재 리뷰 워크플로는 모델이 PR diff 밖 라인(컨텍스트로 읽은 unchanged 파일 등)에 finding을 anchor하면 GitHub `createReview`가 422 "Path could not be resolved"로 리뷰 전체를 거부하는데, 이 실패를 경고로만 삼키고 job은 성공으로 끝나, 같은 배치의 정상 finding까지 통째로 미게시되면서도 "리뷰 통과"처럼 보였다(PR #306 실증: codex의 blocking finding 1건이 PR diff 밖 `dispatch.sh:485`에 anchor되어 전량 폐기, job은 green). 리뷰는 그 PR이 바꾼 내용에 대해서만 판정해야 하며, finding이 사라졌으면 그 사실이 결과에 드러나야 한다.

## 완료 조건
<!-- 5문장 패턴. 각 조건은 관찰 가능하고 독립 검증 가능해야 함. -->
- **항상** 리뷰 워크플로(codex·claude)는 모델 finding을 inline 코멘트로 제출하기 전에, 각 finding의 anchor(파일 경로, `line`, 그리고 `start_line`이 있으면 그 범위의 양 끝)가 그 PR diff의 추가·문맥 라인(우측/RIGHT side) 집합에 포함되는지 검증한다.
- finding의 anchor가 PR diff 라인 집합 **밖일 때**(파일이 PR diff에 없거나, 라인이 변경 hunk 밖일 때) 워크플로는 그 finding을 제출 대상에서 제외하고, 다른 라인으로 옮겨 붙이거나 강제로 게시하지 않으며, 제외한 finding의 파일·라인·제목을 job 로그에 남긴다.
- diff 라인 집합 안에 anchor된 finding이 하나 이상 있는 **동안** 그 finding들은 항상 게시되며, 같은 배치에 섞인 diff 밖 finding 때문에 함께 누락되지 않는다.
- 게시할(diff 안에 anchor된) finding이 있는데 그 finding의 리뷰 제출이 최종적으로 실패하**면(오류)** 워크플로는 경고로만 끝내지 않고 job을 실패(비-성공)로 종료한다. (게시할 in-diff finding이 0건이라 제출할 것이 없는 경우, 그리고 self-approve가 권한 부족으로 일반 코멘트 제출로 정상 강등된 경우는 실패가 아니다.)
- 검증·제외·실패 가드 로직이 공유 단위로 추출되는 **기능이 켜지면**, codex와 claude 워크플로는 동일한 단일 검증 단위를 호출하며 anchor 검증·제외·가드 동작에서 서로 동일하게 동작한다(두 워크플로에 같은 로직이 따로 복제되지 않는다).

## 범위
포함:
- codex·claude 리뷰 워크플로의 inline 리뷰 제출 단계에 diff-only anchor 검증과 diff 밖 finding 제외를 추가.
- 제출 실패 시 job을 실패로 끝내는 false-green 가드 추가(정상 강등·게시할 finding 없음은 제외).
- 검증 로직을 두 워크플로가 공유하는 단일 단위로 추출.
- 신규 검증 단위의 단위 테스트와, 두 워크플로 contract 테스트에 "검증 호출·실패 가드 존재" 정적 검사 추가.

비-목표 / 제외:
- 리뷰 모델이 diff 밖 파일을 **컨텍스트로 읽는** 능력은 제한하지 않는다(codex read-only sandbox, follow-up 컨텍스트 추출은 그대로 유지). 강제는 게시 레이어에서만 한다.
- 리뷰 프롬프트(diff 밖 anchor 금지 지시 등) 자체는 이 변경에서 바꾸지 않는다 — 게시 레이어 검증이 단일 보장 지점이다.
- inline-only 정책(요약/issue 코멘트로 finding fallback 안 함), fingerprint·marker·self-thread resolve, APPROVE/COMMENT 결정, 토큰 선택(App vs default) 등 기존 리뷰 게시 구조는 보존한다.
- diff 계산 방식(`.review-context/diff.patch` 생성)은 바꾸지 않는다 — 이미 생성된 patch를 검증 입력으로 소비만 한다.
- 플러그인 버전 범프는 대상이 아니다(`.github/`는 버전 watch 디렉토리가 아님).

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약
- anchor 검증 입력은 워크플로가 이미 만든 `.review-context/diff.patch`(unified diff)이며, RIGHT side(추가 `+`·문맥 ` ` 라인)의 파일별 라인 번호 집합을 그 patch에서 도출한다. 새로 diff를 계산하지 않는다.
- 검증 로직은 `.github/scripts/` 아래 Node 모듈로 추출하고, 두 워크플로의 inline 제출 단계(`actions/github-script`)에서 이 단일 모듈을 불러 사용한다. 두 워크플로에 같은 검증 로직을 byte 단위로 복제하지 않는다.
- `start_line`이 있는 multi-line finding은 `start_line`과 `line` 양 끝이 모두 diff 라인 집합에 있어야 게시 대상으로 인정한다(한쪽이라도 밖이면 제외).
- 기존 게시 단계의 단일 `createReview` 호출에 invalid anchor가 섞여 valid finding까지 422로 함께 무너지지 않도록, invalid finding은 제출 배치 구성 **전에** 제외한다.
- 실패 가드는 "게시할 in-diff finding이 있었는데 제출이 끝내 실패"한 경우에만 job을 실패시킨다 — diff 밖 finding 제외(정상 동작)나 APPROVE→COMMENT 정상 강등을 실패로 취급하지 않는다.
- 두 워크플로의 contract 테스트(`tests/codex/`, `tests/claude/`)는 GitHub·모델을 호출하지 않는 정적 검사 컨벤션을 유지하며, 신규 검증 단위는 별도 단위 테스트로 diff 파싱→valid 라인 집합→finding 필터링을 직접 검증한다.

## 위험
- diff.patch 파싱의 정확도: 다중 hunk, 문맥 라인, 파일 rename/삭제, multi-line range를 잘못 해석하면 valid finding을 제외하거나 invalid finding을 통과시킬 수 있다 — 단위 테스트로 이 경계들을 덮어야 한다.
- 실패 가드가 리뷰 체크를 required로 운용 중인 저장소에서 merge를 차단할 수 있다. 이는 false-green 제거라는 목적상 의도된 동작이며, 정상적인 diff 밖 제외는 실패로 보지 않아 과도한 차단을 피한다.
- 게시 레이어에서만 강제하므로, 모델이 여전히 diff 밖 finding을 만들면 그 finding은 게시되지 않고 로그로만 남는다(리뷰 신호 손실 가능성) — 단, 그 finding은 해당 PR이 바꾸지 않은 코드에 대한 것이므로 이 PR 리뷰의 범위 밖이라는 것이 의도된 정책이다.
