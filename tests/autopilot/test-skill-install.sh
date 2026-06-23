#!/usr/bin/env bash
# autopilot/loop 스킬 패키지 구조 검증 테스트

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/loop"
SKILL_REFS="$SKILL_DIR/references"

echo "=== 스킬 디렉토리 구조 ==="
# 정합 갱신: 경량 redesign 으로 loop 스킬은 별도 template ref 파일들
# (plan/notes/handoff/runlog/escalation-template)을 제거했다. 현 실제 구조만 검증.
for f in SKILL.md \
         references/constitution.md \
         references/loop.sh \
         references/operational-guide.md \
         references/status-format.md \
         references/troubleshooting.md \
         references/agent-prompts.md; do
  [[ -f "$SKILL_DIR/$f" ]] || { echo "FAIL: $f 부재"; exit 1; }
  echo "OK: $f"
done

echo ""
echo "=== plugin.json 존재 ==="
PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
[[ -f "$PLUGIN_JSON" ]] || { echo "FAIL: plugin.json 부재"; exit 1; }
echo "OK"

echo ""
echo "=== loop.sh 실행 권한 ==="
[[ -x "$SKILL_REFS/loop.sh" ]] || { echo "FAIL: loop.sh 실행 권한 없음"; exit 1; }
echo "OK"

echo ""
echo "=== loop.sh bash syntax 검사 ==="
bash -n "$SKILL_REFS/loop.sh" || { echo "FAIL: loop.sh syntax 오류"; exit 1; }
echo "OK"

echo ""
echo "=== loop.sh SCRIPT_DIR 패턴 확인 ==="
grep -q 'SCRIPT_DIR=.*BASH_SOURCE' "$SKILL_REFS/loop.sh" \
  || { echo "FAIL: SCRIPT_DIR 패턴 없음"; exit 1; }
# 헌법 복사가 SCRIPT_DIR을 사용하는지
grep -q 'SCRIPT_DIR/constitution.md' "$SKILL_REFS/loop.sh" \
  || { echo "FAIL: constitution.md 복사가 SCRIPT_DIR 기반이 아님"; exit 1; }
echo "OK"

echo ""
echo "=== constitution.md 본문 시작 확인 (frontmatter 없음) ==="
FIRST_LINE=$(head -1 "$SKILL_REFS/constitution.md")
[[ "$FIRST_LINE" == "---" ]] && { echo "FAIL: constitution.md에 frontmatter가 남아있음"; exit 1; }
[[ -s "$SKILL_REFS/constitution.md" ]] || { echo "FAIL: constitution.md 비어있음"; exit 1; }
echo "OK"

echo ""
echo "=== constitution.md 내용에 자율-루프-지침 미참조 ==="
grep -q "자율-루프-지침" "$SKILL_REFS/constitution.md" \
  && { echo "FAIL: constitution.md가 자율-루프-지침.md를 참조함"; exit 1; }
echo "OK"

echo ""
echo "=== old autonomous-loop-rule-creator 디렉토리 삭제 확인 ==="
OLD_SKILL="$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator"
[[ -d "$OLD_SKILL" ]] && { echo "FAIL: old autonomous-loop-rule-creator 디렉토리가 아직 존재함"; exit 1; }
echo "OK"


echo ""
echo "=== using-autopilot 스킬 + SessionStart hook 구조 검증 ==="
UA_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/using-autopilot/SKILL.md"
UA_HOOKS_JSON="$REPO_ROOT/plugins/autopilot/hooks/hooks.json"
UA_HOOK_SH="$REPO_ROOT/plugins/autopilot/hooks/session-start.sh"
[[ -f "$UA_SKILL_MD" ]] || { echo "FAIL: using-autopilot/SKILL.md 부재"; exit 1; }
grep -q 'name: using-autopilot' "$UA_SKILL_MD" \
  || { echo "FAIL: using-autopilot/SKILL.md frontmatter에 'name: using-autopilot' 없음"; exit 1; }
[[ -f "$UA_HOOKS_JSON" ]] || { echo "FAIL: hooks/hooks.json 부재"; exit 1; }
[[ -x "$UA_HOOK_SH" ]] || { echo "FAIL: hooks/session-start.sh 실행 권한 없음"; exit 1; }
sh -n "$UA_HOOK_SH" || { echo "FAIL: session-start.sh syntax 오류"; exit 1; }
echo "OK: using-autopilot 스킬·hook 구조"

echo ""
echo "=== plugin.json version bump (>= 0.2.0) ==="
# v0.1.0 → 0.2.0 cutover로 multi-task scope 도입. 최소 0.2.0 이상 보장.
PLUGIN_VERSION=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_JSON" \
  | head -1 \
  | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
[[ -n "$PLUGIN_VERSION" ]] || { echo "FAIL: plugin.json에 version 필드 없음"; exit 1; }
echo "OK: version=$PLUGIN_VERSION"
# 0.1.x 또는 그 이하는 거부 (multi-task scope cutover 후)
case "$PLUGIN_VERSION" in
  0.0.*|0.1.*) echo "FAIL: plugin.json version $PLUGIN_VERSION < 0.2.0 (cutover 후 minimum)"; exit 1 ;;
esac
echo "OK: version $PLUGIN_VERSION >= 0.2.0"

echo ""
echo "=== 모든 테스트 통과 ==="
