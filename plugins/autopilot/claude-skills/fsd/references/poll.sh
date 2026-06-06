#!/usr/bin/env bash
# poll.sh — autopilot:fsd 멱등 상태 드레인 (dispatch 공개 인터페이스 관측 전용)
#
# 책임:
#   - 진행 중인 모든 task 의 dispatch run 상태를 dispatch 의 **공개 인터페이스**
#     (`dispatch status <run-id>`)로 관측해, 그 run 의 모든 SPEC 이 머지 종착(done)에
#     도달했으면 task 를 `done` 으로 전이한다. 아직 진행 중이면 상태를 바꾸지 않는다.
#
# fsd 는 리뷰·머지를 직접 하지 않는다 — `dispatch start`(통합 모드 기본 ON)가
#   implement→통합(PR)→(direct 서브모드)머지를 **소유**하며, poll 은 그 결과를
#   관측만 한다. 사람 개입·외부 승인 보류 지점이 없다(완전자율). poll 자체는 PR 생성·
#   리뷰·승인 조회·머지를 호출하지 않으며 forge·task backend 를 건드리지 않는다.
#
# 멱등성(같은 상태에서 두 번 실행해도 같은 결과, 부작용 없음):
#   - 상태는 fsd 상태 저장소(C0)에 두고, 드레인 호출은 **호출 단위 무상태**여서
#     크래시 후 재시작이 안전하다. 로컬 종착(done/stopped/dispatch-failed) task 는
#     재드레인해도 no-op 이고, run 에 비종착(pending/running/integrating) SPEC 이 남으면
#     상태를 바꾸지 않아 같은 상태 재드레인이 멱등이다. run 의 모든 SPEC 이 종착하면
#     전부 done 일 때 task done, 일부 failed/skipped 면 task dispatch-failed 로 전이해
#     실패를 드러낸다(이후 재드레인은 로컬 종착 no-op).
#
# 무거운 동작(implement·통합·머지)은 모두 dispatch 가 자기 run 안에서 수행하므로,
#   poll 은 가벼운 관측 한 스텝만 한다. dispatch 호출은 주입 가능한 명령으로 두어
#   mock 검증된다.
#
# 환경 변수 (테스트에서 mock 으로 치환 가능):
#   POLL_DISPATCH_CMD  dispatch.sh 호출 (status). 기본: 형제 dispatch.sh.
#   FSD_STATE_ROOT     상태 루트 (기본 <project_root>/.fsd). lib-state.sh 참조.
#
# 상시 호스트 무인 운영(토큰 스코프·실행기 권한 격리·폴링 주기)은
# operational-guide.md 가 문서화한다.
#
# self-referential: 검증은 mock 인터페이스로만 하며 runtime artifact(실제 run·PR)를
# 직접 검사하지 않는다(`bash poll.sh selftest`). bash 3.2+ 호환.

set -uo pipefail

PL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 상태 저장소(C0) 헬퍼만 sourcing — 가볍고 exit 하지 않는다.
# shellcheck source=lib-state.sh
. "$PL_SCRIPT_DIR/lib-state.sh"
# 우리 자신의 옵션을 복원: -e 없이(부분 실패 격리) -u·pipefail 만.
set +e
set -uo pipefail

# ----- 주입 가능한 dispatch 명령(기본: 형제 dispatch.sh) -----
# fsd 는 dispatch 의 공개 인터페이스만 소비한다(내부 run 디렉토리·신호 파일·워크트리는
# 직접 들여다보지 않는다).
POLL_DISPATCH_CMD="${POLL_DISPATCH_CMD:-bash $PL_SCRIPT_DIR/../../dispatch/references/dispatch.sh}"

# pl_log <task-id> <message...> — 상태 저장소 로그 + 운영자용 stdout 한 줄.
pl_log() {
  local id="$1"; shift
  log_event "$id" "poll: $*" 2>/dev/null || true
  echo "[poll] $id: $*"
}

# dispatch_states <run-id> — dispatch status 출력에서 per-SPEC state 들을 한 줄에 하나씩.
#   `wave=<n>  <state>  <loop>  <spec>` 행의 2번째 필드(state)를 뽑는다.
#   공개 인터페이스 출력 파싱이며 내부 파일을 읽지 않는다.
dispatch_states() {
  # shellcheck disable=SC2086
  $POLL_DISPATCH_CMD status "$1" 2>/dev/null \
    | awk '/^wave=/ { print $2 }'
}

# =====================================================================
# poll_task <task-id> — 한 task 의 dispatch run 을 관측해 한 스텝 전진(멱등).
#   완전자율: 사람 개입·외부 승인 보류 분기가 없다.
# =====================================================================
poll_task() {
  local id="$1"
  task_exists "$id" || { echo "[poll] $id: task 디렉토리 없음 — 건너뜀"; return 0; }
  ensure_task_dir "$id"

  local run_id cstate
  run_id="$(get_run_id "$id")"
  cstate="$(get_state "$id")"

  # --- 1) 로컬 종착 → 전진 없음(멱등 no-op). ---
  case "$cstate" in
    done|stopped|dispatch-failed)
      pl_log "$id" "로컬 종착(state=$cstate) — 전진 없음"; return 0 ;;
  esac

  # --- 2) dispatch run 없음 → 관측 대상 없음(멱등 no-op). ---
  # 구현 기동은 fsd start 가 dispatch 에 위임한다(poll 은 관측만).
  if [[ -z "$run_id" ]]; then
    pl_log "$id" "dispatch run 없음 — 전진 없음(fsd start 로 기동)"
    return 0
  fi

  # --- 3) dispatch 공개 인터페이스로 per-SPEC state 관측. ---
  # dispatch 의 per-SPEC 종착 상태는 done|failed|skipped 이며, 그 외(pending|running|
  # integrating 등)는 비종착이다. 종착 분포로 task 상태를 전이한다:
  #   · 비종착이 하나라도 남음 → 진행 중(상태 불변, 멱등 재드레인).
  #   · 전부 종착 + 전부 done → task done.
  #   · 전부 종착 + 일부 failed/skipped → task dispatch-failed(운영자가 실패 감지·재시작).
  local states n_total n_done n_term
  states="$(dispatch_states "$run_id")"
  if [[ -z "$states" ]]; then
    pl_log "$id" "dispatch run 상태 미관측(run=$run_id) — 전진 없음"
    return 0
  fi
  n_total="$(printf '%s\n' "$states" | grep -c .)"
  n_done="$(printf '%s\n' "$states" | grep -c '^done$')"
  n_term="$(printf '%s\n' "$states" | grep -cE '^(done|failed|skipped)$')"

  if [[ "$n_term" != "$n_total" ]]; then
    pl_log "$id" "dispatch run 진행 중($n_done/$n_total done, 종착 $n_term/$n_total) — 전진 없음(상태 불변)"
  elif [[ "$n_done" == "$n_total" ]]; then
    set_state "$id" "done"
    pl_log "$id" "dispatch run 전체 머지 종착($n_done/$n_total) → task done"
  else
    set_state "$id" "dispatch-failed"
    pl_log "$id" "dispatch run 종착하나 일부 실패($n_done/$n_total done) → task dispatch-failed"
  fi
  return 0
}

# =====================================================================
# poll_drain — 모든 task 를 한 바퀴 드레인(호출 단위 무상태·멱등).
# =====================================================================
poll_drain() {
  local ids id n=0
  ids="$(list_tasks)"
  if [[ -z "$ids" ]]; then
    echo "poll: 대상 task 없음 (멱등 no-op)."
    return 0
  fi
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    n=$((n+1))
    poll_task "$id"
  done <<< "$ids"
  echo "poll: 드레인 완료 — $n task 관측·전진(호출 단위 무상태·멱등)."
}

# =====================================================================
# selftest — mock dispatch 로 관측·전이·멱등을 독립 검증(self-referential).
#   runtime artifact(실제 run·PR)는 검사하지 않는다. 외부 승인 보류 케이스는 없다.
# =====================================================================
pl_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  export FSD_STATE_ROOT="$TMP/.fsd"
  export PROJECT_ROOT="$TMP"
  local TRACE="$TMP/trace"; : > "$TRACE"; export TRACE

  # --- mock dispatch: status 출력 시뮬. MOCK_STATES(공백 구분 state 목록)을 wave 행으로. ---
  cat > "$TMP/m-dispatch.sh" <<'EOF'
#!/usr/bin/env bash
echo "dispatch $*" >> "$TRACE"
if [[ "$1" == "status" ]]; then
  i=0
  for s in ${MOCK_STATES:-}; do
    i=$((i+1))
    echo "wave=$i  $s  idle  /tmp/SPEC-$i.md"
  done
fi
exit 0
EOF
  export POLL_DISPATCH_CMD="bash $TMP/m-dispatch.sh"

  local spec="$TMP/SPEC.md"; printf '# T\n## 완료 조건\n1. X.\n' > "$spec"

  local fail=0
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }
  tcount() { grep -c "$1" "$TRACE" 2>/dev/null | tr -d '[:space:]'; }

  # ---- dispatch run 미완(running 섞임) → 상태 불변 ----
  ensure_task_dir d1; set_run_id d1 "run-d1"; set_state d1 "dispatched"; add_spec d1 "$spec"
  MOCK_STATES="done running" poll_task d1 >/dev/null
  chk "dispatch run 미완 → 전진 없음·상태 불변" "$(get_state d1)" "dispatched"

  # ---- dispatch run 전체 머지 종착 → task done 전이 ----
  MOCK_STATES="done done" poll_task d1 >/dev/null
  chk "dispatch run 전체 머지 종착 → task done" "$(get_state d1)" "done"

  # ---- 멱등: 로컬 종착(done) 재드레인 → 상태 불변, dispatch status 미조회 ----
  : > "$TRACE"
  MOCK_STATES="done done" poll_task d1 >/dev/null
  chk "멱등: 로컬 종착 재드레인 상태 불변" "$(get_state d1)" "done"
  chk "멱등: 종착 task 는 dispatch status 미조회" "$(tcount 'dispatch status')" "0"

  # ---- dispatch run 없음 → 전진 없음(done 아님) ----
  ensure_task_dir n1; set_state n1 "intake"; add_spec n1 "$spec"
  poll_task n1 >/dev/null
  chk "dispatch run 없음 → 전진 없음" "$(get_state n1)" "intake"

  # ---- 전부 종착 + 일부 failed → task dispatch-failed (실패 감지) ----
  ensure_task_dir f1; set_run_id f1 "run-f1"; set_state f1 "dispatched"; add_spec f1 "$spec"
  MOCK_STATES="done failed" poll_task f1 >/dev/null
  chk "전부 종착·일부 failed → dispatch-failed" "$(get_state f1)" "dispatch-failed"
  # 멱등: dispatch-failed 는 로컬 종착 → 재드레인 no-op, dispatch status 미조회
  : > "$TRACE"
  MOCK_STATES="done failed" poll_task f1 >/dev/null
  chk "멱등: dispatch-failed 재드레인 상태 불변" "$(get_state f1)" "dispatch-failed"
  chk "멱등: dispatch-failed 는 dispatch status 미조회" "$(tcount 'dispatch status')" "0"

  # ---- 전부 종착 + 일부 skipped → task dispatch-failed ----
  ensure_task_dir k1; set_run_id k1 "run-k1"; set_state k1 "dispatched"; add_spec k1 "$spec"
  MOCK_STATES="done skipped" poll_task k1 >/dev/null
  chk "전부 종착·일부 skipped → dispatch-failed" "$(get_state k1)" "dispatch-failed"

  # ---- 비종착(integrating) 남으면 실패로 단정 않고 상태 유지 ----
  ensure_task_dir p1; set_run_id p1 "run-p1"; set_state p1 "dispatched"; add_spec p1 "$spec"
  MOCK_STATES="failed integrating" poll_task p1 >/dev/null
  chk "비종착(integrating) 남음 → 전진 없음·상태 불변" "$(get_state p1)" "dispatched"

  # ---- poll_drain 이 모든 task 를 한 바퀴 훑는다 ----
  : > "$TRACE"
  out="$(poll_drain)"
  case "$out" in *"드레인 완료"*) ok "드레인 전체 순회 + 완료 보고";; *) bad "드레인 전체 순회 + 완료 보고";; esac

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ----- 사용법 -----
usage() {
  cat >&2 <<'EOF'
usage: poll.sh <command> [args]

Commands:
  poll              모든 진행 중 task 의 dispatch run 을 관측·전진(멱등 드레인).
  task <task-id>    한 task 만 관측·전진.
  selftest          mock dispatch 로 관측·전이·멱등 검증.

환경 변수: POLL_DISPATCH_CMD, FSD_STATE_ROOT
EOF
  exit 1
}

require_git_root() {
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "poll: git 저장소 안에서 실행해야 합니다." >&2; exit 1; }
  export PROJECT_ROOT
}

# ----- 디스패처 (sourcing 시에는 실행되지 않음) -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SUB="${1:-}"; shift || true
  case "$SUB" in
    poll)     require_git_root; poll_drain ;;
    task)     [[ $# -ge 1 ]] || usage; require_git_root; poll_task "$1" ;;
    selftest) pl_selftest ;;
    -h|--help|help) usage ;;
    *) echo "알 수 없는 command: $SUB" >&2; usage ;;
  esac
fi
