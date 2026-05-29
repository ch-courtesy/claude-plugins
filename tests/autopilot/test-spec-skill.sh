#!/usr/bin/env bash
# autopilot:spec 스킬 계약 검증 테스트 (경량 redesign + persona/clarity 가산)
#
# 정합 갱신: 과거 본 테스트는 제거된 기능(검증실패 라우팅 a/b/c·자연어 트리거·
# 사전 명확화 라운드·마일스톤/PRD 라우팅·단일 task 생성·test_sweep_paths·
# 10단계 워크플로)을 검증하는 stale assert 를 담고 있었다. 경량 spec 스킬은
# 외부 상태(task·이슈·브랜치·원격)를 만들지 않고 SPEC 문서만 작성하는 8단계
# 워크플로다. 본 테스트는 stale assert 를 현 경량 계약으로 정정한 뒤, 신규
# persona 적대 리뷰 + clarity 점수 기능 검증 assert 를 가산한다.
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

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$SKILL_MD" ]] || fail "SKILL.md 부재: $SKILL_MD"

# ===========================================================================
# PART A — 현 경량 계약 정합 검증
# ===========================================================================

echo "=== TEST A1: 외부 상태 미생성 경량 계약 ==="
# 경량 redesign: 산출물은 SPEC 문서뿐. task·이슈·브랜치·원격 미생성.
grep -qE '외부 상태.*(만들지 않|미생성|않는다)' "$SKILL_MD" \
  || fail "SKILL.md에 '외부 상태 미생성' 계약 명시 없음"
ok "외부 상태 미생성 계약 명시"
# stale 기능 잔존 금지 (negative): 검증 실패 라우팅·PRD·milestone-id·test_sweep_paths
for stale in '검증 실패 라우팅' 'milestone-id' 'test_sweep_paths' '마일스톤 규모'; do
  if grep -qF "$stale" "$SKILL_MD"; then
    fail "SKILL.md에 제거된 기능 어구 '$stale' 잔존 (경량 계약 위반)"
  fi
done
ok "제거된 기능 어구(라우팅·milestone-id·test_sweep_paths 등) 잔존 없음"

echo ""
echo "=== TEST A2: 8단계 워크플로 + 핵심 step 보존 ==="
for step_kw in '컨텍스트 탐색' '범위 분해 게이트' '명확화 라운드' '접근법 비교' '섹션별 SPEC' 'SPEC 문서 작성' '자체 검토' '구현 스킬 추천'; do
  grep -qF "$step_kw" "$SKILL_MD" \
    || fail "8단계 step 키워드 '$step_kw' 보존 실패"
done
ok "8단계 step 키워드 모두 존재"
grep -qF 'WHAT/HOW' "$SKILL_MD" || fail "WHAT/HOW 방어선 명시 보존 실패"
ok "WHAT/HOW 방어선 보존"

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
echo "=== TEST A5: agent-prompts.md 단계 번호 오기 정정 (실제 8단계와 일치) ==="
# 경량 스킬은 8단계다. 과거 양식의 '10-step'·context=step3·self-review=step9 오기를 정정.
if grep -qE '10[- ]?step|10단계' "$AGENT_PROMPTS"; then
  fail "agent-prompts.md에 stale '10-step/10단계' 잔존 (실제 8단계)"
fi
ok "agent-prompts.md에 stale 10-step 잔존 없음"
grep -qE '8[- ]?step|8단계' "$AGENT_PROMPTS" \
  || fail "agent-prompts.md에 정정된 '8-step/8단계' 표기 부재"
ok "8-step 표기 존재"
# context-explorer 는 step 1, self-reviewer 는 step 7 을 가리켜야 한다.
grep -qE 'step 1 컨텍스트 탐색|step 1 .*컨텍스트' "$AGENT_PROMPTS" \
  || fail "context-explorer 언제 절이 step 1(컨텍스트 탐색)을 가리키지 않음"
ok "context-explorer → step 1"
grep -qE 'step 7 자체 검토|step 7 .*자체 검토' "$AGENT_PROMPTS" \
  || fail "self-reviewer 언제 절이 step 7(자체 검토)을 가리키지 않음"
ok "self-reviewer → step 7"

echo ""
echo "=== TEST A6: 모듈 구성 표 + 헌법 §11.6 + 결정·합성 메인 책임 ==="
grep -qE '§11\.6|이터 내 서브 도구 위임' "$SKILL_MD" \
  || fail "SKILL.md에 헌법 §11.6 / '이터 내 서브 도구 위임' 인용 부재"
ok "§11.6 인용 존재"
grep -qE '결정·합성.*메인|메인.*결정·합성|결정과 합성.*메인|결정.*합성은 메인' "$SKILL_MD" \
  || fail "SKILL.md에 '결정·합성은 메인 책임' 문구 부재"
ok "결정·합성 메인 책임 문구 존재"

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
echo "=== TEST B4: SKILL.md step 7 적대 렌즈 + 메인 반영 ==="
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
echo "=== TEST C5: SKILL.md step 3 명확화 종결에 clarity 리드아웃·소프트 권고 ==="
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
echo ""
echo "=== 모든 spec 계약 + persona/clarity 테스트 통과 ==="
