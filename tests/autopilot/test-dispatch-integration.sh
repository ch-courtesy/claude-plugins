#!/usr/bin/env bash
# autopilot:dispatch 통합 시나리오 테스트
# dispatch.sh의 sentinel watch + ops 흐름을 fixture 기반으로 검증.
# 모델 측 대화 흐름(분해·게이트·spec 위임)은 본 테스트 범위 밖.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
DISPATCH_SH="$REPO_ROOT/plugins/autopilot/skills/dispatch/references/dispatch.sh"
[[ -x "$DISPATCH_SH" ]] || { echo "FAIL: dispatch.sh 실행 권한 없음"; exit 1; }

WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf $WORK_DIR" EXIT

# 가짜 프로젝트 git init
PROJECT="$WORK_DIR/myproject"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init -q
git config user.email "test@example.com"
git config user.name "Test"
git commit --allow-empty -m "initial" -q

# 새 nested 정책: worktree와 lock 모두 milestones/<m>/loops/<c>/ 안에.
# LOOP_WORKTREE_BASE는 더 이상 사용되지 않음 (계산 시 PROJECT_ROOT/milestones/.../worktree 사용)

dispatch() {
  bash "$DISPATCH_SH" "$@"
}

# nested worktree·lock 경로 헬퍼
nested_wt() {
  local m="$1"; local c="$2"
  echo "$PROJECT/milestones/$m/loops/$c/.worktree"
}

nested_lock() {
  local m="$1"; local c="$2"
  echo "$PROJECT/milestones/$m/loops/$c/.lock"
}

# fixture helpers
seed_prd() {
  local m="$1"; local content="${2:-}"
  mkdir -p "$PROJECT/milestones/$m/prd"
  if [[ -n "$content" ]]; then
    printf '%s' "$content" > "$PROJECT/milestones/$m/prd/PRD.md"
  else
    cat > "$PROJECT/milestones/$m/prd/PRD.md" <<'EOF'
# Sample PRD
모든 마커 해결됨.
EOF
  fi
}

seed_dag() {
  local m="$1"; shift
  mkdir -p "$PROJECT/milestones/$m/dispatch"
  local dag="$PROJECT/milestones/$m/dispatch/DAG.md"
  cat > "$dag" <<EOF
# DAG — $m

## 단위 목록
EOF
  local c
  for c in "$@"; do
    echo "- $c: 테스트 단위" >> "$dag"
  done
}

seed_worktree() {
  # 가짜 워크트리 + 메모리 파일 시드 (nested 경로)
  local m="$1"; local c="$2"
  local wt="$(nested_wt "$m" "$c")"
  mkdir -p "$wt/.loop"
  echo "# stub" > "$wt/CLAUDE.md"
}

mark_done() {
  local m="$1"; local c="$2"
  local wt="$(nested_wt "$m" "$c")"
  mkdir -p "$wt"
  touch "$wt/DONE"
}

mark_escalated() {
  local m="$1"; local c="$2"
  local wt="$(nested_wt "$m" "$c")"
  mkdir -p "$wt/.loop"
  cat > "$wt/.loop/ESCALATION.md" <<'EOF'
## 에스컬레이션 보고
**카테고리**: spec-gap
EOF
}

# ==============================================================================

echo "=== TEST 1: list 명령 — milestone 없음 ==="
output=$(dispatch list 2>&1)
echo "$output" | grep -qE 'milestones/ 디렉터리 없음|MILESTONE' \
  || { echo "FAIL: list 출력 형식 이상. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 2: list 명령 — 한 milestone 보임 ==="
seed_prd auth-overhaul
seed_dag auth-overhaul child-a child-b
output=$(dispatch list 2>&1)
echo "$output" | grep -q 'auth-overhaul' \
  || { echo "FAIL: list가 auth-overhaul을 보여주지 않음. got: $output"; exit 1; }
echo "$output" | grep -q 'MILESTONE' \
  || { echo "FAIL: list 출력에 헤더 없음. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 3: status 명령 — PRD/DAG 존재, child 상태 ==="
seed_worktree auth-overhaul child-a
seed_worktree auth-overhaul child-b
output=$(dispatch status auth-overhaul 2>&1)
echo "$output" | grep -q 'PRD' || { echo "FAIL: status에 PRD 라인 없음. got: $output"; exit 1; }
echo "$output" | grep -q 'DAG' || { echo "FAIL: status에 DAG 라인 없음. got: $output"; exit 1; }
echo "$output" | grep -q 'child-a' || { echo "FAIL: status에 child-a 없음. got: $output"; exit 1; }
echo "$output" | grep -q 'child-b' || { echo "FAIL: status에 child-b 없음. got: $output"; exit 1; }
echo "$output" | grep -qE 'idle|done|escalated|running' \
  || { echo "FAIL: status에 state 값 없음. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 4: status 명령 — regular milestone catch-all ==="
mkdir -p "$(nested_wt regular ad-hoc-task)"
output=$(dispatch status regular 2>&1)
echo "$output" | grep -q 'regular' || { echo "FAIL: status regular 출력 없음. got: $output"; exit 1; }
echo "$output" | grep -qE 'catch-all|PRD/DAG 없음' \
  || { echo "FAIL: regular catch-all 안내 없음. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 5: status — PRD 마커 잔존 감지 ==="
seed_prd marker-test '# Marker test
[NEEDS CLARIFICATION: 어떤 인증 방식?]
'
output=$(dispatch status marker-test 2>&1)
echo "$output" | grep -qiE 'markers.*[1-9]|resume' \
  || { echo "FAIL: 마커 잔존 안내 없음. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 6: validate_milestone 거부 — '..' 포함 ==="
set +e
output=$(dispatch status '../escape' 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: '..' 포함 milestone-id가 거부되지 않음"; exit 1; }
echo "$output" | grep -q "'\\.\\.'" || { echo "FAIL: '..' 거부 메시지 없음. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 7: log_event + logs 라운드트립 ==="
dispatch log_event auth-overhaul "wave 1 start — children=[child-a, child-b]"
output=$(dispatch logs auth-overhaul 2>&1)
echo "$output" | grep -q 'wave 1 start' \
  || { echo "FAIL: log_event 기록이 logs에 안 나타남. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 8: watch_wave happy path — 모두 DONE ==="
# 두 child가 모두 DONE이면 exit 100
seed_dag happy-path child-1 child-2
seed_worktree happy-path child-1
seed_worktree happy-path child-2
mark_done happy-path child-1
mark_done happy-path child-2
set +e
WATCH_POLL_SECONDS=1 WATCH_TIMEOUT_SECONDS=10 \
  dispatch watch_wave happy-path child-1 child-2 > /dev/null 2>&1
result=$?
set -e
[[ $result -eq 100 ]] || { echo "FAIL: 모두 DONE인데 exit 100이 아님 (got: $result)"; exit 1; }
# 로그 확인
output=$(dispatch logs happy-path 2>&1)
echo "$output" | grep -q 'ALL DONE' \
  || { echo "FAIL: DISPATCH_LOG.md에 ALL DONE 기록 없음. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 9: watch_wave fail-fast — ESCALATION 감지 ==="
# 한 명이 ESCALATION이면 exit 101
seed_dag fail-fast child-x child-y
seed_worktree fail-fast child-x
seed_worktree fail-fast child-y
mark_escalated fail-fast child-x
set +e
WATCH_POLL_SECONDS=1 WATCH_TIMEOUT_SECONDS=10 \
  dispatch watch_wave fail-fast child-x child-y > /dev/null 2>&1
result=$?
set -e
[[ $result -eq 101 ]] || { echo "FAIL: ESCALATION 감지인데 exit 101이 아님 (got: $result)"; exit 1; }
output=$(dispatch logs fail-fast 2>&1)
echo "$output" | grep -q 'ESCALATION' \
  || { echo "FAIL: DISPATCH_LOG.md에 ESCALATION 기록 없음. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 10: watch_wave timeout ==="
# 어느 child도 sentinel을 만들지 않으면 timeout (exit 102)
seed_dag timeout-test child-z
seed_worktree timeout-test child-z
# DONE / ESCALATION 둘 다 없음
set +e
WATCH_POLL_SECONDS=1 WATCH_TIMEOUT_SECONDS=2 \
  dispatch watch_wave timeout-test child-z > /dev/null 2>&1
result=$?
set -e
[[ $result -eq 102 ]] || { echo "FAIL: timeout exit 102이 아님 (got: $result)"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 11: cleanup — DONE 신호 있는 child만 정리 ==="
seed_dag cleanup-test child-clean child-leave
seed_worktree cleanup-test child-clean
seed_worktree cleanup-test child-leave
mark_done cleanup-test child-clean
# child-leave는 DONE 없음

dispatch cleanup cleanup-test > /dev/null 2>&1 || true
[[ ! -d "$(nested_wt cleanup-test child-clean)" ]] \
  || { echo "FAIL: DONE 있는 child-clean이 정리 안 됨"; exit 1; }
[[ -d "$(nested_wt cleanup-test child-leave)" ]] \
  || { echo "FAIL: DONE 없는 child-leave가 정리됨 (정리되면 안 됨)"; exit 1; }
# PRD/DAG는 보존
[[ -f "$PROJECT/milestones/cleanup-test/dispatch/DAG.md" ]] \
  || { echo "FAIL: cleanup이 DAG.md를 삭제함 (보존해야 함)"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 12: stop — 활성 child 없으면 안내 ==="
seed_dag idle-test child-q
seed_worktree idle-test child-q
output=$(dispatch stop idle-test 2>&1)
echo "$output" | grep -qE '없음|모두 이미' \
  || { echo "FAIL: 활성 child 없음 안내가 없음. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 13: logs — 파일 없으면 명확한 에러 ==="
set +e
output=$(dispatch logs nonexistent-milestone 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 없는 milestone logs가 0 exit"; exit 1; }
echo "$output" | grep -q 'DISPATCH_LOG.md 없음' \
  || { echo "FAIL: 명확한 에러 메시지 없음. got: $output"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 dispatch 통합 테스트 통과 ==="
