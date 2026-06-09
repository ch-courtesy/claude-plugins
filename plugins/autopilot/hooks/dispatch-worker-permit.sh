#!/usr/bin/env bash
# PreToolUse 훅 — autopilot:dispatch-worker 서브에이전트가 자기 계약상 반드시 써야 하는
# 내부 호출(autopilot:loop·review 스킬, dispatch 결정적 헬퍼 bash)을 권한 프롬프트 없이
# 수행하도록 **플러그인 내부에서** 자동 허용한다. settings.json 을 건드리지 않는다.
#
# 스코프: agent_type 이 정확히 'autopilot:dispatch-worker' 인 호출만 allow 한다 — 다른
# 컨텍스트(메인·다른 서브에이전트)에는 영향 없음(아무 결정도 내지 않고 통과).
# background 서브에이전트는 프롬프트를 못 받아 자동 거부되므로, PreToolUse 단계에서 미리 allow 한다.
# 명시 deny 룰은 못 이긴다(allow 는 프롬프트만 억제) — 의도된 한계.
set -uo pipefail
input="$(cat 2>/dev/null)"

jqget() { printf '%s' "$input" | jq -r "$1 // \"\"" 2>/dev/null; }
at="$(jqget '.agent_type')"; [ -n "$at" ] || at="$(jqget '.agentType')"
tool="$(jqget '.tool_name')"; [ -n "$tool" ] || tool="$(jqget '.toolName')"

# 워커 컨텍스트가 아니면 아무 결정도 내지 않는다(정상 권한 흐름 유지).
[ "$at" = "autopilot:dispatch-worker" ] || exit 0

allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"autopilot:dispatch-worker 내부 호출(%s) 자동 허용"}}' "$1"
  exit 0
}

case "$tool" in
  Skill)
    sk="$(jqget '.tool_input.skill')"; [ -n "$sk" ] || sk="$(jqget '.toolInput.skill')"
    case "$sk" in
      autopilot:loop|autopilot:review) allow "skill:$sk" ;;
    esac ;;
  Bash)
    cmd="$(jqget '.tool_input.command')"; [ -n "$cmd" ] || cmd="$(jqget '.toolInput.command')"
    case "$cmd" in
      *dispatch/references/loop.sh*|*loop/references/loop.sh*|*integration.sh*|*review-loop.sh*|*merge.sh*|*dispatch.sh*) allow "bash:helper" ;;
    esac ;;
esac
exit 0
