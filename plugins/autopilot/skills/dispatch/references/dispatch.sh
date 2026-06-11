#!/usr/bin/env bash
# dispatch.sh — autopilot:dispatch 결정적 오케스트레이션 헬퍼 (모델 주도)
#
# dispatch 는 준비된 SPEC마다 서브에이전트를 1개 띄우는 **모델 주도** 오케스트레이터다. 통합·
# 리뷰·머지는 서브에이전트가 SPEC당 한 컨텍스트에서 소유한다(계약: references/subagent-prompt.md).
# 이 셸 스크립트는 그 오케스트레이션의 **결정적 부분만** 제공하는 헬퍼다 — 오케스트레이션 주체가
# 아니다(서브에이전트 spawn 은 Agent 도구를 쓰는 모델이 수행, bash 무인 드레인 루프 아님).
#
# 책임(결정적):
#   - start: SPEC 입력 검증·frontmatter depends_on 으로 DAG 구성·WAVES.txt(진단)·초기 pending
#            상태·run 전역 마커(서브모드 INTEGRATE / 대상 브랜치 TARGET_BRANCH / MAX_PARALLEL /
#            fan-out 드라이버 DRIVER)를 만드는 **셋업 전용**. 스스로 spawn·드레인하지 않는다.
#   - ready: 지금 서브에이전트를 띄울 준비된 SPEC(모든 dep done & pending & 동시성 상한 이내)을
#            출력(skip 전파 적용). 모델이 각 SPEC 에 서브에이전트 1개를 spawn.
#   - mark:  SPEC 상태 전이(running=spawn 직전 / done=서브에이전트 머지 보고=의존자 해제 /
#            failed=비완료 보고 → 이행적 의존자 skipped 전파).
#   - list / status / stop / watch / --resume 운영 인터페이스(읽기 위주). done 의 의미는
#     "대상 브랜치에 머지됨"이며, 의존자 해제는 머지(done) 뒤로 미뤄진다.
#
# **하지 않는 일**:
#   - 입력 SPEC 의 frontmatter 형식·내용 검증 (서브에이전트/loop 책임).
#   - 통합·리뷰·머지의 직접 수행(bash 드레인). 그것은 서브에이전트가 소유한다.
#   - 서브에이전트가 호출하는 loop·review 의 내부 신호 파일·worktree 열람(블랙박스 경계).
#
# 모델 루프(스킬이 구동): start → 반복{ ready → 각 SPEC: mark running + 서브에이전트 spawn →
#   보고 시 mark done(머지)·mark failed(에스컬레이션) } → ready 가 비고 running 없을 때까지.
#
# 사용:
#   bash dispatch.sh start <spec...> [--max-parallel N] [--resume <run-id>] [--target-branch <b>]
#   bash dispatch.sh ready <run-id> [--max-parallel N]
#   bash dispatch.sh mark <run-id> <running|done|failed> <spec>
#   bash dispatch.sh list | status <run-id> | driver <run-id> | stop <run-id> | watch <run-id>
#
# 환경 변수:
#   DISPATCH_POLL_SECONDS          watch 폴링 간격 (기본 2)
#   DISPATCH_WAVE_TIMEOUT_SECONDS  watch 최대 대기 (기본 7200 = 2 시간)
#   FORGE_BIN DEFAULT_BRANCH  서브모드·대상 브랜치 판정(주입 가능, mock 검증).
#   DISPATCH_DRIVER  fan-out 드라이버 override(strong-parallel|background|foreground-batch).
#   DISPATCH_NO_STRONG_PARALLEL=1 / DISPATCH_NO_BACKGROUND=1  강등 신호(기본은 동적 선호; 동적·백그라운드
#                    실행 불가 판정 시에만 주입). 없으면 기본 선호 strong-parallel.
#
# bash 3.2 호환 (assoc array 사용 안 함).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLL_SECONDS="${DISPATCH_POLL_SECONDS:-2}"
WAVE_TIMEOUT_SECONDS="${DISPATCH_WAVE_TIMEOUT_SECONDS:-7200}"

# ----- 서브모드·대상 브랜치 (모델 주도 — 서브에이전트가 리뷰·머지를 소유) -----
# 통합·리뷰·머지는 서브에이전트가 SPEC당 한 컨텍스트에서 소유한다(계약: references/subagent-prompt.md).
# dispatch.sh 는 결정적 셋업·스케줄링 헬퍼만 제공하고 통합 모듈을 드레인하지 않는다.
# 서브모드(forge/direct)와 대상 브랜치는 run 전역 사실로 cmd_start 가 결정·영속(run-dir 마커)해
# 서브에이전트가 일관되게 읽고 --resume 에서 sticky 하다.
#   서브모드: forge(forge CLI 백엔드 가용 → PR 적대 리뷰·가용 토큰 ff 머지, approver 불필요) |
#             direct(백엔드 미가용 → 로컬 적대 리뷰·ff 직접 머지). cmd_start 가 INTEGRATE 마커로 영속.
INTEGRATE_SUBMODE=""
# 대상 브랜치(--target-branch, 미지정 시 기본 브랜치). cmd_start 가 TARGET_BRANCH 마커로 영속하고
# 서브에이전트에 DEFAULT_BRANCH 로 export 한다.
TARGET_BRANCH=""
# forge CLI 바이너리(서브모드 판정용). '사용 가능' 판정에만 쓴다.
FORGE_BIN="${FORGE_BIN:-gh}"

# forge_backend_available — 서브모드 판정: forge CLI(FORGE_BIN)가 사용 가능하면 0(forge),
#   아니면 1(백엔드 미가용 → direct). forge 백엔드가 있으면 분리 승인 신원(approver) 구성
#   여부와 무관하게 forge 경로(작업 브랜치 push→PR)를 쓰고, 머지는 가용 토큰으로 수행한다
#   (분리 approver 요구 없음 — merge.sh 참조). cmd_start 가 run 전역 서브모드를 결정할 때 쓴다
#   (서브에이전트는 이 마커를 읽어 리뷰·머지 대상을 정한다).
forge_backend_available() {
  command -v "${FORGE_BIN%% *}" >/dev/null 2>&1
}

# ----- fan-out 드라이버 (강한 병렬 / 백그라운드 / 포그라운드 배치) -----
# dispatch fan-out 단계(준비된 SPEC당 워커 1개 진행)는 실행 환경 역량에 따라 세 드라이버 중
# 하나로 구동된다. 세 드라이버는 동일한 결정적 코어(ready 스트리밍·mark skip 전파·merge/review
# 게이트)를 공유하고 fan-out 진행 방식만 다르다.
#   strong-parallel : dynamic Workflow 실행 — 임의 depends_on DAG를 promise 기반으로 표현해
#                     노드별 의존성 충족 즉시 워커 실행(SPEC당 워커 1). 런타임이 병렬·스트리밍·
#                     동시성·재개를 네이티브로 소유.
#   background      : 워커를 비동기로 띄우고 개별 완료 신호에 반응해 의존자를 즉시 해제.
#   foreground-batch: 한 턴에 ready 동시 시작 → 배리어 → 준비도 재평가. 안전 폴백(사슬 종착).
# 안전 강등 사슬: strong-parallel → background → foreground-batch.
#
# 기본 선호는 strong-parallel(동적 Workflow): 신호가 없어도 기본으로 동적을 시도한다. 자동 감지는
# 실행 환경(세션) 속성이라 대상 리포 파일로 결정적 probe 불가 — 실행 주체(모델)의 환경 판정에 둔다.
# 동적 Workflow 를 실제로 실행할 수 없다고 판정될 때에만 모델이 강등 신호를 주입한다:
# DISPATCH_NO_STRONG_PARALLEL=1(동적 불가) → background, 추가로 DISPATCH_NO_BACKGROUND=1(백그라운드도
# 불가) → foreground-batch(강등 사슬 종착). 운영자 override 는 기존 시작 CLI 를 바꾸지 않도록
# DISPATCH_DRIVER 환경 변수로 받는다(DISPATCH_* 주입 관례). 결정된 드라이버는 run-dir 마커(DRIVER)로
# 영속해 --resume 에서 sticky 하다.
DISPATCH_DRIVER="${DISPATCH_DRIVER:-}"   # 운영자 override(빈 값이면 자동 감지).
FANOUT_DRIVER=""                         # cmd_start 가 결정 후 채운다.

# valid_driver <name> — 알려진 드라이버 이름이면 0.
valid_driver() {
  case "$1" in
    strong-parallel|background|foreground-batch) return 0 ;;
    *) return 1 ;;
  esac
}

# detect_driver — 드라이버를 결정해 echo. 우선순위:
#   1. DISPATCH_DRIVER override 가 유효하면 그대로(무효면 abort).
#   2. 기본 선호 = strong-parallel(동적 Workflow). 신호가 없으면 동적을 시도한다.
#   3. 동적 실행 불가 판정 시에만 강등(모델 환경 신호):
#        DISPATCH_NO_STRONG_PARALLEL=1 → background 로 강등.
#        + DISPATCH_NO_BACKGROUND=1 도 있으면 → foreground-batch(강등 사슬 종착).
#   강등 사슬은 strong-parallel → background → foreground-batch 순서를 지킨다(건너뛰기 없음):
#   동적 가용이면(NO_STRONG_PARALLEL 미설정) NO_BACKGROUND 와 무관하게 strong-parallel.
detect_driver() {
  if [[ -n "$DISPATCH_DRIVER" ]]; then
    if valid_driver "$DISPATCH_DRIVER"; then
      echo "$DISPATCH_DRIVER"; return
    fi
    die "DISPATCH_DRIVER='$DISPATCH_DRIVER' 은 유효하지 않은 드라이버(strong-parallel|background|foreground-batch)"
  fi
  # 기본 선호: 동적 Workflow(strong-parallel). 실행 불가로 판정될 때에만 안전 강등.
  if [[ "${DISPATCH_NO_STRONG_PARALLEL:-}" == "1" ]]; then
    if [[ "${DISPATCH_NO_BACKGROUND:-}" == "1" ]]; then
      echo "foreground-batch"; return
    fi
    echo "background"; return
  fi
  echo "strong-parallel"
}

# ----- helpers -----

die() { echo "ERROR: $*" >&2; exit 1; }

# yq 는 SPEC frontmatter 의 depends_on 파싱에 쓴다(없으면 awk 폴백이 있으나, 신·구 레이아웃·
# 인라인/블록 형식의 견고한 파싱을 위해 start 에서 명시적으로 요구한다).
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

# propagate_skips <run_dir> <spec...> — fixpoint skip 전파(결정적). pending 인데 dep 중
# failed/skipped 가 있으면 skipped 로 차단한다(이행적). 전제: 호출 전에 compute_dep_idx 로
# 호출자 scope 의 DEP_IDX(MANIFEST 순서 평행 인덱스)를 채워 둔다 — bash 동적 스코프로 참조.
# cmd_start(스트리밍 스케줄러)·cmd_ready·cmd_mark 가 공유하는 단일 출처.
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
# 모델(dispatch 스킬)이 ready 로 "지금 서브에이전트를 띄울 SPEC"을 묻고, 각각에 서브에이전트
# 1개를 Agent 도구로 spawn 한 뒤 mark 로 상태를 전이한다. 스케줄링·동시성·skip 전파의
# 결정적 로직은 여기(코드)에 있고, spawn·구현·리뷰·머지는 서브에이전트(모델)가 소유한다.

# load_run <run-id> → RD(전역) 설정 + SP(전역 배열) 채움 + DEP_IDX 계산. 없으면 die.
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

# cmd_ready <run-id> [--max-parallel N] — 지금 서브에이전트를 띄울 준비가 된 SPEC abspath 를
# 한 줄씩 출력한다. skip 전파를 먼저 적용한 뒤, state==pending & 모든 dep done & (상한 미설정
# 또는 running 수 < 상한)인 SPEC 을 고른다. 한 호출 안에서 상한을 넘지 않도록 선택분을 센다.
# 출력이 비면 "지금 띄울 것 없음"(아직 running 중이거나 모두 terminal).
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
  # --max-parallel 미지정이면 start 가 영속한 MAX_PARALLEL 마커를 기본값으로(sticky).
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

# cmd_mark <run-id> <running|done|failed> <spec> — SPEC 상태 전이(결정적).
#   running: 서브에이전트 spawn 직전(중복 spawn 방지 — ready 에서 빠짐).
#   done   : 서브에이전트가 대상 브랜치 머지를 보고(= 의존자 해제 게이트).
#   failed : 서브에이전트가 비완료(에스컬레이션) 보고 → 이행적 의존자만 skipped 전파.
cmd_mark() {
  require_git_root
  local rid="$1" st="${2:-}" spec="${3:-}"
  [[ -n "$rid" && -n "$st" && -n "$spec" ]] || die "사용: $0 mark <run-id> <running|done|failed> <spec>"
  case "$st" in running|done|failed) ;; *) die "알 수 없는 상태: $st (running|done|failed)" ;; esac
  local RD; local -a SP=() DEP_IDX=()
  load_run "$rid"
  local ap; ap="$(abspath "$spec")"
  set_state "$RD" "$ap" "$st"
  log_event "$RD" "mark $(spec_slug "$ap") $st"
  if [[ "$st" == "failed" ]]; then
    propagate_skips "$RD" "${SP[@]}"
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
      # 통합은 항상 활성(토글 제거). 하위호환을 위해 두 플래그를 받되 아무 효과 없이 무시한다.
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

  # ----- 통합 서브모드 판정 (통합은 항상 활성 — 토글 없음) -----
  # 서브모드(forge/direct)는 run-dir 마커($rd/INTEGRATE, 내용=서브모드)로 보존해 --resume 에서
  # sticky 하다(최초 시작 결정을 그대로 재개). 마커가 있으면(=재개) 현재 env/플래그보다 우선.
  if [[ -f "$rd/INTEGRATE" ]]; then
    INTEGRATE_SUBMODE="$(cat "$rd/INTEGRATE" 2>/dev/null || true)"
  fi
  # 서브모드 미정(최초 시작 또는 빈 마커)이면 forge 백엔드 가용 여부로 결정.
  if [[ -z "$INTEGRATE_SUBMODE" ]]; then
    if forge_backend_available; then INTEGRATE_SUBMODE=forge; else INTEGRATE_SUBMODE=direct; fi
  fi
  printf '%s\n' "$INTEGRATE_SUBMODE" > "$rd/INTEGRATE"

  # ----- 대상 브랜치 판정 (--target-branch, 미지정 시 기본 브랜치) -----
  # run-dir 마커($rd/TARGET_BRANCH)로 영속해 --resume 에서 sticky 하다. 마커가 있으면(=재개)
  # 현재 env(DEFAULT_BRANCH)·--target-branch 플래그보다 마커가 우선한다. 결정된 대상은 모든
  # 통합 모듈(base sync·승인 요청 base·ff 머지·base push)에 DEFAULT_BRANCH 로 export 된다.
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

  # ----- max-parallel 마커(동시성 상한, resume sticky) -----
  # 모델 주도 ready 가 기본값으로 읽는다(모델이 --max-parallel 을 매번 주지 않아도 일관).
  # 마커가 있으면(=재개) 현재 플래그보다 우선(sticky).
  [[ -f "$rd/MAX_PARALLEL" ]] || printf '%s\n' "$max_parallel" > "$rd/MAX_PARALLEL"

  # ----- fan-out 드라이버 판정 (DRIVER 마커, resume sticky) -----
  # run-dir 마커($rd/DRIVER)로 영속해 --resume 에서 sticky(최초 시작 결정을 그대로 재개).
  # 마커가 있으면(=재개) 현재 env(DISPATCH_DRIVER/신호)보다 우선. 자동 감지·override·안전 폴백은
  # detect_driver 가 담당(강등 사슬: strong-parallel → background → foreground-batch).
  if [[ -f "$rd/DRIVER" ]]; then
    FANOUT_DRIVER="$(cat "$rd/DRIVER" 2>/dev/null || true)"
  fi
  if [[ -z "$FANOUT_DRIVER" ]] || ! valid_driver "$FANOUT_DRIVER"; then
    FANOUT_DRIVER="$(detect_driver)"
  fi
  printf '%s\n' "$FANOUT_DRIVER" > "$rd/DRIVER"
  log_event "$rd" "fan-out driver=$FANOUT_DRIVER (override=${DISPATCH_DRIVER:-auto})"

  # ----- 셋업 완료 — 모델 주도 오케스트레이션으로 인계 -----
  # dispatch.sh 는 결정적 셋업(run-dir·DAG·markers·pending 상태)만 수행한다. 준비된 SPEC당
  # 서브에이전트 spawn·구현·리뷰·머지는 모델(dispatch 스킬)이 ready/mark 헬퍼 + Agent 도구로
  # 소유한다(서브에이전트 계약: references/subagent-prompt.md). bash 무인 드레인 루프는 없다.
  #
  # 모델 루프:
  #   1. ready <run-id> [--max-parallel N] → 지금 띄울 준비된 SPEC 목록.
  #   2. 각 SPEC: mark <run-id> running <spec> → 서브에이전트 1개 spawn(Agent 도구).
  #   3. 서브에이전트 보고: 머지됨→mark done(=의존자 해제), 비완료→mark failed(이행적 skip).
  #   4. ready 가 비고 running 이 없을 때까지 반복.
  #
  # resume: done 이 아닌 모든 상태(failed/skipped/running/pending)를 pending 으로 되돌려
  #   미완 SPEC 을 다시 스케줄 대상에 올린다(이미 done 인 SPEC 은 보존).
  local n=${#specs_abs[@]} i
  if [[ -n "$resume" ]]; then
    for ((i=0; i<n; i++)); do
      [[ "$(get_state "$rd" "${specs_abs[i]}")" == "done" ]] \
        || set_state "$rd" "${specs_abs[i]}" "pending"
    done
  fi
  log_event "$rd" "setup done specs=$n submode=$INTEGRATE_SUBMODE target-branch=$TARGET_BRANCH max_parallel=$(cat "$rd/MAX_PARALLEL" 2>/dev/null) (모델 주도; done=머지됨)"
  echo "run-id: $(basename "$rd")"
  return 0
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
  local rd; rd="$(run_dir "$rid")"
  [[ -d "$rd" ]] || die "run-id 없음: $rid"
  echo "run-id: $rid"
  echo "path:   $rd"
  # fan-out 드라이버(관찰성: 자동 선택·override·안전 강등 결과). 마커 없으면 레거시 기본.
  echo "driver: $(cat "$rd/DRIVER" 2>/dev/null || echo foreground-batch)"
  echo ""
  # 모델 주도: dispatch 는 서브에이전트의 결과만 받으므로 오케스트레이션 상태(STATE)만 보고한다.
  # (loop 은 서브에이전트가 자기 컨텍스트에서 호출하므로 dispatch 가 직접 들여다보지 않는다.)
  printf "%-6s %-10s %s\n" "WAVE" "STATE" "SPEC"
  printf "%-6s %-10s %s\n" "----" "------" "----"
  local w sp st
  while IFS=$'\t' read -r w sp; do
    w="${w#wave=}"
    st="$(get_state "$rd" "$sp")"
    printf "wave=%-2s %-10s %s\n" "$w" "$st" "$sp"
  done < "$rd/WAVES.txt"
}

# ----- subcommand: driver -----
# cmd_driver <run-id> — run 의 fan-out 드라이버(strong-parallel|background|foreground-batch)
#   를 출력(관찰성: 자동 선택·override·안전 강등 결과). 마커 없는 레거시 run 은 foreground-batch.
cmd_driver() {
  local rid="${1:-}"
  [[ -z "$rid" ]] && die "사용: $0 driver <run-id>"
  require_git_root
  local rd; rd="$(run_dir "$rid")"
  [[ -d "$rd" ]] || die "run-id 없음: $rid"
  if [[ -f "$rd/DRIVER" ]]; then
    cat "$rd/DRIVER"
  else
    echo "foreground-batch"
  fi
}

# ----- subcommand: stop -----

cmd_stop() {
  local rid="${1:-}"
  [[ -z "$rid" ]] && die "사용: $0 stop <run-id>"
  require_git_root
  # 모델 주도: 서브에이전트는 모델이 spawn/stop 한다. dispatch.sh 의 stop 은 오케스트레이션
  # 상태에서 running SPEC 을 failed 로 표시하고, 그 이행적 의존자는 skipped 로 전파한다
  # (모델이 이 신호를 보고 그 SPEC 의 서브에이전트를 멈춘다).
  local RD; local -a SP=() DEP_IDX=()
  load_run "$rid"
  local any=0 i st
  for ((i=0; i<${#SP[@]}; i++)); do
    st="$(get_state "$RD" "${SP[i]}")"
    if [[ "$st" == "running" ]]; then
      set_state "$RD" "${SP[i]}" "failed"
      log_event "$RD" "stop $(spec_slug "${SP[i]}")"
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
  # 읽기 전용 폴러: 상태를 전진시키지 않는다(전진은 모델의 ready/mark 가 소유). 모든 SPEC 이
  # terminal(done/failed/skipped)에 도달할 때까지 대기하고 결과를 exit code 로 대표한다.
  #   0=전부 done, 1=failed/skipped 있음, 2=timeout.
  local start; start=$(date +%s)
  while true; do
    local all_terminal=1 any_fail=0 sp st
    while IFS= read -r sp; do
      st="$(get_state "$rd" "$sp")"
      case "$st" in
        done) ;;
        failed|skipped) any_fail=1 ;;  # terminal(비완료).
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

# cmd_sweep [--target-branch <b>] — dispatch 자기 출처 작업 브랜치 중 대상에 머지된 것 일괄 정리.
#   명시 요청 정비 진입점(자동 무인 파괴 아님). 실제 삭제·식별은 결정적 머지 헬퍼(merge.sh sweep)
#   가 소유한다 — dispatch.sh 는 대상 브랜치 결정만 하고 raw 원격 명령으로 직접 삭제하지 않는다.
cmd_sweep() {
  local target=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target-branch) target="${2:-}"; shift 2 || die "사용: $0 sweep [--target-branch <branch>]" ;;
      -h|--help) echo "사용: $0 sweep [--target-branch <branch>]" >&2; return 0 ;;
      *) die "sweep: 알 수 없는 인자: $1 (사용: $0 sweep [--target-branch <branch>])" ;;
    esac
  done
  [[ -n "$target" ]] || target="${DEFAULT_BRANCH:-main}"
  DEFAULT_BRANCH="$target" bash "$SCRIPT_DIR/merge.sh" sweep "$target"
}

# =====================================================================
# selftest — 결정적 오케스트레이션 검증(모델 주도). 실제 spawn·머지·PR 미수행.
#   dispatch.sh 는 결정적 셋업(start)·readiness(ready)·전이(mark) 헬퍼만 제공하고,
#   서브에이전트 spawn·구현·리뷰·머지는 모델(Agent 도구)이 소유한다(계약: references/subagent-prompt.md).
#   따라서 여기서는 통합·리뷰·머지 bash 드레인을 검증하지 않는다(그 동작은 서브에이전트 소유
#   이며 helper 모듈 integration/review-loop/merge.sh 의 자체 selftest 가 검증).
#   완료 조건 1·9·12 의 결정적 부분을 검증:
#     S1 start=셋업 전용(스스로 done 으로 드라이브하지 않음) + 마커 생성.
#     S2 모델 루프(ready→mark): done(=머지)된 뒤에만 의존자 ready(의존자 해제 게이트).
#     S3 이행적 실패 격리: A failed → B(dep A) skipped, 독립 가지 C 는 계속.
#     S4 동시성 상한(MAX_PARALLEL 마커 + sticky + ready 가 존중).
#     S5 대상 브랜치(기본/지정) + 서브모드(forge/direct) 마커 + --resume sticky.
#     S6 depends_on cycle → abort(실행 셋업 안 함).
#     S7 bash 드레인·레거시 경로 부재(integrating 상태·NO_INTEGRATE 마커 없음, no-op 플래그).
# =====================================================================
cmd_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local DSP="$SCRIPT_DIR/dispatch.sh"

  # 격리 git 저장소 + SPEC: A(무dep), B(dep A), C(무dep 독립).
  local REPO="$TMP/repo"; mkdir -p "$REPO"
  ( cd "$REPO" && git init -q )
  printf -- '---\n---\n# Feature A\n' > "$REPO/feature-a.md"
  printf -- '---\ndepends_on: [feature-a]\n---\n# Feature B\n' > "$REPO/feature-b.md"
  printf -- '---\n---\n# Feature C\n' > "$REPO/feature-c.md"

  local fail=0
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  run_state() { # <run_dir> <spec-basename>
    local rd="$1" sp key; sp="$REPO/$2"
    key="$(spec_slug "$sp")-$(hash7 "$sp")"
    cat "$rd/state.$key" 2>/dev/null || echo "MISSING"
  }
  latest_run() { ls -1dt "$REPO"/.dispatch/runs/*/ 2>/dev/null | head -1 | sed 's:/$::'; }
  marker()  { cat "$1/INTEGRATE" 2>/dev/null; }
  tmarker() { cat "$1/TARGET_BRANCH" 2>/dev/null; }
  mpmarker(){ cat "$1/MAX_PARALLEL" 2>/dev/null; }
  start_rid() { # cd repo 에서 start 하고 run-id 를 반환(stdout 의 "run-id: X" 파싱).
    ( cd "$REPO" && "$@" ) | sed -n 's/^run-id: //p'
  }
  dsp() { env DISPATCH_POLL_SECONDS=0 DISPATCH_WAVE_TIMEOUT_SECONDS=120 "$@"; }
  rdy() { ( cd "$REPO" && dsp bash "$DSP" ready "$@" 2>/dev/null ); }
  mk() { ( cd "$REPO" && dsp bash "$DSP" mark "$@" ) >/dev/null 2>&1; }

  # ---- S1: start = 셋업 전용 (스스로 done 으로 드라이브하지 않음) + 마커 ----
  rm -rf "$REPO/.dispatch"
  local rid1; rid1="$( start_rid dsp bash "$DSP" start feature-a.md feature-b.md )"
  local rd1; rd1="$(latest_run)"
  [[ -n "$rid1" && -d "$rd1" ]] && ok "S1 start: run-id·run-dir 생성" || bad "S1 start: run-id 생성 got=[$rid1]"
  [[ "$(run_state "$rd1" feature-a.md)" == "pending" ]] && ok "S1 start: A 셋업 직후 pending(미드라이브)" || bad "S1 start: A pending got=$(run_state "$rd1" feature-a.md)"
  [[ "$(run_state "$rd1" feature-b.md)" == "pending" ]] && ok "S1 start: B 셋업 직후 pending" || bad "S1 start: B pending got=$(run_state "$rd1" feature-b.md)"
  [[ -f "$rd1/MANIFEST.txt" && -f "$rd1/WAVES.txt" ]] && ok "S1 start: MANIFEST·WAVES 생성" || bad "S1 start: MANIFEST·WAVES 생성"
  [[ "$(grep -c . "$rd1/MANIFEST.txt")" == "2" ]] && ok "S1 start: MANIFEST 2 SPEC" || bad "S1 start: MANIFEST 2"
  [[ -f "$rd1/MAX_PARALLEL" ]] && ok "S1 start: MAX_PARALLEL 마커" || bad "S1 start: MAX_PARALLEL 마커"

  # ---- S2: 모델 루프(ready→mark) — done(=머지)된 뒤에만 의존자 ready(의존자 해제) ----
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

  # ---- S3: 이행적 실패 격리 — A failed → B skipped, 독립 C 는 계속 ----
  rm -rf "$REPO/.dispatch"
  local rid3; rid3="$( start_rid dsp bash "$DSP" start feature-a.md feature-b.md feature-c.md )"
  local rd3; rd3="$(latest_run)"
  mk "$rid3" failed "$REPO/feature-a.md"
  [[ "$(run_state "$rd3" feature-b.md)" == "skipped" ]] && ok "S3 mark failed: B(dep A) 이행적 skipped" || bad "S3 B skipped got=$(run_state "$rd3" feature-b.md)"
  [[ "$(run_state "$rd3" feature-c.md)" == "pending" ]] && ok "S3 독립 C 는 pending(계속)" || bad "S3 C pending got=$(run_state "$rd3" feature-c.md)"
  r="$(rdy "$rid3")"
  printf '%s\n' "$r" | grep -q 'feature-c.md' && ok "S3 ready: 독립 C 는 준비됨(가지 격리)" || bad "S3 ready C got=[$r]"
  printf '%s\n' "$r" | grep -q 'feature-b.md' && bad "S3 ready: skipped B 는 미준비" || ok "S3 ready: skipped B 미준비"

  # ---- S4: 동시성 상한 (MAX_PARALLEL 마커 + sticky + ready 존중) ----
  rm -rf "$REPO/.dispatch"
  local rid4; rid4="$( start_rid dsp bash "$DSP" start --max-parallel 1 feature-a.md feature-c.md )"
  local rd4; rd4="$(latest_run)"
  [[ "$(mpmarker "$rd4")" == "1" ]] && ok "S4 MAX_PARALLEL 마커=1" || bad "S4 MAX_PARALLEL got=$(mpmarker "$rd4")"
  r="$(rdy "$rid4")"
  [[ "$(printf '%s\n' "$r" | grep -c 'feature-')" == "1" ]] && ok "S4 ready: 상한 1 → 1개만(마커 기본값 존중)" || bad "S4 ready 상한 got=[$r]"
  # 하나 running 표시 후 ready 는 비어야(상한 도달).
  mk "$rid4" running "$(printf '%s\n' "$r" | head -1)"
  r="$(rdy "$rid4")"
  [[ "$(printf '%s\n' "$r" | grep -c 'feature-')" == "0" ]] && ok "S4 ready: 상한 도달 시 빈 출력" || bad "S4 ready 상한도달 got=[$r]"
  # --max-parallel 명시는 마커보다 우선(상한 2 → 둘 다, 단 running 1 제외 → 1).
  r="$( ( cd "$REPO" && dsp bash "$DSP" ready "$rid4" --max-parallel 2 2>/dev/null ) )"
  [[ "$(printf '%s\n' "$r" | grep -c 'feature-')" == "1" ]] && ok "S4 ready: 명시 상한 2 + running 1 → 1개" || bad "S4 명시 상한 got=[$r]"
  # resume sticky: --max-parallel 미지정 재개해도 마커 1 유지.
  ( cd "$REPO" && dsp bash "$DSP" start --resume "$rid4" ) >/dev/null 2>&1 || true
  [[ "$(mpmarker "$rd4")" == "1" ]] && ok "S4 resume: MAX_PARALLEL sticky(마커 유지)" || bad "S4 resume sticky got=$(mpmarker "$rd4")"

  # ---- S5: 대상 브랜치 + 서브모드 마커 + --resume sticky ----
  # 기본 대상 = main.
  rm -rf "$REPO/.dispatch"
  local ridm; ridm="$( start_rid dsp bash "$DSP" start feature-a.md )"
  local rdm; rdm="$(latest_run)"
  [[ "$(tmarker "$rdm")" == "main" ]] && ok "S5 기본 대상 브랜치=main 마커" || bad "S5 기본 대상=main got=$(tmarker "$rdm")"
  # 지정 대상 = release + 미구성(direct) 서브모드.
  rm -rf "$REPO/.dispatch"
  local ridr; ridr="$( start_rid dsp env FORGE_BIN=__noforge__ bash "$DSP" start --target-branch release feature-a.md feature-b.md )"
  local rdr; rdr="$(latest_run)"
  [[ "$(tmarker "$rdr")" == "release" ]] && ok "S5 지정 대상 브랜치=release 마커" || bad "S5 대상=release got=$(tmarker "$rdr")"
  [[ "$(marker "$rdr")" == "direct" ]] && ok "S5 forge 백엔드 미가용(FORGE_BIN) → submode=direct" || bad "S5 submode=direct got=$(marker "$rdr")"
  # 대상 브랜치 resume sticky: 플래그 없이/다른 env 로 재개해도 release 유지.
  local ridr2; ridr2="$(basename "$rdr")"
  ( cd "$REPO" && dsp env DEFAULT_BRANCH=main bash "$DSP" start --resume "$ridr2" ) >/dev/null 2>&1 || true
  [[ "$(tmarker "$rdr")" == "release" ]] && ok "S5 resume: 대상 브랜치 release sticky(env 보다 우선)" || bad "S5 resume 대상 sticky got=$(tmarker "$rdr")"
  # forge 백엔드 가용(forge CLI) → submode=forge — approver 불필요(정상화). + resume sticky.
  rm -rf "$REPO/.dispatch"
  local ridf; ridf="$( start_rid dsp env FORGE_BIN=bash bash "$DSP" start feature-a.md )"
  local rdf; rdf="$(latest_run)"
  [[ "$(marker "$rdf")" == "forge" ]] && ok "S5 forge 백엔드 가용 → submode=forge(approver 불필요)" || bad "S5 submode=forge got=$(marker "$rdf")"
  rm -rf "$REPO/.dispatch"
  local ridd; ridd="$( start_rid dsp env FORGE_BIN=__noforge__ bash "$DSP" start feature-a.md )"
  local rdd; rdd="$(latest_run)"; local riddb; riddb="$(basename "$rdd")"
  ( cd "$REPO" && dsp env FORGE_BIN=bash bash "$DSP" start --resume "$riddb" ) >/dev/null 2>&1 || true
  [[ "$(marker "$rdd")" == "direct" ]] && ok "S5 resume: submode direct sticky(forge 가용 env 보다 마커 우선)" || bad "S5 resume submode sticky got=$(marker "$rdd")"

  # ---- S6: depends_on cycle → abort(실행 셋업 안 함) ----
  rm -rf "$REPO/.dispatch"
  printf -- '---\ndepends_on: [cyc-y]\n---\n# X\n' > "$REPO/cyc-x.md"
  printf -- '---\ndepends_on: [cyc-x]\n---\n# Y\n' > "$REPO/cyc-y.md"
  if ( cd "$REPO" && dsp bash "$DSP" start cyc-x.md cyc-y.md ) >/dev/null 2>&1; then
    bad "S6 cycle: abort 해야(비-0 종료)"
  else
    ok "S6 cycle: abort(비-0 종료)"
  fi
  rm -f "$REPO/cyc-x.md" "$REPO/cyc-y.md"

  # ---- S8: watch(읽기 전용 폴러)·stop(running→failed + 이행적 skip) — 모델 주도 의미 ----
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

  # ---- S7: bash 드레인·레거시 경로 부재 ----
  rm -rf "$REPO/.dispatch"
  local rid7; rid7="$( start_rid dsp bash "$DSP" start --no-integrate --integrate feature-a.md feature-b.md )"
  local rd7; rd7="$(latest_run)"
  [[ -n "$rid7" ]] && ok "S7 --no-integrate/--integrate no-op(받되 셋업 진행)" || bad "S7 no-op 플래그 셋업"
  [[ ! -f "$rd7/NO_INTEGRATE" ]] && ok "S7 NO_INTEGRATE 마커 부재(레거시 경로 없음)" || bad "S7 NO_INTEGRATE 마커 부재"
  # 셋업만 한 직후 어떤 SPEC 도 integrating/done 으로 자동 전이되지 않음(드레인 없음).
  if grep -rqx 'integrating' "$rd7"/state.* 2>/dev/null; then bad "S7 integrating 상태 부재(드레인 없음)"; else ok "S7 integrating 상태 부재(bash 드레인 없음)"; fi
  if grep -rqx 'done' "$rd7"/state.* 2>/dev/null; then bad "S7 셋업 직후 자동 done 부재"; else ok "S7 셋업 직후 자동 done 부재(start 미드라이브)"; fi

  # ---- S9: fan-out 드라이버 — 기본=동적 선호·강등 신호·override·resume sticky ----
  # 기본 선호는 strong-parallel(동적 Workflow). 자동 감지는 모델의 환경 판정에 둔다 → 동적/백그라운드
  # 실행 불가일 때만 강등 신호(DISPATCH_NO_STRONG_PARALLEL/DISPATCH_NO_BACKGROUND)로 표현.
  # override 는 DISPATCH_DRIVER(기존 시작 CLI 불변). 강등 사슬: strong-parallel → background → foreground-batch.
  drv_marker() { cat "$1/DRIVER" 2>/dev/null; }
  drv_cmd()    { ( cd "$REPO" && dsp bash "$DSP" driver "$1" 2>/dev/null ); }

  # S9a: 신호 없음 → 기본 선호 strong-parallel(동적 선호로 역전; 과거 foreground-batch 폴백 아님).
  rm -rf "$REPO/.dispatch"
  local rid9a; rid9a="$( start_rid dsp env DISPATCH_DRIVER= DISPATCH_NO_STRONG_PARALLEL= DISPATCH_NO_BACKGROUND= bash "$DSP" start feature-a.md )"
  local rd9a; rd9a="$(latest_run)"
  [[ "$(drv_marker "$rd9a")" == "strong-parallel" ]] \
    && ok "S9a 신호 없음 → 기본 strong-parallel(동적 선호)" \
    || bad "S9a 기본 선호 got=$(drv_marker "$rd9a")"
  [[ "$(drv_cmd "$rid9a")" == "strong-parallel" ]] \
    && ok "S9a driver 서브커맨드=strong-parallel" \
    || bad "S9a driver 서브커맨드 got=$(drv_cmd "$rid9a")"

  # S9b: DISPATCH_NO_STRONG_PARALLEL=1(동적 불가) → background 로 강등.
  rm -rf "$REPO/.dispatch"
  local rid9b; rid9b="$( start_rid dsp env DISPATCH_DRIVER= DISPATCH_NO_STRONG_PARALLEL=1 DISPATCH_NO_BACKGROUND= bash "$DSP" start feature-a.md )"
  local rd9b; rd9b="$(latest_run)"
  [[ "$(drv_marker "$rd9b")" == "background" ]] \
    && ok "S9b 동적 불가 → background 강등" \
    || bad "S9b background got=$(drv_marker "$rd9b")"

  # S9c: DISPATCH_NO_STRONG_PARALLEL=1 + DISPATCH_NO_BACKGROUND=1(둘 다 불가) → foreground-batch 종착.
  rm -rf "$REPO/.dispatch"
  local rid9c; rid9c="$( start_rid dsp env DISPATCH_DRIVER= DISPATCH_NO_STRONG_PARALLEL=1 DISPATCH_NO_BACKGROUND=1 bash "$DSP" start feature-a.md )"
  local rd9c; rd9c="$(latest_run)"
  [[ "$(drv_marker "$rd9c")" == "foreground-batch" ]] \
    && ok "S9c 동적·백그라운드 불가 → foreground-batch 종착" \
    || bad "S9c foreground-batch got=$(drv_marker "$rd9c")"

  # S9c2: DISPATCH_NO_BACKGROUND=1 만(동적 가용) → 기본 strong-parallel 유지(동적 가용이면 강등 안 함).
  rm -rf "$REPO/.dispatch"
  local rid9c2; rid9c2="$( start_rid dsp env DISPATCH_DRIVER= DISPATCH_NO_STRONG_PARALLEL= DISPATCH_NO_BACKGROUND=1 bash "$DSP" start feature-a.md )"
  local rd9c2; rd9c2="$(latest_run)"
  [[ "$(drv_marker "$rd9c2")" == "strong-parallel" ]] \
    && ok "S9c2 동적 가용이면 NO_BACKGROUND 무관하게 strong-parallel" \
    || bad "S9c2 strong-parallel got=$(drv_marker "$rd9c2")"

  # S9d: DISPATCH_DRIVER override → 강등 신호 무시하고 지정 드라이버 강제.
  rm -rf "$REPO/.dispatch"
  local rid9d; rid9d="$( start_rid dsp env DISPATCH_DRIVER=background DISPATCH_NO_STRONG_PARALLEL=1 DISPATCH_NO_BACKGROUND=1 bash "$DSP" start feature-a.md )"
  local rd9d; rd9d="$(latest_run)"
  [[ "$(drv_marker "$rd9d")" == "background" ]] \
    && ok "S9d override=background(강등 신호 무시)" \
    || bad "S9d override got=$(drv_marker "$rd9d")"

  # S9e: resume sticky — 최초 결정이 마커로 영속돼 재개 시 다른 env override 보다 우선.
  rm -rf "$REPO/.dispatch"
  local rid9e; rid9e="$( start_rid dsp env DISPATCH_DRIVER=strong-parallel bash "$DSP" start feature-a.md )"
  local rd9e; rd9e="$(latest_run)"
  ( cd "$REPO" && dsp env DISPATCH_DRIVER=foreground-batch bash "$DSP" start --resume "$rid9e" ) >/dev/null 2>&1 || true
  [[ "$(drv_marker "$rd9e")" == "strong-parallel" ]] \
    && ok "S9e resume: driver sticky(override env 무시)" \
    || bad "S9e resume sticky got=$(drv_marker "$rd9e")"

  # S9f: 무효 override → 즉시 abort(비-0).
  rm -rf "$REPO/.dispatch"
  local rc9f=0; ( cd "$REPO" && dsp env DISPATCH_DRIVER=bogus bash "$DSP" start feature-a.md ) >/dev/null 2>&1 || rc9f=$?
  [[ "$rc9f" -ne 0 ]] && ok "S9f 무효 override → abort(비-0)" || bad "S9f 무효 override abort got=$rc9f"

  # ---- S10: 안전 강등 관찰 가능성 — 어느 드라이버로 갔는지 driver 커맨드/status 로 관찰 ----
  rm -rf "$REPO/.dispatch"
  local rid10; rid10="$( start_rid dsp env DISPATCH_DRIVER=strong-parallel bash "$DSP" start feature-a.md feature-b.md )"
  [[ "$(drv_cmd "$rid10")" == "strong-parallel" ]] \
    && ok "S10 driver 관찰(strong-parallel)" \
    || bad "S10 driver 관찰 got=$(drv_cmd "$rid10")"
  # 강등 종착(foreground-batch)도 관찰 가능.
  rm -rf "$REPO/.dispatch"
  local rid10b; rid10b="$( start_rid dsp env DISPATCH_DRIVER=foreground-batch bash "$DSP" start feature-a.md )"
  [[ "$(drv_cmd "$rid10b")" == "foreground-batch" ]] \
    && ok "S10 강등 종착 관찰(foreground-batch)" \
    || bad "S10 강등 종착 관찰 got=$(drv_cmd "$rid10b")"
  # status 출력에 driver 라인 포함(관찰성). 출력을 캡처 후 검사(grep -q 조기 종료에 의한
  # SIGPIPE+pipefail 오탐 회피).
  local s10status; s10status="$( cd "$REPO" && dsp bash "$DSP" status "$rid10b" 2>/dev/null )"
  case "$s10status" in
    *"driver: foreground-batch"*) ok "S10 status 에 driver 라인" ;;
    *) bad "S10 status driver 라인 부재" ;;
  esac

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
        결정적 셋업 전용: 1 개 이상의 SPEC 경로를 받아 depends_on 으로 DAG 를 만들고
        run-dir·WAVES.txt(진단)·초기 pending 상태·run 전역 마커(서브모드 INTEGRATE /
        대상 브랜치 TARGET_BRANCH / MAX_PARALLEL)를 생성한 뒤 run-id 를 출력한다.
        스스로 spawn·드레인하지 않는다 — 준비된 SPEC당 서브에이전트 spawn·구현·리뷰·머지는
        모델(dispatch 스킬)이 ready/mark + Agent 도구로 소유한다(계약: references/subagent-prompt.md).
        --target-branch 로 대상 브랜치 지정(미지정 시 기본 브랜치). 서브모드·대상 브랜치·
        동시성 상한은 --resume 에서 sticky(run-dir 마커). 하위호환 --integrate/--no-integrate
        는 받되 무시(no-op). cycle 이면 abort.
  ready <run-id> [--max-parallel N]
        지금 서브에이전트를 띄울 준비가 된 SPEC(모든 dep done & pending & 동시성 상한 이내)
        abspath 를 한 줄씩 출력(결정적, skip 전파 적용). 모델이 각 SPEC 에 서브에이전트 1개 spawn.
        --max-parallel 미지정이면 start 가 영속한 MAX_PARALLEL 마커를 기본값으로 쓴다(sticky).
  mark <run-id> <running|done|failed> <spec>
        SPEC 상태 전이(결정적). running=spawn 직전, done=서브에이전트 머지 보고(=의존자 해제),
        failed=비완료 보고 → 이행적 의존자만 skipped 전파.
  list
        모든 run-id 와 진행 요약.
  status <run-id>
        run-id 단위 per-SPEC state(진단용 wave 표시 포함) + fan-out 드라이버.
  driver <run-id>
        run 의 fan-out 드라이버(strong-parallel|background|foreground-batch) 출력
        (관찰성: 자동 선택·override·안전 강등 결과).
  stop <run-id>
        running SPEC 을 failed 로 표시하고 이행적 의존자를 skipped 전파(모델이 그 서브에이전트
        를 멈춘다). dispatch.sh 는 오케스트레이션 상태만 갱신한다.
  watch <run-id>
        per-SPEC 상태를 읽기 전용으로 폴링하며 모든 SPEC 이 terminal(done/failed/skipped)에
        도달할 때까지 대기(상태 전진은 모델의 ready/mark 소유). exit 0=전부 done, 1=실패 있음, 2=timeout.
  sweep [--target-branch <b>]
        dispatch 자기 출처 작업 브랜치 중 대상 브랜치(미지정 시 DEFAULT_BRANCH)에 이미 머지된
        것만 force 없이 일괄 삭제(누적 stale 브랜치 소급 정리). dispatch 가 만들지 않은 브랜치·
        미머지 브랜치는 보존하고, 부분 실패는 경고로 격리한다. 명시 요청 정비 진입점(merge.sh
        결정적 헬퍼가 식별·삭제 소유). 어떤 브랜치를 지웠고 건너뛰었는지(미머지·실패) 보고한다.

환경 변수:
  DISPATCH_POLL_SECONDS, DISPATCH_WAVE_TIMEOUT_SECONDS, FORGE_BIN, DEFAULT_BRANCH
  DISPATCH_DRIVER       fan-out 드라이버 override(strong-parallel|background|foreground-batch).
                        기존 시작 CLI 불변 — override 는 이 env 로만 받는다.
  DISPATCH_NO_STRONG_PARALLEL=1  동적 불가 강등 신호(모델 자동 감지) → background.
  DISPATCH_NO_BACKGROUND=1       추가 강등 신호(NO_STRONG_PARALLEL 과 함께) → foreground-batch.
                        신호가 없으면 기본 선호 strong-parallel(동적 Workflow).
                        강등 사슬: strong-parallel → background → foreground-batch.
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
  list)   cmd_list  ;;
  status) cmd_status "$@" ;;
  driver) cmd_driver "$@" ;;
  stop)   cmd_stop   "$@" ;;
  watch)  cmd_watch  "$@" ;;
  sweep)  cmd_sweep  "$@" ;;
  selftest) cmd_selftest ;;
  -h|--help|help) usage ;;
  *) echo "알 수 없는 subcommand: $SUB" >&2; usage ;;
esac
