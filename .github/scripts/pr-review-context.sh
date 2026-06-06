#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_EVENT_NAME:?GITHUB_EVENT_NAME is required}"
: "${GITHUB_EVENT_PATH:?GITHUB_EVENT_PATH is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${PR_HEAD_SHA:?PR_HEAD_SHA is required}"

REVIEW_OUTPUT_DIR="${REVIEW_OUTPUT_DIR:-.review-context}"
mkdir -p "$REVIEW_OUTPUT_DIR"

mode="full"
incremental_base=""

action="$(jq -r '.action // ""' "$GITHUB_EVENT_PATH")"
event_before="$(jq -r '.before // empty' "$GITHUB_EVENT_PATH")"
reply_to_id="$(jq -r '.comment.in_reply_to_id // empty' "$GITHUB_EVENT_PATH")"
comment_path="$(jq -r '.comment.path // empty' "$GITHUB_EVENT_PATH")"
comment_line="$(jq -r '.comment.line // empty' "$GITHUB_EVENT_PATH")"

if [[ "$GITHUB_EVENT_NAME" == "pull_request" && "$action" == "synchronize" ]]; then
  : "${REVIEW_MARKER_PREFIX:?REVIEW_MARKER_PREFIX is required for synchronize events}"
  # Incremental base = the commit THIS reviewer last SUCCESSFULLY reviewed — NOT
  # the webhook event.before. event.before is the previous push head, which
  # GitHub advances on every push regardless of whether the prior review ran; a
  # failed review (e.g. usage-limit → nothing posted) would then be skipped by
  # the next incremental diff while the check still goes green. The success-gated
  # per-reviewer source of truth is this reviewer's most recent formal-review
  # marker (<!-- $REVIEW_MARKER_PREFIX head_sha=<sha> ... -->), posted only when a
  # review is actually submitted. Take the latest marker SHA that is an ancestor
  # of the current head; fall back to a full diff (mode stays "full") when none
  # qualifies — first review, all prior reviews failed/unavailable, or the marker
  # SHA is unreachable after a force-push/rebase/squash.
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  base_resolver="$script_dir/pr-review-incremental-base.js"
  # gh --paginate emits one JSON array per page back-to-back; jq -s 'add' merges
  # them into a single flat array (and a lone page stays itself).
  reviews_json="$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/reviews" --paginate 2>/dev/null \
    | jq -c -s 'add // []' 2>/dev/null || true)"
  if [[ -n "$reviews_json" && -f "$base_resolver" ]]; then
    while IFS= read -r cand_sha; do
      [[ -n "$cand_sha" ]] || continue
      if git merge-base --is-ancestor "$cand_sha" "$PR_HEAD_SHA" 2>/dev/null; then
        mode="incremental"
        incremental_base="$cand_sha"
        break
      fi
    done < <(printf '%s' "$reviews_json" | node "$base_resolver" "$REVIEW_MARKER_PREFIX" 2>/dev/null || true)
  fi
elif [[ "$GITHUB_EVENT_NAME" == "pull_request_review_comment" && -n "$reply_to_id" && -n "$comment_path" ]]; then
  mode="thread"
  incremental_base="${PR_BASE_SHA:-${event_before:-HEAD~1}}"
fi

gh pr view "$PR_NUMBER" \
  --repo "$GITHUB_REPOSITORY" \
  --json number,url,title,author,baseRefName,headRefName,additions,deletions,changedFiles,state,isDraft \
  > "$REVIEW_OUTPUT_DIR/pr.json"

gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
  > "$REVIEW_OUTPUT_DIR/issue-comments.json"

gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/comments" \
  > "$REVIEW_OUTPUT_DIR/review-comments.json"

case "$mode" in
  incremental)
    git diff --patch "$incremental_base" "$PR_HEAD_SHA" > "$REVIEW_OUTPUT_DIR/diff.patch" || {
      gh pr diff "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --patch > "$REVIEW_OUTPUT_DIR/diff.patch"
    }
    ;;
  thread)
    jq -n \
      --arg reply_to_id "$reply_to_id" \
      --arg path "$comment_path" \
      --argjson line "${comment_line:-null}" \
      '{reply_to_id: $reply_to_id, path: $path, line: $line}' \
      > "$REVIEW_OUTPUT_DIR/thread.json"
    git diff --patch "$incremental_base" "$PR_HEAD_SHA" -- "$comment_path" > "$REVIEW_OUTPUT_DIR/diff.patch" || {
      gh pr diff "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --patch > "$REVIEW_OUTPUT_DIR/diff.patch"
    }
    ;;
  full)
    gh pr diff "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --patch > "$REVIEW_OUTPUT_DIR/diff.patch"
    ;;
  *)
    echo "unknown review context mode: $mode" >&2
    exit 1
    ;;
esac

# Anchor-validation patch — ALWAYS the canonical PR-vs-base diff that GitHub's
# createReview validates inline-comment anchors against. The mode-specific
# diff.patch above is for the MODEL (incremental on synchronize). Using that
# incremental diff for anchor validation mis-classifies base-merged lines as
# in-diff: a file absent in the previous-reviewed SHA (the incremental base) shows
# as fully-added, so its unchanged-vs-base lines pass the off-diff filter and then
# get 422 "Line could not be resolved" from createReview — which the inline-only
# false-green guard turns into a failed job. `gh pr diff` is exactly the diff
# GitHub resolves anchors against, so validate against it in every mode.
gh pr diff "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --patch \
  > "$REVIEW_OUTPUT_DIR/anchor.patch" \
  || cp "$REVIEW_OUTPUT_DIR/diff.patch" "$REVIEW_OUTPUT_DIR/anchor.patch"

{
  printf 'REVIEW_CONTEXT_MODE=%s\n' "$mode"
  printf 'REVIEW_INCREMENTAL_BASE=%s\n' "$incremental_base"
} > "$REVIEW_OUTPUT_DIR/context-mode.env"
