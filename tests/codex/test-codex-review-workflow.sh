#!/usr/bin/env bash
# Codex PR review workflow contract.
#
# Static checks only: do not call GitHub, npm, or Codex.
#
# This workflow calls the model through the official openai/codex-action and
# publishes results as a SINGLE inline review: findings become inline review
# comments anchored to changed lines, the review summary rides in the review
# body, and self-owned inline threads auto-resolve on a deterministic
# fingerprint basis. The legacy codex-only paths — direct `codex exec`/`codex
# review` CLI calls and the GitHub App installation token / App-token APPROVE —
# are gone, as is the separate marker-managed issue-level finding comment.
# These checks assert the inline+resolve structure exists and removed paths are
# absent. The posting logic mirrors claude-review.yml byte-identically except
# for label/marker/prefix strings.

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
# Placeholder server-info seed: the action's "Read server info" step fires on
# prompt presence but the proxy that writes that file only runs with an API
# key. Without the seed the job dies on "Failed to read server info". The seed
# file name must be "<codex_home>/<github.run_id>.json" per action.yml, and the
# JSON must carry a numeric "port" (read-server-info skips a non-numeric port).
# Assert port + run_id filename on the SAME line so a seed that drops the port
# (e.g. printf '{}' > ".../<run_id>.json") fails — a separate `grep port` would
# pass on unrelated tokens like "export" elsewhere in the workflow.
grep -Eq "printf '\{\"port\":[0-9]+\}' > \"\\\$codex_home/\\\$\{GITHUB_RUN_ID\}\.json\"" "$WORKFLOW" \
  || fail "codex-home 에 더미 server-info 시드(<run_id>.json, numeric port) 부재 — auth.json 단독 호출 시 'Read server info' 실패 회귀 (AC2)"
ok "check 4: CODEX_AUTH_JSON → codex-home/auth.json(600) + server-info 시드 → action codex-home 입력"

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
# App 봇 자동 게시 self-trigger 차단(AC4): @codex 멘션 요구가 멘션 없는 App
# 자동 게시(리뷰/인라인)를 이미 배제한다. comment/review 트리거 분기 모두
# @codex 멘션을 요구하므로 App 봇 identity 게시 이벤트는 재트리거하지 않는다.
mention_count="$(count "contains(github.event.comment.body, '@codex')" "$WORKFLOW")"
review_mention_count="$(count "contains(github.event.review.body, '@codex')" "$WORKFLOW")"
(( mention_count + review_mention_count >= 3 )) \
  || fail "@codex 멘션 요구가 comment/review 트리거 3개 분기에 모두 있지 않음 — App 자동게시 self-trigger 배제 불가 (AC4)"
# App 봇 identity(<slug>[bot])는 'github-actions[bot]' 리터럴 배제로는 걸러지지 않으므로,
# 모든 봇 작성 comment/review 이벤트를 user.type 로 배제해 App 봇 self-trigger 루프를 막는다 (AC4).
comment_bot_type="$(count "github.event.comment.user.type != 'Bot'" "$WORKFLOW")"
review_bot_type="$(count "github.event.review.user.type != 'Bot'" "$WORKFLOW")"
(( comment_bot_type >= 2 && review_bot_type >= 1 )) \
  || fail "App 봇 포함 봇 작성 이벤트 배제(user.type != 'Bot')가 comment 2개·review 1개 분기에 없음 (AC4)"
ok "check 12: @codex + author association + 봇 차단 + 멘션 요구 + user.type!=Bot 로 App 봇 self-trigger 배제"

echo ""
echo "=== check 13: 단일 inline 리뷰 제출 — verdict/event + 승인 본문 + 멱등 (AC1/AC7) ==="
grep -q 'name: Submit Codex inline review' "$WORKFLOW" \
  || fail "'Submit Codex inline review' 스텝 부재 (단일 inline 리뷰 게시 스텝 치환) (제약)"
# 단일 createReview(comments[]) 로 inline + 본문을 한 번에 제출. event 는 APPROVE/COMMENT 만.
grep -qF 'github.rest.pulls.createReview' "$WORKFLOW" \
  || fail "Pulls REST createReview 호출 부재 — inline 단일 리뷰 제출 불가 (AC1)"
grep -qF "event === 'APPROVE'" "$WORKFLOW" \
  || fail "APPROVE event 분기 부재 (AC1)"
grep -qF "event = 'COMMENT'" "$WORKFLOW" \
  || fail "COMMENT event 분기 부재 (AC1)"
# REQUEST_CHANGES review event 는 폐지. may_request_changes(automation_safety) 외 request_changes 토큰 금지.
if grep -qF 'REQUEST_CHANGES' "$WORKFLOW"; then
  fail "REQUEST_CHANGES 잔존 — 공식 review event 는 APPROVE/COMMENT 만 (제약)"
fi
if grep -oE '[a-z_]*request_changes' "$WORKFLOW" | grep -qvE '^may_request_changes$'; then
  fail "request_changes verdict 어휘 잔존 (may_request_changes 외) — 제거 필요 (제약)"
fi
# 리뷰 본문(body): approve 시에만 헤더 + 승인 문구, 그 외엔 마커만 — 요약 미작성.
grep -qF '## Codex PR 리뷰' "$WORKFLOW" \
  || fail "리뷰 본문 헤더 '## Codex PR 리뷰' 부재 (제약: codex 라벨)"
# 리뷰 요약(summary) 작성 폐지 — 본문에 result.summary 를 싣지 않는다.
if grep -qF 'result.summary' "$WORKFLOW"; then
  fail "result.summary 잔존 — 리뷰 요약 본문 게시 폐지 위반 (제약: summary 미작성)"
fi
# approve(event === 'APPROVE')일 때만 본문에 단순 승인 문구를 싣는다.
grep -qF '승인되었습니다.' "$WORKFLOW" \
  || fail "승인 본문 문구('승인되었습니다.') 부재 (제약: approve 시 승인 사실만)"
# 멱등 마커 (head_sha, verdict) 기준 + listReviews 조회 + 중복 skip.
grep -qF 'CODEX_FORMAL_PREFIX: codex-formal-review' "$WORKFLOW" \
  || fail "formal review 마커 prefix(CODEX_FORMAL_PREFIX: codex-formal-review) 부재 (제약)"
grep -qF '${prefix} head_sha=${head_sha} verdict=${verdict}' "$WORKFLOW" \
  || fail "formal review 멱등 마커 템플릿(<!-- {prefix} head_sha=.. verdict=.. -->) 부재 (제약)"
grep -qF 'github.rest.pulls.listReviews' "$WORKFLOW" \
  || fail "기존 review 조회(listReviews) 부재 — 멱등성 판정 불가 (AC1)"
grep -qF 'skipping duplicate submission' "$WORKFLOW" \
  || fail "marker 기반 중복 review 제출 skip 부재 (멱등)"
# APPROVE 실패 → COMMENT 강등 + approval-failed 기록 (AC7).
grep -qF "fs.writeFileSync('.codex-review/approval-failed'" "$WORKFLOW" \
  || fail "APPROVE 실패 시 approval-failed marker 기록 부재 (AC7)"
grep -qF "submit('COMMENT')" "$WORKFLOW" \
  || fail "APPROVE 실패 시 같은 inline 코멘트로 COMMENT 강등 제출 부재 (AC7)"
ok "check 13: 단일 inline 리뷰 제출 (APPROVE/COMMENT) + 승인 본문(요약 미작성) + 멱등 + APPROVE fallback"

echo ""
echo "=== check 14: 별도 마커 관리형 이슈 레벨 코멘트 게시 경로 부재 (AC6) ==="
grep -q 'name: Post Codex review comment' "$WORKFLOW" \
  && fail "'Post Codex review comment' 스텝 잔존 — 이슈 코멘트 게시 경로 제거 필요 (AC6)"
if grep -qF '<!-- codex-api-pr-review -->' "$WORKFLOW"; then
  fail "관리형 이슈 코멘트 마커(<!-- codex-api-pr-review -->) 잔존 (AC6)"
fi
if grep -qF 'github.rest.issues.createComment' "$WORKFLOW"; then
  fail "issues.createComment 잔존 — 발견사항 이슈 코멘트 게시 금지 (AC6)"
fi
if grep -qF 'github.rest.issues.updateComment' "$WORKFLOW"; then
  fail "issues.updateComment 잔존 — 관리형 이슈 코멘트 갱신 경로 금지 (AC6)"
fi
ok "check 14: 마커 관리형 이슈 레벨 코멘트 게시 경로 부재"

echo ""
echo "=== check 15: 인라인 리뷰 코멘트 게시 경로 존재 (AC1/AC2) ==="
grep -qF 'comments: inlineComments' "$WORKFLOW" \
  || fail "createReview 의 comments[] 배열에 inline findings(inlineComments) 전달 부재 (AC1)"
grep -qF 'inline-only' "$WORKFLOW" \
  || fail "inline-only 정책 주석/마커 부재 (모든 finding 을 inline 으로 게시) (AC6)"
grep -qF "side: 'RIGHT'" "$WORKFLOW" \
  || fail "inline comment side='RIGHT' 지정 부재 (AC1)"
grep -qF 'start_line' "$WORKFLOW" \
  || fail "multi-line inline comment 의 start_line 처리 부재 (AC1)"
# createReview 실패 시 finding 을 이슈 코멘트로 덤프하지 않는다 (inline-only).
if grep -qF 'inlineFallback' "$WORKFLOW"; then
  fail "inlineFallback 경로 잔존 — createReview 실패 시 이슈 코멘트 덤프 금지 (AC6)"
fi
ok "check 15: 인라인 리뷰 코멘트 게시 경로 존재 (createReview comments[] + RIGHT + start_line)"

echo ""
echo "=== check 16: fingerprint 기반 self thread 자동 resolve 경로 존재 (AC3/AC4) ==="
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
grep -qF '<!-- codex-review-inline' "$WORKFLOW" \
  || fail "inline self-식별 마커 substring(<!-- codex-review-inline) 부재 (AC2)"
grep -qF 'fingerprint=${computeFingerprint(f)}' "$WORKFLOW" \
  || fail "게시 inline 마커가 결정론적 computeFingerprint(f) 를 운반하지 않음 (AC2/AC3)"
grep -qF 'botLoginGql' "$WORKFLOW" \
  || fail "GraphQL author login 형식 정규화(botLoginGql) 부재 (AC4)"
grep -qF 'isResolved' "$WORKFLOW" \
  || fail "isResolved 조건 검사 부재 (이미 resolved thread skip)"
# verdict 무관 실행 + 모델 자유 fingerprint 미사용.
grep -qF 'regardless of verdict' "$WORKFLOW" \
  || fail "resolve 가 verdict 무관 실행임을 명시하는 마커(regardless of verdict) 부재 (AC4)"
if grep -qF 'fingerprint=${f.fingerprint}' "$WORKFLOW"; then
  fail "게시 마커가 모델 자유 생성 f.fingerprint 운반 — 결정론 계산으로 전환되어야 함 (AC3)"
fi
ok "check 16: fingerprint self thread 자동 resolve 경로 존재 (resolved_threads 1차 + fallback)"

echo ""
echo "=== check 16b: 결정론적 fingerprint — file+perspective+normalized title, 줄번호 비의존 (AC3) ==="
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
ok "check 16b: 결정론적 fingerprint(file+perspective+title), 줄번호 비의존"

echo ""
echo "=== check 17: GitHub App 설치 토큰 발급 + 동적 봇 식별 + graceful degradation (AC1/AC2/AC3/AC5/제약) ==="
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
# 기본 토큰 사용 시 봇 식별은 기존 github-actions[bot] 유지.
grep -qF "'github-actions[bot]'" "$WORKFLOW" \
  || fail "기본 토큰 봇 식별(github-actions[bot]) 폴백 부재 (AC5)"
ok "check 17: App 토큰 발급(SHA 고정) + 동적 봇 식별 + graceful degradation"

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
echo "=== check 26: diff-only anchor 검증 + false-green 가드 (공유 단위) (AC1/AC2/AC4/AC5/제약) ==="
ANCHOR_MODULE="$REPO_ROOT/.github/scripts/diff-anchor-filter.js"
[[ -f "$ANCHOR_MODULE" ]] \
  || fail "공유 검증 모듈 .github/scripts/diff-anchor-filter.js 부재 (제약: 단일 공유 단위)"
# 두 워크플로가 byte 복제 대신 같은 단일 모듈을 require 한다.
grep -qF '.github/scripts/diff-anchor-filter.js' "$WORKFLOW" \
  || fail "워크플로가 공유 검증 모듈(.github/scripts/diff-anchor-filter.js)을 require 하지 않음 (AC5/제약)"
grep -qF 'filterFindingsAgainstPatch' "$WORKFLOW" \
  || fail "공유 검증 단위 호출(filterFindingsAgainstPatch) 부재 (AC1/AC5)"
# 검증 입력은 이미 생성된 diff.patch — 새로 diff 계산하지 않는다 (제약).
grep -qF ".review-context/diff.patch" "$WORKFLOW" \
  || fail "anchor 검증 입력으로 .review-context/diff.patch 소비 부재 (제약)"
# valid(in-diff)만 inline 제출 배치로 사용 — 제외는 배치 구성 전에.
grep -qF 'valid: inlineFindings' "$WORKFLOW" \
  || fail "in-diff valid finding 만 inlineFindings 로 사용하지 않음 (AC2/제약)"
grep -qF 'excluded: excludedFindings' "$WORKFLOW" \
  || fail "diff 밖 finding 분리(excluded) 부재 (AC2)"
# 제외 finding 의 file·line·title 을 로그로 남긴다 (AC2).
grep -qF 'Excluded out-of-diff finding' "$WORKFLOW" \
  || fail "제외 finding 로그(file·line·title) 부재 (AC2)"
# false-green 가드: 게시할 in-diff finding 이 있는데 제출 실패면 job 실패.
grep -qF 'core.setFailed' "$WORKFLOW" \
  || fail "제출 실패 시 job 을 실패시키는 가드(core.setFailed) 부재 (AC4)"
grep -qE 'setFailed\(.*createReview failed' "$WORKFLOW" \
  || fail "createReview 실패가 false-green 가드(setFailed)로 연결되지 않음 (AC4)"
# 가드는 inlineFindings(=in-diff) 가 있을 때만 — 0건/정상강등은 실패로 보지 않음 (AC4/제약).
grep -qF '!skipSubmit && !submitOk && inlineFindings.length > 0' "$WORKFLOW" \
  || fail "false-green 가드 게이트(in-diff finding 존재 시에만 실패)가 inlineFindings.length>0 로 한정되지 않음 (AC4/제약)"
# 실패를 경고로만 끝내던 옛 경로가 setFailed 로 대체됐는지 — createReview 실패에 warning 잔존 금지.
if grep -qE 'core\.warning\(`createReview failed' "$WORKFLOW"; then
  fail "createReview 실패가 여전히 core.warning 으로만 처리됨 — false-green 가드(setFailed) 회귀 (AC4)"
fi
# 공유 검증 모듈은 trusted-base 체크아웃에서 로드되므로, 모듈을 도입·수정하는
# 워크플로 PR 에선 base 에 아직 없어 require 가 실패한다(self-bootstrap). 이때
# unhandled crash 대신 unfiltered 로 graceful degrade 해야 한다 — require 를
# try/catch 로 감싸고 기본값(findings)으로 fallback 한다.
grep -qF 'let inlineFindings = findings;' "$WORKFLOW" \
  || fail "validator 부재 시 fallback 기본값(let inlineFindings = findings) 부재 — self-bootstrap 시 unhandled crash 위험 (robustness)"
grep -qF 'Shared diff-anchor validator unavailable' "$WORKFLOW" \
  || fail "validator require 실패를 graceful degrade(경고+unfiltered fallback)로 처리하지 않음 (robustness)"
ok "check 26: 공유 diff-only anchor 검증 + 제외 로그 + false-green setFailed 가드 + validator 부재 graceful degrade"

echo ""
echo "ALL CHECKS PASSED"
