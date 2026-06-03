# Claude PR Review Workflow

이 문서는 기존 `anthropics/claude-code-action` 기반 자유 형식 리뷰 대신 pinned Claude Code Action의 JSON schema 출력으로 PR 리뷰를 structured JSON으로 자동화하는 경계를 정의한다.

## 목표

- Codex PR review workflow와 같은 review core schema를 공유한다.
- diff를 먼저 읽고 필요한 문맥만 사용한다.
- 명확하고 실행 가능한 correctness 이슈만 남긴다.
- Claude 출력의 발견사항(findings)은 코드 라인에 anchor된 inline review thread로 단일 리뷰에 담아 게시한다. 리뷰 요약(summary)은 작성하지 않으며, 리뷰 본문은 approve일 때만 승인 사실 한 줄을 담는다.
- GitHub 전용 publish 로직과 모델별 review prompt를 분리한다.

## 현재 1차 워크플로

1. PR context를 확인한다.
2. base/head와 diff를 수집한다.
3. `.github/prompts/claude-pr-review.ko.md`를 system prompt처럼 붙인다.
4. pinned `anthropics/claude-code-action`을 실행하면서 `.github/prompts/codex-pr-review.schema.json`을 `--json-schema`로 전달한다.
5. action `structured_output`을 `.claude-review/result.json`으로 저장하고 JSON으로 검증한다.
6. 발견사항을 inline review comment 배열로 만든다. 각 comment는 발견사항의 파일과 변경 라인에 anchor되고 `side: 'RIGHT'`이며(multi-line이면 `start_line`/`start_side` 추가), 본문 끝에 숨김 마커 `<!-- claude-review-inline fingerprint=<fp> -->`를 붙인다. `fingerprint`는 발견사항의 안정 속성(파일 경로 + 리뷰 관점 + 정규화한 제목)만으로 결정론적으로 계산되며 줄 번호에 의존하지 않는다(정규화·해시 규칙은 codex 워크플로와 byte-identical).
7. inline comment 배열과 함께 단일 `github.rest.pulls.createReview` 호출로 제출한다. review event는 발견사항 0 + `approve` verdict + `automation_safety.may_approve` + diff 미절단일 때 `APPROVE`, 그 외 `COMMENT`다. **리뷰 본문은 실제 `APPROVE` 이벤트일 때만 `## Claude PR 리뷰` 헤더 + `승인되었습니다.` 한 줄을 담고, 그 외(비-approve)에는 숨김 멱등 마커만 담는다 — 리뷰 요약(summary)은 작성하지 않으며 발견사항은 inline 전용이다.** 워크플로 기본 토큰이 self-approve를 못 해 `APPROVE`가 실패하면 같은 inline 코멘트와 본문을 담은 `COMMENT` 리뷰로 강등 제출하고 `.claude-review/approval-failed`로 기록한다. 본문에는 `<!-- claude-formal-review head_sha=… verdict=… -->` 멱등 마커가 들어가, 같은 마커의 봇 리뷰가 이미 있으면 제출만 건너뛴다.
8. 게시 후(중복으로 제출을 건너뛰었어도 verdict와 무관하게), GraphQL `reviewThreads`로 조회해 자기 소유 + fingerprint 추출 가능 + 미해결인 inline thread를 fingerprint 기준으로 자동 resolve한다 — 모델이 `resolved_threads`에 올린 fingerprint(1차)이거나 이번 회차 findings의 fingerprint 집합에서 사라진 thread(2차 fallback)를 `resolveReviewThread`로 닫는다. 다른 리뷰어 thread나 fingerprint를 추출할 수 없는 thread는 건드리지 않는다. 발견사항을 담는 별도의 마커 관리형 이슈 레벨 코멘트 게시 경로는 없다(발견사항은 inline 전용).

## 운영 원칙

- review schema는 Codex와 공유한다. Claude 전용 prompt는 모델별 표현만 소유한다.
- user-provided PR title/body/comments는 untrusted context로만 다룬다.
- `@claude` comment trigger는 `OWNER`, `MEMBER`, `COLLABORATOR` author association만 허용한다.
- approval은 JSON verdict와 automation safety가 모두 통과할 때만 수행한다.
- schema/tool output 실패, context truncation, diff fetch 실패 시 approve하지 않는다.
- 기본 모델은 `claude-sonnet-4-5-20250929`이며, 저장소 variable `CLAUDE_REVIEW_MODEL`로 교체할 수 있다.

## Codex Workflow와의 차이

- Codex는 `codex exec --output-schema`로 runner가 schema 출력을 강제한다.
- Claude는 pinned `anthropics/claude-code-action`의 `--json-schema`/`structured_output` 경로를 사용한다.
- Claude workflow는 `claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}`을 요구하며, Codex auth 파일이나 Anthropic API key secret은 사용하지 않는다.

## Context Modes

- `full`: initial PR review. Sends full PR patch and existing comments.
- `incremental`: synchronize event. Sends only previous head to current head patch when available.
- `thread`: review-comment reply. Sends target thread metadata and the target file patch.

If the model returns `needs_context`, the workflow fetches up to 5 requested files from the PR head and runs one follow-up pass.

Claude authentication uses `CLAUDE_CODE_OAUTH_TOKEN`. The workflow uses pinned `anthropics/claude-code-action` with `claude_code_oauth_token`. If direct `claude -p` is used later, the workflow must not pass `--bare` because that path requires API key authentication.
