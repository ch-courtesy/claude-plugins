#!/usr/bin/env bash
# test-loop-persona-lateral.sh
#
# SPEC: loop 스킬 persona verification + lateral unstuck (가산 계약 테스트)
#
# 정적 grep 기반으로 loop 스킬 헌법·위임 양식·운영 안내에 두 가산 기능이
# 명세대로 기술됐는지 검증한다. 외부 API·드라이버 실행은 하지 않는다.
#
# 검증 대상 (수용 기준 매핑):
#
# [페르소나 적대적 검증]
#  P1 constitution Self-Review에 적대 렌즈 검증 절 + 비자명 변경 임계 발동
#  P2 미해결 의심 → 노트 의심점 기록 (조용한 완료 전이 금지)
#  P3 페르소나 카탈로그 단일 출처(spec personas.md) 참조, 렌즈 정의 미복제
#  P4 4-Level Verifier 약화·우회 없이 가산
#  P5 agent-prompts에 적대 렌즈 brief — 발견만 보고, 최종 완료·차단 결정 금지
#
# [정체 시 lateral 회복]
#  L1 에스컬레이션 전 정확히 1회 측면사고 회복 (에피소드당 1회)
#  L2 회복 진전 → 정상 루프 잇고 에스컬레이션 안 함
#  L3 무진전 → 표준 차단 에스컬레이션
#  L4 안전 직결 정지(범위 이탈·테스트 약화·비밀 노출·평가/수용기준 편집) → 회복 없이 즉시
#  L5 드라이버 정지 한계(증상-수정 연속·진동 토글) 내부 유지
#  L6 회복 시도·진전 판정을 task 메모리(노트·인계)에 기록
#  L7 agent-prompts에 lateral 회복 brief — 가설 재구성·읽기 우선·최소 변경·발견만
#  L8 operational-guide에 에스컬레이션 전 1회 회복 + 경계 명시
#
# [불변]
#  I1 bash 드라이버(loop.sh) 미변경 — 정지 게이트 정의가 그대로 존재

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFS="$SCRIPT_DIR/../references"
CONSTITUTION="$REFS/constitution.md"
AGENT_PROMPTS="$REFS/agent-prompts.md"
OPERATIONAL="$REFS/operational-guide.md"
LOOP_SH="$REFS/loop.sh"
# 페르소나 카탈로그 단일 출처 (선행 spec 스킬). loop는 이를 참조만 한다.
PERSONAS="$SCRIPT_DIR/../../../references/personas.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

for f in "$CONSTITUTION" "$AGENT_PROMPTS" "$OPERATIONAL" "$LOOP_SH"; do
  [[ -f "$f" ]] || fail "$f 부재"
done
[[ -f "$PERSONAS" ]] || fail "페르소나 카탈로그 단일 출처 부재: $PERSONAS (선행 SPEC 미적용)"

# ---------------------------------------------------------------------------
# 섹션 추출 헬퍼: 주어진 헤더 라인부터 다음 동급 이상 헤더 직전까지.
# (정확 매칭이 어려운 경우 전체 파일 grep으로 대체)
# ---------------------------------------------------------------------------

# === P1: 적대 렌즈 검증 절 + 비자명 변경 임계 ===
echo "=== P1: 적대 렌즈 검증 절 + 비자명 임계 ==="
grep -qE '적대 렌즈|적대적 검증|페르소나' "$CONSTITUTION" \
  || fail "P1: constitution에 적대 렌즈/페르소나 검증 절 부재"
# 비자명 변경 임계: diff 규모(줄 수) 또는 관여 수용기준 수
grep -qE '비자명|100줄' "$CONSTITUTION" \
  || fail "P1: constitution에 비자명 변경 임계(diff 규모/100줄) 부재"
grep -qE '수용 ?기준 (수|개)|수용기준 (수|개)' "$CONSTITUTION" \
  || fail "P1: constitution에 관여 수용기준 수 임계 부재"
ok "P1"

# === P2: 미해결 의심 → 노트 의심점 기록 ===
echo "=== P2: 의심점 기록 ==="
# 적대 렌즈 발견이 의심을 가리키면 조용히 완료하지 않고 의심점에 기록
awk '/적대 렌즈|적대적 검증|페르소나/{f=1} f{print}' "$CONSTITUTION" | grep -qE '의심점' \
  || fail "P2: 적대 렌즈 절에 '의심점' 기록 경로 부재"
ok "P2"

# === P3: 페르소나 카탈로그 단일 출처 참조, 미복제 ===
echo "=== P3: personas.md 단일 출처 참조 ==="
grep -qE 'personas\.md' "$CONSTITUTION" \
  || fail "P3: constitution이 페르소나 카탈로그(personas.md) 단일 출처를 참조하지 않음"
# 세 렌즈 이름을 정의(복제)하지 않아야 한다 — 적어도 한 렌즈 정의 표제를 자체 보유하면 복제로 간주.
# personas.md의 정의 표제 패턴(예: "contrarian — 반대 가정")이 constitution에 그대로 복제되면 실패.
if grep -qE 'contrarian — |minimalist — |constraint-auditor — ' "$CONSTITUTION"; then
  fail "P3: constitution이 렌즈 정의를 복제함 (단일 출처 참조만 허용)"
fi
ok "P3"

# === P4: 4-Level Verifier 가산(약화·우회 없음) ===
echo "=== P4: 4-Level 가산성 ==="
awk '/적대 렌즈|적대적 검증|페르소나/{f=1} f{print}' "$CONSTITUTION" | grep -qE '가산|약화하지|우회하지|대체하지' \
  || fail "P4: 적대 렌즈 절에 기존 구조 검증 가산(약화·우회 없음) 명시 부재"
# 기존 4-Level Verifier 섹션이 그대로 존재
grep -qE '4-Level Verifier|Existence|Substantive|Wired|Runtime' "$CONSTITUTION" \
  || fail "P4: 기존 4-Level Verifier 섹션이 사라짐 (가산이 아니라 대체됨)"
ok "P4"

# === P5: agent-prompts 적대 렌즈 brief — 발견만, 최종 결정 금지 ===
echo "=== P5: agent-prompts 적대 렌즈 brief ==="
grep -qE '적대 렌즈|적대적 검증|페르소나' "$AGENT_PROMPTS" \
  || fail "P5: agent-prompts에 적대 렌즈 brief 부재"
# 발견만 보고 + 최종 완료/차단 결정 금지
awk '/적대 렌즈|적대적 검증|페르소나/{f=1} f{print}' "$AGENT_PROMPTS" | grep -qE '발견만|발견을 보고' \
  || fail "P5: 적대 렌즈 brief에 '발견만 보고' 명시 부재"
awk '/적대 렌즈|적대적 검증|페르소나/{f=1} f{print}' "$AGENT_PROMPTS" | grep -qE '최종.*결정|완료.*차단.*결정|결정.*금지' \
  || fail "P5: 적대 렌즈 brief에 최종 완료·차단 결정 금지 명시 부재"
# personas.md 참조 (정의 복제 금지)
grep -qE 'personas\.md' "$AGENT_PROMPTS" \
  || fail "P5: agent-prompts 적대 렌즈 brief가 personas.md를 참조하지 않음"
ok "P5"

# === L1: 에스컬레이션 전 정확히 1회 회복 (에피소드당 1회) ===
echo "=== L1: 1회 측면사고 회복 ==="
grep -qE '측면사고|lateral|측면 사고' "$CONSTITUTION" \
  || fail "L1: constitution에 측면사고(lateral) 회복 절 부재"
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$CONSTITUTION" | grep -qE '정확히 한 번|한 번|1회|에피소드당' \
  || fail "L1: 회복이 에스컬레이션 전 정확히 1회/에피소드당 1회로 제한 명시 부재"
ok "L1"

# === L2: 진전 → 정상 루프, 에스컬레이션 안 함 ===
echo "=== L2: 진전 시 정상 루프 ==="
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$CONSTITUTION" | grep -qE '진전' \
  || fail "L2: 회복 절에 진전 판정 부재"
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$CONSTITUTION" | grep -qE '정상 루프|루프를 (잇|이어)|에스컬레이션하지 않' \
  || fail "L2: 진전 시 정상 루프 지속(에스컬레이션 안 함) 명시 부재"
ok "L2"

# === L3: 무진전 → 표준 차단 에스컬레이션 ===
echo "=== L3: 무진전 시 표준 에스컬레이션 ==="
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$CONSTITUTION" | grep -qE '무진전|진전.*없|진전이 없' \
  || fail "L3: 무진전 판정 부재"
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$CONSTITUTION" | grep -qE '에스컬레이션|차단|BLOCKED' \
  || fail "L3: 무진전 시 차단 에스컬레이션 명시 부재"
ok "L3"

# === L4: 안전 직결 정지 → 회복 없이 즉시 에스컬레이션 ===
echo "=== L4: 안전 정지 즉시 에스컬레이션 ==="
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$CONSTITUTION" | grep -qE '즉시 에스컬레이션|회복 없이|회복 시도 없이' \
  || fail "L4: 안전 직결 정지의 즉시(회복 없이) 에스컬레이션 명시 부재"
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$CONSTITUTION" | grep -qE '범위 이탈|scope|테스트 약화|비밀|평가|수용 ?기준' \
  || fail "L4: 안전 직결 정지 조건(범위·테스트 약화·비밀·평가/수용기준) 명시 부재"
ok "L4"

# === L5: 드라이버 정지 한계 내부 유지 ===
echo "=== L5: 드라이버 정지 한계 내부 ==="
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$CONSTITUTION" | grep -qE '드라이버|정지 한계|증상.*연속|진동' \
  || fail "L5: 회복이 드라이버 정지 한계(증상-수정 연속·진동) 내부 유지 명시 부재"
ok "L5"

# === L6: 회복 시도·판정 노트 기록 ===
echo "=== L6: 노트 기록 ==="
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$CONSTITUTION" | grep -qE '노트|인계|메모리|콜드' \
  || fail "L6: 회복 시도·판정의 task 메모리(노트/인계) 기록 명시 부재"
ok "L6"

# === L7: agent-prompts lateral 회복 brief ===
echo "=== L7: agent-prompts lateral brief ==="
grep -qE '측면사고|lateral|측면 사고' "$AGENT_PROMPTS" \
  || fail "L7: agent-prompts에 lateral 회복 brief 부재"
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$AGENT_PROMPTS" | grep -qE '가설' \
  || fail "L7: lateral brief에 가설 재구성 부재"
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$AGENT_PROMPTS" | grep -qE '읽기 우선|read-only|읽기를 우선|관찰' \
  || fail "L7: lateral brief에 읽기 우선 부재"
awk '/측면사고|lateral|측면 사고/{f=1} f{print}' "$AGENT_PROMPTS" | grep -qE '최소 변경|발견만' \
  || fail "L7: lateral brief에 최소 변경/발견만 보고 부재"
ok "L7"

# === L8: operational-guide 에스컬레이션 전 1회 회복 + 경계 ===
echo "=== L8: operational-guide 회복 경계 ==="
grep -qE '측면사고|lateral|측면 사고|회복' "$OPERATIONAL" \
  || fail "L8: operational-guide에 에스컬레이션 전 회복 안내 부재"
awk '/측면사고|lateral|측면 사고|회복/{f=1} f{print}' "$OPERATIONAL" | grep -qE '1회|한 번|에피소드당|에스컬레이션 전' \
  || fail "L8: operational-guide에 1회 회복 경계 명시 부재"
ok "L8"

# === I1: 드라이버(loop.sh) 정지 게이트 정의 그대로 존재 ===
echo "=== I1: 드라이버 정지 게이트 불변 ==="
# 본 SPEC은 bash 드라이버를 변경하지 않는다. 기존 정지 게이트 정의가 loop.sh에 존재해야 한다.
grep -qE 'fix:symptom|진동|테스트 약화|suppressor|deps modified|Scope' "$LOOP_SH" \
  || fail "I1: loop.sh의 기존 정지 게이트 정의가 사라짐 (드라이버 회귀)"
ok "I1"

echo ""
echo "ALL CHECKS PASSED"
