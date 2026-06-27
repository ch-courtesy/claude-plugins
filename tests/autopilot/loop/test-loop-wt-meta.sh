#!/usr/bin/env bash
# test-loop-wt-meta.sh
#
# resolve_actual_wt() 가 <SPEC_DIR>/.loop-wt 메타를 정확히 읽는지 회귀 가드.
# 7 edge case:
#   E1 정상 (trailing newline)
#   E2 trailing newline 없음 (read 가 non-zero 반환하지만 변수에 값 채워짐)
#   E3 빈 파일 → return 1
#   E4 다중 라인 (첫 줄만 읽고 나머지 무시)
#   E5 경로 내부 공백 (IFS= 로 보존)
#   E6 경로 내부 탭 (IFS= 로 보존)
#   E7 파일 부재 → return 1

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_SH="$SCRIPT_DIR/../../../plugins/autopilot/skills/loop/references/loop.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git 미설치"; exit 0; }

# loop.sh source — dispatcher 는 BASH_SOURCE guard 로 비실행.
# shellcheck source=../../../plugins/autopilot/skills/loop/references/loop.sh
source "$LOOP_SH"
set +e   # loop.sh 의 errexit 해제 — 함수 return 1 캡처 위해 필수

fail=0
SPEC_DIR_TEST="$(mktemp -d)"
trap 'rm -rf "$SPEC_DIR_TEST"' EXIT

run_case() {
  local label="$1" expected_rc="$2" expected_wt="$3"
  # 다음 globals 는 source 된 resolve_actual_wt 가 읽고 쓴다(shellcheck 미감지).
  # shellcheck disable=SC2034
  SPEC_DIR="$SPEC_DIR_TEST"
  WT=""
  # shellcheck disable=SC2034
  LOOP_DIR=""
  resolve_actual_wt
  local rc=$?
  if [[ "$rc" == "$expected_rc" && "$WT" == "$expected_wt" ]]; then
    echo "PASS  $label"
  else
    echo "FAIL  $label  got rc=$rc wt='$WT' (expected rc=$expected_rc wt='$expected_wt')"
    fail=1
  fi
}

# E1 정상
printf '/path/to/wt\n' > "$SPEC_DIR_TEST/.loop-wt"
run_case "E1 정상 (trailing newline)" 0 "/path/to/wt"

# E2 trailing newline 없음 — codex finding 회귀 가드 (PR #230 R4)
printf '/path/no/newline' > "$SPEC_DIR_TEST/.loop-wt"
run_case "E2 trailing newline 없음" 0 "/path/no/newline"

# E3 빈 파일
: > "$SPEC_DIR_TEST/.loop-wt"
run_case "E3 빈 파일" 1 ""

# E4 다중 라인 — 첫 줄만
printf 'first/line\nshould/ignore\n' > "$SPEC_DIR_TEST/.loop-wt"
run_case "E4 다중 라인 (첫 줄만)" 0 "first/line"

# E5 경로 내부 공백 — codex finding 회귀 가드 (PR #230 R3)
printf '/My Tasks/spec/.worktree\n' > "$SPEC_DIR_TEST/.loop-wt"
run_case "E5 경로 내부 공백" 0 "/My Tasks/spec/.worktree"

# E6 경로 내부 탭
printf '/p/with\ttab/wt\n' > "$SPEC_DIR_TEST/.loop-wt"
run_case "E6 경로 내부 탭" 0 "$(printf '/p/with\ttab/wt')"

# E7 파일 부재
rm "$SPEC_DIR_TEST/.loop-wt"
run_case "E7 파일 부재" 1 ""

if [[ $fail -ne 0 ]]; then
  echo "FAIL: 일부 case 실패 — resolve_actual_wt"
  exit 1
fi
echo "PASS: resolve_actual_wt 모든 edge case (7건)"
