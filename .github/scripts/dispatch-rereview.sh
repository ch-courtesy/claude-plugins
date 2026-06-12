#!/usr/bin/env bash
# Trigger a fresh Codex + Claude PR review via workflow_dispatch.
#
# Use as the sequential step after resolving review threads (resolve →
# re-review): a maintainer/flow resolves the threads it considers addressed,
# then runs this to re-review WITHOUT an @codex/@claude mention. The review
# only APPROVEs if that fresh run finds zero findings (model still decides).
#
# This script deliberately does NOT resolve threads — resolution is a human
# judgement (findings actually addressed); auto-resolving would forge approval.
#
# Requires: gh (authenticated, repo write access — workflow_dispatch is gated to
# write access by GitHub). The review workflows must be on the default branch.
#
#   .github/scripts/dispatch-rereview.sh <pr-number>
set -euo pipefail

PR="${1:?usage: dispatch-rereview.sh <pr-number>}"

gh workflow run "Codex PR Review" -f pr="$PR"
gh workflow run "Claude PR Review" -f pr="$PR"

echo "dispatched Codex + Claude re-review for PR #$PR"
