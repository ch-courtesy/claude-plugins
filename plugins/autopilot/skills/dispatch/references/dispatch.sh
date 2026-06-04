#!/usr/bin/env bash
# dispatch.sh — autopilot:dispatch driver (spec-list-driven, v0.8+)
#
# 책임:
#   - 1 개 이상의 SPEC 파일 경로를 받아 frontmatter depends_on 으로 DAG 를 구성하고
#     wave 단위로 자율 실행기(loop.sh)에 위임 호출.
#   - run-id 단위로 진행 상태를 <project_root>/.dispatch/runs/<run-id>/ 에 보관.
#   - list / status / stop / watch / --resume 운영 인터페이스 제공.
#   - (통합 모드 활성 시) per-SPEC 통합→리뷰→머지 파이프라인을 소유: loop DONE 을 곧
#     done 으로 보지 않고 push→PR→리뷰→ff-only 머지에 성공한 SPEC 만 done 으로 전이해
#     의존자 해제를 머지 뒤로 미룬다. 통합 모듈(integration/review-loop/merge.sh)은
#     서브프로세스로 격리 호출하고 per-SPEC 통합 상태는 lib-integration.sh 로 보관한다.
#
# **하지 않는 일**:
#   - 입력 SPEC 의 frontmatter 형식·내용 검증 (자율 실행기 책임).
#   - forge(PR/issue/label) 연동 — **기본(비통합) 모드에서는** 호출 레이어 책임이다.
#     통합 모드가 활성이면 dispatch 가 통합·리뷰·머지를 직접 소유한다(위 책임 참조).
#     어느 모드에서도 force(강제) push·rebase·merge 는 쓰지 않는다.
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

# ----- 통합(리뷰·머지) 모드 -----
# 통합 모드가 활성이면 loop DONE 을 곧 done 으로 보지 않고, per-SPEC 통합→리뷰→머지
# 파이프라인을 한 폴링 틱당 한 스텝씩 전진시켜(드레인) 머지에 성공한 SPEC 만 done 으로
# 전이한다(=의존자 해제). done 의 의미가 "머지됨"으로 재정의되며, 기존 ready 검사
# (dep==done)·skip 전파가 그대로 머지 게이트가 된다. 비활성이면 기존 동작(loop DONE=done).
#
# 통합 모듈은 **서브프로세스로 격리** 호출한다 — 모듈의 set +e·die→exit 가 본 스케줄러의
# set -euo pipefail·드레인 루프를 오염·중단시키지 않게 한다. 순수 상태 헬퍼(lib-integration)
# 만 sourcing 한다(top-level set 변경 없음 → 안전).
INTEGRATION_CMD="${INTEGRATION_CMD:-bash $SCRIPT_DIR/integration.sh}"
REVIEW_CMD="${REVIEW_CMD:-bash $SCRIPT_DIR/review-loop.sh}"
MERGE_CMD="${MERGE_CMD:-bash $SCRIPT_DIR/merge.sh}"
INTEGRATE_MODE=0
# shellcheck source=lib-integration.sh
. "$SCRIPT_DIR/lib-integration.sh"

# int_key <spec> — per-SPEC 통합 키. dispatch 실행 상태 키(state.<slug>-<hash7>)와 동일
# 산식이라, 스케줄러가 통합 모듈에 넘기는 키와 실행 상태 키가 일관된다.
int_key() { echo "$(spec_slug "$1")-$(hash7 "$1")"; }

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
      # signals 를 먼저 변수로 받아 yq 의 비-0 종료가 pipefail 로 if 조건에
      # 전파되지 않게 한다 — well-formed JSON 이면 동작 동일, 비정상 출력에도
      # done/failed 오판(특히 BLOCKED 누락 → done 오분류)을 방지.
      local sigs; sigs="$(printf '%s' "$json" | yq -r '.signals[]' 2>/dev/null || true)"
      if printf '%s\n' "$sigs" | grep -Fxq 'BLOCKED'; then
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

# ----- 통합 모드: loop 종료 매핑 + per-SPEC 드레인 -----

# mark_loop_terminal <run_dir> <spec> <term> — loop 가 종료(done/failed/그외)했을 때
# 스케줄러 상태로 매핑한다. 통합 모드면 done/failed 를 곧장 done/failed 로 보지 않고
# `integrating` 으로 두어 통합→리뷰→머지 드레인이 분류·전진하게 한다(spec-gap 여부 포함).
# 비활성이면 기존 동작과 동일(done→done, 그 외→failed).
mark_loop_terminal() {
  local rd="$1" spec="$2" term="$3"
  if (( INTEGRATE_MODE == 1 )) && { [[ "$term" == "done" ]] || [[ "$term" == "failed" ]]; }; then
    set_state "$rd" "$spec" "integrating"
    int_set_phase "$rd" "$(int_key "$spec")" "loop-done"
    int_set "$rd" "$(int_key "$spec")" integ-start "$(date +%s)"
    log_event "$rd" "integrate-enter $(spec_slug "$spec") loop-terminal=$term"
  else
    case "$term" in
      done) set_state "$rd" "$spec" "done";   log_event "$rd" "done $(spec_slug "$spec")" ;;
      *)    set_state "$rd" "$spec" "failed"; log_event "$rd" "failed $(spec_slug "$spec") (term=$term)" ;;
    esac
  fi
}

# drain_integration <run_dir> <spec> — integrating SPEC 을 그 시점 가능한 다음 한 스텝으로
# 전진(멱등). 통합 모듈은 서브프로세스 격리 호출(die→exit 가 스케줄러를 죽이지 않게 || true).
# 종착 통합 phase 를 스케줄러 상태로 매핑: merged→done, blocked|blocked-spec-gap|escalated→failed.
drain_integration() {
  local rd="$1" spec="$2" key phase pr branch started now
  key="$(int_key "$spec")"
  phase="$(int_get_phase "$rd" "$key")"
  pr="$(int_get_pr "$rd" "$key")"
  branch="$(int_get_branch "$rd" "$key")"

  # 통합 단계 runtime cap — 통합/리뷰/머지가 무한 대기(예: approver 승인 미반영)로 폴링
  # 루프를 영원히 막지 않도록 WAVE_TIMEOUT_SECONDS 초과 시 비완료 종착(failed)으로 회수.
  started="$(int_get "$rd" "$key" integ-start "0")"
  now="$(date +%s)"
  if [[ "$started" != "0" ]] && (( now - started >= WAVE_TIMEOUT_SECONDS )); then
    set_state "$rd" "$spec" "failed"
    log_event "$rd" "integrate-timeout $(spec_slug "$spec") elapsed=$((now - started))s phase=$phase"
    return 0
  fi

  case "$phase" in
    ""|loop-done)
      # shellcheck disable=SC2086
      $INTEGRATION_CMD integrate "$spec" "$rd" "$key" >/dev/null 2>&1 || true
      ;;
    review)
      # shellcheck disable=SC2086
      $REVIEW_CMD run "$rd" "$key" "$spec" "$pr" "$branch" >/dev/null 2>&1 || true
      ;;
    approved)
      # 분리 approver 신원 승인 1회 제출 후 머지 시도(멱등: 제출 표시).
      if [[ "$(int_get "$rd" "$key" approval-submitted "")" != "1" ]]; then
        # shellcheck disable=SC2086
        $MERGE_CMD approve "$pr" >/dev/null 2>&1 || true
        int_set "$rd" "$key" approval-submitted 1
      fi
      # shellcheck disable=SC2086
      $MERGE_CMD finish "$spec" "$rd" "$key" "$pr" >/dev/null 2>&1 || true
      ;;
    merging)
      # shellcheck disable=SC2086
      $MERGE_CMD finish "$spec" "$rd" "$key" "$pr" >/dev/null 2>&1 || true
      ;;
  esac

  phase="$(int_get_phase "$rd" "$key")"
  case "$phase" in
    merged) set_state "$rd" "$spec" "done";   log_event "$rd" "merged→done $(spec_slug "$spec")" ;;
    blocked|blocked-spec-gap|escalated)
            set_state "$rd" "$spec" "failed"; log_event "$rd" "integrate-failed $(spec_slug "$spec") phase=$phase" ;;
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

# compute_dep_idx <spec...> — 호출자 스코프의 DEP_IDX[i] 에 spec i 의 (입력 집합 내)
# 의존 인덱스 목록을 공백 구분 문자열로 채운다(bash 동적 스코프). build_dag 의 edge
# 도출과 동일 기법(extract_depends_on + resolve_dep)을 재사용하되, wave 가 아니라
# 준비도 스케줄링용 인접 정보를 만든다. 입력 집합 밖 의존성은 무시(dispatch 범위 밖).
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

# ----- subcommand: start -----

cmd_start() {
  require_git_root
  require_yq
  local resume=""
  local max_parallel=0
  local integrate_opt=0
  local -a inputs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --resume) resume="$2"; shift 2 ;;
      --max-parallel) max_parallel="$2"; shift 2 ;;
      --integrate) integrate_opt=1; shift ;;
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

  # ----- 통합 모드 활성 판정 (opt-in) -----
  # 트리거: --integrate 플래그 또는 forge 구성(APPROVER 신원 설정). 활성이면 run-dir 에
  # 마커를 남겨 --resume 에서도 동일 모드로 재개한다. 비활성이면 기존 동작(loop DONE=done).
  if (( integrate_opt == 1 )) || [[ -n "${APPROVER:-}" ]]; then INTEGRATE_MODE=1; fi
  if [[ -f "$rd/INTEGRATE" ]]; then INTEGRATE_MODE=1; fi
  if (( INTEGRATE_MODE == 1 )); then
    : > "$rd/INTEGRATE"
    log_event "$rd" "integration mode ON (review→merge 게이트; done=머지됨)"
  fi

  # ----- 스트리밍 스케줄러 (SPEC별 준비도 기반) -----
  # WAVES.txt 는 진단용으로 보존하되, 실제 실행은 wave 배리어가 아니라 각 SPEC 의
  # depends_on 준비도로 구동한다. 한 SPEC 은 자신의 모든 dep 이 done 이 되는 즉시
  # (같은 위상의 무관 SPEC 이 아직 실행 중이어도) 동시성 상한 이내에서 시작된다.
  # 한 SPEC 이 failed 면 그 이행적 의존자만 skipped 로 차단되고, 의존 관계가 없는
  # 가지는 끝까지 진행한다.
  local n=${#specs_abs[@]}
  local -a DEP_IDX=()
  compute_dep_idx "${specs_abs[@]}"

  # resume: done 이 아닌 모든 상태(failed/skipped/running/pending)를 pending 으로
  # 되돌려 미완 SPEC 을 스트리밍 스케줄에 따라 재시도(이미 done 인 SPEC 은 재실행 안 함).
  if [[ -n "$resume" ]]; then
    local ri
    for ((ri=0; ri<n; ri++)); do
      [[ "$(get_state "$rd" "${specs_abs[ri]}")" == "done" ]] \
        || set_state "$rd" "${specs_abs[ri]}" "pending"
    done
  fi

  local -a PIDS=() LAUNCH_TS=()
  local i
  for ((i=0; i<n; i++)); do PIDS[i]=""; LAUNCH_TS[i]=0; done
  local overall_rc=0 timed_out=0
  log_event "$rd" "stream start specs=$n max_parallel=$max_parallel"

  while :; do
    # 1) skip 전파 — pending 인데 dep 중 failed/skipped 가 있으면 skipped (fixpoint).
    local changed=1 d ds
    while (( changed == 1 )); do
      changed=0
      for ((i=0; i<n; i++)); do
        [[ "$(get_state "$rd" "${specs_abs[i]}")" == "pending" ]] || continue
        for d in ${DEP_IDX[i]}; do
          ds="$(get_state "$rd" "${specs_abs[d]}")"
          if [[ "$ds" == "failed" || "$ds" == "skipped" ]]; then
            set_state "$rd" "${specs_abs[i]}" "skipped"
            log_event "$rd" "skip $(spec_slug "${specs_abs[i]}") (dep $(spec_slug "${specs_abs[d]}") $ds)"
            changed=1; break
          fi
        done
      done
    done

    # 2) 준비된 pending 실행 — 모든 dep 이 done & 동시 실행 수 < 상한.
    local running_count=0
    for ((i=0; i<n; i++)); do
      [[ "$(get_state "$rd" "${specs_abs[i]}")" == "running" ]] && running_count=$((running_count+1))
    done
    local ready
    for ((i=0; i<n; i++)); do
      [[ "$(get_state "$rd" "${specs_abs[i]}")" == "pending" ]] || continue
      ready=1
      for d in ${DEP_IDX[i]}; do
        [[ "$(get_state "$rd" "${specs_abs[d]}")" == "done" ]] || { ready=0; break; }
      done
      (( ready == 1 )) || continue
      if (( max_parallel > 0 )) && (( running_count >= max_parallel )); then continue; fi
      set_state "$rd" "${specs_abs[i]}" "running"
      local pid; pid="$(loop_start_bg "${specs_abs[i]}")"
      PIDS[i]="$pid"; LAUNCH_TS[i]=$(date +%s)
      running_count=$((running_count+1))
      log_event "$rd" "launch $(spec_slug "${specs_abs[i]}") pid=$pid"
    done

    # 3) 종료된 running reap + per-spec runtime cap(WAVE_TIMEOUT_SECONDS).
    local now term; now=$(date +%s)
    for ((i=0; i<n; i++)); do
      [[ "$(get_state "$rd" "${specs_abs[i]}")" == "running" ]] || continue
      [[ -n "${PIDS[i]}" ]] || continue
      if kill -0 "${PIDS[i]}" 2>/dev/null; then
        # 아직 실행 중 — per-spec runtime cap 초과 시 SIGTERM→SIGKILL 으로 정리.
        if (( now - LAUNCH_TS[i] >= WAVE_TIMEOUT_SECONDS )); then
          timed_out=1
          log_event "$rd" "timeout $(spec_slug "${specs_abs[i]}") elapsed=$((now - LAUNCH_TS[i]))s cap=${WAVE_TIMEOUT_SECONDS}s"
          kill_tree "${PIDS[i]}" TERM; sleep 1
          kill -0 "${PIDS[i]}" 2>/dev/null && kill_tree "${PIDS[i]}" KILL
          wait "${PIDS[i]}" 2>/dev/null || true
          # timeout 직전 이미 done 인 child 는 done(통합 모드면 integrating 진입), 아니면 failed.
          term="$(child_terminal_state "${specs_abs[i]}")"
          mark_loop_terminal "$rd" "${specs_abs[i]}" "$term"
          PIDS[i]=""
        fi
        continue
      fi
      # PID 종료 — loop 구조화 상태로 종료 상태 판정. 통합 모드면 done/failed 를
      # integrating 으로 두고(아래 드레인이 분류·전진), 비활성이면 기존대로 done/failed.
      term="$(child_terminal_state "${specs_abs[i]}")"
      mark_loop_terminal "$rd" "${specs_abs[i]}" "$term"
      PIDS[i]=""
    done

    # 3.5) 통합 모드 드레인 — integrating SPEC 을 틱당 한 스텝씩 멱등 전진.
    #   integrate→review→(approve)→merge. merged→done(=의존자 해제), 비완료 종착→failed.
    if (( INTEGRATE_MODE == 1 )); then
      for ((i=0; i<n; i++)); do
        [[ "$(get_state "$rd" "${specs_abs[i]}")" == "integrating" ]] || continue
        drain_integration "$rd" "${specs_abs[i]}"
      done
    fi

    # 4) 종료 판정 — 모든 SPEC 이 done/failed/skipped 이면 끝.
    local pending_or_running=0
    for ((i=0; i<n; i++)); do
      case "$(get_state "$rd" "${specs_abs[i]}")" in
        done|failed|skipped) ;;
        *) pending_or_running=1 ;;
      esac
    done
    (( pending_or_running == 0 )) && break
    sleep "${POLL_SECONDS:-1}"
  done

  # 종합 결과: timeout 있었으면 2, 아니면 하나라도 failed/skipped 면 1, 전부 done 이면 0.
  local any_bad=0
  for ((i=0; i<n; i++)); do
    case "$(get_state "$rd" "${specs_abs[i]}")" in failed|skipped) any_bad=1 ;; esac
  done
  if (( timed_out == 1 )); then overall_rc=2
  elif (( any_bad == 1 )); then overall_rc=1
  else overall_rc=0; fi
  log_event "$rd" "stream done rc=$overall_rc"

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
        done)    ;;
        failed)  any_fail=1 ;;
        skipped) any_fail=1 ;;  # 이행적 실패로 차단된 SPEC — terminal(비완료).
        integrating)
          # 통합 모드: loop 는 끝났지만 통합→리뷰→머지 진행 중. 머지(=done) 전까지 비완료.
          # watch 는 통합을 전진시키지 않으므로(스케줄러 cmd_start 소유) 미완으로만 보고한다.
          all_terminal=0 ;;
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

# =====================================================================
# selftest — 스케줄러 통합 검증(mock loop/integration/review/merge).
#   AC1/AC8: 의존자는 의존성이 머지(done)된 뒤에만 launch.
#   AC9: 비완료 종착(통합 차단)이면 이행적 의존자만 skipped.
#   AC10: 머지 직렬화는 merge.sh 락 selftest 가 단언(여기선 머지 위임 경로 확인).
#   회귀: 통합 모드 비활성이면 loop DONE=done(통합 모듈 미호출).
#   self-referential: 실제 PR·머지 미수행(모두 mock).
# =====================================================================
cmd_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local LIBINT="$SCRIPT_DIR/lib-integration.sh"
  local DSP="$SCRIPT_DIR/dispatch.sh"

  # mock loop: start→launch 이벤트 + 즉시 종료, status --json→terminal/DONE.
  cat > "$TMP/m-loop.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  start)  shift; [[ "$1" == --* ]] && shift; printf 'launch:%s\n' "$(basename "$1")" >> "$EVENTLOG"; exit 0 ;;
  status) printf '{"state":"terminal","signals":["DONE"]}\n' ;;
  logs|stop|cleanup) : ;;
esac
exit 0
EOF
  # mock integration: integrate <spec> <rd> <key>. MOCK_INT_BLOCK 이면 그 spec 을 blocked.
  cat > "$TMP/m-int.sh" <<'EOF'
#!/usr/bin/env bash
. "$LIBINT"
spec="$2"; rd="$3"; key="$4"
printf 'integrate:%s\n' "$(basename "$spec")" >> "$EVENTLOG"
if [[ -n "${MOCK_INT_BLOCK:-}" && "$(basename "$spec")" == "$MOCK_INT_BLOCK" ]]; then
  int_set_phase "$rd" "$key" blocked
else
  int_set_branch "$rd" "$key" "feat/x-$key"; int_set_pr "$rd" "$key" 100
  int_set_phase "$rd" "$key" review
fi
exit 0
EOF
  # mock review: run <rd> <key> <spec> <pr> <branch> → approved.
  cat > "$TMP/m-review.sh" <<'EOF'
#!/usr/bin/env bash
. "$LIBINT"
rd="$2"; key="$3"; spec="$4"
printf 'review:%s\n' "$(basename "$spec")" >> "$EVENTLOG"
int_set_phase "$rd" "$key" approved
exit 0
EOF
  # mock merge: approve <pr> / finish <spec> <rd> <key> <pr> → merged.
  cat > "$TMP/m-merge.sh" <<'EOF'
#!/usr/bin/env bash
. "$LIBINT"
case "$1" in
  approve) printf 'approve:%s\n' "$2" >> "$EVENTLOG" ;;
  finish)  spec="$2"; rd="$3"; key="$4"
           printf 'merge:%s\n' "$(basename "$spec")" >> "$EVENTLOG"
           int_set_phase "$rd" "$key" merged ;;
esac
exit 0
EOF

  # 격리 git 저장소 + SPEC 2개(B depends_on A).
  local REPO="$TMP/repo"; mkdir -p "$REPO"
  ( cd "$REPO" && git init -q )
  printf -- '---\n---\n# Feature A\n' > "$REPO/feature-a.md"
  printf -- '---\ndepends_on: [feature-a]\n---\n# Feature B\n' > "$REPO/feature-b.md"

  local fail=0
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  before() { # <eventlog> <pat-A> <pat-B> : A 줄번호 < B 줄번호 (둘 다 존재)
    local lg="$1" a b
    a="$(grep -n "$2" "$lg" | head -1 | cut -d: -f1)"
    b="$(grep -n "$3" "$lg" | head -1 | cut -d: -f1)"
    [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]]
  }
  run_state() { # <run_dir> <spec-basename> — state_path 산식(state.<slug>-<hash7>) 재현.
    local rd="$1" sp key; sp="$REPO/$2"
    key="$(spec_slug "$sp")-$(hash7 "$sp")"
    cat "$rd/state.$key" 2>/dev/null || echo "MISSING"
  }
  latest_run() { ls -1dt "$REPO"/.dispatch/runs/*/ 2>/dev/null | head -1 | sed 's:/$::'; }

  # ---- 시나리오 1: 통합 모드 — 머지 게이트로 의존자 해제 ----
  rm -rf "$REPO/.dispatch"
  local EVENTLOG="$TMP/ev1.log"; : > "$EVENTLOG"
  ( cd "$REPO" && env EVENTLOG="$EVENTLOG" LOOP_CMD="bash $TMP/m-loop.sh" \
      INTEGRATION_CMD="bash $TMP/m-int.sh" REVIEW_CMD="bash $TMP/m-review.sh" MERGE_CMD="bash $TMP/m-merge.sh" \
      LIBINT="$LIBINT" DISPATCH_POLL_SECONDS=0 DISPATCH_WAVE_TIMEOUT_SECONDS=120 \
      bash "$DSP" start --integrate feature-a.md feature-b.md ) >/dev/null 2>&1 || true
  local rd1; rd1="$(latest_run)"
  [[ "$(run_state "$rd1" feature-a.md)" == "done" ]] && ok "S1 A 머지(done)" || bad "S1 A 머지(done) got=$(run_state "$rd1" feature-a.md)"
  [[ "$(run_state "$rd1" feature-b.md)" == "done" ]] && ok "S1 B 머지(done)" || bad "S1 B 머지(done) got=$(run_state "$rd1" feature-b.md)"
  before "$EVENTLOG" 'merge:feature-a.md' 'launch:feature-b.md' \
    && ok "AC1/AC8 A 머지 후에만 B launch" || bad "AC1/AC8 A 머지 후에만 B launch"
  before "$EVENTLOG" 'integrate:feature-a.md' 'merge:feature-a.md' \
    && ok "S1 A integrate→review→merge 순서" || bad "S1 A integrate→merge 순서"
  [[ -f "$rd1/INTEGRATE" ]] && ok "S1 통합 모드 마커" || bad "S1 통합 모드 마커"

  # ---- 시나리오 2: 통합 차단(A) → 이행적 의존자 B skipped ----
  rm -rf "$REPO/.dispatch"
  local EVENTLOG2="$TMP/ev2.log"; : > "$EVENTLOG2"
  ( cd "$REPO" && env EVENTLOG="$EVENTLOG2" MOCK_INT_BLOCK="feature-a.md" LOOP_CMD="bash $TMP/m-loop.sh" \
      INTEGRATION_CMD="bash $TMP/m-int.sh" REVIEW_CMD="bash $TMP/m-review.sh" MERGE_CMD="bash $TMP/m-merge.sh" \
      LIBINT="$LIBINT" DISPATCH_POLL_SECONDS=0 DISPATCH_WAVE_TIMEOUT_SECONDS=120 \
      bash "$DSP" start --integrate feature-a.md feature-b.md ) >/dev/null 2>&1 || true
  local rd2; rd2="$(latest_run)"
  [[ "$(run_state "$rd2" feature-a.md)" == "failed" ]] && ok "AC9 A 비완료 종착(failed)" || bad "AC9 A failed got=$(run_state "$rd2" feature-a.md)"
  [[ "$(run_state "$rd2" feature-b.md)" == "skipped" ]] && ok "AC9 B 이행적 skipped" || bad "AC9 B skipped got=$(run_state "$rd2" feature-b.md)"
  if grep -q 'launch:feature-b.md' "$EVENTLOG2"; then bad "AC9 B 미launch"; else ok "AC9 B 미launch(차단 전파)"; fi

  # ---- 시나리오 3: 회귀 — 통합 모드 비활성이면 loop DONE=done, 통합 모듈 미호출 ----
  rm -rf "$REPO/.dispatch"
  local EVENTLOG3="$TMP/ev3.log"; : > "$EVENTLOG3"
  ( cd "$REPO" && env EVENTLOG="$EVENTLOG3" LOOP_CMD="bash $TMP/m-loop.sh" \
      INTEGRATION_CMD="bash $TMP/m-int.sh" REVIEW_CMD="bash $TMP/m-review.sh" MERGE_CMD="bash $TMP/m-merge.sh" \
      LIBINT="$LIBINT" DISPATCH_POLL_SECONDS=0 DISPATCH_WAVE_TIMEOUT_SECONDS=120 \
      bash "$DSP" start feature-a.md feature-b.md ) >/dev/null 2>&1 || true
  local rd3; rd3="$(latest_run)"
  [[ "$(run_state "$rd3" feature-a.md)" == "done" ]] && ok "회귀 A loop DONE=done" || bad "회귀 A done got=$(run_state "$rd3" feature-a.md)"
  [[ "$(run_state "$rd3" feature-b.md)" == "done" ]] && ok "회귀 B loop DONE=done" || bad "회귀 B done got=$(run_state "$rd3" feature-b.md)"
  if grep -qE 'integrate:|review:|merge:' "$EVENTLOG3"; then bad "회귀 통합 모듈 미호출"; else ok "회귀 통합 모듈 미호출(비활성)"; fi
  before "$EVENTLOG3" 'launch:feature-a.md' 'launch:feature-b.md' \
    && ok "회귀 A done 후 B launch(기존 게이트)" || bad "회귀 A done 후 B launch"
  [[ ! -f "$rd3/INTEGRATE" ]] && ok "회귀 통합 마커 없음" || bad "회귀 통합 마커 없음"

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ----- 사용법 -----

usage() {
  cat >&2 <<'EOF'
usage: dispatch.sh <subcommand> [args]

Subcommands:
  start <spec...> [--max-parallel N] [--resume <run-id>]
        1 개 이상의 SPEC 파일 경로를 받아 depends_on 으로 DAG 를 만들고,
        각 SPEC 을 그 의존성이 모두 done 이 되는 즉시(준비도 기반 스트리밍,
        동시성 상한 이내) loop driver 에 위임한다. 한 SPEC 이 failed 면 그
        이행적 의존자만 skipped 되고 독립 가지는 끝까지 진행. WAVES.txt 는
        진단용으로 보존. --resume 이면 done 이 아닌 SPEC 만 재시도.
  list
        모든 run-id 와 진행 요약.
  status <run-id>
        run-id 단위 per-SPEC state(진단용 wave 표시 포함).
  stop <run-id>
        진행 중 child loop 들을 정지 (loop driver 에 위임).
  watch <run-id>
        per-SPEC 상태를 폴링하며 모든 child 가 terminal(done/failed/skipped)에
        도달할 때까지 대기. exit 0=전부 done, 1=failed/skipped 있음, 2=timeout.

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
  selftest) cmd_selftest ;;
  -h|--help|help) usage ;;
  *) echo "알 수 없는 subcommand: $SUB" >&2; usage ;;
esac
