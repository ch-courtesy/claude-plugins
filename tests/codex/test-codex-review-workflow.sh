#!/usr/bin/env bash
# Codex PR review workflow authentication contract.
#
# Static checks only: do not call GitHub, npm, or Codex.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKFLOW="$REPO_ROOT/.github/workflows/codex-review.yml"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$WORKFLOW" ]] || fail "$WORKFLOW 부재"

echo "=== check 1: auth.json secret is restored for Codex CLI ==="
grep -q 'CODEX_AUTH_JSON:.*secrets\.CODEX_AUTH_JSON' "$WORKFLOW" \
  || fail "CODEX_AUTH_JSON secret env 매핑 부재"
grep -q 'mkdir -p "\$HOME/\.codex"' "$WORKFLOW" \
  || fail "~/.codex 디렉토리 생성 부재"
grep -q 'printf .*> "\$HOME/\.codex/auth\.json"' "$WORKFLOW" \
  || fail "~/.codex/auth.json 복원 부재"
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
echo "=== check 3: codex review uses --base without a prompt argument ==="
grep -q 'REVIEW_BASE="$(git merge-base "origin/\$PR_BASE_REF" "refs/remotes/pull/\$PR_NUMBER/head")"' "$WORKFLOW" \
  || fail "PR head 와 base branch 의 merge-base 계산 부재"
grep -q -- '--base "\$REVIEW_BASE" \\' "$WORKFLOW" \
  || fail "codex review 가 계산된 REVIEW_BASE 를 사용하지 않음"
grep -q -- '--title "\$PR_TITLE"' "$WORKFLOW" \
  || fail "codex review title 지정 부재"
if grep -q -- '- < \.codex-review/full-prompt\.md' "$WORKFLOW"; then
  fail "codex review --base 와 prompt stdin 입력을 함께 사용하고 있음"
fi
if grep -q '"$(cat \.codex-review/full-prompt\.md)"' "$WORKFLOW"; then
  fail "prompt 전체를 커맨드라인 인자로 전달하고 있음"
fi
ok "check 3: codex review --base 를 prompt 인자 없이 실행"

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
grep -qE 'npm install -g @openai/codex@[0-9]+\.[0-9]+\.[0-9]+' "$WORKFLOW" \
  || fail "@openai/codex 버전 고정 부재"
if grep -q 'PR_BASE_SHA:' "$WORKFLOW" || grep -q 'PR_HEAD_SHA:' "$WORKFLOW"; then
  fail "미사용 PR_BASE_SHA/PR_HEAD_SHA env 가 남아 있음"
fi
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
echo "ALL CHECKS PASSED"
