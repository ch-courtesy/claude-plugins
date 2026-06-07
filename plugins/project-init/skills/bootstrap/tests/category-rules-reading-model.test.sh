#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
BASE="$ROOT/plugins/project-init/shared/bootstrap/AGENTS.md"

fail=0
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fail=1; fi; }

check "mentions session-start injected index" grep -qF '인덱스' "$BASE"
check "names+purpose only at session start" grep -qE '이름.*목적|목적.*이름' "$BASE"
check "no full pre-read required" grep -qE '선읽기.*(않|금지)|미리 읽지 않' "$BASE"
check "read content right before work" grep -qF '직전' "$BASE"
check "mentions workflow entry branch" grep -qF '진입 분기' "$BASE"
check "branch precedes content reading" grep -qF '먼저' "$BASE"
check "keeps force" grep -qF '예외 없이' "$BASE"
check "keeps gravest-defect framing" grep -qF '무거운 결함' "$BASE"
check "single H1" bash -c "[ \"\$(grep -cE '^# ' '$BASE')\" -eq 1 ]"
check "H1 is category guidance" grep -qxF '# 카테고리별 지침' "$BASE"

if [ "$fail" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi
