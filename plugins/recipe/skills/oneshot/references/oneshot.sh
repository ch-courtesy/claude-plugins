#!/usr/bin/env bash
# oneshot.sh — 외부 에이전트를 격리 환경에서 1회 실행하고 결과를 JSON 으로 반환한다.
#
# 계약: stdin 으로 입력 JSON, stdout 으로 출력 JSON (진단 메시지는 전부 stderr).
# 반복·종료 판정은 하지 않는다 — 재료(exit_code·signals·commits)만 돌려주고
# 판정은 호출자(pipeline while 노드 등)의 몫이다.
#
# 입력 (JSON 객체):
#   prompt              (string, 필수)  에이전트에 줄 지시
#   system_prompt_file  (string)        지침 파일 경로 — 호출자가 규율을 주입
#   isolation           (string)        worktree(기본) | cwd | tmpdir
#   repo                (string)        대상 저장소 (기본: cwd)
#   vendor              (string)        claude(기본) | codex
#   workdir_name        (string)        worktree/tmpdir 작업 공간 이름 (기본: oneshot)
#
# 출력 (JSON 객체): exit_code, output, log_path, workdir, commits, dirty, signals

set -euo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_tool() { command -v "$1" >/dev/null 2>&1 || die "'$1' 명령이 필요합니다."; }

# ----- 프로세스 트리 종료 (에이전트가 남긴 자손까지 완결 종료) -----
proc_alive() { kill -0 "$1" 2>/dev/null; }
proc_children() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -P "$1" 2>/dev/null || true
  elif command -v ps >/dev/null 2>&1; then
    # BSD/macOS ps 는 --ppid 미지원 — 전체 목록에서 ppid 매칭.
    ps -axo pid=,ppid= 2>/dev/null | awk -v p="$1" '$2 == p {print $1}' || true
  fi
}
tree_pids() {
  printf '%s\n' "$1"
  local c; for c in $(proc_children "$1"); do tree_pids "$c"; done
}
terminate_tree() {
  local root="$1" pids p i
  pids=$(tree_pids "$root" 2>/dev/null | grep -E '^[0-9]+$' | sort -un)
  while IFS= read -r p; do [[ -n "$p" ]] && kill -TERM "$p" 2>/dev/null || true; done <<< "$pids"
  for ((i = 0; i < 5; i++)); do
    proc_alive "$root" || return 0
    sleep 1
  done
  while IFS= read -r p; do [[ -n "$p" ]] && kill -KILL "$p" 2>/dev/null || true; done <<< "$pids"
}

# ----- 입력 파싱 -----
require_tool jq
require_tool git
INPUT="$(cat)"
[[ -n "$INPUT" ]] || die "stdin 으로 입력 JSON 이 필요합니다."
jq -e . >/dev/null 2>&1 <<< "$INPUT" || die "입력이 올바른 JSON 이 아닙니다."

field() { jq -r --arg k "$1" --arg d "$2" '.[$k] // $d' <<< "$INPUT"; }
PROMPT="$(field prompt '')"
SYSTEM_FILE="$(field system_prompt_file '')"
ISOLATION="$(field isolation worktree)"
REPO="$(field repo '')"
VENDOR="$(field vendor claude)"
WORKDIR_NAME="$(field workdir_name oneshot)"

[[ -n "$PROMPT" ]] || die "prompt 는 필수입니다."
case "$ISOLATION" in worktree|cwd|tmpdir) ;; *) die "지원하지 않는 isolation: $ISOLATION (worktree, cwd, tmpdir)" ;; esac
case "$VENDOR" in claude|codex) ;; *) die "지원하지 않는 vendor: $VENDOR (claude, codex)" ;; esac
require_tool "$VENDOR"
[[ -z "$SYSTEM_FILE" || -f "$SYSTEM_FILE" ]] || die "system_prompt_file 을 찾을 수 없음: $SYSTEM_FILE"
[[ -n "$SYSTEM_FILE" ]] && SYSTEM_FILE="$(cd "$(dirname "$SYSTEM_FILE")" && pwd -P)/$(basename "$SYSTEM_FILE")"

# 저장소 경로 정규화 — 심볼릭 별칭으로 같은 저장소가 다른 문자열이 되지 않게.
[[ -n "$REPO" ]] || REPO="$PWD"
REPO="$(cd "$REPO" 2>/dev/null && pwd -P)" || die "repo 경로에 접근할 수 없음"
git -C "$REPO" rev-parse --git-common-dir >/dev/null 2>&1 || die "repo 가 git 저장소가 아닙니다: $REPO"

# ----- 작업 공간 준비 -----
LOCK_FILE=""
case "$ISOLATION" in
  cwd)
    WORKDIR="$REPO"
    ;;
  worktree)
    WORKDIR="$REPO/.$WORKDIR_NAME-worktree"
    LOCK_FILE="$REPO/.$WORKDIR_NAME-lock"
    ;;
  tmpdir)
    WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/$WORKDIR_NAME.XXXXXX")"
    ;;
esac

# 동시 실행 방지 — 같은 작업 공간을 두 실행이 함께 쓰지 않게 (worktree 한정).
if [[ -n "$LOCK_FILE" ]]; then
  if [[ -f "$LOCK_FILE" ]]; then
    old_pid="$(cat "$LOCK_FILE" 2>/dev/null || echo "")"
    if [[ -n "$old_pid" ]] && proc_alive "$old_pid"; then
      die "이미 실행 중입니다 (PID $old_pid): $WORKDIR"
    fi
    printf 'WARN: stale lock 정리 (PID %s 비활성)\n' "${old_pid:-none}" >&2
    rm -f "$LOCK_FILE"
  fi
  ( set -C; echo "$$" > "$LOCK_FILE" ) 2>/dev/null || die "lock 획득 실패 (race): $LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT
fi

if [[ "$ISOLATION" != "cwd" && ! -d "$WORKDIR/.git" && ! -f "$WORKDIR/.git" ]]; then
  printf 'oneshot: 워크트리 생성 %s (로컬 HEAD 기준)\n' "$WORKDIR" >&2
  if ! git -C "$REPO" worktree add --detach "$WORKDIR" HEAD >&2; then
    # "등록됐지만 없는" 잔재가 원인일 수 있다 — prune 후 1회만 재시도.
    git -C "$REPO" worktree prune 2>/dev/null || true
    git -C "$REPO" worktree add --detach "$WORKDIR" HEAD >&2 || die "git worktree add 실패: $WORKDIR"
  fi
fi

# 실행 메타(로그·신호)는 작업 공간 안에 두되, cwd 격리에서는 저장소를 오염시키지
# 않도록 저장소 밖에 만든다 (읽기 전용 리뷰 용도라 워킹트리를 건드리면 안 된다).
if [[ "$ISOLATION" == "cwd" ]]; then
  META_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$WORKDIR_NAME-meta.XXXXXX")"
else
  META_DIR="$WORKDIR/.oneshot"
  mkdir -p "$META_DIR"
  printf '*\n' > "$META_DIR/.gitignore"   # 실행 산출물이 에이전트 커밋에 섞이지 않게
fi
mkdir -p "$META_DIR/signals"
LOG_PATH="$META_DIR/run-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"

HEAD_BEFORE="$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || echo "")"

# ----- 에이전트 1회 실행 -----
run_agent() {
  cd "$WORKDIR"
  case "$VENDOR" in
    claude)
      if [[ -n "$SYSTEM_FILE" ]]; then
        claude --print --no-session-persistence --dangerously-skip-permissions \
          --system-prompt-file "$SYSTEM_FILE" --add-dir . <<< "$PROMPT"
      else
        claude --print --no-session-persistence --dangerously-skip-permissions \
          --add-dir . <<< "$PROMPT"
      fi
      ;;
    codex)
      if [[ -n "$SYSTEM_FILE" ]]; then
        cat "$SYSTEM_FILE" - <<< "$PROMPT" | codex exec --ephemeral --sandbox workspace-write -
      else
        codex exec --ephemeral --sandbox workspace-write - <<< "$PROMPT"
      fi
      ;;
  esac
}

EXIT_CODE=0
( run_agent > "$LOG_PATH" 2>&1 ) &
AGENT_PID=$!
trap 'terminate_tree "$AGENT_PID" >/dev/null 2>&1 || true; [[ -n "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"; exit 130' INT TERM HUP QUIT
wait "$AGENT_PID" || EXIT_CODE=$?

# ----- 결과 수집 -----
HEAD_AFTER="$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || echo "")"
if [[ -n "$HEAD_BEFORE" && "$HEAD_AFTER" != "$HEAD_BEFORE" ]]; then
  COMMITS_JSON="$(git -C "$WORKDIR" log --format=%H "$HEAD_BEFORE..$HEAD_AFTER" 2>/dev/null | jq -R . | jq -sc .)"
else
  COMMITS_JSON='[]'
fi

# dirty 는 에이전트가 만든 변경만 본다 — oneshot 자신의 산출물(메타·다른 격리
# 실행의 워크트리)은 제외해야 읽기 전용 실행이 오탐되지 않는다.
DIRTY=false
[[ -n "$(git -C "$WORKDIR" status --porcelain 2>/dev/null \
         | grep -vE '(^|/)\.[A-Za-z0-9_-]+-worktree/|(^|/)\.oneshot/' || true)" ]] && DIRTY=true

# 신호: 에이전트가 메타 디렉토리의 signals/ 에 남긴 파일명 목록 (내용 미파싱).
SIGNALS_JSON="$( ( cd "$META_DIR/signals" 2>/dev/null && find . -mindepth 1 -type f | sed 's|^\./||' ) | jq -R . | jq -sc .)"

jq -nc \
  --argjson exit_code "$EXIT_CODE" \
  --arg output "$(cat "$LOG_PATH" 2>/dev/null || true)" \
  --arg log_path "$LOG_PATH" \
  --arg workdir "$WORKDIR" \
  --arg meta_dir "$META_DIR" \
  --argjson commits "$COMMITS_JSON" \
  --argjson dirty "$DIRTY" \
  --argjson signals "$SIGNALS_JSON" \
  '{exit_code: $exit_code, output: $output, log_path: $log_path, workdir: $workdir,
    meta_dir: $meta_dir, commits: $commits, dirty: $dirty, signals: $signals}'
