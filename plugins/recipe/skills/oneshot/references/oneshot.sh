#!/usr/bin/env bash
# oneshot.sh — 외부 에이전트를 격리 환경에서 1회 실행하고 결과를 JSON 으로 반환한다.
#
# 계약: stdin 으로 입력 JSON, stdout 으로 출력 JSON (진단 메시지는 전부 stderr).
# 반복·종료 판정은 하지 않는다 — 재료(exit_code·output·commits·dirty)만 돌려주고
# 판정은 호출자(pipeline while 노드 등)의 몫이다. 종료 표지가 필요하면 호출자가
# 프롬프트에서 규약을 정하고(예: 마지막 줄에 <<DONE>>) output 으로 판정한다.
#
# 입력 (JSON 객체):
#   prompt              (string, 필수)  에이전트에 줄 지시
#   system_prompt_file  (string)        지침 파일 경로 — 호출자가 규율을 주입
#   isolation           (string)        worktree(기본) | cwd | tmpdir
#   repo                (string)        대상 저장소 (기본: cwd)
#   vendor              (string)        claude(기본) | codex
#   workdir_name        (string)        작업 공간·lock·로그 디렉토리 이름 ([A-Za-z0-9_-], 기본: oneshot)
#
# 출력 (JSON 객체): exit_code, output, log_path, workdir, commits, dirty
#   실패 시에도 같은 형태에 error 필드를 더해 반환한다 (stdout 은 언제나 JSON 하나).
#   output 은 로그 꼬리 최대 ONESHOT_OUTPUT_BYTES(기본 100000) 바이트를 UTF-8 정제한 것.

set -euo pipefail

# 실패도 stdout 은 JSON 하나 — 호출자(파이프라인 while 등)가 파싱 실패 대신
# 구조화된 결과를 받는다. 사람용 메시지는 stderr 로도 남긴다.
die() {
  printf 'ERROR: %s\n' "$*" >&2
  jq -nc --arg e "$*" --arg w "${WORKDIR:-}" --arg l "${LOG_PATH:-}" \
    '{exit_code: 1, error: $e, output: "", log_path: $l, workdir: $w,
      commits: [], dirty: false}' 2>/dev/null \
    || printf '{"exit_code":1,"error":"%s","output":"","log_path":"","workdir":"","commits":[],"dirty":false}\n' "$(printf '%s' "$*" | tr -d '"\\')"
  exit 1
}
require_tool() { command -v "$1" >/dev/null 2>&1 || die "'$1' 명령이 필요합니다."; }

# ----- 프로세스 트리 종료 (에이전트가 남긴 자손까지 완결 종료) -----
proc_alive() { kill -0 "$1" 2>/dev/null; }
proc_children() { pgrep -P "$1" 2>/dev/null || true; }
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
require_tool pgrep
INPUT="$(cat)"
[[ -n "$INPUT" ]] || die "stdin 으로 입력 JSON 이 필요합니다."
jq -e 'type == "object"' >/dev/null 2>&1 <<< "$INPUT" || die "입력은 JSON 객체여야 합니다."

field() { jq -r --arg k "$1" --arg d "$2" '.[$k] // $d' <<< "$INPUT"; }
PROMPT="$(field prompt '')"
SYSTEM_FILE="$(field system_prompt_file '')"
ISOLATION="$(field isolation worktree)"
REPO="$(field repo '')"
VENDOR="$(field vendor claude)"
WORKDIR_NAME="$(field workdir_name oneshot)"

[[ -n "$PROMPT" ]] || die "prompt 는 필수입니다."
# 경로 요소로 쓰이므로 안전한 식별자만 — 상위 탈출·슬래시·공백 차단.
[[ "$WORKDIR_NAME" =~ ^[A-Za-z0-9_-]+$ ]] || die "workdir_name 은 [A-Za-z0-9_-] 만 허용: $WORKDIR_NAME"
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

if [[ "$ISOLATION" == "worktree" && ! -d "$WORKDIR/.git" && ! -f "$WORKDIR/.git" ]]; then
  printf 'oneshot: 워크트리 생성 %s (로컬 HEAD 기준)\n' "$WORKDIR" >&2
  if ! git -C "$REPO" worktree add --detach "$WORKDIR" HEAD >&2; then
    # "등록됐지만 없는" 잔재가 원인일 수 있다 — prune 후 1회만 재시도.
    git -C "$REPO" worktree prune 2>/dev/null || true
    git -C "$REPO" worktree add --detach "$WORKDIR" HEAD >&2 || die "git worktree add 실패: $WORKDIR"
  fi
fi

# 로그는 작업 공간 안에 두되, cwd 격리에서는 저장소를 오염시키지 않도록 밖에 만든다
# (읽기 전용 리뷰 용도라 워킹트리를 건드리면 안 된다).
if [[ "$ISOLATION" == "cwd" ]]; then
  LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$WORKDIR_NAME-log.XXXXXX")"
else
  LOG_DIR="$WORKDIR/.$WORKDIR_NAME"
  mkdir -p "$LOG_DIR"
  printf '*\n' > "$LOG_DIR/.gitignore"   # 실행 산출물이 에이전트 커밋에 섞이지 않게
fi
LOG_PATH="$LOG_DIR/run-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"

HEAD_BEFORE="$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || echo "")"

# ----- 에이전트 1회 실행 -----
# 작업 위치만 알린다 — 종료 표지 같은 규약은 호출자가 prompt 에 직접 넣는다.
FULL_PROMPT="$PROMPT

---
작업 디렉토리: $WORKDIR"

run_agent() {
  cd "$WORKDIR"
  local sys=()
  case "$VENDOR" in
    claude)
      [[ -n "$SYSTEM_FILE" ]] && sys=(--system-prompt-file "$SYSTEM_FILE")
      # bash 3.2 는 set -u 에서 빈 배열 확장을 unbound 로 본다 — ${arr[@]+"${arr[@]}"} 관용구.
      claude --print --no-session-persistence --dangerously-skip-permissions \
        ${sys[@]+"${sys[@]}"} --add-dir . <<< "$FULL_PROMPT"
      ;;
    codex)
      # 지침과 프롬프트 사이에 빈 줄을 보장 — 파일 끝 개행 유무에 의존하지 않는다.
      { [[ -n "$SYSTEM_FILE" ]] && { cat "$SYSTEM_FILE"; printf '\n\n'; }; printf '%s\n' "$FULL_PROMPT"; } \
        | codex exec --ephemeral --sandbox workspace-write -
      ;;
  esac
}

EXIT_CODE=0
run_agent > "$LOG_PATH" 2>&1 &
AGENT_PID=$!
# EXIT 트랩이 lock 을 해제하므로 여기선 트리 종료만 한다.
trap 'terminate_tree "$AGENT_PID" >/dev/null 2>&1 || true; exit 130' INT TERM HUP QUIT
wait "$AGENT_PID" || EXIT_CODE=$?

# ----- 결과 수집 -----
HEAD_AFTER="$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || echo "")"
if [[ -z "$HEAD_AFTER" || "$HEAD_AFTER" == "$HEAD_BEFORE" ]]; then
  COMMITS_JSON='[]'
elif [[ -z "$HEAD_BEFORE" ]]; then
  # unborn HEAD 였다면 이번 실행이 만든 커밋이 전부다.
  COMMITS_JSON="$(git -C "$WORKDIR" log --format=%H 2>/dev/null | jq -R . | jq -sc .)"
else
  COMMITS_JSON="$(git -C "$WORKDIR" log --format=%H "$HEAD_BEFORE..$HEAD_AFTER" 2>/dev/null | jq -R . | jq -sc .)"
fi

# dirty 는 에이전트가 만든 변경만 본다 — oneshot 자신의 산출물(작업 공간·lock·메타)은
# 제외해야 읽기 전용 실행이 오탐되지 않는다. porcelain 은 "XY 경로" 형식이라
# 상태 코드 2자 + 공백을 건너뛰고 경로만 본다.
DIRTY=false
if git -C "$WORKDIR" rev-parse --git-dir >/dev/null 2>&1; then
  changed="$(git -C "$WORKDIR" status --porcelain 2>/dev/null \
    | sed 's/^...//' \
    | grep -vE "^\.${WORKDIR_NAME}(-worktree/|-lock$|/)" || true)"
  [[ -n "$changed" ]] && DIRTY=true
fi

# 로그는 그대로 두고 output 에는 유효 UTF-8 로 정제한 꼬리만 담는다 —
# 잘못된 바이트 하나로 결과 전체(커밋·신호)를 잃지 않게.
OUTPUT_TEXT="$(tail -c "${ONESHOT_OUTPUT_BYTES:-100000}" "$LOG_PATH" 2>/dev/null | iconv -c -f UTF-8 -t UTF-8 2>/dev/null || true)"

jq -nc \
  --argjson exit_code "$EXIT_CODE" \
  --arg output "$OUTPUT_TEXT" \
  --arg log_path "$LOG_PATH" \
  --arg workdir "$WORKDIR" \
  --argjson commits "$COMMITS_JSON" \
  --argjson dirty "$DIRTY" \
  '{exit_code: $exit_code, output: $output, log_path: $log_path, workdir: $workdir,
    commits: $commits, dirty: $dirty}'
