#!/usr/bin/env bash
# 스킬 호출 시뮬레이션: on_create의 의도를 셸로 직접 실행

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator"

# 산출물 존재 검사
echo "=== 스킬 디렉토리 구조 ==="
for f in SKILL.md \
         templates/ralph-loop.md \
         assets/loop.sh \
         assets/PROMPT.template.md \
         assets/loops-README.md \
         assets/PLAN.template.md \
         assets/NOTES.template.md \
         assets/HANDOFF.template.md \
         assets/RUN_LOG.template.md \
         assets/ESCALATION.template.md; do
  [[ -f "$SKILL_DIR/$f" ]] || { echo "FAIL: $f 부재"; exit 1; }
  echo "OK: $f"
done

echo ""
echo "=== loop.sh 실행 권한 ==="
[[ -x "$SKILL_DIR/assets/loop.sh" ]] || { echo "FAIL: loop.sh 실행 권한 없음"; exit 1; }
echo "OK"

echo ""
echo "=== ralph-loop.md frontmatter 필수 필드 ==="
# frontmatter 분리 후 yq 검증 (multi-line sed for BSD 호환)
TMP_FM=$(mktemp)
sed -n '1,/^---$/{
  1d
  /^---$/d
  p
}' "$SKILL_DIR/templates/ralph-loop.md" > "$TMP_FM"

yq '.label' "$TMP_FM" >/dev/null 2>&1 \
  || { echo "FAIL: label 필드 부재"; rm -f "$TMP_FM"; exit 1; }
yq '.on_create' "$TMP_FM" >/dev/null 2>&1 \
  || { echo "FAIL: on_create 필드 부재"; rm -f "$TMP_FM"; exit 1; }
rm -f "$TMP_FM"
echo "OK"

echo ""
echo "=== PROMPT.template.md frontmatter 파싱 ==="
TMP_FM=$(mktemp)
sed -n '1,/^---$/{
  1d
  /^---$/d
  p
}' "$SKILL_DIR/assets/PROMPT.template.md" > "$TMP_FM"

yq '.scope.include[]' "$TMP_FM" >/dev/null \
  || { echo "FAIL: scope.include 파싱 실패"; rm -f "$TMP_FM"; exit 1; }
yq '.verify' "$TMP_FM" >/dev/null \
  || { echo "FAIL: verify 파싱 실패"; rm -f "$TMP_FM"; exit 1; }
rm -f "$TMP_FM"
echo "OK"

echo ""
echo "=== 헌법 본문에서 자율-루프-지침 미참조 ==="
# frontmatter 제외한 본문에 "자율-루프-지침" 문자열이 없어야 함
sed -n '/^---$/,/^---$/!p' "$SKILL_DIR/templates/ralph-loop.md" | grep -q "자율-루프-지침" \
  && { echo "FAIL: 헌법 본문이 자율-루프-지침.md를 참조함"; exit 1; }
echo "OK"

echo ""
echo "=== on_create 시뮬레이션 (임시 프로젝트에서) ==="
WORK_DIR="$(mktemp -d)"
trap "rm -rf $WORK_DIR" EXIT
PROJECT="$WORK_DIR/test-project"
mkdir -p "$PROJECT" "$PROJECT/rules"
cd "$PROJECT"
git init -q
git config user.email "test@example.com"
git config user.name "Test"

# on_create 1단계: rules/autonomous-loop.md 생성 (frontmatter 제거)
sed -n '/^---$/,/^---$/!p' "$SKILL_DIR/templates/ralph-loop.md" > rules/autonomous-loop.md
[[ -s rules/autonomous-loop.md ]] || { echo "FAIL: rules/autonomous-loop.md 빈 파일"; exit 1; }

# on_create 2~4단계: assets 복사
mkdir -p .loops/{templates,locks,archive}
cp "$SKILL_DIR/assets/PROMPT.template.md" .loops/
cp "$SKILL_DIR/assets/loop.sh" .loops/
chmod +x .loops/loop.sh
cp "$SKILL_DIR/assets/loops-README.md" .loops/README.md
cp "$SKILL_DIR/assets/"{PLAN,NOTES,HANDOFF,RUN_LOG,ESCALATION}.template.md .loops/templates/
touch .loops/locks/.gitkeep .loops/archive/.gitkeep

# 모든 파일 존재 확인
for f in rules/autonomous-loop.md \
         .loops/PROMPT.template.md \
         .loops/loop.sh \
         .loops/README.md \
         .loops/templates/PLAN.template.md \
         .loops/templates/NOTES.template.md \
         .loops/templates/HANDOFF.template.md \
         .loops/templates/RUN_LOG.template.md \
         .loops/templates/ESCALATION.template.md; do
  [[ -f "$f" ]] || { echo "FAIL: 시뮬레이션 후 $f 부재"; exit 1; }
done
echo "OK"

echo ""
echo "=== .gitignore 갱신 시뮬레이션 ==="
echo ".loops/locks/" >> .gitignore
grep -q "^\.loops/locks/" .gitignore || { echo "FAIL: .gitignore 갱신 실패"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 테스트 통과 ==="
