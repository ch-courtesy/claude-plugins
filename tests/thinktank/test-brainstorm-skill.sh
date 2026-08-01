#!/usr/bin/env bash
# brainstorm 스킬 패키지와 핵심 발산·수렴·검증 계약 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_DIR="$REPO_ROOT/plugins/thinktank"
SKILL_DIR="$PLUGIN_DIR/skills/brainstorm"
SKILL_MD="$SKILL_DIR/SKILL.md"
REFS="$SKILL_DIR/references"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

echo "=== TEST 1: 스킬 구조 ==="
for file in \
  "$SKILL_MD" \
  "$REFS/framing-template.md" \
  "$REFS/strategy-protocols.md" \
  "$REFS/role-prompts.md" \
  "$REFS/research-protocol.md" \
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
  grep -qE "brainstorm ${command}|### ${command}" "$SKILL_MD" \
    || fail "서브커맨드 누락: $command"
done
for state in framing frame_approval minimal_research diverging transforming clustering converging validation_approval validating completed; do
  grep -q "$state" "$SKILL_MD" \
    || fail "상태 누락: $state"
done
grep -qF '.brainstorm/<session-id>.md' "$SKILL_MD" \
  || fail "단일 세션 파일 계약 누락"
grep -qE 'resume 라우팅|재개 라우팅' "$SKILL_MD" \
  || fail "상태별 resume 라우팅 누락"
grep -qE 'status 보고|상태 보고' "$SKILL_MD" \
  || fail "읽기 전용 status 보고 형식 누락"
grep -qF 'YYYYMMDD-<slug>' "$SKILL_MD" \
  || fail "세션 ID 규칙 인라인 누락"
grep -qE '인자가 없으면.*start' "$SKILL_MD" \
  || fail "무인자 start 기본 규약 인라인 누락"
ok "인터페이스와 상태 계약"

echo ""
echo "=== TEST 3: 세션 책임과 승인 게이트 ==="
FRONTMATTER="$(awk '/^---$/{n++; next} n==1' "$SKILL_MD")"
printf '%s\n' "$FRONTMATTER" | grep -qxF '  - Write(.brainstorm/**)' \
  || fail "Write 권한이 .brainstorm/**로 제한되지 않음"
if printf '%s\n' "$FRONTMATTER" | grep -qxF '  - Write'; then
  fail "제한 없는 Write 권한이 남아 있음"
fi
grep -qE '메인 세션.*세션 책임자|세션 책임자.*메인 세션' "$SKILL_MD" \
  || fail "메인 세션=세션 책임자 계약 누락"
grep -qE '프레임.*명시적 승인|명시적 승인.*프레임' "$SKILL_MD" \
  || fail "프레이밍 승인 게이트 누락"
grep -qE '검증 계획.*명시적 승인|명시적 승인.*검증 계획' "$SKILL_MD" \
  || fail "검증 실행 승인 게이트 누락"
grep -qE '자기완결' "$SKILL_MD" \
  || fail "자기완결 brief 규범 인라인 누락"
grep -qE '중첩 Agent.*(않|금지)' "$SKILL_MD" \
  || fail "중첩 Agent 금지 규범 인라인 누락"
grep -qE '민감 정보.*(넣지 않|금지)' "$SKILL_MD" \
  || fail "민감 정보 안전 경계 인라인 누락"
ok "세션 책임과 승인 게이트"

echo ""
echo "=== TEST 4: 전략 선택과 발산 독립성 ==="
for strategy in Brainwriting SCAMPER NGT; do
  grep -q "$strategy" "$REFS/strategy-protocols.md" \
    || fail "전략 누락: $strategy"
done
grep -qE 'Brainwriting.*항상|항상.*Brainwriting' "$REFS/strategy-protocols.md" \
  || fail "Brainwriting 기본 전략 계약 누락"
grep -qE '다양성.*정체.*SCAMPER|SCAMPER.*다양성.*정체' "$REFS/strategy-protocols.md" \
  || fail "SCAMPER 선택 조건 누락"
grep -qE 'NGT.*수렴|수렴.*NGT' "$REFS/strategy-protocols.md" \
  || fail "NGT 수렴 전략 계약 누락"
grep -qE '3[–-]6|3~6|3명.*6명' "$SKILL_MD" "$REFS/role-prompts.md" \
  || fail "적응형 3-6명 아이디어 생성자 계약 누락"
grep -qE '독립.*생성|독립적으로.*아이디어' "$REFS/strategy-protocols.md" \
  || fail "독립 1차 생성 계약 누락"
grep -qE '발산.*(비판|평가|순위|합의).*(금지|하지 않)|발산 중.*(비판|평가|순위|합의)' "$REFS/strategy-protocols.md" \
  || fail "발산 중 평가·합의 금지 계약 누락"
ok "전략과 발산 독립성 계약"

echo ""
echo "=== TEST 5: 단계별 리서치와 토큰 중복 방지 ==="
grep -qE '발산 전.*최소 리서치|최소 리서치.*발산 전' "$REFS/research-protocol.md" \
  || fail "발산 전 최소 리서치 계약 누락"
grep -qE 'shortlist|후보 목록' "$REFS/research-protocol.md" \
  || fail "후보 선정 후 상세 검증 리서치 계약 누락"
grep -qE '관련.*정보만.*(전달|배포)|전체.*반복.*(전달|주입).*않' "$SKILL_MD" \
  || fail "관련 정보만 배포하는 중복 방지 계약 누락"
grep -qE '중앙.*리서치|공통.*리서치' "$REFS/research-protocol.md" "$SKILL_MD" \
  || fail "중앙 리서치 계약 누락"
ok "단계별 중앙 리서치 계약"

echo ""
echo "=== TEST 6: 아이디어 보존·계보·평가 ==="
grep -qE '원본 아이디어.*보존|raw.*idea.*preserv|원본.*삭제하지' "$REFS/document-templates.md" "$REFS/strategy-protocols.md" \
  || fail "원본 아이디어 보존 계약 누락"
for token in 'idea-id' 'parent-id' 'strategy'; do
  grep -q "$token" "$REFS/document-templates.md" \
    || fail "아이디어 계보 필드 누락: $token"
done
grep -qE '의뢰자 가치|사용자 가치|요청자 가치' "$SKILL_MD" "$REFS/framing-template.md" "$REFS/strategy-protocols.md" \
  || fail "의뢰자 가치 기반 평가 계약 누락"
ok "아이디어 보존·계보·평가 계약"

echo ""
echo "=== TEST 7: 검증 실험 경계와 산출물 ==="
grep -qE 'research|리서치' "$SKILL_MD" \
  || fail "허용 검증 유형 누락: research"
for token in '에이전트 비판' '문서' '목업' '프로토타입'; do
  grep -q "$token" "$SKILL_MD" "$REFS/role-prompts.md" "$REFS/document-templates.md" \
    || fail "허용 검증 유형 누락: $token"
done
grep -qE '코드베이스|조직 정책|외부 시스템' "$SKILL_MD" \
  || fail "검증 실험 금지 경계 누락"
grep -qE '후보군|복수 후보|candidate set' "$SKILL_MD" \
  || fail "단일 강제 결론 대신 후보군 출력 계약 누락"
ok "검증 경계와 산출물 계약"

echo ""
echo "=== TEST 8: 단일 세션 파일 계약 ==="
grep -qF '.brainstorm/<session-id>.md' "$REFS/document-templates.md" \
  || fail "단일 세션 파일 템플릿 누락"
grep -q '## 상태' "$REFS/document-templates.md" \
  || fail "상태 블록 섹션 누락"
for field in 'state' 'next-action'; do
  grep -q "$field" "$REFS/document-templates.md" \
    || fail "상태 블록 필드 누락: $field"
done
for section in '브리프' '연구 컨텍스트' '로스터' '아이디어 풀' '군집' '숏리스트' '검증 계획' '실험' '최종 보고'; do
  grep -q "## ${section}" "$REFS/document-templates.md" \
    || fail "세션 파일 섹션 누락: $section"
done
grep -qE '상태 블록.*먼저 갱신' "$SKILL_MD" \
  || fail "상태 블록 우선 갱신 계약 누락"
grep -qE '섹션 단위로만.*(추가|갱신)' "$SKILL_MD" \
  || fail "섹션 단위 추가·갱신 계약 누락"
grep -qE '전체 파일 재작성.*(금지|않는다)' "$SKILL_MD" \
  || fail "전체 파일 재작성 금지 계약 누락"
grep -qE '(resume|재개).*단일 세션 파일|단일 세션 파일.*(resume|재개)' "$SKILL_MD" \
  || fail "resume 단일 파일 읽기 계약 누락"
ok "단일 세션 파일 계약"

echo ""
echo "=== TEST 9: 구 다중 파일 계약 부재 ==="
if grep -rqF '.brainstorm/<session-id>/' "$SKILL_DIR"; then
  fail "구 디렉터리 계약 잔존: .brainstorm/<session-id>/"
fi
for artifact in state.md brief.md research-context.md roster.md idea-pool.md clusters.md shortlist.md validation-plan.md experiments.md report.md; do
  if grep -rqF "$artifact" "$SKILL_DIR"; then
    fail "구 산출물 파일명 잔존: $artifact"
  fi
done
ok "구 다중 파일 계약 부재"

echo ""
echo "=== TEST 10: 아이디어 상태 enum 계약 (archived 제거, parked/eliminated + 필수 필드, NGT 규칙) ==="
grep -qF 'parked' "$REFS/document-templates.md" \
  || fail "status enum에 parked 누락"
grep -qF 'eliminated' "$REFS/document-templates.md" \
  || fail "status enum에 eliminated 누락"
! grep -qF 'archived' "$REFS/document-templates.md" \
  || fail "status enum에 archived 잔존 (제거 필요)"
grep -qF 'park-recondition' "$REFS/document-templates.md" \
  || fail "park-recondition 필수 필드 누락"
grep -qF 'elimination-reason' "$REFS/document-templates.md" \
  || fail "elimination-reason 필수 필드 누락"
grep -qF '구체화 부족(덜 익음)을 후보 탈락 근거로 쓰지 않는다' "$REFS/strategy-protocols.md" \
  || fail "NGT 성숙도 미사용 규칙 문장 누락"
grep -qF '관찰 가능한 재검토 조건을 쓸 수 있으면 parked' "$REFS/strategy-protocols.md" \
  || fail "NGT 상태 전환 규칙 문장 누락"
ok "아이디어 상태 enum 계약 (parked/eliminated 분리, 필수 필드 2개, NGT 규칙 2문장)"

echo ""
echo "=== TEST 11: 플러그인 버전 ==="
PLUGIN_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN_DIR/.claude-plugin/plugin.json")"
MARKET_VERSION="$(python3 -c 'import json,sys; print(next(p["version"] for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="thinktank"))' "$MARKETPLACE")"
[[ -n "$PLUGIN_VERSION" && "$PLUGIN_VERSION" == "$MARKET_VERSION" ]] \
  || fail "플러그인/마켓플레이스 버전 불일치: plugin.json=$PLUGIN_VERSION marketplace=$MARKET_VERSION"
# 버전 범프 회귀 가드: 릴리스 시 이 핀도 함께 올린다 (parity만으로는 미범프를 못 잡는다)
EXPECTED_VERSION="1.2.0"
[[ "$PLUGIN_VERSION" == "$EXPECTED_VERSION" ]] \
  || fail "플러그인 버전이 현재 릴리스 핀과 다름: plugin.json=$PLUGIN_VERSION expected=$EXPECTED_VERSION (릴리스 시 핀 갱신)"
ok "플러그인과 마켓플레이스 버전 동기 + 릴리스 핀 일치 ($PLUGIN_VERSION)"

echo ""
echo "=== TEST 12: brief 디스패치 규범·증거 임계치 계약 ==="
grep -qF '메인 세션 컨텍스트는 보이지 않는다' "$REFS/role-prompts.md" \
  || fail "brief 메인 컨텍스트 비가시성 명시 누락 (role-prompts)"
grep -qF '중첩 Agent를 호출하지 않는다' "$REFS/role-prompts.md" \
  || fail "brief 중첩 Agent 금지 명시 누락 (role-prompts)"
grep -qF '독립인 출처 2개 이상' "$REFS/research-protocol.md" \
  || fail "핵심 사실 독립 출처 임계치 누락"
ok "brief 디스패치 규범과 증거 임계치 계약"

echo ""
echo "=== 모든 brainstorm 스킬 테스트 통과 ==="
