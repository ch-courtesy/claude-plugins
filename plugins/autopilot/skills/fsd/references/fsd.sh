#!/usr/bin/env bash
# fsd.sh — autopilot:fsd 서브커맨드 라우터 (골격, C0)
#
# 책임:
#   - 호출을 받아 해당 서브커맨드 핸들러로 분기.
#   - 프로젝트 루트 탐지 + 상태 저장소(.fsd/) 초기화.
#   - intake / start 는 spec·dispatch 조합까지만 수행한다 (forge 없음):
#       intake  — SPEC 경로(들)로 task 를 등록 (상태 저장소에 기록).
#       start   — task 의 SPEC(들)을 dispatch 의 공개 서브커맨드로 위임하고
#                 그 run 식별자를 task 상태 디렉토리에 기록.
#
# **하지 않는 일** (후속 단위 references 모듈이 채운다):
#   - forge(이슈/PR/머지/라벨)·task backend 연동.   → C1·C2·C4
#   - 리뷰 피드백 루프.                              → C3
#   - poll 드레인·상시 호스트 운영.                  → C5
#   fsd 는 본 골격에서 forge CLI 를 직접 호출하지 않는다. dispatch·spec 의
#   공개 인터페이스만 소비한다.
#
# 사용:
#   bash fsd.sh intake <spec...>
#   bash fsd.sh start  <spec...>
#   bash fsd.sh review <task-id>     (미구현 — C3)
#   bash fsd.sh merge  <task-id>     (미구현 — C4)
#   bash fsd.sh poll                 (미구현 — C5)
#   bash fsd.sh status <task-id>
#   bash fsd.sh list
#   bash fsd.sh stop   <task-id>
#
# 환경 변수:
#   DISPATCH_CMD          dispatch driver 호출 명령 (기본: 형제 dispatch.sh).
#                         테스트에서 mock 으로 치환 가능.
#   FSD_STATE_ROOT  상태 루트 (기본 <project_root>/.fsd). lib-state.sh 참조.
#
# bash 3.2+ 호환 (associative array 미사용).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 상태 저장소 헬퍼 로드.
# shellcheck source=lib-state.sh
. "$SCRIPT_DIR/lib-state.sh"

# 구현 위임은 dispatch 의 공개 서브커맨드로만 한다(SPEC 제약).
DISPATCH_CMD_DEFAULT="bash $SCRIPT_DIR/../../dispatch/references/dispatch.sh"
DISPATCH_CMD="${DISPATCH_CMD:-$DISPATCH_CMD_DEFAULT}"

# ----- 공통 헬퍼 -----

die() { echo "ERROR: $*" >&2; exit 1; }

# 프로젝트 루트 탐지 + 상태 루트 노출.
require_git_root() {
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  export PROJECT_ROOT
}

# spec_slug — SPEC 경로에서 slug 도출 (dispatch.sh 패턴 차용).
#   구 형식 <date>-<slug>.md      → 파일명에서 .md·YYYY-MM-DD- prefix 제거.
#   신 형식 <date>-<slug>/SPEC.md → 부모 디렉토리명에서 도출.
spec_slug() {
  local b
  b="$(basename "$1")"
  if [[ "$b" == "SPEC.md" ]]; then
    b="$(basename "$(dirname "$1")")"
  else
    b="${b%.md}"
  fi
  echo "$b" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//'
}

# hash7 — sort 된 인자들의 sha256 첫 7 자 (dispatch.sh 패턴 차용).
hash7() {
  local hasher=""
  if command -v sha256sum >/dev/null 2>&1; then
    hasher="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    hasher="shasum -a 256"
  else
    die "sha256sum 또는 shasum 필요"
  fi
  printf '%s\n' "$@" | sort -u | $hasher | cut -c1-7
}

# abspath — 절대·정규화 경로. 호출처는 존재하는 경로만 넘긴다.
abspath() {
  local p="$1"
  (cd "$(dirname "$p")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename "$p")")
}

# derive_task_id <spec...> — task 식별자 = 첫 SPEC slug + 입력 집합 sha7.
#   같은 SPEC 집합 → 같은 task-id (idempotent 재진입).
derive_task_id() {
  local first_slug h
  first_slug="$(spec_slug "$1")"
  h="$(hash7 "$@")"
  echo "${first_slug}-${h}"
}

# 입력 SPEC 경로들을 검증 + 절대경로화 하여 ABS_SPECS 배열에 채운다.
validate_specs() {
  ABS_SPECS=()
  local p
  for p in "$@"; do
    [[ -f "$p" ]] || die "SPEC 파일을 찾을 수 없음: $p"
    [[ -r "$p" ]] || die "SPEC 파일 읽기 불가: $p"
    ABS_SPECS+=("$(abspath "$p")")
  done
}

# dispatch 출력에서 run-id 추출. 출력의 'run-id: <id>' 마지막 줄.
extract_run_id() {
  sed -n 's/^run-id: //p' | tail -1
}

# ----- subcommand: intake -----
# SPEC 경로(들)로 task 를 등록한다. (backend 이슈 생성은 후속 C1.)
cmd_intake() {
  require_git_root
  [[ $# -ge 1 ]] || die "사용: fsd intake <spec...>"
  validate_specs "$@"
  local id
  id="$(derive_task_id "${ABS_SPECS[@]}")"
  ensure_task_dir "$id"
  add_spec "$id" "${ABS_SPECS[@]}"
  set_state "$id" "intake"
  log_event "$id" "intake specs=${#ABS_SPECS[@]}"
  echo "task-id: $id"
}

# ----- subcommand: start -----
# task 의 SPEC(들)을 dispatch 에 위임하고 run 식별자를 기록한다.
cmd_start() {
  require_git_root
  [[ $# -ge 1 ]] || die "사용: fsd start <spec...>"
  validate_specs "$@"
  local id
  id="$(derive_task_id "${ABS_SPECS[@]}")"
  ensure_task_dir "$id"
  # 아직 등록되지 않은 SPEC 이면 함께 기록(start 단독 호출 허용).
  [[ -f "$(task_dir "$id")/SPECS.txt" ]] || add_spec "$id" "${ABS_SPECS[@]}"
  set_state "$id" "dispatching"
  log_event "$id" "start → dispatch 위임 specs=${#ABS_SPECS[@]}"

  # dispatch 의 공개 서브커맨드로 위임. 내부 신호·워크트리는 들여다보지 않는다.
  local out rid
  # shellcheck disable=SC2086
  out="$($DISPATCH_CMD start "${ABS_SPECS[@]}" 2>&1)" || true
  rid="$(printf '%s\n' "$out" | extract_run_id)"

  if [[ -n "$rid" ]]; then
    set_run_id "$id" "$rid"
    log_event "$id" "dispatch run-id=$rid"
    set_state "$id" "dispatched"
    echo "task-id: $id"
    echo "run-id: $rid"
  else
    log_event "$id" "dispatch 위임 결과에서 run-id 미검출"
    set_state "$id" "dispatch-failed"
    echo "task-id: $id"
    die "dispatch run-id 를 얻지 못했습니다. dispatch 출력:
$out"
  fi
}

# ----- subcommand: review (미구현 — C3) -----
cmd_review() {
  echo "fsd review: 미구현 — 리뷰 피드백 루프는 후속 단위(C3)가 채웁니다." >&2
  exit 2
}

# ----- subcommand: merge (미구현 — C4) -----
cmd_merge() {
  echo "fsd merge: 미구현 — 머지·Done·cleanup 은 후속 단위(C4)가 채웁니다." >&2
  exit 2
}

# ----- subcommand: poll (미구현 — C5) -----
cmd_poll() {
  echo "fsd poll: 미구현 — poll 드레인·상시 호스트 운영은 후속 단위(C5)가 채웁니다." >&2
  exit 2
}

# ----- subcommand: status -----
cmd_status() {
  local id="${1:-}"
  [[ -z "$id" ]] && die "사용: fsd status <task-id>"
  require_git_root
  task_exists "$id" || die "task 없음: $id"
  echo "task-id:  $id"
  echo "path:     $(task_dir "$id")"
  echo "state:    $(get_state "$id")"
  echo "run-id:   $(get_run_id "$id")"
  echo "branch:   $(get_branch "$id")"
  echo "pr:       $(get_pr "$id")"
  echo "review:   $(review_round "$id")"
  echo "head:     $(get_head "$id")"
  echo "specs:"
  get_specs "$id" | sed 's/^/  - /'
}

# ----- subcommand: list -----
# 빈 상태에서도 0 exit 로 정상 출력.
cmd_list() {
  require_git_root
  local ids
  ids="$(list_tasks)"
  if [[ -z "$ids" ]]; then
    echo "(no tasks yet — 새 task: fsd intake <spec...>)"
    return 0
  fi
  printf "%-40s %-16s %s\n" "TASK-ID" "STATE" "RUN-ID"
  local id
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    printf "%-40s %-16s %s\n" "$id" "$(get_state "$id")" "$(get_run_id "$id")"
  done <<< "$ids"
}

# ----- subcommand: stop -----
# task 가 소유한 dispatch run 을 dispatch 의 공개 stop 서브커맨드로 정지 위임.
cmd_stop() {
  local id="${1:-}"
  [[ -z "$id" ]] && die "사용: fsd stop <task-id>"
  require_git_root
  task_exists "$id" || die "task 없음: $id"
  local rid
  rid="$(get_run_id "$id")"
  if [[ -z "$rid" ]]; then
    echo "이 task 에 연결된 dispatch run 이 없습니다: $id"
    return 0
  fi
  # shellcheck disable=SC2086
  $DISPATCH_CMD stop "$rid" || true
  set_state "$id" "stopped"
  log_event "$id" "stop → dispatch stop run-id=$rid"
  echo "stopped task-id: $id (run-id: $rid)"
}

# ----- 사용법 -----
usage() {
  cat >&2 <<'EOF'
usage: fsd.sh <subcommand> [args]

Subcommands:
  intake <spec...>   SPEC 경로(들)로 task 를 등록(상태 저장소에 기록).
  start  <spec...>   task 의 SPEC(들)을 dispatch 에 위임하고 run-id 를 기록.
  review <task-id>   리뷰 피드백 루프 (미구현 — C3).
  merge  <task-id>   머지·Done·cleanup (미구현 — C4).
  poll               run 드레인·상태 폴링 (미구현 — C5).
  status <task-id>   task 단위 상태 출력.
  list               모든 task 와 요약(빈 상태면 0 exit).
  stop   <task-id>   task 가 소유한 dispatch run 정지 위임.

환경 변수:
  DISPATCH_CMD, FSD_STATE_ROOT
EOF
  exit 1
}

# ----- 디스패처 -----
if [[ $# -lt 1 ]]; then usage; fi
SUB="$1"; shift
case "$SUB" in
  intake) cmd_intake "$@" ;;
  start)  cmd_start  "$@" ;;
  review) cmd_review "$@" ;;
  merge)  cmd_merge  "$@" ;;
  poll)   cmd_poll   "$@" ;;
  status) cmd_status "$@" ;;
  list)   cmd_list   "$@" ;;
  stop)   cmd_stop   "$@" ;;
  -h|--help|help) usage ;;
  *) echo "알 수 없는 subcommand: $SUB" >&2; usage ;;
esac
