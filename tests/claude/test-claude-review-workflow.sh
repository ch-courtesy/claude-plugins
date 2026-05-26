#!/usr/bin/env bash
# Claude PR review workflow contract.
#
# Static checks only: do not call GitHub or Anthropic.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKFLOW="$REPO_ROOT/.github/workflows/claude-review.yml"
PROMPT="$REPO_ROOT/.github/prompts/claude-pr-review.ko.md"
SCHEMA="$REPO_ROOT/.github/prompts/codex-pr-review.schema.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$WORKFLOW" ]] || fail "$WORKFLOW 부재"
[[ -f "$PROMPT" ]] || fail "$PROMPT 부재"
[[ -f "$SCHEMA" ]] || fail "$SCHEMA 부재"

echo "=== check 1: Claude Code OAuth token is required for Claude review ==="
grep -q 'claude_code_oauth_token:.*secrets\.CLAUDE_CODE_OAUTH_TOKEN' "$WORKFLOW" \
  || fail "claude_code_oauth_token secret 매핑 부재"
grep -q 'CLAUDE_CODE_OAUTH_TOKEN secret is required' "$WORKFLOW" \
  || fail "CLAUDE_CODE_OAUTH_TOKEN 누락 시 실패 메시지 부재"
if grep -q 'ANTHROPIC_API_KEY' "$WORKFLOW"; then
  fail "ANTHROPIC_API_KEY 기반 인증이 남아 있음"
fi
grep -qE '^[[:space:]]*id-token:[[:space:]]*write' "$WORKFLOW" \
  || fail "claude-code-action OIDC 토큰 교환에 필요한 id-token: write 권한 부재"
ok "check 1: claude_code_oauth_token secret + id-token: write 권한을 명시적으로 요구"

echo ""
echo "=== check 2: Claude review uses pinned claude-code-action with shared context ==="
grep -q 'REVIEW_BASE="$(git merge-base "origin/\$PR_BASE_REF" "refs/remotes/pull/\$PR_NUMBER/head")"' "$WORKFLOW" \
  || fail "PR head 와 base branch 의 merge-base 계산 부재"
grep -q 'REVIEW_PROMPT="\.github/prompts/claude-pr-review\.ko\.md"' "$WORKFLOW" \
  || fail "Claude structured review prompt 파일 참조 부재"
grep -q 'REVIEW_SCHEMA="\.github/prompts/codex-pr-review\.schema\.json"' "$WORKFLOW" \
  || fail "공통 structured review schema 파일 참조 부재"
grep -q '\.github/scripts/pr-review-context\.sh' "$WORKFLOW" \
  || fail "shared review context helper 호출 부재"
grep -q 'source \.review-context/context-mode\.env' "$WORKFLOW" \
  || fail "review context mode env 로드 부재"
grep -q 'REVIEW_CONTEXT_MODE' "$WORKFLOW" \
  || fail "prompt 에 review context mode 주입 부재"
grep -qE 'uses: anthropics/claude-code-action@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "anthropics/claude-code-action SHA 고정 부재"
grep -q 'claude_code_oauth_token:.*secrets\.CLAUDE_CODE_OAUTH_TOKEN' "$WORKFLOW" \
  || fail "claude_code_oauth_token input 매핑 부재"
grep -q -- '--json-schema' "$WORKFLOW" \
  || fail "Claude action json schema 지정 부재"
grep -q 'steps\.prepare-claude-review\.outputs\.schema' "$WORKFLOW" \
  || fail "Claude action schema output 연결 부재"
grep -q 'steps\.claude-review\.outputs\.structured_output' "$WORKFLOW" \
  || fail "Claude structured_output 저장 부재"
if grep -q -- '--bare' "$WORKFLOW"; then
  fail "--bare 는 OAuth token 대신 API key 를 요구하므로 사용하면 안 됨"
fi
if grep -q 'https://api\.anthropic\.com/v1/messages' "$WORKFLOW"; then
  fail "Claude API 직접 호출이 남아 있음"
fi
grep -q '\.claude-review/result\.json' "$WORKFLOW" \
  || fail "Claude 최종 JSON 출력 파일 지정 부재"
grep -q 'jq empty \.claude-review/result\.json' "$WORKFLOW" \
  || fail "Claude 최종 JSON jq 검증 부재"
ok "check 2: pinned claude-code-action + schema + shared context 로 structured review 실행"

echo ""
echo "=== check 2b: claude workflow supports targeted context follow-up ==="
grep -q 'context_requests' "$WORKFLOW" \
  || fail "context_requests follow-up 처리 부재"
grep -q 'review-extra-context' "$WORKFLOW" \
  || fail "추가 context 디렉터리 부재"
grep -q 'MAX_CONTEXT_REQUEST_FILES=5' "$WORKFLOW" \
  || fail "context request file limit 부재"
if grep -q 'env\.MAX_CONTEXT_REQUEST_FILES' "$WORKFLOW"; then
  fail "jq env.MAX_CONTEXT_REQUEST_FILES 사용 — shell 변수가 export 되지 않아 null|tonumber 런타임 오류 (jq --argjson 으로 전달해야 함)"
fi
grep -qF -- '--argjson max "$MAX_CONTEXT_REQUEST_FILES"' "$WORKFLOW" \
  || fail "context request file limit 을 jq --argjson 으로 전달하지 않음"
ok "check 2b: targeted context follow-up 처리 존재"

echo ""
echo "=== check 3: @claude mention triggers require trusted author association ==="
trusted_expr="contains(fromJSON('[\"OWNER\",\"MEMBER\",\"COLLABORATOR\"]')"
trusted_count="$(awk -v needle="$trusted_expr" 'index($0, needle) { count++ } END { print count + 0 }' "$WORKFLOW")"
[[ "$trusted_count" == "3" ]] \
  || fail "issue/review comment/review @claude 트리거의 trusted author 제한이 3곳 모두에 없음"
grep -q 'github.event.comment.author_association' "$WORKFLOW" \
  || fail "comment 기반 @claude 트리거 author_association 제한 부재"
grep -q 'github.event.review.author_association' "$WORKFLOW" \
  || fail "review 기반 @claude 트리거 author_association 제한 부재"
ok "check 3: @claude mention 트리거가 OWNER/MEMBER/COLLABORATOR 로 제한됨"

echo ""
echo "=== check 4: PR body is not injected into the review prompt ==="
if grep -q 'PR_BODY:' "$WORKFLOW" || grep -q 'echo "\$PR_BODY"' "$WORKFLOW"; then
  fail "PR body 를 Claude review prompt 에 직접 주입하고 있음"
fi
ok "check 4: PR body 직접 주입 제거됨"

echo ""
echo "=== check 5: third-party actions are pinned ==="
if grep -qE 'uses: actions/[a-z-]+@v[0-9]+' "$WORKFLOW"; then
  fail "GitHub Actions가 mutable version tag 로 참조됨"
fi
grep -qE 'uses: actions/github-script@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "actions/github-script SHA 고정 부재"
grep -qE 'uses: actions/checkout@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "actions/checkout SHA 고정 부재"
grep -qE 'uses: actions/setup-node@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "actions/setup-node SHA 고정 부재"
ok "check 5: Actions SHA 고정됨"

echo ""
echo "=== check 6: review output is posted idempotently ==="
grep -q '<!-- claude-api-pr-review -->' "$WORKFLOW" \
  || fail "중복 방지 marker 부재"
grep -q 'issues.updateComment' "$WORKFLOW" \
  || fail "기존 리뷰 코멘트 update 경로 부재"
grep -q 'issues.createComment' "$WORKFLOW" \
  || fail "신규 리뷰 코멘트 create 경로 부재"
ok "check 6: marker 기반 update/create 코멘트 경로 존재"

echo ""
echo "=== check 7: verdict is submitted through GitHub review API ==="
grep -q 'gh pr review "\$PR_NUMBER".*--approve' "$WORKFLOW" \
  || fail "approve review 제출 경로 부재"
grep -q 'gh pr review "\$PR_NUMBER".*--request-changes' "$WORKFLOW" \
  || fail "request changes review 제출 경로 부재"
grep -q 'gh pr review "\$PR_NUMBER".*--comment' "$WORKFLOW" \
  || fail "comment review 제출 경로 부재"
grep -q 'automation_safety\.may_approve' "$WORKFLOW" \
  || fail "approve safety gate 부재"
grep -q 'confidence_score >= 80' "$WORKFLOW" \
  || fail "confidence threshold gate 부재"
ok "check 7: verdict 기반 GitHub review 제출 경로 존재"

echo ""
echo "=== check 7b: formal review submission is idempotent per (head_sha, verdict) ==="
grep -q 'marker="claude-formal-review head_sha=\$PR_HEAD_SHA verdict=\$verdict"' "$WORKFLOW" \
  || fail "formal review 중복 방지 marker 부재"
grep -q 'gh api "repos/\$GITHUB_REPOSITORY/pulls/\$PR_NUMBER/reviews"' "$WORKFLOW" \
  || fail "기존 review marker 조회 부재"
grep -q 'skipping duplicate' "$WORKFLOW" \
  || fail "중복 review 제출 skip 경로 부재"
ok "check 7b: formal review 제출이 (head_sha, verdict) 기준 멱등"

echo ""
echo "=== check 8: prompt captures token and confidence policies ==="
grep -q '토큰 최적화 정책' "$PROMPT" \
  || fail "prompt 토큰 최적화 정책 부재"
grep -q 'Confidence scoring' "$PROMPT" \
  || fail "prompt confidence scoring 정책 부재"
grep -q 'confidence_score < 80' "$PROMPT" \
  || fail "prompt confidence threshold 정책 부재"
grep -q 'submit_pr_review' "$PROMPT" \
  || fail "prompt structured tool output 규칙 부재"
ok "check 8: prompt 핵심 정책 존재"

echo ""
echo "=== check 9: privileged job checks out trusted base, not PR-controlled code ==="
if grep -qE 'ref:[[:space:]]*refs/pull/.*/(merge|head)' "$WORKFLOW"; then
  fail "권한 있는 리뷰 job이 PR merge/head ref 를 checkout → PR 이 바꾼 스크립트·prompt 가 실행될 수 있음"
fi
grep -qF 'ref: ${{ steps.pr.outputs.base_ref }}' "$WORKFLOW" \
  || fail "리뷰 job 이 trusted base ref 를 checkout 하지 않음"
ok "check 9: trusted base checkout (PR-controlled 코드 미실행)"

echo ""
echo "ALL CHECKS PASSED"
