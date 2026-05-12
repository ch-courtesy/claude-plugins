#!/usr/bin/env bash
# autopilot:spec 스킬 검증 실패 라우팅 검증 테스트
#
# SPEC.md (#65 작업) 수용 기준 1·2·4·5·6·7·8·9·10에 대응하는 assertion 집합.
# 본 테스트는 SKILL.md가 검증 실패 분기 라우팅을 명시적으로 기술하는지를 정적
# 검사로 확인한다. 실제 사용자 인터랙션·외부 도구 호출은 e2e 범위 밖.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/spec"
SKILL_MD="$SKILL_DIR/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$SKILL_MD" ]] || fail "SKILL.md 부재: $SKILL_MD"

# ---------------------------------------------------------------------------
echo "=== TEST 1: 검증 실패 라우팅 섹션 존재 ==="
# 수용 기준 1·9: 라우팅 옵션 (a)/(b)/(c)를 모두 명시
grep -qE '검증 실패.*(라우팅|분기|routing)' "$SKILL_MD" \
  || fail "SKILL.md에 '검증 실패 라우팅/분기' 섹션 명시 없음"
ok "검증 실패 라우팅/분기 섹션 헤더 존재"

# 라우팅 옵션 (a)/(b)/(c) 모두 명시 — 본문 흐름에서 (a) … (b) … (c) 패턴
for opt_label in '\(a\)' '\(b\)' '\(c\)'; do
  grep -q "$opt_label" "$SKILL_MD" \
    || fail "SKILL.md에 라우팅 옵션 $opt_label 표기 없음"
done
ok "라우팅 옵션 (a)/(b)/(c) 모두 명시"

# 각 옵션 의미가 본문에 보이는지 키워드 검사 (수용 기준 1)
grep -qE '재입력|다시 입력|재시도' "$SKILL_MD" \
  || fail "옵션 (a) 의미(재입력·재시도) 명시 없음"
ok "옵션 (a) 의미(task-id 재입력·재시도) 명시"

grep -qE '사전 명확화 라운드' "$SKILL_MD" \
  || fail "옵션 (b) '사전 명확화 라운드' 키워드 없음"
ok "옵션 (b) '사전 명확화 라운드' 명시"

grep -qE '종료|abort|중단' "$SKILL_MD" \
  || fail "옵션 (c) 종료·abort 의미 명시 없음"
ok "옵션 (c) 종료 의미 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 2: 자연어 입력 감지 트리거 ==="
# 수용 기준 2: 자연어 문장으로 보이는 입력 = 검증 실패 트리거
grep -qE '자연어|natural language|문장으로 보이' "$SKILL_MD" \
  || fail "SKILL.md에 '자연어 입력' 검증 실패 트리거 명시 없음"
ok "자연어 입력 트리거 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 3: 사전 명확화 라운드 = step 4 메커니즘 앞당김 ==="
# 수용 기준 4·제약: 별도 phase 신설 없이 기존 step 4 메커니즘 재사용
grep -qE 'step 4|단계 4|명확화 라운드.*앞당김|앞당겨' "$SKILL_MD" \
  || fail "SKILL.md에 step 4 앞당김 명시 없음"
ok "step 4 메커니즘 앞당김 명시"

# 한 번에 한 AskUserQuestion 규칙 재사용 — 본문에 명시되어야 함
grep -qE '한 번에 한 (질문|AskUserQuestion)' "$SKILL_MD" \
  || fail "SKILL.md에 '한 번에 한 질문/AskUserQuestion' 규칙 명시 없음"
ok "'한 번에 한 질문' 규칙 명시"

# 수집할 정보: 문제·목표·범위·제약 (수용 기준 4)
for token in '문제' '목표' '범위' '제약'; do
  grep -q "$token" "$SKILL_MD" \
    || fail "사전 명확화 수집 항목 '$token' 명시 없음"
done
ok "수집 항목 (문제·목표·범위·제약) 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 4: 단일 task 경로 — 프로젝트 태스크 관련 지침 ==="
# 수용 기준 5: 단일 task 수렴 시 프로젝트의 태스크 관련 지침에 따라 task 생성
grep -qE '단일 task|단일 규모|단일로 수렴' "$SKILL_MD" \
  || fail "SKILL.md에 '단일 task 수렴' 분기 명시 없음"
ok "단일 task 수렴 분기 명시"

grep -qE '프로젝트의? 태스크 관련 지침|태스크 관련 지침' "$SKILL_MD" \
  || fail "SKILL.md에 '프로젝트 태스크 관련 지침' 참조 없음"
ok "프로젝트 태스크 관련 지침 참조 명시"

# 수용 기준 5: task 생성 후 step 2 (컨텍스트 탐색)부터 재개
grep -qE 'step 2|단계 2|컨텍스트 탐색.*재개|재개.*(step|단계) ?2' "$SKILL_MD" \
  || fail "SKILL.md에 'step 2부터 재개' 흐름 명시 없음"
ok "task-id 확보 후 step 2 재개 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 5: 마일스톤 경로 — PRD 스킬 라우팅 ==="
# 수용 기준 6: 마일스톤 규모 수렴 시 PRD invoke 여부를 AskUserQuestion으로
grep -qE '마일스톤 규모|마일스톤으로 수렴|마일스톤 분해' "$SKILL_MD" \
  || fail "SKILL.md에 '마일스톤 규모 수렴' 분기 명시 없음"
ok "마일스톤 규모 분기 명시"

grep -qE '(PRD|prd) ?(스킬|skill)' "$SKILL_MD" \
  || fail "SKILL.md에 PRD 스킬 라우팅 명시 없음"
ok "PRD 스킬 라우팅 명시"

# 수용 기준 6·8: PRD 호출은 AskUserQuestion 명시적 승인 후
grep -qE '명시적 승인|승인.*invoke|AskUserQuestion.*PRD|PRD.*AskUserQuestion' "$SKILL_MD" \
  || fail "SKILL.md에 PRD invoke 전 AskUserQuestion 승인 흐름 명시 없음"
ok "PRD invoke 전 AskUserQuestion 승인 명시"

# 위험: PRD 스킬은 milestone-id 인자 필요 — spec이 받아 넘김
grep -qE 'milestone-id|milestone ?id' "$SKILL_MD" \
  || fail "SKILL.md에 PRD 호출 시 milestone-id 인자 전달 명시 없음"
ok "milestone-id 인자 전달 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 6: 산출물 안전성 (취소·종료 시) ==="
# 수용 기준 7·10: 종료·취소 시 SPEC.md/task 어느 것도 남기지 않음
grep -qE '취소|cancel' "$SKILL_MD" \
  || fail "SKILL.md에 '취소' 시나리오 명시 없음"
ok "사전 명확화 라운드 취소 시나리오 명시"

grep -qE '산출물.*(없이|않고|남기지)|어떠한 산출물도|작성하지 않' "$SKILL_MD" \
  || fail "SKILL.md에 '산출물 미작성/미생성' 안전 종료 명시 없음"
ok "취소·종료 시 산출물 미생성 안전 종료 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 7: AskUserQuestion 기반 스킬 체인 규칙 ==="
# 수용 기준 8: "다음 단계: Skill(...)" 자유 텍스트 안내 대신 AskUserQuestion 확인
grep -qE 'AskUserQuestion' "$SKILL_MD" \
  || fail "SKILL.md에 AskUserQuestion 도구 참조 없음"
ok "AskUserQuestion 도구 참조 존재"

# 후속 스킬 호출은 항상 AskUserQuestion 확인 후 invoke 규칙
grep -qE '후속 스킬 호출.*AskUserQuestion|AskUserQuestion.*invoke|AskUserQuestion.*확인 후' "$SKILL_MD" \
  || fail "SKILL.md에 '후속 스킬 호출 = AskUserQuestion 확인 후' 규칙 명시 없음"
ok "AskUserQuestion 기반 스킬 체인 규칙 명시"

# ---------------------------------------------------------------------------
echo ""
echo "=== TEST 8: 기존 워크플로 보존 ==="
# 검증 실패 분기 외 기존 1~9단계 흐름은 그대로 유지되어야 함 (SPEC scope.exclude)
grep -qE '9[- ]?(단계|step) 워크플로' "$SKILL_MD" \
  || fail "SKILL.md에 9단계 워크플로 헤더 보존 없음"
ok "9단계 워크플로 헤더 보존"

for step_kw in '컨텍스트 탐색' '범위 분해 게이트' '명확화 라운드' '섹션별 SPEC' '자체 검토' '사용자 최종 검토'; do
  grep -q "$step_kw" "$SKILL_MD" \
    || fail "기존 step 키워드 '$step_kw' 보존 실패"
done
ok "기존 step 키워드 보존"

# WHAT/HOW 방어선 보존
grep -q 'WHAT/HOW' "$SKILL_MD" \
  || fail "WHAT/HOW 방어선 명시 보존 실패"
ok "WHAT/HOW 방어선 보존"

# ---------------------------------------------------------------------------
echo ""
echo "=== 모든 spec 검증 실패 라우팅 테스트 통과 ==="
