#!/usr/bin/env bash
# Structural acceptance test for the version-control "git 계열 공통 지침 (force-push 토글)" SPEC.
# Verifies:
#   - SKILL.md documents the inputs substitution mechanism (mirroring engineering-rule-creator)
#   - SKILL.md documents git-family gating via a static backend classification reusing
#     the existing backend determination, output rules/version-control/git.md
#   - SKILL.md documents non-git exclusion + user notice, and force-push default-on-missing
#   - templates/git.md exists: sub_rule git, inputs force_push_policy, 금지 first+Recommended
#     with prohibition-clause value, 허용 with empty value, {{force_push_policy}} placeholder
#
# Run: bash git-common-force-push.test.sh   (exit 0 = pass)
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$DIR/SKILL.md"
TPL="$DIR/templates/git.md"

fail=0
check() { # desc, cmd...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc"; fail=1
  fi
}

# line number of first line matching a fixed string (empty if none)
lineno() { grep -nF -m1 "$2" "$1" 2>/dev/null | cut -d: -f1; }
# line number of first line matching an extended regex (empty if none)
lineno_re() { grep -nE -m1 "$2" "$1" 2>/dev/null | cut -d: -f1; }

# --- 1) inputs substitution mechanism in SKILL.md (mirrors engineering-rule-creator) ---
check "SKILL.md documents an inputs mechanism" grep -qF 'inputs' "$SKILL"
check "SKILL.md mirrors engineering-rule-creator inputs" grep -qF 'engineering-rule-creator' "$SKILL"
check "SKILL.md documents {{name}} placeholder substitution" grep -qF '{{' "$SKILL"
check "SKILL.md documents value-over-label substitution rule" grep -qF 'value' "$SKILL"

# --- 2) git-family gating + static classification in SKILL.md ---
check "SKILL.md mentions git 계열 (git-family)" grep -qF 'git 계열' "$SKILL"
check "SKILL.md declares static git-family classification incl github" grep -qF 'github' "$SKILL"
check "SKILL.md declares static git-family classification incl gitlab" grep -qF 'gitlab' "$SKILL"
check "SKILL.md reuses existing backend determination (no new detection)" grep -qF '재사용' "$SKILL"
check "SKILL.md fixes git common output to git.md" grep -qF 'git.md' "$SKILL"

# --- 3) non-git exclusion + notice, and force-push default-on-missing in SKILL.md ---
check "SKILL.md documents non-git exclusion notice" bash -c "grep -qF '계열이 아니' '$SKILL' || grep -qF '비-git' '$SKILL'"
check "SKILL.md documents force-push default-on-missing (금지)" grep -qF 'force push' "$SKILL"

# --- 4) templates/git.md existence + frontmatter ---
check "templates/git.md exists" test -f "$TPL"
check "git.md frontmatter declares sub_rule git" grep -qE '^sub_rule:[[:space:]]*git[[:space:]]*$' "$TPL"
check "git.md declares an inputs block" grep -qF 'inputs:' "$TPL"
check "git.md declares force_push_policy input" grep -qF 'force_push_policy' "$TPL"

# --- 4-bis) step order: backend determination is described BEFORE git-family gating ---
# Guards the reviewed contradiction where the gating step referenced a later
# detection step's result (forward reference / step-number vs execution-order mismatch).
detstep="$(lineno_re "$SKILL" '^[0-9]+\. \*\*백엔드 판별')"
gatestep="$(lineno_re "$SKILL" 'git 계열 공통 sub-룰 게이팅')"
check "SKILL.md describes backend determination before git-family gating" \
  bash -c "[ -n '$detstep' ] && [ -n '$gatestep' ] && [ '$detstep' -lt '$gatestep' ]"
check "SKILL.md has no forward-reference to a later detection step in gating" \
  bash -c "! grep -qF '3단계의 백엔드 판별 결과를 재사용' '$SKILL'"

# --- 5) 금지 option: first, Recommended, carries prohibition clause ---
check "git.md marks an option (Recommended)" grep -qF '(Recommended)' "$TPL"
check "git.md prohibition option text mentions force push 금지" bash -c "grep -qF 'force push' '$TPL' && grep -qF '금지' '$TPL'"

# 금지 option label must appear before 허용 option label (recommended is first).
# Match the option `label:` lines specifically, not the question prose which
# mentions both words.
nodeny="$(lineno_re "$TPL" '^[[:space:]]*-?[[:space:]]*label:.*금지')"
noallow="$(lineno_re "$TPL" '^[[:space:]]*-?[[:space:]]*label:.*허용')"
check "git.md 금지 option label appears before 허용 option label" bash -c "[ -n '$nodeny' ] && [ -n '$noallow' ] && [ '$nodeny' -lt '$noallow' ]"

# --- 6) 허용 option supplies an empty value ---
check "git.md provides an empty value (허용 => placeholder removed)" grep -qE 'value:[[:space:]]*""' "$TPL"

# --- 7) body placeholder ---
check "git.md body has {{force_push_policy}} placeholder" grep -qF '{{force_push_policy}}' "$TPL"

# --- 8) git common sub-rule has NO backend variant (single body, always git.md) ---
check "no backend-variant git template (git.<backend>.md) exists" \
  bash -c "! ls '$DIR/templates/' | grep -qE '^git\.[a-z]+\.md$'"

if [ "$fail" -eq 0 ]; then
  echo "PASS"; exit 0
else
  echo "FAILED"; exit 1
fi
