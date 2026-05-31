#!/usr/bin/env bash
# Codex PR review workflow authentication contract.
#
# Static checks only: do not call GitHub, npm, or Codex.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKFLOW="$REPO_ROOT/.github/workflows/codex-review.yml"
PROMPT="$REPO_ROOT/.github/prompts/codex-pr-review.ko.md"
SCHEMA="$REPO_ROOT/.github/prompts/codex-pr-review.schema.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$WORKFLOW" ]] || fail "$WORKFLOW 부재"
[[ -f "$PROMPT" ]] || fail "$PROMPT 부재"
[[ -f "$SCHEMA" ]] || fail "$SCHEMA 부재"

echo "=== check 1: auth.json secret is restored for Codex CLI ==="
grep -q 'CODEX_AUTH_JSON:.*secrets\.CODEX_AUTH_JSON' "$WORKFLOW" \
  || fail "CODEX_AUTH_JSON secret env 매핑 부재"
grep -q 'mkdir -p "\$HOME/\.codex"' "$WORKFLOW" \
  || fail "~/.codex 디렉토리 생성 부재"
grep -q 'printf .*> "\$HOME/\.codex/auth\.json"' "$WORKFLOW" \
  || fail "~/.codex/auth.json 복원 부재"
grep -q 'unset CODEX_AUTH_JSON' "$WORKFLOW" \
  || fail "auth.json 작성 후 CODEX_AUTH_JSON env 제거 부재"
ok "check 1: CODEX_AUTH_JSON secret을 ~/.codex/auth.json 으로 복원"

echo ""
echo "=== check 2: auth directory is created under restrictive umask ==="
umask_line="$(grep -n 'umask 077' "$WORKFLOW" | head -1 | cut -d: -f1)"
mkdir_line="$(grep -n 'mkdir -p "\$HOME/\.codex"' "$WORKFLOW" | head -1 | cut -d: -f1)"
[[ -n "$umask_line" ]] || fail "umask 077 설정 부재"
[[ -n "$mkdir_line" ]] || fail "~/.codex 디렉토리 생성 부재"
(( umask_line < mkdir_line )) \
  || fail "umask 077 이 ~/.codex mkdir 이후에 설정됨"
ok "check 2: umask 077 이 ~/.codex 생성 전에 적용됨"

echo ""
echo "=== check 3: codex exec uses prompt stdin and JSON schema ==="
grep -q 'REVIEW_BASE="$(git merge-base "origin/\$PR_BASE_REF" "refs/remotes/pull/\$PR_NUMBER/head")"' "$WORKFLOW" \
  || fail "PR head 와 base branch 의 merge-base 계산 부재"
grep -q 'REVIEW_PROMPT="\.github/prompts/codex-pr-review\.ko\.md"' "$WORKFLOW" \
  || fail "structured review prompt 파일 참조 부재"
grep -q 'REVIEW_SCHEMA="\.github/prompts/codex-pr-review\.schema\.json"' "$WORKFLOW" \
  || fail "structured review schema 파일 참조 부재"
grep -q 'codex exec' "$WORKFLOW" \
  || fail "codex exec 사용 부재"
grep -q -- '--sandbox read-only' "$WORKFLOW" \
  || fail "codex exec sandbox 모드 지정 부재"
reasoning_count="$(awk 'index($0, "--config model_reasoning_effort=\\\"medium\\\"") { count++ } END { print count + 0 }' "$WORKFLOW")"
[[ "$reasoning_count" == "2" ]] \
  || fail "codex review 1차/2차 exec 모두 medium reasoning effort 로 실행되지 않음"
grep -q -- '--output-schema "\$REVIEW_SCHEMA"' "$WORKFLOW" \
  || fail "codex exec output schema 지정 부재"
result_output_count="$(awk 'index($0, "--output-last-message \"$result\"") { count++ } END { print count + 0 }' "$WORKFLOW")"
[[ "$result_output_count" == "2" ]] \
  || fail "codex 최종 JSON 출력 파일 지정이 1차/2차 exec 모두에 없음"
grep -q '< "\$initial_prompt"' "$WORKFLOW" \
  || fail "prompt 를 stdin 으로 전달하지 않음"
grep -q 'unset GH_TOKEN' "$WORKFLOW" \
  || fail "Codex 실행 전 GH_TOKEN env 제거 부재"
if grep -q '"$(cat \.codex-review/full-prompt\.md)"' "$WORKFLOW"; then
  fail "prompt 전체를 커맨드라인 인자로 전달하고 있음"
fi
if grep -q 'codex review' "$WORKFLOW"; then
  fail "legacy codex review 호출이 남아 있음"
fi
ok "check 3: codex exec + stdin + schema 로 structured review 실행"

echo ""
echo "=== check 3b: codex workflow uses shared review context helper ==="
grep -q '\.github/scripts/pr-review-context\.sh' "$WORKFLOW" \
  || fail "shared review context helper 호출 부재"
grep -q 'source \.review-context/context-mode\.env' "$WORKFLOW" \
  || fail "review context mode env 로드 부재"
grep -q 'REVIEW_CONTEXT_MODE' "$WORKFLOW" \
  || fail "prompt 에 review context mode 주입 부재"
ok "check 3b: shared review context helper 사용"

echo ""
echo "=== check 3c: codex workflow supports targeted context follow-up ==="
grep -q 'context_requests' "$WORKFLOW" \
  || fail "context_requests follow-up 처리 부재"
grep -q 'review-extra-context' "$WORKFLOW" \
  || fail "추가 context 디렉터리 부재"
grep -q 'MAX_CONTEXT_REQUEST_FILES=5' "$WORKFLOW" \
  || fail "context request file limit 부재"
grep -q 'truncated at 400 lines' "$WORKFLOW" \
  || fail "추가 context 파일 절단 표시 부재"
ok "check 3c: targeted context follow-up 처리 존재"

echo ""
echo "=== check 4: @codex mention triggers require trusted author association ==="
trusted_expr="contains(fromJSON('[\"OWNER\",\"MEMBER\",\"COLLABORATOR\"]')"
trusted_count="$(awk -v needle="$trusted_expr" 'index($0, needle) { count++ } END { print count + 0 }' "$WORKFLOW")"
[[ "$trusted_count" == "3" ]] \
  || fail "issue/review comment/review @codex 트리거의 trusted author 제한이 3곳 모두에 없음"
grep -q 'github.event.comment.author_association' "$WORKFLOW" \
  || fail "comment 기반 @codex 트리거 author_association 제한 부재"
grep -q 'github.event.review.author_association' "$WORKFLOW" \
  || fail "review 기반 @codex 트리거 author_association 제한 부재"
ok "check 4: @codex mention 트리거가 OWNER/MEMBER/COLLABORATOR 로 제한됨"

echo ""
echo "=== check 5: PR body is not injected into the review prompt ==="
if grep -q 'PR_BODY:' "$WORKFLOW" || grep -q 'echo "\$PR_BODY"' "$WORKFLOW"; then
  fail "PR body 를 Codex review prompt 에 직접 주입하고 있음"
fi
ok "check 5: PR body 직접 주입 제거됨"

echo ""
echo "=== check 6: checkout does not trigger submodule auth cleanup failure ==="
if grep -q 'persist-credentials: false' "$WORKFLOW"; then
  fail "actions/checkout persist-credentials:false 는 gitlink-only .claude/worktrees 에서 submodule cleanup 실패를 유발함"
fi
ok "check 6: checkout 이 persist-credentials:false 를 사용하지 않음"

echo ""
echo "=== check 6b: checkout credentials are cleared before codex exec ==="
unset_extraheader_line="$(awk 'index($0, "git config --local --unset-all http.https://github.com/.extraheader") { print NR; exit }' "$WORKFLOW")"
codex_exec_line="$(awk '/codex exec \\/ { print NR; exit }' "$WORKFLOW")"
[[ -n "$unset_extraheader_line" ]] \
  || fail "codex exec 전 checkout credential extraheader 제거 부재"
(( unset_extraheader_line < codex_exec_line )) \
  || fail "checkout credential extraheader 제거가 codex exec 이후에 위치함"
ok "check 6b: codex exec 전 checkout credential extraheader 제거"

echo ""
echo "=== check 7: third-party actions and Codex CLI are pinned ==="
if grep -qE 'uses: actions/[a-z-]+@v[0-9]+' "$WORKFLOW"; then
  fail "GitHub Actions가 mutable version tag 로 참조됨"
fi
grep -qE 'uses: actions/github-script@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "actions/github-script SHA 고정 부재"
grep -qE 'uses: actions/checkout@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "actions/checkout SHA 고정 부재"
grep -qE 'uses: actions/setup-node@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "actions/setup-node SHA 고정 부재"
grep -q 'npm install -g @openai/codex@0\.132\.0' "$WORKFLOW" \
  || fail "@openai/codex 버전 고정 부재"
ok "check 7: Actions SHA 및 Codex CLI 버전이 고정됨"

echo ""
echo "=== check 8: legacy access-token auth is not used ==="
if grep -q 'CODEX_ACCESS_TOKEN' "$WORKFLOW"; then
  fail "CODEX_ACCESS_TOKEN 기반 인증이 남아 있음"
fi
ok "check 8: CODEX_ACCESS_TOKEN 기반 인증 제거됨"

echo ""
echo "=== check 9: review output is posted idempotently ==="
grep -q '<!-- codex-cli-pr-review -->' "$WORKFLOW" \
  || fail "중복 방지 marker 부재"
grep -q 'issues.updateComment' "$WORKFLOW" \
  || fail "기존 리뷰 코멘트 update 경로 부재"
grep -q 'issues.createComment' "$WORKFLOW" \
  || fail "신규 리뷰 코멘트 create 경로 부재"
ok "check 9: marker 기반 update/create 코멘트 경로 존재"

echo ""
echo "=== check 10: verdict submission via Pulls REST API with inline comments + auto-dismiss ==="
# Submit step is now a github-script step that calls pulls.createReview directly
# so it can post inline review comments AND auto-dismiss stale CHANGES_REQUESTED.
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
grep -qF "'REQUEST_CHANGES'" "$WORKFLOW" \
  || fail "REQUEST_CHANGES event 분기 부재"
grep -qF "fs.writeFileSync('.codex-review/approval-failed'" "$WORKFLOW" \
  || fail "APPROVE 실패 시 approval-failed marker 부재"
grep -qF "'github-actions[bot]'" "$WORKFLOW" \
  || fail "self-review 식별 (github-actions[bot]) 부재"
grep -qF 'automation_safety' "$WORKFLOW" \
  || fail "automation_safety gate 부재"
grep -qF 'confidence_score' "$WORKFLOW" \
  || fail "confidence_score gate 부재"
grep -qF '>= 80' "$WORKFLOW" \
  || fail "confidence_score >= 80 threshold 부재"
# 요약(issue-level) managed comment 는 approve 일 때만. inline-fallback 경로 제거(AC2/AC3).
grep -qF 'Managed Codex review comment is only posted on verdict=approve' "$WORKFLOW" \
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
grep -qF 'Superseded by later review' "$WORKFLOW" \
  || fail "verdict!=approve 일 때 옛 approve managed comment supersede 분기 부재 (stale approve 가 PR 대화에 남음)"
grep -qF 'Superseded stale managed comment' "$WORKFLOW" \
  || fail "supersede core.info log 부재"
# auto-resolve self inline threads on verdict=approve (outdated 무관)
grep -qF "<!-- codex-review-inline -->" "$WORKFLOW" \
  || fail "inline comment 의 self-identification marker (codex-review-inline) 부재"
grep -qF 'resolveReviewThread' "$WORKFLOW" \
  || fail "GraphQL resolveReviewThread mutation 호출 부재 — self inline thread 자동 resolve 안 됨"
grep -qF 'botLoginGql' "$WORKFLOW" \
  || fail "GraphQL author login 형식 정규화(botLoginGql) 부재 — GraphQL은 'github-actions' 반환, REST '[bot]' 형식만 비교하면 self thread 매칭 실패로 resolve 안 됨"
grep -qF 'isResolved' "$WORKFLOW" \
  || fail "isResolved 조건 검사 부재 (이미 resolved thread skip)"
grep -qF 'reviewThreads(first: 100)' "$WORKFLOW" \
  || fail "GraphQL reviewThreads 쿼리 부재"
ok "check 10: createReview + inline comments + safety gates + COMMENT fallback"

echo ""
echo "=== check 10b: formal review idempotent per (head_sha, verdict) ==="
grep -qF '<!-- ${prefix} head_sha=${head_sha} verdict=${verdict} -->' "$WORKFLOW" \
  || fail "formal review 중복 방지 marker template 부재"
grep -qF 'github.rest.pulls.listReviews' "$WORKFLOW" \
  || fail "기존 review 조회 (pulls.listReviews) 부재"
grep -qF "r.state === 'APPROVED' && r.commit_id === head_sha" "$WORKFLOW" \
  || fail "동일 head_sha approve 중복 방지 부재"
grep -qF 'already exists; skipping duplicate' "$WORKFLOW" \
  || fail "marker 기반 중복 review skip 메시지 부재"
ok "check 10b: marker + APPROVED state + head_sha 기준 멱등"

echo ""
echo "=== check 10c: auto-dismiss prior CHANGES_REQUESTED when verdict=approve ==="
grep -qF 'github.rest.pulls.dismissReview' "$WORKFLOW" \
  || fail "옛 CHANGES_REQUESTED reviews 자동 dismiss 호출 부재"
grep -qF "r.state === 'CHANGES_REQUESTED'" "$WORKFLOW" \
  || fail "dismiss 대상 식별이 state=CHANGES_REQUESTED 로 제한되지 않음"
grep -qF "verdict === 'approve'" "$WORKFLOW" \
  || fail "dismiss 게이트가 verdict=approve 조건 부재"
grep -qF 'Superseded by later review' "$WORKFLOW" \
  || fail "dismiss message 부재"
ok "check 10c: verdict=approve 시 옛 자기 CHANGES_REQUESTED reviews 자동 dismiss"

echo ""
echo "=== check 10d: managed comment 은 finding 평가 본문을 렌더하지 않는다 (inline-only) ==="
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
ok "check 10d: managed comment 에 finding 평가 렌더 경로 제거됨"

echo ""
echo "=== check 11b: 출력 언어 untrusted block 끝에 재강조 (영어 응답 예방) ==="
grep -qF '## 마지막 재강조 (절대 위반 금지)' "$WORKFLOW" \
  || fail "마지막 재강조 섹션 부재 — 모델이 untrusted PR diff 뒤에서 출력 언어 지시 흘릴 수 있음"
grep -qF '영어 등 다른 언어로 작성하면 안 됩니다' "$WORKFLOW" \
  || fail "출력 언어 명시적 강제 라인 부재"
grep -qF '"$CODEX_REVIEW_LANG"' "$WORKFLOW" \
  || fail "재강조 라인이 CODEX_REVIEW_LANG 변수를 사용하지 않음"
ok "check 11b: untrusted block 끝에 출력 언어 재강조"

echo ""
echo "=== check 11: prompt captures token and confidence policies ==="
grep -q '토큰 최적화 정책' "$PROMPT" \
  || fail "prompt 토큰 최적화 정책 부재"
grep -q 'Confidence scoring' "$PROMPT" \
  || fail "prompt confidence scoring 정책 부재"
grep -q 'confidence_score < 80' "$PROMPT" \
  || fail "prompt confidence threshold 정책 부재"
grep -q 'valid JSON' "$PROMPT" \
  || fail "prompt JSON-only 출력 규칙 부재"
if grep -q '동일 head_sha에 대해 Codex 리뷰가 이미 완료' "$PROMPT"; then
  fail "prompt 가 동일 head_sha 기존 Codex 리뷰만으로 리뷰를 skip 하도록 지시함"
fi
ok "check 11: prompt 핵심 정책 존재"

echo ""
echo "=== check 11c: inline-only 코멘트 정책 (prompt + schema) ==="
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
grep -qF '"kind": "inline"' "$PROMPT" \
  || fail "prompt hidden marker 의 kind 가 inline 전용이 아님"
if grep -qF 'inline|issue' "$PROMPT"; then
  fail "prompt 에 inline|issue 잔존 — inline-only 정책에서 kind 는 inline 만"
fi
# schema: comment_type enum 은 inline 전용
grep -qF '"inline"' "$SCHEMA" \
  || fail "schema comment_type 에 inline 값 부재"
if grep -qF '"issue"' "$SCHEMA"; then
  fail "schema comment_type enum 에 issue 잔존 — inline-only 정책에서 제거되어야 함"
fi
ok "check 11c: prompt·schema 가 inline-only + 강제 anchoring 정책을 반영"

echo ""
echo "=== check 12: schema requires automation safety and context fields ==="
grep -q '"automation_safety"' "$SCHEMA" \
  || fail "schema automation_safety 부재"
grep -q '"reviewed_context"' "$SCHEMA" \
  || fail "schema reviewed_context 부재"
grep -q '"confidence_score"' "$SCHEMA" \
  || fail "schema confidence_score 부재"
grep -q '"context_requests"' "$SCHEMA" \
  || fail "schema context_requests 부재"
ok "check 12: schema 핵심 필드 존재"

echo ""
echo "=== check 13: PR 게시 보일러플레이트 한국어화 (SPEC 2026-05-31) ==="
# AC1/AC6: 섹션 헤더 한국어. PR 코멘트 본문 헤더(## 접두)만 검사 — 워크플로 name 은 제외.
grep -qF '## Codex PR 리뷰' "$WORKFLOW" \
  || fail "한국어 섹션 헤더 '## Codex PR 리뷰' 부재"
if grep -qF '## Codex PR Review' "$WORKFLOW"; then
  fail "영어 섹션 헤더 '## Codex PR Review' 잔존"
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
# AC5: verdict 표시 줄 한국어 라벨. 단, 숨김 마커 verdict enum 은 보존.
grep -qF '결과: 승인' "$WORKFLOW" \
  || fail "한국어 verdict 표시 줄 '결과: 승인' 부재"
if grep -qF 'Verdict: `approve`' "$WORKFLOW"; then
  fail "영어 verdict 표시 줄 'Verdict: \`approve\`' 잔존"
fi
# AC5 제약: 숨김 마커의 verdict enum 값(verdict=...) 은 변경 금지.
grep -qF 'head_sha=${head_sha} verdict=${verdict}' "$WORKFLOW" \
  || fail "숨김 멱등성 마커의 verdict enum 바인딩이 변경됨 (멱등성·승인 게이팅 위험)"
ok "check 13: 보일러플레이트 한국어화 + 숨김 마커/enum 보존"

echo ""
echo "ALL CHECKS PASSED"
