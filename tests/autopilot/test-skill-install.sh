#!/usr/bin/env bash
# autopilot/loop 스킬 패키지 구조 검증 테스트

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/loop"
SKILL_REFS="$SKILL_DIR/references"

echo "=== 스킬 디렉토리 구조 ==="
for f in SKILL.md \
         references/constitution.md \
         references/loop.sh \
         references/spec-template.md \
         references/plan-template.md \
         references/notes-template.md \
         references/handoff-template.md \
         references/runlog-template.md \
         references/escalation-template.md \
         references/operational-guide.md \
         references/prepare.md \
         references/status-format.md \
         references/troubleshooting.md \
         references/agent-prompts.md; do
  [[ -f "$SKILL_DIR/$f" ]] || { echo "FAIL: $f 부재"; exit 1; }
  echo "OK: $f"
done

echo ""
echo "=== plugin.json 존재 ==="
PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
[[ -f "$PLUGIN_JSON" ]] || { echo "FAIL: plugin.json 부재"; exit 1; }
echo "OK"

echo ""
echo "=== loop.sh 실행 권한 ==="
[[ -x "$SKILL_REFS/loop.sh" ]] || { echo "FAIL: loop.sh 실행 권한 없음"; exit 1; }
echo "OK"

echo ""
echo "=== loop.sh bash syntax 검사 ==="
bash -n "$SKILL_REFS/loop.sh" || { echo "FAIL: loop.sh syntax 오류"; exit 1; }
echo "OK"

echo ""
echo "=== loop.sh SCRIPT_DIR 패턴 확인 ==="
grep -q 'SCRIPT_DIR=.*BASH_SOURCE' "$SKILL_REFS/loop.sh" \
  || { echo "FAIL: SCRIPT_DIR 패턴 없음"; exit 1; }
# 헌법 복사가 SCRIPT_DIR을 사용하는지
grep -q 'SCRIPT_DIR/constitution.md' "$SKILL_REFS/loop.sh" \
  || { echo "FAIL: constitution.md 복사가 SCRIPT_DIR 기반이 아님"; exit 1; }
echo "OK"

echo ""
echo "=== constitution.md 본문 시작 확인 (frontmatter 없음) ==="
FIRST_LINE=$(head -1 "$SKILL_REFS/constitution.md")
[[ "$FIRST_LINE" == "---" ]] && { echo "FAIL: constitution.md에 frontmatter가 남아있음"; exit 1; }
[[ -s "$SKILL_REFS/constitution.md" ]] || { echo "FAIL: constitution.md 비어있음"; exit 1; }
echo "OK"

echo ""
echo "=== spec-template.md frontmatter 파싱 ==="
command -v yq >/dev/null 2>&1 || { echo "SKIP: yq 미설치"; echo ""; echo "=== 모든 테스트 통과 (yq 테스트 제외) ==="; exit 0; }

TMP_FM=$(mktemp)
sed -n '1,/^---$/{
  1d
  /^---$/d
  p
}' "$SKILL_REFS/spec-template.md" > "$TMP_FM"

yq '.scope.include[]' "$TMP_FM" >/dev/null \
  || { echo "FAIL: scope.include 파싱 실패"; rm -f "$TMP_FM"; exit 1; }
yq '.verify' "$TMP_FM" >/dev/null \
  || { echo "FAIL: verify 파싱 실패"; rm -f "$TMP_FM"; exit 1; }
rm -f "$TMP_FM"
echo "OK"

echo ""
echo "=== constitution.md 내용에 자율-루프-지침 미참조 ==="
grep -q "자율-루프-지침" "$SKILL_REFS/constitution.md" \
  && { echo "FAIL: constitution.md가 자율-루프-지침.md를 참조함"; exit 1; }
echo "OK"

echo ""
echo "=== old autonomous-loop-rule-creator 디렉토리 삭제 확인 ==="
OLD_SKILL="$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator"
[[ -d "$OLD_SKILL" ]] && { echo "FAIL: old autonomous-loop-rule-creator 디렉토리가 아직 존재함"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 테스트 통과 ==="
