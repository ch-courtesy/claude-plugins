#!/bin/sh
# autopilot 대화형 세션 compaction handoff — 공유 헬퍼.
# pre-compact.sh(캡처)와 session-restore.sh(복원)가 source 한다.
# 어떤 함수도 세션·컴팩션을 차단하지 않는다(호출측이 항상 exit 0).

# 프로젝트(작업 공간) 루트 결정.
# 우선순위: CLAUDE_PROJECT_DIR env → 인자로 받은 stdin cwd → 현재 PWD.
handoff_project_dir() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
  elif [ -n "${1:-}" ]; then
    printf '%s' "$1"
  else
    printf '%s' "$PWD"
  fi
}

# loop 헤드리스 작업 공간 식별.
# loop 드라이버는 워크트리 top-level 에 `.loop/`(노트·신호·메타)를 만든다 —
# 대화형 세션의 cwd 에는 존재하지 않는다. 명시적 opt-out env 도 존중한다.
handoff_is_loop_workspace() {
  dir=${1:-$PWD}
  [ "${AUTOPILOT_HANDOFF_DISABLE:-}" = "1" ] && return 0
  [ -d "$dir/.loop" ] && return 0
  return 1
}

handoff_state_dir() { printf '%s/.autopilot' "${1:-$PWD}"; }
handoff_dir()       { printf '%s/.autopilot/handoff' "${1:-$PWD}"; }
handoff_file()      { printf '%s/.autopilot/handoff/HANDOFF.md' "${1:-$PWD}"; }

# 상태 디렉토리를 만들고 git 추적에서 제외(.autopilot/.gitignore = "*").
# 소비자 repo 의 root .gitignore 를 건드리지 않고 자가-무시 디렉토리를 보장한다.
handoff_ensure_state_dir() {
  dir=$1
  sd=$(handoff_state_dir "$dir")
  mkdir -p "$(handoff_dir "$dir")" 2>/dev/null || return 1
  if [ ! -f "$sd/.gitignore" ]; then
    printf '# autopilot self-state — not tracked\n*\n' > "$sd/.gitignore" 2>/dev/null || true
  fi
  return 0
}

# 관찰 가능한 진단 로그(차단하지 않음). stderr + 상태 디렉토리의 last-error 파일.
handoff_log() {
  dir=$1; shift
  msg=$*
  printf '[autopilot-handoff] %s\n' "$msg" >&2 || true
  sd=$(handoff_state_dir "$dir")
  [ -d "$sd" ] && printf '%s\n' "$msg" >> "$sd/handoff.log" 2>/dev/null || true
}

# stdin JSON 에서 문자열 필드 추출(jq 우선, 없으면 degraded grep).
# 사용: echo "$JSON" | handoff_json_field <key>
handoff_json_field() {
  key=$1
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
  else
    # degraded: "key":"value" 단순 추출(중첩·이스케이프 미지원, best-effort).
    sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
  fi
}
