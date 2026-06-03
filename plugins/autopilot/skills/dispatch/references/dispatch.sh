#!/usr/bin/env bash
# dispatch.sh — autopilot:dispatch driver (spec-list-driven, v0.8+)
#
# 책임:
#   - 1 개 이상의 SPEC 파일 경로를 받아 frontmatter depends_on 으로 DAG 를 구성하고
#     wave 단위로 자율 실행기(loop.sh)에 위임 호출.
#   - run-id 단위로 진행 상태를 <project_root>/.dispatch/runs/<run-id>/ 에 보관.
#   - list / status / stop / watch / --resume 운영 인터페이스 제공.
#
# **하지 않는 일**:
#   - 입력 SPEC 의 frontmatter 형식·내용 검증 (자율 실행기 책임).
#   - forge(PR/issue/label)·task 저장소 연동 (호출 레이어 책임).
#   - 자율 실행기 내부 신호 파일 포맷·iteration·worktree 결정 (loop.sh 책임).
#
# 사용:
#   bash dispatch.sh start <spec...> [--max-parallel N] [--resume <run-id>]
#   bash dispatch.sh list
#   bash dispatch.sh status <run-id>
#   bash dispatch.sh stop <run-id>
#   bash dispatch.sh watch <run-id>
#
# 환경 변수:
#   LOOP_CMD                     loop driver 호출 명령 (기본: 형제 loop.sh).
#                                테스트에서 mock 으로 치환 가능.
#   DISPATCH_POLL_SECONDS        wave 진행 폴링 간격 (기본 2)
#   DISPATCH_WAVE_TIMEOUT_SECONDS  wave 당 최대 대기 (기본 7200 = 2 시간)
#
# bash 3.2 호환 (assoc array 사용 안 함).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_CMD_DEFAULT="bash $SCRIPT_DIR/../../loop/references/loop.sh"
LOOP_CMD="${LOOP_CMD:-$LOOP_CMD_DEFAULT}"
POLL_SECONDS="${DISPATCH_POLL_SECONDS:-2}"
WAVE_TIMEOUT_SECONDS="${DISPATCH_WAVE_TIMEOUT_SECONDS:-7200}"

# ----- helpers -----

die() { echo "ERROR: $*" >&2; exit 1; }

# yq 는 loop 의 구조화 상태(status --json) 파싱의 단일 출처다. 부재 시 종료 상태를
# 판정할 수 없으므로 명확히 정지한다(텍스트 컬럼으로 silent fallback 하지 않음).
require_yq() {
  command -v yq >/dev/null 2>&1 \
    || die "'yq' 가 필요합니다 — loop 구조화 상태(status --json) 판정에 사용됩니다."
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

require_git_root() {
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  RUNS_DIR="$PROJECT_ROOT/.dispatch/runs"
}

# abspath — 절대·정규화 경로(.. 압축)를 반환. 호출처는 항상 존재하는 경로를 넘긴다
# (cmd_start 은 -f 검사 후, resolve_dep 은 매칭된 후보). 절대 경로라도 `..` 가 섞일 수
# 있으므로(신 레이아웃 형제 매칭 `<dir>/../*-<slug>/SPEC.md`) dirname+pwd 로 정규화한다.
abspath() {
  local p="$1"
  (cd "$(dirname "$p")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename "$p")")
}

# spec_slug — SPEC 경로에서 slug 도출.
#   구 형식 <date>-<slug>.md      → 파일명에서 .md·YYYY-MM-DD- prefix 제거.
#   신 형식 <date>-<slug>/SPEC.md → 본문 파일(SPEC.md)이므로 부모 디렉토리명에서 도출.
# 신·구 형식 모두 같은 의미의 slug 를 도출한다(레이아웃 전환 호환).
spec_slug() {
  local b
  b="$(basename "$1")"
  if [[ "$b" == "SPEC.md" ]]; then
    # 신 디렉토리 레이아웃: 본문은 <date>-<slug>/SPEC.md → 부모 디렉토리명 사용.
    b="$(basename "$(dirname "$1")")"
  else
    b="${b%.md}"
  fi
  echo "$b" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//'
}

# hash7 — sort 된 인자들의 sha256 첫 7 자.
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

# extract_depends_on <spec_path> — depends_on 항목을 한 줄에 하나씩 출력.
# yq 가 있으면 yq, 없으면 awk 폴백 (인라인 [a,b] 및 블록 - a 형식 모두 지원).
extract_depends_on() {
  local spec="$1"
  if command -v yq >/dev/null 2>&1; then
    local out
    out=$(yq -r '.depends_on[]?' "$spec" 2>/dev/null \
          | grep -vE '^(null)?$' || true)
    if [[ -n "$out" ]]; then echo "$out"; return; fi
  fi
  awk '
    BEGIN { fm=0; block=0 }
    /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
    fm==1 && /^depends_on:/ {
      line=$0; sub(/^depends_on:[[:space:]]*/,"",line)
      if (line ~ /^\[/) {
        gsub(/[][" ]/, "", line)
        n=split(line, arr, ",")
        for (i=1;i<=n;i++) if (arr[i] != "") print arr[i]
        next
      }
      block=1; next
    }
    fm==1 && block==1 && /^[[:space:]]+-/ {
      v=$0; sub(/^[[:space:]]*-[[:space:]]*/,"",v); gsub(/[" ]/,"",v); print v; next
    }
    fm==1 && block==1 && /^[^[:space:]-]/ { block=0 }
  ' "$spec"
}

# resolve_dep <from_spec_abspath> <dep_string> — 절대 경로 또는 ""(미해결).
# 해석 순서:
#   1) 절대 경로
#   2) project-root 상대 경로
#   3) from_spec 디렉토리 상대 경로
#   4) slug 매칭 — 구·신 레이아웃 형제 모두 탐색:
#        구 형식: <container>/*-<slug>.md      또는 <container>/<slug>.md
#        신 형식: <container>/*-<slug>/SPEC.md 또는 <container>/<slug>/SPEC.md
#      container 후보: from_dir (from 이 구 형식일 때 형제 위치) 와
#                      from_dir/.. (from 이 신 형식 <slug>/SPEC.md 일 때 형제 위치).
#      신·구 혼합 입력에서도 형제 의존을 올바르게 찾는다(레이아웃 전환 호환).
resolve_dep() {
  local from="$1"; local dep="$2"
  local from_dir; from_dir="$(dirname "$from")"
  if [[ "$dep" = /* ]] && [[ -f "$dep" ]]; then echo "$dep"; return; fi
  if [[ -n "${PROJECT_ROOT:-}" ]] && [[ -f "$PROJECT_ROOT/$dep" ]]; then
    abspath "$PROJECT_ROOT/$dep"; return
  fi
  if [[ -f "$from_dir/$dep" ]]; then abspath "$from_dir/$dep"; return; fi
  # slug 매칭 — container 후보별로 구·신 패턴 탐색.
  local container cand
  for container in "$from_dir" "$from_dir/.."; do
    for cand in \
      "$container"/*-"$dep".md \
      "$container"/"$dep".md \
      "$container"/*-"$dep"/SPEC.md \
      "$container"/"$dep"/SPEC.md; do
      [[ -f "$cand" ]] && { abspath "$cand"; return; }
    done
  done
  echo ""
}

# ----- run-id 디렉토리 IO -----

ensure_runs_dir() { mkdir -p "$RUNS_DIR"; }

run_dir() { echo "$RUNS_DIR/$1"; }

write_manifest() {
  local rd="$1"; shift
  : > "$rd/MANIFEST.txt"
  local p
  for p in "$@"; do printf '%s\n' "$p" >> "$rd/MANIFEST.txt"; done
}

read_manifest() {
  local rd="$1"
  [[ -f "$rd/MANIFEST.txt" ]] || return 1
  cat "$rd/MANIFEST.txt"
}

# write_waves <run_dir> < topo_output ("wave=N\t<spec>" lines)
write_waves() {
  local rd="$1"
  cat > "$rd/WAVES.txt"
}

# state 파일 — slug+abspath sha7 단위. pending|running|done|failed.
# spec_slug 만으로는 (a) 다른 날짜 같은 이름 (2026-05-29-x.md vs 2026-05-28-x.md)
# 와 (b) 다른 디렉토리 같은 basename 입력에서 같은 파일로 덮어쓴다. abspath sha7
# 을 suffix 로 붙여 unique 보장. log_event 용 spec_slug 는 가독성용으로 유지.
state_path() {
  local rd="$1"; local spec="$2"
  echo "$rd/state.$(spec_slug "$spec")-$(hash7 "$spec")"
}

set_state() {
  local rd="$1"; local spec="$2"; local s="$3"
  mkdir -p "$rd"
  printf '%s\n' "$s" > "$(state_path "$rd" "$spec")"
}

get_state() {
  local f; f="$(state_path "$1" "$2")"
  [[ -f "$f" ]] && cat "$f" || echo "pending"
}

log_event() {
  local rd="$1"; shift
  mkdir -p "$rd"
  printf '[%s] %s\n' "$(now_iso)" "$*" >> "$rd/LOG.md"
}

# ----- loop 인터페이스 -----

# loop_start_bg <spec> — 비동기 시작. PID 를 출력.
loop_start_bg() {
  local spec="$1"
  # shellcheck disable=SC2086
  ( $LOOP_CMD start "$spec" </dev/null >/dev/null 2>&1 ) &
  echo $!
}

# kill_tree <pid> [<sig>] — pid 와 그 자손 프로세스를 재귀적으로 kill.
# subshell 만 죽이면 손자(자손 프로세스) 가 orphan 으로 남으므로 트리 재귀가 필요.
# pgrep 가 없으면 ps 폴백, ps 마저 없으면 자손 열거를 건너뛰고 pid 만 직접 kill.
# set -euo pipefail 하에서 pgrep·ps 부재가 비0 종료로 스크립트를 죽이지 않도록
# command -v 로 존재를 먼저 확인하고 파이프라인 끝에 `|| true` 가드를 둔다.
kill_tree() {
  local pid="$1"; local sig="${2:-TERM}"
  local children=""
  if command -v pgrep >/dev/null 2>&1; then
    children=$(pgrep -P "$pid" 2>/dev/null || true)
  elif command -v ps >/dev/null 2>&1; then
    children=$(ps -o pid= -o ppid= 2>/dev/null \
                | awk -v p="$pid" '$2==p { print $1 }' || true)
  fi
  local c
  for c in $children; do
    kill_tree "$c" "$sig"
  done
  kill -"$sig" "$pid" 2>/dev/null || true
}

# loop_stop <spec> — 동기 stop 위임.
loop_stop() {
  local spec="$1"
  # shellcheck disable=SC2086
  $LOOP_CMD stop "$spec" >/dev/null 2>&1 || true
}

# loop_status_json <spec> — loop 의 구조화 상태(JSON object 1줄)를 반환.
# loop 의 공개 인터페이스(`status --json <spec>`)만 사용한다 — dispatch 는 loop 내부
# signals/·worktree 파일을 직접 읽지 않는다(불변식 보존). 빈 출력이면 미지원(레거시
# loop)·기록 부재.
loop_status_json() {
  local spec="$1"
  # shellcheck disable=SC2086
  $LOOP_CMD status --json "$spec" 2>/dev/null
}

# loop_status_state <spec> — 구조화 상태의 .state 만 추출(상태 표시용).
# 출력: idle|running|stale|terminal|absent 또는 빈 줄(미지원·부재).
loop_status_state() {
  local spec="$1" json
  json="$(loop_status_json "$spec")"
  [[ -z "$json" ]] && return 0
  printf '%s' "$json" | yq -r '.state' 2>/dev/null
}

# child_terminal_state <spec> — pending|running|done|failed|unknown
# 종료 상태를 loop 의 구조화 상태(status --json)로만 판정한다 — 출력 표의 컬럼 위치나
# 자유 텍스트 부분 문자열 일치에 의존하지 않는다(구조화 핸드오프 단일 출처).
#   done    : .state=terminal 이고 .signals 에 "BLOCKED" 가 정확 일치로 없음.
#   failed  : .state=terminal 이고 .signals 에 "BLOCKED" 가 정확 일치로 있음(워커 컨벤션).
#   running : .state=running 또는 stale.
#   pending : .state=idle 또는 absent(미실행).
#   unknown : 구조화 상태 부재(레거시 loop·yq 부재) — 텍스트 컬럼으로 폴백하지 않음.
#             호출자(결과 판정·watch)가 unknown 을 failed 로 처리한다.
child_terminal_state() {
  local spec="$1" json st
  json="$(loop_status_json "$spec")"
  if [[ -z "$json" ]]; then echo "unknown"; return; fi
  st="$(printf '%s' "$json" | yq -r '.state' 2>/dev/null)"
  case "$st" in
    terminal)
      if printf '%s' "$json" | yq -r '.signals[]' 2>/dev/null | grep -Fxq 'BLOCKED'; then
        echo "failed"
      else
        echo "done"
      fi
      ;;
    running|stale) echo "running" ;;
    idle|absent) echo "pending" ;;
    *) echo "unknown" ;;
  esac
}

# ----- DAG / wave 구성 -----

# build_dag <spec1> <spec2> ... → stdout 에 "wave=N\t<abspath>" 줄.
# bash 3.2 호환: 인덱스 기반 indeg/graph.
# graph 는 "i->j i->k" 문자열로 인코딩, indeg 는 평행 배열.
build_dag() {
  local -a SPECS=()
  local s
  for s in "$@"; do SPECS+=("$s"); done
  local n=${#SPECS[@]}
  local -a INDEG=()
  local -a EDGES=()  # "i,j" pairs
  local i j
  for ((i=0; i<n; i++)); do INDEG[i]=0; done

  # deps 해석 → edges
  local dep dep_path
  for ((i=0; i<n; i++)); do
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      dep_path="$(resolve_dep "${SPECS[i]}" "$dep")"
      if [[ -z "$dep_path" ]]; then
        echo "WARN: ${SPECS[i]}: depends_on '$dep' 해석 실패 (무시)" >&2
        continue
      fi
      # 입력 SPECS 안에서 인덱스 찾기
      local found=-1
      for ((j=0; j<n; j++)); do
        if [[ "${SPECS[j]}" == "$dep_path" ]]; then found=$j; break; fi
      done
      if [[ $found -lt 0 ]]; then
        # 외부 의존성은 dispatch 범위 밖, 무시.
        continue
      fi
      EDGES+=("$found,$i")
      INDEG[i]=$((INDEG[i]+1))
    done < <(extract_depends_on "${SPECS[i]}")
  done

  # Kahn's algorithm
  local wave=1
  local done_count=0
  while (( done_count < n )); do
    local -a current=()
    for ((i=0; i<n; i++)); do
      if [[ "${INDEG[i]}" -eq 0 ]]; then current+=("$i"); fi
    done
    if [[ ${#current[@]} -eq 0 ]]; then
      # cycle — 남은 인덱스 보고
      local -a cyc=()
      for ((i=0; i<n; i++)); do
        [[ "${INDEG[i]}" -gt 0 ]] && cyc+=("${SPECS[i]}")
      done
      echo "CYCLE:${cyc[*]}" >&2
      return 2
    fi
    local idx
    for idx in "${current[@]}"; do
      printf 'wave=%d\t%s\n' "$wave" "${SPECS[idx]}"
      INDEG[idx]=-1
      done_count=$((done_count+1))
      # 영향받는 노드 indeg 감소. bash 3.2 set -u 호환: 빈 배열 가드.
      local e a b
      for e in "${EDGES[@]+"${EDGES[@]}"}"; do
        a="${e%,*}"; b="${e#*,}"
        if [[ "$a" -eq "$idx" ]]; then INDEG[b]=$((INDEG[b]-1)); fi
      done
    done
    wave=$((wave+1))
  done
  return 0
}

# ----- subcommand: start -----

cmd_start() {
  require_git_root
  require_yq
  local resume=""
  local max_parallel=0
  local -a inputs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --resume) resume="$2"; shift 2 ;;
      --max-parallel) max_parallel="$2"; shift 2 ;;
      --) shift; while [[ $# -gt 0 ]]; do inputs+=("$1"); shift; done ;;
      -*) die "알 수 없는 옵션: $1" ;;
      *) inputs+=("$1"); shift ;;
    esac
  done

  local rd specs_abs=()
  if [[ -n "$resume" ]]; then
    rd="$(run_dir "$resume")"
    [[ -d "$rd" ]] || die "run-id 없음: $resume"
    # 기존 manifest 로 입력 복원. 호출자 명시 inputs 가 있으면 무시 (resume 일관성).
    while IFS= read -r p; do specs_abs+=("$p"); done < "$rd/MANIFEST.txt"
    log_event "$rd" "resume start"
  else
    [[ ${#inputs[@]} -ge 1 ]] || die "사용: $0 start <spec...> [--max-parallel N] [--resume <run-id>]"
    # 입력 SPEC 검증
    local p ap
    for p in "${inputs[@]}"; do
      [[ -f "$p" ]] || die "SPEC 파일을 찾을 수 없음: $p"
      [[ -r "$p" ]] || die "SPEC 파일 읽기 불가: $p"
      ap="$(abspath "$p")"
      specs_abs+=("$ap")
    done
    # run-id 계산 — 타임스탬프 + 입력 sha7.
    local ts h rid
    ts="$(date -u +%Y%m%dT%H%M%S)"
    h="$(hash7 "${specs_abs[@]}")"
    rid="${ts}-${h}"
    ensure_runs_dir
    rd="$(run_dir "$rid")"
    mkdir -p "$rd"
    write_manifest "$rd" "${specs_abs[@]}"
    log_event "$rd" "fresh start specs=${#specs_abs[@]}"
    # DAG 구성 + WAVES.txt 기록. cycle 시 abort + run dir 삭제.
    local waves_out
    if ! waves_out="$(build_dag "${specs_abs[@]}" 2>&1)"; then
      local cyc
      cyc=$(echo "$waves_out" | grep '^CYCLE:' | sed 's/^CYCLE://')
      rm -rf "$rd"
      die "depends_on cycle 감지 — 구성 요소: $cyc"
    fi
    printf '%s\n' "$waves_out" > "$rd/WAVES.txt"
    # 초기 상태 = pending
    local s
    for s in "${specs_abs[@]}"; do set_state "$rd" "$s" "pending"; done
  fi

  # wave 순회 — wave 별 SPEC 들 병렬 시작, wait, 결과 판정.
  local current_wave=1 max_wave
  max_wave=$(awk -F'[=\t]' '{print $2}' "$rd/WAVES.txt" | sort -n | tail -1)
  local overall_rc=0
  while (( current_wave <= max_wave )); do
    local -a wave_specs=()
    local line w sp
    while IFS=$'\t' read -r w sp; do
      [[ "$w" == "wave=$current_wave" ]] && wave_specs+=("$sp")
    done < "$rd/WAVES.txt"

    local -a launch_specs=()
    for sp in "${wave_specs[@]}"; do
      local st; st="$(get_state "$rd" "$sp")"
      if [[ "$st" == "done" ]]; then
        log_event "$rd" "wave=$current_wave skip-done $(spec_slug "$sp")"
        continue
      fi
      launch_specs+=("$sp")
    done

    log_event "$rd" "wave=$current_wave start specs=${#launch_specs[@]}"

    # 병렬 시작 (선택적 동시성 상한).
    local -a pids=()
    local -a started_specs=()
    for sp in "${launch_specs[@]}"; do
      if (( max_parallel > 0 )); then
        while (( $(jobs -rp 2>/dev/null | wc -l | tr -d ' ') >= max_parallel )); do
          sleep "${POLL_SECONDS:-1}"
        done
      fi
      set_state "$rd" "$sp" "running"
      local pid; pid="$(loop_start_bg "$sp")"
      pids+=("$pid")
      started_specs+=("$sp")
      log_event "$rd" "wave=$current_wave launch $(spec_slug "$sp") pid=$pid"
    done

    # 같은 wave 의 모든 백그라운드 loop 끝날 때까지 대기.
    # WAVE_TIMEOUT_SECONDS 초과 시 미종료 PID 들을 SIGTERM → SIGKILL 으로 정리하고
    # overall_rc=2 로 break 한다. (단순 `wait` 는 hung child 가 있을 때 영구 정지.)
    local wave_start now elapsed remaining_pids=0 wave_timed_out=0
    wave_start=$(date +%s)
    if (( ${#pids[@]} > 0 )); then
      while :; do
        remaining_pids=0
        local pid
        for pid in "${pids[@]}"; do
          if kill -0 "$pid" 2>/dev/null; then remaining_pids=$((remaining_pids+1)); fi
        done
        if (( remaining_pids == 0 )); then break; fi
        now=$(date +%s); elapsed=$((now - wave_start))
        if (( elapsed >= WAVE_TIMEOUT_SECONDS )); then
          wave_timed_out=1
          log_event "$rd" "wave=$current_wave timeout elapsed=${elapsed}s cap=${WAVE_TIMEOUT_SECONDS}s remaining=${remaining_pids}"
          for pid in "${pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && kill_tree "$pid" TERM
          done
          sleep 2
          for pid in "${pids[@]}"; do
            kill -0 "$pid" 2>/dev/null && kill_tree "$pid" KILL
          done
          for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
          break
        fi
        sleep "${POLL_SECONDS:-1}"
      done
    fi

    # 결과 판정 — 자율 실행기 공개 인터페이스로 child 별 종료 상태 확인.
    # timeout 으로 정리된 wave 라도 timeout 전에 이미 done 인 child 는 done 보존.
    # 미종료(pending/running/unknown) 만 timeout-failed 로 마킹.
    local wave_failed=0
    for sp in "${started_specs[@]}"; do
      local term; term="$(child_terminal_state "$sp")"
      case "$term" in
        done)
          set_state "$rd" "$sp" "done"
          log_event "$rd" "wave=$current_wave done $(spec_slug "$sp")"
          ;;
        failed)
          set_state "$rd" "$sp" "failed"; wave_failed=1
          log_event "$rd" "wave=$current_wave failed $(spec_slug "$sp")"
          ;;
        *)
          set_state "$rd" "$sp" "failed"; wave_failed=1
          if (( wave_timed_out == 1 )); then
            log_event "$rd" "wave=$current_wave timeout-failed $(spec_slug "$sp") state=$term"
          else
            log_event "$rd" "wave=$current_wave unknown-terminal $(spec_slug "$sp") state=$term"
          fi
          ;;
      esac
    done

    if (( wave_timed_out == 1 )); then
      log_event "$rd" "wave=$current_wave fail (timeout) — 다음 wave 진입 차단"
      overall_rc=2
      break
    fi

    if (( wave_failed == 1 )); then
      log_event "$rd" "wave=$current_wave fail — 다음 wave 진입 차단"
      overall_rc=1
      break
    fi

    current_wave=$((current_wave+1))
  done

  echo "run-id: $(basename "$rd")"
  return "$overall_rc"
}

# ----- subcommand: list -----

cmd_list() {
  require_git_root
  if [[ ! -d "$RUNS_DIR" ]] || [[ -z "$(ls "$RUNS_DIR" 2>/dev/null)" ]]; then
    echo "(no runs yet — 새 run: $0 start <spec...>)"
    return 0
  fi
  printf "%-32s %-6s %-6s %-6s %-6s %s\n" "RUN-ID" "SPECS" "DONE" "FAIL" "WAVES" "STARTED"
  local rd rid waves specs done_n fail_n started
  for rd in "$RUNS_DIR"/*/; do
    [[ -d "$rd" ]] || continue
    rid="$(basename "$rd")"
    specs=$(wc -l < "$rd/MANIFEST.txt" 2>/dev/null | tr -d ' ' || echo 0)
    waves=$(awk -F'[=\t]' '{print $2}' "$rd/WAVES.txt" 2>/dev/null | sort -n | tail -1)
    [[ -z "$waves" ]] && waves=0
    done_n=$(grep -lE '^done$' "$rd"/state.* 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    fail_n=$(grep -lE '^failed$' "$rd"/state.* 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    started=$(head -1 "$rd/LOG.md" 2>/dev/null | cut -c2-21 || echo "-")
    printf "%-32s %-6s %-6s %-6s %-6s %s\n" "$rid" "$specs" "$done_n" "$fail_n" "$waves" "$started"
  done
}

# ----- subcommand: status -----

cmd_status() {
  local rid="${1:-}"
  [[ -z "$rid" ]] && die "사용: $0 status <run-id>"
  require_git_root
  require_yq
  local rd; rd="$(run_dir "$rid")"
  [[ -d "$rd" ]] || die "run-id 없음: $rid"
  echo "run-id: $rid"
  echo "path:   $rd"
  echo ""
  printf "%-6s %-10s %-9s %s\n" "WAVE" "STATE" "LOOP" "SPEC"
  printf "%-6s %-10s %-9s %s\n" "----" "------" "----" "----"
  local w sp st loopst
  while IFS=$'\t' read -r w sp; do
    w="${w#wave=}"
    st="$(get_state "$rd" "$sp")"
    loopst="$(loop_status_state "$sp" 2>/dev/null || echo "-")"
    [[ -z "$loopst" ]] && loopst="-"
    printf "wave=%-2s %-10s %-9s %s\n" "$w" "$st" "$loopst" "$sp"
  done < "$rd/WAVES.txt"
}

# ----- subcommand: stop -----

cmd_stop() {
  local rid="${1:-}"
  [[ -z "$rid" ]] && die "사용: $0 stop <run-id>"
  require_git_root
  require_yq
  local rd; rd="$(run_dir "$rid")"
  [[ -d "$rd" ]] || die "run-id 없음: $rid"
  local any=0 sp
  while IFS= read -r sp; do
    local st loopst
    st="$(get_state "$rd" "$sp")"
    loopst="$(loop_status_state "$sp" 2>/dev/null || echo "")"
    if [[ "$st" == "running" ]] || [[ "$loopst" == "running" ]]; then
      loop_stop "$sp"
      set_state "$rd" "$sp" "failed"
      log_event "$rd" "stop $(spec_slug "$sp")"
      any=1
    fi
  done < "$rd/MANIFEST.txt"
  if (( any == 0 )); then echo "활성 child 없음"; fi
}

# ----- subcommand: watch -----

cmd_watch() {
  local rid="${1:-}"
  [[ -z "$rid" ]] && die "사용: $0 watch <run-id>"
  require_git_root
  require_yq
  local rd; rd="$(run_dir "$rid")"
  [[ -d "$rd" ]] || die "run-id 없음: $rid"
  local start; start=$(date +%s)
  while true; do
    local all_terminal=1 any_fail=0 sp st
    while IFS= read -r sp; do
      st="$(get_state "$rd" "$sp")"
      case "$st" in
        done)   ;;
        failed) any_fail=1 ;;
        *)
          # 미완 — loop 공개 IF 로 현 상태 재확인.
          local term; term="$(child_terminal_state "$sp")"
          case "$term" in
            done)   set_state "$rd" "$sp" "done" ;;
            failed) set_state "$rd" "$sp" "failed"; any_fail=1 ;;
            *)      all_terminal=0 ;;
          esac
          ;;
      esac
    done < "$rd/MANIFEST.txt"
    if (( all_terminal == 1 )); then
      if (( any_fail == 1 )); then return 1; fi
      return 0
    fi
    local now; now=$(date +%s)
    if (( now - start >= WAVE_TIMEOUT_SECONDS )); then return 2; fi
    sleep "${POLL_SECONDS:-1}"
  done
}

# ----- 사용법 -----

usage() {
  cat >&2 <<'EOF'
usage: dispatch.sh <subcommand> [args]

Subcommands:
  start <spec...> [--max-parallel N] [--resume <run-id>]
        1 개 이상의 SPEC 파일 경로를 받아 depends_on 으로 DAG 를 만들고
        wave 단위로 loop driver 에 위임. --resume 이면 기존 run 의
        미완 child 만 재실행.
  list
        모든 run-id 와 진행 요약.
  status <run-id>
        run-id 단위 per-SPEC wave/state.
  stop <run-id>
        진행 중 child loop 들을 정지 (loop driver 에 위임).
  watch <run-id>
        per-SPEC 상태를 폴링하며 모든 child 가 terminal 에 도달할 때까지
        대기. exit 0=전부 done, 1=하나라도 failed, 2=timeout.

환경 변수:
  LOOP_CMD, DISPATCH_POLL_SECONDS, DISPATCH_WAVE_TIMEOUT_SECONDS
EOF
  exit 1
}

# ----- 디스패처 -----

if [[ $# -lt 1 ]]; then usage; fi
SUB="$1"; shift
case "$SUB" in
  start)  cmd_start  "$@" ;;
  list)   cmd_list  ;;
  status) cmd_status "$@" ;;
  stop)   cmd_stop   "$@" ;;
  watch)  cmd_watch  "$@" ;;
  -h|--help|help) usage ;;
  *) echo "알 수 없는 subcommand: $SUB" >&2; usage ;;
esac
