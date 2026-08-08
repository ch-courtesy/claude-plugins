#!/usr/bin/env bash
# pipeline 스킬 패키지와 정의·컴파일 계약 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PLUGIN_DIR="$REPO_ROOT/plugins/recipe"
SKILL_DIR="$PLUGIN_DIR/skills/pipeline"
SKILL_MD="$SKILL_DIR/SKILL.md"
REFS="$SKILL_DIR/references"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
CODEX_MARKETPLACE="$REPO_ROOT/.agents/plugins/marketplace.json"
FIXTURES="$REPO_ROOT/tests/recipe/fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

echo "=== TEST 1: 스킬 구조와 등록 ==="
for file in \
  "$SKILL_MD" \
  "$REFS/pipeline-schema.md" \
  "$REFS/util-nodes.md" \
  "$REFS/validate-checklist.md" \
  "$REFS/compile-template.md"; do
  [[ -f "$file" ]] || fail "필수 파일 부재: $file"
done
jq -e '.plugins[] | select(.name == "recipe")' "$MARKETPLACE" >/dev/null \
  || fail "marketplace.json에 recipe 미등록"
jq -e '.name == "recipe"' "$PLUGIN_DIR/.claude-plugin/plugin.json" >/dev/null \
  || fail "plugin.json name 불일치"
ok "필수 파일 존재 + 마켓플레이스 등록"

echo ""
echo "=== TEST 2: 공개 인터페이스와 원칙 ==="
for command in create compile list; do
  grep -qE "pipeline ${command}|## ${command} 워크플로" "$SKILL_MD" \
    || fail "서브커맨드 누락: $command"
done
grep -qE '인자가 없으면.*create' "$SKILL_MD" \
  || fail "무인자 create 기본 규약 누락"
grep -qE 'run 서브커맨드는 없다' "$SKILL_MD" \
  || fail "run 부재 계약 누락"
grep -qE '정의 = 소스.*스킬 = 바이너리|정의=소스' "$SKILL_MD" \
  || fail "정의=소스 원칙 누락"
grep -qF 'compiled-from' "$SKILL_MD" \
  || fail "compiled-from 해시 규약 누락"
grep -qF '.pipelines/<이름>.yaml' "$SKILL_MD" \
  || fail "정의 파일 경로 계약 누락"
grep -qF '.agents/skills/<이름>/' "$SKILL_MD" \
  || fail "컴파일 중립 산출 경로 계약 누락"
grep -qE '\.claude/skills/<이름>.*심링크|심링크.*\.claude/skills/<이름>' "$SKILL_MD" \
  || fail "Claude 어댑터 심링크 규약 누락"
grep -qE '재컴파일 필요' "$SKILL_MD" \
  || fail "list의 해시 대조 표시 누락"
grep -qE '파이프라인 합성' "$SKILL_MD" \
  || fail "kind: pipeline 합성 계약 누락"
ok "인터페이스와 원칙"

echo ""
echo "=== TEST 3: 권한·안전 경계·벤더 중립 ==="
FRONTMATTER="$(awk '/^---$/{n++; next} n==1' "$SKILL_MD")"
BODY="$(awk '/^---$/{n++; next} n>=2' "$SKILL_MD")"
printf '%s\n' "$FRONTMATTER" | grep -qxF '  - Write(.pipelines/**)' \
  || fail "Write 권한에 .pipelines/** 부재"
printf '%s\n' "$FRONTMATTER" | grep -qxF '  - Write(.agents/skills/**)' \
  || fail "Write 권한에 .agents/skills/** 부재"
if printf '%s\n' "$FRONTMATTER" | grep -qxF '  - Write'; then
  fail "제한 없는 Write 권한이 남아 있음"
fi
if printf '%s\n' "$BODY" | grep -q 'AskUserQuestion'; then
  fail "본문에 런타임 도구명 리터럴 잔존: AskUserQuestion"
fi
printf '%s\n' "$BODY" | grep -q '구조화된 사용자 질문 기능' \
  || fail "중립 질문 문구 누락"
grep -qE '실행하지 않는다' "$SKILL_MD" \
  || fail "파이프라인 비실행 경계 누락"
grep -qE 'validate를 통과하지 못한.*(만들지 않)' "$SKILL_MD" \
  || fail "validate 실패 시 산출 금지 규약 누락"
ok "권한·안전 경계·벤더 중립"

echo ""
echo "=== TEST 4: 유틸 노드와 validate 계약 ==="
for util in if switch foreach while merge transform human-gate; do
  grep -q -- "$util" "$REFS/util-nodes.md" \
    || fail "util-nodes에 누락: $util"
done
for check in '참조 무결성' '순환' 'required' '타입'; do
  grep -q "$check" "$REFS/validate-checklist.md" \
    || fail "validate-checklist에 누락: $check"
done
grep -qF '.agents/skills/<이름>/SKILL.md' "$REFS/validate-checklist.md" \
  || fail "validate가 중립 경로의 frontmatter를 읽는 계약 누락"
if grep -q 'AskUserQuestion' "$REFS/util-nodes.md"; then
  fail "util-nodes에 런타임 도구명 리터럴 잔존"
fi
for ref in '\$pipeline\.' '\$item' 'needs' 'retry' 'timeout' 'on_error' \
  'fail' 'continue' 'skill:' 'outputs'; do
  grep -qE "$ref" "$REFS/pipeline-schema.md" \
    || fail "pipeline-schema에 누락: $ref"
done
ok "유틸 노드와 validate"

echo ""
echo "=== TEST 5: 컴파일 템플릿 런타임 계약 ==="
for contract in 'state.json' 'resume' 'run-id' 'skipped' 'aborted' \
  'compiled-from' 'kind: pipeline' '자기완결' '안전 경계' '심링크' \
  '구조화된 사용자 질문 기능' '서브에이전트 기능' 'Claude Code 전용'; do
  grep -q -- "$contract" "$REFS/compile-template.md" \
    || fail "compile-template에 누락: $contract"
done
grep -qE '이 2파일만으로.*동작|2파일만으로' "$REFS/compile-template.md" \
  || fail "자립성 계약 누락"
grep -qE '최소 집합' "$REFS/compile-template.md" \
  || fail "allowed-tools 최소화 규약 누락"
grep -qF '.agents/skills/<이름>/' "$REFS/compile-template.md" \
  || fail "컴파일 템플릿 중립 산출 경로 누락"
ok "컴파일 템플릿"

echo ""
echo "=== TEST 6: Codex 어댑터 ==="
[[ -f "$PLUGIN_DIR/.codex-plugin/plugin.json" ]] || fail ".codex-plugin/plugin.json 부재"
[[ -f "$CODEX_MARKETPLACE" ]] || fail "Codex 마켓플레이스 매니페스트 부재"
jq -e '.name == "recipe" and .skills == "./skills/"' "$PLUGIN_DIR/.codex-plugin/plugin.json" >/dev/null \
  || fail ".codex-plugin name/skills 포인터 불일치"
CLAUDE_VER=$(jq -r .version "$PLUGIN_DIR/.claude-plugin/plugin.json")
CODEX_VER=$(jq -r .version "$PLUGIN_DIR/.codex-plugin/plugin.json")
[[ "$CLAUDE_VER" == "$CODEX_VER" ]] || fail "Claude/Codex plugin.json 버전 불일치: $CLAUDE_VER vs $CODEX_VER"
jq -e '.plugins[] | select(.name == "recipe") | .source.path == "./plugins/recipe"' "$CODEX_MARKETPLACE" >/dev/null \
  || fail "Codex 마켓플레이스에 recipe 미등록"
ok "Codex 어댑터"

echo ""
echo "=== TEST 7: 픽스처 정합성 ==="
for file in \
  "$FIXTURES/skills/greet/SKILL.md" \
  "$FIXTURES/skills/summarize/SKILL.md" \
  "$FIXTURES/sample-pipeline.yaml" \
  "$FIXTURES/broken-pipeline.yaml"; do
  [[ -f "$file" ]] || fail "픽스처 부재: $file"
done
[[ ! -e "$FIXTURES/nodes" ]] || fail "구 노드 픽스처 디렉터리 잔존"
for field in 'name:' 'kind:' 'description:' 'inputs:' 'outputs:' 'run:'; do
  grep -q "$field" "$FIXTURES/skills/greet/SKILL.md" \
    || fail "greet에 필드 누락: $field"
done
grep -q 'kind: script' "$FIXTURES/skills/greet/SKILL.md" || fail "greet는 script여야 함"
grep -q 'kind: llm' "$FIXTURES/skills/summarize/SKILL.md" || fail "summarize는 llm이어야 함"
for field in 'name:' 'description:' 'inputs:' 'outputs:' 'nodes:'; do
  grep -q "$field" "$FIXTURES/sample-pipeline.yaml" \
    || fail "sample-pipeline에 필드 누락: $field"
done
grep -q 'skill: greet' "$FIXTURES/sample-pipeline.yaml" \
  || fail "sample-pipeline에 skill: 참조 부재"
grep -qE 'util: (if|foreach|transform|human-gate|merge|switch)' "$FIXTURES/sample-pipeline.yaml" \
  || fail "sample-pipeline에 유틸 노드 사용 예 부재"
grep -q 'no-such-skill' "$FIXTURES/broken-pipeline.yaml" \
  || fail "broken-pipeline에 의도된 위반(없는 스킬 참조) 부재"
ok "픽스처 정합성"

echo ""
echo "모든 pipeline 스킬 테스트 통과"
