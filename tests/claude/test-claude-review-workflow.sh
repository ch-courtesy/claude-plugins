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
echo "=== check 6: 단일 inline 리뷰 제출 — verdict/event + body summary + 멱등 (AC1/AC7) ==="
grep -q 'name: Submit Claude inline review' "$WORKFLOW" \
  || fail "'Submit Claude inline review' 스텝 부재 (단일 inline 리뷰 게시 스텝 치환) (제약)"
grep -qF 'github.rest.pulls.createReview' "$WORKFLOW" \
  || fail "Pulls REST createReview 호출 부재 — inline 단일 리뷰 제출 불가 (AC1)"
grep -qF "event === 'APPROVE'" "$WORKFLOW" \
  || fail "APPROVE event 분기 부재 (AC1)"
grep -qF "event = 'COMMENT'" "$WORKFLOW" \
  || fail "COMMENT event 분기 부재 (AC1)"
if grep -qF 'REQUEST_CHANGES' "$WORKFLOW"; then
  fail "REQUEST_CHANGES 잔존 — 공식 review event 는 APPROVE/COMMENT 만 (제약)"
fi
if grep -oE '[a-z_]*request_changes' "$WORKFLOW" | grep -qvE '^may_request_changes$'; then
  fail "request_changes verdict 어휘 잔존 (may_request_changes 외) — 제거 필요 (제약)"
fi
grep -qF '## Claude PR 리뷰' "$WORKFLOW" \
  || fail "리뷰 본문 헤더 '## Claude PR 리뷰' 부재 (제약: claude 라벨)"
grep -qF 'result.summary' "$WORKFLOW" \
  || fail "리뷰 본문에 result.summary 포함 부재 (제약: summary 를 본문에 실음)"
grep -qF 'CLAUDE_FORMAL_PREFIX: claude-formal-review' "$WORKFLOW" \
  || fail "formal review 마커 prefix(CLAUDE_FORMAL_PREFIX: claude-formal-review) 부재 (제약)"
grep -qF '${prefix} head_sha=${head_sha} verdict=${verdict}' "$WORKFLOW" \
  || fail "formal review 멱등 마커 템플릿(<!-- {prefix} head_sha=.. verdict=.. -->) 부재 (제약)"
grep -qF 'github.rest.pulls.listReviews' "$WORKFLOW" \
  || fail "기존 review 조회(listReviews) 부재 — 멱등성 판정 불가 (AC1)"
grep -qF 'skipping duplicate submission' "$WORKFLOW" \
  || fail "marker 기반 중복 review 제출 skip 부재 (멱등)"
grep -qF "fs.writeFileSync('.claude-review/approval-failed'" "$WORKFLOW" \
  || fail "APPROVE 실패 시 approval-failed marker 기록 부재 (AC7)"
grep -qF "submit('COMMENT')" "$WORKFLOW" \
  || fail "APPROVE 실패 시 같은 inline 코멘트로 COMMENT 강등 제출 부재 (AC7)"
grep -qF 'may_approve' "$WORKFLOW" \
  || fail "approve safety gate(may_approve) 부재"
ok "check 6: 단일 inline 리뷰 제출 (APPROVE/COMMENT) + body summary + 멱등 + APPROVE fallback"

echo ""
echo "=== check 7: 별도 마커 관리형 이슈 레벨 코멘트 게시 경로 부재 (AC6) ==="
grep -q 'name: Post Claude review comment' "$WORKFLOW" \
  && fail "'Post Claude review comment' 스텝 잔존 — 이슈 코멘트 게시 경로 제거 필요 (AC6)"
if grep -qF '<!-- claude-api-pr-review -->' "$WORKFLOW"; then
  fail "관리형 이슈 코멘트 마커(<!-- claude-api-pr-review -->) 잔존 (AC6)"
fi
if grep -qF 'issues.createComment' "$WORKFLOW"; then
  fail "issues.createComment 잔존 — 발견사항 이슈 코멘트 게시 금지 (AC6)"
fi
if grep -qF 'issues.updateComment' "$WORKFLOW"; then
  fail "issues.updateComment 잔존 — 관리형 이슈 코멘트 갱신 경로 금지 (AC6)"
fi
ok "check 7: 마커 관리형 이슈 레벨 코멘트 게시 경로 부재"

echo ""
echo "=== check 7b: 인라인 리뷰 코멘트 게시 경로 존재 (AC1/AC2) ==="
grep -qF 'comments: inlineComments' "$WORKFLOW" \
  || fail "createReview 의 comments[] 배열에 inline findings(inlineComments) 전달 부재 (AC1)"
grep -qF 'inline-only' "$WORKFLOW" \
  || fail "inline-only 정책 주석/마커 부재 (모든 finding 을 inline 으로 게시) (AC6)"
grep -qF "side: 'RIGHT'" "$WORKFLOW" \
  || fail "inline comment side='RIGHT' 지정 부재 (AC1)"
grep -qF 'start_line' "$WORKFLOW" \
  || fail "multi-line inline comment 의 start_line 처리 부재 (AC1)"
if grep -qF 'inlineFallback' "$WORKFLOW"; then
  fail "inlineFallback 경로 잔존 — createReview 실패 시 이슈 코멘트 덤프 금지 (AC6)"
fi
ok "check 7b: 인라인 리뷰 코멘트 게시 경로 존재 (createReview comments[] + RIGHT + start_line)"

echo ""
echo "=== check 7c: fingerprint 기반 self thread 자동 resolve 경로 존재 (AC3/AC4) ==="
grep -qF 'computeFingerprint' "$WORKFLOW" \
  || fail "결정론적 fingerprint 계산(computeFingerprint) 부재 (AC3)"
grep -qF 'resolveReviewThread' "$WORKFLOW" \
  || fail "GraphQL resolveReviewThread mutation 부재 — self thread 자동 resolve 안 됨 (AC4)"
grep -qF 'reviewThreads(first: 100)' "$WORKFLOW" \
  || fail "GraphQL reviewThreads 조회 부재 (AC4)"
grep -qF 'resolved_threads' "$WORKFLOW" \
  || fail "resolved_threads 소비(1차) 경로 부재 (AC4)"
grep -qF 'findingFingerprints' "$WORKFLOW" \
  || fail "이번 라운드 findings fingerprint 집합(findingFingerprints) 부재 (AC4 fallback)"
grep -qF '<!-- claude-review-inline' "$WORKFLOW" \
  || fail "inline self-식별 마커 substring(<!-- claude-review-inline) 부재 (AC2)"
grep -qF 'fingerprint=${computeFingerprint(f)}' "$WORKFLOW" \
  || fail "게시 inline 마커가 결정론적 computeFingerprint(f) 를 운반하지 않음 (AC2/AC3)"
grep -qF 'botLoginGql' "$WORKFLOW" \
  || fail "GraphQL author login 형식 정규화(botLoginGql) 부재 (AC4)"
grep -qF 'isResolved' "$WORKFLOW" \
  || fail "isResolved 조건 검사 부재 (이미 resolved thread skip)"
grep -qF 'regardless of verdict' "$WORKFLOW" \
  || fail "resolve 가 verdict 무관 실행임을 명시하는 마커(regardless of verdict) 부재 (AC4)"
if grep -qF 'fingerprint=${f.fingerprint}' "$WORKFLOW"; then
  fail "게시 마커가 모델 자유 생성 f.fingerprint 운반 — 결정론 계산으로 전환되어야 함 (AC3)"
fi
ok "check 7c: fingerprint self thread 자동 resolve 경로 존재 (resolved_threads 1차 + fallback)"

echo ""
echo "=== check 7d: 결정론적 fingerprint — file+perspective+normalized title, 줄번호 비의존 (AC3) ==="
grep -qF 'crypto' "$WORKFLOW" \
  || fail "fingerprint 해시 계산(crypto) 부재 (AC3)"
grep -qF "[f.file || '', f.review_perspective || '', normalizeTitle(f.title)]" "$WORKFLOW" \
  || fail "fingerprint 입력이 file+review_perspective+normalized title 로 한정되지 않음 (AC3)"
grep -qF "normalize('NFKC')" "$WORKFLOW" \
  || fail "제목 정규화 NFKC 부재 또는 불일치 (제약: 두 워크플로 byte-identical)"
grep -qF "replace(/[^\\p{L}\\p{N}]+/gu, ' ')" "$WORKFLOW" \
  || fail "제목 정규화(문장부호/공백 → 단일 공백) 구현 부재 또는 불일치 (제약: 두 워크플로 동일)"
grep -qF 'findings.map((f) => computeFingerprint(f))' "$WORKFLOW" \
  || fail "findingFingerprints 가 결정론적 computeFingerprint 로 산정되지 않음 (AC3)"
ok "check 7d: 결정론적 fingerprint(file+perspective+title), 줄번호 비의존"

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
echo "=== check 11: 출력 언어 지시 + untrusted block 끝 재강조 + 구성 변수 (AC1/AC2/AC3/AC4/AC5) ==="
# 구성 변수: 출력 언어는 리포지터리 변수로 구성 가능, 미지정 시 Korean 폴백 (AC3/AC4)
grep -qF "CLAUDE_REVIEW_LANG: \${{ vars.CLAUDE_REVIEW_LANG || 'Korean' }}" "$WORKFLOW" \
  || fail "출력 언어 구성 변수(CLAUDE_REVIEW_LANG, 기본 Korean) 부재 (AC3/AC4)"
# 명시적 출력 언어 지시: untrusted 입력 앞, 프롬프트 본문 뒤 (AC1)
grep -qF '## 출력 언어' "$WORKFLOW" \
  || fail "명시적 출력 언어 지시 섹션(## 출력 언어) 부재 (AC1)"
grep -qF '리뷰 산출물의 자연어 필드(summary, 각 finding의 title·body·suggestion)' "$WORKFLOW" \
  || fail "자연어 필드 대상 명시 지시 부재 (AC1)"
# untrusted PR 입력(metadata·comments·diff) 뒤 재강조 (AC2)
grep -qF '## 마지막 재강조 (절대 위반 금지)' "$WORKFLOW" \
  || fail "마지막 재강조 섹션 부재 — 모델이 untrusted PR diff 뒤에서 출력 언어 지시 흘릴 수 있음 (AC2)"
grep -qF '영어 등 다른 언어로 작성하면 안 됩니다' "$WORKFLOW" \
  || fail "출력 언어 명시적 강제(다른 언어 금지) 라인 부재 (AC2)"
# 재강조가 모든 untrusted 입력(diff) 뒤에 위치하는지 정적 검증 (AC2 / 제약: 재강조 위치)
lang_reiterate_line="$(awk 'index($0, "## 마지막 재강조 (절대 위반 금지)") { print NR; exit }' "$WORKFLOW")"
diff_cat_line="$(awk 'index($0, "cat .review-context/diff.patch") { print NR; exit }' "$WORKFLOW")"
[[ -n "$lang_reiterate_line" && -n "$diff_cat_line" ]] \
  || fail "재강조/ diff cat 라인 탐지 실패 (AC2)"
(( diff_cat_line < lang_reiterate_line )) \
  || fail "재강조가 untrusted diff 출력보다 앞에 위치함 — 모든 untrusted 입력 뒤에 와야 함 (AC2 / 제약)"
# 지시·재강조 양쪽이 구성 변수를 사용 (AC4)
grep -qF '"$CLAUDE_REVIEW_LANG"' "$WORKFLOW" \
  || fail "출력 언어 지시/재강조가 CLAUDE_REVIEW_LANG 변수를 사용하지 않음 (AC4)"
ok "check 11: 출력 언어 지시 + untrusted block 끝 재강조 + 구성 변수(기본 Korean)"

echo ""
echo "=== check 12: GitHub App 설치 토큰 발급 + 동적 봇 식별 + graceful degradation (AC1/AC2/AC3/AC5/제약) ==="
# App 설치 토큰 발급 스텝이 SHA 고정 actions/create-github-app-token 으로 존재.
grep -qE 'uses: actions/create-github-app-token@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "actions/create-github-app-token SHA 고정 발급 스텝 부재 (AC1/제약)"
if grep -qE 'uses: actions/create-github-app-token@v[0-9.]+' "$WORKFLOW"; then
  fail "create-github-app-token 이 mutable version tag — SHA 고정 필요 (제약)"
fi
# App ID / private key 시크릿으로 단명 토큰 발급 (장기 PAT 단일 시크릿 금지).
grep -qF 'app-id: ${{ secrets.REVIEW_APP_ID }}' "$WORKFLOW" \
  || fail "create-github-app-token 에 app-id=secrets.REVIEW_APP_ID 입력 부재 (제약)"
grep -qF 'private-key: ${{ secrets.REVIEW_APP_PRIVATE_KEY }}' "$WORKFLOW" \
  || fail "create-github-app-token 에 private-key=secrets.REVIEW_APP_PRIVATE_KEY 입력 부재 (제약)"
# 시크릿 부재 시 발급 스텝 skip — graceful degradation (AC5).
grep -qF "if: \${{ env.REVIEW_APP_ID != '' }}" "$WORKFLOW" \
  || fail "App 토큰 발급 스텝이 REVIEW_APP_ID 부재 시 skip 되도록 게이트되지 않음 (AC5)"
grep -qF 'REVIEW_APP_ID: ${{ secrets.REVIEW_APP_ID }}' "$WORKFLOW" \
  || fail "REVIEW_APP_ID 시크릿을 env 로 노출(게이트 판정용)하지 않음 (AC5/제약)"
# 발급 실패가 리뷰를 중단시키지 않도록 continue-on-error (AC5: 발급 실패 graceful).
grep -qF 'continue-on-error: true' "$WORKFLOW" \
  || fail "App 토큰 발급 스텝 continue-on-error 부재 — 발급 실패 시 리뷰 전면 중단 (AC5)"
# 게시 토큰: App 토큰 우선, 없으면 기본 토큰 (AC5 graceful).
grep -qF 'steps.app-token.outputs.token || github.token' "$WORKFLOW" \
  || fail "게시 토큰이 App 토큰 우선·기본 토큰 폴백(steps.app-token.outputs.token || github.token)으로 해석되지 않음 (AC5/제약)"
# 봇 로그인 동적 해석: app-slug → <slug>[bot], 없으면 github-actions[bot] (AC3).
grep -qF 'steps.app-token.outputs.app-slug' "$WORKFLOW" \
  || fail "App 봇 로그인 동적 해석(app-slug 출력) 부재 (AC3)"
grep -qF 'const botLogin = appSlug' "$WORKFLOW" \
  || fail "botLogin 이 app-slug 기반 동적 해석으로 산정되지 않음 (AC3/AC5)"
grep -qF "'github-actions[bot]'" "$WORKFLOW" \
  || fail "기본 토큰 봇 식별(github-actions[bot]) 폴백 부재 (AC5)"
# Claude 의 기존 id-token: write(OAuth 토큰 교환용)는 App 토큰 도입 후에도 보존.
grep -qE '^[[:space:]]*id-token:[[:space:]]*write' "$WORKFLOW" \
  || fail "claude-code-action OAuth 용 id-token: write 권한이 App 토큰 도입으로 사라짐 (제약)"
# App 자동 게시 self-trigger 배제(AC4): @claude 멘션 요구가 멘션 없는 App 자동게시를 배제.
mention_count="$(awk -v n="contains(github.event.comment.body, '@claude')" 'index($0,n){c++} END{print c+0}' "$WORKFLOW")"
review_mention_count="$(awk -v n="contains(github.event.review.body, '@claude')" 'index($0,n){c++} END{print c+0}' "$WORKFLOW")"
(( mention_count + review_mention_count >= 3 )) \
  || fail "@claude 멘션 요구가 comment/review 트리거 3개 분기에 모두 있지 않음 — App 자동게시 self-trigger 배제 불가 (AC4)"
# App 봇 identity(<slug>[bot])는 'github-actions[bot]' 리터럴 배제로는 걸러지지 않으므로,
# 모든 봇 작성 comment/review 이벤트를 user.type 로 배제해 App 봇 self-trigger 루프를 막는다 (AC4).
cbt="$(awk -v n="github.event.comment.user.type != 'Bot'" 'index($0,n){c++} END{print c+0}' "$WORKFLOW")"
rbt="$(awk -v n="github.event.review.user.type != 'Bot'" 'index($0,n){c++} END{print c+0}' "$WORKFLOW")"
(( cbt >= 2 && rbt >= 1 )) \
  || fail "App 봇 포함 봇 작성 이벤트 배제(user.type != 'Bot')가 comment 2개·review 1개 분기에 없음 (AC4)"
ok "check 12: App 토큰 발급(SHA 고정) + 동적 봇 식별 + graceful degradation + id-token 보존 + self-trigger 배제"

echo ""
echo "ALL CHECKS PASSED"
