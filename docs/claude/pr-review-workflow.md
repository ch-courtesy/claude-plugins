# Claude PR Review Workflow

이 문서는 기존 `anthropics/claude-code-action` 기반 자유 형식 리뷰 대신 pinned Claude Code Action의 JSON schema 출력으로 PR 리뷰를 structured JSON으로 자동화하는 경계를 정의한다.

## 목표

- Codex PR review workflow와 같은 review core schema를 공유한다.
- diff를 먼저 읽고 필요한 문맥만 사용한다.
- 명확하고 실행 가능한 correctness 이슈만 남긴다.
- Claude 출력은 action `structured_output`으로 받아 GitHub review 동작으로 매핑한다.
- GitHub 전용 publish 로직과 모델별 review prompt를 분리한다.

## 현재 1차 워크플로

1. PR context를 확인한다.
2. base/head와 diff를 수집한다.
3. `.github/prompts/claude-pr-review.ko.md`를 system prompt처럼 붙인다.
4. pinned `anthropics/claude-code-action`을 실행하면서 `.github/prompts/codex-pr-review.schema.json`을 `--json-schema`로 전달한다.
5. action `structured_output`을 `.claude-review/result.json`으로 저장하고 JSON으로 검증한다.
6. `verdict`에 따라 GitHub review를 제출한다.
   - `approve`: `gh pr review --approve`
   - `request_changes`: `gh pr review --request-changes`
   - `comment`, `needs_context`, `unavailable`: `gh pr review --comment`
7. managed issue comment를 marker 기반으로 create/update한다.

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
