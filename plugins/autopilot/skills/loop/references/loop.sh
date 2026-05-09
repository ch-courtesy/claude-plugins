#!/usr/bin/env bash
# loop.sh — 자율 루프 외부 셸 드라이버 (subcommand 기반)
#
# 사용:
#   bash /path/to/autopilot/skills/loop/references/loop.sh prepare <task-id>
#   bash /path/to/autopilot/skills/loop/references/loop.sh start   <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>]
#   bash /path/to/autopilot/skills/loop/references/loop.sh status  [<task-id>]
#   bash /path/to/autopilot/skills/loop/references/loop.sh stop    <task-id>
#   bash /path/to/autopilot/skills/loop/references/loop.sh list
#   bash /path/to/autopilot/skills/loop/references/loop.sh cleanup <task-id> [--force]
#   bash /path/to/autopilot/skills/loop/references/loop.sh logs    <task-id> [--tail] [--iter N]
#
# 환경 변수:
#   LOOP_WORKTREE_BASE     워크트리 부모 디렉토리 (기본: <project>/../<project-name>-loops)
#   MAX_CONCURRENT         동시 실행 task 수 (기본: 3)
#   MAX_ITERATIONS         이터 상한 (기본: 30)
#   WALL_CLOCK_MINUTES     시계 캡 (기본: 120)

set -euo pipefail

# ----- 스크립트 자신의 디렉토리 (references/) -----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ----- 헬퍼 -----

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1이(가) 필요합니다. 설치 후 다시 실행하세요."
}

sanitize_for_filename() {
  # 슬래시·공백 등을 -로 치환 (락 파일명용)
  echo "$1" | tr '/ ' '--'
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# ----- 의존성 검사 -----

require_tool git
require_tool yq
require_tool claude

# ----- 경로 계산 헬퍼 -----

compute_paths() {
  local task_id="$1"
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  PROJECT_NAME="$(basename "$PROJECT_ROOT")"
  WT_BASE="${LOOP_WORKTREE_BASE:-$PROJECT_ROOT/../${PROJECT_NAME}-loops}"
  WT="$WT_BASE/$task_id"
  BRANCH="autonomous-loop/$task_id"
  TASK_ID_SAFE="$(sanitize_for_filename "$task_id")"
  LOCK_DIR="$PROJECT_ROOT/.loops/locks"
  LOCK_FILE="$LOCK_DIR/$TASK_ID_SAFE.lock"
  LOOPS_DIR="$PROJECT_ROOT/.loops/$task_id"
}

# ----- 동시성 락 -----

acquire_lock() {
  mkdir -p "$LOCK_DIR"

  local running
  running=$(find "$LOCK_DIR" -name "*.lock" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ $running -ge $MAX_CONCURRENT ]]; then
    die "이미 $running개 loop이 동작 중 (최대: $MAX_CONCURRENT). 새 loop 거부."
  fi

  if [[ -f "$LOCK_FILE" ]]; then
    local existing_pid
    existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "?")
    die "task ${TASK_ID}가 이미 동작 중 (PID: $existing_pid). 종료 후 재실행. 프로세스가 없으면: rm $LOCK_FILE"
  fi

  echo $$ > "$LOCK_FILE"
  trap "rm -f $LOCK_FILE" EXIT
}

# ----- 게이트 헬퍼 -----

hash_tests() {
  if [[ -d "$WT/tests" ]]; then
    find "$WT/tests" -type f \( -name '*.test.*' -o -name 'test_*.*' -o -name '*_test.*' \) 2>/dev/null \
      | sort \
      | xargs -I{} sha256sum {} 2>/dev/null \
      | sha256sum \
      | awk '{print $1}'
  else
    echo "no-tests-dir"
  fi
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
    echo "$manifests" | xargs -I{} sha256sum {} 2>/dev/null \
      | sha256sum | awk '{print $1}'
  fi
}

read_scope_include() {
  sed -n '1,/^---$/{
    1d
    /^---$/d
    p
  }' "$WT/.loop/SPEC.md" 2>/dev/null \
    | yq '.scope.include[]' 2>/dev/null \
    || true
}

read_scope_exclude() {
  sed -n '1,/^---$/{
    1d
    /^---$/d
    p
  }' "$WT/.loop/SPEC.md" 2>/dev/null \
    | yq '.scope.exclude[]' 2>/dev/null \
    || true
}

diff_vs_scope() {
  local include_patterns exclude_patterns changed
  include_patterns=$(read_scope_include)
  exclude_patterns=$(read_scope_exclude)
  changed=$(cd "$WT" && git diff --name-only HEAD~1 HEAD 2>/dev/null || true)

  [[ -z "$changed" ]] && return 0

  local out_of_scope=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    # exclude 패턴 매칭 → 위반
    local excluded=0
    while IFS= read -r exc; do
      [[ -z "$exc" ]] && continue
      if [[ "$file" == $exc ]]; then
        out_of_scope+="$file (excluded by $exc)\n"
        excluded=1
        break
      fi
    done <<< "$exclude_patterns"
    [[ $excluded -eq 1 ]] && continue

    # include 패턴 중 하나에도 매칭 안 되면 위반
    local matched=0
    while IFS= read -r inc; do
      [[ -z "$inc" ]] && continue
      if [[ "$file" == $inc ]]; then
        matched=1
        break
      fi
    done <<< "$include_patterns"

    if [[ $matched -eq 0 ]]; then
      out_of_scope+="$file (not in include)\n"
    fi
  done <<< "$changed"

  if [[ -n "$out_of_scope" ]]; then
    printf "%b" "$out_of_scope"
  fi
}

grep_new_suppressors() {
  cd "$WT" && git diff HEAD~1 HEAD 2>/dev/null \
    | grep -E '^\+' \
    | grep -E '#[[:space:]]*noqa|@ts-ignore|eslint-disable|#pragma[[:space:]]+warning[[:space:]]+disable' \
    || true
}

check_secrets() {
  command -v gitleaks >/dev/null 2>&1 || return 0
  cd "$WT" && gitleaks detect --staged --no-banner 2>&1 || true
}

count_fix_symptom_streak() {
  cd "$WT" && git log --pretty=format:%s -2 2>/dev/null \
    | { grep -c '^fix:symptom' || true; }
}

detect_oscillation() {
  local commits
  commits=$(cd "$WT" && git log --pretty=tformat:%H -4 2>/dev/null || true)
  [[ $(echo "$commits" | wc -l | tr -d ' ') -lt 4 ]] && return 0

  local sets=()
  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue
    sets+=("$(cd "$WT" && git diff-tree --no-commit-id --name-only -r "$commit" 2>/dev/null | sort | md5sum | awk '{print $1}')")
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

# ----- halt (게이트 위반 시 자동 ESCALATION) -----

halt() {
  local reason="$1"
  echo "[$(now_iso)] HALT: $reason" >&2

  # 진행 중 변경을 stash (있으면)
  (cd "$WT" && git add -A && git stash push -m "auto-stash by loop.sh halt" 2>/dev/null) || true

  # 자동 ESCALATION 작성
  mkdir -p "$WT/.loop"
  cat > "$WT/.loop/ESCALATION.md" <<EOF
# 에스컬레이션 보고 (드라이버 자동 작성)

**작업**: $TASK_ID
**이터레이션**: 자동 정지
**트리거**: 객관 게이트 위반 — $reason

## 현재 상태

드라이버가 매 이터 후 게이트를 검사한 결과 위반이 감지되어 자동 정지함.

## 문제

$reason

## 처리

다음 중 하나:
1. 가설 점검 후 작업 명세(scope·verify) 조정
2. 메모리 파일(NOTES.md) 보강
3. 본 ESCALATION.md 삭제 후 재시작

자세한 내용은 .loop/iterations/ 의 최근 로그 참조.
EOF

  exit 1
}

# ----- 이터레이션 호출 -----

iterate() {
  local n
  n=$(($(find "$WT/.loop/iterations" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ') + 1))

  echo "[$(now_iso)] 이터 #$n 시작"

  local start_hash_tests start_hash_deps
  start_hash_tests=$(hash_tests)
  start_hash_deps=$(hash_deps)

  local exit_code=0
  (
    cd "$WT"
    claude \
      --print \
      --no-session-persistence \
      --dangerously-skip-permissions \
      --system-prompt-file CLAUDE.md \
      --add-dir . \
      --output-format json \
      < .loop/SPEC.md \
      > ".loop/iterations/$n.log" 2>&1
  ) || exit_code=$?

  echo "[$(now_iso)] 이터 #$n 종료 (exit: $exit_code). 게이트 검사..."

  if [[ $exit_code -ne 0 ]]; then
    echo "WARN: claude 호출이 0이 아닌 exit code 반환. iterations/$n.log 확인 권장."
  fi

  # 종료 신호 검사 (먼저)
  if [[ -f "$WT/DONE" ]]; then
    return 100   # 메인 루프에서 정상 종료 처리
  fi
  if [[ -f "$WT/.loop/ESCALATION.md" ]]; then
    return 101   # 메인 루프에서 ESCALATION 처리
  fi

  # 객관 게이트 9종
  if [[ "$start_hash_tests" != "no-tests-dir" ]] \
     && [[ "$(hash_tests)" != "$start_hash_tests" ]]; then
    halt "테스트 약화 — tests/** 해시 변경"
  fi
  if [[ "$start_hash_deps" != "no-manifests" ]] \
     && [[ "$(hash_deps)" != "$start_hash_deps" ]]; then
    halt "의존성 변경 — 매니페스트 해시 변경"
  fi

  local out_of_scope new_supp streak osc
  out_of_scope=$(diff_vs_scope)
  [[ -n "$out_of_scope" ]] && halt "Scope 위반: $out_of_scope"

  new_supp=$(grep_new_suppressors)
  [[ -n "$new_supp" ]] && halt "Suppressor 신규 추가: $new_supp"

  if command -v gitleaks >/dev/null 2>&1; then
    local secrets
    secrets=$(check_secrets)
    [[ -n "$secrets" ]] && halt "Secrets 의심: $secrets"
  fi

  streak=$(count_fix_symptom_streak)
  [[ $streak -ge 2 ]] && halt "fix:symptom streak (2회 연속)"

  osc=$(detect_oscillation)
  [[ -n "$osc" ]] && halt "진동 패턴: $osc"

  return 0
}

# ----- subcommand: prepare -----

cmd_prepare() {
  local task_id="$1"
  [[ -z "$task_id" ]] && die "사용: $0 prepare <task-id>"

  compute_paths "$task_id"

  local spec_dst="$LOOPS_DIR/SPEC.md"
  if [[ -f "$spec_dst" ]]; then
    die "이미 준비되어 있습니다: $spec_dst\n재준비하려면 먼저 삭제하세요: rm $spec_dst"
  fi

  local spec_src="$SCRIPT_DIR/spec-template.md"
  [[ -f "$spec_src" ]] || die "spec-template.md를 찾을 수 없습니다: $spec_src"

  mkdir -p "$LOOPS_DIR"
  cp "$spec_src" "$spec_dst"

  echo "준비 완료. 다음 파일을 편집하세요:"
  echo "  $spec_dst"
  echo ""
  echo "편집 후 루프를 시작하려면:"
  echo "  $0 start $task_id"
}

# ----- subcommand: start -----

cmd_start() {
  local task_id="$1"
  shift || true
  [[ -z "$task_id" ]] && die "사용: $0 start <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>]"

  local max_iterations_override="" wall_clock_minutes_override="" watch_mode=0 spec_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-iterations)
        max_iterations_override="$2"
        shift 2
        ;;
      --wall-clock-minutes)
        wall_clock_minutes_override="$2"
        shift 2
        ;;
      --watch)
        watch_mode=1
        shift
        ;;
      --spec)
        spec_path="$2"
        shift 2
        ;;
      *)
        die "알 수 없는 옵션: $1"
        ;;
    esac
  done

  compute_paths "$task_id"
  TASK_ID="$task_id"

  MAX_ITERATIONS="${max_iterations_override:-${MAX_ITERATIONS:-30}}"
  WALL_CLOCK_MINUTES="${wall_clock_minutes_override:-${WALL_CLOCK_MINUTES:-120}}"
  MAX_CONCURRENT="${MAX_CONCURRENT:-3}"
  WATCH_MODE="$watch_mode"

  # 1. --spec 외부 SPEC 전달 처리
  if [[ -n "$spec_path" ]]; then
    [[ -f "$spec_path" ]] || die "외부 SPEC 파일을 찾을 수 없음: $spec_path"
    mkdir -p "$LOOPS_DIR"
    cp "$spec_path" "$LOOPS_DIR/SPEC.md"
    echo "외부 SPEC 파일 복사: $spec_path → $LOOPS_DIR/SPEC.md"
  fi

  # 2. SPEC.md 존재 확인
  local spec_path_local="$LOOPS_DIR/SPEC.md"
  if [[ ! -f "$spec_path_local" ]]; then
    die "SPEC.md가 없습니다. 먼저 실행하세요: $0 prepare $task_id"
  fi

  # 3. placeholder 검사
  local placeholders
  placeholders=$(grep -oE '\{\{[^}]+\}\}' "$spec_path_local" 2>/dev/null || true)
  if [[ -n "$placeholders" ]]; then
    die "채워지지 않은 placeholder가 있습니다: $(echo "$placeholders" | tr '\n' ' ')\n$spec_path_local 를 편집하세요."
  fi

  # 4. 락 획득
  acquire_lock

  # 5. 워크트리 생성 (없는 경우)
  if [[ ! -d "$WT" ]]; then
    echo "[$(now_iso)] 워크트리 생성 시작: $WT"

    mkdir -p "$WT_BASE"
    git -C "$PROJECT_ROOT" worktree add "$WT" -b "$BRANCH" \
      || die "git worktree add 실패: $WT"

    # 헌법을 워크트리 CLAUDE.md로 복사
    cp "$SCRIPT_DIR/constitution.md" "$WT/CLAUDE.md" \
      || die "constitution.md를 찾을 수 없음: $SCRIPT_DIR/constitution.md"

    # 메타 파일 시드
    mkdir -p "$WT/.loop/iterations"
    cp "$LOOPS_DIR/SPEC.md" "$WT/.loop/SPEC.md"
    cp "$SCRIPT_DIR/plan-template.md" "$WT/.loop/PLAN.md"
    cp "$SCRIPT_DIR/notes-template.md" "$WT/.loop/NOTES.md"
    cp "$SCRIPT_DIR/handoff-template.md" "$WT/.loop/HANDOFF.md"
    cp "$SCRIPT_DIR/runlog-template.md" "$WT/.loop/RUN_LOG.md"

    # 워크트리 로컬 비추적 등록
    local wt_gitdir
    wt_gitdir="$(git -C "$WT" rev-parse --git-dir)"
    mkdir -p "$wt_gitdir/info"
    {
      echo "CLAUDE.md"
      echo ".loop/"
      echo "DONE"
    } >> "$wt_gitdir/info/exclude"

    echo "[$(now_iso)] 워크트리 생성 완료: $WT"
    echo "브랜치: $BRANCH"
  else
    echo "[$(now_iso)] 기존 워크트리 사용: $WT"
  fi

  # 6. 이터레이션 루프
  START_TIME=$(date +%s)
  local n=0

  while true; do
    n=$((n + 1))

    set +e
    iterate
    local iter_status=$?
    set -e

    if [[ $iter_status -eq 100 ]]; then
      echo "[$(now_iso)] DONE 신호 감지. 정상 종료."
      # cleanup 시 archive로 이동하도록 안내만
      echo ""
      echo "task $task_id 완료."
      echo "메타 파일 정리 및 워크트리 제거:"
      echo "  $0 cleanup $task_id"
      exit 0
    fi
    if [[ $iter_status -eq 101 ]]; then
      echo "[$(now_iso)] ESCALATION.md 감지. 사람 처리 대기."
      if [[ $WATCH_MODE -eq 1 ]]; then
        echo "[$(now_iso)] --watch 모드: ESCALATION.md 사라짐 polling 중 (60초 간격, Ctrl+C로 종료)..."
        while [[ -f "$WT/.loop/ESCALATION.md" ]]; do
          sleep 60
        done
        echo "[$(now_iso)] ESCALATION.md 해제 감지. 루프 재개."
        continue
      fi
      exit 1
    fi
    if [[ $iter_status -ne 0 ]]; then
      exit "$iter_status"
    fi

    if [[ $n -ge $MAX_ITERATIONS ]]; then
      halt "이터 상한 도달 ($n / $MAX_ITERATIONS)"
    fi

    if [[ $(elapsed_minutes) -ge $WALL_CLOCK_MINUTES ]]; then
      halt "시계 캡 도달 ($(elapsed_minutes) / $WALL_CLOCK_MINUTES 분)"
    fi
  done
}

# ----- subcommand: status -----

cmd_status() {
  local filter_task_id="${1:-}"

  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  PROJECT_NAME="$(basename "$PROJECT_ROOT")"
  WT_BASE="${LOOP_WORKTREE_BASE:-$PROJECT_ROOT/../${PROJECT_NAME}-loops}"
  LOCK_DIR="$PROJECT_ROOT/.loops/locks"

  # task-id 목록 수집: .loops/<task-id>/ 디렉토리 (시스템 디렉토리 제외)
  local loops_base="$PROJECT_ROOT/.loops"
  local task_ids=()

  if [[ -n "$filter_task_id" ]]; then
    task_ids=("$filter_task_id")
  else
    while IFS= read -r dir; do
      local basename_dir
      basename_dir="$(basename "$dir")"
      # 시스템 디렉토리 제외
      case "$basename_dir" in
        locks|templates|archive) continue ;;
      esac
      [[ -d "$dir" ]] || continue
      task_ids+=("$basename_dir")
    done < <(find "$loops_base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  fi

  if [[ ${#task_ids[@]} -eq 0 ]]; then
    echo "실행 중인 task가 없습니다."
    echo "새 task를 시작하려면: $0 prepare <task-id>"
    return 0
  fi

  printf "%-20s %-12s %-12s %s\n" "TASK-ID" "STATE" "ITERATIONS" "LAST-UPDATE"
  printf "%-20s %-12s %-12s %s\n" "--------------------" "------------" "------------" "-----------"

  for tid in "${task_ids[@]}"; do
    local tid_safe
    tid_safe="$(sanitize_for_filename "$tid")"
    local lock_file="$LOCK_DIR/$tid_safe.lock"
    local wt="$WT_BASE/$tid"
    local loops_dir="$loops_base/$tid"
    local state="-"
    local iterations="-"
    local last_update="-"

    # 상태 판정
    if [[ -f "$lock_file" ]]; then
      state="running"
    elif [[ -d "$wt" ]]; then
      if [[ -f "$wt/.loop/ESCALATION.md" ]]; then
        state="escalated"
      elif [[ -f "$wt/DONE" ]]; then
        state="done"
      else
        state="idle"
      fi
    elif [[ -d "$loops_dir" ]]; then
      # SPEC.md만 있으면 prepared, 메모리 파일이 있으면 archived
      if [[ -f "$loops_dir/PLAN.md" ]] || [[ -f "$loops_dir/NOTES.md" ]]; then
        state="archived"
      elif [[ -f "$loops_dir/SPEC.md" ]]; then
        state="prepared"
      fi
    fi

    # 이터 횟수
    if [[ -d "$wt/.loop/iterations" ]]; then
      local cnt
      cnt=$(find "$wt/.loop/iterations" -name "*.log" -type f 2>/dev/null | wc -l | tr -d ' ')
      iterations="$cnt"
    elif [[ -d "$loops_dir" ]]; then
      # archived 상태에서 RUN_LOG.md로 추정
      if [[ -f "$loops_dir/RUN_LOG.md" ]]; then
        local cnt
        cnt=$(grep -c '^\[' "$loops_dir/RUN_LOG.md" 2>/dev/null || echo "?")
        iterations="$cnt"
      fi
    fi

    # 마지막 갱신 시각
    local ref_file=""
    if [[ -d "$wt/.loop" ]]; then
      ref_file="$wt/.loop/RUN_LOG.md"
    elif [[ -f "$loops_dir/RUN_LOG.md" ]]; then
      ref_file="$loops_dir/RUN_LOG.md"
    fi
    if [[ -n "$ref_file" ]] && [[ -f "$ref_file" ]]; then
      last_update=$(date -r "$ref_file" -u +%Y-%m-%dT%H:%MZ 2>/dev/null || stat -c %y "$ref_file" 2>/dev/null | cut -c1-16 || echo "-")
    fi

    printf "%-20s %-12s %-12s %s\n" "$tid" "$state" "$iterations" "$last_update"
  done
}

# ----- subcommand: stop -----

cmd_stop() {
  local task_id="$1"
  [[ -z "$task_id" ]] && die "사용: $0 stop <task-id>"

  compute_paths "$task_id"

  if [[ ! -f "$LOCK_FILE" ]]; then
    die "$task_id 에 대한 실행 중인 loop가 없습니다."
  fi

  local pid
  pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [[ -z "$pid" ]]; then
    die "락 파일에서 PID를 읽을 수 없습니다: $LOCK_FILE"
  fi

  echo "SIGTERM 전송: PID $pid (task: $task_id)"
  kill -TERM "$pid" 2>/dev/null || echo "WARN: PID $pid 에 SIGTERM 전송 실패 (이미 종료됐을 수 있음)"

  # 5초간 종료 대기
  local waited=0
  while [[ $waited -lt 5 ]]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "프로세스 종료 확인."
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  if kill -0 "$pid" 2>/dev/null; then
    echo "WARN: PID $pid 가 5초 후에도 살아있습니다."
    echo "강제 종료하려면: kill -9 $pid"
  fi

  rm -f "$LOCK_FILE"
  echo "락 파일 제거 완료: $LOCK_FILE"
}

# ----- subcommand: list -----

cmd_list() {
  cmd_status ""
}

# ----- subcommand: cleanup -----

cmd_cleanup() {
  local task_id="$1"
  shift || true
  [[ -z "$task_id" ]] && die "사용: $0 cleanup <task-id> [--force]"

  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1; shift ;;
      *) die "알 수 없는 옵션: $1" ;;
    esac
  done

  compute_paths "$task_id"
  TASK_ID="$task_id"

  # 1. 실행 중 확인
  if [[ -f "$LOCK_FILE" ]]; then
    if [[ $force -eq 0 ]]; then
      die "task $task_id 가 실행 중입니다. 먼저 정지하세요: $0 stop $task_id\n강제 실행: $0 cleanup $task_id --force"
    fi
    echo "WARN: 락 파일이 있지만 --force로 진행합니다."
    rm -f "$LOCK_FILE"
  fi

  # 2. 워크트리 존재 확인
  if [[ ! -d "$WT" ]]; then
    die "$task_id 에 대한 워크트리가 없습니다: $WT"
  fi

  # 3. DONE 확인
  if [[ ! -f "$WT/DONE" ]] && [[ $force -eq 0 ]]; then
    die "task $task_id 에 DONE 신호가 없습니다.\n--force 없이 cleanup하려면 먼저 DONE 파일이 필요합니다: $0 cleanup $task_id --force"
  fi

  # 4. 메타 파일 archive (.loops/<task-id>/ 로 이동)
  mkdir -p "$LOOPS_DIR"
  for f in PLAN.md NOTES.md HANDOFF.md RUN_LOG.md; do
    if [[ -f "$WT/.loop/$f" ]]; then
      cp "$WT/.loop/$f" "$LOOPS_DIR/" 2>/dev/null || true
    fi
  done
  echo "메타 파일 보관: $LOOPS_DIR"

  # 5. 워크트리 제거
  local wt_remove_flags=""
  [[ $force -eq 1 ]] && wt_remove_flags="--force"
  git -C "$PROJECT_ROOT" worktree remove $wt_remove_flags "$WT" \
    || die "git worktree remove 실패. 수동 제거: git worktree remove --force $WT"

  # 6. 브랜치 삭제
  local branch_delete_flag="-d"
  [[ $force -eq 1 ]] && branch_delete_flag="-D"
  git -C "$PROJECT_ROOT" branch $branch_delete_flag "$BRANCH" 2>/dev/null \
    || echo "WARN: 브랜치 삭제 실패 (이미 머지됐거나 없을 수 있음): $BRANCH"

  echo ""
  echo "정리 완료: $task_id"
  echo "보관된 메타 파일: $LOOPS_DIR"
}

# ----- subcommand: logs -----

cmd_logs() {
  local task_id="$1"
  shift || true
  [[ -z "$task_id" ]] && die "사용: $0 logs <task-id> [--tail] [--iter N]"

  local tail_mode=0 iter_n=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tail) tail_mode=1; shift ;;
      --iter) iter_n="$2"; shift 2 ;;
      *) die "알 수 없는 옵션: $1" ;;
    esac
  done

  compute_paths "$task_id"

  if [[ -n "$iter_n" ]]; then
    # 이터 로그 출력 (워크트리 우선, fallback 없음)
    local iter_log="$WT/.loop/iterations/$iter_n.log"
    [[ -f "$iter_log" ]] || die "이터 로그가 없습니다: $iter_log"
    cat "$iter_log"
    return 0
  fi

  # RUN_LOG.md 위치 찾기 (워크트리 우선, archived fallback)
  local run_log=""
  if [[ -f "$WT/.loop/RUN_LOG.md" ]]; then
    run_log="$WT/.loop/RUN_LOG.md"
  elif [[ -f "$LOOPS_DIR/RUN_LOG.md" ]]; then
    run_log="$LOOPS_DIR/RUN_LOG.md"
  else
    die "RUN_LOG.md를 찾을 수 없습니다. task-id가 올바른지 확인하세요: $task_id"
  fi

  if [[ $tail_mode -eq 1 ]]; then
    tail -f "$run_log"
  else
    cat "$run_log"
  fi
}

# ----- 사용법 출력 -----

usage() {
  cat >&2 <<'EOF'
사용법이 바뀌었습니다.

Subcommands:
  prepare <task-id>       SPEC.md 시드 생성
  start <task-id>         검증 후 워크트리·락 생성 + 루프 시작 [--max-iterations N] [--wall-clock-minutes N] [--watch] [--spec <path>]
  status [<task-id>]      상태 조회
  stop <task-id>          실행 중 정지
  list                    전체 task 상태
  cleanup <task-id>       DONE 후 정리
  logs <task-id>          로그 조회

자세한 내용: references/operational-guide.md (autopilot/skills/loop/)
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
  prepare)
    cmd_prepare "$@"
    ;;
  start)
    cmd_start "$@"
    ;;
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
    cmd_cleanup "$@"
    ;;
  logs)
    cmd_logs "$@"
    ;;
  *)
    echo "알 수 없는 subcommand: $SUBCOMMAND" >&2
    usage
    ;;
esac
