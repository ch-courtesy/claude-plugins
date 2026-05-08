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
  die "사용: $0 <task-id> [--max-iterations N] [--wall-clock-minutes N]"
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
    *)
      die "알 수 없는 옵션: $1"
      ;;
  esac
done

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
    die "task $TASK_ID가 이미 동작 중 (PID: $existing_pid). 종료 후 재실행."
  fi

  echo $$ > "$LOCK_FILE"
  trap "rm -f $LOCK_FILE" EXIT
}

# ----- 이터레이션 호출 -----

iterate() {
  local n
  n=$(($(ls "$WT/.loop/iterations/"*.log 2>/dev/null | wc -l | tr -d ' ') + 1))

  echo "[$(now_iso)] 이터 #$n 시작"

  # 워크트리 안에서 호출 (cwd 격리)
  (
    cd "$WT"
    cat .loop/PROMPT.md | claude \
      --print \
      --no-session-persistence \
      --dangerously-skip-permissions \
      --system-prompt-file CLAUDE.md \
      --add-dir . \
      --output-format json \
      > ".loop/iterations/$n.log" 2>&1
  )

  local exit_code=$?
  echo "[$(now_iso)] 이터 #$n 종료 (exit: $exit_code)"

  if [[ $exit_code -ne 0 ]]; then
    echo "WARN: claude 호출이 0이 아닌 exit code 반환. iterations/$n.log 확인 권장."
  fi

  # 호출 결과는 워크트리 안에서 검사 (게이트는 Task 8에서 추가)
}

# ----- 메인 -----

if [[ ! -d "$WT" ]]; then
  create_worktree
  exit 0
fi

# 워크트리 존재 → 이터레이션 루프 진입
acquire_lock

START_TIME=$(date +%s)

while true; do
  iterate

  # 종료 조건은 Task 8에서 추가
  break  # 임시: 한 번만 돌고 종료
done

echo "[$(now_iso)] 루프 종료 (한 이터 후 임시 종료. Task 8 이후 정식 루프)"
