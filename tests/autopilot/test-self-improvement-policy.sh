#!/usr/bin/env bash
# 자가개선 정책(always-on) 회귀 가드 — #485
# - using-autopilot가 자가개선 정책의 단일 소유자: always-on 트리거 + 카테고리 enum
#   + 카테고리→행동 매핑(spec-gap/tool-defect/ops) + 재귀 상한(자가개선-비활성 flag)
# - execute-task·workflow-task가 blocked 시 category 표면화 + 비활성 flag 존중
# - plugin.json 버전 범프

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_DIR="$REPO_ROOT/plugins/autopilot"
USING="$PLUGIN_DIR/skills/using-autopilot/SKILL.md"
EXEC="$PLUGIN_DIR/skills/execute-task/SKILL.md"
WF="$PLUGIN_DIR/skills/workflow-task/SKILL.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"

fail() { echo "FAIL: $1"; exit 1; }

echo "=== 파일 존재 ==="
for f in "$USING" "$EXEC" "$WF" "$PLUGIN_JSON"; do
  [[ -f "$f" ]] || fail "$f 부재"
  echo "OK: ${f#"$REPO_ROOT"/}"
done

echo ""
echo "=== using-autopilot: 자가개선 정책 단일 소유자 (always-on) ==="
grep -q '단일 소유자' "$USING" || fail "using에 '단일 소유자' 표기 없음"
grep -q 'always-on' "$USING" || fail "using에 always-on 표기 없음"
# 실행 경로 무관 항상 발동 — 단일 execute-task와 드레인 양쪽 언급
grep -q 'execute-task' "$USING" || fail "using 자가개선 절에 execute-task 경로 언급 없음"
grep -q 'workflow-task' "$USING" || fail "using 자가개선 절에 workflow-task 경로 언급 없음"
echo "OK"

echo ""
echo "=== using-autopilot: 카테고리 enum + 카테고리→행동 매핑 명문화 ==="
grep -q 'spec-gap' "$USING" || fail "using에 spec-gap 카테고리 없음"
grep -q 'tool-defect' "$USING" || fail "using에 tool-defect 카테고리 없음"
grep -q 'ops' "$USING" || fail "using에 ops 카테고리 없음"
# 행동 매핑: spec-gap→SPEC scope 보정 / tool-defect→새 fix / ops→정리
grep -q 'scope 보정' "$USING" || fail "using에 spec-gap→SPEC scope 보정 매핑 없음"
grep -Eq 'tool-defect.*fix|fix.*수정 스펙' "$USING" || fail "using에 tool-defect→fix 매핑 없음"
grep -q '정리' "$USING" || fail "using에 ops→정리 매핑 없음"
echo "OK"

echo ""
echo "=== using-autopilot: 재귀 상한(자가개선-비활성 flag, depth-1) ==="
grep -q '자가개선-비활성' "$USING" || fail "using에 자가개선-비활성 플래그 없음"
grep -q 'depth-1' "$USING" || fail "using에 depth-1 재귀 상한 표기 없음"
echo "OK"

echo ""
echo "=== execute-task: blocked category 표면화 + 비활성 flag 존중 ==="
grep -q 'category' "$EXEC" || fail "execute-task에 category 표면화 언급 없음"
grep -q '자가개선-비활성' "$EXEC" || fail "execute-task에 자가개선-비활성 flag 존중 언급 없음"
echo "OK"

echo ""
echo "=== workflow-task: 카테고리 분기 + 비활성 flag 존중 ==="
grep -q 'category' "$WF" || fail "workflow-task에 category 분기 언급 없음"
grep -q '자가개선-비활성' "$WF" || fail "workflow-task에 자가개선-비활성 flag 존중 언급 없음"
echo "OK"

echo ""
echo "=== plugin.json 버전 >= 0.55.0 ==="
PLUGIN_VER=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_JSON" \
  | head -1 | sed -E 's/.*"([0-9][^"]*)".*/\1/')
case "$PLUGIN_VER" in
  0.0.*|0.1.*|0.2.*|0.3.*|0.4.*|0.50.*|0.51.*|0.52.*|0.53.*|0.54.*)
    fail "자가개선 정책 추가 후 version $PLUGIN_VER < 0.55.0" ;;
esac
echo "OK: version $PLUGIN_VER >= 0.55.0"

echo ""
echo "=== 모든 테스트 통과 ==="
