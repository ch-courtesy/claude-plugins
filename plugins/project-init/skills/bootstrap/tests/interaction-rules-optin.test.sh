#!/usr/bin/env bash
# Structural acceptance test for the bootstrap "Codex 상호작용 규칙" opt-in SPEC,
# updated for the H1-normalize SPEC: the generated AGENTS.md no longer carries a
# redundant "# AGENTS.md" title; instead each assembled block begins with a
# sibling top-level (H1) heading so block boundaries are visible by heading level
# alone. Single-source assembly model:
#   - base AGENTS.md template = always-included "카테고리별 지침" (now an H1 block)
#   - interaction-rules asset  = the optional "Codex 상호작용 규칙" (now an H1 block)
#   - karpathy-rules asset      = the optional 카파시 룰 (already an H1 block)
#   - SKILL.md documents the request_user_input include/exclude branch and the
#     sibling-H1 boundary assembly (no longer anchored on a "# AGENTS.md" title)
#
# Run: bash interaction-rules-optin.test.sh   (exit 0 = pass)
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$DIR/AGENTS.md"
ASSET="$DIR/assets/interaction-rules.ko.md"
KARPATHY="$DIR/assets/karpathy-rules.ko.md"
SKILL="$DIR/SKILL.md"

fail=0
check() { # desc, cmd...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - $desc"
  else
    echo "FAIL - $desc"; fail=1
  fi
}

# 1) Interaction-rules asset exists and holds the section as an H1 block
#    (single source of truth), with sub-headings promoted one level (### -> ##)
#    so the heading hierarchy under the H1 does not skip a level.
check "interaction-rules asset exists" test -f "$ASSET"
check "asset top heading is H1 '# Codex 상호작용 규칙'" grep -qxF '# Codex 상호작용 규칙' "$ASSET"
check "asset has NO H2 '## Codex 상호작용 규칙' anymore" bash -c "! grep -qxF '## Codex 상호작용 규칙' '$ASSET'"
check "asset sub-headings promoted to H2 (## 발신 전 점검)" grep -qxF '## 발신 전 점검' "$ASSET"
check "asset has NO leftover H3 headings" bash -c "! grep -qE '^### ' '$ASSET'"
check "asset documents request_user_input usage" grep -qF 'request_user_input' "$ASSET"

# 2) Base template always carries "카테고리별 지침" as the H1 block top heading,
#    and the redundant "# AGENTS.md" title is gone.
check "base AGENTS.md top heading is H1 '# 카테고리별 지침'" grep -qxF '# 카테고리별 지침' "$BASE"
check "base AGENTS.md has NO H2 '## 카테고리별 지침' anymore" bash -c "! grep -qxF '## 카테고리별 지침' '$BASE'"
check "base AGENTS.md has NO '# AGENTS.md' title line" bash -c "! grep -qxF '# AGENTS.md' '$BASE'"

# 2b) EXCLUDE invariant: with neither optional block selected, the base (== the
#     exclude-path output) has exactly ONE H1, and it is '# 카테고리별 지침'.
check "base AGENTS.md has exactly one H1" bash -c "[ \"\$(grep -cE '^# ' '$BASE')\" -eq 1 ]"

# 3) EXCLUDE invariant: base must NOT contain the interaction-rules section in
#    ANY form (heading or body), so it is not duplicated and the exclude path
#    cannot leak it.
check "base AGENTS.md has NO interaction-rules heading" bash -c "! grep -qF 'Codex 상호작용 규칙' '$BASE'"
check "base AGENTS.md has NO request_user_input interaction body" bash -c "! grep -qF 'request_user_input' '$BASE'"

# 4) Sibling-H1 boundary invariant: each assembled block begins with its own H1.
check "karpathy asset top heading is H1" bash -c "head -1 '$KARPATHY' | grep -qE '^# '"

# 5) SKILL.md documents the opt-in question and the sibling-H1 boundary assembly,
#    no longer anchored on a now-removed '# AGENTS.md' title.
check "SKILL.md references interaction-rules asset" grep -qF 'interaction-rules.ko.md' "$SKILL"
check "SKILL.md asks via request_user_input for the section" grep -qF '상호작용 규칙' "$SKILL"
check "SKILL.md no longer anchors assembly on '# AGENTS.md' title" bash -c "! grep -qF '\`# AGENTS.md\`' '$SKILL'"

if [ "$fail" -eq 0 ]; then
  echo "PASS"; exit 0
else
  echo "FAILED"; exit 1
fi
