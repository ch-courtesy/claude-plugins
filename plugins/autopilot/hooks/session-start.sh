#!/bin/sh
# SessionStart hook: autopilot이 설치된 프로젝트에서 using-autopilot 라우팅 지침을
# <EXTREMELY_IMPORTANT> 컨텍스트로 주입한다. 내용의 단일 출처는 using-autopilot/SKILL.md다 —
# 본 스크립트는 래퍼 태그만 덧붙이고 내용을 복제하지 않는다.
set -eu

# 런타임 plugin root가 있으면 사용하고, 없으면 스크립트 위치 기준으로 자기 위치를 찾는다.
ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}}"
SKILL_FILE="$ROOT/skills/using-autopilot/SKILL.md"

# 스킬 본문이 없으면 조용히 통과(세션 시작을 막지 않는다).
[ -f "$SKILL_FILE" ] || exit 0

printf '%s\n' "<EXTREMELY_IMPORTANT>"
cat "$SKILL_FILE"
printf '\n%s\n' "</EXTREMELY_IMPORTANT>"
