#!/usr/bin/env bash
# autopilot using-autopilot SessionStart hook 검증 테스트
# - hooks.json 스키마/엔트리, session-start.sh 존재·실행권한·syntax,
#   스크립트 출력의 EXTREMELY_IMPORTANT 래퍼 + 핵심 라우팅 문구,
#   using-autopilot/SKILL.md frontmatter

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_DIR="$REPO_ROOT/plugins/autopilot"
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"
HOOK_SH="$PLUGIN_DIR/hooks/session-start.sh"
SKILL_MD="$PLUGIN_DIR/skills/using-autopilot/SKILL.md"

echo "=== 파일 존재 ==="
for f in "$HOOKS_JSON" "$HOOK_SH" "$SKILL_MD"; do
  [[ -f "$f" ]] || { echo "FAIL: $f 부재"; exit 1; }
  echo "OK: ${f#"$REPO_ROOT"/}"
done

echo ""
echo "=== hooks.json valid JSON + SessionStart 엔트리 ==="
if command -v jq >/dev/null 2>&1; then
  jq -e . "$HOOKS_JSON" >/dev/null || { echo "FAIL: hooks.json invalid JSON"; exit 1; }
  jq -e '.hooks.SessionStart' "$HOOKS_JSON" >/dev/null \
    || { echo "FAIL: hooks.json에 SessionStart 엔트리 없음"; exit 1; }
  CMD=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$HOOKS_JSON")
  echo "$CMD" | grep -q 'session-start.sh' \
    || { echo "FAIL: SessionStart command가 session-start.sh를 참조하지 않음"; exit 1; }
  echo "$CMD" | grep -q 'CLAUDE_PLUGIN_ROOT' \
    || { echo "FAIL: SessionStart command가 CLAUDE_PLUGIN_ROOT를 쓰지 않음"; exit 1; }
else
  echo "WARN: jq 없음 — grep fallback으로 검증"
  grep -q '"SessionStart"' "$HOOKS_JSON" \
    || { echo "FAIL: hooks.json에 SessionStart 없음"; exit 1; }
  grep -q 'session-start.sh' "$HOOKS_JSON" \
    || { echo "FAIL: hooks.json이 session-start.sh를 참조하지 않음"; exit 1; }
fi
echo "OK"

echo ""
echo "=== session-start.sh 실행 권한 + syntax ==="
[[ -x "$HOOK_SH" ]] || { echo "FAIL: session-start.sh 실행 권한 없음"; exit 1; }
sh -n "$HOOK_SH" || { echo "FAIL: session-start.sh syntax 오류"; exit 1; }
echo "OK"

echo ""
echo "=== session-start.sh 출력: EXTREMELY_IMPORTANT 래퍼 + 라우팅 문구 ==="
OUT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" sh "$HOOK_SH")
echo "$OUT" | grep -q '<EXTREMELY_IMPORTANT>' \
  || { echo "FAIL: 출력에 <EXTREMELY_IMPORTANT> 여는 태그 없음"; exit 1; }
echo "$OUT" | grep -q '</EXTREMELY_IMPORTANT>' \
  || { echo "FAIL: 출력에 </EXTREMELY_IMPORTANT> 닫는 태그 없음"; exit 1; }
echo "$OUT" | grep -q 'spec' \
  || { echo "FAIL: 출력에 'spec' 라우팅 문구 없음"; exit 1; }
echo "$OUT" | grep -q '새로 만들기' \
  || { echo "FAIL: 출력에 '새로 만들기' 트리거 문구 없음"; exit 1; }
echo "$OUT" | grep -q 'brainstorming' \
  || { echo "FAIL: 출력에 brainstorming override 언급 없음"; exit 1; }
echo "OK"

echo ""
echo "=== 자기 위치 fallback (CLAUDE_PLUGIN_ROOT 미설정) ==="
OUT2=$(sh "$HOOK_SH")
echo "$OUT2" | grep -q '<EXTREMELY_IMPORTANT>' \
  || { echo "FAIL: env 미설정 시 출력 없음 (자기 위치 fallback 실패)"; exit 1; }
echo "OK"

echo ""
echo "=== using-autopilot/SKILL.md frontmatter ==="
grep -q 'name: using-autopilot' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md frontmatter에 'name: using-autopilot' 없음"; exit 1; }
echo "OK: name: using-autopilot"

echo ""
echo "=== 버전 동기화 (plugin.json == marketplace.json autopilot) ==="
PLUGIN_VER=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_DIR/.claude-plugin/plugin.json" \
  | head -1 | sed -E 's/.*"([0-9][^"]*)".*/\1/')
echo "OK: plugin.json version=$PLUGIN_VER"
case "$PLUGIN_VER" in
  0.0.*|0.1.*|0.2.*|0.3.*|0.4.*|0.5.*|0.6.*|0.7.*)
    echo "FAIL: using-autopilot(새 기능) 추가 후 version $PLUGIN_VER < 0.8.0"; exit 1 ;;
esac
echo "OK: version $PLUGIN_VER >= 0.8.0"

echo ""
echo "=== 모든 테스트 통과 ==="
