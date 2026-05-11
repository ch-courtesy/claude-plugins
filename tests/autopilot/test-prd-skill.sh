#!/usr/bin/env bash
# autopilot:prd 스킬 패키지 구조 검증 테스트

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/prd"
SKILL_MD="$SKILL_DIR/SKILL.md"

echo "=== TEST 1: prd 스킬 디렉토리 구조 ==="
for f in SKILL.md \
         references/prd-template.md \
         references/self-review.md; do
  [[ -f "$SKILL_DIR/$f" ]] || { echo "FAIL: prd/$f 부재"; exit 1; }
  echo "OK: prd/$f"
done

echo ""
echo "=== TEST 2: SKILL.md frontmatter (name: prd) ==="
grep -q '^name: prd$' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md frontmatter에 'name: prd' 없음"; exit 1; }
echo "OK: name: prd"

echo ""
echo "=== TEST 3: SKILL.md description에 핵심 키워드 ==="
DESC_LINE=$(grep -m1 '^description:' "$SKILL_MD" || true)
[[ -n "$DESC_LINE" ]] || { echo "FAIL: description 라인 없음"; exit 1; }
echo "$DESC_LINE" | grep -q 'PRD' \
  || { echo "FAIL: description에 'PRD' 키워드 없음. got: $DESC_LINE"; exit 1; }
echo "OK: PRD 마커"
echo "$DESC_LINE" | grep -q -- '--import' \
  || { echo "FAIL: description에 '--import' 마커 없음. got: $DESC_LINE"; exit 1; }
echo "OK: --import 마커"
echo "$DESC_LINE" | grep -q -- '--resume' \
  || { echo "FAIL: description에 '--resume' 마커 없음. got: $DESC_LINE"; exit 1; }
echo "OK: --resume 마커"

echo ""
echo "=== TEST 4: SKILL.md 본문에 milestones/<m>/prd/PRD.md 경로 명시 ==="
grep -q 'milestones/.*prd/PRD\.md\|milestones/.*PRD\.md' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md에 milestones/<m>/prd/PRD.md 경로 명시 없음"; exit 1; }
echo "OK: PRD 출력 경로 명시"

echo ""
echo "=== TEST 5: SKILL.md 본문에 9-step 워크플로 명시 ==="
grep -qE '9[- ]?(step|단계)' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md에 9단계 워크플로 명시 없음"; exit 1; }
echo "OK: 9-step 명시"

echo ""
echo "=== TEST 6: SKILL.md에 NEEDS CLARIFICATION 마커 처리 명시 ==="
grep -q 'NEEDS CLARIFICATION' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md에 [NEEDS CLARIFICATION] 마커 처리 명시 없음"; exit 1; }
echo "OK: 마커 처리"

echo ""
echo "=== TEST 7: SKILL.md에 dispatch 안내 ==="
grep -q 'dispatch' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md에 'dispatch' 다음 단계 안내 없음"; exit 1; }
echo "OK: dispatch 안내"

echo ""
echo "=== TEST 8: prd-template.md placeholder 패턴 ==="
TEMPLATE="$SKILL_DIR/references/prd-template.md"
grep -q '{{prd_title}}\|{{milestone}}\|{{problem}}\|{{goals}}\|{{success_criteria}}' "$TEMPLATE" \
  || { echo "FAIL: prd-template.md에 placeholder 패턴 없음"; exit 1; }
echo "OK: placeholder"

echo ""
echo "=== TEST 9: self-review.md 5축 항목 ==="
SELF_REVIEW="$SKILL_DIR/references/self-review.md"
for axis in 'Placeholder|placeholder' '모순|inconsistency' '범위|scope|decomposable' '모호성|ambiguity' '마커|NEEDS CLARIFICATION'; do
  grep -qE "$axis" "$SELF_REVIEW" \
    || { echo "FAIL: self-review.md에 '$axis' 축 부재"; exit 1; }
done
echo "OK: 5축 자체 검토 명시"

echo ""
echo "=== 모든 prd 스킬 테스트 통과 ==="
