#!/usr/bin/env bash
# autopilot:spec 스킬 — task 상태 전이 단계 정적 검증 테스트
#
# SPEC: spec 워크플로우(일반·--resume)가 사전 검사 통과 직후 task-id로
# 식별되는 외부 task의 상태를 설계 상태로 정합(reconcile)하는지 검사.
#
# 검사는 SKILL.md(+ references)에 4갈래 분기·abort·양 모드 적용·사용자
# 안내·백킹 시스템 매핑이 명시되었는지 grep으로 정적 확인한다.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/spec"
SKILL_MD="$SKILL_DIR/SKILL.md"

[[ -f "$SKILL_MD" ]] || { echo "FAIL: SKILL.md 부재"; exit 1; }

echo "=== TEST 1: SKILL.md에 task 상태 정합 단계 헤더 존재 ==="
# 새 단계 헤더 (정합/전이/reconcile 중 어느 표현이든 허용; '상태' + '정합|전이|reconcile')
grep -qE '^###? .*(상태 정합|상태 전이|status reconcil|status transition)' "$SKILL_MD" \
  || { echo "FAIL: SKILL.md에 'task 상태 정합/전이' 단계 헤더 부재"; exit 1; }
echo "OK: 단계 헤더"

echo ""
echo "=== TEST 2: SKILL.md에 사전 검사 통과 직후 실행 명시 ==="
# "사전 검사 통과 직후" 또는 "preflight 직후" 같은 표현으로 위치 명시
grep -qE '사전 검사 (통과 )?직후|preflight (통과 )?직후|after preflight' "$SKILL_MD" \
  || { echo "FAIL: 사전 검사 통과 직후 실행 위치 명시 없음"; exit 1; }
echo "OK: 사전 검사 직후 실행"

echo ""
echo "=== TEST 3: SKILL.md에 4갈래 분기 모두 명시 ==="
# (a) task 부재 → 새 task 생성
grep -qE '부재|없으면|존재하지 않|absent' "$SKILL_MD" \
  || { echo "FAIL: (a) task 부재 분기 명시 없음"; exit 1; }
echo "OK: (a) 부재 분기"

# (b) 설계 상태(In Design) → 변경 없음 / 그대로
grep -qE '설계 상태|In Design' "$SKILL_MD" \
  || { echo "FAIL: (b) 설계 상태(In Design) 분기 명시 없음"; exit 1; }
echo "OK: (b) 설계 상태 분기"

# (c) 설계 이전 상태(Backlog) → 설계 상태로 전이
grep -qE '설계 이전|Backlog' "$SKILL_MD" \
  || { echo "FAIL: (c) 설계 이전(Backlog) 분기 명시 없음"; exit 1; }
echo "OK: (c) 설계 이전 분기"

# (d) 설계 이후 상태 → 새 task 생성
grep -qE '설계 이후|In Progress|Review|Done' "$SKILL_MD" \
  || { echo "FAIL: (d) 설계 이후 분기 명시 없음"; exit 1; }
echo "OK: (d) 설계 이후 분기"

echo ""
echo "=== TEST 4: SKILL.md에 task-id 교체 + 사용자 안내 명시 ==="
grep -qE '교체|새 task-id|새 task의 식별자' "$SKILL_MD" \
  || { echo "FAIL: task-id 교체 명시 없음"; exit 1; }
echo "OK: task-id 교체"
grep -qE '사용자에게.*안내|새 task-id를.*안내|AskUserQuestion.*새 task' "$SKILL_MD" \
  || { echo "FAIL: 사용자에게 새 task-id 안내 명시 없음"; exit 1; }
echo "OK: 사용자 안내"

echo ""
echo "=== TEST 5: SKILL.md에 호출 실패 시 abort 명시 ==="
# 조회·생성·전이 호출 중 하나라도 실패하면 abort
grep -qE '실패.*abort|abort.*실패|호출 실패' "$SKILL_MD" \
  || { echo "FAIL: 호출 실패 시 abort 동작 명시 없음"; exit 1; }
echo "OK: 실패 시 abort"

echo ""
echo "=== TEST 6: SKILL.md에 일반 모드·--resume 모드 모두 적용 명시 ==="
# 새 단계가 양 모드에 적용된다는 명시 (--resume 모드 요약 섹션에 본 단계 언급)
# 단계 헤더부터 끝까지 추출해 일반·--resume 두 키워드 동시 등장 확인
grep -qE -- '일반 모드.*--?resume|--?resume.*일반 모드|일반·--?resume|두 모드' "$SKILL_MD" \
  || { echo "FAIL: 일반/--resume 두 모드 적용 명시 없음"; exit 1; }
echo "OK: 양 모드 적용"

echo ""
echo "=== TEST 7: SKILL.md에 백킹 시스템(GitHub Project/Issue) 매핑 명시 ==="
# rules/context.md 어휘에 정렬: Issue + Project Status field
grep -qE 'GitHub (Project|Issue)|gh (issue|project)' "$SKILL_MD" \
  || { echo "FAIL: GitHub Project/Issue 백킹 시스템 매핑 명시 없음"; exit 1; }
echo "OK: 백킹 시스템 매핑"

echo ""
echo "=== TEST 8: SKILL.md allowed-tools에 task 상태 전이용 gh 명령 추가 ==="
ALLOWED_LINE=$(grep -m1 '^allowed-tools:' "$SKILL_MD" || true)
[[ -n "$ALLOWED_LINE" ]] || { echo "FAIL: allowed-tools 라인 없음"; exit 1; }
# 신규 task 생성 + 상태 전이 호출에 필요한 gh 명령
echo "$ALLOWED_LINE" | grep -q 'gh issue create' \
  || { echo "FAIL: allowed-tools에 'gh issue create' 없음"; exit 1; }
echo "OK: gh issue create"
echo "$ALLOWED_LINE" | grep -qE 'gh project (item-list|item-edit|item-add)' \
  || { echo "FAIL: allowed-tools에 'gh project item-*' 없음"; exit 1; }
echo "OK: gh project item-*"

echo ""
echo "=== TEST 9: SKILL.md 워크플로 번호가 새 단계 반영 ==="
# 단계 추가 후 워크플로 헤더 번호가 10으로 갱신됐는지 (main의 9단계 + 단계 2 task 상태 정합)
grep -qE '^## 10단계 워크플로|^## 10-step|총 10단계' "$SKILL_MD" \
  || { echo "FAIL: 워크플로 헤더가 10단계로 갱신되지 않음"; exit 1; }
echo "OK: 10단계 헤더"

echo ""
echo "=== TEST 10: SKILL.md (a)·(d) 새 issue 생성 시 title/body 수집 절차 명시 ==="
# PR #96 review (claude[bot]): step 2 (a)/(d) gh issue create title/body 명시 부재.
# 모델이 임의 값으로 채우는 것을 방지하기 위해 title은 AskUserQuestion 1문항 + task-id fallback,
# body는 고정 placeholder임을 명시해야 한다.
grep -qE 'title.*AskUserQuestion|AskUserQuestion.*title|한 줄 제목.*수집' "$SKILL_MD" \
  || { echo "FAIL: (a)/(d) title 수집 절차(AskUserQuestion) 명시 없음"; exit 1; }
echo "OK: title 수집 절차"
grep -qE 'task-id.*fallback|fallback.*task-id|task-id 문자열.*fallback' "$SKILL_MD" \
  || { echo "FAIL: title fallback (task-id 사용) 명시 없음"; exit 1; }
echo "OK: title fallback"
grep -qE 'body.*최소|최소 본문|body.*고정|placeholder' "$SKILL_MD" \
  || { echo "FAIL: body 최소/고정 placeholder 명시 없음"; exit 1; }
echo "OK: body 최소/고정"

echo ""
echo "=== TEST 11: SKILL.md <new-task-id> 플레이스홀더 치환 절차 명시 ==="
# PR #96 review NIT (claude[bot]): body의 <new-task-id> placeholder가 issue 생성 전엔
# 값이 없으므로 create 후 즉시 edit으로 치환하는 절차를 명시해야 한다.
grep -qE 'gh issue edit.*body|edit.*치환|치환.*edit|반환된 issue number.*edit' "$SKILL_MD" \
  || { echo "FAIL: <new-task-id> 치환 절차(create 후 edit) 명시 없음"; exit 1; }
echo "OK: create 후 edit 치환 절차"
# allowed-tools에 gh issue edit 추가
grep -m1 '^allowed-tools:' "$SKILL_MD" | grep -q 'gh issue edit' \
  || { echo "FAIL: allowed-tools에 'gh issue edit' 없음"; exit 1; }
echo "OK: allowed-tools에 gh issue edit"

echo ""
echo "=== 모든 spec 상태 전이 테스트 통과 ==="
