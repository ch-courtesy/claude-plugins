#!/usr/bin/env bash
# autopilot:dispatch 스킬 패키지 구조 검증 테스트

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/dispatch"
SKILL_MD="$SKILL_DIR/SKILL.md"
DISPATCH_SH="$SKILL_DIR/references/dispatch.sh"

echo "=== TEST 1: dispatch 스킬 디렉토리 구조 ==="
for f in SKILL.md \
         references/dispatch.sh \
         references/dag-template.md \
         references/decomposition-algorithm.md; do
  [[ -f "$SKILL_DIR/$f" ]] || { echo "FAIL: dispatch/$f 부재"; exit 1; }
  echo "OK: dispatch/$f"
done

echo ""
echo "=== TEST 2: SKILL.md frontmatter (name: dispatch) ==="
grep -q '^name: dispatch$' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md frontmatter에 'name: dispatch' 없음"; exit 1; }
echo "OK: name: dispatch"

echo ""
echo "=== TEST 3: SKILL.md description에 핵심 키워드 ==="
DESC_LINE=$(grep -m1 '^description:' "$SKILL_MD" || true)
[[ -n "$DESC_LINE" ]] || { echo "FAIL: description 라인 없음"; exit 1; }
for kw in 'PRD|prd' 'dispatch|분해' 'wave|병렬' 'milestone'; do
  echo "$DESC_LINE" | grep -qE "$kw" \
    || { echo "FAIL: description에 '$kw' 키워드 없음. got: $DESC_LINE"; exit 1; }
done
echo "OK: 키워드 마커"

echo ""
echo "=== TEST 4: SKILL.md에 ops 서브커맨드 7종 명시 ==="
for sub in 'start' 'status' 'stop' 'list' 'cleanup' 'logs' 'resume'; do
  grep -qE "dispatch ${sub}|### ${sub}" "$SKILL_MD" \
    || { echo "FAIL: SKILL.md에 '${sub}' 서브커맨드 안내 없음"; exit 1; }
done
echo "OK: 서브커맨드 7종"

echo ""
echo "=== TEST 5: SKILL.md에 3 게이트 명시 ==="
# 게이트 1: 분해 plan 승인, 2: spec 위임, 3: 최종 확인
GATE_COUNT=$(grep -ciE '게이트|gate' "$SKILL_MD")
[[ "$GATE_COUNT" -ge 3 ]] || { echo "FAIL: 게이트 언급 3회 미만 (got: $GATE_COUNT)"; exit 1; }
echo "OK: 게이트 3종"

echo ""
echo "=== TEST 6: SKILL.md에 sentinel watch 명시 ==="
grep -qE 'sentinel|DONE|ESCALATION' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md에 sentinel watch (DONE/ESCALATION) 명시 없음"; exit 1; }
echo "OK: sentinel watch"

echo ""
echo "=== TEST 7: SKILL.md에 fail-fast 동작 명시 ==="
grep -qE 'fail-fast|fail fast|loop stop' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md에 fail-fast/stop 동작 명시 없음"; exit 1; }
echo "OK: fail-fast"

echo ""
echo "=== TEST 8: SKILL.md에 분해 하드 캡 명시 ==="
grep -qE '≤ 8|≤ 20|하드 캡|hard cap' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md에 분해 하드 캡 명시 없음"; exit 1; }
echo "OK: 하드 캡"

echo ""
echo "=== TEST 9: SKILL.md에 마커 거부자 역할 명시 ==="
grep -q 'NEEDS CLARIFICATION' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md에 [NEEDS CLARIFICATION] 처리 명시 없음"; exit 1; }
echo "OK: 마커 거부"

echo ""
echo "=== TEST 10: dispatch.sh 실행 권한 ==="
[[ -x "$DISPATCH_SH" ]] || { echo "FAIL: dispatch.sh 실행 권한 없음"; exit 1; }
echo "OK: 실행 권한"

echo ""
echo "=== TEST 11: dispatch.sh bash syntax 검사 ==="
bash -n "$DISPATCH_SH" || { echo "FAIL: dispatch.sh syntax 오류"; exit 1; }
echo "OK: syntax"

echo ""
echo "=== TEST 12: dispatch.sh subcommand 디스패처 ==="
for sub in 'status' 'stop' 'list' 'cleanup' 'logs'; do
  grep -qE "^[[:space:]]*${sub}\)" "$DISPATCH_SH" \
    || { echo "FAIL: dispatch.sh에 subcommand 분기 '${sub})' 없음"; exit 1; }
done
echo "OK: subcommand 디스패치"

echo ""
echo "=== TEST 13: dispatch.sh에 milestones/<m> 경로 처리 ==="
grep -q 'milestones/' "$DISPATCH_SH" \
  || { echo "FAIL: dispatch.sh에 milestones/ 경로 처리 없음"; exit 1; }
echo "OK: milestones 경로"

echo ""
echo "=== TEST 14: dag-template.md placeholder ==="
DAG_TEMPLATE="$SKILL_DIR/references/dag-template.md"
grep -qE '\{\{[a-z_]+\}\}' "$DAG_TEMPLATE" \
  || { echo "FAIL: dag-template.md에 placeholder 없음"; exit 1; }
echo "OK: dag-template placeholder"

echo ""
echo "=== TEST 15: decomposition-algorithm.md에 3 조건 + 하드 캡 명시 ==="
DECOMP_ALG="$SKILL_DIR/references/decomposition-algorithm.md"
grep -qE '8|20' "$DECOMP_ALG" \
  || { echo "FAIL: decomposition-algorithm.md에 하드 캡(8/20) 없음"; exit 1; }
grep -qE 'fit|폐쇄성|격리|컨텍스트' "$DECOMP_ALG" \
  || { echo "FAIL: decomposition-algorithm.md에 3 조건 신호 없음"; exit 1; }
echo "OK: 분해 알고리즘"

echo ""
echo "=== 모든 dispatch 스킬 테스트 통과 ==="
