---
scope:
  include:
    - .github/workflows/codex-review.yml
    - .github/workflows/claude-review.yml
    - tests/codex/test-codex-review-workflow.sh
    - tests/claude/test-claude-review-workflow.sh
    - docs/codex/pr-review-workflow.md
    - docs/claude/pr-review-workflow.md
  exclude:
    - rules/**
    - milestones/**
    - CLAUDE.md
# ears_language: ko
---

# PR Review Inline Thread 게시 + fingerprint resolve 복원

## 무엇을 만들 것인가
<!-- WHAT/HOW 방어선: 무엇을 만들지만 적고 구현 방법·파일·라이브러리·클래스명은 제약으로 이동. -->

두 PR 리뷰 GitHub Actions 워크플로(Codex·Claude)가 리뷰 발견사항(findings)을 **코드 라인에 anchor된 inline review thread**로 게시하고, 모델이 해소되었다고 판정한 자기 소유 thread를 **fingerprint 기준으로 자동 resolve**하도록 게시 동작을 전환한다.

현재 두 워크플로의 프롬프트와 공유 스키마는 이미 "inline 전용 게시 + fingerprint 기반 thread 라이프사이클"을 완전히 기술하지만, 실제 게시 단계는 그 데이터를 버리고 정식 verdict 리뷰 + 마커 관리형 이슈 코멘트 1개를 평문으로 올린다. 이 어긋남을 해소해, 게시를 **단일 inline 리뷰**로 통합한다 — findings는 inline comment로, 리뷰 요약(summary)은 그 리뷰 본문으로, 한 번의 리뷰 제출에 담는다. 별도 마커 관리형 이슈 코멘트 게시 경로는 제거한다.

이 inline+resolve 게시 동작은 과거에 존재했다가 제거된 것으로, 검증된 구현이 git 이력에 온전히 남아 있다. 백지에서 다시 설계하지 않고 그 구현을 현재(앱 토큰이 제거된) 구조에 맞춰 복원·적응한다.

## 완료 조건
<!-- 5문장 패턴(항상 / …할 때 / …인 동안 / …이면(오류) / …기능이 켜지면). 각 조건은 관찰 가능하고 독립 검증 가능. -->

1. **항상**, 두 워크플로(Codex·Claude)의 리뷰 게시 단계는 발견사항을 inline comment 배열과 함께 단일 리뷰 생성 호출(`github.rest.pulls.createReview`의 `comments[]`)로 게시해야 한다. 각 inline comment는 발견사항의 파일과 변경 라인에 anchor되고 `side: 'RIGHT'`를 갖는다.

2. **모델이 발견사항을 반환할 때**, 시스템은 각 inline comment 본문 끝에 그 발견사항의 fingerprint를 담은 숨김 마커(`<!-- codex-review-inline fingerprint=… -->` 또는 `<!-- claude-review-inline fingerprint=… -->`)를 자동으로 덧붙여야 한다.

3. **항상**, fingerprint는 발견사항의 안정 속성(파일 경로 + 리뷰 관점 + 정규화한 제목)만으로 계산되고 줄 번호에 의존하지 않아야 하며, 두 워크플로가 byte-identical한 정규화·해시 규칙으로 같은 값을 산출해야 한다(같은 발견사항은 PR 진화로 줄 위치가 바뀌어도 실행 간 동일 fingerprint).

4. **모델이 어떤 self thread를 해소로 판정(resolved_threads)했거나, 이전 회차 self thread의 발견사항이 이번 회차 발견사항 집합에서 사라졌을 때**, 시스템은 그 자기 소유 미해결 inline thread를 자동으로 resolve해야 한다(리뷰 thread 조회 → 자기 소유 + fingerprint 추출 가능 + 미해결인 thread만 대상; 다른 리뷰어 thread는 건드리지 않음). 이 후처리는 verdict와 무관하게, 그리고 중복 제출로 게시를 건너뛴 경우에도 실행되어야 한다.

5. **항상**, 게시·resolve는 워크플로 기본 토큰만 사용해야 하며 GitHub App 설치 토큰 발급·App 토큰 정식 승인 경로를 두지 않아야 한다.

6. **항상**, 발견사항을 담는 별도의 마커 관리형 이슈 레벨 코멘트 게시 경로가 없어야 한다(발견사항은 inline 전용; 요약은 리뷰 본문에만 실린다).

7. **정식 승인(APPROVE) 제출이 토큰 권한으로 실패하면**, 시스템은 같은 inline 코멘트를 담은 COMMENT 리뷰로 강등 제출하고 승인 실패를 기록해야 한다(발견사항을 미게시로 흘리지 않음).

8. **항상**, 두 계약 테스트(`tests/codex/test-codex-review-workflow.sh`, `tests/claude/test-claude-review-workflow.sh`)가 inline 게시·fingerprint resolve 동작의 존재를 단언하고 모두 통과(ALL CHECKS PASSED)해야 한다.

## 범위
포함:
- `.github/workflows/codex-review.yml`: 게시 두 스텝(`Submit Codex review verdict` + `Post Codex review comment`)을 단일 inline 리뷰 게시 스텝으로 대체.
- `.github/workflows/claude-review.yml`: 동일하게 `Submit Claude review verdict` + `Post Claude review comment`를 단일 inline 리뷰 게시 스텝으로 대체.
- `tests/codex/test-codex-review-workflow.sh`: inline 부재를 강제하던 검사를 inline 존재 강제로 반전, verdict/이슈 코멘트 검사를 inline 구조로 갱신.
- `tests/claude/test-claude-review-workflow.sh`: 동일한 inline 존재 + fingerprint resolve 회귀 가드 추가(패리티), 기존 verdict/comment 검사 갱신.
- `docs/codex/pr-review-workflow.md`: Phase 2/3 "superseded" 표기 해제 → 현행 동작 기술.
- `docs/claude/pr-review-workflow.md`: 게시 구조 기술을 inline 단일 리뷰 + fingerprint resolve로 갱신.

비-목표 / 제외:
- 공유 스키마(`.github/prompts/codex-pr-review.schema.json`) 수정 — 이미 inline·fingerprint thread 필드 보유.
- 두 리뷰 프롬프트(`.github/prompts/*-pr-review.ko.md`) 수정 — 이미 inline 전용 정책·마커 라이프사이클 기술.
- 공유 컨텍스트 헬퍼(`.github/scripts/pr-review-context.sh`) 수정 — 기존 thread는 게시 스텝이 GraphQL로 직접 조회.
- createReview all-or-nothing 422를 회피하는 diff 라인 사전검증 하드닝 — 별도 후속(범위 외).
- 모델 호출·인증·2-pass needs_context 흐름 등 게시 외 단계 변경.

## 검증
<!-- 검증 기준의 단일 출처는 위 "완료 조건"이다. 검증을 실행하는 진입 명령(테스트·lint·빌드)은 SPEC이 선언하지 않는다. -->
이 SPEC의 인수 바는 위 **완료 조건**이다. 각 조건이 관찰 가능하게 충족되면 충족된 것으로 본다. 검증을 실행하는 진입 명령은 SPEC이 아니라 프로젝트 규칙(`rules/`)이 단일 출처로 정의한다.

## 제약 (있을 때만)

**복원 기준 구현 (백지 작성 금지).** 검증된 구현이 커밋 `3199ff1`에 온전히 존재한다. 이를 참조해 복원·적응한다:
- 참조: `git show 3199ff1:.github/workflows/codex-review.yml` — 게시 스텝은 단일 `actions/github-script` 블록(원본 L248-480). 동일 시점의 `claude-review.yml`도 같은 구조.
- 신규 게시 스텝은 `actions/github-script`(현재 SHA 고정 핀 유지) 한 개로, 다음을 수행한다:
  - **결정론적 fingerprint**: `sha256(file + ' ' + review_perspective + ' ' + normalizeTitle(title))`의 hex 앞 16자. `normalizeTitle` = NFKC 정규화 → 소문자 → `[^\p{L}\p{N}]+`를 단일 공백으로 → trim. 정규화·해시 규칙은 두 워크플로 byte-identical.
  - **inline comments 배열**: 발견사항마다 `{ path: f.file, line: (f.line>0 ? f.line : f.start_line), side: 'RIGHT', body }`. multi-line이면 `start_line < anchor`일 때만 `start_line`/`start_side:'RIGHT'` 추가. `body`는 `**[severity/confidence] title**` + 본문 + `**Suggestion:**` + 끝에 `<!-- {codex,claude}-review-inline fingerprint=<fp> -->` 마커.
  - **단일 리뷰 제출**: `github.rest.pulls.createReview({ owner, repo, pull_number, commit_id: head_sha, event, body, comments })`. `event`는 발견사항 0 + verdict `approve` + `automation_safety.may_approve` + `reviewed_context.diff_truncated`가 false일 때 `APPROVE`, 그 외 `COMMENT`.
  - **리뷰 본문(body)**: 헤더(`## Codex PR 리뷰` / `## Claude PR 리뷰`) + `result.summary`(있으면) + 숨김 멱등 마커 `<!-- {prefix}-formal-review head_sha=… verdict=… -->`. approve일 때는 `_승인 — 지적 사항은 인라인 코멘트 참조._` 줄 추가. 자연어 문자열은 한국어 유지.
  - **멱등성**: `github.rest.pulls.listReviews`에서 `botLogin`이 올린 리뷰 중 본문에 같은 멱등 마커가 있으면 제출만 건너뛴다(resolve 후처리는 계속). APPROVE 중복(같은 head_sha의 기존 APPROVED)도 건너뛴다.
  - **APPROVE 실패 fallback**: APPROVE 제출이 throw하면 `.{codex,claude}-review/approval-failed`를 쓰고 COMMENT로 재시도한다.
  - **self-thread resolve**: GraphQL `reviewThreads(first:100)`로 조회 → `isResolved=false` + 첫 코멘트 author가 `botLogin`(또는 `[bot]` suffix 제거형 `botLoginGql`) + 본문에 inline 마커 base 포함 + `fingerprint=…` 추출 가능한 thread에 대해, (1차) `resolved_threads`에 fingerprint가 있거나 (2차/fallback) 이번 회차 findings의 fingerprint 집합에 없으면 `resolveReviewThread` mutation 실행. fingerprint를 추출할 수 없는 thread는 건드리지 않는다.

**현재 구조에 맞춘 적응 (원본과의 차이).**
- App 토큰 의존 제거: 원본의 `app-token`/`app-slug`/`APP_SLUG` 입력·분기를 두지 않는다. `github-token: ${{ github.token }}`, `botLogin = 'github-actions[bot]'` 고정.
- summary를 리뷰 본문에 포함(원본은 inline-only로 summary를 본문에서 생략했음 — 본 SPEC은 사용자 결정에 따라 summary를 본문에 싣는다).
- `claude-review.yml`의 기존 `id-token: write` 권한은 `claude-code-action` OIDC용이므로 유지한다. `codex-review.yml`에는 `id-token` 권한을 추가하지 않는다.

**테스트 갱신.**
- `tests/codex/test-codex-review-workflow.sh`: inline 부재를 강제하던 검사(현 check 15: `pulls.createReview`/`inlineComments`/`side: 'RIGHT'` 부재 단언, check 16: `computeFingerprint`/`resolveReviewThread`/`reviewThreads`/`resolved_threads`/`codex-review-inline`/`fingerprint` 부재 단언)를 **존재 강제로 반전**한다. verdict·이슈 코멘트 구조 검사(현 check 13/14)는 inline 단일 리뷰 구조로 갱신하되 `issues.createComment` 등 이슈 코멘트 게시 단언은 제거한다. App 토큰 부재 검사(현 check 17)·권한 검사(현 check 18, `id-token` 없음 포함)·기타 보안/핀 검사는 유지한다. 줄 비의존 fingerprint(줄 번호 미포함)·마커 형식 일치 회귀 가드는 `3199ff1`이 추가했던 것을 참조해 복원한다.
- `tests/claude/test-claude-review-workflow.sh`: 현재 inline 단언이 없으므로 codex와 동등한 inline 존재 + fingerprint resolve 회귀 가드를 추가하고, 기존 verdict/comment 단언을 inline 구조로 갱신한다.

**문서 갱신.**
- `docs/codex/pr-review-workflow.md`: Phase 2(Inline Comment Adapter)·Phase 3(Thread Lifecycle)의 "superseded" 표기를 해제하고 현행 동작으로 기술한다. "현재 1차 워크플로" 게시 단락과 인라인 미사용을 명시한 단락을 inline 단일 리뷰 + fingerprint resolve로 갱신한다.
- `docs/claude/pr-review-workflow.md`: 게시 구조 기술(현재 이슈 코멘트 + verdict)을 inline 단일 리뷰 + fingerprint resolve로 갱신한다.

**일관성.** 두 워크플로의 게시 스텝은 라벨/마커 prefix/헤더 문자열만 다르고(codex ↔ claude) 로직은 동일해야 한다.

## 위험 (있을 때만)

- **createReview all-or-nothing 422**: 한 발견사항의 line이 diff에 포함되지 않으면 `pulls.createReview`가 통째로 422가 되어 그 회차 inline이 전부 미게시되고 로그로만 남는다. 프롬프트가 "변경된 diff 라인의 양수 정수에 anchor"를 강하게 강제하므로 원본 동작을 그대로 수용한다. diff 라인 사전검증 후 미anchor 발견사항을 본문으로 강등하는 하드닝은 범위 외 후속.
- **self-approve 제약**: 워크플로 기본 토큰은 자기 PR을 정식 APPROVE하지 못해 COMMENT로 강등될 수 있다(완료 조건 7로 처리).
- **워크플로 자기 변경 가드**: 두 워크플로 모두 `paths-ignore: .github/workflows/**` 트리거를 가져, 이 SPEC 변경을 담은 PR에서는 변경된 워크플로가 머지 후에야 효력을 갖는다. 따라서 신규 inline 동작은 이 PR의 self-review로 직접 검증할 수 없고 머지 후 후속 PR에서 확인한다. 계약 테스트·정적 검증이 머지 전 1차 판정 근거다.
