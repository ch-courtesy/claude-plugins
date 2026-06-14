#!/usr/bin/env bash
# Acceptance test for references/template_tools.py.
# Verifies (PR 408 review delta):
#   - parse-name / git-family without an argument exit 2 with a usage message on
#     stderr instead of crashing with an IndexError (blocking/100 x2).
#   - normal behavior is preserved (regression guard for the arg-count change).
#   - SKILL.md allowed-tools no longer grants blanket `Bash(python3:*)` and instead
#     scopes execution to the template_tools.py subcommands (Codex blocking/95).
#
# Run: bash template_tools.test.sh   (exit 0 = pass)
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$DIR/references/template_tools.py"
SKILL="$DIR/SKILL.md"

fail=0
ok()   { echo "ok   - $1"; }
bad()  { echo "FAIL - $1"; fail=1; }

# run_tool: captures stdout, stderr, exit code into globals OUT ERR RC
run_tool() {
  ERR_FILE="$(mktemp)"
  OUT="$(python3 "$TOOL" "$@" 2>"$ERR_FILE")"
  RC=$?
  ERR="$(cat "$ERR_FILE")"
  rm -f "$ERR_FILE"
}

# ===========================================================================
# 1) Missing-argument guards: exit 2 + usage on stderr, no traceback.
# ===========================================================================
run_tool parse-name
[ "$RC" -eq 2 ] && ok "parse-name without arg exits 2" || bad "parse-name without arg exits 2 (got $RC)"
echo "$ERR" | grep -qiF "usage" && ok "parse-name without arg prints usage" || bad "parse-name without arg prints usage"
echo "$ERR" | grep -q "Traceback" && bad "parse-name without arg must not traceback" || ok "parse-name without arg no traceback"

run_tool git-family
[ "$RC" -eq 2 ] && ok "git-family without arg exits 2" || bad "git-family without arg exits 2 (got $RC)"
echo "$ERR" | grep -qiF "usage" && ok "git-family without arg prints usage" || bad "git-family without arg prints usage"
echo "$ERR" | grep -q "Traceback" && bad "git-family without arg must not traceback" || ok "git-family without arg no traceback"

# ===========================================================================
# 2) Normal behavior preserved (regression guard).
# ===========================================================================
run_tool parse-name review-approval.github.md
{ [ "$RC" -eq 0 ] && [ "$OUT" = "review-approval	github" ]; } \
  && ok "parse-name splits backend variant" || bad "parse-name splits backend variant (rc=$RC out=$OUT)"

run_tool parse-name branch-naming.md
{ [ "$RC" -eq 0 ] && [ "$OUT" = "branch-naming	" ]; } \
  && ok "parse-name no-variant leaves backend blank" || bad "parse-name no-variant (rc=$RC out=$OUT)"

run_tool git-family github
[ "$RC" -eq 0 ] && ok "git-family github exits 0" || bad "git-family github exits 0 (got $RC)"

run_tool git-family svn
[ "$RC" -eq 1 ] && ok "git-family non-member exits 1" || bad "git-family non-member exits 1 (got $RC)"

run_tool aggregate a b "" c
{ [ "$RC" -eq 0 ] && [ "$OUT" = "$(printf 'a\n\nb\n\nc')" ]; } \
  && ok "aggregate joins non-empty values" || bad "aggregate joins (rc=$RC out=$OUT)"

# ===========================================================================
# 3) SKILL.md allowed-tools: no blanket python3, scoped to template_tools.py.
# ===========================================================================
grep -qE '^\s*-\s*Bash\(python3:\*\)\s*$' "$SKILL" \
  && bad "SKILL.md must not grant blanket Bash(python3:*)" \
  || ok "SKILL.md no blanket Bash(python3:*)"
grep -qF 'Bash(python3 references/template_tools.py' "$SKILL" \
  && ok "SKILL.md scopes python3 to template_tools.py" \
  || bad "SKILL.md scopes python3 to template_tools.py"

echo
[ "$fail" -eq 0 ] && echo "PASS" || echo "SOME TESTS FAILED"
exit "$fail"
