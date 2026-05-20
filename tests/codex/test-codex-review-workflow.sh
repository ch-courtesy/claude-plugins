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
echo "=== check 2: legacy access-token auth is not used ==="
if grep -q 'CODEX_ACCESS_TOKEN' "$WORKFLOW"; then
  fail "CODEX_ACCESS_TOKEN 기반 인증이 남아 있음"
fi
ok "check 2: CODEX_ACCESS_TOKEN 기반 인증 제거됨"

echo ""
echo "=== check 3: review output is posted idempotently ==="
grep -q '<!-- codex-cli-pr-review -->' "$WORKFLOW" \
  || fail "중복 방지 marker 부재"
grep -q 'issues.updateComment' "$WORKFLOW" \
  || fail "기존 리뷰 코멘트 update 경로 부재"
grep -q 'issues.createComment' "$WORKFLOW" \
  || fail "신규 리뷰 코멘트 create 경로 부재"
ok "check 3: marker 기반 update/create 코멘트 경로 존재"

echo ""
echo "ALL CHECKS PASSED"
