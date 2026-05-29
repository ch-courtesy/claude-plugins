#!/usr/bin/env bash
# autopilot/loop 스킬 패키지 구조 검증 테스트

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/loop"
SKILL_REFS="$SKILL_DIR/references"

echo "=== 스킬 디렉토리 구조 ==="
for f in SKILL.md \
         references/constitution.md \
         references/loop.sh \
         references/plan-template.md \
         references/notes-template.md \
         references/handoff-template.md \
         references/runlog-template.md \
         references/escalation-template.md \
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
echo "=== spec 스킬 구조 검증 ==="
SPEC_SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/spec"
for f in SKILL.md \
         references/spec-template.md \
         references/ears-patterns.md \
         references/self-review.md \
         references/decomposition-gate.md; do
  [[ -f "$SPEC_SKILL_DIR/$f" ]] || { echo "FAIL: spec/$f 부재"; exit 1; }
  echo "OK: spec/$f"
done

echo ""
echo "=== spec/SKILL.md frontmatter 검증 ==="
SPEC_SKILL_MD="$SPEC_SKILL_DIR/SKILL.md"
grep -q 'name: spec' "$SPEC_SKILL_MD" \
  || { echo "FAIL: spec/SKILL.md frontmatter에 'name: spec' 없음"; exit 1; }
echo "OK: name: spec"
grep -q 'EARS' "$SPEC_SKILL_MD" \
  || { echo "FAIL: spec/SKILL.md description에 'EARS' 마커 없음"; exit 1; }
echo "OK: EARS 마커"
grep -q '\[NEEDS CLARIFICATION\]' "$SPEC_SKILL_MD" \
  || { echo "FAIL: spec/SKILL.md description에 '[NEEDS CLARIFICATION]' 마커 없음"; exit 1; }
echo "OK: [NEEDS CLARIFICATION] 마커"
grep -q -- '--resume' "$SPEC_SKILL_MD" \
  || { echo "FAIL: spec/SKILL.md description에 '--resume' 마커 없음"; exit 1; }
echo "OK: --resume 마커"
# 신규 contract: feat 브랜치 자동 생성·SPEC.md commit 단계가 명시되어야 함
grep -q 'feat/<task-id>' "$SPEC_SKILL_MD" \
  || { echo "FAIL: spec/SKILL.md에 'feat/<task-id>' 브랜치 명세 없음 (신규 contract 미반영)"; exit 1; }
echo "OK: feat/<task-id> 브랜치 명세"
grep -qE '슬러그|slug' "$SPEC_SKILL_MD" \
  || { echo "FAIL: spec/SKILL.md에 슬러그화 규칙 명세 없음"; exit 1; }
echo "OK: 슬러그화 규칙 명세"

echo ""
echo "=== dispatch 스킬 구조 검증 ==="
DISPATCH_SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/dispatch"
for f in SKILL.md \
         references/dispatch.sh \
         references/dag-template.md \
         references/decomposition-algorithm.md; do
  [[ -f "$DISPATCH_SKILL_DIR/$f" ]] || { echo "FAIL: dispatch/$f 부재"; exit 1; }
  echo "OK: dispatch/$f"
done

echo ""
echo "=== dispatch/SKILL.md frontmatter 검증 ==="
DISPATCH_SKILL_MD="$DISPATCH_SKILL_DIR/SKILL.md"
grep -q 'name: dispatch' "$DISPATCH_SKILL_MD" \
  || { echo "FAIL: dispatch/SKILL.md frontmatter에 'name: dispatch' 없음"; exit 1; }
echo "OK: name: dispatch"
grep -qE 'start|status|stop|list|cleanup|logs|resume' "$DISPATCH_SKILL_MD" \
  || { echo "FAIL: dispatch/SKILL.md description에 서브커맨드 마커 없음"; exit 1; }
echo "OK: 서브커맨드 마커"

echo ""
echo "=== dispatch.sh 실행 권한 + syntax 검증 ==="
DISPATCH_SH="$DISPATCH_SKILL_DIR/references/dispatch.sh"
[[ -x "$DISPATCH_SH" ]] || { echo "FAIL: dispatch.sh 실행 권한 없음"; exit 1; }
echo "OK: 실행 권한"
bash -n "$DISPATCH_SH" || { echo "FAIL: dispatch.sh syntax 오류"; exit 1; }
echo "OK: syntax"

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
