#!/usr/bin/env bash
# Acceptance test for the project-init rules-index SessionStart hook.
#
# Contract (SPEC: project-init-rules-sessionstart-hook):
#   - Scans the TARGET PROJECT's rules/ tree and injects an index: per rule file,
#     its project-relative path + one-line purpose (the file's first H1).
#   - Injects names+purpose ONLY (never full file contents).
#   - No rules/ dir  -> exit 0, no output (silent no-op).
#   - rules/ with no .md -> exit 0, no output.
#   - Project root resolution mirrors the repo convention:
#       CLAUDE_PROJECT_DIR env -> stdin JSON cwd -> PWD.
#   - Vendor-neutral: the script's static text names no plugin/skill/tool marker.
#
# Run: bash rules-index.test.sh   (exit 0 = pass)
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$DIR/rules-index.sh"

fail=0
check() { # desc, cmd...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fail=1; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- fixture: a project with a rules/ tree ----------------------------------
PROJ="$TMP/proj"
mkdir -p "$PROJ/rules/engineering"
printf '# 버전 관리 지침\n\n본문...\n' > "$PROJ/rules/versioning-top.md"
printf -- '---\nx: 1\n---\n# 브랜치 규칙\n\n본문\n' > "$PROJ/rules/engineering/branch.md"
printf -- 'no heading here\njust text\n' > "$PROJ/rules/engineering/noh1.md"

# --- project WITHOUT rules/ -------------------------------------------------
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"

# --- project with rules/ but no .md ----------------------------------------
NOMD="$TMP/nomd"; mkdir -p "$NOMD/rules/sub"
printf -- 'not markdown\n' > "$NOMD/rules/readme.txt"

# 1) hook exists
check "hook script exists" test -f "$HOOK"

# 2) with rules/: emits the index wrapper + path+H1 lines
printf '%s' '{}' | env CLAUDE_PROJECT_DIR="$PROJ" sh "$HOOK" > "$TMP/out1" 2>/dev/null
check "emits <project-rules-index> wrapper" grep -qF '<project-rules-index>' "$TMP/out1"
check "closes wrapper" grep -qF '</project-rules-index>' "$TMP/out1"
check "top-level rule path + H1 purpose" grep -qF 'rules/versioning-top.md — 버전 관리 지침' "$TMP/out1"
check "nested rule path + H1 purpose" grep -qF 'rules/engineering/branch.md — 브랜치 규칙' "$TMP/out1"
check "file without H1 -> path listed" grep -qE 'rules/engineering/noh1\.md' "$TMP/out1"
check "file without H1 -> no purpose em dash on its line" bash -c "! grep -E 'noh1\.md .*—' '$TMP/out1'"
check "does NOT inject full file body" bash -c "! grep -qF '본문...' '$TMP/out1'"
check "paths are project-relative (no temp abs prefix)" bash -c "! grep -qF '$PROJ' '$TMP/out1'"

# 3) no rules/ dir -> no output, exit 0
printf '%s' '{}' | env CLAUDE_PROJECT_DIR="$EMPTY" sh "$HOOK" > "$TMP/out2" 2>/dev/null; rc2=$?
check "no rules/: exit 0" test "$rc2" -eq 0
check "no rules/: empty output" test ! -s "$TMP/out2"

# 4) rules/ exists but no .md -> no output, exit 0
printf '%s' '{}' | env CLAUDE_PROJECT_DIR="$NOMD" sh "$HOOK" > "$TMP/out3" 2>/dev/null; rc3=$?
check "rules/ no .md: exit 0" test "$rc3" -eq 0
check "rules/ no .md: empty output" test ! -s "$TMP/out3"

# 5) project root from stdin cwd when env unset
printf '{"cwd":"%s"}' "$PROJ" | env -u CLAUDE_PROJECT_DIR sh "$HOOK" > "$TMP/out4" 2>/dev/null
check "resolves project root from stdin cwd" grep -qF 'rules/versioning-top.md' "$TMP/out4"

# 6) vendor-neutral: static script text names no plugin/skill/tool marker
check "script has no 'autopilot'" bash -c "! grep -qiF 'autopilot' '$HOOK'"
check "script has no 'using-autopilot'" bash -c "! grep -qiF 'using-autopilot' '$HOOK'"
check "script has no 'fsd' marker" bash -c "! grep -qiwF 'fsd' '$HOOK'"

if [ "$fail" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi
