#!/bin/sh
# PreToolUse 이벤트 핸들러 — stdin JSON 을 1회 읽어 lib command 로 위임한다.
input="$(cat)"
printf %s "$input" >/dev/null
exit 0
