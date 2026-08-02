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

# gh 스텁 — 마커 기반 증분 base 해석(reviews API) 때문에 synchronize 블록마다
# "마지막 성공 리뷰 마커의 head_sha"가 달라야 해서 블록별로 재생성한다.
# 마커 SHA 는 resolver(pr-review-incremental-base.js)가 hex 만 통과시키므로
# 반드시 hex 문자열이어야 한다.
write_gh_stub() { # $1 = formal-review 마커의 head_sha (hex)
  sed "s/__MARKER_SHA__/$1/" > "$tmp/bin/gh" <<'GH'
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
  'api repos/owner/repo/pulls/12/reviews --paginate')
    printf '[{"user":{"login":"github-actions[bot]","type":"Bot"},"submitted_at":"2026-01-01T00:00:00Z","body":"<!-- claude-formal-review head_sha=__MARKER_SHA__ verdict=approve -->"}]\n'
    ;;
  *)
    echo "unexpected gh call: $*" >&2
    exit 2
    ;;
esac
GH
  chmod +x "$tmp/bin/gh"
}
write_gh_stub beefa123

cat > "$tmp/bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'diff --patch beefa123 head456')
    printf 'diff --git a/src/inc.js b/src/inc.js\n+incremental\n'
    ;;
  'diff --patch deadb123 head456')
    exit 1
    ;;
  'diff --patch base000 head456 -- src/thread.js')
    printf 'diff --git a/src/thread.js b/src/thread.js\n+thread\n'
    ;;
  'diff --patch mergebaseM2 head456 -- src/thread.js')
    printf 'diff --git a/src/thread.js b/src/thread.js\n+thread-fallback\n'
    ;;
  'merge-base --is-ancestor beefa123 head456' \
  | 'merge-base --is-ancestor deadb123 head456' \
  | 'merge-base --is-ancestor cafeb001 head456')
    exit 0
    ;;
  'rev-list --merges beefa123..head456' \
  | 'rev-list --merges deadb123..head456' \
  | 'rev-list --merges base000..head456')
    : # 머지 커밋 없음 — 빈 출력
    ;;
  'rev-list --merges cafeb001..head456')
    printf 'mergecommit1\n'
    ;;
  'rev-list --merges baseM2..head456')
    printf 'mergecommit2\n'
    ;;
  'merge-base base000 head456')
    printf 'mergebaseM1\n'
    ;;
  'merge-base baseM2 head456')
    printf 'mergebaseM2\n'
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
PR_BASE_SHA=base000 \
PR_HEAD_SHA=head456 \
REVIEW_MARKER_PREFIX=claude-formal-review \
REVIEW_BOT_LOGINS='github-actions[bot]' \
REVIEW_OUTPUT_DIR="$out" \
"$SCRIPT"

grep -q '^REVIEW_CONTEXT_MODE=incremental$' "$out/context-mode.env" \
  || fail "synchronize event should use incremental mode"
grep -q '+incremental' "$out/diff.patch" \
  || fail "incremental mode should use marker..head diff"
ok "synchronize event uses incremental diff"

# Regression: anchor.patch must be the canonical PR-vs-base diff (gh pr diff,
# here '+full') even in incremental mode — NOT the incremental diff.patch.
# Validating anchors against the incremental diff mis-marks base-merged lines
# as in-diff → createReview 422 + false-green job failure.
[[ -f "$out/anchor.patch" ]] \
  || fail "anchor.patch must always be produced for createReview anchor validation"
grep -q '+full' "$out/anchor.patch" \
  || fail "incremental mode anchor.patch must be canonical gh pr diff, not the incremental diff"
grep -q '+incremental' "$out/anchor.patch" \
  && fail "anchor.patch must NOT be the incremental diff (would 422 on base-merged lines)"
ok "incremental mode anchor.patch = canonical PR-vs-base diff (createReview-safe)"

out="$tmp/incremental-fallback-out"
mkdir -p "$out"
write_gh_stub deadb123
GITHUB_EVENT_NAME=pull_request \
GITHUB_EVENT_PATH="$FIXTURES/synchronize-missing-before-event.json" \
GITHUB_REPOSITORY=owner/repo \
PR_NUMBER=12 \
PR_BASE_SHA=base000 \
PR_HEAD_SHA=head456 \
REVIEW_MARKER_PREFIX=claude-formal-review \
REVIEW_BOT_LOGINS='github-actions[bot]' \
REVIEW_OUTPUT_DIR="$out" \
"$SCRIPT"

grep -q '^REVIEW_CONTEXT_MODE=incremental$' "$out/context-mode.env" \
  || fail "synchronize event with unreachable diff should still use incremental mode"
grep -q '+full' "$out/diff.patch" \
  || fail "incremental diff failure should fallback to gh pr diff"
ok "incremental diff failure falls back to full PR diff"

# Regression (merge-influx): a base-sync merge commit inside the incremental
# range must NOT be diffed two-dot (it would drag the whole base delta into
# diff.patch → oversized input → review skip → marker never posts → the base
# never advances). The script must detect it and fall back to the canonical
# PR-vs-base diff, labelling the mode so the header stays truthful.
out="$tmp/merge-fallback-out"
mkdir -p "$out"
write_gh_stub cafeb001
GITHUB_EVENT_NAME=pull_request \
GITHUB_EVENT_PATH="$FIXTURES/synchronize-event.json" \
GITHUB_REPOSITORY=owner/repo \
PR_NUMBER=12 \
PR_BASE_SHA=base000 \
PR_HEAD_SHA=head456 \
REVIEW_MARKER_PREFIX=claude-formal-review \
REVIEW_BOT_LOGINS='github-actions[bot]' \
REVIEW_OUTPUT_DIR="$out" \
"$SCRIPT"

grep -q '^REVIEW_CONTEXT_MODE=full-merge-fallback$' "$out/context-mode.env" \
  || fail "merge commit in incremental range should switch to full-merge-fallback"
grep -q '+full' "$out/diff.patch" \
  || fail "merge-fallback diff.patch should be the canonical PR-vs-base diff"
grep -q '+incremental' "$out/diff.patch" \
  && fail "merge-fallback diff.patch must not contain the polluted incremental range"
ok "merge commit influx falls back to canonical PR-vs-base diff"

out="$tmp/thread-out"
mkdir -p "$out"
GITHUB_EVENT_NAME=pull_request_review_comment \
GITHUB_EVENT_PATH="$FIXTURES/thread-reply-event.json" \
GITHUB_REPOSITORY=owner/repo \
PR_NUMBER=12 \
PR_BASE_SHA=base000 \
PR_HEAD_SHA=head456 \
REVIEW_OUTPUT_DIR="$out" \
"$SCRIPT"

grep -q '^REVIEW_CONTEXT_MODE=thread$' "$out/context-mode.env" \
  || fail "thread reply event should use thread mode"
grep -q '"path": "src/thread.js"' "$out/thread.json" \
  || fail "thread mode should persist target thread metadata"
ok "thread reply event uses thread context"

# Regression (thread merge-influx): thread mode keeps its path scope on merge
# influx — only the diff base swaps to the PR-own merge-base. An unscoped full
# diff would bury the reply context under unrelated files.
out="$tmp/thread-merge-fallback-out"
mkdir -p "$out"
GITHUB_EVENT_NAME=pull_request_review_comment \
GITHUB_EVENT_PATH="$FIXTURES/thread-reply-event.json" \
GITHUB_REPOSITORY=owner/repo \
PR_NUMBER=12 \
PR_BASE_SHA=baseM2 \
PR_HEAD_SHA=head456 \
REVIEW_OUTPUT_DIR="$out" \
"$SCRIPT"

grep -q '^REVIEW_CONTEXT_MODE=thread-merge-fallback$' "$out/context-mode.env" \
  || fail "thread mode with merge influx should be labelled thread-merge-fallback"
grep -q '"path": "src/thread.js"' "$out/thread.json" \
  || fail "thread merge-fallback should keep target thread metadata"
grep -q '+thread-fallback' "$out/diff.patch" \
  || fail "thread merge-fallback diff should stay path-scoped on the swapped base"
ok "thread merge influx swaps base only, keeping path scope"

out="$tmp/full-out"
mkdir -p "$out"
GITHUB_EVENT_NAME=pull_request \
GITHUB_EVENT_PATH="$FIXTURES/opened-event.json" \
GITHUB_REPOSITORY=owner/repo \
PR_NUMBER=12 \
PR_BASE_SHA=base000 \
PR_HEAD_SHA=head456 \
REVIEW_OUTPUT_DIR="$out" \
"$SCRIPT"

grep -q '^REVIEW_CONTEXT_MODE=full$' "$out/context-mode.env" \
  || fail "opened pull_request event should use full mode"
grep -q '+full' "$out/diff.patch" \
  || fail "full mode should use gh pr diff fallback"
ok "opened pull_request event uses full context"

echo "ALL CHECKS PASSED"
