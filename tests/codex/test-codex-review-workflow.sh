#!/usr/bin/env bash
# Codex PR review workflow contract.
#
# Static checks only: do not call GitHub, npm, or Codex.
#
# This workflow calls the model through the official openai/codex-action and
# publishes results with the SAME structure as the sibling Claude PR review
# workflow (formal review verdict + a single marker-managed PR comment). The
# legacy codex-only paths — direct `codex exec`/`codex review` CLI calls,
# inline review comments, fingerprint-based self thread auto-resolve, and the
# GitHub App installation token / App-token APPROVE — are gone. These checks
# assert the new structure exists and the removed paths are absent.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKFLOW="$REPO_ROOT/.github/workflows/codex-review.yml"
PROMPT="$REPO_ROOT/.github/prompts/codex-pr-review.ko.md"
SCHEMA="$REPO_ROOT/.github/prompts/codex-pr-review.schema.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

count() { awk -v needle="$1" 'index($0, needle) { c++ } END { print c + 0 }' "$2"; }

[[ -f "$WORKFLOW" ]] || fail "$WORKFLOW 부재"
[[ -f "$PROMPT" ]] || fail "$PROMPT 부재"
[[ -f "$SCHEMA" ]] || fail "$SCHEMA 부재"

echo "=== check 1: 모델 호출은 공식 openai/codex-action 으로 이뤄진다 (AC1) ==="
# 1차/2차(needs_context follow-up) 모두 동일한 SHA 고정 action 으로 실행.
codex_action_count="$(grep -cE 'uses: openai/codex-action@[0-9a-f]{40}' "$WORKFLOW")"
[[ "$codex_action_count" == "2" ]] \
  || fail "openai/codex-action SHA 고정 호출이 1차/2차 2곳에 없음 (현재 $codex_action_count)"
if grep -qE 'uses: openai/codex-action@v[0-9.]+' "$WORKFLOW"; then
  fail "openai/codex-action 이 mutable version tag 로 참조됨 — SHA 고정 필요"
fi
ok "check 1: openai/codex-action SHA 고정 호출 2곳"

echo ""
echo "=== check 2: 셸 직접 codex CLI 호출·설치 스텝이 존재하지 않는다 (AC1) ==="
if grep -q 'npm install -g @openai/codex' "$WORKFLOW"; then
  fail "npm install -g @openai/codex 설치 스텝 잔존 — CLI 직접 호출 제거 필요 (AC1)"
fi
if grep -q 'codex exec' "$WORKFLOW"; then
  fail "셸에서 직접 'codex exec' 호출 잔존 — action 을 통해야 함 (AC1)"
fi
if grep -q 'codex review' "$WORKFLOW"; then
  fail "legacy 'codex review' 호출 잔존 (AC1)"
fi
ok "check 2: codex CLI 직접 호출·설치 스텝 부재"

echo ""
echo "=== check 3: codex CLI 버전이 action 버전 입력으로 고정된다 (제약) ==="
codex_version_count="$(count "codex-version: '0.132.0'" "$WORKFLOW")"
[[ "$codex_version_count" == "2" ]] \
  || fail "codex-version 입력이 1차/2차 action 호출 양쪽에 0.132.0 으로 고정되지 않음 (현재 $codex_version_count)"
ok "check 3: codex-version 입력으로 codex CLI 0.132.0 고정"

echo ""
echo "=== check 4: ChatGPT auth.json codex-home 부트스트랩 (AC2/제약) ==="
secret_count="$(count 'secrets.CODEX_AUTH_JSON' "$WORKFLOW")"
[[ "$secret_count" == "1" ]] \
  || fail "secrets.CODEX_AUTH_JSON 참조가 정확히 1곳(부트스트랩 env)이어야 함 — 모델 호출 스텝 노출 금지 (현재 $secret_count) (제약)"
grep -q 'CODEX_AUTH_JSON:.*secrets\.CODEX_AUTH_JSON' "$WORKFLOW" \
  || fail "CODEX_AUTH_JSON secret env 매핑 부재 (AC2)"
grep -q 'printf .*> "\$codex_home/auth\.json"' "$WORKFLOW" \
  || fail "codex-home 디렉터리의 auth.json 기록 부재 (AC2/제약)"
grep -q 'chmod 600 "\$codex_home/auth\.json"' "$WORKFLOW" \
  || fail "auth.json 권한 600 설정 부재 (제약)"
grep -q 'codex-home: ${{ env\.CODEX_HOME_DIR }}' "$WORKFLOW" \
  || fail "codex-home 디렉터리를 action 의 codex-home 입력으로 전달하지 않음 (AC2/제약)"
codex_home_input_count="$(count 'codex-home: ${{ env.CODEX_HOME_DIR }}' "$WORKFLOW")"
[[ "$codex_home_input_count" == "2" ]] \
  || fail "codex-home 입력이 1차/2차 action 호출 양쪽에 전달되지 않음 (현재 $codex_home_input_count)"
ok "check 4: CODEX_AUTH_JSON → codex-home/auth.json(600) → action codex-home 입력"

echo ""
echo "=== check 5: auth 디렉터리가 restrictive umask 아래 생성됨 (제약) ==="
umask_line="$(grep -n 'umask 077' "$WORKFLOW" | head -1 | cut -d: -f1)"
mkdir_line="$(grep -n 'mkdir -p "\$codex_home"' "$WORKFLOW" | head -1 | cut -d: -f1)"
[[ -n "$umask_line" ]] || fail "umask 077 설정 부재"
[[ -n "$mkdir_line" ]] || fail "codex-home 디렉터리 생성 부재"
(( umask_line < mkdir_line )) \
  || fail "umask 077 이 codex-home mkdir 이후에 설정됨"
ok "check 5: umask 077 이 codex-home 생성 전에 적용됨"

echo ""
echo "=== check 6: CODEX_AUTH_JSON 비어 있으면 명확한 오류로 실패 (AC3) ==="
grep -q 'if \[ -z "\$CODEX_AUTH_JSON" \]; then' "$WORKFLOW" \
  || fail "CODEX_AUTH_JSON 비어있음 가드 부재 (AC3)"
grep -qF 'CODEX_AUTH_JSON secret is required' "$WORKFLOW" \
  || fail "인증 부재 오류 메시지 부재 (AC3)"
ok "check 6: 빈 CODEX_AUTH_JSON → exit 1"

echo ""
echo "=== check 7: API 키 인증 경로가 없다 (AC2) ==="
if grep -qi 'openai-api-key' "$WORKFLOW"; then
  fail "openai-api-key 입력 잔존 — auth.json 방식만 허용 (AC2)"
fi
if grep -q 'OPENAI_API_KEY' "$WORKFLOW"; then
  fail "OPENAI_API_KEY 환경 잔존 — auth.json 방식만 허용 (AC2)"
fi
if grep -q 'CODEX_ACCESS_TOKEN' "$WORKFLOW"; then
  fail "CODEX_ACCESS_TOKEN 기반 인증 잔존"
fi
ok "check 7: API 키 인증 경로 부재"

echo ""
echo "=== check 8: action 입력 매핑 (schema 파일·프롬프트 파일·sandbox·effort·output 파일) (AC6/제약) ==="
grep -q 'sandbox: read-only' "$WORKFLOW" \
  || fail "sandbox read-only 입력 부재 (제약)"
grep -q 'effort: medium' "$WORKFLOW" \
  || fail "reasoning effort medium 입력 부재 (제약)"
grep -q 'output-schema-file: \.github/prompts/codex-pr-review\.schema\.json' "$WORKFLOW" \
  || fail "공유 schema 를 output-schema-file 입력으로 전달하지 않음 (AC6/제약)"
grep -q 'output-file: \.codex-review/result\.json' "$WORKFLOW" \
  || fail "결과 JSON 을 output-file 입력으로 수신하지 않음 (제약)"
grep -q 'prompt-file: \.codex-review/prompt\.md' "$WORKFLOW" \
  || fail "1차 프롬프트 파일을 prompt-file 입력으로 전달하지 않음 (제약)"
grep -q 'prompt-file: \.codex-review/prompt\.follow-up\.md' "$WORKFLOW" \
  || fail "2차(follow-up) 프롬프트 파일을 prompt-file 입력으로 전달하지 않음 (제약)"
ok "check 8: schema-file·prompt-file·sandbox·effort·output-file 입력 매핑"

echo ""
echo "=== check 9: 결과 JSON 유효성 가드 (AC6/위험) ==="
jq_empty_count="$(count 'jq empty .codex-review/result.json' "$WORKFLOW")"
[[ "$jq_empty_count" == "2" ]] \
  || fail "결과 JSON 유효성 가드(jq empty)가 1차/2차 저장 직후 양쪽에 없음 (현재 $jq_empty_count) (위험)"
ok "check 9: 1차/2차 결과 저장 직후 jq empty 검증"

echo ""
echo "=== check 10: 공유 review context helper 사용 (보존) ==="
grep -q '\.github/scripts/pr-review-context\.sh' "$WORKFLOW" \
  || fail "shared review context helper 호출 부재"
grep -q 'source \.review-context/context-mode\.env' "$WORKFLOW" \
  || fail "review context mode env 로드 부재"
grep -q 'REVIEW_CONTEXT_MODE' "$WORKFLOW" \
  || fail "prompt 에 review context mode 주입 부재"
grep -q 'REVIEW_BASE="$(git merge-base "origin/\$PR_BASE_REF" "refs/remotes/pull/\$PR_NUMBER/head")"' "$WORKFLOW" \
  || fail "PR head 와 base branch 의 merge-base 계산 부재"
ok "check 10: 공유 context helper + merge-base 계산"

echo ""
echo "=== check 11: needs_context 2-pass follow-up 보존 (AC7) ==="
grep -q 'context_requests' "$WORKFLOW" \
  || fail "context_requests follow-up 처리 부재 (AC7)"
grep -q 'review-extra-context' "$WORKFLOW" \
  || fail "추가 context 디렉터리 부재 (AC7)"
grep -q 'MAX_CONTEXT_REQUEST_FILES=5' "$WORKFLOW" \
  || fail "context request file limit 부재 (AC7)"
grep -q 'truncated at 400 lines' "$WORKFLOW" \
  || fail "추가 context 파일 절단 표시 부재 (AC7)"
grep -q 'has_extra_context' "$WORKFLOW" \
  || fail "follow-up 게이트 출력(has_extra_context) 부재 (AC7)"
grep -q "if: steps\.prepare-codex-follow-up\.outputs\.has_extra_context == 'true'" "$WORKFLOW" \
  || fail "follow-up action 실행이 has_extra_context 로 게이트되지 않음 (AC7)"
ok "check 11: needs_context 2-pass follow-up 보존"

echo ""
echo "=== check 12: @codex 멘션 트리거 + author association 게이트 보존, App 봇 분기 제거 (AC8/제약) ==="
trusted_expr="contains(fromJSON('[\"OWNER\",\"MEMBER\",\"COLLABORATOR\"]')"
trusted_count="$(count "$trusted_expr" "$WORKFLOW")"
[[ "$trusted_count" == "3" ]] \
  || fail "issue/review comment/review @codex 트리거의 trusted author 제한이 3곳 모두에 없음 (현재 $trusted_count) (AC8)"
grep -q "contains(github.event.comment.body, '@codex')" "$WORKFLOW" \
  || fail "@codex 멘션 트리거 부재 (AC8)"
grep -q 'github.event.comment.author_association' "$WORKFLOW" \
  || fail "comment 기반 @codex 트리거 author_association 제한 부재 (AC8)"
grep -q 'github.event.review.author_association' "$WORKFLOW" \
  || fail "review 기반 @codex 트리거 author_association 제한 부재 (AC8)"
grep -q "github.event.comment.user.login != 'github-actions\[bot\]'" "$WORKFLOW" \
  || fail "봇 self-trigger 차단 게이트 부재 (AC8)"
if grep -q 'REVIEW_APP_BOT_LOGIN' "$WORKFLOW"; then
  fail "REVIEW_APP_BOT_LOGIN App 봇 식별 분기 잔존 — Claude 구조에 없음 (제약)"
fi
ok "check 12: @codex + author association + 봇 차단 게이트, App 봇 분기 제거됨"

echo ""
echo "=== check 13: Claude 동일 게시 구조 — verdict 정식 리뷰 제출 (AC4/제약) ==="
grep -q 'name: Submit Codex review verdict' "$WORKFLOW" \
  || fail "'Submit Codex review verdict' 스텝 부재 (Claude 'Submit … review verdict' 구조 치환) (제약)"
# 정식 리뷰 verdict 는 gh pr review 로 제출 (Claude 와 동일). approve/comment/request-changes 3 경로.
grep -q 'gh pr review .*--approve' "$WORKFLOW" \
  || fail "approve 정식 리뷰 제출 경로 부재 (AC4)"
grep -q 'submit_review --comment' "$WORKFLOW" \
  || fail "comment 정식 리뷰 제출 경로 부재 (AC4)"
grep -q 'submit_review --request-changes' "$WORKFLOW" \
  || fail "request-changes 정식 리뷰 제출 경로 부재 (AC4 — Claude 동일)"
grep -qF '## Codex PR Review' "$WORKFLOW" \
  || fail "정식 리뷰 본문 헤더 '## Codex PR Review' 부재 (제약: codex 라벨 치환)"
# 멱등 마커 (head_sha, verdict) 기준.
grep -qF 'codex-formal-review head_sha=$PR_HEAD_SHA verdict=$verdict' "$WORKFLOW" \
  || fail "formal review 멱등 마커(codex-formal-review head_sha=.. verdict=..) 부재 (제약)"
grep -qF 'already exists for $PR_HEAD_SHA / $verdict; skipping duplicate' "$WORKFLOW" \
  || fail "marker 기반 중복 review skip 부재 (AC4 멱등)"
grep -qF 'pulls/$PR_NUMBER/reviews' "$WORKFLOW" \
  || fail "기존 review 조회(REST) 부재 — 멱등성 판정 불가"
grep -q 'touch .codex-review/approval-failed' "$WORKFLOW" \
  || fail "APPROVE 실패 시 approval-failed marker 부재 (Claude 동일 fallback)"
ok "check 13: verdict 정식 리뷰 제출 (approve/comment/request-changes) + 멱등"

echo ""
echo "=== check 14: Claude 동일 게시 구조 — 마커 관리형 PR 코멘트 1개 (AC4/제약) ==="
grep -q 'name: Post Codex review comment' "$WORKFLOW" \
  || fail "'Post Codex review comment' 스텝 부재 (Claude 'Post … review comment' 구조 치환) (제약)"
grep -qF '<!-- codex-api-pr-review -->' "$WORKFLOW" \
  || fail "codex 전용 관리형 코멘트 마커(<!-- codex-api-pr-review -->) 부재 (제약)"
grep -qF 'github.rest.issues.listComments' "$WORKFLOW" \
  || fail "기존 관리형 코멘트 조회(issues.listComments) 부재 — 1개 갱신 보장 불가 (AC4)"
grep -qF 'github.rest.issues.updateComment' "$WORKFLOW" \
  || fail "기존 관리형 코멘트 갱신(issues.updateComment) 경로 부재 (AC4: 최대 1개 갱신)"
grep -qF 'github.rest.issues.createComment' "$WORKFLOW" \
  || fail "관리형 코멘트 생성(issues.createComment) 경로 부재 (AC4)"
grep -qF 'comment.body?.includes(marker)' "$WORKFLOW" \
  || fail "마커 기준 기존 코멘트 식별 부재 (AC4: 마커 기준 최대 1개)"
ok "check 14: 마커 기반 관리형 PR 코멘트 생성/갱신 (최대 1개)"

echo ""
echo "=== check 15: 인라인 리뷰 코멘트 게시 경로 부재 (AC5) ==="
if grep -qF 'pulls.createReview' "$WORKFLOW"; then
  fail "pulls.createReview 잔존 — 인라인 코멘트 게시 경로 제거되어야 함 (AC5)"
fi
if grep -qF 'inlineComments' "$WORKFLOW"; then
  fail "inlineComments 잔존 — 인라인 코멘트 경로 제거되어야 함 (AC5)"
fi
if grep -qF 'inline-only' "$WORKFLOW"; then
  fail "inline-only 정책 잔존 — 인라인 게시 경로 제거되어야 함 (AC5)"
fi
if grep -qF "side: 'RIGHT'" "$WORKFLOW"; then
  fail "inline comment side='RIGHT' 잔존 (AC5)"
fi
ok "check 15: 인라인 리뷰 코멘트 게시 경로 부재"

echo ""
echo "=== check 16: fingerprint 기반 self thread 자동 resolve 경로 부재 (AC5) ==="
if grep -qF 'computeFingerprint' "$WORKFLOW"; then
  fail "computeFingerprint 잔존 — fingerprint resolve 경로 제거되어야 함 (AC5)"
fi
if grep -qF 'resolveReviewThread' "$WORKFLOW"; then
  fail "resolveReviewThread 잔존 — self thread 자동 resolve 제거되어야 함 (AC5)"
fi
if grep -qF 'reviewThreads' "$WORKFLOW"; then
  fail "reviewThreads GraphQL 조회 잔존 (AC5)"
fi
if grep -qF 'resolved_threads' "$WORKFLOW"; then
  fail "resolved_threads 소비 경로 잔존 (AC5)"
fi
if grep -qF 'codex-review-inline' "$WORKFLOW"; then
  fail "codex-review-inline fingerprint 마커 잔존 (AC5)"
fi
if grep -qiF 'fingerprint' "$WORKFLOW"; then
  fail "fingerprint 어휘 잔존 — fingerprint 기반 resolve 제거되어야 함 (AC5)"
fi
ok "check 16: fingerprint self thread 자동 resolve 경로 부재"

echo ""
echo "=== check 17: GitHub App 설치 토큰 발급·App 토큰 approve 경로 부재 (AC5/제약) ==="
if grep -qF 'create-github-app-token' "$WORKFLOW"; then
  fail "create-github-app-token 잔존 — App 설치 토큰 발급 경로 제거되어야 함 (AC5)"
fi
if grep -qF 'app-token' "$WORKFLOW"; then
  fail "app-token 스텝/출력 잔존 (AC5)"
fi
if grep -qF 'app-slug' "$WORKFLOW"; then
  fail "app-slug 동적 봇 식별 잔존 (AC5)"
fi
if grep -qF 'REVIEW_APP_ID' "$WORKFLOW"; then
  fail "REVIEW_APP_ID App 게이트 잔존 (AC5)"
fi
if grep -qF 'dismissReview' "$WORKFLOW"; then
  fail "dismissReview 잔존 (AC5)"
fi
# 자기 트리거/식별은 기본 토큰 봇(github-actions[bot])만 사용.
grep -qF "'github-actions[bot]'" "$WORKFLOW" \
  || fail "기본 토큰 봇 식별(github-actions[bot]) 부재"
ok "check 17: App 토큰 발급·App approve 경로 부재"

echo ""
echo "=== check 18: 권한 범위 — 게시에 필요한 범위만, App/OIDC 전용 권한 없음 (제약) ==="
grep -q 'contents: read' "$WORKFLOW" \
  || fail "contents: read 권한 부재"
grep -q 'pull-requests: write' "$WORKFLOW" \
  || fail "pull-requests: write 권한 부재"
grep -q 'issues: write' "$WORKFLOW" \
  || fail "issues: write 권한 부재"
if grep -q 'id-token: write' "$WORKFLOW"; then
  fail "id-token: write 권한 잔존 — App/OIDC 전용 권한 두지 않음 (제약)"
fi
ok "check 18: 게시 권한 범위만, id-token 없음"

echo ""
echo "=== check 19: third-party actions SHA 고정 ==="
if grep -qE 'uses: actions/[a-z-]+@v[0-9]+' "$WORKFLOW"; then
  fail "GitHub Actions가 mutable version tag 로 참조됨"
fi
grep -qE 'uses: actions/github-script@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "actions/github-script SHA 고정 부재"
grep -qE 'uses: actions/checkout@[0-9a-f]{40}' "$WORKFLOW" \
  || fail "actions/checkout SHA 고정 부재"
ok "check 19: Actions SHA 고정"

echo ""
echo "=== check 20: checkout 이 submodule auth cleanup 실패를 유발하지 않음 ==="
if grep -q 'persist-credentials: false' "$WORKFLOW"; then
  fail "actions/checkout persist-credentials:false 는 gitlink-only .claude/worktrees 에서 submodule cleanup 실패를 유발함"
fi
ok "check 20: checkout 이 persist-credentials:false 를 사용하지 않음"

echo ""
echo "=== check 21: 모델 호출 전 checkout credential 제거 ==="
grep -q 'git config --local --unset-all http.https://github.com/.extraheader' "$WORKFLOW" \
  || fail "모델 호출 전 checkout credential extraheader 제거 부재"
ok "check 21: checkout credential extraheader 제거"

echo ""
echo "=== check 22: PR body 가 review prompt 에 직접 주입되지 않음 ==="
if grep -q 'PR_BODY:' "$WORKFLOW" || grep -q 'echo "\$PR_BODY"' "$WORKFLOW"; then
  fail "PR body 를 Codex review prompt 에 직접 주입하고 있음"
fi
ok "check 22: PR body 직접 주입 없음"

echo ""
echo "=== check 23: prompt 핵심 정책 보존 (비-목표: prompt 내용 불변) ==="
grep -q '토큰 최적화 정책' "$PROMPT" \
  || fail "prompt 토큰 최적화 정책 부재"
grep -q 'Confidence scoring' "$PROMPT" \
  || fail "prompt confidence scoring 정책 부재"
grep -q 'confidence_score < 80' "$PROMPT" \
  || fail "prompt confidence threshold 정책 부재"
grep -q 'valid JSON' "$PROMPT" \
  || fail "prompt JSON-only 출력 규칙 부재"
ok "check 23: prompt 핵심 정책 존재"

echo ""
echo "=== check 24: 공유 schema 핵심 필드 존재 (비-목표: schema 불변) ==="
grep -q '"automation_safety"' "$SCHEMA" \
  || fail "schema automation_safety 부재"
grep -q '"reviewed_context"' "$SCHEMA" \
  || fail "schema reviewed_context 부재"
grep -q '"confidence_score"' "$SCHEMA" \
  || fail "schema confidence_score 부재"
grep -q '"context_requests"' "$SCHEMA" \
  || fail "schema context_requests 부재"
ok "check 24: schema 핵심 필드 존재"

echo ""
echo "=== check 25: 출력 언어 untrusted block 끝 재강조 보존 ==="
grep -qF '## 마지막 재강조 (절대 위반 금지)' "$WORKFLOW" \
  || fail "마지막 재강조 섹션 부재 — 모델이 untrusted PR diff 뒤에서 출력 언어 지시 흘릴 수 있음"
grep -qF '영어 등 다른 언어로 작성하면 안 됩니다' "$WORKFLOW" \
  || fail "출력 언어 명시적 강제 라인 부재"
grep -qF '"$CODEX_REVIEW_LANG"' "$WORKFLOW" \
  || fail "재강조 라인이 CODEX_REVIEW_LANG 변수를 사용하지 않음"
ok "check 25: untrusted block 끝 출력 언어 재강조"

echo ""
echo "ALL CHECKS PASSED"
