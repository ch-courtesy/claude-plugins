#!/usr/bin/env bash
# execute-task.sh — 단일 태스크 전체 생애 드라이버 (구현→리뷰→머지→done).
#
# 책임(결정적 글루): 태스크 본문 materialize → in_progress + heartbeat lease →
#   loop.sh 로 구현(포그라운드) → DONE/BLOCKED 분류 → forge 어댑터로 integrate→review→merge →
#   백엔드 상태 전이(review/done/blocked). 의존성·DAG 는 다루지 않는다(workflow-task 가 fan-out).
#
# 재사용 엔진(런타임 호출, 그대로 둠): loop.sh(ralph), forge 어댑터(dispatch 워커 헬퍼 래핑).
# 백엔드 연동: task-backend/adapter.sh. 무인 실행: 대화형 호출 없음, 차단은 blocked 상태+로그.
#
# 모킹: ADAPTER_CMD / LOOP_CMD / FORGE_CMD 환경변수로 엔진 치환(테스트).
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PLUGIN="$ROOT_DIR/plugins/autopilot"
# 플러그인 자신이 소비처가 아닐 때(설치형): 스크립트 위치 기준으로도 해석
[[ -d "$PLUGIN" ]] || PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

ADAPTER_CMD="${ADAPTER_CMD:-bash $PLUGIN/task-backend/adapter.sh}"
FORGE_CMD="${FORGE_CMD:-bash $PLUGIN/forge/forge.sh}"
LOOP_CMD="${LOOP_CMD:-bash $PLUGIN/skills/loop/references/loop.sh}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-60}"
REVIEW_MAX="${REVIEW_MAX:-5}"

die() { echo "execute-task: $*" >&2; exit 1; }

HB_PID=""
cleanup_hb() { [[ -n "${HB_PID:-}" ]] && kill "$HB_PID" 2>/dev/null || true; }
trap cleanup_hb EXIT

et_start() {
  local id="" stop_at=""
  while [[ $# -gt 0 ]]; do case "$1" in
    --stop-at) stop_at="$2"; shift 2;;
    -*) shift;;
    *) [[ -z "$id" ]] && id="$1"; shift;;
  esac; done
  [[ -n "$id" ]] || die "start <task-id> [--stop-at review]"

  local sp; sp="$($ADAPTER_CMD materialize --task-id "$id" | jq -r .spec_path)"
  [[ -n "$sp" && "$sp" != null ]] || die "materialize 실패: $id"

  local owner; owner="$(hostname 2>/dev/null || echo host)-$$"

  # 원자적 실행권 획득(중복 실행 방지). 이미 다른 실행자가 점유 중이면 조용히 skip(에러 아님).
  local claimed; claimed="$($ADAPTER_CMD claim --task-id "$id" --owner "$owner" | jq -r '.claimed // false')"
  if [[ "$claimed" != "true" ]]; then echo "execute-task: 이미 다른 실행자가 점유 — skip ($id)"; return 0; fi

  # reclaim: 죽은 워커 잔재 정리(있으면) — loop 가 notes/worktree 로 이어받음
  $LOOP_CMD cleanup "$sp" --force >/dev/null 2>&1 || true

  # 백그라운드 heartbeat (lease 갱신). 연속 실패 시 lease 를 잃어 이중 실행 위험 → fail-fast 로 메인 중단.
  ( fail=0
    while true; do
      if $ADAPTER_CMD renew_lease --task-id "$id" --owner "$owner" >/dev/null 2>&1; then fail=0
      else fail=$((fail+1)); if (( fail >= 3 )); then
        echo "execute-task: heartbeat lease 갱신 연속 실패 — 작업 중단($id)" >&2
        kill -TERM $$ 2>/dev/null || true; exit 1
      fi; fi
      sleep "$HEARTBEAT_INTERVAL"
    done ) &
  HB_PID=$!

  # 구현 (포그라운드 블로킹)
  $LOOP_CMD start "$sp" || true

  # 분류
  local sj signals; sj="$($LOOP_CMD status --json "$sp" 2>/dev/null || echo '{}')"
  # loop status --json 은 JSON 계약 → 필수 의존성 jq 로 읽는다(미선언 yq 회피).
  signals="$(printf '%s' "$sj" | jq -r '.signals[]?' 2>/dev/null || true)"
  if printf '%s\n' "$signals" | grep -Fxq BLOCKED; then
    $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "loop BLOCKED" >/dev/null
    $ADAPTER_CMD append_log --task-id "$id" --marker blocked --text "loop BLOCKED" >/dev/null
    return 1
  fi
  if ! printf '%s\n' "$signals" | grep -Fxq DONE; then
    $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "loop 미완(DONE 신호 없음)" >/dev/null
    return 1
  fi

  $ADAPTER_CMD set_status --task-id "$id" --status review >/dev/null
  if [[ "$stop_at" == "review" ]]; then echo "execute-task: review 단계 정지 ($id)"; return 0; fi

  # forge: integrate → review(승인까지 반복, 가드) → merge (origin 라우팅)
  local run_dir="$ROOT_DIR/.autopilot/runs/$id"; mkdir -p "$run_dir"
  local key="$id"
  local iout branch pr=""
  iout="$($FORGE_CMD integrate "$sp" "$run_dir" "$key" 2>&1)" || {
    $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "integrate 실패" >/dev/null; echo "$iout" >&2; return 1; }
  branch="$(printf '%s' "$iout" | sed -n 's/^branch:[[:space:]]*//p' | head -1)"
  pr="$(printf '%s' "$iout" | sed -n 's/^pr:[[:space:]]*//p' | head -1)"

  local n=0 approved=0
  while (( n < REVIEW_MAX )); do
    n=$((n+1))
    if $FORGE_CMD review "$run_dir" "$key" "$sp" "$pr" "$branch"; then approved=1; break; fi
    # 비-0: 재작업/대기/에스컬레이션 — review-loop 내부 가드가 재구현/판정. 한 라운드 더 시도.
  done
  if (( ! approved )); then
    $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "리뷰 미승인(에스컬레이션/가드)" >/dev/null
    $ADAPTER_CMD append_log --task-id "$id" --marker blocked --text "review 미승인 ($n 라운드)" >/dev/null
    return 1
  fi

  if $FORGE_CMD merge "$sp" "$run_dir" "$key" "$pr"; then
    $ADAPTER_CMD set_status --task-id "$id" --status done >/dev/null
    $ADAPTER_CMD append_log --task-id "$id" --marker handoff --text "merged ${branch:+($branch)}" >/dev/null
    echo "execute-task: done ($id)"
  else
    $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "merge 실패" >/dev/null
    return 1
  fi
}

et_passthrough() {  # status|stop|logs <task-id> → loop 위임
  local sub="$1" id="$2"
  local sp; sp="$($ADAPTER_CMD materialize --task-id "$id" | jq -r .spec_path)"
  $LOOP_CMD "$sub" "$sp"
}

main() {
  local verb="${1:-}"; shift || true
  case "$verb" in
    start) et_start "$@";;
    status|stop|logs) et_passthrough "$verb" "$@";;
    ""|-h|--help|help) echo "usage: execute-task.sh start <task-id> [--stop-at review] | status|stop|logs <task-id>" >&2; exit 2;;
    *) die "알 수 없는 동사: $verb";;
  esac
}
main "$@"
