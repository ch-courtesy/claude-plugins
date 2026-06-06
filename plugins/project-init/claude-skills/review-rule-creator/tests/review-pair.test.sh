#!/usr/bin/env bash
# Structural acceptance test for the review-rule-creator skill.
# Verifies:
#   - the two fixed sub-rule templates (principles.md, change-adoption.md) exist.
#   - SKILL.md declares name review-rule-creator and its description names both
#     sub-rule output paths (rules/review/principles.md, rules/review/change-adoption.md).
#   - SKILL.md documents co-production of the fixed pair (둘을 항상 함께 기록),
#     not a one-of menu/single-select.
#   - change-adoption.md cross-references rules/review/principles.md and does NOT
#     reference the flat rules/review.md path (dangling-reference guard).
#   - vendor-neutral: principles.md has no hard CLAUDE.md path and no tool-specific
#     marker (autopilot).
#   - principles.md keeps the 9-principle structure (H1 header + "9원칙" section).
#
# Run: bash review-pair.test.sh   (exit 0 = pass)
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$DIR/SKILL.md"
find_shared_templates() {
  local p="$DIR"
  while [ "$p" != "/" ]; do
    if [ -d "$p/shared/review-rule-creator/templates" ]; then
      printf '%s\n' "$p/shared/review-rule-creator/templates"
      return 0
    fi
    p="$(dirname "$p")"
  done
  return 1
}
TEMPLATE_DIR="$(find_shared_templates)"
PRIN="$TEMPLATE_DIR/principles.md"
CADO="$TEMPLATE_DIR/change-adoption.md"

fail=0
check() { # desc, cmd...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc"; fail=1
  fi
}

# ===========================================================================
# 1) both fixed templates exist
# ===========================================================================
check "templates/principles.md exists" test -f "$PRIN"
check "templates/change-adoption.md exists" test -f "$CADO"

# ===========================================================================
# 2) SKILL.md identity + description names both sub-rule output paths
# ===========================================================================
check "SKILL.md exists" test -f "$SKILL"
check "SKILL.md declares name review-rule-creator" grep -qE '^name:[[:space:]]*review-rule-creator[[:space:]]*$' "$SKILL"
check "SKILL.md description names rules/review/principles.md" grep -qF 'rules/review/principles.md' "$SKILL"
check "SKILL.md description names rules/review/change-adoption.md" grep -qF 'rules/review/change-adoption.md' "$SKILL"

# ===========================================================================
# 3) SKILL documents co-production of the fixed pair (not a one-of menu)
# ===========================================================================
check "SKILL.md states the pair is written together (항상 함께)" grep -qF '항상 함께' "$SKILL"
check "SKILL.md frames the two outputs as a fixed pair (페어)" grep -qF '페어' "$SKILL"

# ===========================================================================
# 4) change-adoption.md cross-references principles.md, NOT the flat path
# ===========================================================================
check "change-adoption.md references rules/review/principles.md" grep -qF 'rules/review/principles.md' "$CADO"
check "change-adoption.md has NO flat rules/review.md reference (dangling guard)" \
  bash -c "! grep -qE 'rules/review\.md' '$CADO'"

# ===========================================================================
# 5) vendor-neutral: principles.md has no CLAUDE.md hard path, no tool marker
# ===========================================================================
check "principles.md has no hard CLAUDE.md path (vendor-neutral)" \
  bash -c "! grep -qF 'CLAUDE.md' '$PRIN'"
check "principles.md has no tool-specific marker (autopilot)" \
  bash -c "! grep -qiF 'autopilot' '$PRIN'"

# ===========================================================================
# 6) principles.md keeps the 9-principle structure
# ===========================================================================
check "principles.md has the H1 header" grep -qE '^#[[:space:]].*리뷰' "$PRIN"
check "principles.md has the 9원칙 section" grep -qF '9원칙' "$PRIN"

if [ "$fail" -eq 0 ]; then
  echo "PASS"; exit 0
else
  echo "FAILED"; exit 1
fi
