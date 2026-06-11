#!/usr/bin/env bash
# brainstorm 스킬 패키지와 핵심 발산·수렴·검증 계약 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_DIR="$REPO_ROOT/plugins/roundtable"
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
ok "필수 파일 존재"

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
grep -qF '.brainstorm/<session-id>/' "$SKILL_MD" \
  || fail "브레인스토밍 산출물 루트 계약 누락"
grep -qE 'resume 라우팅|재개 라우팅' "$SKILL_MD" \
  || fail "상태별 resume 라우팅 누락"
grep -qE 'status 보고|상태 보고' "$SKILL_MD" \
  || fail "읽기 전용 status 보고 형식 누락"
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
grep -qE '관련.*정보만.*(전달|배포)|전체.*반복.*(전달|주입).*않' "$REFS/research-protocol.md" \
  || fail "관련 정보만 배포하는 중복 방지 계약 누락"
grep -qE '중앙.*리서치|공통.*리서치' "$REFS/research-protocol.md" \
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
for artifact in state.md brief.md research-context.md roster.md idea-pool.md clusters.md shortlist.md validation-plan.md experiments.md report.md; do
  grep -q "$artifact" "$REFS/document-templates.md" "$SKILL_MD" \
    || fail "산출물 계약 누락: $artifact"
done
ok "검증 경계와 산출물 계약"

echo ""
echo "=== TEST 8: 플러그인 버전 ==="
grep -q '"version": "0.2.0"' "$PLUGIN_DIR/.claude-plugin/plugin.json" \
  || fail "roundtable 플러그인 버전이 0.2.0이 아님"
awk '/"name": "roundtable"/{found=1} found && /"version": "0.2.0"/{ok=1; exit} END{exit !ok}' "$MARKETPLACE" \
  || fail "마켓플레이스 roundtable 버전이 0.2.0이 아님"
ok "플러그인과 마켓플레이스 버전"

echo ""
echo "=== 모든 brainstorm 스킬 테스트 통과 ==="
