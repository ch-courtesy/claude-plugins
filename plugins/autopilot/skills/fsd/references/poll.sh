#!/usr/bin/env bash
# poll.sh — autopilot:fsd 멱등 드레인 + 상시 호스트 운영 진입점 (C5)
#
# 책임 (파이프라인을 하나의 반복 가능한 단위로 닫는다):
#   - 멱등 드레인(poll): 진행 중인 모든 task 를 한 바퀴 훑어, 백엔드(task backend·승인
#     요청)의 실제 진실과 로컬 미러를 **정합(reconcile)**시키고, 각 task 를 그 시점에
#     가능한 **다음 한 스텝**으로 전진시킨다:
#       · 미시작 백로그 task           → 구현 시작(start → dispatch 위임)
#       · 구현 완료(loop DONE) task     → 통합(C2 forge: base sync→push→PR, Review 전이)
#       · 미승인 열린 승인요청          → 외부 승인 대기(no-op·상태 불변; 외부 CI/사람이 승인)
#       · 승인된 승인요청               → 머지(C4: ff-only, Done 전이)
#   - 백엔드 우선 정합: 로컬 미러와 백엔드가 불일치하면 백엔드를 진실의 원천으로
#     채택해 미러를 갱신한다(tb_reconcile, C1 공개 계약).
#
# 멱등성(같은 상태에서 두 번 실행해도 같은 결과, 부작용 없음):
#   - 상태는 fsd 상태 저장소(C0)에 두고, 드레인 호출은 **호출 단위 무상태**여서
#     크래시 후 재시작이 안전하다. 각 전이 전 현재 상태를 재확인해 이미 처리한 전이를
#     중복 수행하거나 중복 승인 요청(PR)을 만들지 않는다:
#       · start   는 run-id 가 비었을 때만 (1회 dispatch 후 run-id 가 차서 재시작 안 함).
#       · integrate 는 PR 미생성 상태에서만 (PR 이 차면 다음 드레인은 머지/승인대기 경로로).
#         또한 C2 ensure_pr 이 같은 head 의 open PR 을 재사용해 중복 PR 을 만들지 않는다.
#       · 미승인 PR 은 외부 승인 대기 no-op 이라 상태를 바꾸지 않아 재드레인이 안전하다.
#       · merge   는 Done 전이 후 종착 no-op (재머지 안 함).
#
# 이 단위는 C1~C4 의 공개 동작을 **조합**할 뿐, 각 스텝의 동작을 정의하지 않는다.
# 무거운 액션(start·integrate·merge)은 주입 가능한 명령으로 **서브프로세스**
# 격리 호출하여(각 모듈의 die→exit 가 드레인 전체를 죽이지 않게), 한 task 의 실패가
# 다른 task 의 전진을 막지 않도록 한다. 상태 IO·정합 헬퍼만 sourcing 한다.
#
# 환경 변수 (테스트에서 mock 으로 치환 가능):
#   POLL_FSD_CMD  fsd.sh 호출 (start). 기본: 형제 fsd.sh.
#   POLL_FORGE_CMD      forge.sh 호출 (terminal/integrate). 기본: 형제 forge.sh.
#   POLL_MERGE_CMD      merge.sh 호출 (approval/finish). 기본: 형제 merge.sh.
#   TASK_BACKEND_CMD    task backend 호출 (tb_reconcile 가 소비; C1, mock 가능).
#   FSD_STATE_ROOT 상태 루트 (기본 <project_root>/.fsd). lib-state.sh 참조.
#
# 상시 호스트 무인 운영(토큰 스코프·approver 신원 분리·실행기 권한 격리·폴링 주기)은
# operational-guide.md 가 문서화한다.
#
# self-referential: 검증은 mock 인터페이스로만 하며 runtime artifact(실제 보드·승인
# 요청)를 직접 검사하지 않는다(`bash poll.sh selftest`). bash 3.2+ 호환.

set -uo pipefail

PL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 상태 저장소(C0) + task backend 정합 헬퍼(C1) 만 sourcing — 가볍고 exit 하지 않는다.
# shellcheck source=lib-state.sh
. "$PL_SCRIPT_DIR/lib-state.sh"
# task-backend.sh 는 top-level 에서 `set -uo pipefail` 을 재설정한다(우리와 동일).
# shellcheck source=task-backend.sh
. "$PL_SCRIPT_DIR/task-backend.sh"
# 우리 자신의 옵션을 복원: -e 없이(부분 실패 격리) -u·pipefail 만.
set +e
set -uo pipefail

# ----- 주입 가능한 액션 명령(기본: 형제 모듈, 서브프로세스 격리) -----
POLL_FSD_CMD="${POLL_FSD_CMD:-bash $PL_SCRIPT_DIR/fsd.sh}"
POLL_FORGE_CMD="${POLL_FORGE_CMD:-bash $PL_SCRIPT_DIR/forge.sh}"
POLL_MERGE_CMD="${POLL_MERGE_CMD:-bash $PL_SCRIPT_DIR/merge.sh}"

pl_die() { echo "poll: $*" >&2; return 1; }

# pl_log <task-id> <message...> — 상태 저장소 로그 + 운영자용 stdout 한 줄.
pl_log() {
  local id="$1"; shift
  log_event "$id" "poll: $*" 2>/dev/null || true
  echo "[poll] $id: $*"
}

# =====================================================================
# poll_task <task-id> — 한 task 를 그 시점 가능한 다음 한 스텝으로 전진(멱등).
# =====================================================================
poll_task() {
  local id="$1"
  task_exists "$id" || { echo "[poll] $id: task 디렉토리 없음 — 건너뜀"; return 0; }
  ensure_task_dir "$id"
  # 주입된 액션 명령이 task 컨텍스트를 알 수 있도록 노출(실제 모듈은 무시).
  export POLL_CUR_TASK="$id"

  local spec pr run_id cstate bstat
  spec="$(get_specs "$id" | head -1)"
  pr="$(get_pr "$id")"
  run_id="$(get_run_id "$id")"
  cstate="$(get_state "$id")"

  # --- AC4: 백엔드 우선 정합 — 미러를 백엔드 진실로 갱신하고 현재 상태 채택. ---
  bstat="$(tb_reconcile "$id" 2>/dev/null)"

  # --- 1) 종착 상태 → 전진 없음(멱등 no-op). ---
  case "$bstat" in
    Done|Cancelled|Blocked) pl_log "$id" "종착(backend=$bstat) — 전진 없음"; return 0 ;;
  esac
  case "$cstate" in
    done|stopped|merged|dispatch-failed)
      pl_log "$id" "로컬 종착(state=$cstate) — 전진 없음"; return 0 ;;
  esac

  # --- 2) 열린 승인 요청(PR) 보유 → 승인되면 머지(C4), 아니면 외부 승인 대기 no-op. ---
  # 내부 자동 리뷰·재구현 고리는 제거됨. 미승인 PR 의 승인은 외부 CI 봇·사람에게 위임한다.
  # 미승인 분기는 어떤 전이도 하지 않아(상태 불변) 같은 상태 재드레인이 멱등이다.
  if [[ -n "$pr" ]]; then
    if $POLL_MERGE_CMD approval "$pr" >/dev/null 2>&1; then
      pl_log "$id" "승인됨 → merge(C4) pr=$pr"
      $POLL_MERGE_CMD finish "$spec" "$id" "$pr" \
        || pl_log "$id" "merge 보류/게이트 차단 pr=$pr"
    else
      pl_log "$id" "PR 열림·미승인 → 외부 승인 대기(전진 없음·상태 불변) pr=$pr"
    fi
    return 0
  fi

  # --- 3) PR 미생성 + dispatch run 보유 → 종료신호 정합 후 통합(C2). ---
  if [[ -n "$run_id" ]]; then
    local term
    term="$($POLL_FORGE_CMD terminal "$spec" 2>/dev/null)"
    case "$term" in
      done|failed)
        pl_log "$id" "loop 종료($term) → forge integrate(C2)"
        $POLL_FORGE_CMD integrate "$spec" "$id" \
          || pl_log "$id" "integrate 보류 spec=$spec"
        ;;
      *)
        pl_log "$id" "구현 진행 중($term) — 전진 없음"
        ;;
    esac
    return 0
  fi

  # --- 4) 미시작(run 없음) + 백로그류 → 구현 시작(dispatch 위임). ---
  case "$bstat" in
    ""|Backlog|"In Design"|intake|unknown)
      if [[ -n "$spec" ]]; then
        pl_log "$id" "미시작(backend=${bstat:-none}) → 구현 시작 start"
        $POLL_FSD_CMD start "$spec" \
          || pl_log "$id" "start 위임 실패 spec=$spec"
      else
        pl_log "$id" "미시작이나 SPEC 경로 없음 — 전진 없음"
      fi
      ;;
    *)
      pl_log "$id" "전진 가능한 스텝 없음(backend=$bstat run=$run_id)"
      ;;
  esac
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
  echo "poll: 드레인 완료 — $n task 정합·전진(호출 단위 무상태·멱등)."
}

# =====================================================================
# selftest — mock 인터페이스로 AC2~4 동작·멱등을 독립 검증(self-referential).
#   runtime artifact(실제 보드·승인 요청)는 검사하지 않는다.
# =====================================================================
pl_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  export FSD_STATE_ROOT="$TMP/.fsd"
  export PROJECT_ROOT="$TMP"
  export PL_REF="$PL_SCRIPT_DIR"
  local TRACE="$TMP/trace"; : > "$TRACE"; export TRACE
  local BK="$TMP/backend"; mkdir -p "$BK"; export BK

  # --- mock task backend (tb_reconcile 소비; 이슈별 .status 파일) ---
  mock_backend() {
    case "$1" in
      get-status) cat "$BK/$2.status" 2>/dev/null || true ;;
      *) : ;;
    esac
  }
  export -f mock_backend
  export TASK_BACKEND_CMD=mock_backend

  # --- mock 액션 명령(서브프로세스) — 호출 기록 + 현실적 상태 시뮬 ---
  cat > "$TMP/m-fsd.sh" <<'EOF'
#!/usr/bin/env bash
. "$PL_REF/lib-state.sh"
echo "fsd $*" >> "$TRACE"
[[ "$1" == "start" ]] && set_field "$POLL_CUR_TASK" run-id "run-$POLL_CUR_TASK"
exit 0
EOF
  cat > "$TMP/m-forge.sh" <<'EOF'
#!/usr/bin/env bash
. "$PL_REF/lib-state.sh"
echo "forge $*" >> "$TRACE"
case "$1" in
  terminal)  echo "${MOCK_TERM:-pending}" ;;
  integrate) # integrate <spec> <id> — Review 전이 + PR 생성 시뮬(1회만).
             set_field "$3" pr "PR-$3"
             set_field "$3" backend-status "Review"
             set_field "$3" state "Review" ;;
esac
exit 0
EOF
  cat > "$TMP/m-merge.sh" <<'EOF'
#!/usr/bin/env bash
. "$PL_REF/lib-state.sh"
echo "merge $*" >> "$TRACE"
case "$1" in
  approval) [[ "${MOCK_APPROVED:-0}" == "1" ]] && exit 0 || exit 1 ;;
  finish)   set_field "$3" backend-status "Done"; set_field "$3" state "Done" ;; # finish <spec> <id> <pr>
esac
exit 0
EOF
  export POLL_FSD_CMD="bash $TMP/m-fsd.sh"
  export POLL_FORGE_CMD="bash $TMP/m-forge.sh"
  export POLL_MERGE_CMD="bash $TMP/m-merge.sh"

  local spec="$TMP/SPEC.md"; printf '# T\n## 수용 기준\n1. X.\n' > "$spec"

  local fail=0
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }
  tcount() { grep -c "$1" "$TRACE" 2>/dev/null | tr -d '[:space:]'; }

  # ---- AC4: 백엔드 우선 정합 — 미러≠백엔드면 백엔드 채택 ----
  ensure_task_dir r1; set_field r1 issue 1; printf 'Review' > "$BK/1.status"
  set_field r1 backend-status "In Progress"; set_run_id r1 "run-r1"; add_spec r1 "$spec"
  MOCK_TERM=running poll_task r1 >/dev/null
  chk "AC4 백엔드 우선(미러 갱신)" "$(get_field r1 backend-status)" "Review"

  # ---- AC2-a: 미시작(run 없음, Backlog) → 구현 시작 start ----
  : > "$TRACE"
  ensure_task_dir s1; set_field s1 issue 10; printf 'Backlog' > "$BK/10.status"
  set_field s1 backend-status "Backlog"; add_spec s1 "$spec"
  poll_task s1 >/dev/null
  [[ "$(tcount '^fsd start')" == "1" ]] && ok "AC2-a 미시작→start 위임" || bad "AC2-a 미시작→start 위임"
  [[ -n "$(get_run_id s1)" ]] && ok "AC2-a run-id 기록됨" || bad "AC2-a run-id 기록됨"
  # AC3 멱등: 같은 상태(이제 run-id 참) 재드레인 → 중복 start 없음.
  MOCK_TERM=running poll_task s1 >/dev/null
  chk "AC3 멱등: start 중복 없음(총 1회)" "$(tcount '^fsd start')" "1"

  # ---- AC2-b: 구현 완료(loop done) + PR 없음 → 통합 integrate(C2) ----
  : > "$TRACE"
  ensure_task_dir g1; set_field g1 backend-status "In Progress"; set_run_id g1 "run-g1"; add_spec g1 "$spec"
  MOCK_TERM=done poll_task g1 >/dev/null
  chk "AC2-b loop done→integrate(1회)" "$(tcount 'forge integrate')" "1"
  [[ -n "$(get_pr g1)" ]] && ok "AC2-b PR 기록됨" || bad "AC2-b PR 기록됨"
  # AC3 멱등: PR 이 찼으니 재드레인은 integrate 재호출/중복 PR 없이 외부 승인 대기 no-op.
  MOCK_TERM=done MOCK_APPROVED=0 poll_task g1 >/dev/null
  chk "AC3 멱등: integrate 중복 없음(총 1회)" "$(tcount 'forge integrate')" "1"
  chk "AC3 재드레인은 외부 승인 대기 no-op(상태 불변)" "$(get_field g1 backend-status)" "Review"

  # ---- AC2-c: PR 열림·미승인 → 외부 승인 대기(전진 없음·상태 불변) ----
  # 내부 자동 리뷰 고리 제거 후 미승인 PR 은 어떤 모듈도 호출하지 않고 상태를 바꾸지 않는다.
  : > "$TRACE"
  ensure_task_dir v1; set_field v1 backend-status "Review"; set_pr v1 "PR-v1"
  set_branch v1 "feat/v1-x"; add_spec v1 "$spec"
  MOCK_APPROVED=0 poll_task v1 >/dev/null
  [[ "$(tcount 'merge finish')" == "0" ]] && ok "AC2-c 미승인→머지 안 함" || bad "AC2-c 미승인→머지 안 함"
  chk "AC2-c 미승인→상태 불변(전진 없음)" "$(get_field v1 backend-status)" "Review"
  # AC3 멱등: 동일 상태 재드레인 → 결과 동일, 상태 불변·머지 전이 없음.
  MOCK_APPROVED=0 poll_task v1 >/dev/null
  chk "AC3 멱등: 미승인 상태 불변" "$(get_field v1 backend-status)" "Review"
  chk "AC3 멱등: 머지 전이 없음" "$(tcount 'merge finish')" "0"

  # ---- AC2-d: PR 승인됨 → 머지(C4) → Done ----
  : > "$TRACE"
  ensure_task_dir m1; set_field m1 backend-status "Review"; set_pr m1 "PR-m1"
  set_branch m1 "feat/m1-x"; add_spec m1 "$spec"
  MOCK_APPROVED=1 poll_task m1 >/dev/null
  chk "AC2-d 승인→merge finish(1회)" "$(tcount 'merge finish')" "1"
  chk "AC2-d Done 전이" "$(get_field m1 backend-status)" "Done"
  # AC3 멱등: Done 은 종착 — 재드레인 시 머지 재호출 없음.
  MOCK_APPROVED=1 poll_task m1 >/dev/null
  chk "AC3 멱등: Done 재머지 없음(총 1회)" "$(tcount 'merge finish')" "1"

  # ---- AC2 전체: poll_drain 이 모든 task 를 한 바퀴 훑는다 ----
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
  poll              모든 진행 중 task 를 한 바퀴 정합·전진(멱등 드레인).
  task <task-id>    한 task 만 정합·전진.
  selftest          mock 인터페이스로 AC2~4·멱등 검증.

환경 변수: POLL_FSD_CMD, POLL_FORGE_CMD, POLL_MERGE_CMD,
          TASK_BACKEND_CMD, FSD_STATE_ROOT
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
