#!/usr/bin/env bash
# loop 워커 지침 구성이 소비 프로젝트의 벤더 지침(AGENTS.md/CLAUDE.md → rules 인덱스 등)을
# 보존하고 그 뒤에 constitution 을 병합하는지 검증(정적). 회귀: 과거엔 constitution 을
# CLAUDE.md/AGENTS.md 로 cp 덮어써 워커가 프로젝트 지침(versioning 등)을 보지 못했다.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFS="$SCRIPT_DIR/../references"
LOOP_SH="$REFS/loop.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$LOOP_SH" ]] || fail "loop.sh 부재: $LOOP_SH"

# 1) 더 이상 constitution 을 CLAUDE.md/AGENTS.md 로 덮어쓰지(cp) 않는다(프로젝트 지침 유실 회귀 방지).
if grep -qE 'cp +"\$SCRIPT_DIR/constitution\.md" +"\$WT/(CLAUDE|AGENTS)\.md"' "$LOOP_SH"; then
  fail "loop.sh 가 여전히 constitution 을 CLAUDE.md/AGENTS.md 로 cp 덮어쓴다 — 프로젝트 지침 유실"
fi

# 2) 원본(프로젝트 지침) 보존 + 병합 로직 존재.
grep -q '_loop_base' "$LOOP_SH"   || fail "원본 지침 보존(_loop_base) 로직 부재"
grep -q '_loop_merged' "$LOOP_SH" || fail "병합(_loop_merged) 로직 부재"

# 3) 병합본을 두 워커 지침 파일에 기록.
grep -qE 'printf .+_loop_merged.+> *"\$WT/CLAUDE\.md"' "$LOOP_SH" \
  || fail "CLAUDE.md 에 병합본 기록 부재"
grep -qE 'printf .+_loop_merged.+> *"\$WT/AGENTS\.md"' "$LOOP_SH" \
  || fail "AGENTS.md 에 병합본 기록 부재"

# 4) 병합 기반은 워크트리의 기존 프로젝트 지침(AGENTS.md 우선, 없으면 CLAUDE.md)이어야 한다.
grep -q '"\$WT/AGENTS.md"' "$LOOP_SH" || fail "병합 기반에서 워크트리 AGENTS.md 참조 부재"

echo "=== loop 프로젝트 지침 보존+병합 테스트 통과 ==="
