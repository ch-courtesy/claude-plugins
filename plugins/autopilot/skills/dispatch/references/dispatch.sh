#!/usr/bin/env bash
# dispatch.sh — autopilot:dispatch 외부 셸 드라이버
#
# 책임:
#   - milestone-level ops (status/stop/list/cleanup/logs)
#   - sentinel watch (wave 내 child loop들의 DONE/.loop/ESCALATION.md 폴링)
#   - DISPATCH_LOG.md 기록
#
# **하지 않는 일**:
#   - PRD 분해 (모델이 dispatch SKILL.md 흐름에서 수행)
#   - 게이트 3종 대화 (모델 + AskUserQuestion)
#   - wave 병렬 실행 자체 (모델이 Bash(loop start ...) 호출)
#
# 사용:
#   bash dispatch.sh status   <milestone>
#   bash dispatch.sh stop     <milestone>
#   bash dispatch.sh list
#   bash dispatch.sh cleanup  [<milestone>]
#   bash dispatch.sh logs     <milestone>
#   bash dispatch.sh watch_wave <milestone> <child1> [<child2> ...]
#   bash dispatch.sh log_event  <milestone> <event-line>
#
# 환경 변수:
#   LOOP_WORKTREE_BASE   loop.sh와 동일 (워크트리 부모)
#   WATCH_POLL_SECONDS   sentinel 폴링 간격 (기본: 2)
#   WATCH_TIMEOUT_SECONDS  watch_wave 최대 대기 (기본: 7200 = 2시간)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----- 헬퍼 -----

die() {
  echo "ERROR: $*" >&2
  exit 1
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

validate_milestone() {
  local m="$1"
  [[ -z "$m" ]] && die "milestone-id가 비어 있음"
  [[ "$m" == *..* ]] && die "milestone-id에 '..' 사용 불가"
  case "$m" in
    .|./*|*/.|*/./*) die "milestone-id에 '.' 단독 컴포넌트 사용 불가" ;;
  esac
  [[ "$m" == *__* ]] && die "milestone-id에 '__' 사용 불가"
  [[ "$m" == *' '* ]] && die "milestone-id에 공백 사용 불가"
  return 0
}

compute_milestone_paths() {
  local milestone="$1"
  validate_milestone "$milestone"
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  PROJECT_NAME="$(basename "$PROJECT_ROOT")"
  WT_BASE="${LOOP_WORKTREE_BASE:-$PROJECT_ROOT/../${PROJECT_NAME}-loops}"
  MILESTONE="$milestone"
  MILESTONE_DIR="$PROJECT_ROOT/milestones/$milestone"
  PRD_PATH="$MILESTONE_DIR/prd/PRD.md"
  DAG_PATH="$MILESTONE_DIR/dispatch/DAG.md"
  LOG_PATH="$MILESTONE_DIR/dispatch/DISPATCH_LOG.md"
  LOCK_DIR="$PROJECT_ROOT/.loops/locks"
}

ensure_dispatch_dir() {
  mkdir -p "$MILESTONE_DIR/dispatch"
}

# 슬래시를 __로 인코딩 (loop.sh sanitize_for_filename과 일치)
sanitize_for_filename() {
  echo "${1//\//__}"
}

# child 워크트리 경로
child_wt_path() {
  local milestone="$1"
  local child="$2"
  echo "$WT_BASE/$milestone/$child"
}

# child의 lock 파일 경로 (loop.sh 명명 규칙과 일치)
child_lock_path() {
  local milestone="$1"
  local child="$2"
  local task_id="$milestone/$child"
  local safe="$(sanitize_for_filename "$task_id")"
  echo "$LOCK_DIR/$safe.lock"
}

# child의 sentinel 상태: done / escalated / running / idle / missing
child_state() {
  local milestone="$1"
  local child="$2"
  local wt="$(child_wt_path "$milestone" "$child")"
  local lock="$(child_lock_path "$milestone" "$child")"

  if [[ -f "$wt/DONE" ]]; then
    echo "done"
    return
  fi
  if [[ -f "$wt/.loop/ESCALATION.md" ]]; then
    echo "escalated"
    return
  fi
  if [[ -f "$lock" ]]; then
    echo "running"
    return
  fi
  if [[ -d "$wt" ]]; then
    echo "idle"
    return
  fi
  echo "missing"
}

# DAG.md에서 child 단위 목록 추출 (단순 grep)
# 형식: "- child-name: ..."
list_dag_children() {
  local dag="$1"
  [[ -f "$dag" ]] || return 0
  grep -oE '^- [a-zA-Z0-9_-]+:' "$dag" 2>/dev/null \
    | sed -e 's/^- //' -e 's/:$//' \
    | sort -u
}

# ----- subcommand: status -----

cmd_status() {
  local milestone="$1"
  [[ -z "$milestone" ]] && die "사용: $0 status <milestone>"
  compute_milestone_paths "$milestone"

  echo "Milestone: $milestone"
  echo "Path:      $MILESTONE_DIR"

  if [[ "$milestone" == "regular" ]]; then
    echo "Type:      regular (ad-hoc catch-all, PRD/DAG 없음)"
  else
    if [[ -f "$PRD_PATH" ]]; then
      echo "PRD:       $PRD_PATH"
      local markers
      markers=$(grep -c '\[NEEDS CLARIFICATION' "$PRD_PATH" 2>/dev/null || echo 0)
      if [[ "$markers" -gt 0 ]]; then
        echo "Markers:   $markers (resolve via prd --resume)"
      else
        echo "Markers:   0"
      fi
    else
      echo "PRD:       (없음 — prd 스킬로 작성)"
    fi

    if [[ -f "$DAG_PATH" ]]; then
      echo "DAG:       $DAG_PATH"
    else
      echo "DAG:       (없음 — dispatch start로 분해)"
    fi
  fi

  # child 상태 — DAG에서 추출하거나 worktree 디렉토리 탐색
  echo ""
  echo "Children:"
  local children=""
  if [[ -f "$DAG_PATH" ]]; then
    children=$(list_dag_children "$DAG_PATH")
  fi
  # DAG 없거나 비어있으면 워크트리 디렉토리 탐색으로 추정
  if [[ -z "$children" ]] && [[ -d "$WT_BASE/$milestone" ]]; then
    children=$(ls "$WT_BASE/$milestone" 2>/dev/null | sort -u || true)
  fi

  if [[ -z "$children" ]]; then
    echo "  (없음)"
    return 0
  fi

  printf "  %-30s %s\n" "CHILD" "STATE"
  printf "  %-30s %s\n" "------------------------------" "-------------"
  while IFS= read -r child; do
    [[ -z "$child" ]] && continue
    local state
    state=$(child_state "$milestone" "$child")
    printf "  %-30s %s\n" "$child" "$state"
  done <<< "$children"
}

# ----- subcommand: stop -----

cmd_stop() {
  local milestone="$1"
  [[ -z "$milestone" ]] && die "사용: $0 stop <milestone>"
  compute_milestone_paths "$milestone"
  ensure_dispatch_dir

  echo "[$(now_iso)] dispatch stop milestone=$milestone"
  local any_stopped=0
  local children=""
  if [[ -f "$DAG_PATH" ]]; then
    children=$(list_dag_children "$DAG_PATH")
  fi
  if [[ -z "$children" ]] && [[ -d "$WT_BASE/$milestone" ]]; then
    children=$(ls "$WT_BASE/$milestone" 2>/dev/null | sort -u || true)
  fi

  if [[ -z "$children" ]]; then
    echo "정지할 child 없음."
    return 0
  fi

  while IFS= read -r child; do
    [[ -z "$child" ]] && continue
    local lock="$(child_lock_path "$milestone" "$child")"
    if [[ -f "$lock" ]]; then
      echo "[$(now_iso)] child $child stop 요청"
      local pid
      pid=$(cat "$lock" 2>/dev/null || echo "")
      if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        any_stopped=1
        log_event_internal "stop child=$child pid=$pid"
      else
        echo "  WARN: $child lock 파일에 활성 PID 없음 (stale)"
        rm -f "$lock" || true
      fi
    fi
  done <<< "$children"

  if [[ $any_stopped -eq 0 ]]; then
    echo "활성 child loop 없음. 모두 이미 정지됨."
  fi
}

# ----- subcommand: list -----

cmd_list() {
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  PROJECT_NAME="$(basename "$PROJECT_ROOT")"
  WT_BASE="${LOOP_WORKTREE_BASE:-$PROJECT_ROOT/../${PROJECT_NAME}-loops}"
  LOCK_DIR="$PROJECT_ROOT/.loops/locks"

  local milestones_base="$PROJECT_ROOT/milestones"
  if [[ ! -d "$milestones_base" ]]; then
    echo "milestones/ 디렉터리 없음. 새 milestone 생성: Skill(skill: \"prd\", args: \"<milestone-id>\")"
    return 0
  fi

  printf "%-30s %-10s %-10s %s\n" "MILESTONE" "PRD" "DAG" "CHILDREN"
  printf "%-30s %-10s %-10s %s\n" "------------------------------" "----------" "----------" "--------"

  local entry
  for entry in "$milestones_base"/*/; do
    [[ -d "$entry" ]] || continue
    local milestone
    milestone=$(basename "$entry")
    local prd_state="no" dag_state="no" child_count=0
    [[ -f "$entry/prd/PRD.md" ]] && prd_state="yes"
    [[ -f "$entry/dispatch/DAG.md" ]] && dag_state="yes"

    # child 개수 — DAG가 있으면 거기서, 없으면 워크트리 디렉토리 갯수
    if [[ -f "$entry/dispatch/DAG.md" ]]; then
      child_count=$(list_dag_children "$entry/dispatch/DAG.md" | grep -c . || true)
    elif [[ -d "$WT_BASE/$milestone" ]]; then
      child_count=$(ls "$WT_BASE/$milestone" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    fi
    printf "%-30s %-10s %-10s %s\n" "$milestone" "$prd_state" "$dag_state" "$child_count"
  done
}

# ----- subcommand: cleanup -----

cmd_cleanup() {
  local milestone="${1:-}"
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  PROJECT_NAME="$(basename "$PROJECT_ROOT")"
  WT_BASE="${LOOP_WORKTREE_BASE:-$PROJECT_ROOT/../${PROJECT_NAME}-loops}"

  local milestones_to_clean=()
  if [[ -n "$milestone" ]]; then
    validate_milestone "$milestone"
    milestones_to_clean=("$milestone")
  else
    # 모든 milestone (regular 포함, 워크트리가 있는 것만)
    [[ -d "$WT_BASE" ]] || { echo "워크트리 베이스 없음. 정리할 것 없음."; return 0; }
    local entry
    for entry in "$WT_BASE"/*/; do
      [[ -d "$entry" ]] || continue
      milestones_to_clean+=("$(basename "$entry")")
    done
  fi

  if [[ ${#milestones_to_clean[@]} -eq 0 ]]; then
    echo "정리할 milestone 없음."
    return 0
  fi

  local m
  for m in "${milestones_to_clean[@]}"; do
    compute_milestone_paths "$m"
    local cleaned=0
    if [[ -d "$WT_BASE/$m" ]]; then
      local child
      for child in $(ls "$WT_BASE/$m" 2>/dev/null || true); do
        local wt="$(child_wt_path "$m" "$child")"
        if [[ -f "$wt/DONE" ]]; then
          echo "[$(now_iso)] cleanup $m/$child (DONE 신호 있음)"
          # loop.sh의 cleanup을 호출하지 않음 — git worktree 제거는 git만으로
          git -C "$PROJECT_ROOT" worktree remove --force "$wt" 2>/dev/null || true
          rm -rf "$wt" 2>/dev/null || true
          cleaned=$((cleaned + 1))
        fi
      done
      # 빈 milestone 디렉토리 제거
      if [[ -d "$WT_BASE/$m" ]] && [[ -z "$(ls "$WT_BASE/$m" 2>/dev/null)" ]]; then
        rmdir "$WT_BASE/$m" 2>/dev/null || true
      fi
    fi
    echo "milestone $m: $cleaned 개 cleanup. PRD/DAG 보존."
  done
}

# ----- subcommand: logs -----

cmd_logs() {
  local milestone="$1"
  [[ -z "$milestone" ]] && die "사용: $0 logs <milestone>"
  compute_milestone_paths "$milestone"
  if [[ ! -f "$LOG_PATH" ]]; then
    die "DISPATCH_LOG.md 없음: $LOG_PATH"
  fi
  cat "$LOG_PATH"
}

# ----- subcommand: log_event (모델 호출용) -----

log_event_internal() {
  local event="$1"
  ensure_dispatch_dir
  if [[ ! -f "$LOG_PATH" ]]; then
    cat > "$LOG_PATH" <<EOF
# DISPATCH_LOG — $MILESTONE

이 파일은 runtime 로그입니다. git에 commit하지 마세요 (.gitignore 처리 권장).
EOF
  fi
  echo "[$(now_iso)] $event" >> "$LOG_PATH"
}

cmd_log_event() {
  local milestone="$1"; shift || true
  [[ -z "$milestone" ]] && die "사용: $0 log_event <milestone> <event...>"
  compute_milestone_paths "$milestone"
  local event="$*"
  [[ -z "$event" ]] && die "이벤트 본문이 비어 있음"
  log_event_internal "$event"
}

# ----- subcommand: watch_wave -----
#
# 여러 child의 sentinel 파일을 폴링.
# 한 명이라도 ESCALATION.md를 만들면 다른 child들 stop + exit 101.
# 모두 DONE이면 exit 100.
# 타임아웃 시 exit 102.

cmd_watch_wave() {
  local milestone="$1"; shift || true
  [[ -z "$milestone" ]] && die "사용: $0 watch_wave <milestone> <child1> [<child2> ...]"
  [[ $# -eq 0 ]] && die "child 목록이 비어 있음"
  compute_milestone_paths "$milestone"
  ensure_dispatch_dir

  local children=("$@")
  local poll="${WATCH_POLL_SECONDS:-2}"
  local timeout="${WATCH_TIMEOUT_SECONDS:-7200}"
  local start_time
  start_time=$(date +%s)

  log_event_internal "watch_wave START children=[${children[*]}]"

  while true; do
    local all_done=1
    local any_escalated=0
    local escalated_child=""

    local c
    for c in "${children[@]}"; do
      local state
      state=$(child_state "$milestone" "$c")
      case "$state" in
        done)
          ;;
        escalated)
          any_escalated=1
          escalated_child="$c"
          all_done=0
          break
          ;;
        *)
          all_done=0
          ;;
      esac
    done

    if [[ $any_escalated -eq 1 ]]; then
      log_event_internal "watch_wave ESCALATION child=$escalated_child — stopping others"
      # 다른 진행 중 child들 stop
      for c in "${children[@]}"; do
        [[ "$c" == "$escalated_child" ]] && continue
        local state
        state=$(child_state "$milestone" "$c")
        if [[ "$state" == "running" ]]; then
          local lock="$(child_lock_path "$milestone" "$c")"
          local pid
          pid=$(cat "$lock" 2>/dev/null || echo "")
          if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
            log_event_internal "watch_wave fail-fast stop child=$c pid=$pid"
          fi
        fi
      done
      exit 101
    fi

    if [[ $all_done -eq 1 ]]; then
      log_event_internal "watch_wave ALL DONE children=[${children[*]}]"
      exit 100
    fi

    # 타임아웃 체크
    local now_time
    now_time=$(date +%s)
    if [[ $((now_time - start_time)) -ge $timeout ]]; then
      log_event_internal "watch_wave TIMEOUT after ${timeout}s — stopping running children"
      # 진행 중 child들 stop (ESCALATION 분기와 동일한 실패 격리, orphan 방지)
      for c in "${children[@]}"; do
        local state
        state=$(child_state "$milestone" "$c")
        if [[ "$state" == "running" ]]; then
          local lock="$(child_lock_path "$milestone" "$c")"
          local pid
          pid=$(cat "$lock" 2>/dev/null || echo "")
          if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
            log_event_internal "watch_wave timeout-stop child=$c pid=$pid"
          fi
        fi
      done
      exit 102
    fi

    sleep "$poll"
  done
}

# ----- 사용법 출력 -----

usage() {
  cat >&2 <<'EOF'
autopilot dispatch 드라이버

Subcommands:
  status <m>                            milestone 상태 (PRD/DAG/child) 조회
  stop <m>                              진행 중 모든 child loop 정지
  list                                  모든 milestone 목록
  cleanup [<m>]                         완료된 워크트리 정리. PRD/DAG 보존
  logs <m>                              milestones/<m>/dispatch/DISPATCH_LOG.md 출력
  watch_wave <m> <child...>             wave 내 child들 sentinel 폴링 (모델이 호출)
  log_event <m> <event...>              DISPATCH_LOG.md에 이벤트 추가 (모델이 호출)

자세한 내용: plugins/autopilot/skills/dispatch/SKILL.md
EOF
  exit 1
}

# ----- subcommand 디스패처 -----

if [[ $# -lt 1 ]]; then
  usage
fi

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  status)
    cmd_status "${1:-}"
    ;;
  stop)
    cmd_stop "${1:-}"
    ;;
  list)
    cmd_list
    ;;
  cleanup)
    cmd_cleanup "${1:-}"
    ;;
  logs)
    cmd_logs "${1:-}"
    ;;
  watch_wave)
    cmd_watch_wave "$@"
    ;;
  log_event)
    cmd_log_event "$@"
    ;;
  *)
    echo "알 수 없는 subcommand: $SUBCOMMAND" >&2
    usage
    ;;
esac
