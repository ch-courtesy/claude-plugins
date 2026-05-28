#!/usr/bin/env bash
# Claude PR review workflow contract.
#
# Static checks only: do not call GitHub, npm, or Anthropic.

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

echo "=== check 1: Claude Code OAuth token env (direct CLI), no API key, no claude-code-action ==="
grep -qE '^[[:space:]]*CLAUDE_CODE_OAUTH_TOKEN:[[:space:]]*\$\{\{[[:space:]]*secrets\.CLAUDE_CODE_OAUTH_TOKEN' "$WORKFLOW" \
  || fail "CLAUDE_CODE_OAUTH_TOKEN env secret 매핑 부재 (직접 CLI는 env 로 전달해야 함)"
grep -q 'CLAUDE_CODE_OAUTH_TOKEN secret is required' "$WORKFLOW" \
  || fail "CLAUDE_CODE_OAUTH_TOKEN 누락 시 실패 메시지 부재"
if grep -q 'ANTHROPIC_API_KEY' "$WORKFLOW"; then
  fail "ANTHROPIC_API_KEY 기반 인증이 남아 있음"
fi
if grep -q 'anthropics/claude-code-action' "$WORKFLOW"; then
  fail "claude-code-action 잔존 — 직접 CLI 로 전환 미완"
fi
if grep -qE '^[[:space:]]*id-token:[[:space:]]*write' "$WORKFLOW"; then
  fail "id-token: write 잔존 — 직접 CLI 에서는 OIDC 불필요(권한 최소화 위반)"
fi
ok "check 1: CLAUDE_CODE_OAUTH_TOKEN env + no API key + no claude-code-action + no id-token"

echo ""
echo "=== check 2: Claude CLI is pinned and run directly with shared context ==="
grep -qE 'npm install -g @anthropic-ai/claude-code@[0-9]+\.[0-9]+\.[0-9]+' "$WORKFLOW" \
  || fail "@anthropic-ai/claude-code 버전 고정 부재"
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
grep -qE 'claude -p( *\\| *$)' "$WORKFLOW" \
  || fail "claude -p 직접 호출 부재"
grep -q -- '--output-format json' "$WORKFLOW" \
  || fail "claude CLI --output-format json 지정 부재"
grep -q -- '--json-schema' "$WORKFLOW" \
  || fail "claude CLI --json-schema(클라이언트 hint) 지정 부재"
grep -q -- '--strict-mcp-config' "$WORKFLOW" \
  || fail "claude CLI --strict-mcp-config(MCP 격리) 지정 부재"
grep -qF -- '--setting-sources ""' "$WORKFLOW" \
  || fail "claude CLI --setting-sources \"\"(project/local/user 설정 차단) 지정 부재"
grep -q -- '--no-session-persistence' "$WORKFLOW" \
  || fail "claude CLI --no-session-persistence 지정 부재"
grep -qF -- '< "$prompt_file" > "$envelope"' "$WORKFLOW" \
  || fail "stdin으로 prompt 주입 / envelope 캡처 부재"
grep -q 'unset GH_TOKEN' "$WORKFLOW" \
  || fail "claude CLI 실행 전 GH_TOKEN env 제거 부재"
grep -qF 'mktemp -d' "$WORKFLOW" \
  || fail "scratch cwd(mktemp -d) 격리 부재 — 레포 CLAUDE.md/skills/MCP auto-discovery 위험"
if grep -q -- '--bare' "$WORKFLOW"; then
  fail "--bare 는 OAuth token 대신 API key 를 요구하므로 사용하면 안 됨"
fi
if grep -q 'https://api\.anthropic\.com/v1/messages' "$WORKFLOW"; then
  fail "Claude API 직접 호출이 남아 있음"
fi
ok "check 2: pinned CLI + 직접 claude -p + 격리 플래그 + shared context"

echo ""
echo "=== check 2a: model receives the schema (embedded in prompt) + raw-output rules ==="
grep -qF '<schema>' "$WORKFLOW" \
  || fail "프롬프트에 <schema> 임베드 블록 부재 (claude-code의 --json-schema 는 client-side 만이라 모델이 스키마를 봐야 함)"
grep -qF 'schema_json="$(jq -c . "$REVIEW_SCHEMA")"' "$WORKFLOW" \
  || fail "schema_json 인라인 생성(jq -c) 부재"
grep -q '## 출력 스키마' "$WORKFLOW" \
  || fail "출력 스키마 섹션 헤더 부재"
grep -q '## 응답 형식 규칙' "$WORKFLOW" \
  || fail "응답 형식 규칙(raw JSON, 펜스 금지) 섹션 부재"
grep -qF 'additionalProperties:false' "$WORKFLOW" \
  || fail "프롬프트에 additionalProperties:false 강조 부재"
ok "check 2a: 모델이 스키마와 raw-only 규칙을 직접 본다"

echo ""
echo "=== check 2b: workflow parses .result and validates required fields with fallback ==="
grep -qF 'jq -r ' "$WORKFLOW" \
  || fail "jq -r 으로 .result 추출 부재"
grep -qF 'extract_json_object' "$WORKFLOW" \
  || fail "extract_json_object 헬퍼(첫 { ~ 마지막 } 추출) 부재"
grep -qF 'write_fallback' "$WORKFLOW" \
  || fail "write_fallback 헬퍼(파싱 실패 → 합성 result.json) 부재"
grep -qE 'eligibility.*reviewed.*reason.*fallback' "$WORKFLOW" \
  || fail "fallback 합성 result 가 eligibility=reviewed + fallback reason 으로 구성되지 않음(submit 스텝이 게시하지 못함)"
grep -q 'verdict.*comment' "$WORKFLOW" \
  || fail "fallback verdict=comment 부재 — submit 스텝이 managed comment 게시를 위해 필요"
for k in eligibility verdict summary confidence reviewed_context automation_safety findings resolved_threads unresolved_threads skipped_duplicates context_requests; do
  grep -q "\"$k\"" "$WORKFLOW" \
    || fail "required 필드 키워드 \"$k\" 가 워크플로 검증/합성에 없음"
done
grep -q 'missing required fields' "$WORKFLOW" \
  || fail "필수 필드 누락 진단 메시지 부재"
grep -qF 'nested_shape_validation_error' "$WORKFLOW" \
  || fail "nested-shape validation 실패 fallback reason 부재 — top-level keys만 검증 시 Submit 단계가 깨질 수 있음"
grep -qF 'automation_safety.may_approve | type == "boolean"' "$WORKFLOW" \
  || fail "automation_safety.may_approve boolean 타입 검증 부재 (Submit 단계가 boolean 비교에 의존)"
grep -qF 'reviewed_context.diff_truncated | type == "boolean"' "$WORKFLOW" \
  || fail "reviewed_context.diff_truncated boolean 타입 검증 부재"
grep -qF 'IN("blocking","non_blocking","question")' "$WORKFLOW" \
  || fail "findings[].severity enum 검증 부재 (Submit 단계가 severity 매칭에 의존)"
grep -qF 'IN("approve","request_changes","comment","needs_context","unavailable")' "$WORKFLOW" \
  || fail "verdict enum 검증 부재"
grep -qF 'IN("guideline","bug","history","previous_pr","code_comment","cross_file")' "$WORKFLOW" \
  || fail "findings[].review_perspective enum 검증 부재 (schema required)"
grep -qF 'IN("inline","issue")' "$WORKFLOW" \
  || fail "findings[].comment_type enum 검증 부재 (schema required, 라우팅에 사용)"
grep -qF '.fingerprint | type == "string"' "$WORKFLOW" \
  || fail "findings[].fingerprint 검증 부재 (schema required, dedup 에 사용)"
grep -qF '.duplicate_of | (type == "string" or . == null)' "$WORKFLOW" \
  || fail "findings[].duplicate_of nullable 검증 부재"
grep -qF 'if .comment_type == "inline"' "$WORKFLOW" \
  || fail "inline comment_type 의 line/start_line 조건부 검증 부재 (inline 위치 정보 없으면 GitHub API 400)"
grep -qF '.line | (. == null or (type == "number" and . == floor and . >= 1))' "$WORKFLOW" \
  || fail "findings[].line 검증이 스키마 contract(integer ≥1 또는 null)를 강제하지 않음"
grep -qF '.start_line | (. == null or (type == "number" and . == floor and . >= 1))' "$WORKFLOW" \
  || fail "findings[].start_line 검증이 스키마 contract(integer ≥1 또는 null)를 강제하지 않음"
ok "check 2b: .result 파싱 + top-level + nested-shape + schema-required findings 필드 검증 + 실패 시 합성 fallback"

echo ""
echo "=== check 2c: targeted context follow-up ==="
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
grep -qF 'find .review-extra-context -type f -print -quit' "$WORKFLOW" \
  || fail "추가 context 존재 판정이 find -print -quit 패턴이 아님(파일 누수/잘못된 판정 위험)"
grep -q 'truncated at 400 lines' "$WORKFLOW" \
  || fail "추가 context 파일 절단 표시(400줄) 부재"
ok "check 2c: targeted context follow-up + find -print -quit + 400줄 절단 마커"

echo ""
echo "=== check 2d: configurable output language and model ==="
grep -qE 'CLAUDE_REVIEW_LANG:[[:space:]]*\$\{\{[[:space:]]*vars\.CLAUDE_REVIEW_LANG' "$WORKFLOW" \
  || fail "CLAUDE_REVIEW_LANG vars 매핑 부재"
grep -q '## 출력 언어' "$WORKFLOW" \
  || fail "출력 언어 섹션 부재"
grep -qE 'CLAUDE_REVIEW_MODEL:[[:space:]]*\$\{\{[[:space:]]*vars\.CLAUDE_REVIEW_MODEL' "$WORKFLOW" \
  || fail "CLAUDE_REVIEW_MODEL vars 매핑 부재"
grep -qF -- '--model "$CLAUDE_REVIEW_MODEL"' "$WORKFLOW" \
  || fail "claude CLI --model 에 CLAUDE_REVIEW_MODEL 전달 부재"
grep -qE '\[\[[[:space:]]*-n[[:space:]]+"\$REVIEW_INCREMENTAL_BASE"[[:space:]]*\]\][[:space:]]*&&[[:space:]]*printf' "$WORKFLOW" \
  || fail "incremental base SHA 출력이 조건부가 아님(빈 값에서 비어 있는 라인 노출)"
ok "check 2d: CLAUDE_REVIEW_LANG·CLAUDE_REVIEW_MODEL 설정 가능 + 조건부 incremental base"

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
grep -q 'structured output' "$PROMPT" \
  || fail "prompt structured output 규칙 부재"
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
echo "=== check 10: checkout credentials cleared before claude CLI execution ==="
unset_extraheader_line="$(awk 'index($0, "git config --local --unset-all http.https://github.com/.extraheader") { print NR; exit }' "$WORKFLOW")"
claude_cli_line="$(awk '/claude -p \\/ { print NR; exit }' "$WORKFLOW")"
[[ -n "$unset_extraheader_line" ]] \
  || fail "claude CLI 실행 전 checkout credential extraheader 제거 부재"
[[ -n "$claude_cli_line" ]] \
  || fail "claude -p 호출 라인 위치 미식별"
(( unset_extraheader_line < claude_cli_line )) \
  || fail "extraheader 제거가 claude -p 이후에 위치함"
ok "check 10: claude CLI 실행 전 checkout credential extraheader 제거"

echo ""
echo "ALL CHECKS PASSED"
