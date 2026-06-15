#!/bin/sh
# SessionStart hook(복원 단계): 핸드오프 문서가 있으면 그 내용을 새 세션 컨텍스트로
# 주입한다(stdout → 세션 컨텍스트). 기존 session-start.sh 의 using-autopilot 라우팅
# 주입과 별개 엔트리로 공존한다(둘 다 동작).
#
# 절대 차단하지 않는다: 핸드오프 부재·읽기 실패 시 조용히 통과(빈 출력, exit 0).
# loop 헤드리스 작업 공간(`.loop/`)에서는 복원하지 않는다.
#
# stdin(JSON): {session_id, source, cwd, hook_event_name, ...}

ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}}"
if [ -f "$ROOT/handoff-common.sh" ]; then
  . "$ROOT/handoff-common.sh"
elif [ -f "$ROOT/hooks/handoff-common.sh" ]; then
  . "$ROOT/hooks/handoff-common.sh"
else
  exit 0
fi

INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | handoff_json_field cwd)
PROJ=$(handoff_project_dir "$CWD")

# AC4: loop 헤드리스 작업 공간이면 복원하지 않는다.
handoff_is_loop_workspace "$PROJ" && exit 0

OUT=$(handoff_file "$PROJ")
[ -f "$OUT" ] || exit 0   # 핸드오프 없음 — 무해하게 통과.

# 내용을 컨텍스트로 주입. 래퍼로 출처를 명시한다.
printf '%s\n' "<session-handoff source=\"autopilot-precompact\">"
printf '%s\n' "이전 세션이 자동 컴팩션 경계에서 남긴 작업 핸드오프다. 이어서 작업하라."
cat "$OUT" 2>/dev/null || true
printf '\n%s\n' "</session-handoff>"

# 복원 후 보관: 다음 세션이 stale 핸드오프를 다시 주입하지 않도록 archive 로 이동.
ARCHIVE="$(handoff_dir "$PROJ")/restored"
if mkdir -p "$ARCHIVE" 2>/dev/null; then
  mv "$OUT" "$ARCHIVE/HANDOFF.last.md" 2>/dev/null || true
fi

exit 0
