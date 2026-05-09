#!/usr/bin/env bash
# loop.sh 통합 테스트
# claude CLI를 mock으로 대체해 워크트리 생성·락·게이트 분기를 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOOP_SH_SRC="$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator/assets/loop.sh"
RULES_SRC="$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator/templates/ralph-loop.md"

# 기대 산출물 검사
[[ -x "$LOOP_SH_SRC" ]] || { echo "FAIL: loop.sh가 실행 가능하지 않음"; exit 1; }
[[ -f "$RULES_SRC" ]] || { echo "FAIL: ralph-loop.md 템플릿 부재"; exit 1; }

# 임시 작업공간 (테스트 격리)
WORK_DIR="$(mktemp -d)"
trap "rm -rf $WORK_DIR" EXIT

# 가짜 프로젝트 git init
PROJECT="$WORK_DIR/myproject"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init -q
git config user.email "test@example.com"
git config user.name "Test"
git commit --allow-empty -m "initial" -q

# .loops/ 구조 시뮬레이션 (스킬이 했을 작업)
mkdir -p .loops/{templates,locks}
mkdir -p rules
# frontmatter 제거한 본문을 rules/autonomous-loop.md로 — multi-line sed (BSD 호환)
sed -n '1,/^---$/!p' "$RULES_SRC" > rules/autonomous-loop.md
[[ -s rules/autonomous-loop.md ]] || { echo "FAIL: rules/autonomous-loop.md 비어있음"; exit 1; }

cp "$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator/assets/PROMPT.template.md" .loops/
cp "$REPO_ROOT/plugins/project-init/skills/autonomous-loop-rule-creator/assets/"{PLAN,NOTES,HANDOFF,RUN_LOG,ESCALATION}.template.md .loops/templates/
cp "$LOOP_SH_SRC" .loops/loop.sh
chmod +x .loops/loop.sh
git add -A
git commit -q -m "init project"
# 추가 커밋: diff HEAD~1 HEAD가 비어 있어야 suppressor 오탐 방지
git commit --allow-empty -q -m "chore: baseline"

# claude CLI mock — PATH 앞에 둠
MOCK_BIN="$WORK_DIR/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env bash
# 단순 mock: stdin 소비 후 DONE 파일 생성 + JSON 응답
# iterate() 서브쉘에서 cd "$WT" 상태로 호출되므로 cwd = 워크트리 루트
cat > /dev/null
touch DONE
echo '{"result": "mock", "usage": {"input_tokens": 100, "output_tokens": 50}}'
EOF
chmod +x "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

# yq 의존 확인
command -v yq >/dev/null || { echo "SKIP: yq 미설치"; exit 0; }

echo "=== TEST 1: 첫 호출에 워크트리 생성 ==="
./.loops/loop.sh test-task-1
WT="$WORK_DIR/myproject-loops/test-task-1"
[[ -d "$WT" ]] || { echo "FAIL: 워크트리 미생성"; exit 1; }
[[ -f "$WT/CLAUDE.md" ]] || { echo "FAIL: CLAUDE.md 미복사"; exit 1; }
[[ -f "$WT/.loop/PROMPT.md" ]] || { echo "FAIL: PROMPT.md 미시드"; exit 1; }
[[ -f "$WT/.loop/PLAN.md" ]] || { echo "FAIL: PLAN.md 미시드"; exit 1; }

# .git/info/exclude 검증 — git rev-parse --git-dir로 정확 경로
WT_GITDIR=$(git -C "$WT" rev-parse --git-dir)
grep -q "^CLAUDE.md$" "$WT_GITDIR/info/exclude" || { echo "FAIL: exclude에 CLAUDE.md 없음"; exit 1; }
grep -q "^.loop/$" "$WT_GITDIR/info/exclude" || { echo "FAIL: exclude에 .loop/ 없음"; exit 1; }
echo "OK"

echo "=== TEST 2: 두 번째 호출에 한 이터 실행 (mock claude) ==="
# PROMPT.md에 최소 frontmatter 채움
cat > "$WT/.loop/PROMPT.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Test PROMPT
EOF

# mock claude가 DONE 파일을 생성하므로 루프가 DONE 신호로 정상 종료
# archive_meta_files가 호출되면서 이터 로그는 .loop/iterations/에 남음
MAX_ITERATIONS=10 WALL_CLOCK_MINUTES=10 ./.loops/loop.sh test-task-1
[[ -f "$WT/.loop/iterations/1.log" ]] || { echo "FAIL: 이터 로그 미생성"; exit 1; }
echo "OK"

echo "=== TEST 3: 같은 task-id 이중 호출 차단 ==="
# 락 파일을 미리 만들어두고 호출
mkdir -p .loops/locks
echo $$ > .loops/locks/test-task-1.lock
set +e
output=$(MAX_ITERATIONS=1 ./.loops/loop.sh test-task-1 2>&1)
result=$?
set -e
rm -f .loops/locks/test-task-1.lock
[[ $result -ne 0 ]] || { echo "FAIL: 이중 호출이 차단되지 않음"; exit 1; }
echo "$output" | grep -q "이미 동작 중" || { echo "FAIL: 락 메시지 누락"; exit 1; }
echo "OK"

echo "=== TEST 4: 슬래시 task-id (Layer 2 호환) ==="
./.loops/loop.sh "goal-x/sub-task" > /dev/null 2>&1 || true
WT2="$WORK_DIR/myproject-loops/goal-x/sub-task"
[[ -d "$WT2" ]] || { echo "FAIL: 슬래시 task-id 워크트리 미생성"; exit 1; }
# 락 파일명 sanitize 확인 (슬래시가 -로 치환)
[[ ! -d ".loops/locks/goal-x" ]] || { echo "FAIL: 락 디렉토리에 슬래시 잔존"; exit 1; }
# (락 파일은 호출 종료 시 trap으로 정리됨)
echo "OK"

echo ""
echo "=== 모든 테스트 통과 ==="
