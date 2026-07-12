#!/usr/bin/env bash
# Structural acceptance test for the review-approval "머지 방식 single-select" SPEC.
# Verifies the model:
#   - both review-approval.<backend>.md templates declare an inputs block with a
#     SINGLE input named merge_method.
#   - merge_method is SINGLE-select (NOT multi_select: true) — the project picks
#     exactly one merge method.
#   - options carry backend-appropriate methods (github: rebase; gitlab:
#     fast-forward; both: merge commit + squash) plus exactly one default-checked
#     option (default: true) that degrades to the prior passive "follow repo
#     config" guidance when the answer is missing.
#   - body uses the single placeholder {{merge_method}} for the chosen clause, and
#     the static pre-merge check bullet (conflicts resolved + checks/pipeline green)
#     stands regardless of the choice.
#   - SKILL.md documents single-select input handling (단일 선택, single value
#     substitution, default-on-missing) alongside the existing multi-select doc.
#
# Run: bash review-approval-merge-method.test.sh   (exit 0 = pass)
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$DIR/SKILL.md"
GH="$DIR/templates/review-approval.github.md"
GL="$DIR/templates/review-approval.gitlab.md"

fail=0
check() { # desc, cmd...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc"; fail=1
  fi
}

# number of distinct {{...}} placeholders in a file
distinct_ph() { grep -oE '\{\{[a-zA-Z_]+\}\}' "$1" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//'; }
# line number of the second `---` (end of frontmatter), empty if none
fmend() { grep -nE '^---[[:space:]]*$' "$1" | sed -n '2p' | cut -d: -f1; }

# ===========================================================================
# 1) both templates exist and declare sub_rule review-approval
# ===========================================================================
check "review-approval.github.md exists" test -f "$GH"
check "review-approval.gitlab.md exists" test -f "$GL"
check "github template declares sub_rule review-approval" grep -qE '^sub_rule:[[:space:]]*review-approval[[:space:]]*$' "$GH"
check "gitlab template declares sub_rule review-approval" grep -qE '^sub_rule:[[:space:]]*review-approval[[:space:]]*$' "$GL"

# ===========================================================================
# 2) inputs block with a SINGLE input named merge_method
# ===========================================================================
for f in "$GH" "$GL"; do
  b="$(basename "$f")"
  check "$b declares an inputs block" grep -qF 'inputs:' "$f"
  check "$b declares an input named merge_method" grep -qE '^[[:space:]]*-[[:space:]]*name:[[:space:]]*merge_method[[:space:]]*$' "$f"
  ninputs="$(grep -cE '^[[:space:]]*-[[:space:]]*name:' "$f")"
  check "$b declares exactly ONE input" bash -c "[ '$ninputs' -eq 1 ]"
  # SINGLE-select: must NOT be multi_select: true
  check "$b merge_method is single-select (no multi_select: true)" \
    bash -c "! grep -qE 'multi_select:[[:space:]]*true' '$f'"
done

# ===========================================================================
# 3) backend-appropriate method options + exactly one default-checked option
# ===========================================================================
check "github options include merge commit" grep -qF 'merge commit' "$GH"
check "github options include squash" grep -qF 'squash' "$GH"
check "github options include rebase (github-specific)" grep -qF 'rebase' "$GH"
check "gitlab options include merge commit" grep -qF 'merge commit' "$GL"
check "gitlab options include squash" grep -qF 'squash' "$GL"
check "gitlab options include fast-forward (gitlab-specific)" grep -qF 'fast-forward' "$GL"
# variant separation: github must NOT offer fast-forward; gitlab must NOT offer rebase
check "github does NOT offer fast-forward" bash -c "! grep -qF 'fast-forward' '$GH'"
check "gitlab does NOT offer rebase" bash -c "! grep -qF 'rebase' '$GL'"

for f in "$GH" "$GL"; do
  b="$(basename "$f")"
  ndef="$(grep -cE 'default:[[:space:]]*true' "$f")"
  check "$b has exactly one default-checked option" bash -c "[ '$ndef' -eq 1 ]"
done

# ===========================================================================
# 4) single placeholder {{merge_method}} in body; static pre-merge bullet kept
# ===========================================================================
for f in "$GH" "$GL"; do
  b="$(basename "$f")"
  check "$b has a closed frontmatter block" bash -c "[ -n \"\$(grep -nE '^---[[:space:]]*\$' '$f' | sed -n '2p')\" ]"
  ph="$(distinct_ph "$f")"
  check "$b body uses the single placeholder {{merge_method}}" bash -c "[ '$ph' = '{{merge_method}}' ]"
  check "$b retains the 머지 방식 section header" grep -qF '## 머지 방식' "$f"
  # static pre-merge check bullet survives (conflict resolution + green) below frontmatter
  e="$(fmend "$f")"
  check "$b keeps a pre-merge green-check bullet" \
    bash -c "tail -n +$e '$f' | grep -qF '충돌' && tail -n +$e '$f' | grep -qF 'green'"
done

# ===========================================================================
# 5) SKILL.md documents single-select handling (additive, multi-select kept)
# ===========================================================================
check "SKILL.md documents single-select (단일 선택)" grep -qF '단일 선택' "$SKILL"
check "SKILL.md still documents multi-select (multi_select)" grep -qF 'multi_select' "$SKILL"
check "SKILL.md still documents aggregate placeholder (집계)" grep -qF '집계' "$SKILL"
check "SKILL.md still documents {{name}} substitution" grep -qF '{{' "$SKILL"
check "SKILL.md still documents value-over-label" grep -qF 'value' "$SKILL"
check "SKILL.md still documents default-on-missing" grep -qF 'default' "$SKILL"
check "SKILL.md mentions merge_method consumer" grep -qF 'merge_method' "$SKILL"

# ===========================================================================
# 6) references split: input-substitution detail delegated out of SKILL.md
# ===========================================================================
REF="$DIR/references"
check "references/input-substitution.md exists" test -f "$REF/input-substitution.md"
check "references/template_tools.py exists (deterministic script)" test -f "$REF/template_tools.py"
# SKILL.md keeps only the contract/summary and points substitution detail out.
check "SKILL.md points input-substitution detail to references/input-substitution.md" \
  grep -qF 'references/input-substitution.md' "$SKILL"
check "SKILL.md delegates aggregate concat to references/template_tools.py" \
  grep -qF 'references/template_tools.py aggregate' "$SKILL"

if [ "$fail" -eq 0 ]; then
  echo "PASS"; exit 0
else
  echo "FAILED"; exit 1
fi
