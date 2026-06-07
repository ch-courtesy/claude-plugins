#!/usr/bin/env bash
# Static contract for the shared bootstrap guidance and vendor skeletons.
set -u

ROOT="$(cd "$(dirname "$0")/../../../../.." && pwd)"
SHARED="$ROOT/plugins/project-init/shared/bootstrap"
BOOTSTRAP_SKILL="$ROOT/plugins/project-init/skills/bootstrap/SKILL.md"
CODEX_MANIFEST="$ROOT/plugins/project-init/.codex-plugin/plugin.json"
CLAUDE_MANIFEST="$ROOT/plugins/project-init/.claude-plugin/plugin.json"
CLAUDE_MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"

fail=0
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc"; fail=1
  fi
}

check "bootstrap references shared assets" grep -qF 'shared/bootstrap/' "$BOOTSTRAP_SKILL"
check "bootstrap requires at least one vendor" grep -qF '최소 1개' "$BOOTSTRAP_SKILL"
check "bootstrap retries empty vendor selection at most three times" grep -qE '3회|세 번' "$BOOTSTRAP_SKILL"
check "bootstrap aborts before creating files after three empty selections" grep -qF '아무 파일도 생성·변경하지 않은 채 bootstrap을 중단' "$BOOTSTRAP_SKILL"
check "bootstrap documents both recommended vendors" bash -c "grep -qF 'Claude Code (Recommended)' '$BOOTSTRAP_SKILL' && grep -qF 'Codex (Recommended)' '$BOOTSTRAP_SKILL'"
check "bootstrap preserves existing files" grep -qF '덮어쓰지' "$BOOTSTRAP_SKILL"
check "bootstrap gates existing CLAUDE.md import behind diff approval" bash -c "grep -qF '@AGENTS.md' '$BOOTSTRAP_SKILL' && grep -qF 'diff' '$BOOTSTRAP_SKILL' && grep -qE '승인|물어' '$BOOTSTRAP_SKILL'"
check "bootstrap uses skill-relative shared path" grep -qF '../../shared/bootstrap/' "$BOOTSTRAP_SKILL"
check "bootstrap can create vendor directories" grep -qF 'Bash(mkdir:*)' "$BOOTSTRAP_SKILL"

check "shared AGENTS base exists" test -f "$SHARED/AGENTS.md"
check "shared interaction asset exists" test -f "$SHARED/assets/interaction-rules.ko.md"
check "shared karpathy asset exists" test -f "$SHARED/assets/karpathy-rules.ko.md"
check "Claude entrypoint exists" test -f "$SHARED/vendors/claude/CLAUDE.md"
check "Claude settings skeleton exists" test -f "$SHARED/vendors/claude/settings.json"
check "Codex config skeleton exists" test -f "$SHARED/vendors/codex/config.toml"

check "shared interaction asset uses capability wording" grep -qF '구조화된 사용자 질문 기능' "$SHARED/assets/interaction-rules.ko.md"
check "shared guidance has no vendor or tool literals" bash -c "! grep -RIE 'Claude|Codex|AskUserQuestion|request_user_input|\\.claude/|\\.codex/' '$SHARED/AGENTS.md' '$SHARED/assets'"
check "Claude entrypoint imports AGENTS.md" grep -qxF '@AGENTS.md' "$SHARED/vendors/claude/CLAUDE.md"
check "Claude settings skeleton is an empty object" bash -c "[ \"\$(jq -c . '$SHARED/vendors/claude/settings.json')\" = '{}' ]"
check "Codex config contains comments only" bash -c "! grep -qE '^[[:space:]]*[^#[:space:]][^#]*=' '$SHARED/vendors/codex/config.toml'"

check "legacy local bootstrap base removed" test ! -e "$ROOT/plugins/project-init/skills/bootstrap/CLAUDE.md"
check "legacy local interaction asset removed" test ! -e "$ROOT/plugins/project-init/skills/bootstrap/assets/interaction-rules.ko.md"
check "legacy duplicated bootstrap directory removed" test ! -e "$ROOT/plugins/project-init/claude-skills/bootstrap"

check "Codex manifest version is 0.17.0" bash -c "[ \"\$(jq -r .version '$CODEX_MANIFEST')\" = '0.17.0' ]"

check "Claude manifest version is 0.17.0" bash -c "[ \"\$(jq -r .version '$CLAUDE_MANIFEST')\" = '0.17.0' ]"
check "Claude marketplace version is 0.17.0" bash -c "[ \"\$(jq -r '.plugins[] | select(.name == \"project-init\") | .version' '$CLAUDE_MARKETPLACE')\" = '0.17.0' ]"

if [ "$fail" -eq 0 ]; then
  echo "PASS"; exit 0
else
  echo "FAILED"; exit 1
fi
