#!/usr/bin/env bash
# loop.sh 통합 테스트 (subcommand 기반)
# claude CLI를 mock으로 대체해 subcommand·워크트리 생성·락·게이트 분기를 검증

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

echo "=== TEST 1: prepare 명령으로 PROMPT.md 생성 ==="
./.loops/loop.sh prepare test-task-1
LOOPS_TASK_DIR="$PROJECT/.loops/test-task-1"
[[ -d "$LOOPS_TASK_DIR" ]] || { echo "FAIL: .loops/test-task-1/ 디렉토리 미생성"; exit 1; }
[[ -f "$LOOPS_TASK_DIR/PROMPT.md" ]] || { echo "FAIL: .loops/test-task-1/PROMPT.md 미생성"; exit 1; }
# 이미 준비된 상태에서 재실행하면 오류
set +e
output=$(./.loops/loop.sh prepare test-task-1 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 이미 준비된 task에 prepare가 성공하면 안 됨"; exit 1; }
echo "$output" | grep -q "이미 준비되어 있습니다" || { echo "FAIL: 이미 준비 메시지 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 2: start 전 prepare 안 하면 거부 ==="
set +e
output=$(./.loops/loop.sh start test-task-unprepared 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: prepare 없이 start가 성공하면 안 됨"; exit 1; }
echo "$output" | grep -q "PROMPT.md가 없습니다\|prepare" || { echo "FAIL: prepare 안내 메시지 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 3: start로 워크트리 생성 + 1 이터 (mock claude로 즉시 DONE) ==="
# PROMPT.md의 placeholder를 채움
PROMPT_FILE="$LOOPS_TASK_DIR/PROMPT.md"
# placeholder를 실제 값으로 치환
sed -i.bak \
  -e 's/{{task_description}}/Test task/g' \
  -e 's/{{acceptance_criteria}}/All tests pass/g' \
  -e 's/{{scope_in}}/src\//g' \
  -e 's/{{scope_out}}/none/g' \
  -e 's/{{verify_command}}/true/g' \
  "$PROMPT_FILE"
rm -f "$PROMPT_FILE.bak"

# frontmatter의 verify도 실행 가능한 명령으로 교체
cat > "$PROMPT_FILE" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Test PROMPT

## 작업 정의 (불변)

### 무엇을 만들 것인가
Test task

### 수용 기준
All tests pass

### 범위
포함:
src/

비-목표 / 제외:
none

### 검증
true
EOF

WT="$WORK_DIR/myproject-loops/test-task-1"
MAX_ITERATIONS=10 WALL_CLOCK_MINUTES=10 ./.loops/loop.sh start test-task-1
[[ -d "$WT" ]] || { echo "FAIL: 워크트리 미생성"; exit 1; }
[[ -f "$WT/CLAUDE.md" ]] || { echo "FAIL: CLAUDE.md 미복사"; exit 1; }
[[ -f "$WT/.loop/PROMPT.md" ]] || { echo "FAIL: PROMPT.md 미복사"; exit 1; }
[[ -f "$WT/.loop/PLAN.md" ]] || { echo "FAIL: PLAN.md 미시드"; exit 1; }
[[ -f "$WT/.loop/iterations/1.log" ]] || { echo "FAIL: 이터 로그 미생성"; exit 1; }

# .git/info/exclude 검증
WT_GITDIR=$(git -C "$WT" rev-parse --git-dir)
grep -q "^CLAUDE.md$" "$WT_GITDIR/info/exclude" || { echo "FAIL: exclude에 CLAUDE.md 없음"; exit 1; }
grep -q "^.loop/$" "$WT_GITDIR/info/exclude" || { echo "FAIL: exclude에 .loop/ 없음"; exit 1; }
echo "OK"

echo "=== TEST 4: 같은 task-id 이중 start 차단 (락) ==="
# 락 파일을 미리 만들어두고 호출
mkdir -p .loops/locks
echo $$ > .loops/locks/test-task-1.lock
set +e
output=$(MAX_ITERATIONS=1 ./.loops/loop.sh start test-task-1 2>&1)
result=$?
set -e
rm -f .loops/locks/test-task-1.lock
[[ $result -ne 0 ]] || { echo "FAIL: 이중 호출이 차단되지 않음"; exit 1; }
echo "$output" | grep -q "이미 동작 중" || { echo "FAIL: 락 메시지 누락. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 5: 슬래시 task-id (Layer 2 호환) ==="
# prepare 후 start
./.loops/loop.sh prepare "goal-x/sub-task" > /dev/null 2>&1
SLASH_PROMPT="$PROJECT/.loops/goal-x/sub-task/PROMPT.md"
[[ -f "$SLASH_PROMPT" ]] || { echo "FAIL: 슬래시 task-id prepare 실패"; exit 1; }

# placeholder 채움
cat > "$SLASH_PROMPT" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Test Slash Task
EOF

MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 ./.loops/loop.sh start "goal-x/sub-task" > /dev/null 2>&1 || true
WT2="$WORK_DIR/myproject-loops/goal-x/sub-task"
[[ -d "$WT2" ]] || { echo "FAIL: 슬래시 task-id 워크트리 미생성"; exit 1; }
# 락 파일명 sanitize 확인 (슬래시가 -로 치환)
[[ ! -d ".loops/locks/goal-x" ]] || { echo "FAIL: 락 디렉토리에 슬래시 잔존"; exit 1; }
echo "OK"

echo "=== TEST 6: status가 적절한 상태 반환 ==="
# test-task-1 은 DONE(워크트리에 DONE 파일 있음), goal-x/sub-task는 idle
output=$(./.loops/loop.sh status 2>&1)
echo "$output" | grep -q "test-task-1" || { echo "FAIL: status에 test-task-1 없음"; exit 1; }
echo "$output" | grep -q "done\|idle\|running\|prepared\|archived\|escalated" || { echo "FAIL: 상태 값이 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 7: cleanup이 DONE 없으면 거부 (--force 없이) ==="
# DONE 없는 워크트리를 명시적으로 준비
./.loops/loop.sh prepare "no-done-task" > /dev/null 2>&1
cat > "$PROJECT/.loops/no-done-task/PROMPT.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# No Done Task
EOF
# 워크트리만 만들고 DONE은 생성하지 않는 mock
NO_DONE_MOCK="$WORK_DIR/no-done-mock-bin"
mkdir -p "$NO_DONE_MOCK"
cat > "$NO_DONE_MOCK/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
# DONE 파일 생성 안 함
echo '{"result": "mock-no-done", "usage": {"input_tokens": 10, "output_tokens": 5}}'
exit 0
MOCKEOF
chmod +x "$NO_DONE_MOCK/claude"

WT3="$WORK_DIR/myproject-loops/no-done-task"
# no-done mock으로 이터 1회 실행 후 자연 종료 (MAX_ITERATIONS=1)
PATH="$NO_DONE_MOCK:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 ./.loops/loop.sh start "no-done-task" 2>&1 || true
[[ -d "$WT3" ]] || { echo "FAIL: no-done-task 워크트리 미생성"; exit 1; }
[[ ! -f "$WT3/DONE" ]] || { echo "FAIL: mock이 DONE 파일을 만들면 안 됨"; exit 1; }

set +e
output=$(./.loops/loop.sh cleanup "no-done-task" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: DONE 없는 cleanup이 성공하면 안 됨"; exit 1; }
echo "$output" | grep -q "DONE\|--force" || { echo "FAIL: DONE/--force 메시지 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 8: cleanup --force로 정리 ==="
# goal-x/sub-task 워크트리를 --force로 정리 (DONE 파일 있음 — mock이 생성)
./.loops/loop.sh cleanup "goal-x/sub-task" --force
[[ ! -d "$WT2" ]] || { echo "FAIL: cleanup 후 워크트리가 남아있음"; exit 1; }
# 아카이브 확인: .loops/goal-x/sub-task/ 에 디렉토리가 남아있어야 함
ARCHIVED_DIR="$PROJECT/.loops/goal-x/sub-task"
[[ -d "$ARCHIVED_DIR" ]] || { echo "FAIL: cleanup 후 .loops/<task-id>/ 디렉토리 없음"; exit 1; }

# no-done-task도 --force로 정리
./.loops/loop.sh cleanup "no-done-task" --force
[[ ! -d "$WT3" ]] || { echo "FAIL: no-done-task cleanup 후 워크트리가 남아있음"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 테스트 통과 ==="
