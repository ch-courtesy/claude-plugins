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
grep -qF 'PR_BASE_SHA="$PR_BASE_SHA"' "$WORKFLOW" \
  || fail "helper 호출에 PR_BASE_SHA 미전달 — thread/incremental diff base 가 HEAD~1 로 추락함"
grep -q 'source \.review-context/context-mode\.env' "$WORKFLOW" \
  || fail "review context mode env 로드 부재"
grep -q 'REVIEW_CONTEXT_MODE' "$WORKFLOW" \
  || fail "prompt 에 review context mode 주입 부재"
grep -qE 'uses: anthropics/claude-code-action@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "anthropics/claude-code-action SHA 고정 부재"
grep -q 'claude_code_oauth_token:.*secrets\.CLAUDE_CODE_OAUTH_TOKEN' "$WORKFLOW" \
  || fail "claude_code_oauth_token input 매핑 부재"
if grep -q -- '--json-schema' "$WORKFLOW"; then
  fail "--json-schema 강제 구조화 출력 채널 의존이 남아 있음 (prompt schema 방식으로 전환해야 함)"
fi
if grep -q 'structured_output' "$WORKFLOW"; then
  fail "structured_output 강제 채널 의존이 남아 있음 (execution_file 결과 텍스트 파싱으로 전환해야 함)"
fi
grep -qF 'cat "$REVIEW_SCHEMA"' "$WORKFLOW" \
  || fail "공유 스키마(REVIEW_SCHEMA)를 프롬프트 본문에 싣지 않음 (cat \"\$REVIEW_SCHEMA\" 부재)"
grep -q 'steps\.claude-review\.outputs\.execution_file' "$WORKFLOW" \
  || fail "1차 리뷰 결과를 claude-code-action execution_file 에서 가져오지 않음"
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
ok "check 2: pinned claude-code-action + prompt schema + shared context 로 review 실행 (강제 구조화 출력 채널 미사용)"

echo ""
echo "=== check 2c: model result text is parsed into JSON with core-field validation ==="
grep -q 'JSON 객체를 추출' "$WORKFLOW" \
  || fail "모델 결과 텍스트에서 JSON 추출 실패 시 명확한 오류 부재"
grep -q '필수 필드' "$WORKFLOW" \
  || fail "추출 JSON 핵심 필드 확인(필수 필드) 부재"
for field in verdict eligibility findings automation_safety reviewed_context; do
  grep -q "\"$field\"" "$WORKFLOW" \
    || fail "핵심 필드 확인 목록에 \"$field\" 부재"
done
grep -q 'steps\.claude-follow-up-review\.outputs\.execution_file' "$WORKFLOW" \
  || fail "2차(follow-up) 리뷰도 execution_file 결과 텍스트 파싱을 쓰지 않음"
ok "check 2c: 결과 텍스트 JSON 추출 + 핵심 필드 검증 (1차/2차 동일)"

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
echo "=== check 7: verdict submission with graceful degradation ==="
grep -q 'findings_count=' "$WORKFLOW" \
  || fail "findings count 계산 부재"
grep -q 'No review output to post' "$WORKFLOW" \
  || fail "eligibility != reviewed 시 skip 경로 부재"
grep -q 'approve_without_body=' "$WORKFLOW" \
  || fail "finding 없는 approve 의 무본문 처리 부재"
grep -q 'state == "APPROVED"' "$WORKFLOW" \
  || fail "동일 head approve 중복 방지 부재"
grep -Fq 'user.login == "github-actions[bot]"' "$WORKFLOW" \
  || fail "approve 중복 체크가 봇 자신 리뷰로 제한되지 않음"
grep -q 'touch \.claude-review/approval-failed' "$WORKFLOW" \
  || fail "approve 실패 시 managed comment fallback marker 부재"
grep -A3 'touch \.claude-review/approval-failed' "$WORKFLOW" | grep -q 'exit 0' \
  || fail "approve 실패 후 정상 종료(다음 step 진행) 부재"
if grep -q 'submit_review --approve' "$WORKFLOW"; then
  fail "finding 없는 approve 는 body 없는 전용 경로만 사용해야 함"
fi
grep -q 'submit_review --request-changes' "$WORKFLOW" \
  || fail "request changes review 제출 경로 부재"
grep -q 'submit_review --comment' "$WORKFLOW" \
  || fail "comment review 제출 경로 부재"
grep -q 'gh pr review "\$PR_NUMBER".*--body-file "\$body"' "$WORKFLOW" \
  || fail "submit_review 의 gh pr review 호출 부재 (graceful degradation)"
grep -q 'No managed Claude review comment to post' "$WORKFLOW" \
  || fail "managed comment 게이트(미reviewed/무findings 생략) 부재"
grep -q 'automation_safety\.may_approve' "$WORKFLOW" \
  || fail "approve safety gate 부재"
grep -q 'confidence_score >= 80' "$WORKFLOW" \
  || fail "confidence threshold gate 부재"
ok "check 7: verdict 제출 + graceful degradation + managed comment 게이트"

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
grep -q 'JSON 객체' "$PROMPT" \
  || fail "prompt JSON-only 출력 지시 부재"
grep -q '코드펜스' "$PROMPT" \
  || fail "prompt 코드펜스 금지 지시 부재"
if grep -qE 'submit_pr_review|--json-schema|structured_output' "$PROMPT"; then
  fail "prompt 가 강제 구조화 출력 채널/도구를 지시하고 있음 (JSON-only 출력으로 전환해야 함)"
fi
ok "check 8: prompt 핵심 정책 + JSON-only 출력 지시 존재"

echo ""
echo "=== check 9: privileged job checks out trusted base, not PR-controlled code ==="
if grep -qE 'ref:[[:space:]]*refs/pull/.*/(merge|head)' "$WORKFLOW"; then
  fail "권한 있는 리뷰 job이 PR merge/head ref 를 checkout → PR 이 바꾼 스크립트·prompt 가 실행될 수 있음"
fi
grep -qF 'ref: ${{ steps.pr.outputs.base_ref }}' "$WORKFLOW" \
  || fail "리뷰 job 이 trusted base ref 를 checkout 하지 않음"
ok "check 9: trusted base checkout (PR-controlled 코드 미실행)"

echo ""
echo "=== check 10: checkout credentials cleared before model action ==="
unset_extraheader_line="$(awk 'index($0, "git config --local --unset-all http.https://github.com/.extraheader") { print NR; exit }' "$WORKFLOW")"
model_action_line="$(awk '/uses: anthropics\/claude-code-action@/ { print NR; exit }' "$WORKFLOW")"
[[ -n "$unset_extraheader_line" ]] \
  || fail "모델 action 전 checkout credential extraheader 제거 부재"
(( unset_extraheader_line < model_action_line )) \
  || fail "extraheader 제거가 첫 claude-code-action 이후에 위치함"
ok "check 10: 모델 action 전 checkout credential extraheader 제거"

echo ""
echo "ALL CHECKS PASSED"
