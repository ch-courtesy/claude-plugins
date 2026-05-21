#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="$REPO_ROOT/.github/scripts/pr-review-context.sh"
FIXTURES="$REPO_ROOT/tests/review-context/fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

[[ -x "$SCRIPT" ]] || fail "$SCRIPT executable 부재"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'pr view 12 --repo owner/repo --json number,url,title,author,baseRefName,headRefName,additions,deletions,changedFiles,state,isDraft')
    printf '{"number":12,"title":"Test PR","state":"OPEN","isDraft":false}\n'
    ;;
  'pr diff 12 --repo owner/repo --patch')
    printf 'diff --git a/src/full.js b/src/full.js\n+full\n'
    ;;
  'api repos/owner/repo/issues/12/comments')
    printf '[{"id":1,"body":"<!-- claude-api-pr-review --> old"}]\n'
    ;;
  'api repos/owner/repo/pulls/12/comments')
    printf '[{"id":2,"path":"src/thread.js","line":9,"body":"old inline"}]\n'
    ;;
  *)
    echo "unexpected gh call: $*" >&2
    exit 2
    ;;
esac
GH
chmod +x "$tmp/bin/gh"

cat > "$tmp/bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'diff --patch before123 head456')
    printf 'diff --git a/src/inc.js b/src/inc.js\n+incremental\n'
    ;;
  'diff --patch HEAD~1 head456 -- src/thread.js')
    printf 'diff --git a/src/thread.js b/src/thread.js\n+thread\n'
    ;;
  *)
    echo "unexpected git call: $*" >&2
    exit 2
    ;;
esac
GIT
chmod +x "$tmp/bin/git"

PATH="$tmp/bin:$PATH"

out="$tmp/out"
mkdir -p "$out"
GITHUB_EVENT_NAME=pull_request \
GITHUB_EVENT_PATH="$FIXTURES/synchronize-event.json" \
GITHUB_REPOSITORY=owner/repo \
PR_NUMBER=12 \
PR_HEAD_SHA=head456 \
REVIEW_OUTPUT_DIR="$out" \
"$SCRIPT"

grep -q '^REVIEW_CONTEXT_MODE=incremental$' "$out/context-mode.env" \
  || fail "synchronize event should use incremental mode"
grep -q '+incremental' "$out/diff.patch" \
  || fail "incremental mode should use before..head diff"
ok "synchronize event uses incremental diff"

out="$tmp/thread-out"
mkdir -p "$out"
GITHUB_EVENT_NAME=pull_request_review_comment \
GITHUB_EVENT_PATH="$FIXTURES/thread-reply-event.json" \
GITHUB_REPOSITORY=owner/repo \
PR_NUMBER=12 \
PR_HEAD_SHA=head456 \
REVIEW_OUTPUT_DIR="$out" \
"$SCRIPT"

grep -q '^REVIEW_CONTEXT_MODE=thread$' "$out/context-mode.env" \
  || fail "thread reply event should use thread mode"
grep -q '"path": "src/thread.js"' "$out/thread.json" \
  || fail "thread mode should persist target thread metadata"
ok "thread reply event uses thread context"

echo "ALL CHECKS PASSED"
