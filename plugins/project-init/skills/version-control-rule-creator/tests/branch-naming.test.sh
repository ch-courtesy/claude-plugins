#!/usr/bin/env bash
# Structural acceptance test for the version-control "branch-naming" sub-rule.
# Verifies:
#   - templates/branch-naming.md declares sub_rule branch-naming.
#   - the policy input is ONE multi-select question (multi_select: true), named
#     branch_policies — exactly one `- name:` entry.
#   - exactly the first TWO options (type 접두사, 소문자 kebab-case) are
#     default-checked (exactly two `default: true`); the 3rd/4th are not.
#   - body uses a SINGLE aggregate placeholder ({{branch_policies}}); no per-policy
#     placeholder.
#   - always-create intro (H1 header + purpose sentence) stands without any policy.
#   - no backend-variant template (branch-naming.<backend>.md) — single body, always
#     branch-naming.md (branch naming is backend-independent).
#
# Run: bash branch-naming.test.sh   (exit 0 = pass)
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$DIR/templates/branch-naming.md"

fail=0
check() { # desc, cmd...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc"; fail=1
  fi
}

# line number of first line matching an extended regex (empty if none)
lineno_re() { grep -nE -m1 "$2" "$1" 2>/dev/null | cut -d: -f1; }

# ===========================================================================
# 1) templates/branch-naming.md: single multi-select question
# ===========================================================================
check "templates/branch-naming.md exists" test -f "$TPL"
check "branch-naming.md frontmatter declares sub_rule branch-naming" grep -qE '^sub_rule:[[:space:]]*branch-naming[[:space:]]*$' "$TPL"
check "branch-naming.md declares an inputs block" grep -qF 'inputs:' "$TPL"
check "branch-naming.md declares multi-select (multi_select: true)" grep -qE 'multi_select:[[:space:]]*true' "$TPL"

# exactly ONE input under inputs: => exactly one `- name:` entry
ninputs="$(grep -cE '^[[:space:]]*-[[:space:]]*name:' "$TPL")"
check "branch-naming.md declares exactly ONE input (one aggregate question)" \
  bash -c "[ '$ninputs' -eq 1 ]"

# the single input is named branch_policies (aggregate over policies, not per-policy)
check "branch-naming.md single input is named branch_policies" grep -qE '^[[:space:]]*-[[:space:]]*name:[[:space:]]*branch_policies[[:space:]]*$' "$TPL"

# ===========================================================================
# 2) exactly the first TWO options default-checked; 3rd/4th NOT
# ===========================================================================
firstlabel="$(lineno_re "$TPL" '^[[:space:]]*-[[:space:]]*label:')"
secondlabel="$(grep -nE '^[[:space:]]*-[[:space:]]*label:' "$TPL" | sed -n '2p' | cut -d: -f1)"
thirdlabel="$(grep -nE '^[[:space:]]*-[[:space:]]*label:' "$TPL" | sed -n '3p' | cut -d: -f1)"
check "branch-naming.md has at least one option label" bash -c "[ -n '$firstlabel' ]"

# exactly TWO `default: true` markers (type 접두사 + 소문자 kebab-case)
ndef="$(grep -cE 'default:[[:space:]]*true' "$TPL")"
check "branch-naming.md marks exactly TWO options default-checked" bash -c "[ '$ndef' -eq 2 ]"

# the first default belongs to the FIRST option (between 1st and 2nd label)
firstdef="$(lineno_re "$TPL" 'default:[[:space:]]*true')"
check "branch-naming.md first default belongs to the first option" \
  bash -c "[ -n '$firstdef' ] && [ -n '$secondlabel' ] && [ '$firstdef' -gt '$firstlabel' ] && [ '$firstdef' -lt '$secondlabel' ]"

# the SECOND default belongs to the SECOND option (between 2nd and 3rd label).
# This guards against both defaults landing inside option 1 with option 2 unchecked
# (which would still satisfy count==2 and "before 3rd label").
seconddef="$(grep -nE 'default:[[:space:]]*true' "$TPL" | sed -n '2p' | cut -d: -f1)"
check "branch-naming.md second default belongs to the second option" \
  bash -c "[ -n '$seconddef' ] && [ -n '$secondlabel' ] && [ -n '$thirdlabel' ] && [ '$seconddef' -gt '$secondlabel' ] && [ '$seconddef' -lt '$thirdlabel' ]"

# ===========================================================================
# 3) single aggregate placeholder; NO per-policy placeholder
# ===========================================================================
fmend="$(grep -nE '^---[[:space:]]*$' "$TPL" | sed -n '2p' | cut -d: -f1)"
check "branch-naming.md has a closed frontmatter block" bash -c "[ -n '$fmend' ]"

# exactly one distinct {{...}} placeholder in the file, and it is {{branch_policies}}
distinct_ph="$(grep -oE '\{\{[a-zA-Z_]+\}\}' "$TPL" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
check "branch-naming.md body uses the single aggregate placeholder {{branch_policies}}" \
  bash -c "[ '$distinct_ph' = '{{branch_policies}}' ]"

# ===========================================================================
# 4) always-create intro: H1 header + purpose anchor
# ===========================================================================
check "branch-naming.md body has the H1 header" grep -qE '^#[[:space:]].*브랜치' "$TPL"
check "branch-naming.md intro states a purpose sentence" grep -qF '브랜치 이름' "$TPL"

# ===========================================================================
# 5) no backend-variant branch-naming template (single body, always branch-naming.md)
# ===========================================================================
check "no backend-variant branch-naming template (branch-naming.<backend>.md) exists" \
  bash -c "! ls '$DIR/templates/' | grep -qE '^branch-naming\.[a-z]+\.md$'"

if [ "$fail" -eq 0 ]; then
  echo "PASS"; exit 0
else
  echo "FAILED"; exit 1
fi
