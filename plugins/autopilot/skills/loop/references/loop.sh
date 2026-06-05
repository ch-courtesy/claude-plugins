#!/usr/bin/env bash
# loop.sh — 스펙 파일 기반 로컬 자율 루프 드라이버 (subcommand 기반)
#
# 사용:
#   bash .../loop/references/loop.sh start  <spec-path> [--max-iterations N] [--wall-clock-minutes N]
#   bash .../loop/references/loop.sh status [<spec-path>]
#   bash .../loop/references/loop.sh stop   <spec-path>
#   bash .../loop/references/loop.sh list
#   bash .../loop/references/loop.sh cleanup <spec-path> [--force]
#   bash .../loop/references/loop.sh logs   <spec-path> [--iter N]
#
# 정체성: 스펙 파일의 절대 경로.
# 작업 공간: <spec 디렉토리>/.worktree (호출 위치와 무관하게 항상 전용 워크트리 생성).
# 이터 간 노트: <WT>/.loop/notes.md. 워커 terminal 신호: <WT>/.loop/signals/ 디렉토리.
#
# 환경 변수:
#   MAX_ITERATIONS         이터 상한 (기본: 30)
#   WALL_CLOCK_MINUTES     시계 캡 (기본: 120)
#   CODEX_FAIL_STREAK_LIMIT  codex 비정상 exit 연속 허용 (기본: 3)

set -euo pipefail

# ----- 스크립트 자신의 디렉토리 (references/) -----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----- 워커 Codex 세션 -----
# 무인 이터 워커는 Codex sandbox 기반으로 실행한다. legacy tool allow-list 모델은
# Codex CLI에 1:1 대응하지 않으므로 --sandbox workspace-write와 --ask-for-approval never로
# 자동 루프에 필요한 비대화형 실행 경계를 고정한다.

# ----- 헬퍼 -----
die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' 명령이 필요합니다."
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# 해시 유틸 — macOS 기본은 sha256sum 미지원, shasum이 표준.
if command -v sha256sum >/dev/null 2>&1; then
  HASH_BIN="sha256sum"; HASH_ARGS=()
elif command -v shasum >/dev/null 2>&1; then
  HASH_BIN="shasum"; HASH_ARGS=(-a 256)
else
  HASH_BIN=""; HASH_ARGS=()
fi

# 스펙 절대 경로 → 안정적 12자 키.
spec_key() {
  local abs="$1"
  if [[ -n "$HASH_BIN" ]]; then
    printf '%s' "$abs" | "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} | awk '{print substr($1,1,12)}'
  else
    # 해시 도구 부재 시 경로를 sanitize한 fallback (충돌 가능성 낮음).
    printf '%s' "$abs" | tr -c 'a-zA-Z0-9' '-' | awk '{print substr($0,1,40)}'
  fi
}

# ----- 의존성 검사 -----
# git은 모든 subcommand가 쓴다(compute_paths). yq·codex는 start의 게이트·이터에서만
# 필요하므로 cmd_start에서 늦게 검사한다 — status/list/stop/cleanup/logs와 테스트의
# 함수 source가 codex·yq 부재에도 동작하도록.
require_tool git

# ----- 시그널 처리: SIGTERM/SIGINT 시 자식 트리 정리 (orphan 방지) -----
kill_descendants() {
  local parent="$1" child
  for child in $(pgrep -P "$parent" 2>/dev/null || true); do
    kill_descendants "$child"
    kill -TERM "$child" 2>/dev/null || true
  done
}

on_signal_exit() {
  [[ -n "${CODEX_PID:-}" ]] && kill_descendants "$CODEX_PID"
  exit 130
}

# ----- 경로·정체성 계산 -----
# 입력: 스펙 파일 경로. 출력 전역:
#   SPEC_PATH        스펙 절대 경로 (정체성)
#   SPEC_DIR         스펙 디렉토리 절대 경로
#   WT               작업 공간 (<SPEC_DIR>/.worktree — 항상 전용 워크트리)
#   LOOP_DIR         <WT>/.loop (노트·신호·메타)
#   LOCK_FILE        <SPEC_DIR>/.loop-lock (실행 중에만; 워크트리 생성 전에 획득해 race 보호)
compute_paths() {
  local input="$1"
  [[ -n "$input" ]] || die "스펙 파일 경로가 필요합니다."

  # 절대 경로화 (파일이 아직 없을 수도 있는 status/list 외 경로는 start에서 존재 검증).
  if [[ -f "$input" ]]; then
    local d b
    d="$(cd "$(dirname "$input")" && pwd)"
    b="$(basename "$input")"
    SPEC_PATH="$d/$b"
  else
    # 비존재 입력도 키 계산은 가능하도록 정규화 시도 (디렉토리 존재 시).
    local d b
    d="$(cd "$(dirname "$input")" 2>/dev/null && pwd || echo "")"
    b="$(basename "$input")"
    [[ -n "$d" ]] && SPEC_PATH="$d/$b" || SPEC_PATH="$input"
  fi

  SPEC_DIR="$(dirname "$SPEC_PATH")"

  # 스펙 디렉토리가 git 저장소 안이어야 함 (워크트리 생성·게이트에 필요).
  git -C "$SPEC_DIR" rev-parse --git-common-dir >/dev/null 2>&1 \
    || die "스펙 파일이 git 저장소 안에 있어야 합니다: $SPEC_PATH"

  WT="$SPEC_DIR/.worktree"
  LOOP_DIR="$WT/.loop"
  LOCK_FILE="$SPEC_DIR/.loop-lock"   # 스펙 디렉토리에 colocate — 워크트리 생성 전에 획득해 race 보호
}

# 실제 WT 영구 메타 읽기 — start 가 작성한 <SPEC_DIR>/.loop-wt 가 있으면 그 값으로
# WT·LOOP_DIR 를 재설정한다. 어느 cwd 에서 follow-up 명령이 와도 동일한 작업 공간을
# 가리키게 만드는 핵심. cmd_status·logs·cleanup·paths 등 compute_paths 다음에 호출.
# 반환: 0 = 메타 적용함, 1 = 메타 없음(기본값 유지).
resolve_actual_wt() {
  local wtfile="$SPEC_DIR/.loop-wt"
  [[ -f "$wtfile" ]] || return 1
  # 끝 개행만 제거 — 경로 내부 공백·탭은 보존(spec/worktree 경로에 공백 가능).
  # read 는 trailing newline 없는 마지막 줄에서 non-zero 를 반환하지만 변수에는
  # 값이 채워져 있다 → '|| true' 로 exit code 만 무시하고 값은 보존.
  local actual=""
  IFS= read -r actual < "$wtfile" 2>/dev/null || true
  [[ -n "$actual" ]] || return 1
  WT="$actual"
  LOOP_DIR="$WT/.loop"
  return 0
}

# ----- 동시성 락 -----
acquire_lock() {
  # stale lock 정리 (PID 비활성 시)
  if [[ -f "$LOCK_FILE" ]]; then
    local old_pid
    old_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      die "이미 실행 중입니다 (PID $old_pid): $SPEC_PATH\n정지: $0 stop $SPEC_PATH"
    fi
    echo "[$(now_iso)] WARN: stale lock 정리 (PID ${old_pid:-?} 비활성)" >&2
    rm -f "$LOCK_FILE"
  fi
  # 원자적 획득 (noclobber): 두 start 동시 진입 시 한 쪽만 성공.
  ( set -C; echo "$$" > "$LOCK_FILE" ) 2>/dev/null \
    || die "lock 획득 실패 (race): $LOCK_FILE"
  # EXIT trap으로 lock 해제. 작업 공간(.worktree/)은 cleanup까지 유지.
  trap 'rm -f "$LOCK_FILE"' EXIT
  trap on_signal_exit INT TERM
}

# ----- 게이트 헬퍼 -----
# 스펙 frontmatter(첫 --- ~ 둘째 ---) 추출.
# SPEC_PATH 는 드라이버 프로세스 생애 동안 불변(워커는 스펙 편집 금지)이므로
# SPEC_PATH 키로 1회만 sed 파싱하고 캐시한다 — 이터당 ~7회 호출되던 재파싱 제거.
read_scope_yaml() {
  if [[ "${_SCOPE_YAML_KEY:-}" == "$SPEC_PATH" ]]; then
    printf '%s\n' "$_SCOPE_YAML_CACHE"
    return
  fi
  _SCOPE_YAML_CACHE=$(sed -n '1,/^---$/{
    1d
    /^---$/d
    p
  }' "$SPEC_PATH" 2>/dev/null)
  _SCOPE_YAML_KEY="$SPEC_PATH"
  printf '%s\n' "$_SCOPE_YAML_CACHE"
}

# test_paths override 또는 기본 휴리스틱으로 기존 테스트 파일 목록.
list_test_files() {
  local scope_yaml test_override sweep
  scope_yaml=$(read_scope_yaml)
  test_override=$(echo "$scope_yaml" | yq '.test_paths[]' 2>/dev/null || true)
  sweep=$(list_sweep_files)

  local found
  if [[ -n "$test_override" ]]; then
    found=$(cd "$WT" && git ls-files -- $test_override 2>/dev/null || true)
  else
    found=$(cd "$WT" && git ls-files 2>/dev/null \
      | grep -Ei '(^|/)(tests?|spec|__tests__)/|[._-](test|spec)\.[a-z0-9]+$|_test\.[a-z0-9]+$' || true)
  fi
  # sweep 화이트리스트 파일은 weakening 비교 대상에서 제외.
  if [[ -n "$sweep" ]]; then
    comm -23 <(printf '%s\n' "$found" | sort -u) <(printf '%s\n' "$sweep" | sort -u) 2>/dev/null || printf '%s\n' "$found"
  else
    printf '%s\n' "$found"
  fi
}

list_sweep_files() {
  local scope_yaml sweep_patterns
  scope_yaml=$(read_scope_yaml)
  sweep_patterns=$(echo "$scope_yaml" | yq '.test_sweep_paths[]' 2>/dev/null || true)
  [[ -z "$sweep_patterns" ]] && return 0
  cd "$WT" && git ls-files -- $sweep_patterns 2>/dev/null || true
}

warn_sweep_no_match() {
  local sweep_declared
  sweep_declared=$(read_scope_yaml | yq 'has("test_sweep_paths")' 2>/dev/null || echo "false")
  [[ "$sweep_declared" != "true" ]] && return 0
  [[ -z "$(list_sweep_files)" ]] \
    && echo "[$(now_iso)] WARN: test_sweep_paths 선언됐으나 매칭 파일 없음 (패턴 오타 또는 신규 추가 전 상태 가능)" >&2 || true
}

hash_listed_files() {
  local files="$1"
  [[ -z "$files" ]] && { echo "no-files"; return; }
  echo "$files" \
    | xargs -I{} "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} "$WT/{}" 2>/dev/null \
    | "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} \
    | awk '{print $1}'
}

hash_deps() {
  local manifests
  manifests=$(find "$WT" -maxdepth 2 -type f \
    \( -name 'package.json' -o -name 'requirements.txt' -o -name 'Cargo.toml' \
       -o -name 'go.mod' -o -name 'pyproject.toml' -o -name 'Gemfile' \
       -o -name 'pom.xml' -o -name 'build.gradle' \) 2>/dev/null | sort)
  if [[ -z "$manifests" ]]; then
    echo "no-manifests"
  else
    echo "$manifests" | xargs -I{} "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} {} 2>/dev/null \
      | "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} | awk '{print $1}'
  fi
}

# 워크트리 생성 시점 부모 HEAD SHA. 게이트 diff 기준. <LOOP_DIR>/BASE_SHA 단일 파일.
read_base_sha() {
  local f="$LOOP_DIR/BASE_SHA"
  [[ -f "$f" ]] || return 1
  local sha
  sha=$(tr -d '[:space:]' < "$f" 2>/dev/null)
  [[ -n "$sha" ]] || return 1
  printf '%s' "$sha"
}

# 변경 파일이 scope.include 안인지 검사. 위반 파일 목록 출력(있으면).
diff_vs_scope() {
  local base_sha="$1"
  local scope_yaml include_patterns exclude_patterns committed working changed
  scope_yaml=$(read_scope_yaml)
  include_patterns=$(echo "$scope_yaml" | yq '.scope.include[]' 2>/dev/null || true)
  exclude_patterns=$(echo "$scope_yaml" | yq '.scope.exclude[]' 2>/dev/null || true)
  committed=$(cd "$WT" && git diff --name-only "$base_sha" HEAD 2>/dev/null || true)
  working=$(cd "$WT" && git diff --name-only HEAD 2>/dev/null || true)
  changed=$(printf '%s\n%s\n' "$committed" "$working" | sort -u | grep -v '^$' || true)
  [[ -z "$changed" ]] && return 0

  local out_of_scope=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    local excluded=0
    while IFS= read -r exc; do
      [[ -z "$exc" ]] && continue
      # shellcheck disable=SC2053
      if [[ "$file" == $exc ]]; then
        out_of_scope+="$file (excluded by $exc)\n"; excluded=1; break
      fi
    done <<< "$exclude_patterns"
    [[ $excluded -eq 1 ]] && continue

    local matched=0
    while IFS= read -r inc; do
      [[ -z "$inc" ]] && continue
      # shellcheck disable=SC2053
      if [[ "$file" == $inc ]]; then matched=1; break; fi
    done <<< "$include_patterns"
    [[ $matched -eq 0 ]] && out_of_scope+="$file (not in include)\n"
  done <<< "$changed"

  [[ -n "$out_of_scope" ]] && printf "%b" "$out_of_scope"
}

grep_new_suppressors() {
  local base_sha="$1"
  cd "$WT" || return
  {
    git diff "$base_sha" HEAD 2>/dev/null
    git diff HEAD 2>/dev/null
  } \
    | grep -E '^\+' \
    | grep -E '#[[:space:]]*noqa|@ts-ignore|eslint-disable|#pragma[[:space:]]+warning[[:space:]]+disable' \
    || true
}

check_secrets() {
  command -v gitleaks >/dev/null 2>&1 || return 0
  local base_sha="$1"
  {
    cd "$WT" && gitleaks detect --log-opts="$base_sha..HEAD" --no-banner 2>&1 || true
    cd "$WT" && gitleaks detect --staged --no-banner 2>&1 || true
  }
}

count_fix_symptom_streak() {
  cd "$WT" && git log --pretty=format:%s -2 2>/dev/null | { grep -c '^fix:symptom' || true; }
}

detect_oscillation() {
  local commits
  commits=$(cd "$WT" && git log --pretty=tformat:%H -4 2>/dev/null || true)
  [[ $(echo "$commits" | wc -l | tr -d ' ') -lt 4 ]] && return 0
  local sets=()
  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue
    sets+=("$(cd "$WT" && git diff-tree --no-commit-id --name-only -r "$commit" 2>/dev/null | sort | "$HASH_BIN" ${HASH_ARGS[@]+"${HASH_ARGS[@]}"} | awk '{print $1}')")
  done <<< "$commits"
  if [[ ${#sets[@]} -eq 4 ]] \
     && [[ "${sets[0]}" == "${sets[2]}" ]] \
     && [[ "${sets[1]}" == "${sets[3]}" ]] \
     && [[ "${sets[0]}" != "${sets[1]}" ]]; then
    echo "최근 4 커밋이 두 상태로 토글됨"
  fi
}

elapsed_minutes() {
  echo $(( ( $(date +%s) - START_TIME ) / 60 ))
}

# ----- halt (게이트 위반 시 driver 자체 정지) -----
# driver 는 워커 신호 파일을 만들지 않는다. stash + stderr + exit 1 만 한다.
# 워커 컨벤션(signals/)에 영향을 주지 않음 → SoT 가 constitution 에 머무름.
halt() {
  local reason="$1"
  echo "[$(now_iso)] HALT: $reason" >&2

  # 진행 중 변경 stash (있으면)
  local stash_before stash_after
  stash_before=$(cd "$WT" && git stash list 2>/dev/null | wc -l | tr -d ' ')
  (cd "$WT" && git add -A && git stash push -m "auto-stash by loop.sh halt: $reason" >/dev/null 2>&1) || true
  stash_after=$(cd "$WT" && git stash list 2>/dev/null | wc -l | tr -d ' ')
  if [[ $stash_after -gt $stash_before ]]; then
    echo "[$(now_iso)] WARN: 미커밋 변경이 stash에 보관됨 — 복구: cd $WT && git stash pop" >&2
  fi
  echo "[$(now_iso)] 진단: $LOOP_DIR/iterations/ 최근 로그 참조" >&2
  exit 1
}

# ----- 이터레이션 호출 -----
# 반환: 100 = signals/ 에 파일 있음(워커 terminal), 0 = 계속. 게이트 위반 시 halt(exit 1).
# driver 는 signals/ 파일 이름·내용을 보지 않는다(워커 컨벤션은 constitution SoT).
iterate() {
  local n
  n=$(($(find "$LOOP_DIR/iterations" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ') + 1))
  echo "[$(now_iso)] 이터 #$n 시작"
  warn_sweep_no_match

  local start_test_files start_hash_tests start_hash_deps
  start_test_files=$(list_test_files)
  start_hash_tests=$(hash_listed_files "$start_test_files")
  start_hash_deps=$(hash_deps)

  local exit_code=0
  (
    cd "$WT"
    exec codex exec \
      --cd "$WT" \
      --sandbox workspace-write \
      --ask-for-approval never \
      - \
      < "$SPEC_PATH" \
      > ".loop/iterations/$n.log" 2>&1
  ) &
  CODEX_PID=$!
  wait "$CODEX_PID" || exit_code=$?
  CODEX_PID=""

  echo "[$(now_iso)] 이터 #$n 종료 (exit: $exit_code). 게이트 검사..."

  if [[ $exit_code -ne 0 ]]; then
    CODEX_FAIL_STREAK=$((CODEX_FAIL_STREAK + 1))
    echo "WARN: codex 비정상 exit (연속 $CODEX_FAIL_STREAK회). .loop/iterations/$n.log 확인."
    if [[ $CODEX_FAIL_STREAK -ge ${CODEX_FAIL_STREAK_LIMIT:-3} ]]; then
      halt "codex 비정상 exit ${CODEX_FAIL_STREAK}회 연속 (rate limit·네트워크·인증 의심)."
    fi
  else
    CODEX_FAIL_STREAK=0
  fi

  # 워커 terminal: signals/ 디렉토리가 비어있지 않으면 정지(파일 이름·내용 미파싱).
  [[ -n "$(ls "$LOOP_DIR/signals" 2>/dev/null)" ]] && return 100

  # 객관 게이트
  if [[ "$start_hash_tests" != "no-files" ]] \
     && [[ "$(hash_listed_files "$start_test_files")" != "$start_hash_tests" ]]; then
    halt "테스트 약화 — 기존 테스트 파일 변경 감지 (삭제·수정 의심)"
  fi
  if [[ "$start_hash_deps" != "no-manifests" ]] \
     && [[ "$(hash_deps)" != "$start_hash_deps" ]]; then
    halt "의존성 변경 — 매니페스트 해시 변경"
  fi

  local base_sha
  if ! base_sha=$(read_base_sha); then
    halt "BASE SHA 메타 부재 — $LOOP_DIR/BASE_SHA 없음. cleanup 후 재생성 필요."
  fi

  local out_of_scope new_supp streak osc
  out_of_scope=$(diff_vs_scope "$base_sha")
  [[ -n "$out_of_scope" ]] && halt "Scope 위반: $out_of_scope"
  new_supp=$(grep_new_suppressors "$base_sha")
  [[ -n "$new_supp" ]] && halt "Suppressor 신규 추가: $new_supp"
  if command -v gitleaks >/dev/null 2>&1; then
    local secrets; secrets=$(check_secrets "$base_sha")
    [[ -n "$secrets" ]] && halt "Secrets 의심: $secrets"
  fi
  streak=$(count_fix_symptom_streak)
  [[ $streak -ge 2 ]] && halt "fix:symptom streak (2회 연속)"
  osc=$(detect_oscillation)
  [[ -n "$osc" ]] && halt "진동 패턴: $osc"

  return 0
}

# 워크스페이스 준비: 호출 위치와 무관하게 항상 스펙 디렉토리 하위 전용 워크트리
# (<SPEC_DIR>/.worktree)를 생성한다. 보조(secondary) worktree 안에서 호출돼도 그
# enclosing 워크트리를 재사용하지 않고 전용(필요 시 중첩) 워크트리를 새로 만든다.
# 전용 워크트리 생성 실패는 die 로 abort(0이 아닌 코드) — 대체 위치 폴백 없음.
# 이미 동일 전용 워크트리가 있으면(같은 스펙 재기동) 재사용한다.
prepare_workspace() {
  if [[ ! -d "$WT" ]]; then
    echo "[$(now_iso)] 워크트리 생성: $WT (detached HEAD)"
    git -C "$SPEC_DIR" worktree add --detach "$WT" HEAD \
      || die "git worktree add 실패: $WT"
    mkdir -p "$LOOP_DIR/iterations" "$LOOP_DIR/signals"
    git -C "$WT" rev-parse HEAD > "$LOOP_DIR/BASE_SHA" \
      || die "BASE SHA 캡처 실패: $LOOP_DIR/BASE_SHA"
  else
    echo "[$(now_iso)] 기존 워크트리 사용: $WT"
    mkdir -p "$LOOP_DIR/iterations" "$LOOP_DIR/signals"
  fi

  # 스펙 경로 기록 — list 스캔이 작업 공간에서 정체성을 복원하는 데 사용.
  printf '%s\n' "$SPEC_PATH" > "$LOOP_DIR/SPEC_PATH"
  # 실제 WT 경로를 spec_dir 메타에 영구 기록 — follow-up 명령(status·logs·cleanup·paths)이
  # 어느 cwd 에서 호출되든 같은 작업 공간을 본다.
  printf '%s\n' "$WT" > "$SPEC_DIR/.loop-wt"

  # 헌법을 워크트리 AGENTS.md로 복사. 워커 계약(노트·signals/ 컨벤션 등)의 SoT 는
  # constitution.md 이므로 별도 append 없이 cp 만으로 충분하다.
  cp "$SCRIPT_DIR/constitution.md" "$WT/AGENTS.md" \
    || die "constitution.md를 찾을 수 없음: $SCRIPT_DIR/constitution.md"
  if git -C "$WT" ls-files --error-unmatch AGENTS.md >/dev/null 2>&1; then
    git -C "$WT" update-index --skip-worktree AGENTS.md || true
  fi
  local gcd; gcd="$(git -C "$WT" rev-parse --git-common-dir)"
  [[ "$gcd" != /* ]] && gcd="$WT/$gcd"
  mkdir -p "$gcd/info"; touch "$gcd/info/exclude"
  # .worktree/ 가 제외되면 그 안의 .loop/(노트·신호·BASE_SHA·SPEC_PATH·iterations)도
  # 자동 제외. enclosing worktree(보조 포함)에서 중첩 .worktree/ 가 untracked 로
  # 노출되지 않게 공통 git 디렉토리의 info/exclude 에 등록한다(모든 worktree 공유).
  # .loop-lock 은 SPEC_DIR 레벨이라 별도 패턴 필요. .loop/ 는 안전망 중복.
  for pat in "AGENTS.md" ".worktree/" ".loop/" ".loop-lock" ".loop-wt"; do
    grep -qxF "$pat" "$gcd/info/exclude" 2>/dev/null || echo "$pat" >> "$gcd/info/exclude"
  done
}

# ----- subcommand: start -----
cmd_start() {
  local input="$1"; shift || true
  [[ -z "$input" ]] && die "사용: $0 start <spec-path> [--max-iterations N] [--wall-clock-minutes N]"
  [[ -f "$input" ]] || die "스펙 파일을 찾을 수 없음: $input"
  # 게이트(yq)·이터(codex)는 start에서만 필요 — 여기서 검사.
  require_tool yq
  require_tool codex

  local max_iterations_override="" wall_clock_minutes_override=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-iterations) max_iterations_override="$2"; shift 2 ;;
      --wall-clock-minutes) wall_clock_minutes_override="$2"; shift 2 ;;
      *) die "알 수 없는 옵션: $1" ;;
    esac
  done

  compute_paths "$input"

  # 스펙 내용 검증은 하지 않는다 — 특정 스펙 작성 도구의 규약(마커·placeholder)에
  # 비결합. 스펙 강화 필요 여부는 워커가 signals/ 에 차단 신호로 표현하고, 호출자가
  # 그 본문을 보고 판단한다(driver 는 signals/ 내용 미파싱).

  MAX_ITERATIONS="${max_iterations_override:-${MAX_ITERATIONS:-30}}"
  WALL_CLOCK_MINUTES="${wall_clock_minutes_override:-${WALL_CLOCK_MINUTES:-120}}"

  # 1) lock 먼저 획득 — 워크트리 생성 race 보호. LOCK_FILE 은 SPEC_DIR/.loop-lock 이라
  #    워크트리 존재와 무관하게 잡을 수 있다(noclobber 원자성).
  acquire_lock

  # 2) 워크스페이스 준비 — 호출 위치와 무관하게 항상 <SPEC_DIR>/.worktree 전용
  #    워크트리를 생성한다(보조 worktree 안에서도 enclosing 재사용 금지). 생성 실패는
  #    prepare_workspace 내부에서 die 로 abort.
  prepare_workspace

  # 이터레이션 루프
  START_TIME=$(date +%s)
  CODEX_FAIL_STREAK=0
  local n=0
  while true; do
    n=$((n + 1))
    set +e; iterate; local iter_status=$?; set -e

    if [[ $iter_status -eq 100 ]]; then
      echo "[$(now_iso)] terminal 신호 감지 (signals/ 비어있지 않음). 정상 종료."
      echo "작업 공간 보존: $WT"
      echo "signals/ 내용 ($LOOP_DIR/signals):"
      ls -1 "$LOOP_DIR/signals" 2>/dev/null | sed 's/^/  /'
      echo "후속(통합·PR 등)은 코어가 수행하지 않는다 — 호출 레이어 책임."
      echo "정리: $0 cleanup $SPEC_PATH"
      exit 0
    fi
    if [[ $iter_status -ne 0 ]]; then exit "$iter_status"; fi

    [[ $n -ge $MAX_ITERATIONS ]] && halt "이터 상한 도달 ($n / $MAX_ITERATIONS)"
    [[ $(elapsed_minutes) -ge $WALL_CLOCK_MINUTES ]] && halt "시계 캡 도달 ($(elapsed_minutes) / $WALL_CLOCK_MINUTES 분)"
  done
}

# JSON 문자열 이스케이프(역슬래시·큰따옴표만 — 신호/경로용 최소 처리).
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# ----- status 한 줄 출력 헬퍼 -----
# 인자: <spec_dir> [<format>]. format=json 이면 기계 판독 JSON object 1줄,
#       그 외(기본 table)면 사람용 정렬 1줄. WT 는 <spec_dir>/.loop-wt 메타에서
#       자동 해석(없으면 <spec_dir>/.worktree 기본값). 상태는 spec_dir 내 로컬
#       파일에서만 도출. signals 는 raw fact(파일명 그대로) — driver 는 의미 미파싱.
print_run_status() {
  local spec_dir="$1"
  local fmt="${2:-table}"
  local wt=""
  if [[ -f "$spec_dir/.loop-wt" ]]; then
    # 끝 개행만 제거(값 보존: read 는 EOF-without-newline 시 non-zero 라도 변수
    # 는 채워져 있으므로 '|| true' 로 exit code 만 무시).
    IFS= read -r wt < "$spec_dir/.loop-wt" 2>/dev/null || true
  fi
  [[ -z "$wt" ]] && wt="$spec_dir/.worktree"
  local lock="$spec_dir/.loop-lock"
  local spec key state iters last ref epoch
  spec="$(cat "$wt/.loop/SPEC_PATH" 2>/dev/null || echo "$spec_dir/?")"
  key="$(spec_key "$spec")"
  # signals/ 내용물 — 줄단위 파일명 보존(table 은 콤마, json 은 배열로 가공).
  local sig_lines="" files="-"
  if [[ -d "$wt/.loop/signals" ]]; then
    sig_lines=$(ls -1 "$wt/.loop/signals" 2>/dev/null || true)
    local ls_out
    ls_out=$(printf '%s' "$sig_lines" | tr '\n' ',' | sed 's/,$//')
    [[ -n "$ls_out" ]] && files="$ls_out"
  fi
  state="idle"
  if [[ -f "$lock" ]]; then
    local pid; pid=$(cat "$lock" 2>/dev/null || echo "")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then state="running"; else state="stale"; fi
  elif [[ "$files" != "-" ]]; then
    state="terminal"
  fi
  iters="-"
  last="-"
  if [[ -d "$wt/.loop/iterations" ]]; then
    iters=$(find "$wt/.loop/iterations" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ')
    ref=$(find "$wt/.loop/iterations" -name "*.log" -type f 2>/dev/null | sort | tail -1)
    if [[ -n "$ref" && -f "$ref" ]]; then
      epoch=$(stat -f %m "$ref" 2>/dev/null || stat -c %Y "$ref" 2>/dev/null || echo "")
      [[ -n "$epoch" ]] && last=$(date -u -r "$epoch" +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -d "@$epoch" +%Y-%m-%dT%H:%MZ 2>/dev/null || echo "-")
    fi
  fi

  if [[ "$fmt" == "json" ]]; then
    # signals 를 JSON 배열로 — 빈 디렉토리·기록부재면 []. 의미 해석 없음(raw fact).
    local sig_json="[]" sline first=1
    if [[ -n "$sig_lines" ]]; then
      sig_json="["
      while IFS= read -r sline; do
        [[ -z "$sline" ]] && continue
        if (( first == 1 )); then first=0; else sig_json+=","; fi
        sig_json+="\"$(json_escape "$sline")\""
      done <<< "$sig_lines"
      sig_json+="]"
    fi
    local iters_json="$iters"; [[ "$iters_json" =~ ^[0-9]+$ ]] || iters_json=0
    printf '{"key":"%s","state":"%s","signals":%s,"iters":%s,"last":"%s","spec":"%s"}\n' \
      "$(json_escape "$key")" "$(json_escape "$state")" "$sig_json" \
      "$iters_json" "$(json_escape "$last")" "$(json_escape "$spec")"
    return 0
  fi

  printf "%-14s %-9s %-20s %-6s %-20s %s\n" "$key" "$state" "$files" "$iters" "$last" "$spec"
}

# ----- subcommand: status -----
# status [--json] [<spec-path>]
#   --json : 기계 판독 가능한 구조화 상태 출력. 단일 spec → JSON object,
#            전체 스캔 → JSON array. dispatch 등 호출 레이어의 종료상태 판정용
#            단일 출처(컬럼 위치·부분 문자열 일치 비의존). signals 는 raw fact
#            배열이며 DONE/BLOCKED 의미 해석은 호출자 컨벤션(driver 미파싱).
cmd_status() {
  local json=0 input=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=1; shift ;;
      *) input="$1"; shift ;;
    esac
  done

  if [[ -n "$input" ]]; then
    compute_paths "$input"
    # 영구 메타 (<SPEC_DIR>/.loop-wt) 가 있거나 lock 이 있으면 기록 존재.
    if [[ ! -f "$SPEC_DIR/.loop-wt" && ! -f "$LOCK_FILE" && ! -d "$WT" ]]; then
      if (( json == 1 )); then
        # 기록 부재도 기계 판독 가능하게 — state=absent.
        printf '{"key":"%s","state":"absent","signals":[],"iters":0,"last":"-","spec":"%s"}\n' \
          "$(json_escape "$(spec_key "$SPEC_PATH")")" "$(json_escape "$SPEC_PATH")"
      else
        echo "해당 스펙의 실행 기록이 없습니다: $SPEC_PATH"
      fi
      return 0
    fi
    if (( json == 1 )); then
      print_run_status "$SPEC_DIR" json
    else
      printf "%-14s %-9s %-20s %-6s %-20s %s\n" "KEY" "STATE" "FILES" "ITERS" "LAST-UPDATE" "SPEC"
      print_run_status "$SPEC_DIR"
    fi
    return 0
  fi
  # 전체: repo 작업트리를 스캔해 .loop-lock(실행 중) 또는 .worktree/.loop(이후 상태)을
  # 가진 스펙 디렉토리를 모은다(중앙 registry 없음 — 축소된 best-effort 열거).
  # .git 하위는 prune.
  local top; top="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  local dirs
  dirs="$( {
      find "$top" -type d -name .git -prune -o -type f -name '.loop-lock' -print 2>/dev/null | sed 's#/.loop-lock$##'
      find "$top" -type d -name .git -prune -o -type f -name '.loop-wt'   -print 2>/dev/null | sed 's#/.loop-wt$##'
      find "$top" -type d -name .git -prune -o -type d -path '*/.worktree/.loop' -print 2>/dev/null | sed 's#/.worktree/.loop$##'
    } | sort -u | grep -v '^$' || true )"
  if [[ -z "$dirs" ]]; then
    if (( json == 1 )); then echo "[]"; else
      echo "실행 기록이 없습니다. 새 실행: $0 start <spec-path>"
    fi
    return 0
  fi
  local d
  if (( json == 1 )); then
    # JSON array — 각 run 을 object 로, 콤마 결합.
    local arr="[" first=1
    while IFS= read -r d; do
      [[ -z "$d" ]] && continue
      if (( first == 1 )); then first=0; else arr+=","; fi
      arr+="$(print_run_status "$d" json)"
    done <<< "$dirs"
    arr+="]"
    # print_run_status json 은 끝에 개행을 붙이므로 콤마 결합 시 개행이 섞인다 →
    # 개행 제거 후 한 줄 JSON array 로 출력.
    printf '%s\n' "$(printf '%s' "$arr" | tr -d '\n')"
    return 0
  fi
  printf "%-14s %-9s %-20s %-6s %-20s %s\n" "KEY" "STATE" "FILES" "ITERS" "LAST-UPDATE" "SPEC"
  while IFS= read -r d; do [[ -n "$d" ]] && print_run_status "$d"; done <<< "$dirs"
}

cmd_list() { cmd_status ""; }

# ----- subcommand: stop -----
cmd_stop() {
  local input="$1"
  [[ -z "$input" ]] && die "사용: $0 stop <spec-path>"
  compute_paths "$input"
  [[ -f "$LOCK_FILE" ]] || die "활성 실행이 없습니다: $SPEC_PATH"
  local pid; pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  [[ -z "$pid" ]] && die "락 파일에서 PID 읽기 실패"
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "[$(now_iso)] WARN: PID $pid 비활성 (stale). 락만 정리." >&2
    rm -f "$LOCK_FILE"; return 0
  fi
  echo "[$(now_iso)] 정지 시그널 전송 (PID $pid)..."
  kill -TERM "$pid" 2>/dev/null
  for _ in 1 2 3 4 5; do
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "[$(now_iso)] 정상 정지."; rm -f "$LOCK_FILE"; return 0
    fi
  done
  echo "[$(now_iso)] WARN: PID $pid 무응답. 수동: kill -9 $pid && rm $LOCK_FILE" >&2
  exit 1
}

# ----- subcommand: cleanup -----
cmd_cleanup() {
  local input="$1"; shift || true
  [[ -z "$input" ]] && die "사용: $0 cleanup <spec-path> [--force]"
  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1; shift ;;
      *) die "알 수 없는 옵션: $1" ;;
    esac
  done
  compute_paths "$input"
  # 영구 메타(<SPEC_DIR>/.loop-wt)에서 start 가 쓴 실제 WT 를 해석. 어느 cwd 에서
  # 호출돼도 같은 작업 공간을 본다. 메타 부재 시 기본값(<SPEC_DIR>/.worktree) 유지.
  resolve_actual_wt || true

  if [[ -f "$LOCK_FILE" ]]; then
    local pid; pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ $force -eq 0 ]]; then
      die "실행 중입니다. 먼저 정지: $0 stop $SPEC_PATH\n강제: $0 cleanup $SPEC_PATH --force"
    fi
    if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      echo "WARN: --force — 실행 중 (PID $pid) SIGTERM 후 종료 대기..."
      kill -TERM "$pid" 2>/dev/null || true
      for _ in 1 2 3 4 5; do sleep 1; kill -0 "$pid" 2>/dev/null || break; done
      kill -0 "$pid" 2>/dev/null && { echo "WARN: SIGKILL 전송" >&2; kill -KILL "$pid" 2>/dev/null || true; sleep 1; }
    fi
    rm -f "$LOCK_FILE"
  fi

  # terminal 확인 — signals/ 디렉토리에 파일이 하나라도 있어야 함(이름·내용 미파싱).
  if [[ -z "$(ls "$WT/.loop/signals" 2>/dev/null)" && $force -eq 0 ]]; then
    die "terminal 신호가 없습니다 (signals/ 비어 있음). --force 로 강제 정리 가능: $0 cleanup $SPEC_PATH --force"
  fi

  [[ -n "$WT" ]] || die "WT 비어 있음 (cleanup 거부)"

  # loop 은 항상 자신의 전용 워크트리(<spec_dir>/.worktree)를 소유하므로, 호출 위치와
  # 무관하게 그 워크트리를 제거한다(보조 worktree 라는 이유로 보존하는 분기 없음).
  case "$WT" in
    */.worktree) ;;
    *) die "워크트리 경로 형식 부적절 (기대: */.worktree): $WT" ;;
  esac
  if [[ -d "$WT" ]]; then
    local flags=""; [[ $force -eq 1 ]] && flags="--force"
    git -C "$SPEC_DIR" worktree remove $flags "$WT" \
      || die "git worktree remove 실패. 수동: git worktree remove --force $WT"
  fi
  rm -f "$LOCK_FILE" "$SPEC_DIR/.loop-wt"
  echo "정리 완료: $SPEC_PATH"
}

# ----- subcommand: logs -----
cmd_logs() {
  local input="$1"; shift || true
  [[ -z "$input" ]] && die "사용: $0 logs <spec-path> [--iter N]"
  local iter_n=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --iter) iter_n="$2"; shift 2 ;;
      *) die "알 수 없는 옵션: $1" ;;
    esac
  done
  compute_paths "$input"
  # 영구 메타에서 실제 WT/LOOP_DIR 해석. 어느 cwd 에서 호출돼도 일관. 메타 부재 시 기본값.
  resolve_actual_wt || true
  if [[ -n "$iter_n" ]]; then
    local log="$LOOP_DIR/iterations/$iter_n.log"
    [[ -f "$log" ]] || die "이터 로그 없음: $log"
    cat "$log"; return 0
  fi
  # 인자 없으면 노트 + 이터 로그 목록 + signals/ 내 파일 본문.
  echo "===== notes ($LOOP_DIR/notes.md) ====="
  [[ -f "$LOOP_DIR/notes.md" ]] && cat "$LOOP_DIR/notes.md" || echo "(없음)"
  echo
  echo "===== iterations ====="
  find "$LOOP_DIR/iterations" -name "*.log" -type f 2>/dev/null | sort \
    || echo "(없음)"
  # signals/ 안 파일들 — 이름·개수는 워커 컨벤션이므로 driver 는 그대로 dump.
  if [[ -d "$LOOP_DIR/signals" ]]; then
    local sig
    while IFS= read -r sig; do
      [[ -n "$sig" ]] && { echo; echo "===== signals/$(basename "$sig") ====="; cat "$sig"; }
    done < <(find "$LOOP_DIR/signals" -maxdepth 1 -type f 2>/dev/null | sort)
  fi
}

# ----- subcommand: env (환경 변수 + 기본값을 단일 출처로 노출) -----
cmd_env() {
  cat <<'EOF'
start 동작을 조정하는 환경 변수:

  MAX_ITERATIONS             기본 30      이터 상한 (--max-iterations 로 override)
  WALL_CLOCK_MINUTES         기본 120     시간 상한 (--wall-clock-minutes 로 override)
  CODEX_FAIL_STREAK_LIMIT   기본 3       codex 비정상 exit 연속 허용 횟수
EOF
}

# ----- subcommand: gates (객관 게이트 목록을 단일 출처로 노출) -----
cmd_gates() {
  cat <<'EOF'
이터 후 driver 가 검사하는 객관 게이트 (위반 시 halt → stash + stderr + exit 1):

  - 이터 상한 도달               (MAX_ITERATIONS)
  - 시간 상한 도달               (WALL_CLOCK_MINUTES)
  - codex 비정상 exit 연속      (CODEX_FAIL_STREAK_LIMIT)
  - 테스트 약화                  (기존 테스트 파일 변경 감지)
  - 의존성 manifest 변경
  - SPEC scope 위반              (scope.include 밖 변경)
  - Suppressor 신규 추가         (noqa·@ts-ignore·eslint-disable·#pragma warning disable)
  - secrets 의심                 (gitleaks 설치 시)
  - fix:symptom streak           (2회 연속)
  - 변경 파일 진동               (최근 4 커밋이 두 상태로 토글)

SPEC frontmatter override:
  test_paths        기본 테스트 경로 휴리스틱 대체
  test_sweep_paths  합법적 테스트 rename/cleanup/delete sweep 화이트리스트
EOF
}

# ----- subcommand: deps (필수·선택 의존성과 설치 상태를 단일 출처로 노출) -----
cmd_deps() {
  echo "필수:"
  echo "  ✓ bash $BASH_VERSION"
  echo "  $(command -v git    >/dev/null 2>&1 && echo "✓" || echo "✗") git"
  echo "  $(command -v yq     >/dev/null 2>&1 && echo "✓" || echo "✗") yq (mikefarah)"
  echo "  $(command -v codex >/dev/null 2>&1 && echo "✓" || echo "✗") codex"
  if [[ -n "$HASH_BIN" ]]; then
    echo "  ✓ $HASH_BIN (해시 유틸)"
  else
    echo "  ✗ sha256sum 또는 shasum (해시 유틸)"
  fi
  echo
  echo "선택:"
  if command -v gitleaks >/dev/null 2>&1; then
    echo "  ✓ gitleaks (secret 스캔 게이트 활성화)"
  else
    echo "  - gitleaks (미설치 — secret 스캔 게이트 비활성화)"
  fi
}

# ----- subcommand: paths (스펙의 계산된 경로를 단일 출처로 노출) -----
cmd_paths() {
  local input="$1"
  [[ -z "$input" ]] && die "사용: $0 paths <spec-path>"
  [[ -f "$input" ]] || die "스펙 파일을 찾을 수 없음: $input"
  compute_paths "$input"
  # 메타(<SPEC_DIR>/.loop-wt)가 있으면 그 값을 사용(실제 start 가 쓴 경로).
  # 없으면 기본값(<SPEC_DIR>/.worktree) 유지.
  local source="default"
  if resolve_actual_wt; then
    source="meta"
  fi
  cat <<EOF
SPEC_PATH   $SPEC_PATH
SPEC_DIR    $SPEC_DIR
WT          $WT
LOOP_DIR    $LOOP_DIR
LOCK_FILE   $LOCK_FILE
WT_SOURCE   $source
EOF
}

# ----- 사용법 -----
usage() {
  cat >&2 <<'EOF'
autopilot loop 드라이버 (스펙 파일 기반 로컬 자율 실행기)

Subcommands:
  start   <spec-path>   검증 후 lock 획득 + 워크트리 생성 + 이터 루프
                        [--max-iterations N] [--wall-clock-minutes N]
  status  [<spec-path>] 상태 조회 (인자 없으면 전체)
  stop    <spec-path>   실행 중 정지
  list                  전체 실행 상태
  cleanup <spec-path>   terminal(signals/ non-empty) 후 워크트리 정리 [--force]
  logs    <spec-path>   노트·이터 로그 조회 [--iter N]
  env                   환경 변수 + 기본값
  gates                 객관 게이트 목록 (halt 트리거)
  paths   <spec-path>   해당 스펙의 계산된 경로 (진단·문서 교차 검증용)
  deps                  필수·선택 의존성 + 설치 상태

Exit codes (driver 자체):
  0     정상 종료 (signals/ 가 비어있지 않음 — 워커 terminal 의도)
  1     halt (객관 게이트 위반, codex 비정상 streak, 환경/락 에러 등)
  2     사용법 에러 (잘못된 인자)
  130   SIGTERM/SIGINT

signals/ 내 파일의 의미(DONE/BLOCKED/category 등)는 워커 컨벤션 — 호출자가
종료 후 .loop/signals/ 를 검사해 outcome 을 판별한다. driver 는 파싱하지 않는다.
워커 컨벤션 SoT: references/constitution.md §작업 매체.

자세한 내용: references/operational-guide.md
EOF
  exit 2
}

# ----- 디스패처 (실행 모드일 때만; source 시 함수만 노출) -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  [[ $# -lt 1 ]] && usage
  SUBCOMMAND="$1"; shift
  case "$SUBCOMMAND" in
    start)   cmd_start "$@" ;;
    status)  cmd_status "$@" ;;
    stop)    cmd_stop "${1:-}" ;;
    list)    cmd_list ;;
    cleanup) cmd_cleanup "$@" ;;
    logs)    cmd_logs "$@" ;;
    env)     cmd_env ;;
    gates)   cmd_gates ;;
    paths)   cmd_paths "${1:-}" ;;
    deps)    cmd_deps ;;
    *) echo "알 수 없는 subcommand: $SUBCOMMAND" >&2; usage ;;
  esac
fi
