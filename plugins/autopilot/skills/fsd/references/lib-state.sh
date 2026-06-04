#!/usr/bin/env bash
# lib-state.sh — autopilot:fsd 상태 저장소 헬퍼 (골격, C0)
#
# 책임:
#   - task 단위의 진행 상태를 프로젝트 루트 하위 전용 디렉토리에 보관·조회·기록.
#   - 기본 위치: <project_root>/.fsd/tasks/<task-id>/
#     task 별로 격리된 디렉토리를 갖고 다음을 담는다:
#       state          상태 로컬 미러 (intake|dispatching|dispatched|...|done|failed)
#       SPECS.txt      이 task 가 다루는 SPEC 경로 목록 (append-only)
#       branch         작업 브랜치 이름                  (forge 연동은 후속 단위)
#       pr             PR 번호                            (forge 연동은 후속 단위)
#       run-id         이 task 가 소유한 dispatch run 식별자
#       head           마지막으로 관측한 head 식별자
#       origin         이 task 를 촉발한 원본 task 식별자  (버그 분리 연결, 선택)
#       LOG.md         append-only 이벤트 로그
#
# **하지 않는 일**:
#   - forge(PR/issue/label)·task backend 연동 (후속 단위 references 모듈 책임).
#   - dispatch / loop 의 내부 상태 디렉토리·신호 파일 해석.
#
# 이 헬퍼는 sourcing 으로 사용한다. <project_root>/.fsd/ 디렉토리 밖 경로는
# 만들지 않는다. bash 3.2+ 호환 (associative array 미사용).

# state_root — 상태 루트. FSD_STATE_ROOT 로 재정의 가능(테스트용).
#   기본: <project_root>/.fsd  (PROJECT_ROOT 는 호출자 fsd.sh 가 export)
state_root() {
  echo "${FSD_STATE_ROOT:-${PROJECT_ROOT:-.}/.fsd}"
}

# tasks_dir — 모든 task 디렉토리의 부모: .fsd/tasks
tasks_dir() {
  echo "$(state_root)/tasks"
}

# task_dir <task-id> — 한 task 의 격리 디렉토리 경로.
task_dir() {
  echo "$(tasks_dir)/$1"
}

# ensure_task_dir <task-id> — task 디렉토리 생성(idempotent).
ensure_task_dir() {
  mkdir -p "$(task_dir "$1")"
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ----- 일반 필드 IO -----

# set_field <task-id> <field> <value>
set_field() {
  local id="$1" field="$2" value="$3"
  ensure_task_dir "$id"
  printf '%s\n' "$value" > "$(task_dir "$id")/$field"
}

# get_field <task-id> <field> [<default>]
get_field() {
  local id="$1" field="$2" def="${3:-}"
  local f
  f="$(task_dir "$id")/$field"
  if [[ -f "$f" ]]; then cat "$f"; else printf '%s\n' "$def"; fi
}

# ----- 의미 있는 래퍼 -----

set_state()   { set_field "$1" "state" "$2"; }
get_state()   { get_field "$1" "state" "unknown"; }

set_run_id()  { set_field "$1" "run-id" "$2"; }
get_run_id()  { get_field "$1" "run-id" ""; }

set_branch()  { set_field "$1" "branch" "$2"; }
get_branch()  { get_field "$1" "branch" ""; }

set_pr()      { set_field "$1" "pr" "$2"; }
get_pr()      { get_field "$1" "pr" ""; }

set_head()    { set_field "$1" "head" "$2"; }
get_head()    { get_field "$1" "head" ""; }

# origin — 이 task 를 촉발한 원본 task 의 식별자(버그 분리 연결). 없으면 빈 값.
set_origin()  { set_field "$1" "origin" "$2"; }
get_origin()  { get_field "$1" "origin" ""; }

# ----- SPEC 경로 집합 (append-only) -----

# add_spec <task-id> <spec...>
add_spec() {
  local id="$1"; shift
  ensure_task_dir "$id"
  local p
  for p in "$@"; do printf '%s\n' "$p" >> "$(task_dir "$id")/SPECS.txt"; done
}

# get_specs <task-id> — 한 줄에 하나씩 (없으면 빈 출력).
get_specs() {
  local f
  f="$(task_dir "$1")/SPECS.txt"
  [[ -f "$f" ]] && cat "$f" || true
}

# ----- append-only 로그 -----

# log_event <task-id> <message...>
log_event() {
  local id="$1"; shift
  ensure_task_dir "$id"
  printf '[%s] %s\n' "$(now_iso)" "$*" >> "$(task_dir "$id")/LOG.md"
}

# ----- 조회 -----

# list_tasks — 존재하는 모든 task-id 를 한 줄에 하나씩. 없으면 빈 출력(0 exit).
list_tasks() {
  local td
  td="$(tasks_dir)"
  [[ -d "$td" ]] || return 0
  local d
  for d in "$td"/*/; do
    [[ -d "$d" ]] || continue
    basename "$d"
  done
}

# task_exists <task-id>
task_exists() {
  [[ -d "$(task_dir "$1")" ]]
}
