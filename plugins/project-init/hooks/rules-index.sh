#!/bin/sh
# SessionStart hook: 이 프로젝트의 `rules/` 트리를 훑어 각 룰 파일의
# 경로 + 한 줄 목적(파일 첫 H1)을 인덱스로 세션 컨텍스트에 주입한다.
#
# 읽기 모델(이름-먼저/내용-just-in-time): 세션 시작 시엔 이름·목적만 알리고
# 전체 내용은 주입하지 않는다 — 내용은 관련 작업 직전에 읽는다.
#
# `rules/` 디렉토리가 없으면(또는 .md 가 하나도 없으면) 조용히 아무것도 하지
# 않는다(무출력, exit 0). 세션 시작을 절대 막지 않는다.
#
# 프로젝트(작업 공간) 루트 결정 우선순위:
#   CLAUDE_PROJECT_DIR env -> stdin JSON 의 cwd -> 현재 PWD.
set -u

INPUT=$(cat 2>/dev/null || true)

if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  PROJ="${CLAUDE_PROJECT_DIR}"
else
  CWD=$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  PROJ="${CWD:-$PWD}"
fi

RULES_DIR="$PROJ/rules"
[ -d "$RULES_DIR" ] || exit 0   # rules/ 없음 — 무해하게 통과.

# rules/ 아래 모든 .md 를 안정적으로 정렬해, 각 파일을
# "- <프로젝트 상대 경로> — <첫 H1>" (H1 없으면 경로만) 한 줄로 만든다.
# 첫 H1 = '# ' 로 시작하는 첫 줄(접두 '# ' 제거). '## ' 등 하위 헤딩은 제외.
body=$(
  find "$RULES_DIR" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
    rel=${f#"$PROJ"/}
    title=$(sed -n 's/^#[[:space:]]\{1,\}//p' "$f" 2>/dev/null | head -n 1)
    if [ -n "$title" ]; then
      printf '%s — %s\n' "- $rel" "$title"
    else
      printf '%s\n' "- $rel"
    fi
  done
)

[ -n "$body" ] || exit 0   # .md 없음 — 무해하게 통과.

printf '%s\n' "<project-rules-index>"
printf '%s\n' "이 프로젝트의 \`rules/\` 카테고리별 지침 목록이다(경로 + 한 줄 목적). 세션 시작 시엔 이 인덱스로 파일 이름·목적만 파악하고, 각 파일의 전체 내용은 관련 작업을 시작하기 직전에 읽고 그 내용을 예외 없이 따른다(전체 내용 선읽기 금지)."
printf '%s\n' "$body"
printf '%s\n' "</project-rules-index>"
exit 0
