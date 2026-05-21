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

if [[ "$GITHUB_EVENT_NAME" == "pull_request" && "$action" == "synchronize" && -n "$event_before" ]]; then
  mode="incremental"
  incremental_base="$event_before"
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
    git diff --patch "$incremental_base" "$PR_HEAD_SHA" > "$REVIEW_OUTPUT_DIR/diff.patch"
    ;;
  thread)
    jq -n \
      --arg reply_to_id "$reply_to_id" \
      --arg path "$comment_path" \
      --argjson line "${comment_line:-0}" \
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

{
  printf 'REVIEW_CONTEXT_MODE=%s\n' "$mode"
  printf 'REVIEW_INCREMENTAL_BASE=%s\n' "$incremental_base"
} > "$REVIEW_OUTPUT_DIR/context-mode.env"
