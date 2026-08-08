#!/usr/bin/env bash
# oneshot.sh — 외부 에이전트 CLI 를 1회 실행하는 raw 래퍼 (claude -p 수준).
#
# 계약: stdin 으로 입력 JSON, stdout 으로 출력 JSON. 에이전트의 stderr 는 그대로
# 통과시킨다(호출자가 본다). 이 도구는 판단하지 않는다 — 격리(워크트리 준비),
# 커밋 여부, 종료 표지 규약, 입력 검증은 전부 호출자(파이프라인 노드·사람)의 몫이다.
# 다만 "지시한 대로 실행했다"는 전제(작업 디렉토리 이동·지침 파일 읽기)가 깨지면
# 조용히 진행하지 않고 중단한다 — 격리를 믿는 호출자가 속지 않게.
#
# 필요 도구: jq, 선택한 벤더 CLI.
#
# 입력 (JSON 객체):
#   prompt              (string, 필수)  에이전트에 줄 지시
#   cwd                 (string)        실행 디렉토리 (기본: 현재 디렉토리)
#   system_prompt_file  (string)        시스템 지침 파일 경로 (cwd 이동 전 기준으로 해석)
#   vendor              (string)        claude(기본) | codex | agy(=antigravity)
#
# 출력 (JSON 객체): {exit_code, output}
#   output  = 에이전트 stdout (후행 개행은 잘린다). 도구 자체 오류면 error 필드가 붙고
#             output 은 빈 문자열이다.
#   프로세스 종료 코드는 도구 자체 오류일 때만 1 이고, 에이전트가 몇으로 죽든 0 이다
#   — 에이전트 성패는 exit_code 필드로 판정한다.
#
# 벤더별 관례 차이는 이 층이 흡수한다: claude 는 프롬프트를 stdin 으로 받고 시스템
# 지침을 파일 옵션으로 받는다. codex 는 프롬프트를 stdin 으로 받되 지침 옵션이 없어
# 선두 병합한다. agy 는 프롬프트를 --print 의 인자로 받고 지침도 선두 병합한다.

set -uo pipefail

emit() { jq -nc --argjson c "$1" --rawfile o "$2" '{exit_code: $c, output: $o}'; }
fail() { jq -nc --arg e "$1" '{exit_code: 1, output: "", error: $e}'; exit 1; }

command -v jq >/dev/null 2>&1 || { printf 'ERROR: jq 가 필요합니다.\n' >&2; exit 1; }

INPUT="$(cat)"
PROMPT="$(jq -r '.prompt // empty' <<< "$INPUT")"
CWD="$(jq -r '.cwd // empty' <<< "$INPUT")"
SYSTEM_FILE="$(jq -r '.system_prompt_file // empty' <<< "$INPUT")"
VENDOR="$(jq -r '.vendor // "claude"' <<< "$INPUT")"
[[ "$VENDOR" == "antigravity" ]] && VENDOR=agy

# 지침 파일은 cwd 이동 전에 읽는다 — 이동 후 상대 경로 해석이 바뀌어 엉뚱한 파일이
# 지침으로 들어가는 것을 막는다. 읽기 실패는 조용히 넘기지 않는다.
SYSTEM_TEXT=""
if [[ -n "$SYSTEM_FILE" ]]; then
  SYSTEM_TEXT="$(cat "$SYSTEM_FILE" 2>/dev/null)" \
    || fail "system_prompt_file 을 읽을 수 없음: $SYSTEM_FILE"
  SYSTEM_ABS="$(cd "$(dirname "$SYSTEM_FILE")" 2>/dev/null && pwd -P)/$(basename "$SYSTEM_FILE")" \
    || fail "system_prompt_file 경로 해석 실패: $SYSTEM_FILE"
fi

# 이동 실패는 치명적이다 — 실패를 무시하면 호출자가 격리했다고 믿는 사이
# 무인 권한 에이전트가 호출자의 현재 디렉토리에서 뜬다.
# CDPATH 가 설정돼 있으면 cd 가 stdout 에 경로를 찍어 출력 JSON 을 오염시키므로 끈다.
if [[ -n "$CWD" ]]; then
  CDPATH= cd "$CWD" >/dev/null 2>&1 || fail "cwd 로 이동할 수 없음: $CWD"
fi

# 출력은 임시 파일로 받는다 — argv 로 넘기면 긴 출력에서 ARG_MAX 를 넘겨 결과를
# 통째로 잃는다.
OUT_FILE="$(mktemp "${TMPDIR:-/tmp}/oneshot.XXXXXX")" || fail "임시 파일 생성 실패"
trap 'rm -f "$OUT_FILE"' EXIT

merged_prompt() {
  [[ -n "$SYSTEM_TEXT" ]] && printf '%s\n\n' "$SYSTEM_TEXT"
  printf '%s\n' "$PROMPT"
}

CODE=0
case "$VENDOR" in
  claude)
    sys=()
    [[ -n "$SYSTEM_FILE" ]] && sys=(--system-prompt-file "$SYSTEM_ABS")
    # bash 3.2 는 빈 배열 확장을 unbound 로 보므로 ${arr[@]+"${arr[@]}"} 관용구.
    claude --print --no-session-persistence --dangerously-skip-permissions \
      ${sys[@]+"${sys[@]}"} --add-dir . > "$OUT_FILE" <<< "$PROMPT" || CODE=$?
    ;;
  codex)
    merged_prompt | codex exec --ephemeral --sandbox workspace-write - > "$OUT_FILE" || CODE=$?
    ;;
  agy)
    # 프롬프트를 stdin 이 아니라 --print 의 값으로 받는다.
    agy --print "$(merged_prompt)" --dangerously-skip-permissions --add-dir . > "$OUT_FILE" || CODE=$?
    ;;
  *)
    fail "지원하지 않는 vendor: $VENDOR (claude, codex, agy)"
    ;;
esac

emit "$CODE" "$OUT_FILE"
