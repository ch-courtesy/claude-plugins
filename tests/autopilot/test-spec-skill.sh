#!/usr/bin/env bash
# autopilot:spec 스킬 계약 검증 테스트 (자연 인터뷰 재설계 + persona/clarity 가산)
#
# 정합 갱신: 명확화 인터뷰 자연화 재설계로 spec 스킬은
#   (a) 별도 "섹션별 SPEC 승인" 단계(구 step 5)를 제거해 워크플로가 7단계로 줄었고,
#   (b) 사용자 노출 용어를 평이화해 "EARS" 약어를 쓰지 않고 "완료 조건" 라벨을 쓰며,
#   (c) 인터뷰 종료·최종 승인 시 dispatch 로의 옵트인 자동 핸드오프를 도입했다.
# 본 테스트는 과거의 'EARS 마커 존재 + 섹션별 SPEC + 8단계' 단언을
#   동등 강도의 신 계약 단언('EARS 부재 + 완료 조건 + 섹션별 SPEC 부재 + 7단계 + 옵트인 핸드오프')으로
#   재작성한다. 단언을 삭제·skip·약화하지 않는다(정합 갱신이지 커버리지 축소가 아니다).
# persona 적대 리뷰 + clarity 점수 검증 assert 는 그대로 가산 보존한다.
#
# 정적(grep) 검사. 실제 사용자 인터랙션·외부 도구 호출은 e2e 범위 밖.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/spec"
SKILL_MD="$SKILL_DIR/SKILL.md"
SELF_REVIEW_MD="$SKILL_DIR/references/self-review.md"
CLARIFICATION_MD="$SKILL_DIR/references/clarification.md"
AGENT_PROMPTS="$SKILL_DIR/references/agent-prompts.md"
PERSONAS_MD="$SKILL_DIR/references/personas.md"
CLARITY_MD="$SKILL_DIR/references/clarity-score.md"
SPEC_TEMPLATE="$SKILL_DIR/references/spec-template.md"
EARS_PATTERNS="$SKILL_DIR/references/ears-patterns.md"
DECOMP_MD="$SKILL_DIR/references/decomposition-gate.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$SKILL_MD" ]] || fail "SKILL.md 부재: $SKILL_MD"

# ===========================================================================
# PART A — 현 경량 계약 정합 검증
# ===========================================================================

echo "=== TEST A1: 외부 상태 미생성 경량 계약 + 제거 어구 부재 ==="
# 경량 redesign: 산출물은 SPEC 문서뿐. task·이슈·브랜치·원격 미생성.
grep -qE '외부 상태.*(만들지 않|미생성|않는다)' "$SKILL_MD" \
  || fail "SKILL.md에 '외부 상태 미생성' 계약 명시 없음"
ok "외부 상태 미생성 계약 명시"
# stale/제거 기능 잔존 금지 (negative):
#   - 검증 실패 라우팅·milestone-id·test_sweep_paths·마일스톤 규모: 경량 계약에서 이미 제거
#   - 섹션별 SPEC: 자연 인터뷰 재설계로 섹션별 승인 단계 제거
#   - EARS: 사용자 노출 용어 평이화로 약어 제거 ("완료 조건"으로 대체)
for stale in '검증 실패 라우팅' 'milestone-id' 'test_sweep_paths' '마일스톤 규모' '섹션별 SPEC' 'EARS'; do
  if grep -qF "$stale" "$SKILL_MD"; then
    fail "SKILL.md에 제거/평이화 대상 어구 '$stale' 잔존 (신 계약 위반)"
  fi
done
ok "제거/평이화 대상 어구(라우팅·milestone-id·섹션별 SPEC·EARS 등) 잔존 없음"

echo ""
echo "=== TEST A2: 7단계 워크플로 + 핵심 step 보존 + 섹션별 승인 부재 ==="
# 섹션별 SPEC 승인(구 step 5) 제거로 워크플로는 7단계.
for step_kw in '컨텍스트 탐색' '범위 분해 게이트' '명확화' '접근법 비교' 'SPEC 문서 작성' '자체 검토' '구현 스킬 추천'; do
  grep -qF "$step_kw" "$SKILL_MD" \
    || fail "7단계 step 키워드 '$step_kw' 보존 실패"
done
ok "7단계 step 키워드 모두 존재"
step_count=$(grep -cE '^### [0-9]+\.' "$SKILL_MD")
[[ "$step_count" -eq 7 ]] \
  || fail "워크플로 step 헤더 수가 7이 아님 (실제: $step_count) — 섹션별 승인 제거로 7단계여야 함"
ok "워크플로 step 헤더 정확히 7개 (줄어든 단계 수 단언)"
grep -qF 'WHAT/HOW' "$SKILL_MD" || fail "WHAT/HOW 방어선 명시 보존 실패"
ok "WHAT/HOW 방어선 보존"

echo ""
echo "=== TEST A2b: 평이화 — 완료 조건 라벨 + EARS 부재 ==="
# 사용자 노출 용어 평이화: SKILL 본문은 "완료 조건" 라벨을 쓰고 "EARS" 약어를 쓰지 않는다.
grep -qF '완료 조건' "$SKILL_MD" || fail "SKILL.md에 '완료 조건' 라벨 부재"
ok "SKILL.md '완료 조건' 라벨 존재"
# (EARS 부재는 A1 negative 루프에서 단언됨 — 여기서는 라벨 존재만 가산)

echo ""
echo "=== TEST A3: AskUserQuestion 기반 결정 + dispatch 추천 ==="
grep -qF 'AskUserQuestion' "$SKILL_MD" || fail "AskUserQuestion 도구 참조 없음"
ok "AskUserQuestion 참조 존재"
grep -qF 'autopilot:dispatch' "$SKILL_MD" || fail "구현 스킬 추천(autopilot:dispatch) 명시 없음"
ok "dispatch 추천 명시"

echo ""
echo "=== TEST A4: agent-prompts.md 양식 + 역할 2종 ==="
[[ -f "$AGENT_PROMPTS" ]] || fail "agent-prompts.md 부재: $AGENT_PROMPTS"
for role in 'spec-context-explorer' 'spec-self-reviewer'; do
  grep -qF "$role" "$AGENT_PROMPTS" || fail "agent-prompts.md에 역할 헤더 '$role' 부재"
  grep -qF "$role" "$SKILL_MD"      || fail "SKILL.md 본문에 역할명 '$role' 부재"
done
ok "두 역할(spec-context-explorer·spec-self-reviewer) agent-prompts·SKILL 본문 등장"
ref_count=$(grep -cE 'references/agent-prompts\.md' "$SKILL_MD")
[[ "$ref_count" -ge 2 ]] || fail "SKILL.md에 references/agent-prompts.md 참조 2회 미만"
ok "agent-prompts.md 참조 2회 이상"

echo ""
echo "=== TEST A5: agent-prompts.md 단계 번호 정합 (실제 7단계와 일치) ==="
# 섹션별 승인 제거로 7단계다. stale '10-step'·'8-step/8단계' 잔존 금지.
if grep -qE '10[- ]?step|10단계|8[- ]?step|8단계' "$AGENT_PROMPTS"; then
  fail "agent-prompts.md에 stale '8/10-step·8/10단계' 잔존 (실제 7단계)"
fi
ok "agent-prompts.md에 stale 8/10-step 잔존 없음"
grep -qE '7[- ]?step|7단계' "$AGENT_PROMPTS" \
  || fail "agent-prompts.md에 정정된 '7-step/7단계' 표기 부재"
ok "7-step 표기 존재"
# context-explorer 는 step 1, self-reviewer 는 step 6(자체 검토)을 가리켜야 한다.
grep -qE 'step 1 컨텍스트 탐색|step 1 .*컨텍스트' "$AGENT_PROMPTS" \
  || fail "context-explorer 언제 절이 step 1(컨텍스트 탐색)을 가리키지 않음"
ok "context-explorer → step 1"
grep -qE 'step 6 자체 검토|step 6 .*자체 검토' "$AGENT_PROMPTS" \
  || fail "self-reviewer 언제 절이 step 6(자체 검토)을 가리키지 않음"
ok "self-reviewer → step 6"

echo ""
echo "=== TEST A6: 모듈 구성 표 + 헌법 §11.6 + 결정·합성 메인 책임 ==="
grep -qE '§11\.6|이터 내 서브 도구 위임' "$SKILL_MD" \
  || fail "SKILL.md에 헌법 §11.6 / '이터 내 서브 도구 위임' 인용 부재"
ok "§11.6 인용 존재"
grep -qE '결정·합성.*메인|메인.*결정·합성|결정과 합성.*메인|결정.*합성은 메인' "$SKILL_MD" \
  || fail "SKILL.md에 '결정·합성은 메인 책임' 문구 부재"
ok "결정·합성 메인 책임 문구 존재"

echo ""
echo "=== TEST A7: decomposition-gate.md 단계 번호·용어 정합 ==="
[[ -f "$DECOMP_MD" ]] || fail "decomposition-gate.md 부재: $DECOMP_MD"
# 워크플로는 7단계 — 구현 스킬 추천은 step 7이다. stale 'step 8' 잔존 금지.
if grep -qE 'step 8|step8|8단계' "$DECOMP_MD"; then
  fail "decomposition-gate.md에 stale 'step 8' 잔존 (실제 추천은 step 7)"
fi
ok "decomposition-gate.md stale 'step 8' 부재"
grep -qE 'step 7' "$DECOMP_MD" \
  || fail "decomposition-gate.md가 정정된 'step 7'(추천 단계)을 가리키지 않음"
ok "decomposition-gate.md → step 7 참조"
# SPEC 문서 작성은 step 5다. stale 'step 6'(구 번호) 잔존 금지.
if grep -qE 'step 6' "$DECOMP_MD"; then
  fail "decomposition-gate.md에 stale 'step 6' 잔존 (SPEC 문서 작성은 step 5)"
fi
ok "decomposition-gate.md stale 'step 6' 부재"
grep -qE 'step 5' "$DECOMP_MD" \
  || fail "decomposition-gate.md가 SPEC 문서 작성 단계 'step 5'를 가리키지 않음"
ok "decomposition-gate.md → step 5 참조"
# 평이화: 사용자 노출 용어는 '완료 조건' — 'EARS' 약어 잔존 금지.
if grep -qF 'EARS' "$DECOMP_MD"; then
  fail "decomposition-gate.md에 'EARS' 약어 잔존 (평이화 위반 — '완료 조건' 사용)"
fi
ok "decomposition-gate.md 'EARS' 부재"

# ===========================================================================
# PART B — persona 적대 리뷰 (신규 가산)
# ===========================================================================

echo ""
echo "=== TEST B1: 페르소나 카탈로그 단일 출처 문서 존재 ==="
[[ -f "$PERSONAS_MD" ]] || fail "페르소나 카탈로그 references/personas.md 부재"
ok "references/personas.md 존재"
grep -qF '단일 출처' "$PERSONAS_MD" || fail "personas.md에 '단일 출처' 명시 없음"
ok "단일 출처 명시"
# 다른 스킬은 복제 없이 참조
grep -qE '복제(하지|없)' "$PERSONAS_MD" \
  || fail "personas.md에 '복제 없이 참조' 의미 어구 없음"
ok "복제 없이 참조 명시"

echo ""
echo "=== TEST B2: 세 적대 렌즈 정의 (반대가정·최소해법·구속제약) ==="
grep -qF '반대 가정' "$PERSONAS_MD" || fail "personas.md에 '반대 가정' 렌즈 없음"
grep -qF '최소 해법' "$PERSONAS_MD" || fail "personas.md에 '최소 해법' 렌즈 없음"
grep -qF '구속력 있는 제약' "$PERSONAS_MD" || fail "personas.md에 '구속력 있는 제약' 렌즈 없음"
ok "세 적대 렌즈 어구 모두 존재"
# 렌즈는 발견만 보고 (편집·마커 삽입 금지)
grep -qF '발견만' "$PERSONAS_MD" || fail "personas.md에 '발견만 보고' 제약 없음"
ok "발견만 보고 제약 명시"

echo ""
echo "=== TEST B3: self-review.md 적대 렌즈 절 (규모 임계 발동) ==="
[[ -f "$SELF_REVIEW_MD" ]] || fail "self-review.md 부재"
grep -qE '적대 렌즈|페르소나' "$SELF_REVIEW_MD" \
  || fail "self-review.md에 적대 렌즈/페르소나 절 없음"
ok "self-review.md 적대 렌즈 절 존재"
grep -qF 'personas.md' "$SELF_REVIEW_MD" \
  || fail "self-review.md가 personas.md 단일 출처를 참조하지 않음"
ok "self-review.md → personas.md 참조"
# 기존 규모 임계로만 발동: 100줄·마커 2개
grep -qE '100줄' "$SELF_REVIEW_MD" || fail "self-review.md에 규모 임계 '100줄' 부재"
grep -qE '마커 2개|2개 이상' "$SELF_REVIEW_MD" || fail "self-review.md에 규모 임계 '마커 2개' 부재"
ok "규모 임계(100줄·마커 2개) 발동 명시"
# 기존 5축 자체 검토 보존 (가산성: 약화하지 않음)
grep -qE '5 ?checks|5축|5 개 체크' "$SELF_REVIEW_MD" \
  || fail "self-review.md 기존 5축 자체 검토 보존 실패 (적대 렌즈는 가산이어야 함)"
ok "기존 5축 자체 검토 보존 (적대 렌즈 가산)"

echo ""
echo "=== TEST B4: SKILL.md step 6 적대 렌즈 + 메인 반영 ==="
grep -qF 'references/personas.md' "$SKILL_MD" \
  || fail "SKILL.md가 references/personas.md를 참조하지 않음"
ok "SKILL.md → personas.md 참조"
grep -qE '적대 렌즈' "$SKILL_MD" || fail "SKILL.md에 '적대 렌즈' 어구 없음"
ok "SKILL.md 적대 렌즈 어구 존재"

echo ""
echo "=== TEST B5: agent-prompts self-reviewer 양식에 적대 렌즈 질문 (발견만) ==="
grep -qF 'personas.md' "$AGENT_PROMPTS" \
  || fail "agent-prompts.md self-reviewer 양식이 personas.md를 참조하지 않음"
ok "agent-prompts.md → personas.md 참조"
grep -qE '적대 렌즈|반대 가정' "$AGENT_PROMPTS" \
  || fail "agent-prompts.md에 적대 렌즈 질문 어구 없음"
ok "agent-prompts.md 적대 렌즈 질문 존재"
# 위임 보조자는 발견만 보고, 편집·마커 삽입 금지
grep -qE '수정·마커 삽입 금지|마커 삽입 금지|발견만' "$AGENT_PROMPTS" \
  || fail "agent-prompts.md에 '발견만 보고, 마커 삽입 금지' 제약 없음"
ok "보조자 발견만 보고·마커 삽입 금지 제약 명시"

# ===========================================================================
# PART C — clarity 점수 (신규 가산)
# ===========================================================================

echo ""
echo "=== TEST C1: clarity 점수 단일 출처 문서 존재 ==="
[[ -f "$CLARITY_MD" ]] || fail "clarity 점수 references/clarity-score.md 부재"
ok "references/clarity-score.md 존재"
for dim in '목적' '제약' '성공기준'; do
  grep -qF "$dim" "$CLARITY_MD" || fail "clarity-score.md에 차원 '$dim' 없음"
done
ok "차원(목적·제약·성공기준) 정의"
grep -qF '차원' "$CLARITY_MD" || fail "clarity-score.md에 '차원' 개념 없음"
grep -qE '척도|스케일' "$CLARITY_MD" || fail "clarity-score.md에 '척도' 없음"
ok "차원·척도 정의"

echo ""
echo "=== TEST C2: 메인 추론 산정 + 무인프라 ==="
grep -qE '메인.*추론|추론.*산정' "$CLARITY_MD" \
  || fail "clarity-score.md에 '메인 에이전트 추론 산정' 명시 없음"
ok "메인 추론 산정 명시"
grep -qE '새 (런타임|엔진|의존성)|런타임·엔진·의존성|엔진·의존성' "$CLARITY_MD" \
  || fail "clarity-score.md에 '새 런타임·엔진·의존성 불요' 명시 없음"
ok "무인프라(새 런타임·엔진·의존성 불요) 명시"

echo ""
echo "=== TEST C3: 소프트 권고 + 미해결 마커 보완(대체 아님) ==="
grep -qE '소프트 권고|소프트' "$CLARITY_MD" || fail "clarity-score.md에 '소프트 권고' 없음"
ok "소프트 권고 명시"
grep -qE '차단하지 않|자동 게이트.*않|게이트로 동작하지 않' "$CLARITY_MD" \
  || fail "clarity-score.md에 'SPEC 작성을 차단/게이트하지 않음' 명시 없음"
ok "비차단·비게이트 명시"
grep -qF '미해결 마커' "$CLARITY_MD" || fail "clarity-score.md에 '미해결 마커' 보완 규칙 없음"
grep -qE '대체하지 않|대체가 아|보완' "$CLARITY_MD" \
  || fail "clarity-score.md에 '미해결 마커 보완(대체 아님)' 규칙 없음"
ok "미해결 마커 보완(대체 아님) 규칙 명시"
grep -qE '임계' "$CLARITY_MD" || fail "clarity-score.md에 '권장 임계' 없음"
ok "권장 임계 명시"

echo ""
echo "=== TEST C4: clarification.md 잠정 종결 시 clarity 리드아웃 + 소프트 권고 ==="
[[ -f "$CLARIFICATION_MD" ]] || fail "clarification.md 부재"
grep -qiF 'clarity' "$CLARIFICATION_MD" \
  || fail "clarification.md에 clarity 점수 절 없음"
ok "clarification.md clarity 절 존재"
grep -qF 'clarity-score.md' "$CLARIFICATION_MD" \
  || fail "clarification.md가 clarity-score.md 단일 출처를 참조하지 않음"
ok "clarification.md → clarity-score.md 참조"
# 추가 명확화 권고는 구조화 선택지(AskUserQuestion)로, 자유 텍스트 금지
grep -qF 'AskUserQuestion' "$CLARIFICATION_MD" \
  || fail "clarification.md clarity 권고가 AskUserQuestion(구조화 선택지) 매체를 명시하지 않음"
ok "구조화 선택지(AskUserQuestion) 권고 매체 명시"

echo ""
echo "=== TEST C5: SKILL.md 명확화 종결에 clarity 리드아웃·소프트 권고 ==="
grep -qiF 'clarity' "$SKILL_MD" || fail "SKILL.md에 clarity 점수 언급 없음"
ok "SKILL.md clarity 언급 존재"
grep -qF 'references/clarity-score.md' "$SKILL_MD" \
  || fail "SKILL.md가 references/clarity-score.md를 참조하지 않음"
ok "SKILL.md → clarity-score.md 참조"

echo ""
echo "=== TEST C6: SKILL.md 모듈 구성 표에 personas.md·clarity-score.md 행 ==="
grep -qE '^\|.*personas\.md.*\|' "$SKILL_MD" \
  || fail "모듈 구성 표에 personas.md 행 부재"
ok "모듈 표 personas.md 행 존재"
grep -qE '^\|.*clarity-score\.md.*\|' "$SKILL_MD" \
  || fail "모듈 구성 표에 clarity-score.md 행 부재"
ok "모듈 표 clarity-score.md 행 존재"

# ===========================================================================
# PART D — 자연 인터뷰 + 옵트인 핸드오프 (신 계약)
# ===========================================================================

echo ""
echo "=== TEST D1: 자연 인터뷰 — 깔때기형 + 내부 커버리지 체크리스트 ==="
[[ -f "$CLARIFICATION_MD" ]] || fail "clarification.md 부재"
# 사용자의 최초 진술에서 출발하고 직전 답에서 다음 질문이 파생되는 단일 흐름
grep -qE '최초 진술|처음 한 말|첫 문장|되짚' "$CLARIFICATION_MD" \
  || fail "clarification.md에 '사용자 최초 진술 되짚기' 흐름 명시 없음"
ok "clarification.md 최초 진술 되짚기 명시"
grep -qE '직전 답.*파생|파생.*직전 답|이전 답.*파생' "$CLARIFICATION_MD" \
  || fail "clarification.md에 '직전 답에서 다음 질문 파생' 명시 없음"
ok "clarification.md 직전 답 파생 명시"
# 목적·성공기준·제약·위험은 사용자 슬롯이 아니라 내부 커버리지 체크리스트
grep -qE '내부 커버리지|커버리지 체크리스트' "$CLARIFICATION_MD" \
  || fail "clarification.md에 '내부 커버리지 체크리스트' 개념 없음"
ok "clarification.md 내부 커버리지 체크리스트 명시"
grep -qE '나열(해|하지).*않|슬롯|카테고리.*나열' "$CLARIFICATION_MD" \
  || fail "clarification.md에 '카테고리를 사용자에게 나열하지 않음' 명시 없음"
ok "clarification.md 카테고리 비나열 명시"

echo ""
echo "=== TEST D2: 최종 단일 승인 (섹션별 승인 흡수) ==="
grep -qE '마지막에 한 번|전체를.*한 번|완성된 SPEC.*한 번|최종.*단일 승인|단일 승인' "$SKILL_MD" \
  || fail "SKILL.md에 '완성 SPEC을 마지막에 한 번 제시·단일 승인' 명시 없음"
ok "SKILL.md 최종 단일 승인 명시"

echo ""
echo "=== TEST D3: 옵트인 자동 핸드오프 (명시 동의 시에만 dispatch) ==="
grep -qF '옵트인' "$SKILL_MD" || fail "SKILL.md에 '옵트인' 핸드오프 개념 없음"
ok "옵트인 개념 명시"
grep -qE '구현까지 자동|자동으로 진행|자동 진행' "$SKILL_MD" \
  || fail "SKILL.md에 '구현까지 자동 진행' 핸드오프 제안 없음"
ok "자동 진행 제안 명시"
grep -qE '명시.*동의|동의.*명시|명시적 동의' "$SKILL_MD" \
  || fail "SKILL.md에 '명시 동의 시에만' 옵트인 경계 없음"
ok "명시 동의 경계 명시"
# 동의 시 dispatch 호출 / 미동의 시 어떤 후속 스킬도 호출하지 않음
grep -qE '동의.*dispatch|dispatch.*호출|호출한다' "$SKILL_MD" \
  || fail "SKILL.md에 '동의 시 dispatch 호출' 명시 없음"
ok "동의 시 dispatch 호출 명시"

echo ""
echo "=== TEST D4: 미해결 마커 시 핸드오프 미제안 + --resume 안내 ==="
grep -qE '\[NEEDS CLARIFICATION' "$SKILL_MD" \
  || fail "SKILL.md에 '[NEEDS CLARIFICATION' 마커 언급 없음"
ok "미해결 마커 언급 존재"
grep -qE '자율 실행.*차단|차단된다' "$SKILL_MD" \
  || fail "SKILL.md에 '마커 잔존 시 자율 실행 차단' 명시 없음"
ok "마커 잔존 시 자율 실행 차단 명시"
grep -q -- '--resume' "$SKILL_MD" \
  || fail "SKILL.md에 '--resume 해결 방법' 안내 없음"
ok "--resume 안내 존재"

# ===========================================================================
# PART E — 평이화: SPEC 템플릿 본문 + 완료 조건 문장 패턴
# ===========================================================================

echo ""
echo "=== TEST E1: SPEC 템플릿 본문 평이화 (완료 조건 라벨, EARS 부재) ==="
[[ -f "$SPEC_TEMPLATE" ]] || fail "spec-template.md 부재"
grep -qE '^##[[:space:]]*완료 조건' "$SPEC_TEMPLATE" \
  || fail "spec-template.md 수용 기준 섹션 제목이 '완료 조건'이 아님"
ok "spec-template.md '## 완료 조건' 섹션 제목 존재"
if grep -qF 'EARS' "$SPEC_TEMPLATE"; then
  fail "spec-template.md 본문에 'EARS' 약어 잔존 (평이화 위반)"
fi
ok "spec-template.md 본문 'EARS' 부재"

echo ""
echo "=== TEST E2: 완료 조건 5문장 패턴 평이한 한국어 안내 ==="
[[ -f "$EARS_PATTERNS" ]] || fail "ears-patterns.md 부재"
# 영문 패턴 유형명(Ubiquitous/Event-driven 등) 대신 평이한 한국어 안내
if grep -qE 'Ubiquitous|Event-driven|State-driven' "$EARS_PATTERNS"; then
  fail "ears-patterns.md에 영문 패턴 유형명(Ubiquitous/Event-driven 등) 잔존 (평이화 위반)"
fi
ok "ears-patterns.md 영문 패턴 유형명 부재"
# 평이한 한국어 안내 어구 존재: 항상 / …할 때 / …인 동안 / 오류(…이면) / 기능이 켜지면
for plain in '항상' '할 때' '동안' '오류' '기능'; do
  grep -qF "$plain" "$EARS_PATTERNS" \
    || fail "ears-patterns.md에 평이한 한국어 패턴 안내 어구 '$plain' 없음"
done
ok "평이한 한국어 5문장 패턴 안내 존재"

# ===========================================================================
# PART F — 목적(WHY) 섹션 보존 (신 계약)
# ===========================================================================

echo ""
echo "=== TEST F1: SPEC 템플릿 목적 섹션 + placeholder + 위치 ==="
# 목적 섹션은 "무엇을 만들 것인가" 뒤, "완료 조건" 앞에 위치.
grep -qE '^##[[:space:]]*목적' "$SPEC_TEMPLATE" \
  || fail "spec-template.md에 목적 섹션 제목(## 목적 ...) 부재"
ok "spec-template.md 목적 섹션 제목 존재"
grep -qF '{{purpose}}' "$SPEC_TEMPLATE" \
  || fail "spec-template.md에 목적 placeholder {{purpose}} 부재"
ok "spec-template.md {{purpose}} placeholder 존재"
what_ln=$(grep -nE '^##[[:space:]]*무엇을 만들 것인가' "$SPEC_TEMPLATE" | head -1 | cut -d: -f1)
purpose_ln=$(grep -nE '^##[[:space:]]*목적' "$SPEC_TEMPLATE" | head -1 | cut -d: -f1)
done_ln=$(grep -nE '^##[[:space:]]*완료 조건' "$SPEC_TEMPLATE" | head -1 | cut -d: -f1)
[[ -n "$what_ln" && -n "$purpose_ln" && -n "$done_ln" ]] \
  || fail "spec-template.md 섹션 줄번호 추출 실패 (what=$what_ln purpose=$purpose_ln done=$done_ln)"
(( what_ln < purpose_ln && purpose_ln < done_ln )) \
  || fail "목적 섹션 위치가 'WHAT 뒤·완료 조건 앞'이 아님 (what=$what_ln purpose=$purpose_ln done=$done_ln)"
ok "목적 섹션 위치: '무엇을 만들 것인가' 뒤·'완료 조건' 앞"

echo ""
echo "=== TEST F2: SKILL.md step 5 — {{purpose}} 치환 + 종속 앵커·비검증 규칙 ==="
grep -qF '{{purpose}}' "$SKILL_MD" \
  || fail "SKILL.md 치환 대상 목록에 {{purpose}} 부재"
ok "SKILL.md {{purpose}} 치환 대상 명시"
grep -qF '종속 앵커' "$SKILL_MD" \
  || fail "SKILL.md에 목적='완료 조건의 종속 앵커' 규칙 부재"
ok "SKILL.md 목적 종속 앵커 규칙 명시"
grep -qE '검증 기준이 아|검증 기준 아' "$SKILL_MD" \
  || fail "SKILL.md에 목적='검증 기준이 아님' 규칙 부재"
ok "SKILL.md 목적 비검증 규칙 명시"

echo ""
echo "=== TEST F2b: SKILL.md 구조 계약 — 워크플로 헤더 7개 + 대문자 EARS 부재 ==="
# 완료 조건 8: 워크플로 단계 헤더는 정확히 7개 (새 단계 추가 금지)
header_count=$(grep -cE '^###[[:space:]]+[0-9]+\.' "$SKILL_MD")
[[ "$header_count" -eq 7 ]] \
  || fail "SKILL.md 워크플로 헤더가 7개가 아님 (실제 $header_count) — 새 단계 추가 금지 (완료 조건 8)"
ok "SKILL.md 워크플로 단계 헤더 정확히 7개"
# 완료 조건 9: 대문자 EARS 문자열 부재 (소문자 ears-patterns.md 경로는 허용)
if grep -qF 'EARS' "$SKILL_MD"; then
  fail "SKILL.md에 대문자 EARS 문자열 존재 — 평이한 한국어 유지 (완료 조건 9)"
fi
ok "SKILL.md 대문자 EARS 문자열 부재"

echo ""
echo "=== TEST F3: clarification.md '충분' 종결 조건에 목적(왜) ==="
grep -qE '목적\(왜\)' "$CLARIFICATION_MD" \
  || fail "clarification.md 종결 조건에 '목적(왜)' 항목 부재"
ok "clarification.md 종결 조건 목적(왜) 포함"

echo ""
echo "=== TEST F4: clarity-score.md 목적 차원 보존 의무 연결 ==="
grep -qE '문장으로 남' "$CLARITY_MD" \
  || fail "clarity-score.md 목적 차원이 'SPEC 문서에 문장으로 남았는가' 보존 의무와 미연결"
ok "clarity-score.md 목적 보존 의무 연결"

echo ""
echo "=== TEST F5: self-review.md 5축 유지 + 목적 점검 흡수 ==="
check_count=$(grep -cE '^[0-9]+\. ' "$SELF_REVIEW_MD")
[[ "$check_count" -eq 5 ]] \
  || fail "self-review.md 검사 항목 수가 5가 아님 (실제 $check_count) — 6번째 축 신설 금지"
ok "self-review.md 검사 항목 정확히 5개"
grep -qF '목적' "$SELF_REVIEW_MD" \
  || fail "self-review.md 5축 중 목적 섹션 점검 흡수 부재"
ok "self-review.md 목적 점검 흡수"

# ===========================================================================
echo ""
echo "=== 모든 spec 계약 + persona/clarity + 자연 인터뷰/옵트인 핸드오프 + 목적(WHY) 테스트 통과 ==="
