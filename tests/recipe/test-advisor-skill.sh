#!/usr/bin/env bash
# recipe advisor 스킬 패키지와 프로토콜 계약 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_DIR="$REPO_ROOT/plugins/recipe"
SKILL_MD="$PLUGIN_DIR/skills/advisor/SKILL.md"
AGENT_MD="$PLUGIN_DIR/agents/advisor.md"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

echo "=== TEST 1: 패키지 구조 ==="
for file in "$PLUGIN_JSON" "$SKILL_MD" "$AGENT_MD"; do
  [[ -f "$file" ]] || fail "필수 파일 부재: $file"
done
ok "필수 파일 존재"

echo ""
echo "=== TEST 2: 매니페스트와 버전 ==="
PLUGIN_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$PLUGIN_JSON")"
[[ "$PLUGIN_NAME" == "recipe" ]] || fail "플러그인 이름 불일치: $PLUGIN_NAME"
PLUGIN_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN_JSON")"
MARKET_VERSION="$(python3 -c 'import json,sys; print(next(p["version"] for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="recipe"))' "$MARKETPLACE")"
[[ -n "$PLUGIN_VERSION" && "$PLUGIN_VERSION" == "$MARKET_VERSION" ]] \
  || fail "플러그인/마켓플레이스 버전 불일치: plugin.json=$PLUGIN_VERSION marketplace=$MARKET_VERSION"
# 버전 범프 회귀 가드: 릴리스 시 이 핀도 함께 올린다
EXPECTED_VERSION="0.3.0"
[[ "$PLUGIN_VERSION" == "$EXPECTED_VERSION" ]] \
  || fail "플러그인 버전이 현재 릴리스 핀과 다름: plugin.json=$PLUGIN_VERSION expected=$EXPECTED_VERSION (릴리스 시 핀 갱신)"
SOURCE_PATH="$(python3 -c 'import json,sys; print(next(p["source"] for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="recipe"))' "$MARKETPLACE")"
[[ "$SOURCE_PATH" == "./plugins/recipe" ]] || fail "마켓플레이스 source 경로 불일치: $SOURCE_PATH"
ok "매니페스트·버전 동기·릴리스 핀 ($PLUGIN_VERSION)"

echo ""
echo "=== TEST 3: 상태 태그 계약 ==="
for tag in BRIEF QUESTION SKIP APPROVED REVISE ESCALATE; do
  grep -q "$tag" "$AGENT_MD" || fail "에이전트 상태 태그 누락: $tag"
  grep -q "$tag" "$SKILL_MD" || fail "스킬 상태 태그 누락: $tag"
done
grep -qE '첫 줄.*상태 태그|상태 태그.*첫 줄' "$AGENT_MD" \
  || fail "첫 줄 상태 태그 출력 계약 누락"
ok "상태 태그 6종 양쪽 존재 + 첫 줄 출력 계약"

echo ""
echo "=== TEST 4: Advisor 판단 규율 ==="
grep -qF 'tools: [Read, Grep, Glob, Bash, Edit, Write]' "$AGENT_MD" \
  || fail "에이전트 도구 선언 불일치"
grep -qE '그대로 믿지 마라|믿지 않는다' "$AGENT_MD" \
  || fail "완료 보고 불신 계약 누락"
grep -qF 'git diff' "$AGENT_MD" \
  || fail "diff 직접 확인 계약 누락"
grep -qE '직접 실행' "$AGENT_MD" \
  || fail "완료 기준 직접 실행 계약 누락"
grep -qF '사소한 마무리' "$AGENT_MD" \
  || fail "직접 수정 허용 범위 계약 누락"
grep -qE '3라운드|라운드 2/3' "$AGENT_MD" \
  || fail "REVISE 3라운드 상한 누락"
grep -qE '커밋.*Worker의 몫|커밋.*직접 실행하지 않는다' "$AGENT_MD" \
  || fail "커밋 비실행 계약 누락"
grep -qE '자기완결' "$AGENT_MD" \
  || fail "자기완결 브리프 규범 누락"
for field in '목표' '대상 파일' '컨벤션' '함정' '완료 기준'; do
  grep -q "$field" "$AGENT_MD" || fail "브리프 필드 누락: $field"
done
ok "판단 규율·브리프 템플릿 계약"

echo ""
echo "=== TEST 5: Worker 프로토콜 ==="
grep -qF 'recipe:advisor' "$SKILL_MD" \
  || fail "에이전트 참조(recipe:advisor) 누락"
grep -qF 'SendMessage' "$SKILL_MD" \
  || fail "SendMessage 루프 계약 누락"
grep -qE '가공 없이' "$SKILL_MD" \
  || fail "무가공 릴레이 계약 누락"
grep -qE '파일을 수정하지 않는다' "$SKILL_MD" \
  || fail "검증 턴 턴제(수정 금지) 계약 누락"
grep -qE '커밋을 요청했을 때만' "$SKILL_MD" \
  || fail "사용자 커밋 요청 조건 누락"
grep -qE '새 Advisor를 스폰' "$SKILL_MD" \
  || fail "소실 시 재스폰 계약 누락"
for item in '변경 파일 목록' '변경 요약' '완료 기준 실행 결과'; do
  grep -qF "$item" "$SKILL_MD" || fail "완료 보고 형식 누락: $item"
done
ok "Worker 프로토콜 계약"

echo ""
echo "=== 모든 advisor 스킬 테스트 통과 ==="
