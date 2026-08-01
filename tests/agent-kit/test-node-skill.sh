#!/usr/bin/env bash
# node 스킬 패키지와 노드 타입 계약 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_DIR="$REPO_ROOT/plugins/agent-kit"
SKILL_DIR="$PLUGIN_DIR/skills/node"
SKILL_MD="$SKILL_DIR/SKILL.md"
REFS="$SKILL_DIR/references"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

echo "=== TEST 1: 스킬 구조 ==="
for file in \
  "$SKILL_MD" \
  "$REFS/node-schema.md" \
  "$REFS/run-kinds.md" \
  "$PLUGIN_DIR/.claude-plugin/plugin.json" \
  "$PLUGIN_DIR/README.md"; do
  [[ -f "$file" ]] || fail "필수 파일 부재: $file"
done
ok "필수 파일 존재"

echo ""
echo "=== TEST 2: 공개 인터페이스 ==="
for command in create test list; do
  grep -qE "node ${command}|## ${command} 워크플로" "$SKILL_MD" \
    || fail "서브커맨드 누락: $command"
done
grep -qE '인자가 없으면.*create' "$SKILL_MD" \
  || fail "무인자 create 기본 규약 누락"
grep -qF '.pipelines/nodes/<이름>.yaml' "$SKILL_MD" \
  || fail "노드 타입 파일 경로 계약 누락"
grep -qE '덮어쓰지 말고' "$SKILL_MD" \
  || fail "동명 파일 덮어쓰기 방지 규약 누락"
ok "인터페이스 계약"

echo ""
echo "=== TEST 3: 권한과 안전 경계 ==="
FRONTMATTER="$(awk '/^---$/{n++; next} n==1' "$SKILL_MD")"
printf '%s\n' "$FRONTMATTER" | grep -qxF '  - Write(.pipelines/**)' \
  || fail "Write 권한이 .pipelines/**로 제한되지 않음"
if printf '%s\n' "$FRONTMATTER" | grep -qxF '  - Write'; then
  fail "제한 없는 Write 권한이 남아 있음"
fi
grep -qE '실행 전 명령.*(보여주고|확인)' "$SKILL_MD" \
  || fail "test 실행 전 명령 확인 규약 누락"
grep -qE '중첩 Agent.*(않|금지)' "$SKILL_MD" \
  || fail "중첩 Agent 금지 규범 누락"
grep -qE '민감 정보.*(넣지 않|금지)' "$SKILL_MD" \
  || fail "민감 정보 안전 경계 누락"
ok "권한과 안전 경계"

echo ""
echo "=== TEST 4: kind 계약 ==="
for kind in llm script http mcp; do
  grep -qE "^## ${kind}" "$REFS/run-kinds.md" \
    || fail "run-kinds에 kind 섹션 누락: $kind"
done
grep -qE 'llm \| script \| http \| mcp' "$SKILL_MD" \
  || fail "kind 4종 열거 누락"
for field in name kind description inputs outputs run; do
  grep -qE "\`${field}\`" "$REFS/node-schema.md" \
    || fail "node-schema에 필드 누락: $field"
done
grep -qE '스키마.*(만족|강제)' "$REFS/run-kinds.md" \
  || fail "출력 스키마 계약 누락"
ok "kind와 스키마 계약"

echo ""
echo "모든 node 스킬 테스트 통과"
