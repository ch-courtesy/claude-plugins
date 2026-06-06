#!/usr/bin/env bash
# Structural acceptance test for the version-control "git 공통 정책 multi-select 집계" SPEC.
# Verifies the NEW model:
#   - templates/git.md declares git common policy input as ONE multi-select question
#     (multi_select: true), not per-policy single-select questions.
#   - force push 금지 is the FIRST option and is default-checked (default: true).
#   - body has a SINGLE aggregate placeholder ({{git_policies}}); no per-policy
#     placeholder like {{force_push_policy}}.
#   - 허용 is expressed by leaving force push 금지 unchecked (no separate 허용 option /
#     no value:"" empty-value option needed).
#   - always-create: intro (header + git-family classification) stands without any policy.
#   - SKILL.md documents the static multi-select aggregate mechanism (multi_select,
#     집계 placeholder, default-checked, default-on-missing) and git-family
#     co-production (review-approval + git together), NOT a git-vs-review-approval
#     single-select menu.
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

# ===========================================================================
# 1) templates/git.md: single multi-select question
# ===========================================================================
check "templates/git.md exists" test -f "$TPL"
check "git.md frontmatter declares sub_rule git" grep -qE '^sub_rule:[[:space:]]*git[[:space:]]*$' "$TPL"
check "git.md declares an inputs block" grep -qF 'inputs:' "$TPL"
check "git.md declares multi-select (multi_select: true)" grep -qE 'multi_select:[[:space:]]*true' "$TPL"

# exactly ONE input under inputs: => exactly one `- name:` entry
ninputs="$(grep -cE '^[[:space:]]*-[[:space:]]*name:' "$TPL")"
check "git.md declares exactly ONE input (one aggregate question)" \
  bash -c "[ '$ninputs' -eq 1 ]"

# the single input is named git_policies (aggregate over policies, not per-policy)
check "git.md single input is named git_policies" grep -qE '^[[:space:]]*-[[:space:]]*name:[[:space:]]*git_policies[[:space:]]*$' "$TPL"

# ===========================================================================
# 2) force push 금지 = first option + default-checked
# ===========================================================================
check "git.md has a force push 금지 option clause" bash -c "grep -qF 'force push' '$TPL' && grep -qF '금지' '$TPL'"

# first option label must mention force push 금지
firstlabel="$(lineno_re "$TPL" '^[[:space:]]*-[[:space:]]*label:')"
firstdeny="$(lineno_re "$TPL" '^[[:space:]]*-[[:space:]]*label:.*(force push|금지)')"
check "git.md FIRST option label is force push 금지" \
  bash -c "[ -n '$firstlabel' ] && [ -n '$firstdeny' ] && [ '$firstlabel' -eq '$firstdeny' ]"

# default-checked marker present
check "git.md marks force push option default-checked (default: true)" grep -qE 'default:[[:space:]]*true' "$TPL"

# default: true must belong to the FIRST option (before any 2nd option label, if any)
deflineno="$(lineno_re "$TPL" 'default:[[:space:]]*true')"
secondlabel="$(grep -nE '^[[:space:]]*-[[:space:]]*label:' "$TPL" | sed -n '2p' | cut -d: -f1)"
check "git.md default-checked belongs to the first option" \
  bash -c "[ -n '$deflineno' ] && [ '$deflineno' -gt '$firstlabel' ] && { [ -z '$secondlabel' ] || [ '$deflineno' -lt '$secondlabel' ]; }"

# ===========================================================================
# 3) single aggregate placeholder; NO per-policy placeholder
# ===========================================================================
# body (after frontmatter) — frontmatter is delimited by the first two `---`
fmend="$(grep -nE '^---[[:space:]]*$' "$TPL" | sed -n '2p' | cut -d: -f1)"
check "git.md has a closed frontmatter block" bash -c "[ -n '$fmend' ]"

# exactly one distinct {{...}} placeholder in the file, and it is {{git_policies}}
distinct_ph="$(grep -oE '\{\{[a-zA-Z_]+\}\}' "$TPL" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
check "git.md body uses the single aggregate placeholder {{git_policies}}" \
  bash -c "[ '$distinct_ph' = '{{git_policies}}' ]"
check "git.md has NO per-policy {{force_push_policy}} placeholder" \
  bash -c "! grep -qF '{{force_push_policy}}' '$TPL'"

# ===========================================================================
# 4) 허용 = unchecked (no separate empty-value 허용 option)
# ===========================================================================
check "git.md does NOT carry a separate empty-value option (value:\"\")" \
  bash -c "! grep -qE 'value:[[:space:]]*\"\"[[:space:]]*$' '$TPL'"

# ===========================================================================
# 5) always-create intro: header + git-family classification anchor
# ===========================================================================
check "git.md body has the H1 header" grep -qE '^#[[:space:]].*git' "$TPL"
check "git.md intro states git-family classification" grep -qF 'git 계열' "$TPL"

# ===========================================================================
# 6) no backend-variant git template (single body, always git.md)
# ===========================================================================
check "no backend-variant git template (git.<backend>.md) exists" \
  bash -c "! ls '$DIR/templates/' | grep -qE '^git\.[a-z]+\.md$'"

# ===========================================================================
# 7) SKILL.md: multi-select aggregate mechanism
# ===========================================================================
check "SKILL.md documents a multi-select input (multi_select)" grep -qF 'multi_select' "$SKILL"
check "SKILL.md documents aggregate placeholder substitution (집계)" grep -qF '집계' "$SKILL"
check "SKILL.md documents {{name}} placeholder substitution" grep -qF '{{' "$SKILL"
check "SKILL.md documents value-over-label substitution rule" grep -qF 'value' "$SKILL"
check "SKILL.md documents default-checked default-on-missing" grep -qF 'default' "$SKILL"
check "SKILL.md still mentions force push default-on-missing (금지)" grep -qF 'force push' "$SKILL"

# ===========================================================================
# 8) SKILL.md: git-family co-production, NOT git-vs-review-approval menu
# ===========================================================================
check "SKILL.md mentions git 계열 (git-family)" grep -qF 'git 계열' "$SKILL"
check "SKILL.md declares static git-family classification incl github" grep -qF 'github' "$SKILL"
check "SKILL.md declares static git-family classification incl gitlab" grep -qF 'gitlab' "$SKILL"
check "SKILL.md reuses existing backend determination (no new detection)" grep -qF '재사용' "$SKILL"
check "SKILL.md fixes git common output to git.md" grep -qF 'git.md' "$SKILL"
check "SKILL.md documents review-approval + git co-production (함께 산출)" grep -qF '함께 산출' "$SKILL"
check "SKILL.md describes git common as a companion output (동반)" grep -qF '동반' "$SKILL"

# git must NOT be offered as a single-select choice competing with review-approval.
# Guard the specific old phrasing that gated git into the single-select sub-rule menu.
check "SKILL.md does not gate git into the single-select sub-rule menu (old phrasing gone)" \
  bash -c "! grep -qF 'git 계열 공통 sub-룰 게이팅' '$SKILL'"

# ===========================================================================
# 9) backend determination still precedes git-family handling
# ===========================================================================
detstep="$(lineno_re "$SKILL" '^[0-9]+\. \*\*백엔드 판별')"
check "SKILL.md still describes backend determination step" bash -c "[ -n '$detstep' ]"

if [ "$fail" -eq 0 ]; then
  echo "PASS"; exit 0
else
  echo "FAILED"; exit 1
fi
