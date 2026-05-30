#!/usr/bin/env bash
# Structural acceptance test for the bootstrap "Claude 상호작용 규칙" opt-in SPEC.
# Verifies the single-source assembly model:
#   - base CLAUDE.md template = always-included "카테고리별 지침" only
#   - interaction-rules asset  = the optional "Claude 상호작용 규칙" section
#   - SKILL.md documents the AskUserQuestion include/exclude branch
#
# Run: bash interaction-rules-optin.test.sh   (exit 0 = pass)
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$DIR/CLAUDE.md"
ASSET="$DIR/assets/interaction-rules.ko.md"
SKILL="$DIR/SKILL.md"

fail=0
check() { # desc, cmd...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc"; fail=1
  fi
}

# 1) Interaction-rules asset exists and holds the section (single source of truth).
check "interaction-rules asset exists" test -f "$ASSET"
check "asset has '## Claude 상호작용 규칙' heading" grep -qF '## Claude 상호작용 규칙' "$ASSET"
check "asset documents AskUserQuestion usage" grep -qF 'AskUserQuestion' "$ASSET"

# 2) Base template always carries "카테고리별 지침".
check "base CLAUDE.md has '## 카테고리별 지침'" grep -qF '## 카테고리별 지침' "$BASE"

# 3) EXCLUDE invariant: base (== exclude-path output) must NOT contain the
#    interaction-rules section in ANY form (heading or body), so it is not
#    duplicated and the exclude path cannot leak it.
check "base CLAUDE.md has NO interaction-rules heading" bash -c "! grep -qF 'Claude 상호작용 규칙' '$BASE'"
check "base CLAUDE.md has NO AskUserQuestion interaction body" bash -c "! grep -qF 'AskUserQuestion' '$BASE'"

# 4) SKILL.md documents the opt-in question + neutral, only-when-absent behavior.
check "SKILL.md references interaction-rules asset" grep -qF 'interaction-rules.ko.md' "$SKILL"
check "SKILL.md asks via AskUserQuestion for the section" grep -qF '상호작용 규칙' "$SKILL"

if [ "$fail" -eq 0 ]; then
  echo "PASS"; exit 0
else
  echo "FAILED"; exit 1
fi
