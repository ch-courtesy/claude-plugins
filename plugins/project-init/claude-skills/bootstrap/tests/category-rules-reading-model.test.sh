#!/usr/bin/env bash
# Acceptance test for the bootstrap "카테고리별 지침" base template reading-model
# reconstruction (SPEC: project-init-rules-sessionstart-hook, conditions 3/4/6).
#
# The base template must:
#   (3) name-first / content-just-in-time: at session start, learn file
#       names+purpose from the injected index ONLY (no full pre-read); read a
#       file's content right before related work, and follow it.
#   (4) vendor-neutral gate carve-out: if a session-start-injected workflow entry
#       rule requires presenting an entry branch first, then on new code-change
#       signals that branch presentation precedes category-content reading
#       (branch presentation is not "starting work").
#   (6) vendor-neutral: names no plugin/skill or tool marker prefix.
#   + must NOT weaken the existing force (violation = gravest defect; follow
#     relevant content "예외 없이").
#   + structural invariants kept (single H1 '# 카테고리별 지침', no AskUserQuestion,
#     no interaction-rules section) so the assembly/exclude test still holds.
#
# Run: bash category-rules-reading-model.test.sh   (exit 0 = pass)
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$DIR/CLAUDE.md"

fail=0
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fail=1; fi; }

# --- (3) name-first / content-just-in-time ----------------------------------
check "mentions session-start injected index" grep -qF '인덱스' "$BASE"
check "names+purpose only at session start" grep -qE '이름.*목적|목적.*이름' "$BASE"
check "no full pre-read required (선읽기 ... 않/금지)" grep -qE '선읽기.*(않|금지)|미리 읽지 않' "$BASE"
check "read content right before work (직전)" grep -qF '직전' "$BASE"

# --- (4) vendor-neutral gate carve-out --------------------------------------
check "mentions workflow entry branch (진입 분기)" grep -qF '진입 분기' "$BASE"
check "branch precedes content reading (먼저)" grep -qF '먼저' "$BASE"
check "branch presentation is not 'starting work'" grep -qE '분기 제시.*(작업|탐색)' "$BASE"
check "ties carve-out to new code-change signal" grep -qF '코드 변경' "$BASE"

# --- force preserved --------------------------------------------------------
check "keeps '예외 없이' force" grep -qF '예외 없이' "$BASE"
check "keeps gravest-defect framing" grep -qF '무거운 결함' "$BASE"

# --- (6) vendor-neutral + structural invariants -----------------------------
check "no 'autopilot' marker" bash -c "! grep -qiF 'autopilot' '$BASE'"
check "no 'using-autopilot' marker" bash -c "! grep -qiF 'using-autopilot' '$BASE'"
check "no 'fsd' marker" bash -c "! grep -qiwF 'fsd' '$BASE'"
check "no AskUserQuestion (kept out)" bash -c "! grep -qF 'AskUserQuestion' '$BASE'"
check "no interaction-rules section leaked" bash -c "! grep -qF '상호작용 규칙' '$BASE'"
check "single H1" bash -c "[ \"\$(grep -cE '^# ' '$BASE')\" -eq 1 ]"
check "H1 is '# 카테고리별 지침'" grep -qxF '# 카테고리별 지침' "$BASE"

if [ "$fail" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi
