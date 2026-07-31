#!/usr/bin/env bash
# roundtable 스킬 패키지와 핵심 회의 계약 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_DIR="$REPO_ROOT/plugins/thinktank"
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
[[ ! -e "$PLUGIN_DIR/skills/shared" ]] \
  || fail "구 공유 디렉터리 잔존: skills/shared/"
if grep -rq 'shared/session-conventions' "$PLUGIN_DIR" || grep -rqF '../shared/' "$PLUGIN_DIR"; then
  fail "구 공유 규약 참조 잔존"
fi
ok "필수 파일 존재 + 공유 디렉터리·참조 부재"

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
grep -qF '.roundtable/<meeting-id>.md' "$SKILL_MD" \
  || fail "단일 회의 파일 계약 누락"
grep -qE 'resume 라우팅|재개 라우팅' "$SKILL_MD" \
  || fail "상태별 resume 라우팅 누락"
grep -qE 'status 보고|상태 보고' "$SKILL_MD" \
  || fail "읽기 전용 status 보고 형식 누락"
grep -qF 'YYYYMMDD-<slug>' "$SKILL_MD" \
  || fail "회의 ID 규칙 인라인 누락"
grep -qE '인자가 없으면.*start' "$SKILL_MD" \
  || fail "무인자 start 기본 규약 인라인 누락"
ok "인터페이스와 상태 계약"

echo ""
echo "=== TEST 3: 메인 세션 책임과 승인 게이트 ==="
FRONTMATTER="$(awk '/^---$/{n++; next} n==1' "$SKILL_MD")"
printf '%s\n' "$FRONTMATTER" | grep -qxF '  - Write(.roundtable/**)' \
  || fail "Write 권한이 .roundtable/**로 제한되지 않음"
if printf '%s\n' "$FRONTMATTER" | grep -qxF '  - Write'; then
  fail "제한 없는 Write 권한이 남아 있음"
fi
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
grep -qE '자기완결' "$SKILL_MD" \
  || fail "자기완결 brief 규범 인라인 누락"
grep -qE '중첩 Agent.*(않|금지)' "$SKILL_MD" \
  || fail "중첩 Agent 금지 규범 인라인 누락"
grep -qE '민감 정보.*(넣지 않|금지)' "$SKILL_MD" \
  || fail "민감 정보 안전 경계 인라인 누락"
ok "책임 분리와 승인 게이트"

echo ""
echo "=== TEST 4: 중앙 리서치와 토큰 중복 방지 ==="
for token in '공통 증거 팩' '중앙 리서처' '리서치 계획' '증거 팩' ; do
  grep -q "$token" "$REFS/research-protocol.md" \
    || fail "리서치 프로토콜 토큰 누락: $token"
done
grep -qE '회의 책임자.*리서치 계획|리서치 계획.*회의 책임자' "$REFS/research-protocol.md" \
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
grep -qE '불합의 보고서.*정상|정상.*불합의 보고서' "$REFS/meeting-protocol.md" \
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
echo "=== TEST 7: 단일 회의 파일 계약 ==="
grep -qF '.roundtable/<meeting-id>.md' "$REFS/document-templates.md" \
  || fail "단일 회의 파일 템플릿 누락"
grep -q '## 상태' "$REFS/document-templates.md" \
  || fail "상태 블록 섹션 누락"
for field in 'status' 'next-action'; do
  grep -q "$field" "$REFS/document-templates.md" \
    || fail "상태 블록 필드 누락: $field"
done
if grep -qE 'meeting_id|next_action|current_round|max_rounds|(research|agent)_calls_used|last_updated' "$REFS/document-templates.md"; then
  fail "상태 블록 snake_case 필드 잔존 (kebab-case 통일 필요)"
fi
for section in '아젠다' '리서치 계획' '증거 팩' '로스터' '초기 입장' '결정 지도' '논의 기록' '최종 문서'; do
  grep -q "## ${section}" "$REFS/document-templates.md" \
    || fail "회의 파일 섹션 누락: $section"
done
grep -qE '합의·실행서.*불합의 보고서|불합의 보고서.*합의·실행서' "$REFS/document-templates.md" \
  || fail "최종 문서 이분 계약(합의·실행서/불합의 보고서) 누락"
grep -qE '상태 블록.*먼저 갱신' "$SKILL_MD" \
  || fail "상태 블록 우선 갱신 계약 누락"
grep -qE '섹션 단위로만.*(추가|갱신)' "$SKILL_MD" \
  || fail "섹션 단위 추가·갱신 계약 누락"
grep -qE '전체 파일 재작성.*(금지|않는다)' "$SKILL_MD" \
  || fail "전체 파일 재작성 금지 계약 누락"
grep -qE '(resume|재개).*단일 (세션|회의) 파일|단일 (세션|회의) 파일.*(resume|재개)' "$SKILL_MD" \
  || fail "resume 단일 파일 읽기 계약 누락"
grep -qE '초기 입장.*다시 생성하지 않|초기 입장.*재생성.*않' "$SKILL_MD" \
  || fail "초기 입장 재생성 금지 계약 누락"
grep -qE '실제.*실행.*(범위 밖|수행하지 않)|합의 내용.*실행하지 않' "$SKILL_MD" \
  || fail "합의 이후 자동 실행 금지 누락"
ok "단일 회의 파일 계약과 실행 경계"

echo ""
echo "=== TEST 8: 구 다중 파일 계약 부재 ==="
if grep -rqF '.roundtable/<meeting-id>/' "$SKILL_DIR"; then
  fail "구 디렉터리 계약 잔존: .roundtable/<meeting-id>/"
fi
for artifact in state.md agenda.md research-plan.md evidence-pack.md roster.md initial-positions.md decision-map.md discussion.md agreement.md no-consensus.md; do
  if grep -rqF "$artifact" "$SKILL_DIR"; then
    fail "구 산출물 파일명 잔존: $artifact"
  fi
done
ok "구 다중 파일 계약 부재"

echo ""
echo "=== TEST 9: 마켓플레이스 등록 ==="
grep -q '"name": "thinktank"' "$MARKETPLACE" \
  || fail "마켓플레이스에 thinktank 미등록"
ok "마켓플레이스 등록"

echo ""
echo "=== TEST 10: 숙의 강화 계약 (상호 반박·반대 강제·증거 임계치·brief 규범) ==="
grep -qF '반박 → 재반박 1왕복' "$REFS/meeting-protocol.md" \
  || fail "상호 반박 왕복 계약 누락"
grep -qF '반대 강제' "$REFS/meeting-protocol.md" \
  || fail "반대 강제 계약 누락"
grep -qF '가장 강한 반대 논거' "$REFS/meeting-protocol.md" \
  || fail "최강 반대 논거 요구 누락"
grep -qF '독립인 출처 2개 이상' "$REFS/research-protocol.md" \
  || fail "핵심 주장 독립 출처 임계치 누락"
grep -qF '반증 시도 결과' "$REFS/research-protocol.md" \
  || fail "반증 시도 기록 요구 누락"
grep -qF '메인 세션 컨텍스트는 보이지 않는다' "$REFS/role-prompts.md" \
  || fail "brief 메인 컨텍스트 비가시성 명시 누락 (role-prompts)"
grep -qF '중첩 Agent를 호출하지 않는다' "$REFS/role-prompts.md" \
  || fail "brief 중첩 Agent 금지 명시 누락 (role-prompts)"
grep -qF '메인 컨텍스트는 보이지 않는다' "$REFS/participant-personas.md" \
  || fail "brief 메인 컨텍스트 비가시성 명시 누락 (participant-personas)"
ok "숙의 강화 계약"

echo ""
echo "=== 모든 roundtable 스킬 테스트 통과 ==="
