#!/usr/bin/env bash
# autopilot:spec 스킬 — 외부 상태 미생성 계약 정적 검증 테스트
#
# 정합 갱신: 과거 본 테스트는 제거된 기능(사전 검사 직후 외부 task 상태 정합/전이,
# GitHub Project/Issue 매핑, gh issue create/edit·gh project item-* 호출, 4갈래
# 분기, task-id 교체)을 검증하는 stale assert 집합이었다. 경량 redesign 으로 spec
# 스킬은 외부 상태(task·이슈·브랜치·원격)를 일절 만들지 않으므로, 본 테스트는
# 제거된 task-전이 계약의 부재(negative)와 현 경량 계약(외부 상태 미생성)을
# 검증하도록 정정하고, 그 위에 persona/clarity 가산 기능의 단일 출처 보장을 가산한다.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/spec"
SKILL_MD="$SKILL_DIR/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$SKILL_MD" ]] || fail "SKILL.md 부재"

echo "=== TEST 1: 제거된 task 상태 정합/전이 '단계 헤더' 부재 (negative) ==="
# 경량 계약은 외부 task 상태를 정합/전이하는 워크플로 '단계'를 두지 않는다.
# (본문 disclaimer 에서 '상태 정합'이 호출자 책임으로 언급되는 것은 허용 —
#  여기서는 단계 헤더 라인만 negative 검사한다.)
if grep -qE '^###? .*(상태 정합|상태 전이|status reconcil|status transition)' "$SKILL_MD"; then
  fail "SKILL.md에 제거된 'task 상태 정합/전이' 단계 헤더가 잔존 (경량 계약 위반)"
fi
ok "task 상태 정합/전이 단계 헤더 부재"

echo ""
echo "=== TEST 2: 외부 상태 미생성 계약 명시 ==="
grep -qE '외부 상태.*(task|이슈|브랜치|원격)' "$SKILL_MD" \
  || fail "SKILL.md에 '외부 상태(task·이슈·브랜치·원격)' 언급 없음"
grep -qE '외부 상태.*(만들지 않|미생성|않는다)' "$SKILL_MD" \
  || fail "SKILL.md에 '외부 상태 미생성' 계약 없음"
ok "외부 상태 미생성 계약 명시"

echo ""
echo "=== TEST 3: 제거된 gh issue/project 명령 부재 (negative) ==="
ALLOWED_BLOCK="$(awk '/^---$/{c++; next} c==1' "$SKILL_MD")"
for ghcmd in 'gh issue create' 'gh issue edit' 'gh project item-list' 'gh project item-edit' 'gh project item-add'; do
  if grep -qF "$ghcmd" <<< "$ALLOWED_BLOCK"; then
    fail "allowed-tools에 제거된 명령 '$ghcmd' 잔존 (외부 상태 미생성 위반)"
  fi
done
ok "제거된 gh issue/project 명령 모두 부재"

echo ""
echo "=== TEST 4: 제거된 마일스톤/PRD/4갈래 분기 어구 부재 (negative) ==="
for stale in 'GitHub Project' 'In Design' 'Backlog' 'milestone-id' '백킹 시스템'; do
  if grep -qF "$stale" "$SKILL_MD"; then
    fail "SKILL.md에 제거된 task-전이 어구 '$stale' 잔존"
  fi
done
ok "제거된 task-전이 어구 모두 부재"

echo ""
echo "=== TEST 5: --resume 모드는 마커 해결만, 외부 상태 미생성 ==="
grep -qE -- '--resume' "$SKILL_MD" || fail "SKILL.md에 --resume 모드 명시 없음"
grep -qF '[NEEDS CLARIFICATION' "$SKILL_MD" \
  || fail "SKILL.md에 미해결 마커([NEEDS CLARIFICATION) 시스템 명시 없음"
ok "--resume + 미해결 마커 시스템 명시"

echo ""
echo "=== TEST 6: persona/clarity 단일 출처 참조 문서 보장 ==="
# 가산 기능의 단일 출처 — 카탈로그/점수 정의는 각각 정확히 한 곳.
PERSONAS_MD="$SKILL_DIR/references/personas.md"
CLARITY_MD="$SKILL_DIR/references/clarity-score.md"
[[ -f "$PERSONAS_MD" ]] || fail "personas.md 단일 출처 문서 부재"
[[ -f "$CLARITY_MD" ]]  || fail "clarity-score.md 단일 출처 문서 부재"
ok "personas.md·clarity-score.md 단일 출처 문서 존재"
# SKILL.md 가 두 단일 출처를 참조
grep -qF 'references/personas.md' "$SKILL_MD" \
  || fail "SKILL.md가 personas.md 단일 출처를 참조하지 않음"
grep -qF 'references/clarity-score.md' "$SKILL_MD" \
  || fail "SKILL.md가 clarity-score.md 단일 출처를 참조하지 않음"
ok "SKILL.md가 두 단일 출처 참조"

echo ""
echo "=== 모든 spec 외부 상태 미생성 + persona/clarity 단일 출처 테스트 통과 ==="
