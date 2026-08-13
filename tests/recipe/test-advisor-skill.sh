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
CODEX_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN_DIR/.codex-plugin/plugin.json")"
[[ "$CODEX_VERSION" == "$PLUGIN_VERSION" ]] \
  || fail "codex 매니페스트 버전 불일치: .codex-plugin=$CODEX_VERSION plugin.json=$PLUGIN_VERSION"
# 버전 범프 회귀 가드: 릴리스 시 이 핀도 함께 올린다
EXPECTED_VERSION="0.5.0"
[[ "$PLUGIN_VERSION" == "$EXPECTED_VERSION" ]] \
  || fail "플러그인 버전이 현재 릴리스 핀과 다름: plugin.json=$PLUGIN_VERSION expected=$EXPECTED_VERSION (릴리스 시 핀 갱신)"
# 구성요소 열거 동기 — 같은 4종이 매니페스트·README에 손으로 복제돼 있어 한 곳만 빠져도 표류한다.
# 스킬 디렉터리를 단일 출처로 삼아, 각 스킬을 대표하는 키워드가 모든 사용자 노출 설명에 있는지 본다.
# 다중 플러그인 파일은 recipe 항목만 뽑아 검사 — 파일 전체 grep이면 다른 플러그인 텍스트가 표류를 가린다
RECIPE_ENTRY="$(python3 -c 'import json,sys; print(json.dumps(next(p for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="recipe"), ensure_ascii=False))' "$MARKETPLACE")"
ROOT_RECIPE_LINE="$(grep -E '^- `recipe`' "$REPO_ROOT/README.md" || true)"
[[ -n "$ROOT_RECIPE_LINE" ]] || fail "루트 README에 recipe 불릿(^- \`recipe\`) 없음"
# keywords/tags 배열이 아니라 **사람이 읽는 설명 필드**를 대상으로 — 배열이 매치를 대신하면
# description 표류(구성요소 구절 삭제)를 못 잡는다.
DESC_CLAUDE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["description"])' "$PLUGIN_JSON")"
CODEX_MANIFEST="$PLUGIN_DIR/.codex-plugin/plugin.json"
codex_field() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
k=sys.argv[2]
print(d[k] if k in d else d.get("interface",{}).get(k,""))' "$CODEX_MANIFEST" "$1"; }
DESC_MARKET="$(python3 -c 'import json,sys; print(next(p for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="recipe")["description"])' "$MARKETPLACE")"
# 각 구성요소를 설명 필드에서 알아볼 수 있는 표지(스킬명 또는 그 스킬을 가리키는 한국어 구절)
check_desc() {   # $1=라벨 $2=설명텍스트
  # 각 표지는 해당 구성요소에만 나타나는 것이어야 한다 — 예: '워크플로'는 advisor 구절
  # ("Advisor 감독 워크플로")에도 있어 pipeline 검사를 항상 참으로 만든다(실측 확인).
  grep -qiE 'advisor|어드바이저' <<<"$2" || fail "설명 동기: $1 에 advisor 구성요소 없음"
  grep -qiE 'pipeline|파이프라인|컴파일' <<<"$2" || fail "설명 동기: $1 에 pipeline 구성요소 없음"
  grep -qiE 'oneshot|one-shot|원샷' <<<"$2" || fail "설명 동기: $1 에 oneshot 구성요소 없음"
  grep -qiE 'codex-auth-reseed|시크릿 재시드|auth secret|reseed' <<<"$2" || fail "설명 동기: $1 에 codex-auth-reseed 구성요소 없음"
}
check_desc "plugin.json description" "$DESC_CLAUDE"
# .codex-plugin은 필드별로 따로 — 합쳐서 검사하면 영문 longDescription이 한국어 필드의 표류를 가린다
for f in description shortDescription longDescription; do
  check_desc ".codex-plugin $f" "$(codex_field "$f")"
done
check_desc "marketplace recipe description" "$DESC_MARKET"
check_desc "루트 README recipe 불릿" "$ROOT_RECIPE_LINE"
for kw in advisor pipeline oneshot codex-auth-reseed; do
  grep -qi -- "$kw" "$PLUGIN_DIR/README.md" || fail "설명 동기 누락: plugins/recipe/README.md 에 '$kw' 없음"
done
for d in "$PLUGIN_DIR"/skills/*/; do
  s="$(basename "$d")"
  grep -qi -- "$s" "$PLUGIN_DIR/README.md" || fail "스킬 $s 가 plugins/recipe/README.md 에 미기재"
done
ok "구성요소 열거 동기 (매니페스트·README 5곳)"

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
grep -qE '후속 메시지' "$SKILL_MD" \
  || fail "후속 메시지 회신 계약 누락"
grep -qF 'agents/advisor.md' "$SKILL_MD" \
  || fail "프롬프트 주입 폴백(agents/advisor.md) 누락"
grep -qE '감독이 불가' "$SKILL_MD" \
  || fail "서브에이전트 기능 부재 폴백 누락"
if grep -qE 'SendMessage|subagent_type|Agent 도구' "$SKILL_MD" "$AGENT_MD"; then
  fail "벤더 전용 표기 잔재 존재 (SendMessage/subagent_type/Agent 도구)"
fi
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
