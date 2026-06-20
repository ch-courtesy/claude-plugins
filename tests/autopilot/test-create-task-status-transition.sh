#!/usr/bin/env bash
# autopilot:create-task 스킬 — 등록-후 상태 전이 조건부화 정적 검증 테스트
#
# 계약: create-task 는 완성된 SPEC 본문을 생산한다. 본문에 미해결 마커
# ([NEEDS CLARIFICATION)가 없으면 초기 상태 backlog 를 유지하고, 남아 있으면
# in_design 으로 전이한다. 과거 무조건 in_design 전이는 제거되어야 한다.
# (SKILL.md 는 LLM 지침 산문이므로 동작을 정적 어구로 검증한다.)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/create-task/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$SKILL_MD" ]] || fail "SKILL.md 부재"

echo "=== TEST 1: 무조건 in_design 전이 어구 부재 (negative) ==="
# 과거 §7: "등록 후 ... set_status ... --status in_design 로 전이하고" (무조건)
if grep -qE '등록 후 .*set_status .*--status in_design.* 로 전이' "$SKILL_MD"; then
  fail "SKILL.md에 무조건 in_design 전이 어구가 잔존 (조건부화 위반)"
fi
ok "무조건 in_design 전이 어구 부재"

echo ""
echo "=== TEST 2: 마커 없음 → backlog 분기 명시 ==="
grep -qE '없으면.*backlog' "$SKILL_MD" \
  || fail "SKILL.md에 '마커 없으면 backlog 유지' 분기 없음"
ok "마커 없음 → backlog 분기 명시"

echo ""
echo "=== TEST 3: 마커 잔존 → in_design 분기 명시 ==="
grep -qE '(남아 있으면|있으면).*in_design' "$SKILL_MD" \
  || fail "SKILL.md에 '마커 남아 있으면 in_design 전이' 분기 없음"
ok "마커 잔존 → in_design 분기 명시"

echo ""
echo "=== TEST 4: 전이 분기가 [NEEDS CLARIFICATION 마커 기준임 ==="
grep -qF '[NEEDS CLARIFICATION' "$SKILL_MD" \
  || fail "SKILL.md에 [NEEDS CLARIFICATION 마커 기준 없음"
ok "[NEEDS CLARIFICATION 마커 기준 명시"

echo ""
echo "=== 모든 create-task 등록-후 상태 전이 조건부화 테스트 통과 ==="
