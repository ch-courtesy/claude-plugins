#!/usr/bin/env bash
# using-autopilot 라우팅 회귀 가드 — #504
# (a) 버그·증상·실패 라우팅이 `fix`를 가리키는가
# (b) stale 과도기 문구가 없는가
# (c) 자가개선 행동 순서 step 1 산출물 요구사항이 있는가

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/using-autopilot/SKILL.md"

fail() { echo "FAIL: $1"; exit 1; }

echo "=== 파일 존재 ==="
[[ -f "$SKILL_MD" ]] || fail "SKILL.md 부재: $SKILL_MD"
echo "OK: ${SKILL_MD#"$REPO_ROOT"/}"

echo ""
echo "=== (a) 버그 라우팅: fix를 가리키는가 ==="
# 절대 우선 섹션에 fix 호출 지시가 있어야 한다
grep -q 'skill="fix"' "$SKILL_MD" \
  || fail 'SKILL.md에 Skill(skill="fix", ...) 라우팅 없음'
# 섹션 헤더가 fix를 가리켜야 한다
grep -q '버그·증상·실패.*→.*`fix`' "$SKILL_MD" \
  || fail 'SKILL.md에 "버그·증상·실패 → fix" 섹션 헤더 없음'
# 파이프라인 다이어그램이 fix를 가리켜야 한다
grep -q 'autopilot:fix' "$SKILL_MD" \
  || fail 'SKILL.md 파이프라인에 autopilot:fix 없음'
echo "OK"

echo ""
echo "=== (b) stale 과도기 문구 없음 ==="
# 모든 "과도기" 문구가 제거되어야 한다
if grep -q '과도기' "$SKILL_MD"; then
  echo "FAIL: stale 과도기 문구가 남아 있음:"
  grep -n '과도기' "$SKILL_MD"
  exit 1
fi
# "fix가 아직 없" 류 문구 없음
grep -q 'fix가 아직' "$SKILL_MD" \
  && { echo "FAIL: 'fix가 아직' stale 문구 잔존"; exit 1; }
# "fix 머지 전까지" 류 문구 없음
grep -q 'fix 머지' "$SKILL_MD" \
  && { echo "FAIL: 'fix 머지' stale 문구 잔존"; exit 1; }
echo "OK"

echo ""
echo "=== (c) step 1 산출물 요구사항 존재 ==="
# step 1에 카테고리 + 근본 원인 후보 명시 요구가 있어야 한다
grep -q 'step 1 산출물 요구사항' "$SKILL_MD" \
  || fail 'SKILL.md에 step 1 산출물 요구사항 없음'
# 진단 없이 step 2 직행 차단 문구가 있어야 한다
grep -q '진단 없이.*step 2\|step 2.*직행.*step 1 미완' "$SKILL_MD" \
  || fail 'SKILL.md에 "진단 없이 step 2 직행" 차단 문구 없음'
echo "OK"

echo ""
echo "=== (d) Red flags: 진단 없이 fix 직행 차단 항목 존재 ==="
grep -q '진단 없이.*fix\|fix.*직행.*step 1 미완\|step 1.*완료.*없이\|일단.*fix.*부터' "$SKILL_MD" \
  || fail 'Red flags에 "진단 없이 fix 직행" 차단 항목 없음'
echo "OK"

echo ""
echo "=== (e) [NEEDS CLARIFICATION] → feature resume 경로 언급 ==="
grep -q 'NEEDS CLARIFICATION' "$SKILL_MD" \
  || fail 'SKILL.md에 [NEEDS CLARIFICATION] 마커 언급 없음'
grep -q 'feature.*resume\|resume.*feature' "$SKILL_MD" \
  || fail 'SKILL.md에 feature resume 경로 언급 없음'
echo "OK"

echo ""
echo "=== 모든 테스트 통과 ==="
