#!/usr/bin/env bash
# roundtable 스킬 패키지와 핵심 회의 계약 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_DIR="$REPO_ROOT/plugins/roundtable"
SKILL_DIR="$PLUGIN_DIR/skills/roundtable"
SKILL_MD="$SKILL_DIR/SKILL.md"
REFS="$SKILL_DIR/references"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

echo "=== TEST 1: 플러그인 구조 ==="
for file in \
  "$PLUGIN_DIR/.claude-plugin/plugin.json" \
  "$SKILL_MD" \
  "$REFS/agenda-template.md" \
  "$REFS/research-protocol.md" \
  "$REFS/meeting-protocol.md" \
  "$REFS/role-prompts.md" \
  "$REFS/participant-personas.md" \
  "$REFS/document-templates.md"; do
  [[ -f "$file" ]] || fail "필수 파일 부재: $file"
done
ok "필수 파일 존재"

echo ""
echo "=== TEST 2: 공개 인터페이스와 상태 ==="
for command in start resume status; do
  grep -qE "roundtable ${command}|### ${command}" "$SKILL_MD" \
    || fail "서브커맨드 누락: $command"
done
for state in interviewing agenda_approval researching research_review roster_approval discussing documenting completed no_consensus; do
  grep -q "$state" "$SKILL_MD" \
    || fail "상태 누락: $state"
done
grep -qF '.roundtable/<meeting-id>/' "$SKILL_MD" \
  || fail "회의 산출물 루트 계약 누락"
grep -qE 'resume 라우팅|재개 라우팅' "$SKILL_MD" \
  || fail "상태별 resume 라우팅 누락"
grep -qE 'status 보고|상태 보고' "$SKILL_MD" \
  || fail "읽기 전용 status 보고 형식 누락"
ok "인터페이스와 상태 계약"

echo ""
echo "=== TEST 3: 메인 세션 책임과 승인 게이트 ==="
grep -qE '메인 세션.*회의 책임자|회의 책임자.*메인 세션' "$SKILL_MD" \
  || fail "메인 세션=회의 책임자 계약 누락"
grep -qE '아젠다.*승인|승인.*아젠다' "$SKILL_MD" \
  || fail "아젠다 승인 게이트 누락"
grep -qE 'roster|참여자 구성' "$SKILL_MD" \
  || fail "참여자 구성 승인 계약 누락"
grep -qE '진행자.*지휘|진행자.*판정' "$SKILL_MD" \
  || fail "진행자 지휘 계약 누락"
grep -qE '메인.*(호출|디스패치)|디스패치.*메인' "$SKILL_MD" \
  || fail "메인 디스패치 계약 누락"
ok "책임 분리와 승인 게이트"

echo ""
echo "=== TEST 4: 중앙 리서치와 토큰 중복 방지 ==="
for token in '공통 증거 팩' '중앙 리서처' 'research-plan.md' 'evidence-pack.md'; do
  grep -q "$token" "$REFS/research-protocol.md" \
    || fail "리서치 프로토콜 토큰 누락: $token"
done
grep -qE '회의 책임자.*research-plan.md|research-plan.md.*회의 책임자' "$REFS/research-protocol.md" \
  || fail "회의 책임자의 리서치 계획 책임 누락"
grep -qE '전체 증거 팩.*반복.*(전달|주입).*않|관련.*증거.*배포' "$REFS/research-protocol.md" \
  || fail "관련 증거만 배포하는 중복 방지 계약 누락"
grep -qE '추가 조사.*(통합|중복 제거)|중복.*추가 조사' "$REFS/research-protocol.md" \
  || fail "추가 조사 요청 통합·중복 제거 계약 누락"
grep -qE '사실.*해석.*(가정|추정)|확인 상태' "$REFS/research-protocol.md" \
  || fail "사실·해석·가정 구분 계약 누락"
ok "중앙 리서치 계약"

echo ""
echo "=== TEST 5: 숙의 품질과 종료 안전성 ==="
grep -qE '독립.*초기 입장|초기 입장.*독립' "$REFS/meeting-protocol.md" \
  || fail "독립 초기 입장 계약 누락"
grep -qE '입장을 바꿀 조건|변경 조건' "$REFS/meeting-protocol.md" \
  || fail "입장 변경 조건 계약 누락"
grep -qE '수용.*조건부 수용.*중대한 반대.*판단 불가' "$REFS/meeting-protocol.md" \
  || fail "합의 후보 평가 상태 누락"
grep -qE '거짓 합의|합의되지 않은.*합의' "$REFS/meeting-protocol.md" \
  || fail "거짓 합의 금지 계약 누락"
grep -q 'no-consensus.md' "$REFS/meeting-protocol.md" \
  || fail "불합의 정상 종료 계약 누락"
ok "숙의와 종료 계약"

echo ""
echo "=== TEST 6: 역할·페르소나 카탈로그 ==="
for role in '회의 책임자' '중앙 리서처' '리서치 검증자' '진행자' '기록자'; do
  grep -q "$role" "$REFS/role-prompts.md" \
    || fail "운영 역할 누락: $role"
done
for persona in '문제 소유자' '현장 실무자' '사용자·고객 대변인' '창의적 탐색자' '비판적 검증자' '실행 가능성 검토자' '데이터·근거 분석가' '도메인 전문가' '위험·법무·컴플라이언스 검토자' '반대 관점 대변인' '의사결정 관점 대변인'; do
  grep -q "$persona" "$REFS/participant-personas.md" \
    || fail "참여자 페르소나 누락: $persona"
done
for field in '대표 관점' '보호할 가치' '검증할 가정' '관련 증거' '금지 행동' '응답 형식'; do
  grep -q "$field" "$REFS/participant-personas.md" \
    || fail "참여자 brief 필드 누락: $field"
done
ok "운영 역할과 참여자 페르소나"

echo ""
echo "=== TEST 7: 문서 산출물 계약 ==="
for artifact in state.md agenda.md research-plan.md evidence-pack.md roster.md initial-positions.md decision-map.md discussion.md agreement.md no-consensus.md; do
  grep -q "$artifact" "$REFS/document-templates.md" "$SKILL_MD" \
    || fail "산출물 계약 누락: $artifact"
done
grep -qE '실제.*실행.*(범위 밖|수행하지 않)|합의 내용.*실행하지 않' "$SKILL_MD" \
  || fail "합의 이후 자동 실행 금지 누락"
ok "문서 산출물과 실행 경계"

echo ""
echo "=== TEST 8: 마켓플레이스 등록 ==="
grep -q '"name": "roundtable"' "$MARKETPLACE" \
  || fail "마켓플레이스에 roundtable 미등록"
ok "마켓플레이스 등록"

echo ""
echo "=== 모든 roundtable 스킬 테스트 통과 ==="
