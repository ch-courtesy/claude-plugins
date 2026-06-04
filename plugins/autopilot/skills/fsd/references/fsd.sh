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

# 드레인 위임(주입 가능, 기본: 형제 모듈, 서브프로세스 격리).
FSD_POLL_CMD="${FSD_POLL_CMD:-bash $SCRIPT_DIR/poll.sh}"

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

# spec_has_marker <spec> — 미해결 사용자-결정 마커(`[NEEDS CLARIFICATION` prefix) 포함 여부.
#   spec 스킬 관례와 일치(닫는 괄호에 의존하지 않음). 매치 시 0, 아니면 1.
spec_has_marker() {
  grep -qF '[NEEDS CLARIFICATION' "$1"
}

# ----- subcommand: intake -----
# SPEC 경로(들)로 task 를 등록한다. (backend 이슈 생성은 후속 C1.)
cmd_intake() {
  require_git_root
  # 선택적 --origin <task-id>: 이 task 를 촉발한 원본 task 와의 연결을 기록.
  local origin=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --origin)   origin="${2:-}"; [[ -n "$origin" ]] || die "사용: --origin <task-id>"; shift 2 ;;
      --origin=*) origin="${1#--origin=}"; shift ;;
      *) break ;;
    esac
  done
  [[ $# -ge 1 ]] || die "사용: fsd intake [--origin <task-id>] <spec...>"
  validate_specs "$@"
  local id
  id="$(derive_task_id "${ABS_SPECS[@]}")"
  ensure_task_dir "$id"
  add_spec "$id" "${ABS_SPECS[@]}"
  set_state "$id" "intake"
  [[ -n "$origin" ]] && set_origin "$id" "$origin"
  log_event "$id" "intake specs=${#ABS_SPECS[@]}${origin:+ origin=$origin}"
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

  # 미해결 사용자-결정 마커 가드: 마커 보유 SPEC 이 하나라도 있으면 dispatch 를 막는다.
  #   spec --resume 로 빈 칸을 채운 뒤에야 구현이 시작된다(버그 분리 흐름).
  local marked=() p
  for p in "${ABS_SPECS[@]}"; do
    if spec_has_marker "$p"; then marked+=("$p"); fi
  done
  if [[ ${#marked[@]} -gt 0 ]]; then
    set_state "$id" "needs-clarification"
    log_event "$id" "start 차단 — 미해결 마커 SPEC=${#marked[@]} (spec --resume 필요)"
    echo "task-id: $id"
    for p in "${marked[@]}"; do
      echo "needs-resume: $p"
    done
    exit 1
  fi

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

# ----- subcommand: merge (미구현 — C4) -----
cmd_merge() {
  echo "fsd merge: 미구현 — 머지·Done·cleanup 은 후속 단위(C4)가 채웁니다." >&2
  exit 2
}

# ----- subcommand: poll -----
# 진행 중인 모든 task 를 한 바퀴 드레인하며 가능한 다음 한 스텝으로 전진(멱등).
# 열린 승인 요청(PR)은 외부 승인 대기 no-op, 그 외는 start·integrate·merge 경로를 전이적으로 적용한다.
cmd_poll() {
  require_git_root
  # shellcheck disable=SC2086
  $FSD_POLL_CMD poll
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
  echo "origin:   $(get_origin "$id")"
  echo "run-id:   $(get_run_id "$id")"
  echo "branch:   $(get_branch "$id")"
  echo "pr:       $(get_pr "$id")"
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

# ----- 자체 검증 (mock 인터페이스) -----
# poll 배선이 미구현 안내(exit 2)가 아니라 실제 오케스트레이터(poll)로 위임하는지
# mock 으로 검증한다. 무거운 동작은 각 모듈 selftest 가 검증(여기선 배선만).
fsd_selftest() {
  set +e   # 반환코드 기반 검증(서브셸 exit 코드 캡처)을 위해 errexit 해제.
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  export FSD_STATE_ROOT="$TMP/.fsd"
  local TRACE="$TMP/trace"; : > "$TRACE"; export TRACE
  local spec="$TMP/SPEC.md"; printf '# T\n## 수용 기준\n1. X.\n' > "$spec"

  cat > "$TMP/m-poll.sh" <<'EOF'
#!/usr/bin/env bash
echo "poll $*" >> "$TRACE"
EOF
  export FSD_POLL_CMD="bash $TMP/m-poll.sh"

  local fail=0 rc
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }

  # poll → poll 드레인 위임.
  : > "$TRACE"
  ( cmd_poll ) >/dev/null 2>&1; rc=$?
  [[ "$rc" == "0" ]] && ok "poll 위임 0 exit(미구현 아님)" || bad "poll 위임 0 exit (rc=$rc)"
  grep -q "^poll poll" "$TRACE" && ok "poll→poll 드레인 위임" || bad "poll→poll 드레인 위임"

  # ----- 버그 분리 계약: origin 기록 / 마커 가드 / 회귀 -----
  # 별도 SPEC 들(서로 다른 task-id 도출용): clean / 마커보유.
  local spec_clean="$TMP/SPEC-clean.md"
  printf '# Clean\n## 수용 기준\n1. Y.\n' > "$spec_clean"
  local spec_mark="$TMP/SPEC-mark.md"
  printf '# Marked\n## 수용 기준\n1. Z [NEEDS CLARIFICATION: 무엇을?]\n' > "$spec_mark"
  local spec_reg="$TMP/SPEC-reg.md"
  printf '# Reg\n## 수용 기준\n1. W.\n' > "$spec_reg"

  # dispatch mock: run-id 발급 + TRACE 기록.
  cat > "$TMP/m-dispatch.sh" <<'EOF'
#!/usr/bin/env bash
echo "dispatch $*" >> "$TRACE"
echo "run-id: RUN-MOCK"
EOF
  export DISPATCH_CMD="bash $TMP/m-dispatch.sh"

  # (a) intake --origin: origin 기록 + status 노출.
  local oid
  oid="$(cmd_intake --origin parent-task "$spec_clean" 2>/dev/null | sed -n 's/^task-id: //p')"
  [[ "$(get_origin "$oid")" == "parent-task" ]] && ok "intake --origin 기록" || bad "intake --origin 기록"
  # 파일로 캡처 후 grep: 함수→grep -q 파이프는 pipefail+SIGPIPE 로 거짓 실패한다.
  cmd_status "$oid" > "$TMP/status.out" 2>/dev/null
  grep -q "^origin: *parent-task" "$TMP/status.out" \
    && ok "status origin 노출" || bad "status origin 노출"

  # (a') 하위호환: --origin 없으면 origin 비어있음(기존 동작 불변).
  local nid
  nid="$(cmd_intake "$spec_reg" 2>/dev/null | sed -n 's/^task-id: //p')"
  [[ -z "$(get_origin "$nid")" ]] && ok "intake origin 없음 하위호환" || bad "intake origin 없음 하위호환"

  # (b) 마커 보유 SPEC: start 차단·미-dispatch·needs-resume 출력·state.
  : > "$TRACE"
  ( cmd_start "$spec_mark" ) > "$TMP/start-mark.out" 2>&1; rc=$?
  [[ "$rc" != "0" ]] && ok "마커 start 비-0 종료" || bad "마커 start 비-0 종료 (rc=$rc)"
  grep -q "^needs-resume: .*SPEC-mark.md" "$TMP/start-mark.out" \
    && ok "마커 needs-resume 출력" || bad "마커 needs-resume 출력"
  grep -q "^dispatch start" "$TRACE" && bad "마커 SPEC dispatch 미위임" || ok "마커 SPEC dispatch 미위임"
  local mid; mid="$(derive_task_id "$(abspath "$spec_mark")")"
  [[ "$(get_state "$mid")" == "needs-clarification" ]] \
    && ok "마커 state=needs-clarification" || bad "마커 state=needs-clarification"

  # (c) 마커 없는 SPEC: 정상 dispatch 회귀.
  : > "$TRACE"
  ( cmd_start "$spec_clean" ) > "$TMP/start-clean.out" 2>&1; rc=$?
  [[ "$rc" == "0" ]] && ok "마커없는 start 0 exit" || bad "마커없는 start 0 exit (rc=$rc)"
  grep -q "^dispatch start" "$TRACE" && ok "마커없는 SPEC dispatch 위임" || bad "마커없는 SPEC dispatch 위임"
  grep -q "^run-id: RUN-MOCK" "$TMP/start-clean.out" && ok "마커없는 run-id 기록" || bad "마커없는 run-id 기록"
  [[ "$(get_state "$oid")" == "dispatched" ]] && ok "마커없는 state=dispatched" || bad "마커없는 state=dispatched"

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ----- 사용법 -----
usage() {
  cat >&2 <<'EOF'
usage: fsd.sh <subcommand> [args]

Subcommands:
  intake [--origin <task-id>] <spec...>
                     SPEC 경로(들)로 task 를 등록(상태 저장소에 기록).
                     --origin: 이 task 를 촉발한 원본 task 와의 연결을 기록(버그 분리).
  start  <spec...>   task 의 SPEC(들)을 dispatch 에 위임하고 run-id 를 기록.
  merge  <task-id>   머지·Done·cleanup (미구현 — C4).
  poll               진행 중 task 한 바퀴 드레인·전이(멱등).
  status <task-id>   task 단위 상태 출력.
  list               모든 task 와 요약(빈 상태면 0 exit).
  stop   <task-id>   task 가 소유한 dispatch run 정지 위임.

환경 변수:
  DISPATCH_CMD, FSD_POLL_CMD, FSD_STATE_ROOT
EOF
  exit 1
}

# ----- 디스패처 -----
if [[ $# -lt 1 ]]; then usage; fi
SUB="$1"; shift
case "$SUB" in
  intake) cmd_intake "$@" ;;
  start)  cmd_start  "$@" ;;
  merge)  cmd_merge  "$@" ;;
  poll)   cmd_poll   "$@" ;;
  status) cmd_status "$@" ;;
  list)   cmd_list   "$@" ;;
  stop)   cmd_stop   "$@" ;;
  selftest) fsd_selftest ;;
  -h|--help|help) usage ;;
  *) echo "알 수 없는 subcommand: $SUB" >&2; usage ;;
esac
