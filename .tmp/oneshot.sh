#!/usr/bin/env bash
# usage: oneshot.sh <claude|codex|agy> "<prompt>" [extra flags...]
# 안전 기본값은 리뷰 대상 콘텐츠의 프롬프트 주입 방어용(실증됨). 신뢰된 호출자는 extra flags로 재정의 가능.
# codex --sandbox는 중복 불가(-c sandbox_mode로는 변경 가능).
set -euo pipefail

[ $# -ge 2 ] || { echo "usage: oneshot.sh <claude|codex|agy> \"<prompt>\" [extra flags...]" >&2; exit 2; }
agent="$1"; prompt="$2"; shift 2
[ $# -eq 0 ] || case "$1" in --|-) echo "bare '-' or '--' not allowed as first extra: $1" >&2; exit 2 ;; -*) ;; *) echo "extra flags must start with '-': $1" >&2; exit 2 ;; esac
for a in "$@"; do [ "$a" = "--" ] && { echo "'--' not allowed in extra flags (breaks prompt isolation)" >&2; exit 2; }; done

case "$agent" in
  claude) exec claude -p --allowedTools=Read,Grep,Glob --disallowedTools=Bash,Edit,Write,NotebookEdit "$@" -- "$prompt" ;;
  codex)  exec codex exec --sandbox read-only "$@" -- "$prompt" ;;
  agy)    exec agy -p --mode plan "$@" -- "$prompt" ;;
  *)      echo "unknown agent: $agent (claude|codex|agy)" >&2; exit 2 ;;
esac
