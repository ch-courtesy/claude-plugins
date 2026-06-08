#!/usr/bin/env bash
# dispatch.sh — autopilot:dispatch 결정적 오케스트레이션 헬퍼 (모델 주도)
#
# dispatch 는 준비된 SPEC마다 서브에이전트를 1개 띄우는 **모델 주도** 오케스트레이터다. 통합·
# 리뷰·머지는 서브에이전트가 SPEC당 한 컨텍스트에서 소유한다(계약: references/spec-subagent.md).
# 이 셸 스크립트는 그 오케스트레이션의 **결정적 부분만** 제공하는 헬퍼다 — 오케스트레이션 주체가
# 아니다(서브에이전트 spawn 은 Agent 도구를 쓰는 모델이 수행, bash 무인 드레인 루프 아님).
#
# 책임(결정적):
#   - start: SPEC 입력 검증·frontmatter depends_on 으로 DAG 구성·WAVES.txt(진단)·초기 pending
#            상태·run 전역 마커(서브모드 INTEGRATE / 대상 브랜치 TARGET_BRANCH / MAX_PARALLEL /
#            드라이버 DRIVER)를 만드는 **셋업 전용**. 스스로 spawn·드레인하지 않는다.
#   - ready: 지금 서브에이전트를 띄울 준비된 SPEC(모든 dep done & pending & 동시성 상한 이내)을
#            출력(skip 전파 적용). 모델이 각 SPEC 에 서브에이전트 1개를 spawn.
#   - mark:  SPEC 상태 전이(running=spawn 직전 / done=서브에이전트 머지 보고=의존자 해제 /
#            failed=비완료 보고 → 이행적 의존자 skipped 전파). running 에 --task-id 를
#            넘기면 백그라운드 드라이버의 task-id 를 run-dir 에 기록(stop 위임 경로).
#   - list / status / stop / watch / driver / --resume 운영 인터페이스(읽기 위주). done 의
#     의미는 "대상 브랜치에 머지됨"이며, 의존자 해제는 머지(done) 뒤로 미뤄진다.
#
# **하지 않는 일**:
#   - 입력 SPEC 의 frontmatter 형식·내용 검증 (서브에이전트/loop 책임).
#   - 통합·리뷰·머지의 직접 수행(bash 드레인). 그것은 서브에이전트가 소유한다.
#   - 서브에이전트가 호출하는 loop·review 의 내부 신호 파일·worktree 열람(블랙박스 경계).
#   - 드라이버 자동 감지(모델·실행환경 판정): 드라이버 선택은 모델이 DRIVER 마커로 넘기고,
#     override 는 DISPATCH_DRIVER 환경 변수로 주입한다. bash 코드로는 probe 불가.
#
# 모델 루프(스킬이 구동): start → 반복{ ready → 각 SPEC: mark running [--task-id <id>] +
#   서브에이전트 spawn → 보고 시 mark done(머지)·mark failed(에스컬레이션) } →
#   ready 가 비고 running 없을 때까지.
#
# 사용:
#   bash dispatch.sh start <spec...> [--max-parallel N] [--resume <run-id>] [--target-branch <b>]
#   bash dispatch.sh ready <run-id> [--max-parallel N]
#   bash dispatch.sh mark <run-id> <running|done|failed> <spec> [--task-id <id>]
#   bash dispatch.sh list | status <run-id> | stop <run-id> | watch <run-id>
#   bash dispatch.sh driver <run-id>
#
# 환경 변수:
#   DISPATCH_POLL_SECONDS          watch 폴링 간격 (기본 2)
#   DISPATCH_WAVE_TIMEOUT_SECONDS  watch 최대 대기 (기본 7200 = 2 시간)
#   DISPATCH_DRIVER                드라이버 override (strong-parallel|background|foreground-batch).
#                                  미설정이면 모델이 DRIVER 마커로 기록한 값을 쓴다.
#   FORGE_BIN DEFAULT_BRANCH  서브모드·대상 브랜치 판정(주입 가능, mock 검증).
#
# 드라이버 abstraction (모델 주도, 결정적 코어 공유):
#   strong-parallel    — dynamic Workflow: promise-per-node DAG, SPEC당 워커 1개.
#                        의존자가 충족되는 즉시 무관한 형제를 기다리지 않고 시작(스트리밍 준비도).
#   background         — 워커를 비동기 run_in_background 로 spawn, 완료마다 개별 재호출(reconcile).
#                        mark running --task-id 로 task-id 기록; stop 시 TaskStop 위임.
#   foreground-batch   — 한 턴에 ready 목록 동시 시작 → 배리어 → 준비도 재평가. 안전 강등 종착점.
#
#   자동 감지 순서: strong-parallel 가용이면 선택, 아니면 background 가능 여부 판정, 아니면
#     foreground-batch 로 강등. override: DISPATCH_DRIVER 환경 변수.
#   강등 사슬: strong-parallel → background → foreground-batch.
#   어느 드라이버든 결정적 코어(DAG 준비도·상태 전이·skip 전파·머지/리뷰 게이트)는 공유한다.
#   드라이버 선택은 run-dir DRIVER 마커로 영속(--resume sticky).
#
# bash 3.2 호환 (assoc array 사용 안 함).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLL_SECONDS="${DISPATCH_POLL_SECONDS:-2}"
WAVE_TIMEOUT_SECONDS="${DISPATCH_WAVE_TIMEOUT_SECONDS:-7200}"

# ----- 서브모드·대상 브랜치 (모델 주도 — 서브에이전트가 리뷰·머지를 소유) -----
INTEGRATE_SUBMODE=""
TARGET_BRANCH=""
FORGE_BIN="${FORGE_BIN:-gh}"

# ----- 드라이버 선택 (모델 주도, 결정적 코어 공유) -----
DISPATCH_DRIVER="${DISPATCH_DRIVER:-}"

# drv_valid <driver> — 유효한 드라이버 이름이면 0, 아니면 1.
drv_valid() {
  case "${1:-}" in
    strong-parallel|background|foreground-batch) return 0 ;;
    *) return 1 ;;
  esac
}

# drv_choose <current_marker> — DISPATCH_DRIVER override 있으면 그것, 아니면
#   current_marker(마커에 저장된 값), 둘 다 없거나 invalid 면 foreground-batch.
drv_choose() {
  local current="${1:-}"
  local chosen=""
  if [[ -n "$DISPATCH_DRIVER" ]]; then
    if drv_valid "$DISPATCH_DRIVER"; then chosen="$DISPATCH_DRIVER"
    else
      echo "WARN: DISPATCH_DRIVER='$DISPATCH_DRIVER' 은 유효하지 않은 드라이버 — foreground-batch 로 강등" >&2
      chosen="foreground-batch"
    fi
  elif [[ -n "$current" ]] && drv_valid "$current"; then
    chosen="$current"
  else
    chosen="foreground-batch"
  fi
  printf '%s\n' "$chosen"
}

forge_backend_available() {
  command -v "${FORGE_BIN%% *}" >/dev/null 2>&1
}

# ----- helpers -----

die() { echo "ERROR: $*" >&2; exit 1; }

require_yq() {
  command -v yq >/dev/null 2>&1 \
    || die "'yq' 가 필요합니다 — SPEC depends_on 파싱(DAG 구성)에 사용됩니다."
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

require_git_root() {
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  RUNS_DIR="$PROJECT_ROOT/.dispatch/runs"
}

abspath() {
  local p="$1"
  (cd "$(dirname "$p")" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$(basename "$p")")
}

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

resolve_dep() {
  local from="$1"; local dep="$2"
  local from_dir; from_dir="$(dirname "$from")"
  if [[ "$dep" = /* ]] && [[ -f "$dep" ]]; then echo "$dep"; return; fi
  if [[ -n "${PROJECT_ROOT:-}" ]] && [[ -f "$PROJECT_ROOT/$dep" ]]; then
    abspath "$PROJECT_ROOT/$dep"; return
  fi
  if [[ -f "$from_dir/$dep" ]]; then abspath "$from_dir/$dep"; return; fi
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

write_waves() {
  local rd="$1"
  cat > "$rd/WAVES.txt"
}

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

# ----- task-id IO (백그라운드 드라이버용) -----
# mark running --task-id <id> 로 기록, stop 이 TaskStop 위임에 사용한다.

taskid_path() {
  local rd="$1"; local spec="$2"
  echo "$rd/taskid.$(spec_slug "$spec")-$(hash7 "$spec")"
}

set_taskid() {
  local rd="$1" spec="$2" id="$3"
  [[ -n "$id" ]] || return 0
  mkdir -p "$rd"
  printf '%s\n' "$id" > "$(taskid_path "$rd" "$spec")"
}

get_taskid() {
  local f; f="$(taskid_path "$1" "$2")"
  [[ -f "$f" ]] && cat "$f" || echo ""
}

del_taskid() {
  local f; f="$(taskid_path "$1" "$2")"
  rm -f "$f" 2>/dev/null || true
}

# ----- DAG / wave 구성 -----

build_dag() {
  local -a SPECS=()
  local s
  for s in "$@"; do SPECS+=("$s"); done
  local n=${#SPECS[@]}
  local -a INDEG=()
  local -a EDGES=()
  local i j
  for ((i=0; i<n; i++)); do INDEG[i]=0; done

  local dep dep_path
  for ((i=0; i<n; i++)); do
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      dep_path="$(resolve_dep "${SPECS[i]}" "$dep")"
      if [[ -z "$dep_path" ]]; then
        echo "WARN: ${SPECS[i]}: depends_on '$dep' 해석 실패 (무시)" >&2
        continue
      fi
      local found=-1
      for ((j=0; j<n; j++)); do
        if [[ "${SPECS[j]}" == "$dep_path" ]]; then found=$j; break; fi
      done
      if [[ $found -lt 0 ]]; then
        continue
      fi
      EDGES+=("$found,$i")
      INDEG[i]=$((INDEG[i]+1))
    done < <(extract_depends_on "${SPECS[i]}")
  done

  local wave=1
  local done_count=0
  while (( done_count < n )); do
    local -a current=()
    for ((i=0; i<n; i++)); do
      if [[ "${INDEG[i]}" -eq 0 ]]; then current+=("$i"); fi
    done
    if [[ ${#current[@]} -eq 0 ]]; then
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

compute_dep_idx() {
  local -a SP=()
  local s
  for s in "$@"; do SP+=("$s"); done
  local n=${#SP[@]} i j dep dep_path
  for ((i=0; i<n; i++)); do DEP_IDX[i]=""; done
  for ((i=0; i<n; i++)); do
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      dep_path="$(resolve_dep "${SP[i]}" "$dep")"
      [[ -z "$dep_path" ]] && continue
      for ((j=0; j<n; j++)); do
        if [[ "${SP[j]}" == "$dep_path" ]]; then
          DEP_IDX[i]="${DEP_IDX[i]} $j"; break
        fi
      done
    done < <(extract_depends_on "${SP[i]}")
  done
}

propagate_skips() {
  local rd="$1"; shift
  local -a SP=("$@"); local n=${#SP[@]}
  local changed=1 i d ds
  while (( changed == 1 )); do
    changed=0
    for ((i=0; i<n; i++)); do
      [[ "$(get_state "$rd" "${SP[i]}")" == "pending" ]] || continue
      for d in ${DEP_IDX[i]}; do
        ds="$(get_state "$rd" "${SP[d]}")"
        if [[ "$ds" == "failed" || "$ds" == "skipped" ]]; then
          set_state "$rd" "${SP[i]}" "skipped"
          log_event "$rd" "skip $(spec_slug "${SP[i]}") (dep $(spec_slug "${SP[d]}") $ds)"
          changed=1; break
        fi
      done
    done
  done
}

# ----- 결정적 오케스트레이션 헬퍼(모델 주도) -----

load_run() {
  local rid="$1"
  [[ -n "$rid" ]] || die "run-id 필요"
  RD="$(run_dir "$rid")"
  [[ -d "$RD" ]] || die "run-id 없음: $rid"
  [[ -f "$RD/MANIFEST.txt" ]] || die "MANIFEST 없음: $rid"
  SP=()
  local p
  while IFS= read -r p; do [[ -n "$p" ]] && SP+=("$p"); done < "$RD/MANIFEST.txt"
  DEP_IDX=()
  compute_dep_idx "${SP[@]}"
}

cmd_ready() {
  require_git_root
  local rid="" max_parallel=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-parallel) max_parallel="$2"; shift 2 ;;
      -*) die "알 수 없는 옵션: $1" ;;
      *) rid="$1"; shift ;;
    esac
  done
  local RD; local -a SP=() DEP_IDX=()
  load_run "$rid"
  if (( max_parallel == 0 )) && [[ -f "$RD/MAX_PARALLEL" ]]; then
    max_parallel="$(cat "$RD/MAX_PARALLEL" 2>/dev/null || echo 0)"
    [[ "$max_parallel" =~ ^[0-9]+$ ]] || max_parallel=0
  fi
  propagate_skips "$RD" "${SP[@]}"
  local n=${#SP[@]} i d ready running_count=0
  for ((i=0; i<n; i++)); do
    [[ "$(get_state "$RD" "${SP[i]}")" == "running" ]] && running_count=$((running_count+1))
  done
  for ((i=0; i<n; i++)); do
    [[ "$(get_state "$RD" "${SP[i]}")" == "pending" ]] || continue
    ready=1
    for d in ${DEP_IDX[i]}; do
      [[ "$(get_state "$RD" "${SP[d]}")" == "done" ]] || { ready=0; break; }
    done
    (( ready == 1 )) || continue
    if (( max_parallel > 0 )) && (( running_count >= max_parallel )); then continue; fi
    printf '%s\n' "${SP[i]}"
    running_count=$((running_count+1))
  done
}

# cmd_mark <run-id> <running|done|failed> <spec> [--task-id <id>]
cmd_mark() {
  require_git_root
  local rid="${1:-}" st="${2:-}" spec="${3:-}" task_id=""
  shift 3 2>/dev/null || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id) task_id="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$rid" && -n "$st" && -n "$spec" ]] || die "사용: $0 mark <run-id> <running|done|failed> <spec> [--task-id <id>]"
  case "$st" in running|done|failed) ;; *) die "알 수 없는 상태: $st (running|done|failed)" ;; esac
  local RD; local -a SP=() DEP_IDX=()
  load_run "$rid"
  local ap; ap="$(abspath "$spec")"
  set_state "$RD" "$ap" "$st"
  log_event "$RD" "mark $(spec_slug "$ap") $st${task_id:+ task-id=$task_id}"
  if [[ "$st" == "running" ]]; then
    set_taskid "$RD" "$ap" "$task_id"
  elif [[ "$st" == "done" || "$st" == "failed" ]]; then
    del_taskid "$RD" "$ap"
    if [[ "$st" == "failed" ]]; then
      propagate_skips "$RD" "${SP[@]}"
    fi
  fi
}

# ----- subcommand: start -----

cmd_start() {
  require_git_root
  require_yq
  local resume=""
  local max_parallel=0
  local target_branch_opt=""
  local -a inputs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --resume) resume="$2"; shift 2 ;;
      --max-parallel) max_parallel="$2"; shift 2 ;;
      --target-branch) target_branch_opt="$2"; shift 2 ;;
      --integrate|--no-integrate) shift ;;
      --) shift; while [[ $# -gt 0 ]]; do inputs+=("$1"); shift; done ;;
      -*) die "알 수 없는 옵션: $1" ;;
      *) inputs+=("$1"); shift ;;
    esac
  done

  local rd specs_abs=()
  if [[ -n "$resume" ]]; then
    rd="$(run_dir "$resume")"
    [[ -d "$rd" ]] || die "run-id 없음: $resume"
    while IFS= read -r p; do specs_abs+=("$p"); done < "$rd/MANIFEST.txt"
    log_event "$rd" "resume start"
  else
    [[ ${#inputs[@]} -ge 1 ]] || die "사용: $0 start <spec...> [--max-parallel N] [--resume <run-id>]"
    local p ap
    for p in "${inputs[@]}"; do
      [[ -f "$p" ]] || die "SPEC 파일을 찾을 수 없음: $p"
      [[ -r "$p" ]] || die "SPEC 파일 읽기 불가: $p"
      ap="$(abspath "$p")"
      specs_abs+=("$ap")
    done
    local ts h rid
    ts="$(date -u +%Y%m%dT%H%M%S)"
    h="$(hash7 "${specs_abs[@]}")"
    rid="${ts}-${h}"
    ensure_runs_dir
    rd="$(run_dir "$rid")"
    mkdir -p "$rd"
    write_manifest "$rd" "${specs_abs[@]}"
    log_event "$rd" "fresh start specs=${#specs_abs[@]}"
    local waves_out
    if ! waves_out="$(build_dag "${specs_abs[@]}" 2>&1)"; then
      local cyc
      cyc=$(echo "$waves_out" | grep '^CYCLE:' | sed 's/^CYCLE://')
      rm -rf "$rd"
      die "depends_on cycle 감지 — 구성 요소: $cyc"
    fi
    printf '%s\n' "$waves_out" > "$rd/WAVES.txt"
    local s
    for s in "${specs_abs[@]}"; do set_state "$rd" "$s" "pending"; done
  fi

  # ----- 통합 서브모드 판정 -----
  if [[ -f "$rd/INTEGRATE" ]]; then
    INTEGRATE_SUBMODE="$(cat "$rd/INTEGRATE" 2>/dev/null || true)"
  fi
  if [[ -z "$INTEGRATE_SUBMODE" ]]; then
    if forge_backend_available; then INTEGRATE_SUBMODE=forge; else INTEGRATE_SUBMODE=direct; fi
  fi
  printf '%s\n' "$INTEGRATE_SUBMODE" > "$rd/INTEGRATE"

  # ----- 대상 브랜치 판정 -----
  if [[ -f "$rd/TARGET_BRANCH" ]]; then
    TARGET_BRANCH="$(cat "$rd/TARGET_BRANCH" 2>/dev/null || true)"
  elif [[ -n "$target_branch_opt" ]]; then
    TARGET_BRANCH="$target_branch_opt"
  else
    TARGET_BRANCH="${DEFAULT_BRANCH:-main}"
  fi
  [[ -n "$TARGET_BRANCH" ]] || TARGET_BRANCH="${DEFAULT_BRANCH:-main}"
  printf '%s\n' "$TARGET_BRANCH" > "$rd/TARGET_BRANCH"
  export DEFAULT_BRANCH="$TARGET_BRANCH"
  log_event "$rd" "integration submode=$INTEGRATE_SUBMODE target-branch=$TARGET_BRANCH (done=머지됨)"

  # ----- max-parallel 마커 -----
  [[ -f "$rd/MAX_PARALLEL" ]] || printf '%s\n' "$max_parallel" > "$rd/MAX_PARALLEL"

  # ----- 드라이버 선택 -----
  local current_driver=""
  [[ -f "$rd/DRIVER" ]] && current_driver="$(cat "$rd/DRIVER" 2>/dev/null || true)"
  local chosen_driver; chosen_driver="$(drv_choose "$current_driver")"
  printf '%s\n' "$chosen_driver" > "$rd/DRIVER"

  local n=${#specs_abs[@]} i
  if [[ -n "$resume" ]]; then
    for ((i=0; i<n; i++)); do
      [[ "$(get_state "$rd" "${specs_abs[i]}")" == "done" ]] \
        || set_state "$rd" "${specs_abs[i]}" "pending"
    done
  fi
  log_event "$rd" "setup done specs=$n submode=$INTEGRATE_SUBMODE target-branch=$TARGET_BRANCH max_parallel=$(cat "$rd/MAX_PARALLEL" 2>/dev/null) driver=$chosen_driver (모델 주도; done=머지됨)"
  echo "run-id: $(basename "$rd")"
  echo "driver: $chosen_driver"
  return 0
}

# ----- subcommand: driver -----

cmd_driver() {
  local rid="${1:-}"
  [[ -z "$rid" ]] && die "사용: $0 driver <run-id>"
  require_git_root
  local rd; rd="$(run_dir "$rid")"
  [[ -d "$rd" ]] || die "run-id 없음: $rid"
  local drv=""
  [[ -f "$rd/DRIVER" ]] && drv="$(cat "$rd/DRIVER" 2>/dev/null || true)"
  [[ -z "$drv" ]] && drv="(unset — foreground-batch 기본값)"
  echo "run-id: $rid"
  echo "driver: $drv"
}

# ----- subcommand: list -----

cmd_list() {
  require_git_root
  if [[ ! -d "$RUNS_DIR" ]] || [[ -z "$(ls "$RUNS_DIR" 2>/dev/null)" ]]; then
    echo "(no runs yet — 새 run: $0 start <spec...>)"
    return 0
  fi
  printf "%-32s %-6s %-6s %-6s %-6s %-20s %s\n" "RUN-ID" "SPECS" "DONE" "FAIL" "WAVES" "DRIVER" "STARTED"
  local rd rid waves specs done_n fail_n started drv
  for rd in "$RUNS_DIR"/*/; do
    [[ -d "$rd" ]] || continue
    rid="$(basename "$rd")"
    specs=$(wc -l < "$rd/MANIFEST.txt" 2>/dev/null | tr -d ' ' || echo 0)
    waves=$(awk -F'[=\t]' '{print $2}' "$rd/WAVES.txt" 2>/dev/null | sort -n | tail -1)
    [[ -z "$waves" ]] && waves=0
    done_n=$(grep -lE '^done$' "$rd"/state.* 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    fail_n=$(grep -lE '^failed$' "$rd"/state.* 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    drv=$(cat "$rd/DRIVER" 2>/dev/null | tr -d ' ' || echo "-")
    [[ -z "$drv" ]] && drv="-"
    started=$(head -1 "$rd/LOG.md" 2>/dev/null | cut -c2-21 || echo "-")
    printf "%-32s %-6s %-6s %-6s %-6s %-20s %s\n" "$rid" "$specs" "$done_n" "$fail_n" "$waves" "$drv" "$started"
  done
}

# ----- subcommand: status -----

cmd_status() {
  local rid="${1:-}"
  [[ -z "$rid" ]] && die "사용: $0 status <run-id>"
  require_git_root
  local rd; rd="$(run_dir "$rid")"
  [[ -d "$rd" ]] || die "run-id 없음: $rid"
  echo "run-id: $rid"
  echo "path:   $rd"
  local drv=""
  [[ -f "$rd/DRIVER" ]] && drv="$(cat "$rd/DRIVER" 2>/dev/null || true)"
  [[ -n "$drv" ]] && echo "driver: $drv"
  echo ""
  printf "%-6s %-10s %s\n" "WAVE" "STATE" "SPEC"
  printf "%-6s %-10s %s\n" "----" "------" "----"
  local w sp st
  while IFS=$'\t' read -r w sp; do
    w="${w#wave=}"
    st="$(get_state "$rd" "$sp")"
    printf "wave=%-2s %-10s %s\n" "$w" "$st" "$sp"
  done < "$rd/WAVES.txt"
}

# ----- subcommand: stop -----

cmd_stop() {
  local rid="${1:-}"
  [[ -z "$rid" ]] && die "사용: $0 stop <run-id>"
  require_git_root
  local RD; local -a SP=() DEP_IDX=()
  load_run "$rid"
  local any=0 i st tid
  for ((i=0; i<${#SP[@]}; i++)); do
    st="$(get_state "$RD" "${SP[i]}")"
    if [[ "$st" == "running" ]]; then
      tid="$(get_taskid "$RD" "${SP[i]}")"
      [[ -n "$tid" ]] && echo "task-id: $tid ($(spec_slug "${SP[i]}"))"
      set_state "$RD" "${SP[i]}" "failed"
      del_taskid "$RD" "${SP[i]}"
      log_event "$RD" "stop $(spec_slug "${SP[i]}")${tid:+ task-id=$tid}"
      any=1
    fi
  done
  if (( any == 1 )); then
    propagate_skips "$RD" "${SP[@]}"
  else
    echo "활성(running) SPEC 없음"
  fi
}

# ----- subcommand: watch -----

cmd_watch() {
  local rid="${1:-}"
  [[ -z "$rid" ]] && die "사용: $0 watch <run-id>"
  require_git_root
  local rd; rd="$(run_dir "$rid")"
  [[ -d "$rd" ]] || die "run-id 없음: $rid"
  local start; start=$(date +%s)
  while true; do
    local all_terminal=1 any_fail=0 sp st
    while IFS= read -r sp; do
      st="$(get_state "$rd" "$sp")"
      case "$st" in
        done) ;;
        failed|skipped) any_fail=1 ;;
        *) all_terminal=0 ;;
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

# =====================================================================
# selftest — 결정적 오케스트레이션 검증(모델 주도). 실제 spawn·머지·PR 미수행.
# =====================================================================
cmd_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local DSP="$SCRIPT_DIR/dispatch.sh"

  local REPO="$TMP/repo"; mkdir -p "$REPO"
  ( cd "$REPO" && git init -q )
  printf -- '---\n---\n# Feature A\n' > "$REPO/feature-a.md"
  printf -- '---\ndepends_on: [feature-a]\n---\n# Feature B\n' > "$REPO/feature-b.md"
  printf -- '---\n---\n# Feature C\n' > "$REPO/feature-c.md"

  local fail=0
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  run_state() {
    local rd="$1" sp key; sp="$REPO/$2"
    key="$(spec_slug "$sp")-$(hash7 "$sp")"
    cat "$rd/state.$key" 2>/dev/null || echo "MISSING"
  }
  latest_run() { ls -1dt "$REPO"/.dispatch/runs/*/ 2>/dev/null | head -1 | sed 's:/$::'; }
  marker()  { cat "$1/INTEGRATE" 2>/dev/null; }
  tmarker() { cat "$1/TARGET_BRANCH" 2>/dev/null; }
  mpmarker(){ cat "$1/MAX_PARALLEL" 2>/dev/null; }
  drvmarker(){ cat "$1/DRIVER" 2>/dev/null; }
  start_rid() {
    ( cd "$REPO" && "$@" ) | sed -n 's/^run-id: //p'
  }
  start_drv() {
    ( cd "$REPO" && "$@" ) | sed -n 's/^driver: //p'
  }
  dsp() { env DISPATCH_POLL_SECONDS=0 DISPATCH_WAVE_TIMEOUT_SECONDS=120 "$@"; }
  rdy() { ( cd "$REPO" && dsp bash "$DSP" ready "$@" 2>/dev/null ); }
  mk() { ( cd "$REPO" && dsp bash "$DSP" mark "$@" ) >/dev/null 2>&1; }

  # ---- S1 ----
  rm -rf "$REPO/.dispatch"
  local rid1; rid1="$( start_rid dsp bash "$DSP" start feature-a.md feature-b.md )"
  local rd1; rd1="$(latest_run)"
  [[ -n "$rid1" && -d "$rd1" ]] && ok "S1 start: run-id·run-dir 생성" || bad "S1 start: run-id 생성 got=[$rid1]"
  [[ "$(run_state "$rd1" feature-a.md)" == "pending" ]] && ok "S1 start: A 셋업 직후 pending(미드라이브)" || bad "S1 start: A pending got=$(run_state "$rd1" feature-a.md)"
  [[ "$(run_state "$rd1" feature-b.md)" == "pending" ]] && ok "S1 start: B 셋업 직후 pending" || bad "S1 start: B pending got=$(run_state "$rd1" feature-b.md)"
  [[ -f "$rd1/MANIFEST.txt" && -f "$rd1/WAVES.txt" ]] && ok "S1 start: MANIFEST·WAVES 생성" || bad "S1 start: MANIFEST·WAVES 생성"
  [[ "$(grep -c . "$rd1/MANIFEST.txt")" == "2" ]] && ok "S1 start: MANIFEST 2 SPEC" || bad "S1 start: MANIFEST 2"
  [[ -f "$rd1/MAX_PARALLEL" ]] && ok "S1 start: MAX_PARALLEL 마커" || bad "S1 start: MAX_PARALLEL 마커"
  [[ -f "$rd1/DRIVER" ]] && ok "S1 start: DRIVER 마커 생성" || bad "S1 start: DRIVER 마커 생성"

  # ---- S2 ----
  rm -rf "$REPO/.dispatch"
  local rid2; rid2="$( start_rid dsp bash "$DSP" start feature-a.md feature-b.md )"
  local rd2; rd2="$(latest_run)"
  local r; r="$(rdy "$rid2")"
  printf '%s\n' "$r" | grep -q 'feature-a.md' && ok "S2 ready: A(무dep) 준비됨" || bad "S2 ready: A 준비됨 got=[$r]"
  printf '%s\n' "$r" | grep -q 'feature-b.md' && bad "S2 ready: B(dep A) 미준비여야" || ok "S2 ready: B 미준비(dep A pending)"
  mk "$rid2" running "$REPO/feature-a.md"
  r="$(rdy "$rid2")"
  printf '%s\n' "$r" | grep -q 'feature-a.md' && bad "S2 ready: running A 제외돼야(중복 spawn 방지)" || ok "S2 ready: running A 제외"
  mk "$rid2" done "$REPO/feature-a.md"
  r="$(rdy "$rid2")"
  printf '%s\n' "$r" | grep -q 'feature-b.md' && ok "S2 ready: A done(머지) 후 B 준비됨(의존자 해제)" || bad "S2 ready: A done 후 B 준비 got=[$r]"
  mk "$rid2" running "$REPO/feature-b.md"; mk "$rid2" done "$REPO/feature-b.md"
  [[ "$(run_state "$rd2" feature-a.md)" == "done" && "$(run_state "$rd2" feature-b.md)" == "done" ]] && ok "S2 모델 루프: 전부 done(머지)" || bad "S2 전부 done"
  r="$(rdy "$rid2")"
  [[ -z "$r" ]] && ok "S2 ready: 모두 terminal 이면 빈 출력(루프 종료)" || bad "S2 빈 ready got=[$r]"

  # ---- S3 ----
  rm -rf "$REPO/.dispatch"
  local rid3; rid3="$( start_rid dsp bash "$DSP" start feature-a.md feature-b.md feature-c.md )"
  local rd3; rd3="$(latest_run)"
  mk "$rid3" failed "$REPO/feature-a.md"
  [[ "$(run_state "$rd3" feature-b.md)" == "skipped" ]] && ok "S3 mark failed: B(dep A) 이행적 skipped" || bad "S3 B skipped got=$(run_state "$rd3" feature-b.md)"
  [[ "$(run_state "$rd3" feature-c.md)" == "pending" ]] && ok "S3 독립 C 는 pending(계속)" || bad "S3 C pending got=$(run_state "$rd3" feature-c.md)"
  r="$(rdy "$rid3")"
  printf '%s\n' "$r" | grep -q 'feature-c.md' && ok "S3 ready: 독립 C 는 준비됨(가지 격리)" || bad "S3 ready C got=[$r]"
  printf '%s\n' "$r" | grep -q 'feature-b.md' && bad "S3 ready: skipped B 는 미준비" || ok "S3 ready: skipped B 미준비"

  # ---- S4 ----
  rm -rf "$REPO/.dispatch"
  local rid4; rid4="$( start_rid dsp bash "$DSP" start --max-parallel 1 feature-a.md feature-c.md )"
  local rd4; rd4="$(latest_run)"
  [[ "$(mpmarker "$rd4")" == "1" ]] && ok "S4 MAX_PARALLEL 마커=1" || bad "S4 MAX_PARALLEL got=$(mpmarker "$rd4")"
  r="$(rdy "$rid4")"
  [[ "$(printf '%s\n' "$r" | grep -c 'feature-')" == "1" ]] && ok "S4 ready: 상한 1 → 1개만(마커 기본값 존중)" || bad "S4 ready 상한 got=[$r]"
  mk "$rid4" running "$(printf '%s\n' "$r" | head -1)"
  r="$(rdy "$rid4")"
  [[ "$(printf '%s\n' "$r" | grep -c 'feature-')" == "0" ]] && ok "S4 ready: 상한 도달 시 빈 출력" || bad "S4 ready 상한도달 got=[$r]"
  r="$( ( cd "$REPO" && dsp bash "$DSP" ready "$rid4" --max-parallel 2 2>/dev/null ) )"
  [[ "$(printf '%s\n' "$r" | grep -c 'feature-')" == "1" ]] && ok "S4 ready: 명시 상한 2 + running 1 → 1개" || bad "S4 명시 상한 got=[$r]"
  ( cd "$REPO" && dsp bash "$DSP" start --resume "$rid4" ) >/dev/null 2>&1 || true
  [[ "$(mpmarker "$rd4")" == "1" ]] && ok "S4 resume: MAX_PARALLEL sticky(마커 유지)" || bad "S4 resume sticky got=$(mpmarker "$rd4")"

  # ---- S5 ----
  rm -rf "$REPO/.dispatch"
  local ridm; ridm="$( start_rid dsp bash "$DSP" start feature-a.md )"
  local rdm; rdm="$(latest_run)"
  [[ "$(tmarker "$rdm")" == "main" ]] && ok "S5 기본 대상 브랜치=main 마커" || bad "S5 기본 대상=main got=$(tmarker "$rdm")"
  rm -rf "$REPO/.dispatch"
  local ridr; ridr="$( start_rid dsp env FORGE_BIN=__noforge__ bash "$DSP" start --target-branch release feature-a.md feature-b.md )"
  local rdr; rdr="$(latest_run)"
  [[ "$(tmarker "$rdr")" == "release" ]] && ok "S5 지정 대상 브랜치=release 마커" || bad "S5 대상=release got=$(tmarker "$rdr")"
  [[ "$(marker "$rdr")" == "direct" ]] && ok "S5 forge 백엔드 미가용(FORGE_BIN) → submode=direct" || bad "S5 submode=direct got=$(marker "$rdr")"
  local ridr2; ridr2="$(basename "$rdr")"
  ( cd "$REPO" && dsp env DEFAULT_BRANCH=main bash "$DSP" start --resume "$ridr2" ) >/dev/null 2>&1 || true
  [[ "$(tmarker "$rdr")" == "release" ]] && ok "S5 resume: 대상 브랜치 release sticky(env 보다 우선)" || bad "S5 resume 대상 sticky got=$(tmarker "$rdr")"
  rm -rf "$REPO/.dispatch"
  local ridf; ridf="$( start_rid dsp env FORGE_BIN=bash bash "$DSP" start feature-a.md )"
  local rdf; rdf="$(latest_run)"
  [[ "$(marker "$rdf")" == "forge" ]] && ok "S5 forge 백엔드 가용 → submode=forge(approver 불필요)" || bad "S5 submode=forge got=$(marker "$rdf")"
  rm -rf "$REPO/.dispatch"
  local ridd; ridd="$( start_rid dsp env FORGE_BIN=__noforge__ bash "$DSP" start feature-a.md )"
  local rdd; rdd="$(latest_run)"; local riddb; riddb="$(basename "$rdd")"
  ( cd "$REPO" && dsp env FORGE_BIN=bash bash "$DSP" start --resume "$riddb" ) >/dev/null 2>&1 || true
  [[ "$(marker "$rdd")" == "direct" ]] && ok "S5 resume: submode direct sticky(forge 가용 env 보다 마커 우선)" || bad "S5 resume submode sticky got=$(marker "$rdd")"

  # ---- S6 ----
  rm -rf "$REPO/.dispatch"
  printf -- '---\ndepends_on: [cyc-y]\n---\n# X\n' > "$REPO/cyc-x.md"
  printf -- '---\ndepends_on: [cyc-x]\n---\n# Y\n' > "$REPO/cyc-y.md"
  if ( cd "$REPO" && dsp bash "$DSP" start cyc-x.md cyc-y.md ) >/dev/null 2>&1; then
    bad "S6 cycle: abort 해야(비-0 종료)"
  else
    ok "S6 cycle: abort(비-0 종료)"
  fi
  rm -f "$REPO/cyc-x.md" "$REPO/cyc-y.md"

  # ---- S8 ----
  rm -rf "$REPO/.dispatch"
  local rid8; rid8="$( start_rid dsp bash "$DSP" start feature-a.md feature-b.md )"
  mk "$rid8" done "$REPO/feature-a.md"; mk "$rid8" done "$REPO/feature-b.md"
  if ( cd "$REPO" && dsp bash "$DSP" watch "$rid8" ) >/dev/null 2>&1; then ok "S8 watch: 전부 done → exit 0" ; else bad "S8 watch done exit0"; fi
  rm -rf "$REPO/.dispatch"
  local rid9; rid9="$( start_rid dsp bash "$DSP" start feature-a.md feature-b.md )"
  mk "$rid9" running "$REPO/feature-a.md"
  ( cd "$REPO" && dsp bash "$DSP" stop "$rid9" ) >/dev/null 2>&1
  local rd9; rd9="$(latest_run)"
  [[ "$(run_state "$rd9" feature-a.md)" == "failed" ]] && ok "S8 stop: running A → failed" || bad "S8 stop A failed got=$(run_state "$rd9" feature-a.md)"
  [[ "$(run_state "$rd9" feature-b.md)" == "skipped" ]] && ok "S8 stop: B(dep A) 이행적 skipped" || bad "S8 stop B skipped got=$(run_state "$rd9" feature-b.md)"
  local wrc=0; ( cd "$REPO" && dsp bash "$DSP" watch "$rid9" ) >/dev/null 2>&1 || wrc=$?
  [[ "$wrc" -eq 1 ]] && ok "S8 watch: failed/skipped 있으면 exit 1" || bad "S8 watch failed exit1 got=$wrc"

  # ---- S7 ----
  rm -rf "$REPO/.dispatch"
  local rid7; rid7="$( start_rid dsp bash "$DSP" start --no-integrate --integrate feature-a.md feature-b.md )"
  local rd7; rd7="$(latest_run)"
  [[ -n "$rid7" ]] && ok "S7 --no-integrate/--integrate no-op(받되 셋업 진행)" || bad "S7 no-op 플래그 셋업"
  [[ ! -f "$rd7/NO_INTEGRATE" ]] && ok "S7 NO_INTEGRATE 마커 부재(레거시 경로 없음)" || bad "S7 NO_INTEGRATE 마커 부재"
  if grep -rqx 'integrating' "$rd7"/state.* 2>/dev/null; then bad "S7 integrating 상태 부재(드레인 없음)"; else ok "S7 integrating 상태 부재(bash 드레인 없음)"; fi
  if grep -rqx 'done' "$rd7"/state.* 2>/dev/null; then bad "S7 셋업 직후 자동 done 부재"; else ok "S7 셋업 직후 자동 done 부재(start 미드라이브)"; fi

  # ---- S9: 드라이버 선택·override·강등·task-id IO·stop TaskStop 위임·resume sticky ----

  # S9a: 기본 드라이버 = foreground-batch
  rm -rf "$REPO/.dispatch"
  local rid9a; rid9a="$( start_rid dsp bash "$DSP" start feature-a.md )"
  local rd9a; rd9a="$(latest_run)"
  [[ "$(drvmarker "$rd9a")" == "foreground-batch" ]] && ok "S9a 기본 드라이버=foreground-batch" || bad "S9a 기본 드라이버 got=$(drvmarker "$rd9a")"

  # S9b: DISPATCH_DRIVER=strong-parallel override
  rm -rf "$REPO/.dispatch"
  local d_out; d_out="$( start_drv dsp env DISPATCH_DRIVER=strong-parallel bash "$DSP" start feature-a.md )"
  [[ "$d_out" == "strong-parallel" ]] && ok "S9b override strong-parallel: start 출력 확인" || bad "S9b override strong-parallel got=[$d_out]"
  local rd9b; rd9b="$(latest_run)"
  [[ "$(drvmarker "$rd9b")" == "strong-parallel" ]] && ok "S9b override: DRIVER 마커=strong-parallel" || bad "S9b override 마커 got=$(drvmarker "$rd9b")"

  # S9c: DISPATCH_DRIVER=background override
  rm -rf "$REPO/.dispatch"
  d_out="$( start_drv dsp env DISPATCH_DRIVER=background bash "$DSP" start feature-a.md )"
  [[ "$d_out" == "background" ]] && ok "S9c override background: start 출력 확인" || bad "S9c override background got=[$d_out]"

  # S9d: DISPATCH_DRIVER=invalid → foreground-batch 강등
  rm -rf "$REPO/.dispatch"
  d_out="$( start_drv dsp env DISPATCH_DRIVER=invalid-driver bash "$DSP" start feature-a.md 2>/dev/null )"
  [[ "$d_out" == "foreground-batch" ]] && ok "S9d invalid override → foreground-batch 강등" || bad "S9d 강등 got=[$d_out]"

  # S9e: resume sticky — background 설정 후 DISPATCH_DRIVER 없이 재개해도 유지
  rm -rf "$REPO/.dispatch"
  local rid9e; rid9e="$( start_rid dsp env DISPATCH_DRIVER=background bash "$DSP" start feature-a.md )"
  local rd9e; rd9e="$(latest_run)"
  [[ "$(drvmarker "$rd9e")" == "background" ]] && ok "S9e background 마커 설정" || bad "S9e background 마커 got=$(drvmarker "$rd9e")"
  ( cd "$REPO" && dsp bash "$DSP" start --resume "$rid9e" ) >/dev/null 2>&1 || true
  [[ "$(drvmarker "$rd9e")" == "background" ]] && ok "S9e resume: DRIVER 마커 sticky(background 유지)" || bad "S9e resume sticky got=$(drvmarker "$rd9e")"

  # S9f: task-id IO — mark running --task-id 기록, done 전이 시 삭제
  rm -rf "$REPO/.dispatch"
  local rid9f; rid9f="$( start_rid dsp env DISPATCH_DRIVER=background bash "$DSP" start feature-a.md )"
  local rd9f; rd9f="$(latest_run)"
  ( cd "$REPO" && dsp bash "$DSP" mark "$rid9f" running "$REPO/feature-a.md" --task-id "task-abc-123" ) >/dev/null 2>&1
  local tid_key; tid_key="$(spec_slug "$REPO/feature-a.md")-$(hash7 "$REPO/feature-a.md")"
  local tid_file="$rd9f/taskid.$tid_key"
  [[ -f "$tid_file" ]] && ok "S9f mark running: task-id 파일 생성" || bad "S9f mark running: task-id 파일 생성 (expected $tid_file)"
  [[ "$(cat "$tid_file" 2>/dev/null)" == "task-abc-123" ]] && ok "S9f task-id 값 정확" || bad "S9f task-id 값 got=$(cat "$tid_file" 2>/dev/null)"
  ( cd "$REPO" && dsp bash "$DSP" mark "$rid9f" done "$REPO/feature-a.md" ) >/dev/null 2>&1
  [[ ! -f "$tid_file" ]] && ok "S9f mark done: task-id 파일 삭제" || bad "S9f mark done: task-id 파일 삭제 안 됨"

  # S9g: stop 시 task-id 출력
  rm -rf "$REPO/.dispatch"
  local rid9g; rid9g="$( start_rid dsp env DISPATCH_DRIVER=background bash "$DSP" start feature-a.md feature-b.md )"
  local rd9g; rd9g="$(latest_run)"
  ( cd "$REPO" && dsp bash "$DSP" mark "$rid9g" running "$REPO/feature-a.md" --task-id "bg-task-xyz" ) >/dev/null 2>&1
  local stop_out; stop_out="$( cd "$REPO" && dsp bash "$DSP" stop "$rid9g" 2>/dev/null )"
  case "$stop_out" in *"bg-task-xyz"*) ok "S9g stop: task-id 출력(TaskStop 위임)" ;; *) bad "S9g stop: task-id 출력 got=[$stop_out]" ;; esac
  [[ "$(run_state "$rd9g" feature-a.md)" == "failed" ]] && ok "S9g stop: A running→failed" || bad "S9g stop A failed got=$(run_state "$rd9g" feature-a.md)"
  local tid_key_g; tid_key_g="$(spec_slug "$REPO/feature-a.md")-$(hash7 "$REPO/feature-a.md")"
  [[ ! -f "$rd9g/taskid.$tid_key_g" ]] && ok "S9g stop: task-id 파일 정리" || bad "S9g stop: task-id 파일 미정리"

  # S9h: driver subcommand
  rm -rf "$REPO/.dispatch"
  local rid9h; rid9h="$( start_rid dsp env DISPATCH_DRIVER=strong-parallel bash "$DSP" start feature-a.md )"
  local drv_out; drv_out="$( cd "$REPO" && dsp bash "$DSP" driver "$rid9h" 2>/dev/null )"
  case "$drv_out" in *"strong-parallel"*) ok "S9h driver subcommand: strong-parallel 출력" ;; *) bad "S9h driver subcommand got=[$drv_out]" ;; esac

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ----- 사용법 -----

usage() {
  cat >&2 <<'EOF'
usage: dispatch.sh <subcommand> [args]

Subcommands:
  start <spec...> [--max-parallel N] [--resume <run-id>] [--target-branch <b>]
        결정적 셋업 전용: run-dir·WAVES.txt·초기 pending 상태·run 전역 마커(INTEGRATE/
        TARGET_BRANCH/MAX_PARALLEL/DRIVER)를 생성. 드라이버 override: DISPATCH_DRIVER.
        --resume sticky. 하위호환 --integrate/--no-integrate no-op. cycle → abort.
  ready <run-id> [--max-parallel N]
        준비된 SPEC abspath 출력(skip 전파 적용, 동시성 상한 존중).
  mark <run-id> <running|done|failed> <spec> [--task-id <id>]
        상태 전이. running --task-id: 백그라운드 드라이버 task-id 기록.
        done/failed: task-id 정리. failed: 이행적 skip 전파.
  driver <run-id>
        선택된 드라이버 출력(진단용).
  list
        run-id 목록·요약(드라이버 컬럼 포함).
  status <run-id>
        per-SPEC state·드라이버 출력.
  stop <run-id>
        running→failed + skip 전파. 백그라운드 task-id 있으면 출력(TaskStop 위임).
  watch <run-id>
        모든 SPEC terminal 까지 폴링. exit 0=전부 done, 1=실패, 2=timeout.

환경 변수:
  DISPATCH_POLL_SECONDS, DISPATCH_WAVE_TIMEOUT_SECONDS, FORGE_BIN, DEFAULT_BRANCH,
  DISPATCH_DRIVER (strong-parallel|background|foreground-batch)
EOF
  exit 1
}

# ----- 디스패처 -----

if [[ $# -lt 1 ]]; then usage; fi
SUB="$1"; shift
case "$SUB" in
  start)  cmd_start  "$@" ;;
  ready)  cmd_ready  "$@" ;;
  mark)   cmd_mark   "$@" ;;
  driver) cmd_driver "$@" ;;
  list)   cmd_list  ;;
  status) cmd_status "$@" ;;
  stop)   cmd_stop   "$@" ;;
  watch)  cmd_watch  "$@" ;;
  selftest) cmd_selftest ;;
  -h|--help|help) usage ;;
  *) echo "알 수 없는 subcommand: $SUB" >&2; usage ;;
esac
