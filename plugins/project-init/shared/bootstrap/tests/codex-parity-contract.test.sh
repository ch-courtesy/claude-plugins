#!/usr/bin/env bash
# Static contract for shared project-init behavior and thin Claude/Codex adapters.
set -u

ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
PLUGIN="$ROOT/plugins/project-init"
CODEX_MARKETPLACE="$ROOT/.agents/plugins/marketplace.json"
CLAUDE_MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"
CODEX_MANIFEST="$PLUGIN/.codex-plugin/plugin.json"
CLAUDE_MANIFEST="$PLUGIN/.claude-plugin/plugin.json"
DEFAULT_PLUGIN_HOOKS="$PLUGIN/hooks/hooks.json"
REDUNDANT_ROOT_HOOKS="$PLUGIN/hooks.json"

fail=0
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc"; fail=1
  fi
}

check "Codex marketplace exists" test -f "$CODEX_MARKETPLACE"
check "Codex marketplace exposes only project-init" bash -c \
  "[ \"\$(jq -r '.plugins | length' '$CODEX_MARKETPLACE')\" = 1 ] && [ \"\$(jq -r '.plugins[0].name' '$CODEX_MARKETPLACE')\" = project-init ]"
check "Codex marketplace uses local project-init source" bash -c \
  "[ \"\$(jq -r '.plugins[0].source.source' '$CODEX_MARKETPLACE')\" = local ] && [ \"\$(jq -r '.plugins[0].source.path' '$CODEX_MARKETPLACE')\" = './plugins/project-init' ]"
check "Codex marketplace has required policy and category" bash -c \
  "[ \"\$(jq -r '.plugins[0].policy.installation' '$CODEX_MARKETPLACE')\" = AVAILABLE ] && [ \"\$(jq -r '.plugins[0].policy.authentication' '$CODEX_MARKETPLACE')\" = ON_INSTALL ] && [ \"\$(jq -r '.plugins[0].category' '$CODEX_MARKETPLACE')\" = Productivity ]"
check "Codex marketplace omits plugin version" bash -c \
  "[ \"\$(jq -r '.plugins[0] | has(\"version\")' '$CODEX_MARKETPLACE')\" = false ]"

check "project-init release surfaces are version 0.21.0" bash -c \
  "[ \"\$(jq -r .version '$CODEX_MANIFEST')\" = 0.21.0 ] && [ \"\$(jq -r .version '$CLAUDE_MANIFEST')\" = 0.21.0 ] && [ \"\$(jq -r '.plugins[] | select(.name == \"project-init\") | .version' '$CLAUDE_MARKETPLACE')\" = 0.21.0 ]"
check "Codex manifest uses default plugin hook discovery without override" bash -c \
  "[ \"\$(jq -r 'has(\"hooks\")' '$CODEX_MANIFEST')\" = false ]"

check "shared default plugin hook exists" test -f "$DEFAULT_PLUGIN_HOOKS"
check "shared default plugin hook has SessionStart" bash -c \
  "[ \"\$(jq -r '.hooks.SessionStart | length' '$DEFAULT_PLUGIN_HOOKS')\" -gt 0 ]"
check "shared default plugin hook calls rules-index script" grep -qF 'hooks/rules-index.sh' "$DEFAULT_PLUGIN_HOOKS"
check "no redundant plugin-root hooks.json adapter" test ! -e "$REDUNDANT_ROOT_HOOKS"

check "skill procedure bodies avoid direct runtime tool names" bash -c '
  fail=0
  while IFS= read -r skill; do
    body=$(awk "BEGIN { separators=0 } /^---$/ { separators++; next } separators >= 2 { print }" "$skill")
    if printf "%s\n" "$body" | grep -Eq "AskUserQuestion|request_user_input|Skill\\(skill="; then
      fail=1
    fi
  done < <(find "'"$PLUGIN"'/skills" -name SKILL.md -type f | sort)
  [ "$fail" -eq 0 ]
'
check "skills define direct-question fallback without automatic recommendation" bash -c \
  "grep -qF '구조화된 사용자 질문 기능을 사용할 수 없으면' '$PLUGIN/skills/bootstrap/SKILL.md' && grep -qF '기능 부재 자체를 이유로 추천값을 임의로 적용하거나' '$PLUGIN/skills/bootstrap/SKILL.md' && grep -qF '명시적 누락 응답 계약은 그대로 따릅니다' '$PLUGIN/skills/bootstrap/SKILL.md'"

if [ "$fail" -eq 0 ]; then
  echo "PASS"; exit 0
else
  echo "FAILED"; exit 1
fi
