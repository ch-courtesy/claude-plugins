#!/usr/bin/env bash
# loop.sh — 자율 루프 외부 셸 드라이버
# 사용: ./.loops/loop.sh <task-id>
#
# 환경 변수:
#   LOOP_WORKTREE_BASE     워크트리 부모 디렉토리 (기본: <project>/../<project-name>-loops)
#   MAX_CONCURRENT         동시 실행 task 수 (기본: 3)
#   MAX_ITERATIONS         이터 상한 (기본: 30)
#   WALL_CLOCK_MINUTES     시계 캡 (기본: 120)

set -euo pipefail

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

# ----- 인자 파싱 -----

if [[ $# -lt 1 ]]; then
  die "사용: $0 <task-id> [--max-iterations N] [--wall-clock-minutes N] [--watch]"
fi

TASK_ID="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations)
      MAX_ITERATIONS_OVERRIDE="$2"
      shift 2
      ;;
    --wall-clock-minutes)
      WALL_CLOCK_MINUTES_OVERRIDE="$2"
      shift 2
      ;;
    --watch)
      WATCH_MODE=1
      shift
      ;;
    *)
      die "알 수 없는 옵션: $1"
      ;;
  esac
done

WATCH_MODE="${WATCH_MODE:-0}"

# ----- 경로 계산 -----

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "git 저장소 안에서 실행해야 합니다."
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
WT_BASE="${LOOP_WORKTREE_BASE:-$PROJECT_ROOT/../${PROJECT_NAME}-loops}"
WT="$WT_BASE/$TASK_ID"
BRANCH="autonomous-loop/$TASK_ID"
TASK_ID_SAFE="$(sanitize_for_filename "$TASK_ID")"
LOCK_DIR="$PROJECT_ROOT/.loops/locks"
LOCK_FILE="$LOCK_DIR/$TASK_ID_SAFE.lock"
ARCHIVE_DIR="$PROJECT_ROOT/.loops/archive/$TASK_ID"

# 캡 기본값 (CLI > 환경 변수 > 디폴트)
MAX_ITERATIONS="${MAX_ITERATIONS_OVERRIDE:-${MAX_ITERATIONS:-30}}"
WALL_CLOCK_MINUTES="${WALL_CLOCK_MINUTES_OVERRIDE:-${WALL_CLOCK_MINUTES:-120}}"
MAX_CONCURRENT="${MAX_CONCURRENT:-3}"

# ----- 워크트리 생성 (첫 호출용) -----

create_worktree() {
  echo "[$(now_iso)] 워크트리 생성 시작: $WT"

  mkdir -p "$WT_BASE"
  git -C "$PROJECT_ROOT" worktree add "$WT" -b "$BRANCH" \
    || die "git worktree add 실패: $WT"

  # 헌법을 워크트리 CLAUDE.md로 복사
  cp "$PROJECT_ROOT/rules/autonomous-loop.md" "$WT/CLAUDE.md" \
    || die "rules/autonomous-loop.md를 찾을 수 없음. 스킬이 정상 설치됐는지 확인하세요."

  # 템플릿 디렉토리 존재 확인
  [[ -d "$PROJECT_ROOT/.loops/templates" ]] \
    || die ".loops/templates/가 없습니다. autonomous-loop-rule-creator 스킬을 먼저 실행하세요."
  [[ -f "$PROJECT_ROOT/.loops/PROMPT.template.md" ]] \
    || die ".loops/PROMPT.template.md가 없습니다. 스킬 설치를 확인하세요."

  # 메타 파일 시드
  mkdir -p "$WT/.loop/iterations"
  cp "$PROJECT_ROOT/.loops/PROMPT.template.md" "$WT/.loop/PROMPT.md"
  cp "$PROJECT_ROOT/.loops/templates/PLAN.template.md" "$WT/.loop/PLAN.md"
  cp "$PROJECT_ROOT/.loops/templates/NOTES.template.md" "$WT/.loop/NOTES.md"
  cp "$PROJECT_ROOT/.loops/templates/HANDOFF.template.md" "$WT/.loop/HANDOFF.md"
  cp "$PROJECT_ROOT/.loops/templates/RUN_LOG.template.md" "$WT/.loop/RUN_LOG.md"

  # 워크트리 로컬 비추적 등록 (git worktree의 .git는 파일이므로 실제 gitdir 경로 사용)
  local wt_gitdir
  wt_gitdir="$(git -C "$WT" rev-parse --git-dir)"
  mkdir -p "$wt_gitdir/info"
  {
    echo "CLAUDE.md"
    echo ".loop/"
    echo "DONE"
  } >> "$wt_gitdir/info/exclude"

  echo ""
  echo "워크트리 생성 완료: $WT"
  echo "브랜치: $BRANCH"
  echo ""
  echo "다음 파일을 채워 주세요:"
  echo "  $WT/.loop/PROMPT.md"
  echo ""
  echo "채운 후 다시 실행:"
  echo "  $0 $TASK_ID"
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
  # PROMPT.md frontmatter 분리 후 yq 파싱 (markdown body의 angle bracket이 yq를 깨지 않도록)
  # multi-line sed 블록: macOS BSD sed는 {1d; ...} 세미콜론 구문을 거부하므로 newline 사용
  sed -n '1,/^---$/{
    1d
    /^---$/d
    p
  }' "$WT/.loop/PROMPT.md" 2>/dev/null \
    | yq '.scope.include[]' 2>/dev/null \
    || true
}

read_scope_exclude() {
  sed -n '1,/^---$/{
    1d
    /^---$/d
    p
  }' "$WT/.loop/PROMPT.md" 2>/dev/null \
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
  # 최근 4 커밋의 변경 파일 셋이 두 상태로 토글되는지 검사
  local commits
  commits=$(cd "$WT" && git log --pretty=tformat:%H -4 2>/dev/null || true)
  [[ $(echo "$commits" | wc -l | tr -d ' ') -lt 4 ]] && return 0

  local sets=()
  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue
    sets+=("$(cd "$WT" && git diff-tree --no-commit-id --name-only -r "$commit" 2>/dev/null | sort | md5sum | awk '{print $1}')")
  done <<< "$commits"

  # set[0] == set[2] 그리고 set[1] == set[3]이면 토글
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

# ----- DONE 처리: 메타 파일 archive -----

archive_meta_files() {
  mkdir -p "$ARCHIVE_DIR"
  cp "$WT/.loop/PLAN.md" "$ARCHIVE_DIR/" 2>/dev/null || true
  cp "$WT/.loop/NOTES.md" "$ARCHIVE_DIR/" 2>/dev/null || true
  cp "$WT/.loop/HANDOFF.md" "$ARCHIVE_DIR/" 2>/dev/null || true
  cp "$WT/.loop/RUN_LOG.md" "$ARCHIVE_DIR/" 2>/dev/null || true

  echo ""
  echo "task $TASK_ID 완료. 메타 파일 보관: $ARCHIVE_DIR"
  echo ""
  echo "머지 검토:"
  echo "  cd $PROJECT_ROOT"
  echo "  git log $BRANCH"
  echo "  git merge $BRANCH"
  echo "  git worktree remove $WT"
  echo "  git branch -d $BRANCH"
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
      < .loop/PROMPT.md \
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
  # sentinel-aware: 처음에 디렉토리/매니페스트가 없었으면 최초 생성은 위반이 아님
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

# ----- 메인 -----

if [[ ! -d "$WT" ]]; then
  create_worktree
  exit 0
fi

# 워크트리 존재 → 이터레이션 루프 진입
acquire_lock

START_TIME=$(date +%s)
n=0

while true; do
  n=$((n + 1))

  set +e
  iterate
  iter_status=$?
  set -e

  if [[ $iter_status -eq 100 ]]; then
    echo "[$(now_iso)] DONE 신호 감지. 정상 종료."
    archive_meta_files
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
    # halt가 이미 종료시킴. 도달 안 해야 함.
    exit "$iter_status"
  fi

  if [[ $n -ge $MAX_ITERATIONS ]]; then
    halt "이터 상한 도달 ($n / $MAX_ITERATIONS)"
  fi

  if [[ $(elapsed_minutes) -ge $WALL_CLOCK_MINUTES ]]; then
    halt "시계 캡 도달 ($(elapsed_minutes) / $WALL_CLOCK_MINUTES 분)"
  fi
done
