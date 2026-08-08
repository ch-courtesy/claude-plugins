#!/usr/bin/env bash
# oneshot.sh — 외부 에이전트 CLI 를 1회 실행하는 raw 래퍼 (claude -p 수준).
#
# 계약: stdin 으로 입력 JSON, stdout 으로 출력 JSON. 에이전트의 stderr 는 그대로
# 통과시킨다(호출자가 본다). 이 도구는 판단하지 않는다 — 격리(워크트리 준비),
# 커밋 여부, 종료 표지 규약, 입력 검증은 전부 호출자(래퍼·파이프라인 노드)의 몫이다.
#
# 입력 (JSON 객체):
#   prompt              (string, 필수)  에이전트에 줄 지시
#   cwd                 (string)        실행 디렉토리 (기본: 현재 디렉토리)
#   system_prompt_file  (string)        시스템 지침 파일 경로
#   vendor              (string)        claude(기본) | codex
#
# 출력 (JSON 객체): {exit_code, output}  — output 은 에이전트 stdout 전문.

set -uo pipefail

emit() { jq -nc --argjson c "$1" --arg o "$2" '{exit_code: $c, output: $o}'; }

INPUT="$(cat)"
PROMPT="$(jq -r '.prompt // empty' <<< "$INPUT")"
CWD="$(jq -r '.cwd // empty' <<< "$INPUT")"
SYSTEM_FILE="$(jq -r '.system_prompt_file // empty' <<< "$INPUT")"
VENDOR="$(jq -r '.vendor // "claude"' <<< "$INPUT")"

[[ -n "$CWD" ]] && cd "$CWD"

case "$VENDOR" in
  claude)
    sys=()
    [[ -n "$SYSTEM_FILE" ]] && sys=(--system-prompt-file "$SYSTEM_FILE")
    # bash 3.2 는 빈 배열 확장을 unbound 로 보므로 ${arr[@]+"${arr[@]}"} 관용구.
    OUTPUT="$(claude --print --no-session-persistence --dangerously-skip-permissions \
      ${sys[@]+"${sys[@]}"} --add-dir . <<< "$PROMPT")"
    CODE=$?
    ;;
  codex)
    # 지침이 있으면 프롬프트 앞에 붙인다 (빈 줄로 분리 — 파일 끝 개행에 의존하지 않음).
    OUTPUT="$( { [[ -n "$SYSTEM_FILE" ]] && { cat "$SYSTEM_FILE"; printf '\n\n'; }; printf '%s\n' "$PROMPT"; } \
      | codex exec --ephemeral --sandbox workspace-write - )"
    CODE=$?
    ;;
  *)
    emit 1 "지원하지 않는 vendor: $VENDOR (claude, codex)"
    exit 1
    ;;
esac

emit "$CODE" "$OUTPUT"
