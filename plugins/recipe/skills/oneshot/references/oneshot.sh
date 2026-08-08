#!/usr/bin/env bash
# oneshot.sh — 외부 에이전트 CLI 를 1회 실행하는 raw 래퍼 (claude -p 수준).
#
# 계약: stdin 으로 입력 JSON, stdout 으로 출력 JSON. 에이전트의 stderr 는 그대로
# 통과시킨다(호출자가 본다). 이 도구는 판단하지 않는다 — 격리(작업 공간 준비),
# 커밋 여부, 종료 표지 규약, 반복은 전부 호출자의 몫이다. 다만 "지시한 대로
# 실행했다"는 전제(입력 해석·벤더 지원·작업 디렉토리 이동·지침 파일 읽기)가 깨지면
# 조용히 진행하지 않고 도구 오류로 중단한다 — 격리를 믿는 호출자가 속지 않게.
#
# 필요 도구: jq, 선택한 벤더 CLI.
#
# 입력 (JSON 객체):
#   prompt              (string)  에이전트에 줄 지시 (비어 있어도 막지 않는다)
#   cwd                 (string)  실행 디렉토리 (기본: 현재 디렉토리)
#   system_prompt_file  (string)  시스템 지침 파일 (cwd 이동 전 기준으로 해석,
#                                 내용이 비어 있으면 지침 없이 실행)
#   vendor              (string)  claude(기본) | codex | agy (별칭: antigravity)
#
# 출력 (JSON 객체): {exit_code, output}
#   output     에이전트 stdout — 후행 공백·개행(CR 포함)을 제거해 마지막 줄이 실제
#              마지막 내용이 되게 한다. NUL 바이트는 보존하지 않는다.
#   exit_code  에이전트 종료 코드. 도구 자체 오류면 {exit_code: 1, output: "", error: "..."}
#              이고 프로세스도 1 이다 — 에이전트가 몇으로 죽든 프로세스는 0 이므로
#              에이전트 성패는 반드시 exit_code 필드로 본다.
#
# 벤더 관례 차이는 이 층이 흡수한다: 지침은 프롬프트 선두에 병합하고, 프롬프트는
# claude·codex 에 stdin 으로 준다. agy 만 stdin 을 받지 않아 인자로 넘기므로,
# 프롬프트+지침이 커지면 agy 경로에서만 실행이 실패하고(macOS 는 인자 총합 약 1MB,
# Linux 는 인자 하나당 128KiB 가 먼저 걸린다) 그 내용이 실행 중 ps 에 노출된다 —
# 큰 지침을 쓸 때는 claude·codex 를 쓴다.

set -u

command -v jq >/dev/null \
  || { printf '{"exit_code":1,"output":"","error":"jq 가 필요합니다."}\n'; exit 1; }

fail() { jq -nc --arg e "$1" '{exit_code: 1, output: "", error: $e}'; exit 1; }

INPUT="$(cat)"
# -s 로 문서 수까지 본다 — 객체 검사만 하면 이어붙은 다중 문서가 통과해 필드마다
# 여러 값이 잡히고, 그 결과가 엉뚱한 곳(벤더 케이스)에서 실패로 나타난다.
jq -es 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1 <<< "$INPUT" \
  || fail "입력이 JSON 객체 하나가 아닙니다 (stdin 으로 {prompt: ...} 전달)"

PROMPT="$(jq -r '.prompt // empty' <<< "$INPUT")"
CWD="$(jq -r '.cwd // empty' <<< "$INPUT")"
SYSTEM_FILE="$(jq -r '.system_prompt_file // empty' <<< "$INPUT")"
VENDOR="$(jq -r '.vendor // "claude"' <<< "$INPUT")"

# 지원 여부를 CLI 존재 검사보다 먼저 본다 — 순서가 반대면 오타·미지원 벤더가
# "설치하라"로 오보고된다.
case "$VENDOR" in
  claude|codex) ;;
  agy|antigravity) VENDOR=agy ;;
  *) fail "지원하지 않는 vendor: $VENDOR (claude, codex, agy)" ;;
esac
command -v "$VENDOR" >/dev/null || fail "벤더 CLI 를 찾을 수 없음: $VENDOR"

# 지침 파일은 cwd 이동 전에 읽는다 — 이동 후 상대 경로 해석이 바뀌면 엉뚱한 파일이
# 지침으로 들어간다. 읽기 실패는 조용히 넘기지 않는다.
FULL="$PROMPT"
if [[ -n "$SYSTEM_FILE" ]]; then
  SYSTEM_TEXT="$(cat "$SYSTEM_FILE")" || fail "system_prompt_file 을 읽을 수 없음: $SYSTEM_FILE"
  [[ -z "$SYSTEM_TEXT" ]] || FULL="$SYSTEM_TEXT

$PROMPT"   # 빈 지침이면 프롬프트만 — 선두 빈 줄을 만들지 않는다
fi

# 이동 실패는 치명적이다 — 무시하면 호출자가 격리했다고 믿는 사이 무인 권한
# 에이전트가 호출자의 현재 디렉토리에서 뜬다. CDPATH 는 cd 가 stdout 에 경로를
# 찍어 출력 JSON 을 오염시키므로 끈다.
[[ -z "$CWD" ]] || CDPATH= cd "$CWD" || fail "cwd 로 이동할 수 없음: $CWD"

CODE=0
case "$VENDOR" in
  claude)
    OUTPUT="$(claude --print --no-session-persistence --dangerously-skip-permissions \
      --add-dir . <<< "$FULL")" || CODE=$?
    ;;
  codex)
    OUTPUT="$(codex exec --ephemeral --sandbox workspace-write - <<< "$FULL")" || CODE=$?
    ;;
  agy)
    OUTPUT="$(agy --print "$FULL" --dangerously-skip-permissions --add-dir .)" || CODE=$?
    ;;
esac

# 출력은 파이프로 넘긴다 — argv(--arg)로 주면 큰 출력에서 jq 가 exec 되지 못해
# stdout 이 통째로 비고(계약 위반) 프로세스 코드도 규약 밖 값이 된다. printf 는
# 빌트인이라 크기 제한이 없다. -Rs 로 전체를 문자열 하나로 읽는다.
printf '%s' "$OUTPUT" | jq -Rs --argjson c "$CODE" \
  '{exit_code: $c, output: (. | sub("[[:space:]]+$"; ""))}'
