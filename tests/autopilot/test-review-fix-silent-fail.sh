#!/usr/bin/env bash
# test-review-fix-silent-fail.sh — SPEC 181
# review-fix-phase silent-fail false-positive: statusCheckRollup 빈 상태 오판 회귀 검사.
#
# evaluate_silent_fail()를 단위 호출해 4가지 statusCheckRollup mock 시나리오와
# grace 기간 동작·환경변수 명시(정적 검사)를 검증한다. 실제 gh CLI/PR 접근 없음.

set -uo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$THIS_DIR/../.." && pwd)"
SCRIPT="$ROOT/plugins/autopilot/skills/loop/references/review-fix-phase.sh"
SKILL_MD="$ROOT/plugins/autopilot/skills/loop/SKILL.md"

if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: review-fix-phase.sh 미존재 ($SCRIPT)" >&2
  exit 1
fi

PASSED=0
FAILED=0

pass() { echo "PASS: $*"; PASSED=$((PASSED + 1)); }
fail() { echo "FAIL: $*" >&2; FAILED=$((FAILED + 1)); }

# evaluate_silent_fail 단위 호출 헬퍼.
# 인자: fetch_fail pending total_checks reviews comments inline elapsed grace
run_eval() {
  local fetch_fail="$1" pending="$2" total="$3" reviews="$4" comments="$5" inline="$6" elapsed="$7" grace="$8"
  REVIEW_FIX_PHASE_TEST_MODE=1 SCRIPT_PATH="$SCRIPT" \
    bash -c '
      set -uo pipefail
      # shellcheck disable=SC1090
      source "$SCRIPT_PATH"
      evaluate_silent_fail "$@"
    ' _ "$fetch_fail" "$pending" "$total" "$reviews" "$comments" "$inline" "$elapsed" "$grace" 2>/dev/null
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$desc"
  else
    fail "$desc — expected '$expected', got '$actual'"
  fi
}

# ---------- (a-i) 빈 rollup + grace 기간 안 → GRACE_SKIP (AC1) ----------
got=$(run_eval 0 0 0 0 0 0 60 300)
assert_eq "(a-i) 빈 rollup + grace 안 → GRACE_SKIP" "GRACE_SKIP" "$got"

# ---------- (a-ii) 빈 rollup + grace 기간 밖 → EMPTY_ROLLUP_SKIP (AC2) ----------
got=$(run_eval 0 0 0 0 0 0 600 300)
assert_eq "(a-ii) 빈 rollup + grace 밖 → EMPTY_ROLLUP_SKIP" "EMPTY_ROLLUP_SKIP" "$got"

# ---------- (a-iii) [COMPLETED] + grace 기간 안 → GRACE_SKIP (grace 우선) ----------
# total_checks>0이라도 grace 안이면 ESCALATE_STUCK이 아닌 GRACE_SKIP 반환 — grace 분기가
# total_checks 분기보다 우선 (evaluate_silent_fail 우선순위 2 > 3·4).
got=$(run_eval 0 0 1 0 0 0 60 300)
assert_eq "(a-iii) [COMPLETED] + grace 안 → GRACE_SKIP" "GRACE_SKIP" "$got"

# ---------- (b) [COMPLETED] + 활동 0 + grace 후 → ESCALATE_STUCK (AC3 회귀 보존) ----------
got=$(run_eval 0 0 1 0 0 0 600 300)
assert_eq "(b) [COMPLETED] + 활동 0 + grace 후 → ESCALATE_STUCK" "ESCALATE_STUCK" "$got"

# ---------- (c) [IN_PROGRESS] → pending=1 → RESET_COUNTER (기존 동작 회귀) ----------
got=$(run_eval 0 1 1 0 0 0 600 300)
assert_eq "(c) [IN_PROGRESS] pending=1 → RESET_COUNTER" "RESET_COUNTER" "$got"

# ---------- (d) [COMPLETED, IN_PROGRESS] → pending=1, total=2 → RESET_COUNTER (기존 동작 회귀) ----------
got=$(run_eval 0 1 2 0 0 0 600 300)
assert_eq "(d) [COMPLETED, IN_PROGRESS] pending=1 → RESET_COUNTER" "RESET_COUNTER" "$got"

# ---------- (e) fetch_fail=1 — grace보다 우선 ESCALATE_FETCH_FAIL ----------
got=$(run_eval 1 0 0 0 0 0 60 300)
assert_eq "(e) fetch_fail=1 → ESCALATE_FETCH_FAIL (grace보다 우선)" "ESCALATE_FETCH_FAIL" "$got"

# ---------- (f) 활동 있음 (reviews>0) + 빈 rollup + grace 후 → RESET_COUNTER ----------
# total_checks=0이면 EMPTY_ROLLUP_SKIP 분기가 먼저 잡지만, 안전 회귀: pending=0+활동>0 케이스도 escalate 안 함.
got=$(run_eval 0 0 1 1 0 0 600 300)
assert_eq "(f) [COMPLETED] + reviews>0 + grace 후 → RESET_COUNTER" "RESET_COUNTER" "$got"

# ---------- AC4 정적 검사 — env var name, 기본값, floor 명시 ----------
if grep -q 'LOOP_REVIEW_PR_GRACE_SECS' "$SCRIPT"; then
  pass "(AC4) env var name 'LOOP_REVIEW_PR_GRACE_SECS' script에 명시"
else
  fail "(AC4) env var name 'LOOP_REVIEW_PR_GRACE_SECS' script에 미명시"
fi

if grep -qE 'LOOP_REVIEW_PR_GRACE_SECS:-300' "$SCRIPT"; then
  pass "(AC4) 기본값 300s (5분) script에 명시"
else
  fail "(AC4) 기본값 300s 미명시"
fi

if grep -qE 'GRACE_SECS[[:space:]]*<[[:space:]]*0' "$SCRIPT"; then
  pass "(AC4) GRACE_SECS floor 처리 script에 명시"
else
  fail "(AC4) GRACE_SECS floor 처리 미명시"
fi

# ---------- AC4 SKILL.md 명시 ----------
if [[ -f "$SKILL_MD" ]] && grep -q 'LOOP_REVIEW_PR_GRACE_SECS' "$SKILL_MD"; then
  pass "(AC4) SKILL.md에 env var 명시"
else
  fail "(AC4) SKILL.md에 env var 미명시"
fi

# ---------- LOOP_REVIEW_IDLE_THRESHOLD 문서·구현 일치 (drift 방지) ----------
# 환경변수가 SKILL.md에 문서화돼 있다면 script에서도 실제 읽혀야 한다. drift 방어용 정적 검사.
if grep -q 'LOOP_REVIEW_IDLE_THRESHOLD' "$SCRIPT"; then
  pass "LOOP_REVIEW_IDLE_THRESHOLD script에서 읽힘 (문서·구현 일치)"
else
  fail "LOOP_REVIEW_IDLE_THRESHOLD script에서 미사용 (문서·구현 불일치)"
fi

# ---------- 요약 ----------
TOTAL=$((PASSED + FAILED))
echo ""
echo "총 $TOTAL 검사 — PASS: $PASSED, FAIL: $FAILED"
if (( FAILED > 0 )); then
  exit 1
fi
exit 0
