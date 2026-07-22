#!/usr/bin/env bash
# autopilot:create-task 스킬 — 등록-후 상태 전이 조건부화 정적 검증 테스트
#
# 계약: create-task 는 완성된 SPEC 본문을 생산한다. 본문에 미해결 마커
# ([NEEDS CLARIFICATION)가 없으면 초기 상태 backlog 를 유지하고, 남아 있으면
# in_design 으로 전이한다. 과거 무조건 in_design 전이는 제거되어야 한다.
# (SKILL.md 는 LLM 지침 산문이므로 동작을 정적 어구로 검증한다.)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/create-task/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$SKILL_MD" ]] || fail "SKILL.md 부재"

echo "=== TEST 1: 무조건 in_design 전이 어구 부재 (negative) ==="
# 과거 §7: "등록 후 ... set_status ... --status in_design 로 전이하고" (무조건)
if grep -qE '등록 후 .*set_status .*--status in_design.* 로 전이' "$SKILL_MD"; then
  fail "SKILL.md에 무조건 in_design 전이 어구가 잔존 (조건부화 위반)"
fi
ok "무조건 in_design 전이 어구 부재"

echo ""
echo "=== TEST 2: 마커 없음 → backlog 분기 명시 ==="
grep -qE '없으면.*backlog' "$SKILL_MD" \
  || fail "SKILL.md에 '마커 없으면 backlog 유지' 분기 없음"
ok "마커 없음 → backlog 분기 명시"

echo ""
echo "=== TEST 3: 마커 잔존 → in_design 분기 명시 ==="
grep -qE '(남아 있으면|있으면).*in_design' "$SKILL_MD" \
  || fail "SKILL.md에 '마커 남아 있으면 in_design 전이' 분기 없음"
ok "마커 잔존 → in_design 분기 명시"

echo ""
echo "=== TEST 4: 전이 분기가 [NEEDS CLARIFICATION 마커 기준임 ==="
grep -qF '[NEEDS CLARIFICATION' "$SKILL_MD" \
  || fail "SKILL.md에 [NEEDS CLARIFICATION 마커 기준 없음"
ok "[NEEDS CLARIFICATION 마커 기준 명시"

echo ""
echo "=== TEST 5: 상태 전이 이중 허용 문구 부재 (negative) ==="
# 과거 §5: "전이를 생략하거나 명시적으로 set_status ... --status backlog 를 호출한다"
# 두 갈래 허용은 세션마다 다른 동사 시퀀스를 만든다 — 단일 행동만 지시해야 한다.
if grep -qE '생략하거나' "$SKILL_MD"; then
  fail "SKILL.md에 전이 이중 허용 문구('…생략하거나…')가 잔존"
fi
# 등록-후 전이(5단계) 블록 한정 — resume 경로의 in_design → backlog 전이는 정당하므로 제외한다.
STEP5=$(awk '/^5\. \*\*등록-후 상태 전이/{flag=1} /^6\. \*\*본문 갱신/{flag=0} flag' "$SKILL_MD")
[[ -n "$STEP5" ]] || fail "SKILL.md에서 등록-후 상태 전이(5단계) 블록을 찾지 못함"
if grep -qE 'set_status .*--status backlog' <<<"$STEP5"; then
  fail "SKILL.md 5단계에 backlog 유지 분기의 중복 set_status 호출 지시가 잔존"
fi
ok "상태 전이 이중 허용 문구 부재"

echo ""
echo "=== TEST 9: description이 WHEN(트리거 표현) 중심 (#560 컨벤션) ==="
DESC="$(grep -m1 '^description:' "$SKILL_MD")"
BODY="$(awk 'NR>1 && /^---$/{f=1;next} f' "$SKILL_MD")"
echo "$DESC" | grep -qE '등록해줘|백로그에 올려|태스크 만들어줘' \
  || fail "description에 사용자 직접 등록 요청 표현(트리거 동의어)이 없음"
ok "description: 직접 등록 요청 트리거 표현 포함"

echo ""
echo "=== TEST 9: description에 소유권·경계 상세 서술 부재 (본문 소관) ==="
if echo "$DESC" | grep -qE '작성 로직|set_body'; then
  fail "description에 경계 상세 서술(작성 로직/set_body 위임)이 잔존 — 본문으로 이동해야 함"
fi
ok "description: 경계 상세 서술 부재"

echo ""
echo "=== TEST 9: 옮겨진 경계 서술이 본문에 보존됨 (정보 손실 없음) ==="
echo "$BODY" | grep -q 'set_body' \
  || fail "본문에 set_body 위임 서술이 없음"
echo "$BODY" | grep -qE '작성.*(feature|fix).*소유|소유.*작성' \
  || fail "본문에 작성 소유권(feature/fix) 서술이 없음"
ok "본문: 경계 서술 보존"

echo ""
echo "=== TEST 9: description에 오발동 방지 배제 조항 존재 (작성 신호는 feature·fix) ==="
echo "$DESC" | grep -qE '(feature.*fix).*(먼저|아니)' \
  || fail "description에 작성 신호는 feature·fix가 먼저라는 배제 조항이 없음"
ok "description: 배제 조항 존재"

echo ""
echo "=== TEST 10: 본문 CLAUDE_PLUGIN_ROOT 참조는 전부 env 폴백 형태 (벤더 독립) ==="
FM="$(awk 'NR==1{next} /^---$/{exit} {print}' "$SKILL_MD")"
# 폴백 없는 단독 확장 형태 ${CLAUDE_PLUGIN_ROOT} (\":-\" 폴백 미포함)만 결함 — 폴백 규칙을 설명하는 산문 언급은 허용
bare="$(echo "$BODY" | grep -nF '${CLAUDE_PLUGIN_ROOT}' || true)"
[[ -z "$bare" ]] \
  || fail "본문에 폴백 없는 단독 \${CLAUDE_PLUGIN_ROOT} 참조 잔존: $bare"
echo "$BODY" | grep -q 'CLAUDE_PLUGIN_ROOT:-' \
  || fail "본문에 CLAUDE_PLUGIN_ROOT env 폴백 형태 참조가 하나도 없음 (경로 해석 서술 소실)"
ok "본문 CLAUDE_PLUGIN_ROOT: 전부 폴백 형태"

echo ""
echo "=== TEST 11: 본문 산문에 Claude 전용 도구명 부재 (벤더 중립) ==="
hits="$(echo "$BODY" | grep -nE 'TodoWrite|AskUserQuestion' || true)"
[[ -z "$hits" ]] \
  || fail "본문 산문에 Claude 전용 도구명 잔존: $hits"
ok "본문 산문: TodoWrite/AskUserQuestion 부재"

echo ""
echo "=== TEST 12: 벤더 중립 기능 서술 + 기능 부재 폴백 존재 ==="
echo "$BODY" | grep -q '구조화된 사용자 질문' \
  || fail "본문에 '구조화된 사용자 질문' 기능 서술 없음"
echo "$BODY" | grep -qE '체크리스트|todo' \
  || fail "본문에 체크리스트(todo) 기능 서술 없음"
echo "$BODY" | grep -qE '직접 질문' \
  || fail "본문에 기능 부재 런타임 폴백(직접 질문) 서술 없음"
ok "벤더 중립 기능 서술 + 폴백 존재"

echo ""
echo "=== TEST 13: frontmatter allowed-tools 유지 (AskUserQuestion 항목 보존) ==="
echo "$FM" | grep -q 'AskUserQuestion' \
  || fail "frontmatter에서 AskUserQuestion 항목이 제거됨 (유지 대상)"
echo "$FM" | grep -q 'allowed-tools' \
  || fail "frontmatter allowed-tools 블록 소실"
ok "frontmatter allowed-tools 유지"

echo ""
echo "=== 모든 create-task 등록-후 상태 전이 조건부화 테스트 통과 ==="
