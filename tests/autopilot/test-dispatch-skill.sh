#!/usr/bin/env bash
# autopilot:dispatch 스킬 패키지 구조 검증 — spec-list-driven 재설계 (v0.8+)
#
# 본 테스트는 SKILL.md·dispatch.sh·plugin.json 의 정적 계약을 검사한다.
# 행위 계약은 test-dispatch-integration.sh.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/dispatch"
SKILL_MD="$SKILL_DIR/SKILL.md"
DISPATCH_SH="$SKILL_DIR/references/dispatch.sh"
PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"

echo "=== TEST 1: 필수 파일 존재 ==="
for f in SKILL.md references/dispatch.sh; do
  [[ -f "$SKILL_DIR/$f" ]] || { echo "FAIL: dispatch/$f 부재"; exit 1; }
  echo "OK: dispatch/$f"
done

echo ""
echo "=== TEST 2: 폐기된 reference 파일 부재 ==="
for f in references/dag-template.md \
         references/decomposition-algorithm.md \
         references/task-storage.sh; do
  if [[ -e "$SKILL_DIR/$f" ]]; then
    echo "FAIL: 폐기 파일 잔존: dispatch/$f"; exit 1
  fi
  echo "OK: 폐기 파일 부재 — dispatch/$f"
done

echo ""
echo "=== TEST 3: SKILL.md frontmatter name: dispatch ==="
grep -q '^name: dispatch$' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md frontmatter 에 'name: dispatch' 없음"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 5: SKILL.md 5 subcommand (start/list/status/stop/watch) ==="
for sub in start list status stop watch; do
  grep -qE "dispatch ${sub}\b|^### ${sub}\b|^## ${sub}\b" "$SKILL_MD" \
    || { echo "FAIL: SKILL.md 에 '${sub}' subcommand 안내 없음"; exit 1; }
done
echo "OK"

echo ""
echo "=== TEST 6: SKILL.md 에 .dispatch/runs/ 경로 명시 ==="
grep -q '\.dispatch/runs/' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md 에 '.dispatch/runs/' 경로 명시 없음"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 7: SKILL.md 에 depends_on 명시 ==="
grep -q 'depends_on' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md 에 'depends_on' 명시 없음"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 8: SKILL.md 에 PRD/milestones 단어 부재 ==="
# PRD 는 단어 경계 내에서만 검사. "PRD-foo" 같은 합성은 잡힘. milestones/ 는 경로 패턴.
if grep -Eq '(^|[^a-zA-Z])PRD([^a-zA-Z]|$)' "$SKILL_MD"; then
  echo "FAIL: SKILL.md 에 PRD 단어 잔존"; exit 1
fi
if grep -q 'milestones/' "$SKILL_MD"; then
  echo "FAIL: SKILL.md 에 milestones/ 경로 잔존"; exit 1
fi
echo "OK"

echo ""
echo "=== TEST 9: dispatch.sh 실행 권한 + bash syntax ==="
[[ -x "$DISPATCH_SH" ]] || { echo "FAIL: dispatch.sh 실행 권한 없음"; exit 1; }
bash -n "$DISPATCH_SH" || { echo "FAIL: dispatch.sh syntax 오류"; exit 1; }
echo "OK"

echo ""
echo "=== TEST 10: dispatch.sh subcommand 디스패처 (start/list/status/stop/watch) ==="
for sub in start list status stop watch; do
  grep -qE "^[[:space:]]*${sub}\)" "$DISPATCH_SH" \
    || { echo "FAIL: dispatch.sh 에 '${sub})' 분기 없음"; exit 1; }
done
echo "OK"

echo ""
echo "=== TEST 11: dispatch.sh 금지 키워드 부재 ==="
# 코어는 milestone·PRD·issue·label·task-storage·ESCALATION.md 와 결합하지 않는다.
for pat in 'task-storage' 'gh pr' 'gh issue' 'LOOP_DONE_LABEL' 'ESCALATION\.md' 'milestones/'; do
  if grep -Eq "$pat" "$DISPATCH_SH"; then
    echo "FAIL: dispatch.sh 에 금지 키워드 잔존: $pat"; exit 1
  fi
  echo "OK: 금지 키워드 부재 — $pat"
done

echo ""
echo "=== TEST 12: plugin.json version >= 0.8.0 ==="
grep -Eq '"version":[[:space:]]*"0\.(8|9|[1-9][0-9])\.' "$PLUGIN_JSON" \
  || { echo "FAIL: plugin.json version 0.8.0+ 아님. got: $(grep version "$PLUGIN_JSON")"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 dispatch 스킬 구조 테스트 통과 ==="
