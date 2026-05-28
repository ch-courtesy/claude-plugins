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
# 작업 공간: <spec 디렉토리>/.worktree (보조 worktree 안에서 호출되면 현재 cwd 사용).
# 이터 간 노트: <WT>/.loop/notes.md. 완료·차단 신호: <WT>/.loop/DONE·BLOCKED 파일.
#
# 환경 변수:
#   MAX_ITERATIONS         이터 상한 (기본: 30)
#   WALL_CLOCK_MINUTES     시계 캡 (기본: 120)
#   CLAUDE_FAIL_STREAK_LIMIT  claude 비정상 exit 연속 허용 (기본: 3)

set -euo pipefail

# ----- 스크립트 자신의 디렉토리 (references/) -----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----- 워커 claude 세션 도구 권한 -----
# 무인 이터 워커는 `--dangerously-skip-permissions`로 실행되므로 별도 allow-list를
# 코어에서 강제하지 않는다.

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
# git은 모든 subcommand가 쓴다(compute_paths). yq·claude는 start의 게이트·이터에서만
# 필요하므로 cmd_start에서 늦게 검사한다 — status/list/stop/cleanup/logs와 테스트의
# 함수 source가 claude·yq 부재에도 동작하도록.
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
  [[ -n "${CLAUDE_PID:-}" ]] && kill_descendants "$CLAUDE_PID"
  exit 130
}

# ----- 경로·정체성 계산 -----
# 입력: 스펙 파일 경로. 출력 전역:
#   SPEC_PATH        스펙 절대 경로 (정체성)
#   SPEC_DIR         스펙 디렉토리 절대 경로
#   KEY              spec_key(SPEC_PATH)
#   WT               작업 공간 (<SPEC_DIR>/.worktree 또는 보조 worktree cwd)
#   LOOP_DIR         <WT>/.loop (노트·신호·메타)
#   BRANCH           loop/<KEY> (워크트리 임시 브랜치)
#   LOCK_FILE        <SPEC_DIR>/.loop.lock (실행 중에만 존재; 스펙 디렉토리에 colocate)
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
  KEY="$(spec_key "$SPEC_PATH")"

  # 스펙 디렉토리가 git 저장소 안이어야 함 (워크트리 생성·게이트에 필요).
  git -C "$SPEC_DIR" rev-parse --git-common-dir >/dev/null 2>&1 \
    || die "스펙 파일이 git 저장소 안에 있어야 합니다: $SPEC_PATH"

  WT="$SPEC_DIR/.worktree"
  LOOP_DIR="$WT/.loop"
  LOCK_FILE="$SPEC_DIR/.loop.lock"   # 스펙 디렉토리에 colocate (워크트리 생성 전 획득)
  BRANCH="loop/$KEY"
}

# 호출 cwd가 git 저장소의 *보조 worktree* 인지 판정 (주 작업트리면 false).
# 보조 worktree: top-level의 .git이 'gitdir: <main>/.git/worktrees/<name>' 형태의 파일.
is_secondary_worktree() {
  local top dotgit
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  dotgit="$top/.git"
  [[ -f "$dotgit" ]] || return 1
  grep -q 'gitdir:.*/\.git/worktrees/' "$dotgit" 2>/dev/null
}

# ----- 동시성 락 -----
acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local old_pid
    old_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      die "이미 실행 중입니다 (PID $old_pid): $SPEC_PATH\n정지: $0 stop $SPEC_PATH"
    fi
    echo "[$(now_iso)] WARN: stale lock 정리 (PID ${old_pid:-?} 비활성)" >&2
    rm -f "$LOCK_FILE"
  fi
  echo "$$" > "$LOCK_FILE"
  # EXIT trap으로 lock 해제. 작업 공간(.worktree/)은 cleanup까지 유지.
  trap 'rm -f "$LOCK_FILE"' EXIT
  trap on_signal_exit INT TERM
}

# ----- 게이트 헬퍼 -----
# 스펙 frontmatter(첫 --- ~ 둘째 ---) 추출.
read_scope_yaml() {
  sed -n '1,/^---$/{
    1d
    /^---$/d
    p
  }' "$SPEC_PATH" 2>/dev/null
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

# ----- halt (게이트 위반 시 자동 BLOCKED 신호) -----
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

  mkdir -p "$LOOP_DIR"
  cat > "$LOOP_DIR/BLOCKED" <<EOF
category: gate-violation
스펙: $SPEC_PATH
트리거: 객관 게이트 위반 — $reason

드라이버가 매 이터 후 게이트를 검사한 결과 위반이 감지되어 자동 정지함.
처리: 가설 점검 후 스펙(scope·verify) 조정, 또는 .loop/notes.md에 후속 노트 누적 후
BLOCKED 파일 삭제하고 재시작. 최근 이터 로그: $LOOP_DIR/iterations/
EOF
  exit 1
}

# ----- 이터레이션 호출 -----
# 반환: 100=DONE, 101=BLOCKED, 0=계속. 게이트 위반 시 halt(exit 1).
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
    exec claude \
      --print \
      --no-session-persistence \
      --dangerously-skip-permissions \
      --system-prompt-file CLAUDE.md \
      --add-dir . \
      --output-format json \
      < "$SPEC_PATH" \
      > ".loop/iterations/$n.log" 2>&1
  ) &
  CLAUDE_PID=$!
  wait "$CLAUDE_PID" || exit_code=$?
  CLAUDE_PID=""

  echo "[$(now_iso)] 이터 #$n 종료 (exit: $exit_code). 게이트 검사..."

  if [[ $exit_code -ne 0 ]]; then
    CLAUDE_FAIL_STREAK=$((CLAUDE_FAIL_STREAK + 1))
    echo "WARN: claude 비정상 exit (연속 $CLAUDE_FAIL_STREAK회). .loop/iterations/$n.log 확인."
    if [[ $CLAUDE_FAIL_STREAK -ge ${CLAUDE_FAIL_STREAK_LIMIT:-3} ]]; then
      halt "claude 비정상 exit ${CLAUDE_FAIL_STREAK}회 연속 (rate limit·네트워크·인증 의심)."
    fi
  else
    CLAUDE_FAIL_STREAK=0
  fi

  # 종료·차단 신호: 워크트리 .loop/ 파일.
  [[ -f "$LOOP_DIR/DONE" ]] && return 100
  [[ -f "$LOOP_DIR/BLOCKED" ]] && return 101

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

# ----- subcommand: start -----
cmd_start() {
  local input="$1"; shift || true
  [[ -z "$input" ]] && die "사용: $0 start <spec-path> [--max-iterations N] [--wall-clock-minutes N]"
  [[ -f "$input" ]] || die "스펙 파일을 찾을 수 없음: $input"
  # 게이트(yq)·이터(claude)는 start에서만 필요 — 여기서 검사.
  require_tool yq
  require_tool claude

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
  # 비결합. 스펙으로 실행 계획을 형성할 수 있는지는 이터 계획 단계의 플랜 게이트가
  # 판정한다(불가 시 1회차 spec-gap BLOCKED → "스펙 강화 필요").

  MAX_ITERATIONS="${max_iterations_override:-${MAX_ITERATIONS:-30}}"
  WALL_CLOCK_MINUTES="${wall_clock_minutes_override:-${WALL_CLOCK_MINUTES:-120}}"

  # 보조 worktree 안에서 호출 시 nested 생성 생략, 현재 cwd 사용.
  local is_secondary=0
  is_secondary_worktree && is_secondary=1

  acquire_lock

  if (( is_secondary == 1 )); then
    WT="$(git rev-parse --show-toplevel)"
    LOOP_DIR="$WT/.loop"
    echo "[$(now_iso)] 보조 worktree 감지 — nested 생성 생략. 작업 공간: $WT"
    mkdir -p "$LOOP_DIR/iterations"
    [[ -f "$LOOP_DIR/BASE_SHA" ]] || git -C "$WT" rev-parse HEAD > "$LOOP_DIR/BASE_SHA" 2>/dev/null || true
  elif [[ ! -d "$WT" ]]; then
    echo "[$(now_iso)] 워크트리 생성: $WT (브랜치 $BRANCH)"
    git -C "$SPEC_DIR" worktree add -b "$BRANCH" "$WT" HEAD \
      || die "git worktree add 실패: $WT"
    mkdir -p "$LOOP_DIR/iterations"
    git -C "$WT" rev-parse HEAD > "$LOOP_DIR/BASE_SHA" \
      || die "BASE SHA 캡처 실패: $LOOP_DIR/BASE_SHA"
  else
    echo "[$(now_iso)] 기존 워크트리 사용: $WT"
    mkdir -p "$LOOP_DIR/iterations"
  fi

  # 스펙 경로 기록 — list 스캔이 작업 공간에서 정체성을 복원하는 데 사용.
  printf '%s\n' "$SPEC_PATH" > "$LOOP_DIR/SPEC_PATH"

  # 헌법을 워크트리 CLAUDE.md로 복사 + 게이트 false-positive 방지(추적 분리·exclude).
  cp "$SCRIPT_DIR/constitution.md" "$WT/CLAUDE.md" \
    || die "constitution.md를 찾을 수 없음: $SCRIPT_DIR/constitution.md"
  if git -C "$WT" ls-files --error-unmatch CLAUDE.md >/dev/null 2>&1; then
    git -C "$WT" update-index --skip-worktree CLAUDE.md || true
  fi
  local gcd; gcd="$(git -C "$WT" rev-parse --git-common-dir)"
  [[ "$gcd" != /* ]] && gcd="$WT/$gcd"
  mkdir -p "$gcd/info"; touch "$gcd/info/exclude"
  for pat in "CLAUDE.md" ".loop/" ".worktree/" ".loop.lock"; do
    grep -qxF "$pat" "$gcd/info/exclude" 2>/dev/null || echo "$pat" >> "$gcd/info/exclude"
  done

  # 이터레이션 루프
  START_TIME=$(date +%s)
  CLAUDE_FAIL_STREAK=0
  local n=0
  while true; do
    n=$((n + 1))
    set +e; iterate; local iter_status=$?; set -e

    if [[ $iter_status -eq 100 ]]; then
      echo "[$(now_iso)] 완료 신호(DONE) 감지. 정상 종료."
      echo "작업 공간 보존: $WT"
      echo "후속(통합·PR 등)은 코어가 수행하지 않는다 — 호출 레이어 책임."
      echo "정리: $0 cleanup $SPEC_PATH"
      exit 0
    fi
    if [[ $iter_status -eq 101 ]]; then
      local category=""
      category=$(sed -n 's/^category:[[:space:]]*//p' "$LOOP_DIR/BLOCKED" 2>/dev/null | head -1)
      # 플랜 게이트: 1회차 spec-gap BLOCKED는 "스펙 강화 필요"로 표면화.
      if [[ $n -eq 1 && "$category" == "spec-gap" ]]; then
        echo "[$(now_iso)] 스펙 강화 필요 — 1회차 계획 단계에서 플랜 형성 불가 (spec-gap)." >&2
        echo "----- BLOCKED -----" >&2
        cat "$LOOP_DIR/BLOCKED" >&2
        exit 3
      fi
      echo "[$(now_iso)] 차단 신호(BLOCKED) 감지. 사람 처리 대기." >&2
      cat "$LOOP_DIR/BLOCKED" >&2
      exit 1
    fi
    if [[ $iter_status -ne 0 ]]; then exit "$iter_status"; fi

    [[ $n -ge $MAX_ITERATIONS ]] && halt "이터 상한 도달 ($n / $MAX_ITERATIONS)"
    [[ $(elapsed_minutes) -ge $WALL_CLOCK_MINUTES ]] && halt "시계 캡 도달 ($(elapsed_minutes) / $WALL_CLOCK_MINUTES 분)"
  done
}

# ----- status 한 줄 출력 헬퍼 -----
# 인자: 스펙 디렉토리(.worktree·.loop.lock 이 위치하는 곳). 상태는 그 안의
# 로컬 파일에서만 도출한다(중앙 registry 없음).
print_run_status() {
  local spec_dir="$1"
  local wt="$spec_dir/.worktree"
  local lock="$spec_dir/.loop.lock"
  local spec key state iters last ref epoch
  spec="$(cat "$wt/.loop/SPEC_PATH" 2>/dev/null || echo "$spec_dir/?")"
  key="$(spec_key "$spec")"
  state="idle"
  if [[ -f "$lock" ]]; then
    local pid; pid=$(cat "$lock" 2>/dev/null || echo "")
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then state="running"; else state="stale"; fi
  elif [[ -f "$wt/.loop/DONE" ]]; then state="done"
  elif [[ -f "$wt/.loop/BLOCKED" ]]; then state="blocked"
  fi
  iters="-"
  [[ -d "$wt/.loop/iterations" ]] && iters=$(find "$wt/.loop/iterations" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ')
  last="-"
  ref=$(find "$wt/.loop/iterations" -name "*.log" -type f 2>/dev/null | sort | tail -1)
  if [[ -n "$ref" && -f "$ref" ]]; then
    epoch=$(stat -f %m "$ref" 2>/dev/null || stat -c %Y "$ref" 2>/dev/null || echo "")
    [[ -n "$epoch" ]] && last=$(date -u -r "$epoch" +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -d "@$epoch" +%Y-%m-%dT%H:%MZ 2>/dev/null || echo "-")
  fi
  printf "%-14s %-9s %-6s %-20s %s\n" "$key" "$state" "$iters" "$last" "$spec"
}

# ----- subcommand: status -----
cmd_status() {
  local input="${1:-}"
  if [[ -n "$input" ]]; then
    compute_paths "$input"
    [[ -d "$WT" || -f "$LOCK_FILE" ]] || { echo "해당 스펙의 실행 기록이 없습니다: $SPEC_PATH"; return 0; }
    printf "%-14s %-9s %-6s %-20s %s\n" "KEY" "STATE" "ITERS" "LAST-UPDATE" "SPEC"
    print_run_status "$SPEC_DIR"
    return 0
  fi
  # 전체: repo 작업트리를 스캔해 .loop.lock·.worktree/.loop 을 가진 스펙 디렉토리를
  # 모은다(중앙 registry 없음 — 축소된 best-effort 열거). .git 하위는 prune.
  local top; top="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  local dirs
  dirs="$( {
      find "$top" -type d -name .git -prune -o -type f -name '.loop.lock' -print 2>/dev/null | sed 's#/.loop.lock$##'
      find "$top" -type d -name .git -prune -o -type d -path '*/.worktree/.loop' -print 2>/dev/null | sed 's#/.worktree/.loop$##'
    } | sort -u | grep -v '^$' || true )"
  if [[ -z "$dirs" ]]; then
    echo "실행 기록이 없습니다. 새 실행: $0 start <spec-path>"
    return 0
  fi
  printf "%-14s %-9s %-6s %-20s %s\n" "KEY" "STATE" "ITERS" "LAST-UPDATE" "SPEC"
  local d
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

  # 완료 확인 — DONE 파일.
  if [[ ! -f "$WT/.loop/DONE" && $force -eq 0 ]]; then
    die "완료 신호(.loop/DONE)가 없습니다. --force로 강제 정리 가능: $0 cleanup $SPEC_PATH --force"
  fi

  # path guard
  [[ -n "$WT" ]] || die "WT 비어 있음 (cleanup 거부)"
  case "$WT" in
    */.worktree) ;;
    *) die "워크트리 경로 형식 부적절 (기대: */.worktree): $WT" ;;
  esac

  if [[ -d "$WT" ]]; then
    local flags=""; [[ $force -eq 1 ]] && flags="--force"
    git -C "$SPEC_DIR" worktree remove $flags "$WT" \
      || die "git worktree remove 실패. 수동: git worktree remove --force $WT"
    # 임시 브랜치 삭제 (loop/<key>).
    git -C "$SPEC_DIR" branch -D "$BRANCH" >/dev/null 2>&1 || true
  fi
  rm -f "$LOCK_FILE"
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
  if [[ -n "$iter_n" ]]; then
    local log="$LOOP_DIR/iterations/$iter_n.log"
    [[ -f "$log" ]] || die "이터 로그 없음: $log"
    cat "$log"; return 0
  fi
  # 인자 없으면 노트 + 최근 이터 로그 목록.
  echo "===== notes ($LOOP_DIR/notes.md) ====="
  [[ -f "$LOOP_DIR/notes.md" ]] && cat "$LOOP_DIR/notes.md" || echo "(없음)"
  echo
  echo "===== iterations ====="
  find "$LOOP_DIR/iterations" -name "*.log" -type f 2>/dev/null | sort \
    || echo "(없음)"
  for sig in DONE BLOCKED; do
    [[ -f "$LOOP_DIR/$sig" ]] && { echo; echo "===== $sig ====="; cat "$LOOP_DIR/$sig"; }
  done
}

# ----- 사용법 -----
usage() {
  cat >&2 <<'EOF'
autopilot loop 드라이버 (스펙 파일 기반 로컬 자율 실행기)

Subcommands:
  start  <spec-path>   검증·플랜 게이트 후 워크트리·락 생성 + 루프 시작
                       [--max-iterations N] [--wall-clock-minutes N]
  status [<spec-path>] 상태 조회 (인자 없으면 전체)
  stop   <spec-path>   실행 중 정지
  list                 전체 실행 상태
  cleanup <spec-path>  완료(.loop/DONE) 후 워크트리·브랜치 정리 [--force]
  logs   <spec-path>   노트·이터 로그 조회 [--iter N]

자세한 내용: references/operational-guide.md
EOF
  exit 1
}

# ----- 디스패처 (실행 모드일 때만; source 시 함수만 노출) -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  [[ $# -lt 1 ]] && usage
  SUBCOMMAND="$1"; shift
  case "$SUBCOMMAND" in
    start)   cmd_start "$@" ;;
    status)  cmd_status "${1:-}" ;;
    stop)    cmd_stop "${1:-}" ;;
    list)    cmd_list ;;
    cleanup) cmd_cleanup "$@" ;;
    logs)    cmd_logs "$@" ;;
    *) echo "알 수 없는 subcommand: $SUBCOMMAND" >&2; usage ;;
  esac
fi
