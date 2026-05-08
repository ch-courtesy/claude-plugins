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
  die "사용: $0 <task-id>"
fi

TASK_ID="$1"

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
ARCHIVE_DIR="$PROJECT_ROOT/.loops/archive/$TASK_ID_SAFE"

# 캡 기본값
MAX_ITERATIONS="${MAX_ITERATIONS:-30}"
WALL_CLOCK_MINUTES="${WALL_CLOCK_MINUTES:-120}"
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

  # 메타 파일 시드
  mkdir -p "$WT/.loop/iterations"
  cp "$PROJECT_ROOT/.loops/PROMPT.template.md" "$WT/.loop/PROMPT.md"
  cp "$PROJECT_ROOT/.loops/templates/PLAN.template.md" "$WT/.loop/PLAN.md"
  cp "$PROJECT_ROOT/.loops/templates/NOTES.template.md" "$WT/.loop/NOTES.md"
  cp "$PROJECT_ROOT/.loops/templates/HANDOFF.template.md" "$WT/.loop/HANDOFF.md"
  cp "$PROJECT_ROOT/.loops/templates/RUN_LOG.template.md" "$WT/.loop/RUN_LOG.md"

  # 워크트리 로컬 비추적 등록
  {
    echo "CLAUDE.md"
    echo ".loop/"
    echo "DONE"
  } >> "$WT/.git/info/exclude"

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

# ----- 메인 -----

if [[ ! -d "$WT" ]]; then
  create_worktree
  exit 0
fi

# 이후 분기는 Task 7~9에서 추가
echo "TODO: 이터레이션 루프 진입 — Task 7~9에서 구현"
exit 0
