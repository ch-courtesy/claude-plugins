#!/usr/bin/env bash
# loop.sh 통합 테스트 (subcommand 기반)
# claude CLI를 mock으로 대체해 subcommand·워크트리 생성·락·게이트 분기를 검증

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_REFS="$REPO_ROOT/plugins/autopilot/skills/loop/references"
LOOP_SH_SRC="$SKILL_REFS/loop.sh"
CONSTITUTION_SRC="$SKILL_REFS/constitution.md"

# 기대 산출물 검사
[[ -x "$LOOP_SH_SRC" ]] || { echo "FAIL: loop.sh가 실행 가능하지 않음"; exit 1; }
[[ -f "$CONSTITUTION_SRC" ]] || { echo "FAIL: constitution.md 부재"; exit 1; }

# 임시 작업공간 (테스트 격리)
WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2064  # $WORK_DIR은 trap-set 시점에 확정된 값으로 고정 의도
trap "rm -rf $WORK_DIR" EXIT

# 가짜 프로젝트 git init
PROJECT="$WORK_DIR/myproject"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init -q
git config user.email "test@example.com"
git config user.name "Test"
git commit --allow-empty -m "initial" -q

# .loops/ 런타임 디렉토리만 생성 (새 아키텍처: 스킬 패키지에서 직접 호출)
mkdir -p .loops/locks
# git은 빈 디렉토리를 추적하지 않으므로 .gitkeep 추가
touch .loops/locks/.gitkeep
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

# loop.sh 호출 헬퍼 (새 아키텍처: SKILL_REFS에서 직접 호출)
loop() {
  bash "$LOOP_SH_SRC" "$@"
}

echo "=== TEST 1: prepare 명령으로 SPEC.md 생성 ==="
loop prepare test-task-1
LOOPS_TASK_DIR="$PROJECT/.loops/test-task-1"
[[ -d "$LOOPS_TASK_DIR" ]] || { echo "FAIL: .loops/test-task-1/ 디렉토리 미생성"; exit 1; }
[[ -f "$LOOPS_TASK_DIR/SPEC.md" ]] || { echo "FAIL: .loops/test-task-1/SPEC.md 미생성"; exit 1; }
# 이미 준비된 상태에서 재실행하면 오류
set +e
output=$(loop prepare test-task-1 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 이미 준비된 task에 prepare가 성공하면 안 됨"; exit 1; }
echo "$output" | grep -q "이미 준비되어 있습니다" || { echo "FAIL: 이미 준비 메시지 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 2: start 전 prepare 안 하면 거부 ==="
set +e
output=$(loop start test-task-unprepared 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: prepare 없이 start가 성공하면 안 됨"; exit 1; }
echo "$output" | grep -q "SPEC.md가 없습니다\|prepare" || { echo "FAIL: prepare 안내 메시지 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 3: start로 워크트리 생성 + 1 이터 (mock claude로 즉시 DONE) ==="
# SPEC.md의 placeholder를 채움 (frontmatter의 verify도 실행 가능한 명령으로)
SPEC_FILE="$LOOPS_TASK_DIR/SPEC.md"
cat > "$SPEC_FILE" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Test SPEC

## 무엇을 만들 것인가
Test task

## 수용 기준
All tests pass

## 범위
포함:
src/

비-목표 / 제외:
none

## 검증
true
EOF

WT="$WORK_DIR/myproject-loops/test-task-1"
MAX_ITERATIONS=10 WALL_CLOCK_MINUTES=10 loop start test-task-1
[[ -d "$WT" ]] || { echo "FAIL: 워크트리 미생성"; exit 1; }
[[ -f "$WT/CLAUDE.md" ]] || { echo "FAIL: CLAUDE.md 미복사"; exit 1; }
[[ -f "$WT/.loop/SPEC.md" ]] || { echo "FAIL: SPEC.md 미복사"; exit 1; }
[[ -f "$WT/.loop/PLAN.md" ]] || { echo "FAIL: PLAN.md 미시드"; exit 1; }
[[ -f "$WT/.loop/iterations/1.log" ]] || { echo "FAIL: 이터 로그 미생성"; exit 1; }

# .git/info/exclude 검증
WT_GITDIR=$(git -C "$WT" rev-parse --git-dir)
grep -q "^CLAUDE.md$" "$WT_GITDIR/info/exclude" || { echo "FAIL: exclude에 CLAUDE.md 없음"; exit 1; }
grep -q "^.loop/$" "$WT_GITDIR/info/exclude" || { echo "FAIL: exclude에 .loop/ 없음"; exit 1; }

# CLAUDE.md가 constitution.md 내용과 동일한지 확인
diff "$CONSTITUTION_SRC" "$WT/CLAUDE.md" >/dev/null || { echo "FAIL: CLAUDE.md가 constitution.md와 다름"; exit 1; }
echo "OK"

echo "=== TEST 4: 같은 task-id 이중 start 차단 (락) ==="
# 락 파일을 미리 만들어두고 호출
mkdir -p .loops/locks
echo $$ > .loops/locks/test-task-1.lock
set +e
output=$(MAX_ITERATIONS=1 loop start test-task-1 2>&1)
result=$?
set -e
rm -f .loops/locks/test-task-1.lock
[[ $result -ne 0 ]] || { echo "FAIL: 이중 호출이 차단되지 않음"; exit 1; }
echo "$output" | grep -q "이미 동작 중" || { echo "FAIL: 락 메시지 누락. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 5: 슬래시 task-id (Layer 2 호환) ==="
# prepare 후 start
loop prepare "goal-x/sub-task" > /dev/null 2>&1
SLASH_SPEC="$PROJECT/.loops/goal-x/sub-task/SPEC.md"
[[ -f "$SLASH_SPEC" ]] || { echo "FAIL: 슬래시 task-id prepare 실패"; exit 1; }

# placeholder 채움
cat > "$SLASH_SPEC" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Test Slash Task
EOF

MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 loop start "goal-x/sub-task" > /dev/null 2>&1 || true
WT2="$WORK_DIR/myproject-loops/goal-x/sub-task"
[[ -d "$WT2" ]] || { echo "FAIL: 슬래시 task-id 워크트리 미생성"; exit 1; }
# 락 파일명 sanitize 확인 (슬래시가 -로 치환)
[[ ! -d ".loops/locks/goal-x" ]] || { echo "FAIL: 락 디렉토리에 슬래시 잔존"; exit 1; }
echo "OK"

echo "=== TEST 6: status가 적절한 상태 반환 ==="
# test-task-1 은 DONE(워크트리에 DONE 파일 있음), goal-x/sub-task는 idle
output=$(loop status 2>&1)
echo "$output" | grep -q "test-task-1" || { echo "FAIL: status에 test-task-1 없음"; exit 1; }
echo "$output" | grep -q "done\|idle\|running\|prepared\|archived\|escalated" || { echo "FAIL: 상태 값이 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 7: cleanup이 DONE 없으면 거부 (--force 없이) ==="
# DONE 없는 워크트리를 명시적으로 준비
loop prepare "no-done-task" > /dev/null 2>&1
cat > "$PROJECT/.loops/no-done-task/SPEC.md" <<'EOF'
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
PATH="$NO_DONE_MOCK:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 loop start "no-done-task" 2>&1 || true
[[ -d "$WT3" ]] || { echo "FAIL: no-done-task 워크트리 미생성"; exit 1; }
[[ ! -f "$WT3/DONE" ]] || { echo "FAIL: mock이 DONE 파일을 만들면 안 됨"; exit 1; }

set +e
output=$(loop cleanup "no-done-task" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: DONE 없는 cleanup이 성공하면 안 됨"; exit 1; }
echo "$output" | grep -q "DONE\|--force" || { echo "FAIL: DONE/--force 메시지 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 8: cleanup --force로 정리 ==="
# goal-x/sub-task 워크트리를 --force로 정리 (DONE 파일 있음 — mock이 생성)
loop cleanup "goal-x/sub-task" --force
[[ ! -d "$WT2" ]] || { echo "FAIL: cleanup 후 워크트리가 남아있음"; exit 1; }
# 아카이브 확인: .loops/goal-x/sub-task/ 에 디렉토리가 남아있어야 함
ARCHIVED_DIR="$PROJECT/.loops/goal-x/sub-task"
[[ -d "$ARCHIVED_DIR" ]] || { echo "FAIL: cleanup 후 .loops/<task-id>/ 디렉토리 없음"; exit 1; }

# no-done-task도 --force로 정리
loop cleanup "no-done-task" --force
[[ ! -d "$WT3" ]] || { echo "FAIL: no-done-task cleanup 후 워크트리가 남아있음"; exit 1; }
echo "OK"

echo "=== TEST 9: --spec 외부 파일 전달 ==="
# 임시 외부 SPEC 파일 생성
EXTERNAL_SPEC="$WORK_DIR/external-spec.md"
cat > "$EXTERNAL_SPEC" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# External SPEC Task

## 무엇을 만들 것인가
External spec test

## 수용 기준
All pass

## 범위
포함:
src/

비-목표 / 제외:
none

## 검증
true
EOF

# --spec 플래그로 start (prepare 없이)
SPEC_TASK_ID="spec-flag-task"
MAX_ITERATIONS=10 WALL_CLOCK_MINUTES=10 loop start "$SPEC_TASK_ID" --spec "$EXTERNAL_SPEC"

# .loops/<id>/SPEC.md로 복사 확인
[[ -f "$PROJECT/.loops/$SPEC_TASK_ID/SPEC.md" ]] || { echo "FAIL: --spec 복사 후 .loops/<id>/SPEC.md 미생성"; exit 1; }
# 워크트리에도 .loop/SPEC.md 복사 확인
WT_SPEC="$WORK_DIR/myproject-loops/$SPEC_TASK_ID"
[[ -f "$WT_SPEC/.loop/SPEC.md" ]] || { echo "FAIL: 워크트리 .loop/SPEC.md 미복사"; exit 1; }
echo "OK"

echo "=== TEST 10: 빈 SPEC.md (placeholder 그대로) → start 거부 ==="
loop prepare "placeholder-task" > /dev/null 2>&1
# placeholder를 채우지 않은 채 start 호출
set +e
output=$(MAX_ITERATIONS=1 loop start "placeholder-task" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: placeholder가 남은 SPEC.md로 start가 성공하면 안 됨"; exit 1; }
echo "$output" | grep -qE '\{\{[^}]+\}\}|placeholder' \
  || { echo "FAIL: placeholder 이름이 에러 메시지에 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 11: frontmatter에 placeholder 잔존 → start 거부 ==="
# frontmatter 안의 verify 값도 placeholder로 남기면 placeholder 검사가 거부해야 함
loop prepare "bad-yaml-task" > /dev/null 2>&1
BAD_SPEC="$PROJECT/.loops/bad-yaml-task/SPEC.md"
cat > "$BAD_SPEC" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: '{{verify_command}}'
---

# Bad YAML Task

## 무엇을 만들 것인가
Test

## 수용 기준
Pass

## 범위
포함:
src/

비-목표 / 제외:
none

## 검증
{{verify_command}}
EOF
set +e
output=$(MAX_ITERATIONS=1 loop start "bad-yaml-task" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: frontmatter에 placeholder가 남은 SPEC.md로 start가 성공하면 안 됨"; exit 1; }
echo "$output" | grep -qE '\{\{[^}]+\}\}|placeholder' \
  || { echo "FAIL: 에러 메시지에 placeholder 이름 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 12: status 빈 .loops/ → 정상 출력 (안내 또는 빈 테이블) ==="
# 별도 격리 git repo 사용
EMPTY_PROJECT="$WORK_DIR/emptyproject"
mkdir -p "$EMPTY_PROJECT"
git -C "$EMPTY_PROJECT" init -q
git -C "$EMPTY_PROJECT" config user.email "test@example.com"
git -C "$EMPTY_PROJECT" config user.name "Test"
git -C "$EMPTY_PROJECT" commit --allow-empty -m "initial" -q
mkdir -p "$EMPTY_PROJECT/.loops/locks"
touch "$EMPTY_PROJECT/.loops/locks/.gitkeep"

set +e
output=$(cd "$EMPTY_PROJECT" && bash "$LOOP_SH_SRC" status 2>&1)
result=$?
set -e
[[ $result -eq 0 ]] || { echo "FAIL: 빈 .loops/에서 status가 0이 아닌 코드를 반환함 (got: $result). output: $output"; exit 1; }
echo "$output" | grep -qiE 'task|없습니다|No' \
  || { echo "FAIL: 빈 .loops/에서 status 출력에 안내 문구 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 13: cleanup 워크트리 부재 → 적절한 에러 ==="
# task 디렉토리는 있지만 워크트리가 없는 상태 (prepare만 한 경우)
loop prepare "no-wt-task" > /dev/null 2>&1
NO_WT_SPEC="$PROJECT/.loops/no-wt-task/SPEC.md"
cat > "$NO_WT_SPEC" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# No Worktree Task
EOF
# worktree를 만들지 않고 바로 cleanup 호출
set +e
output=$(loop cleanup "no-wt-task" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 워크트리가 없는데 cleanup이 성공하면 안 됨"; exit 1; }
echo "$output" | grep -qiE '워크트리|worktree' \
  || { echo "FAIL: 워크트리 부재 에러 메시지 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 14: 매우 긴 task-id (50자) → 워크트리 경로 안전 ==="
LONG_ID="abcdefghij1234567890abcdefghij1234567890abcdefghij"  # 50자
loop prepare "$LONG_ID" > /dev/null 2>&1
LONG_SPEC="$PROJECT/.loops/$LONG_ID/SPEC.md"
cat > "$LONG_SPEC" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Long Task-ID Task
EOF
MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 loop start "$LONG_ID" > /dev/null 2>&1
WT_LONG="$WORK_DIR/myproject-loops/$LONG_ID"
[[ -d "$WT_LONG" ]] || { echo "FAIL: 긴 task-id 워크트리 미생성"; exit 1; }
[[ -f "$WT_LONG/.loop/iterations/1.log" ]] || { echo "FAIL: 긴 task-id 이터 로그 미생성"; exit 1; }
loop cleanup "$LONG_ID" --force > /dev/null 2>&1
[[ ! -d "$WT_LONG" ]] || { echo "FAIL: 긴 task-id cleanup 후 워크트리가 남아있음"; exit 1; }
echo "OK"

echo "=== TEST 15: Multi-iteration mock — 3회 이터 후 DONE ==="
MULTI_TASK="multi-iter-task"
loop prepare "$MULTI_TASK" > /dev/null 2>&1
cat > "$PROJECT/.loops/$MULTI_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Multi-Iteration Task
EOF

# 카운터 파일 초기화
COUNTER_FILE="$WORK_DIR/iter-count.txt"
echo "0" > "$COUNTER_FILE"
export COUNTER_FILE_PATH="$COUNTER_FILE"

# multi-iter mock: 호출 횟수를 파일에 기록하고 3회째에 DONE 생성
MULTI_MOCK_BIN="$WORK_DIR/multi-mock-bin"
mkdir -p "$MULTI_MOCK_BIN"
cat > "$MULTI_MOCK_BIN/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null  # stdin 소비
COUNTER_FILE="${COUNTER_FILE_PATH:-/tmp/iter-count.txt}"
n=$(cat "$COUNTER_FILE")
n=$((n + 1))
echo "$n" > "$COUNTER_FILE"
if [[ $n -ge 3 ]]; then
  touch DONE
fi
echo '{"result": "mock iter '"$n"'", "usage": {"input_tokens": 100, "output_tokens": 50}}'
MOCKEOF
chmod +x "$MULTI_MOCK_BIN/claude"

WT_MULTI="$WORK_DIR/myproject-loops/$MULTI_TASK"
PATH="$MULTI_MOCK_BIN:$PATH" MAX_ITERATIONS=10 WALL_CLOCK_MINUTES=10 loop start "$MULTI_TASK"
# 3회 이터 로그 확인
[[ -f "$WT_MULTI/.loop/iterations/1.log" ]] || { echo "FAIL: iter 1.log 없음"; exit 1; }
[[ -f "$WT_MULTI/.loop/iterations/2.log" ]] || { echo "FAIL: iter 2.log 없음"; exit 1; }
[[ -f "$WT_MULTI/.loop/iterations/3.log" ]] || { echo "FAIL: iter 3.log 없음"; exit 1; }
# DONE 파일 확인
[[ -f "$WT_MULTI/DONE" ]] || { echo "FAIL: DONE 파일 없음"; exit 1; }
# cleanup 후 archive 메타 파일 확인 (mock이 커밋하지 않으므로 --force 사용)
loop cleanup "$MULTI_TASK" --force
MULTI_LOOPS_DIR="$PROJECT/.loops/$MULTI_TASK"
[[ -d "$MULTI_LOOPS_DIR" ]] || { echo "FAIL: archive 디렉토리 없음"; exit 1; }
[[ -f "$MULTI_LOOPS_DIR/PLAN.md" ]] || { echo "FAIL: archive PLAN.md 없음"; exit 1; }
echo "OK"

echo "=== TEST 16: scope 게이트가 framework 파일(.loop/*·CLAUDE.md·DONE) 무시 ==="
# 회귀 테스트: 모델이 메모리 파일과 함께 commit해도 scope 게이트가 발동 안 해야
# (autopilot-smoke-STREAK 시나리오에서 발견된 버그의 regression 보호)

SCOPE_TASK="scope-framework-test"
loop prepare "$SCOPE_TASK" > /dev/null 2>&1
SCOPE_TASK_DIR="$PROJECT/.loops/$SCOPE_TASK"

# 좁은 scope.include — app/만 (.loop/는 명시 안 함)
cat > "$SCOPE_TASK_DIR/SPEC.md" <<'EOF'
---
scope:
  include:
    - "app/**"
  exclude:
    - "rules/**"
    - "tests/**"
    - "vendor/**"
verify: 'true'
---

# Scope Framework Test

## 무엇을 만들 것인가
scope.include = ["app/**"] 만 — framework 파일은 명시 안 함.

## 수용 기준
- app/main.py 생성
EOF

# scope 게이트가 framework 파일을 무시하는지 검증하는 mock
# mock이: 1) app/main.py 생성+commit, 2) .loop/PLAN.md 변경+commit (framework 파일도 함께)
# 그 후 scope 게이트가 .loop/PLAN.md를 위반으로 잡지 않아야
SCOPE_MOCK="$WORK_DIR/scope-mock-bin"
mkdir -p "$SCOPE_MOCK"
cat > "$SCOPE_MOCK/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
# 1. app/main.py 생성
mkdir -p app
echo "print('hello')" > app/main.py
# 2. 메모리 파일도 변경 (시나리오 재현)
echo "# updated" >> .loop/PLAN.md
# 3. 모두 stage + commit (memory file 포함, .git/info/exclude를 -f로 우회)
git add -f .loop/PLAN.md
git add app/main.py
git commit -q -m "feat: hello + plan update" --no-verify 2>/dev/null
# DONE 작성해 단일 이터 종료
touch DONE
echo '{"result": "scope test mock", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$SCOPE_MOCK/claude"

WT_SCOPE="$WORK_DIR/myproject-loops/$SCOPE_TASK"
set +e
output=$(PATH="$SCOPE_MOCK:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 loop start "$SCOPE_TASK" 2>&1)
result=$?
set -e
# 게이트가 .loop/PLAN.md를 잡지 않아 정상 진행 → DONE 신호로 정상 종료(exit 0)
[[ $result -eq 0 ]] || { echo "FAIL: scope 게이트가 framework 파일을 위반으로 잡음 (regression). exit=$result"; echo "$output" | tail -10; exit 1; }
[[ -f "$WT_SCOPE/DONE" ]] || { echo "FAIL: DONE 파일 미생성 (정상 종료 안 됨)"; exit 1; }
echo "$output" | grep -q "Scope 위반" && { echo "FAIL: scope 게이트가 framework 파일을 잡음 (regression)"; exit 1; }
loop cleanup "$SCOPE_TASK" --force >/dev/null 2>&1
echo "OK"

echo ""
echo "=== 모든 테스트 통과 ==="
