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
grep -qF 'IN("approve","comment","needs_context","unavailable")' "$WORKFLOW" \
  || fail "verdict enum 검증 부재 (request_changes 제거됨)"
grep -qF 'IN("guideline","bug","history","previous_pr","code_comment","cross_file")' "$WORKFLOW" \
  || fail "findings[].review_perspective enum 검증 부재 (schema required)"
grep -qF 'IN("inline")' "$WORKFLOW" \
  || fail "findings[].comment_type enum 검증이 inline 전용이 아님 (inline-only 정책: 모든 finding 은 inline)"
if grep -qF 'IN("inline","issue")' "$WORKFLOW"; then
  fail "comment_type 에 issue 가 잔존 — inline-only 정책에서 finding 은 issue 채널로 가지 않음"
fi
# findings[].fingerprint 는 모델이 생성하지 않으므로(워크플로가 결정론적으로 계산)
# schema·검증에서 제거되었다 — 모델 출력에 fingerprint 가 있으면 안 된다.
if grep -qF '.fingerprint | type == "string"' "$WORKFLOW"; then
  fail "findings[].fingerprint 검증 잔존 — 결정론 계산 전환으로 모델 fingerprint 의존 제거되어야 함 (AC1)"
fi
grep -qF '.duplicate_of | (type == "string" or . == null)' "$WORKFLOW" \
  || fail "findings[].duplicate_of nullable 검증 부재"
grep -qF 'and ((.line | type == "number") or (.start_line | type == "number"))' "$WORKFLOW" \
  || fail "모든 finding 의 line/start_line 필수 검증 부재 (inline-only: 모든 finding 이 변경 라인에 anchor 되어야 함, 없으면 fallback)"
if grep -qF 'if .comment_type == "inline"' "$WORKFLOW"; then
  fail "comment_type 조건부 line 검증 잔존 — inline-only 정책에서는 모든 finding 이 무조건 line 을 가져야 함"
fi
grep -qF '.line | (. == null or (type == "number" and . == (. | floor) and . >= 1))' "$WORKFLOW" \
  || fail "findings[].line 검증이 스키마 contract(integer ≥1 또는 null)를 강제하지 않음"
grep -qF '.start_line | (. == null or (type == "number" and . == (. | floor) and . >= 1))' "$WORKFLOW" \
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
echo "=== check 7: verdict submission via Pulls REST API with inline-only comments (APPROVE/COMMENT only) ==="
# Submit step is a github-script step that calls pulls.createReview directly
# so it can post inline review comments. Official event is APPROVE or COMMENT
# only — REQUEST_CHANGES is abolished (AC10/AC11).
grep -qF 'github.rest.pulls.createReview' "$WORKFLOW" \
  || fail "Pulls REST createReview 호출 부재 — inline comments 게시 불가 (gh pr review 로는 inline 미지원)"
grep -qF 'comments: inlineComments' "$WORKFLOW" \
  || fail "createReview 의 comments[] 배열에 inline findings 전달 부재"
# inline-only 정책: 모든 finding 이 inline. issue 채널 분기/렌더가 없어야 한다.
grep -qF 'inline-only' "$WORKFLOW" \
  || fail "inline-only 정책 주석/마커 부재 (모든 finding 을 inline 으로 게시한다는 의도 명시 필요)"
if grep -qF 'issueFindings' "$WORKFLOW"; then
  fail "issueFindings 분기 잔존 — inline-only 정책에서 issue 채널 finding 라우팅 금지"
fi
if grep -qF 'Issue-level findings' "$WORKFLOW"; then
  fail "'Issue-level findings' 렌더 잔존 — issue-level 코멘트에 finding 평가 본문 포함 금지 (AC2)"
fi
grep -qF "side: 'RIGHT'" "$WORKFLOW" \
  || fail "inline comment 의 side='RIGHT' 지정 부재"
grep -qF 'start_line' "$WORKFLOW" \
  || fail "multi-line inline comment 의 start_line 처리 부재"
grep -qF "event === 'APPROVE'" "$WORKFLOW" \
  || fail "APPROVE event 분기 부재"
# AC16(e): REQUEST_CHANGES review event 를 제출하는 분기가 존재하면 실패.
if grep -qF 'REQUEST_CHANGES' "$WORKFLOW"; then
  fail "REQUEST_CHANGES 잔존 — 공식 review event 는 APPROVE/COMMENT 만 (AC10/AC11)"
fi
grep -qF "fs.writeFileSync('.claude-review/approval-failed'" "$WORKFLOW" \
  || fail "APPROVE 실패 시 approval-failed marker 부재"
grep -qF "'github-actions[bot]'" "$WORKFLOW" \
  || fail "self-review 식별 (github-actions[bot]) 부재"
grep -qF 'automation_safety' "$WORKFLOW" \
  || fail "automation_safety gate 부재"
grep -qF 'confidence_score' "$WORKFLOW" \
  || fail "confidence_score 부재"
# 요약(issue-level) managed comment 는 approve 일 때만. inline-fallback 경로 제거(AC2/AC3).
grep -qF 'Managed Claude review comment is only posted on verdict=approve' "$WORKFLOW" \
  || fail "managed comment 게이트가 verdict=approve 전용이 아님 (AC3)"
grep -qF "result.verdict === 'approve'" "$WORKFLOW" \
  || fail "showFullBody 결정이 verdict=approve 조건을 사용하지 않음"
if grep -qF 'inlineFallback' "$WORKFLOW"; then
  fail "inlineFallback 경로 잔존 — createReview 실패 시 finding 을 issue 코멘트로 덤프하면 AC2 위반"
fi
if grep -qF 'inline-fallback-needed' "$WORKFLOW"; then
  fail "inline-fallback-needed marker 잔존 — inline-only 정책에서 제거되어야 함"
fi
grep -qF '!showFullBody' "$WORKFLOW" \
  || fail "early-return 조건이 showFullBody 변수를 사용하지 않음"
# supersede stale approve managed comment when latest verdict is non-approve
grep -qF '이후 리뷰로 대체됨 (현재 결과' "$WORKFLOW" \
  || fail "verdict!=approve 일 때 옛 approve managed comment supersede 분기 부재 (stale approve 가 PR 대화에 남음)"
grep -qF 'Superseded stale managed comment' "$WORKFLOW" \
  || fail "supersede core.info log 부재"
ok "check 7: createReview + inline-only findings + APPROVE/COMMENT only + approve-only managed comment"

echo ""
echo "=== check 7b: formal review idempotent per (head_sha, verdict) ==="
grep -qF '<!-- ${prefix} head_sha=${head_sha} verdict=${verdict} -->' "$WORKFLOW" \
  || fail "formal review 중복 방지 marker template 부재"
grep -qF 'github.rest.pulls.listReviews' "$WORKFLOW" \
  || fail "기존 review 조회 (pulls.listReviews) 부재"
grep -qF "r.state === 'APPROVED' && r.commit_id === head_sha" "$WORKFLOW" \
  || fail "동일 head_sha approve 중복 방지 부재"
grep -qF 'already exists; skipping duplicate' "$WORKFLOW" \
  || fail "marker 기반 중복 review skip 메시지 부재"
ok "check 7b: marker + APPROVED state + head_sha 기준 멱등 (REST botLogin 식별 불변, AC14)"

echo ""
echo "=== check 7c: dismiss-on-approve(CHANGES_REQUESTED dismiss) 로직 제거됨 (AC13) ==="
if grep -qF 'github.rest.pulls.dismissReview' "$WORKFLOW"; then
  fail "dismissReview 잔존 — dismiss-on-approve 로직 제거 필요 (AC13)"
fi
if grep -qF 'CHANGES_REQUESTED' "$WORKFLOW"; then
  fail "CHANGES_REQUESTED 잔존 — REQUEST_CHANGES 폐지로 거둘 대상 없음 (AC13)"
fi
if grep -qF 'verdictIsApprove' "$WORKFLOW"; then
  fail "verdictIsApprove 게이트 잔존 — self thread resolve 는 verdict 무관이어야 함 (AC6)"
fi
ok "check 7c: dismiss-on-approve / CHANGES_REQUESTED 제거됨"

echo ""
echo "=== check 7e: finding-unit (fingerprint) self inline thread resolve, verdict 무관 (AC1~AC9) ==="
# AC1/AC9: 게시 inline 마커가 기존 self-식별 substring 을 보존하면서 finding fingerprint 운반.
grep -qF '<!-- claude-review-inline' "$WORKFLOW" \
  || fail "inline self-식별 마커 substring(<!-- claude-review-inline) 부재 (AC9 기존 식별 보존)"
# AC1: 게시 inline 마커는 워크플로가 결정론적으로 계산한 fingerprint 를 운반한다.
grep -qF 'fingerprint=${computeFingerprint(f)}' "$WORKFLOW" \
  || fail "게시 inline 마커가 결정론적 computeFingerprint(f) 를 운반하지 않음 (AC1)"
if grep -qF 'fingerprint=${f.fingerprint}' "$WORKFLOW"; then
  fail "게시 마커가 모델 자유 생성 f.fingerprint 를 운반 — 결정론 계산으로 전환되어야 함 (AC1)"
fi
# AC3: resolved_threads 소비 1차 경로.
grep -qF 'resolved_threads' "$WORKFLOW" \
  || fail "resolved_threads 소비 경로 부재 (AC3) — 모델 판단을 thread resolve 로 매핑 못함"
grep -qF 'resolvedFingerprints' "$WORKFLOW" \
  || fail "resolved_threads fingerprint 집합(resolvedFingerprints) 부재 (AC3)"
# AC4: fingerprint-부재 fallback 2차 경로.
grep -qF 'findingFingerprints' "$WORKFLOW" \
  || fail "이번 라운드 findings fingerprint 집합(findingFingerprints) 부재 (AC4 fallback)"
# AC6: verdict 게이트 밖에서 매 실행 resolve (sentinel 마커).
grep -qF 'regardless of verdict' "$WORKFLOW" \
  || fail "resolve 가 verdict 무관 실행임을 명시하는 마커(regardless of verdict) 부재 (AC6)"
grep -qF 'resolveReviewThread' "$WORKFLOW" \
  || fail "GraphQL resolveReviewThread mutation 호출 부재 — self inline thread 자동 resolve 안 됨"
grep -qF 'botLoginGql' "$WORKFLOW" \
  || fail "GraphQL author login 형식 정규화(botLoginGql) 부재 (AC9)"
grep -qF 'isResolved' "$WORKFLOW" \
  || fail "isResolved 조건 검사 부재 (AC8 이미 resolved thread skip)"
grep -qF 'reviewThreads(first: 100)' "$WORKFLOW" \
  || fail "GraphQL reviewThreads 쿼리 부재"
ok "check 7e: fingerprint 운반 + resolved_threads 1차 + fallback 2차 + verdict 무관 resolve"

echo ""
echo "=== check 7g: 결정론적 fingerprint 계산 — file+perspective+normalized title, 줄번호 비의존 (AC1/AC2/AC7) ==="
# AC1/AC2: fingerprint 는 finding 의 안정 속성(파일 경로·리뷰 관점·정규화 제목)에서만
# 결정론적으로 계산되며 line/start_line 에는 의존하지 않는다 — 줄 이동에도 동일 fp.
grep -qF 'computeFingerprint' "$WORKFLOW" \
  || fail "결정론적 fingerprint 계산 함수(computeFingerprint) 부재 (AC1)"
grep -qF 'crypto' "$WORKFLOW" \
  || fail "fingerprint 해시 계산(crypto) 부재 (AC1)"
grep -qF "[f.file || '', f.review_perspective || '', normalizeTitle(f.title)]" "$WORKFLOW" \
  || fail "fingerprint 입력이 file+review_perspective+normalized title 로 한정되지 않음 (AC1 제약)"
# 정규화 방식은 두 워크플로에서 동일해야 한다(제약). 정확한 구현 라인을 잠근다.
grep -qF "replace(/[^\\p{L}\\p{N}]+/gu, ' ')" "$WORKFLOW" \
  || fail "제목 정규화(문장부호/공백 → 단일 공백) 구현 부재 또는 불일치 (제약: 두 워크플로 동일)"
grep -qF "normalize('NFKC')" "$WORKFLOW" \
  || fail "제목 정규화 NFKC 부재 또는 불일치 (제약: 두 워크플로 동일)"
# 줄 비의존: findingFingerprints 가 모델 f.fingerprint 가 아니라 computeFingerprint 로 산정.
grep -qF 'findings.map((f) => computeFingerprint(f))' "$WORKFLOW" \
  || grep -qF 'findings.map(computeFingerprint)' "$WORKFLOW" \
  || fail "findingFingerprints 가 결정론적 computeFingerprint 로 산정되지 않음 (AC4)"
ok "check 7g: 결정론적 fingerprint(file+perspective+title), 줄번호 비의존"

echo ""
echo "=== check 7f: request_changes verdict 어휘 제거 (workflow 검증) (AC12/AC16f) ==="
# may_request_changes 필드(automation_safety)는 유지(non-goal). 그 외 request_changes 토큰 금지.
if grep -oE '[a-z_]*request_changes' "$WORKFLOW" | grep -qvE '^may_request_changes$'; then
  fail "request_changes verdict 어휘 잔존 (may_request_changes 외) — workflow verdict 검증/분기에서 제거 필요 (AC12)"
fi
ok "check 7f: workflow verdict 어휘에 request_changes 없음 (may_request_changes 만 잔존)"

echo ""
echo "=== check 7d: managed comment 은 finding 평가 본문을 렌더하지 않는다 (inline-only) ==="
# inline-only 정책: finding 평가는 inline 코멘트 전용. managed(issue-level) comment 에
# finding 상세를 렌더하던 inlineDetailText / renderIssue 경로는 제거되어야 한다 (AC2/AC4).
if grep -qF 'inlineDetailText' "$WORKFLOW"; then
  fail "inlineDetailText 잔존 — managed comment 에 inline finding 상세 렌더 금지 (AC2)"
fi
if grep -qF 'renderIssue' "$WORKFLOW"; then
  fail "renderIssue 잔존 — issue-level 코멘트에 finding 평가 본문 렌더 금지 (AC2)"
fi
if grep -qF 'review submission failed; included here for visibility' "$WORKFLOW"; then
  fail "inline-fallback 본문 헤더 잔존 — inline-only 정책에서 제거되어야 함"
fi
ok "check 7d: managed comment 에 finding 평가 렌더 경로 제거됨"

echo ""
echo "=== check 8a: 출력 언어 untrusted block 끝에 재강조 (영어 응답 예방) ==="
grep -qF '## 마지막 재강조 (절대 위반 금지)' "$WORKFLOW" \
  || fail "마지막 재강조 섹션 부재 — 모델이 untrusted PR diff 뒤에서 출력 언어 지시 흘릴 수 있음"
grep -qF '영어 등 다른 언어로 작성하면 안 됩니다' "$WORKFLOW" \
  || fail "출력 언어 명시적 강제 라인 부재"
grep -qF '"$CLAUDE_REVIEW_LANG"' "$WORKFLOW" \
  || fail "재강조 라인이 CLAUDE_REVIEW_LANG 변수를 사용하지 않음"
ok "check 8a: untrusted block 끝에 출력 언어 재강조"

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
echo "=== check 8b: inline-only 코멘트 정책 (prompt + schema) ==="
# 모든 finding 은 inline 코멘트로만. anchor 불가 finding 도 가장 가까운 변경 라인에 inline,
# 본문에 실제 위치 명시. issue-level 코멘트로 finding 을 보고하지 않는다 (AC1/AC2/AC5).
grep -q 'inline' "$PROMPT" \
  || fail "prompt inline 코멘트 정책 부재"
grep -q '가장 가까운 변경' "$PROMPT" \
  || fail "prompt 에 anchor 불가 finding 을 가장 가까운 변경 라인에 inline 으로 붙이는 지침 부재 (AC5)"
grep -q '실제 위치' "$PROMPT" \
  || fail "prompt 에 inline 본문에 실제 문제 위치(파일·라인) 명시 지침 부재 (AC5)"
if grep -q 'issue-level comment로 보고' "$PROMPT"; then
  fail "prompt 가 finding 을 issue-level comment 로 보고하도록 지시함 — inline-only 정책 위반"
fi
grep -q 'inline comment로만 보고' "$PROMPT" \
  || fail "prompt inline-only 보고 지침 부재 (모든 finding 은 inline)"
# schema: comment_type enum 은 inline 전용
grep -qF '"inline"' "$SCHEMA" \
  || fail "schema comment_type 에 inline 값 부재"
if grep -qF '"issue"' "$SCHEMA"; then
  fail "schema comment_type enum 에 issue 잔존 — inline-only 정책에서 제거되어야 함"
fi
ok "check 8b: prompt·schema 가 inline-only + 강제 anchoring 정책을 반영"

echo ""
echo "=== check 8c: resolved_threads 채우기 지시 + request_changes 어휘 제거 (prompt·schema) ==="
# AC2: 기존 self thread 마커 fingerprint 근거로 resolved_threads 를 채우라는 지시.
grep -q 'resolved_threads' "$PROMPT" \
  || fail "prompt 에 resolved_threads 기록 지시 부재 (AC2)"
grep -q 'fingerprint' "$PROMPT" \
  || fail "prompt 에 fingerprint 근거 지시 부재 (AC2)"
# AC12/AC16(f): request_changes 어휘가 prompt·schema verdict enum 에서 제거.
if grep -qF 'request_changes' "$PROMPT"; then
  fail "prompt 에 request_changes 어휘 잔존 — 모델이 산출하지 않도록 제거 필요 (AC12)"
fi
if grep -oE '[a-z_]*request_changes' "$SCHEMA" | grep -qvE '^may_request_changes$'; then
  fail "schema verdict enum 에 request_changes 잔존 (AC12)"
fi
grep -q 'may_request_changes' "$SCHEMA" \
  || fail "may_request_changes 필드가 schema 에서 제거됨 — non-goal: 미사용으로 남기되 유지해야 함"
ok "check 8c: resolved_threads 지시 + request_changes 어휘 제거 (may_request_changes 필드 유지)"

echo ""
echo "=== check 8e: 프롬프트 마커 형식이 실제 게시·매칭 마커와 일치 (AC5/AC7) ==="
# AC5: 프롬프트가 모델에게 기존 self thread fingerprint 출처로 안내하는 마커 형식은,
# 워크플로가 실제 게시(fingerprintMarker)하고 resolve 시 매칭(fpRe)하는 마커와 동일해야 한다.
# 워크플로 실제 마커: <!-- claude-review-inline fingerprint=... -->
grep -qF 'claude-review-inline fingerprint=' "$PROMPT" \
  || fail "프롬프트가 실제 게시·매칭 마커 형식(claude-review-inline fingerprint=)을 가리키지 않음 (AC5)"
# 어긋난 옛 JSON 마커 형식(<!-- claude-review: {json} -->)은 제거되어야 한다.
if grep -qF '<!-- claude-review:' "$PROMPT"; then
  fail "프롬프트에 옛 JSON 마커 형식(<!-- claude-review:) 잔존 — 실제 마커와 어긋남 (AC5)"
fi
# 프롬프트는 모델이 fingerprint 를 생성하지 않음을 반영해야 한다(줄 기반 생성 지시 제거).
if grep -q 'changed line' "$PROMPT"; then
  fail "프롬프트에 changed line 기반 fingerprint 생성 지시 잔존 — 결정론 계산은 워크플로 소관 (AC1)"
fi
# 워크플로의 게시 마커와 매칭 정규식이 동일 substring 을 공유하는지(자체 정합) 확인.
grep -qF 'claude-review-inline fingerprint=' "$WORKFLOW" \
  || fail "워크플로 마커 substring(claude-review-inline fingerprint=)이 프롬프트 안내와 불일치 (AC5)"
ok "check 8e: 프롬프트 마커 == 실제 게시·매칭 마커"

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
echo "=== check 11: PR 게시 보일러플레이트 한국어화 (SPEC 2026-05-31) ==="
# AC1/AC6: 섹션 헤더 한국어. PR 코멘트 본문 헤더(## 접두)만 검사 — 워크플로 name 은 제외.
grep -qF '## Claude PR 리뷰' "$WORKFLOW" \
  || fail "한국어 섹션 헤더 '## Claude PR 리뷰' 부재"
if grep -qF '## Claude PR Review' "$WORKFLOW"; then
  fail "영어 섹션 헤더 '## Claude PR Review' 잔존"
fi
# AC1: approve 안내 문구 한국어.
grep -qF '_승인 — 지적 사항은 인라인 코멘트 참조._' "$WORKFLOW" \
  || fail "한국어 승인 안내 문구 부재"
if grep -qF 'Approved by automated review' "$WORKFLOW"; then
  fail "영어 승인 안내 문구 잔존"
fi
# AC2: summary 없을 때 기본 라벨 한국어.
grep -qF '승인 — 차단 지적 없음' "$WORKFLOW" \
  || fail "한국어 기본 승인 라벨 '승인 — 차단 지적 없음' 부재"
if grep -qF 'Approved — no blocking findings.' "$WORKFLOW"; then
  fail "영어 기본 승인 라벨 잔존"
fi
# AC3: 토큰 권한으로 정식 승인 미제출 안내 한국어.
grep -qF '승인 가능 — 단, 토큰 권한으로 정식 승인 미제출' "$WORKFLOW" \
  || fail "한국어 토큰 승인 실패 안내 부재"
if grep -qF 'could not be submitted by this workflow token' "$WORKFLOW"; then
  fail "영어 토큰 승인 실패 안내 잔존"
fi
# AC4: 스키마 파싱 실패 fallback 요약 한국어.
grep -qF '리뷰 출력 파싱 실패:' "$WORKFLOW" \
  || fail "한국어 파싱 실패 fallback 요약 부재"
if grep -qF 'could not be parsed against the schema' "$WORKFLOW"; then
  fail "영어 파싱 실패 fallback 요약 잔존"
fi
# AC5: verdict 표시 줄 한국어 라벨. 단, 숨김 마커 verdict enum 은 보존.
grep -qF '결과: 승인' "$WORKFLOW" \
  || fail "한국어 verdict 표시 줄 '결과: 승인' 부재"
if grep -qF 'Verdict: `approve`' "$WORKFLOW"; then
  fail "영어 verdict 표시 줄 'Verdict: \`approve\`' 잔존"
fi
# AC5 제약: 숨김 마커의 verdict enum 값(verdict=...) 은 변경 금지.
grep -qF 'head_sha=${head_sha} verdict=${verdict}' "$WORKFLOW" \
  || fail "숨김 멱등성 마커의 verdict enum 바인딩이 변경됨 (멱등성·승인 게이팅 위험)"
ok "check 11: 보일러플레이트 한국어화 + 숨김 마커/enum 보존"

echo ""
echo "=== check 12: GitHub App 설치 토큰 발급 + identity 통일 + graceful fallback + self-trigger 게이트 (SPEC 2026-05-31 app-token-approve) ==="
# AC1/제약(토큰 발급 방식): actions/create-github-app-token 으로 단명 설치 토큰 발급, SHA 고정.
grep -qE 'uses: actions/create-github-app-token@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "actions/create-github-app-token SHA 고정 발급 스텝 부재 (단명 설치 토큰, 장기 PAT 금지)"
grep -qF 'id: app-token' "$WORKFLOW" \
  || fail "App 토큰 스텝 id(app-token) 부재 — outputs.token 참조 불가"
# AC5/제약(graceful degradation): 시크릿 없으면 스텝 skip, 실패해도 job 중단 금지.
grep -qF 'REVIEW_APP_ID' "$WORKFLOW" \
  || fail "App 토큰 발급 게이트(REVIEW_APP_ID 시크릿 존재 판정) 부재 — 시크릿 미구성 환경 graceful skip 불가 (AC5)"
grep -qF 'continue-on-error: true' "$WORKFLOW" \
  || fail "App 토큰 발급 실패 시 job 중단 방지(continue-on-error) 부재 (AC5)"
# AC1/AC2/제약(identity 통일): 게시 스텝 토큰이 App 토큰 우선·없으면 기본 토큰.
fallback_count="$(grep -cF 'steps.app-token.outputs.token || github.token' "$WORKFLOW")"
[[ "$fallback_count" -ge 2 ]] \
  || fail "게시 스텝 github-token 이 App-토큰-or-기본 토큰 fallback 표현식을 쓰지 않음 (Submit·Post 최소 2곳, 현재 $fallback_count) (AC2/AC5)"
# AC3/제약(봇 로그인 동적 해석): App 봇 슬러그로 botLogin 해석, 기본 토큰 시 github-actions[bot].
grep -qF 'app-slug' "$WORKFLOW" \
  || fail "App 봇 로그인 동적 해석용 app-slug 출력 사용 부재 (AC3)"
grep -qF 'process.env.APP_SLUG' "$WORKFLOW" \
  || fail "게시/식별 스텝이 APP_SLUG env 로 봇 로그인 동적 해석 안 함 (AC3)"
grep -qF "'github-actions[bot]'" "$WORKFLOW" \
  || fail "기본 토큰 시 botLogin fallback(github-actions[bot]) 부재 (AC3 위험 분기)"
# AC4/제약(self-trigger 차단): 게이트가 App 봇 identity 가 게시한 이벤트도 배제(3 이벤트 분기).
appbot_gate_count="$(grep -cF 'vars.REVIEW_APP_BOT_LOGIN' "$WORKFLOW")"
[[ "$appbot_gate_count" -ge 3 ]] \
  || fail "self-trigger 게이트에 App 봇(vars.REVIEW_APP_BOT_LOGIN) 배제가 3개 이벤트 분기 모두에 없음 (현재 $appbot_gate_count) (AC4)"
ok "check 12: App 설치 토큰 발급 + identity 통일 + 봇 로그인 동적 해석 + self-trigger 게이트"

echo ""
echo "ALL CHECKS PASSED"
