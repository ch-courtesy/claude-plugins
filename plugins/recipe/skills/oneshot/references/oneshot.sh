#!/usr/bin/env bash
# oneshot.sh — 외부 에이전트 CLI 를 1회 실행하는 raw 래퍼 (claude -p 수준).
#
# 계약: stdin 으로 입력 JSON, stdout 으로 출력 JSON. 에이전트의 stderr 는 그대로
# 통과시킨다(호출자가 본다). 이 도구는 판단하지 않는다 — 격리(작업 공간 준비),
# 커밋 여부, 종료 표지 규약, 반복은 전부 호출자의 몫이다. 다만 "지시한 대로
# 실행했다"는 전제(입력 해석·작업 디렉토리 이동·지침 파일 읽기·벤더 지원)가 깨지면
# 조용히 진행하지 않고 도구 오류로 중단한다 — 격리를 믿는 호출자가 속지 않게.
#
# 필요 도구: jq, 선택한 벤더 CLI.
#
# 입력 (JSON 객체):
#   prompt              (string)  에이전트에 줄 지시
#   cwd                 (string)  실행 디렉토리 (기본: 현재 디렉토리)
#   system_prompt_file  (string)  시스템 지침 파일 (cwd 이동 전 기준으로 해석,
#                                 내용이 비어 있으면 지침 없이 실행)
#   vendor              (string)  claude(기본) | codex | agy (별칭: antigravity)
#
# 출력 (JSON 객체): {exit_code, output} — output 은 에이전트 stdout, 후행 개행 제거.
#   도구 자체 오류면 {exit_code: 1, output: "", error: "..."} 이고 프로세스도 1 이다.
#   에이전트가 몇으로 죽든 프로세스는 0 이므로, 에이전트 성패는 exit_code 로 본다.
#
# 벤더별 관례 차이는 이 층이 흡수한다: 지침은 프롬프트 선두에 병합하고, 프롬프트는
# claude·codex 는 stdin 으로, agy 는 --print 의 인자로 넘긴다.

set -uo pipefail

fail() { jq -nc --arg e "$1" '{exit_code: 1, output: "", error: $e}' 2>/dev/null \
  || printf '{"exit_code":1,"output":"","error":"도구 오류"}\n'; exit 1; }

command -v jq >/dev/null 2>&1 \
  || { printf '{"exit_code":1,"output":"","error":"jq 가 필요합니다."}\n'; exit 1; }

INPUT="$(cat)"
jq -e 'type == "object"' >/dev/null 2>&1 <<< "$INPUT" \
  || fail "입력이 JSON 객체가 아닙니다 (stdin 으로 {prompt: ...} 전달)"

PROMPT="$(jq -r '.prompt // empty' <<< "$INPUT")"
CWD="$(jq -r '.cwd // empty' <<< "$INPUT")"
SYSTEM_FILE="$(jq -r '.system_prompt_file // empty' <<< "$INPUT")"
VENDOR="$(jq -r '.vendor // "claude"' <<< "$INPUT")"

# 지원 여부를 먼저 본다 — CLI 존재 검사를 앞세우면 오타·미지원 벤더가
# "설치하라"로 오보고된다.
case "$VENDOR" in
  claude|codex) ;;
  agy|antigravity) VENDOR=agy ;;
  *) fail "지원하지 않는 vendor: $VENDOR (claude, codex, agy)" ;;
esac
command -v "$VENDOR" >/dev/null 2>&1 || fail "벤더 CLI 를 찾을 수 없음: $VENDOR"

# 지침 파일은 cwd 이동 전에 읽는다 — 이동 후 상대 경로 해석이 바뀌면 엉뚱한 파일이
# 지침으로 들어간다. 읽기 실패는 조용히 넘기지 않는다.
SYSTEM_TEXT=""
if [[ -n "$SYSTEM_FILE" ]]; then
  SYSTEM_TEXT="$(cat "$SYSTEM_FILE")" || fail "system_prompt_file 을 읽을 수 없음: $SYSTEM_FILE"
fi

# 이동 실패는 치명적이다 — 무시하면 호출자가 격리했다고 믿는 사이 무인 권한
# 에이전트가 호출자의 현재 디렉토리에서 뜬다. CDPATH 는 cd 가 stdout 에 경로를
# 찍어 출력 JSON 을 오염시키므로 끈다.
[[ -z "$CWD" ]] || CDPATH= cd "$CWD" || fail "cwd 로 이동할 수 없음: $CWD"

# 프롬프트·출력 모두 파일 경유 — argv 로 넘기면 긴 입력·출력에서 ARG_MAX 를 넘겨
# 실행 자체가 실패하고, 그 실패가 에이전트 실패로 위장된다. argv 는 ps 로 내용이
# 노출되기도 한다.
IN_FILE="$(mktemp)" && OUT_FILE="$(mktemp)" || fail "임시 파일 생성 실패"
trap 'rm -f "$IN_FILE" "$OUT_FILE"' EXIT
{ [[ -z "$SYSTEM_TEXT" ]] || printf '%s\n\n' "$SYSTEM_TEXT"; printf '%s\n' "$PROMPT"; } > "$IN_FILE" \
  || fail "프롬프트 파일 쓰기 실패 (디스크 여유 확인)"

CODE=0
case "$VENDOR" in
  claude)
    claude --print --no-session-persistence --dangerously-skip-permissions \
      --add-dir . < "$IN_FILE" > "$OUT_FILE" || CODE=$?
    ;;
  codex)
    codex exec --ephemeral --sandbox workspace-write - < "$IN_FILE" > "$OUT_FILE" || CODE=$?
    ;;
  agy)
    # 프롬프트를 stdin 이 아니라 --print 의 값으로 받는 유일한 벤더.
    agy --print "$(cat "$IN_FILE")" --dangerously-skip-permissions --add-dir . > "$OUT_FILE" || CODE=$?
    ;;
esac

# jq 는 잘못된 바이트를 U+FFFD 로 치환하고 성공하므로 인코딩 오류 폴백은 두지 않는다
# — 바이너리 출력은 손실될 수 있고, 원본이 필요하면 호출자가 stderr·리다이렉트로 받는다.
jq -nc --argjson c "$CODE" --rawfile o "$OUT_FILE" \
  '{exit_code: $c, output: ($o | sub("\n+$"; ""))}' || fail "결과 JSON 생성 실패"
