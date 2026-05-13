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

# 빈 baseline commit (nested layout에서는 첫 호출 setup이 .gitignore 자동 관리)
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
# SPEC 103 AC1: PR phase가 default로 실행됨. 본 파일의 테스트는 loop driver 본체를
# 검증하며 PR phase는 검증 대상이 아니므로(별도 test-loop-pr-phase.sh가 담당), `start`
# 호출 시 `--no-pr` 플래그를 자동 주입해 gh·origin 미설치 환경에서도 안정 동작하게 한다.
loop() {
  if [[ "${1:-}" == "start" ]]; then
    local sub="$1"
    shift
    bash "$LOOP_SH_SRC" "$sub" "$@" --no-pr
  else
    bash "$LOOP_SH_SRC" "$@"
  fi
}

echo "=== TEST 1: prepare는 spec 스킬로 안내하는 스텁 ==="
set +e
output=$(loop prepare test-task-1 2>&1)
result=$?
set -e
# 스텁이므로 0이 아닌 exit + 안내 메시지
[[ $result -ne 0 ]] || { echo "FAIL: 스텁이 0 exit으로 끝남 (사용자가 spec 스킬로 가도록 유도해야)"; exit 1; }
echo "$output" | grep -q "spec\|이전" || { echo "FAIL: spec 스킬 안내 없음. got: $output"; exit 1; }
# .loops 디렉터리·SPEC.md 미생성 확인
[[ ! -d "$PROJECT/milestones/regular/loops/test-task-1" ]] || { echo "FAIL: 스텁이 디렉터리 만들면 안 됨"; exit 1; }
echo "OK"

echo "=== TEST 2: SPEC.md가 없으면 start 거부 ==="
set +e
output=$(loop start test-task-unprepared 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: prepare 없이 start가 성공하면 안 됨"; exit 1; }
echo "$output" | grep -q "SPEC.md가 없습니다" || { echo "FAIL: SPEC.md 없음 안내 메시지 없음. got: $output"; exit 1; }
echo "OK"

LOOPS_TASK_DIR="$PROJECT/milestones/regular/loops/test-task-1"
mkdir -p "$LOOPS_TASK_DIR"
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

WT="$PROJECT/milestones/regular/loops/test-task-1/.worktree"
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
# 락 파일을 미리 만들어두고 호출 (새 nested 경로)
LOCK_FILE_4="$PROJECT/milestones/regular/loops/test-task-1/.lock"
mkdir -p "$(dirname "$LOCK_FILE_4")"
echo $$ > "$LOCK_FILE_4"
set +e
output=$(MAX_ITERATIONS=1 loop start test-task-1 2>&1)
result=$?
set -e
rm -f "$LOCK_FILE_4"
[[ $result -ne 0 ]] || { echo "FAIL: 이중 호출이 차단되지 않음"; exit 1; }
echo "$output" | grep -q "이미 동작 중" || { echo "FAIL: 락 메시지 누락. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 5: 슬래시 task-id (Layer 2 호환) ==="
# 디렉터리 명시적 생성 (prepare 스텁화 이후)
mkdir -p "$PROJECT/milestones/goal-x/loops/sub-task"
SLASH_SPEC="$PROJECT/milestones/goal-x/loops/sub-task/SPEC.md"

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
WT2="$PROJECT/milestones/goal-x/loops/sub-task/.worktree"
[[ -d "$WT2" ]] || { echo "FAIL: 슬래시 task-id 워크트리 미생성"; exit 1; }
# 새 nested 정책: 락은 milestones/<m>/loops/<c>/.lock — 디렉터리 구조가 자연스럽게 분리
[[ ! -d "$PROJECT/.loops" ]] || { echo "FAIL: 새 정책인데 .loops/ 디렉토리가 생성됨"; exit 1; }
echo "OK"

echo "=== TEST 6: status가 적절한 상태 반환 ==="
# test-task-1 은 DONE(워크트리에 DONE 파일 있음), goal-x/sub-task는 idle
output=$(loop status 2>&1)
echo "$output" | grep -q "test-task-1" || { echo "FAIL: status에 test-task-1 없음"; exit 1; }
echo "$output" | grep -q "done\|idle\|running\|prepared\|archived\|escalated" || { echo "FAIL: 상태 값이 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 7: cleanup이 DONE 없으면 거부 (--force 없이) ==="
# DONE 없는 워크트리를 명시적으로 준비 (prepare 스텁화 이후)
mkdir -p "$PROJECT/milestones/regular/loops/no-done-task"
cat > "$PROJECT/milestones/regular/loops/no-done-task/SPEC.md" <<'EOF'
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

WT3="$PROJECT/milestones/regular/loops/no-done-task/.worktree"
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
# 아카이브 확인: milestones/goal-x/loops/sub-task/ 에 메타 파일이 남아있어야 함
ARCHIVED_DIR="$PROJECT/milestones/goal-x/loops/sub-task"
[[ -d "$ARCHIVED_DIR" ]] || { echo "FAIL: cleanup 후 milestones/goal-x/loops/sub-task/ 디렉토리 없음"; exit 1; }

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

# milestones/regular/loops/<id>/SPEC.md로 복사 확인
[[ -f "$PROJECT/milestones/regular/loops/$SPEC_TASK_ID/SPEC.md" ]] || { echo "FAIL: --spec 복사 후 milestones/regular/loops/<id>/SPEC.md 미생성"; exit 1; }
# 워크트리에도 .loop/SPEC.md 복사 확인
WT_SPEC="$PROJECT/milestones/regular/loops/$SPEC_TASK_ID/.worktree"
[[ -f "$WT_SPEC/.loop/SPEC.md" ]] || { echo "FAIL: 워크트리 .loop/SPEC.md 미복사"; exit 1; }
echo "OK"

echo "=== TEST 10: 빈 SPEC.md (placeholder 그대로) → start 거부 ==="
# spec-template.md는 삭제됨(spec 스킬로 이관). 인라인으로 placeholder가 남은 SPEC.md 생성
mkdir -p "$PROJECT/milestones/regular/loops/placeholder-task"
cat > "$PROJECT/milestones/regular/loops/placeholder-task/SPEC.md" <<'SPEC_EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: '{{verify_command}}'
---

# {{task_title}}

## 목표

{{goal_description}}
SPEC_EOF
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
# prepare 스텁화 이후: 디렉터리 명시적 생성
mkdir -p "$PROJECT/milestones/regular/loops/bad-yaml-task"
BAD_SPEC="$PROJECT/milestones/regular/loops/bad-yaml-task/SPEC.md"
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

echo "=== TEST 12: status 빈 milestones/ → 정상 출력 (안내 또는 빈 테이블) ==="
# 별도 격리 git repo 사용
EMPTY_PROJECT="$WORK_DIR/emptyproject"
mkdir -p "$EMPTY_PROJECT"
git -C "$EMPTY_PROJECT" init -q
git -C "$EMPTY_PROJECT" config user.email "test@example.com"
git -C "$EMPTY_PROJECT" config user.name "Test"
git -C "$EMPTY_PROJECT" commit --allow-empty -m "initial" -q
# 새 정책: 빈 milestones/ 디렉터리만 (lock 디렉터리는 task 시작 시점에 nested 생성)
mkdir -p "$EMPTY_PROJECT/milestones"

set +e
output=$(cd "$EMPTY_PROJECT" && bash "$LOOP_SH_SRC" status 2>&1)
result=$?
set -e
[[ $result -eq 0 ]] || { echo "FAIL: 빈 milestones/에서 status가 0이 아닌 코드를 반환함 (got: $result). output: $output"; exit 1; }
echo "$output" | grep -qiE 'task|없습니다|No' \
  || { echo "FAIL: 빈 milestones/에서 status 출력에 안내 문구 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 13: cleanup 워크트리 부재 → 적절한 에러 ==="
# task 디렉토리는 있지만 워크트리가 없는 상태 (prepare 스텁화 이후: 명시적 생성)
mkdir -p "$PROJECT/milestones/regular/loops/no-wt-task"
NO_WT_SPEC="$PROJECT/milestones/regular/loops/no-wt-task/SPEC.md"
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
mkdir -p "$PROJECT/milestones/regular/loops/$LONG_ID"
LONG_SPEC="$PROJECT/milestones/regular/loops/$LONG_ID/SPEC.md"
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
WT_LONG="$PROJECT/milestones/regular/loops/$LONG_ID/.worktree"
[[ -d "$WT_LONG" ]] || { echo "FAIL: 긴 task-id 워크트리 미생성"; exit 1; }
[[ -f "$WT_LONG/.loop/iterations/1.log" ]] || { echo "FAIL: 긴 task-id 이터 로그 미생성"; exit 1; }
loop cleanup "$LONG_ID" --force > /dev/null 2>&1
[[ ! -d "$WT_LONG" ]] || { echo "FAIL: 긴 task-id cleanup 후 워크트리가 남아있음"; exit 1; }
echo "OK"

echo "=== TEST 15: Multi-iteration mock — 3회 이터 후 DONE ==="
MULTI_TASK="multi-iter-task"
mkdir -p "$PROJECT/milestones/regular/loops/$MULTI_TASK"
cat > "$PROJECT/milestones/regular/loops/$MULTI_TASK/SPEC.md" <<'EOF'
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

WT_MULTI="$PROJECT/milestones/regular/loops/$MULTI_TASK/.worktree"
PATH="$MULTI_MOCK_BIN:$PATH" MAX_ITERATIONS=10 WALL_CLOCK_MINUTES=10 loop start "$MULTI_TASK"
# 3회 이터 로그 확인
[[ -f "$WT_MULTI/.loop/iterations/1.log" ]] || { echo "FAIL: iter 1.log 없음"; exit 1; }
[[ -f "$WT_MULTI/.loop/iterations/2.log" ]] || { echo "FAIL: iter 2.log 없음"; exit 1; }
[[ -f "$WT_MULTI/.loop/iterations/3.log" ]] || { echo "FAIL: iter 3.log 없음"; exit 1; }
# DONE 파일 확인
[[ -f "$WT_MULTI/DONE" ]] || { echo "FAIL: DONE 파일 없음"; exit 1; }
# cleanup 후 archive 메타 파일 확인 (mock이 커밋하지 않으므로 --force 사용)
loop cleanup "$MULTI_TASK" --force
MULTI_LOOPS_DIR="$PROJECT/milestones/regular/loops/$MULTI_TASK"
[[ -d "$MULTI_LOOPS_DIR" ]] || { echo "FAIL: archive 디렉토리 없음"; exit 1; }
[[ -f "$MULTI_LOOPS_DIR/PLAN.md" ]] || { echo "FAIL: archive PLAN.md 없음"; exit 1; }
echo "OK"

echo "=== TEST 16: scope 게이트가 framework 파일(.loop/*·CLAUDE.md·DONE) 무시 ==="
# 회귀 테스트: 모델이 메모리 파일과 함께 commit해도 scope 게이트가 발동 안 해야
# (autopilot-smoke-STREAK 시나리오에서 발견된 버그의 regression 보호)

SCOPE_TASK="scope-framework-test"
mkdir -p "$PROJECT/milestones/regular/loops/$SCOPE_TASK"
SCOPE_TASK_DIR="$PROJECT/milestones/regular/loops/$SCOPE_TASK"

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

WT_SCOPE="$PROJECT/milestones/regular/loops/$SCOPE_TASK/.worktree"
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

echo "=== TEST 17: 테스트 약화 게이트 (tests/** 해시 변경 감지) ==="
TEST17_TASK="gate-test-weakening"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST17_TASK"
cat > "$PROJECT/milestones/regular/loops/$TEST17_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Gate Test — Test Weakening
EOF

COUNTER17="$WORK_DIR/iter-count-17.txt"
echo "0" > "$COUNTER17"
export COUNTER17_PATH="$COUNTER17"

MOCK17="$WORK_DIR/mock17-bin"
mkdir -p "$MOCK17"
cat > "$MOCK17/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER17_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER17_PATH}"
if [[ $n -eq 1 ]]; then
  # 첫 번째 호출: tests/test_x.py 생성 + commit
  mkdir -p tests
  echo "def test_x(): pass" > tests/test_x.py
  git add tests/test_x.py
  git commit -q -m "test: add test_x"
else
  # 두 번째 호출: tests/test_x.py 삭제 + commit (테스트 약화)
  git rm -q tests/test_x.py
  git commit -q -m "remove: test_x"
fi
echo '{"result": "mock17", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK17/claude"

set +e
output17=$(PATH="$MOCK17:$PATH" MAX_ITERATIONS=5 WALL_CLOCK_MINUTES=5 loop start "$TEST17_TASK" 2>&1)
result17=$?
set -e
[[ $result17 -ne 0 ]] || { echo "FAIL: 테스트 약화 게이트가 halt하지 않음 (exit 0)"; exit 1; }
echo "$output17" | grep -q "HALT\|tests modified\|테스트 약화" \
  || { echo "FAIL: 테스트 약화 halt 메시지 없음. got: $output17"; exit 1; }
WT17="$PROJECT/milestones/regular/loops/$TEST17_TASK/.worktree"
[[ -f "$WT17/.loop/ESCALATION.md" ]] || { echo "FAIL: ESCALATION.md 미생성"; exit 1; }
loop cleanup "$TEST17_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 18: 의존성 변경 게이트 (manifest 해시 변경 감지) ==="
TEST18_TASK="gate-dep-change"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST18_TASK"
cat > "$PROJECT/milestones/regular/loops/$TEST18_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Gate Test — Dependency Change
EOF

COUNTER18="$WORK_DIR/iter-count-18.txt"
echo "0" > "$COUNTER18"
export COUNTER18_PATH="$COUNTER18"

MOCK18="$WORK_DIR/mock18-bin"
mkdir -p "$MOCK18"
cat > "$MOCK18/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER18_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER18_PATH}"
if [[ $n -eq 1 ]]; then
  # 첫 번째 호출: package.json 생성 + commit (초기 manifest)
  echo '{"name":"test","version":"1.0.0"}' > package.json
  git add package.json
  git commit -q -m "chore: add package.json"
else
  # 두 번째 호출: package.json 수정 + commit (의존성 변경)
  echo '{"name":"test","version":"1.0.0","dependencies":{"lodash":"^4.0.0"}}' > package.json
  git add package.json
  git commit -q -m "chore: add lodash dependency"
fi
echo '{"result": "mock18", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK18/claude"

set +e
output18=$(PATH="$MOCK18:$PATH" MAX_ITERATIONS=5 WALL_CLOCK_MINUTES=5 loop start "$TEST18_TASK" 2>&1)
result18=$?
set -e
[[ $result18 -ne 0 ]] || { echo "FAIL: 의존성 변경 게이트가 halt하지 않음 (exit 0)"; exit 1; }
echo "$output18" | grep -q "HALT\|deps modified\|의존성 변경" \
  || { echo "FAIL: 의존성 변경 halt 메시지 없음. got: $output18"; exit 1; }
WT18="$PROJECT/milestones/regular/loops/$TEST18_TASK/.worktree"
[[ -f "$WT18/.loop/ESCALATION.md" ]] || { echo "FAIL: ESCALATION.md 미생성"; exit 1; }
loop cleanup "$TEST18_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 19: suppressor 신규 추가 게이트 ==="
TEST19_TASK="gate-suppressor"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST19_TASK"
cat > "$PROJECT/milestones/regular/loops/$TEST19_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Gate Test — Suppressor
EOF

MOCK19="$WORK_DIR/mock19-bin"
mkdir -p "$MOCK19"
cat > "$MOCK19/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
# noqa 를 포함한 파일 생성 + commit (위반 즉시)
mkdir -p src
echo "x = 1  # noqa" > src/bad.py
git add src/bad.py
git commit -q -m "feat: add bad.py with suppressor"
echo '{"result": "mock19", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK19/claude"

set +e
output19=$(PATH="$MOCK19:$PATH" MAX_ITERATIONS=3 WALL_CLOCK_MINUTES=5 loop start "$TEST19_TASK" 2>&1)
result19=$?
set -e
[[ $result19 -ne 0 ]] || { echo "FAIL: suppressor 게이트가 halt하지 않음 (exit 0)"; exit 1; }
echo "$output19" | grep -q "HALT\|Suppressor" \
  || { echo "FAIL: suppressor halt 메시지 없음. got: $output19"; exit 1; }
WT19="$PROJECT/milestones/regular/loops/$TEST19_TASK/.worktree"
[[ -f "$WT19/.loop/ESCALATION.md" ]] || { echo "FAIL: ESCALATION.md 미생성"; exit 1; }
loop cleanup "$TEST19_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 20: fix:symptom streak 게이트 ==="
TEST20_TASK="gate-streak"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST20_TASK"
cat > "$PROJECT/milestones/regular/loops/$TEST20_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Gate Test — fix:symptom streak
EOF

COUNTER20="$WORK_DIR/iter-count-20.txt"
echo "0" > "$COUNTER20"
export COUNTER20_PATH="$COUNTER20"

MOCK20="$WORK_DIR/mock20-bin"
mkdir -p "$MOCK20"
cat > "$MOCK20/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER20_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER20_PATH}"
if [[ $n -eq 1 ]]; then
  # 첫 번째 호출: fix:symptom commit
  echo "patch1" > symptom1.txt
  git add symptom1.txt
  git commit -q -m "fix:symptom patch 1"
else
  # 두 번째 호출: 또 fix:symptom commit → streak 2회
  echo "patch2" > symptom2.txt
  git add symptom2.txt
  git commit -q -m "fix:symptom patch 2"
fi
echo '{"result": "mock20", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK20/claude"

set +e
output20=$(PATH="$MOCK20:$PATH" MAX_ITERATIONS=5 WALL_CLOCK_MINUTES=5 loop start "$TEST20_TASK" 2>&1)
result20=$?
set -e
[[ $result20 -ne 0 ]] || { echo "FAIL: fix:symptom streak 게이트가 halt하지 않음 (exit 0)"; exit 1; }
echo "$output20" | grep -q "HALT\|fix:symptom streak" \
  || { echo "FAIL: fix:symptom streak halt 메시지 없음. got: $output20"; exit 1; }
WT20="$PROJECT/milestones/regular/loops/$TEST20_TASK/.worktree"
[[ -f "$WT20/.loop/ESCALATION.md" ]] || { echo "FAIL: ESCALATION.md 미생성"; exit 1; }
loop cleanup "$TEST20_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 21: 진동 패턴 게이트 ==="
TEST21_TASK="gate-oscillation"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST21_TASK"
cat > "$PROJECT/milestones/regular/loops/$TEST21_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Gate Test — Oscillation
EOF

COUNTER21="$WORK_DIR/iter-count-21.txt"
echo "0" > "$COUNTER21"
export COUNTER21_PATH="$COUNTER21"

MOCK21="$WORK_DIR/mock21-bin"
mkdir -p "$MOCK21"
cat > "$MOCK21/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER21_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER21_PATH}"
if (( n % 2 == 1 )); then
  # 홀수 이터: file_x.txt 변경
  echo "state-$n" > file_x.txt
  git add file_x.txt
  git commit -q -m "chore: update file_x iter $n"
else
  # 짝수 이터: file_y.txt 변경 (다른 파일 셋 → 토글)
  echo "state-$n" > file_y.txt
  git add file_y.txt
  git commit -q -m "chore: update file_y iter $n"
fi
echo '{"result": "mock21", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK21/claude"

set +e
output21=$(PATH="$MOCK21:$PATH" MAX_ITERATIONS=10 WALL_CLOCK_MINUTES=5 loop start "$TEST21_TASK" 2>&1)
result21=$?
set -e
[[ $result21 -ne 0 ]] || { echo "FAIL: 진동 패턴 게이트가 halt하지 않음 (exit 0)"; exit 1; }
echo "$output21" | grep -q "HALT\|진동 패턴" \
  || { echo "FAIL: 진동 패턴 halt 메시지 없음. got: $output21"; exit 1; }
WT21="$PROJECT/milestones/regular/loops/$TEST21_TASK/.worktree"
[[ -f "$WT21/.loop/ESCALATION.md" ]] || { echo "FAIL: ESCALATION.md 미생성"; exit 1; }
loop cleanup "$TEST21_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 22: M1 — task-id에 '..' 포함 시 거부 (path traversal) ==="
# prepare는 deprecated stub이므로 task-id 검증을 안 함 — 실제 진입점만 검사
for sub in start status stop cleanup logs; do
  set +e
  output=$(loop "$sub" "../escape-task" 2>&1)
  result=$?
  set -e
  [[ $result -ne 0 ]] || { echo "FAIL: ${sub}가 '..' task-id를 받아들임"; exit 1; }
  echo "$output" | grep -q "path traversal\|'\\.\\.'" \
    || { echo "FAIL: ${sub}의 path traversal 거부 메시지 없음. got: $output"; exit 1; }
done
echo "OK"

echo "=== TEST 23: M4 — scope.include 빈 배열이면 start 거부 ==="
mkdir -p "$PROJECT/milestones/regular/loops/empty-scope-task"
cat > "$PROJECT/milestones/regular/loops/empty-scope-task/SPEC.md" <<'EOF'
---
scope:
  include: []
  exclude: []
verify: 'true'
---

# Empty Scope Task
EOF
set +e
output=$(MAX_ITERATIONS=1 loop start "empty-scope-task" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 빈 scope.include로 start가 성공하면 안 됨"; exit 1; }
echo "$output" | grep -q "scope.include.*비어\|최소 한 패턴" \
  || { echo "FAIL: 빈 scope 거부 메시지 없음. got: $output"; exit 1; }
echo "OK"

echo "=== TEST 24: M5 — stop on stale lock (PID 죽음) ==="
STALE_TASK="stale-lock-task"
STALE_LOCK_24="$PROJECT/milestones/regular/loops/$STALE_TASK/.lock"
mkdir -p "$(dirname "$STALE_LOCK_24")"
# 존재하지 않을 PID 사용 (sentinel — 절대 동작하지 않을 큰 PID)
echo "999999" > "$STALE_LOCK_24"
set +e
output=$(loop stop "$STALE_TASK" 2>&1)
result=$?
set -e
[[ $result -eq 0 ]] || { echo "FAIL: stale lock 정리에 실패 (exit $result). got: $output"; exit 1; }
echo "$output" | grep -q "stale lock\|살아있지 않음" \
  || { echo "FAIL: stale lock 경고 메시지 없음. got: $output"; exit 1; }
[[ ! -f "$STALE_LOCK_24" ]] \
  || { echo "FAIL: stale lock 파일이 정리되지 않음"; exit 1; }
echo "OK"

echo "=== TEST 25: M5 — stop on live PID (SIGTERM 처리) ==="
LIVE_TASK="live-pid-task"
# 잠시 자는 백그라운드 프로세스를 시작해 그 PID를 락 파일에 기록
sleep 30 &
LIVE_PID=$!
LIVE_LOCK_25="$PROJECT/milestones/regular/loops/$LIVE_TASK/.lock"
mkdir -p "$(dirname "$LIVE_LOCK_25")"
echo "$LIVE_PID" > "$LIVE_LOCK_25"

set +e
output=$(loop stop "$LIVE_TASK" 2>&1)
result=$?
set -e
# SIGTERM이 sleep을 즉시 종료시키므로 5초 대기 안에 정리 완료 → exit 0
[[ $result -eq 0 ]] || { echo "FAIL: live PID stop이 실패 (exit $result). got: $output"; exit 1; }
echo "$output" | grep -q "정상 정지\|시그널 전송" \
  || { echo "FAIL: stop 진행 메시지 없음. got: $output"; exit 1; }
[[ ! -f "$LIVE_LOCK_25" ]] \
  || { echo "FAIL: lock 파일이 정리되지 않음"; exit 1; }
# 프로세스가 실제로 죽었는지 확인 (이미 죽었으면 0 반환)
kill -0 "$LIVE_PID" 2>/dev/null && { echo "FAIL: PID ${LIVE_PID}가 아직 살아있음"; kill -9 "$LIVE_PID" 2>/dev/null; exit 1; }
echo "OK"

echo "=== TEST 26: I2 — halt 시 미커밋 변경이 stash로 보관되면 WARN 출력 ==="
STASH_TASK="stash-warn-task"
mkdir -p "$PROJECT/milestones/regular/loops/$STASH_TASK"
cat > "$PROJECT/milestones/regular/loops/$STASH_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Stash Warn Task
EOF

# mock: iter 1·2 모두 fix:symptom + 미커밋 변경 남김 → iter 2 후 streak halt → stash 발생
COUNTER26="$WORK_DIR/iter-count-26.txt"
echo "0" > "$COUNTER26"
export COUNTER26_PATH="$COUNTER26"
MOCK26="$WORK_DIR/mock26-bin"
mkdir -p "$MOCK26"
cat > "$MOCK26/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER26_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER26_PATH}"
# fix:symptom commit
echo "patch-$n" > "stash_committed_$n.txt"
git add "stash_committed_$n.txt"
git commit -q -m "fix:symptom stash test $n"
# 미커밋 변경 추가 (stash 트리거)
echo "uncommitted-$n" > "stash_uncommitted_$n.txt"
echo '{"result": "mock26", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK26/claude"

set +e
output26=$(PATH="$MOCK26:$PATH" MAX_ITERATIONS=5 WALL_CLOCK_MINUTES=5 loop start "$STASH_TASK" 2>&1)
result26=$?
set -e
[[ $result26 -ne 0 ]] || { echo "FAIL: streak halt 안 됨 (exit 0)"; exit 1; }
echo "$output26" | grep -q "stash에 보관됨\|미커밋 변경" \
  || { echo "FAIL: stash WARN 메시지 없음. got: $output26"; exit 1; }
loop cleanup "$STASH_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 27: 테스트 약화 게이트가 __tests__/ 같은 비-tests/ 컨벤션 감지 ==="
TEST27_TASK="gate-tests-jest"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST27_TASK"
cat > "$PROJECT/milestones/regular/loops/$TEST27_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Gate Test — __tests__/ Detection
EOF

COUNTER27="$WORK_DIR/iter-count-27.txt"
echo "0" > "$COUNTER27"
export COUNTER27_PATH="$COUNTER27"

MOCK27="$WORK_DIR/mock27-bin"
mkdir -p "$MOCK27"
cat > "$MOCK27/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER27_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER27_PATH}"
if [[ $n -eq 1 ]]; then
  # iter 1: __tests__/foo.test.js 생성 + commit (jest 컨벤션)
  mkdir -p __tests__
  echo "test('a', () => {})" > __tests__/foo.test.js
  git add __tests__/foo.test.js
  git commit -q -m "test: add jest test"
else
  # iter 2: 삭제 (테스트 약화)
  git rm -q __tests__/foo.test.js
  git commit -q -m "remove: foo.test.js"
fi
echo '{"result": "mock27", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK27/claude"

set +e
output27=$(PATH="$MOCK27:$PATH" MAX_ITERATIONS=5 WALL_CLOCK_MINUTES=5 loop start "$TEST27_TASK" 2>&1)
result27=$?
set -e
[[ $result27 -ne 0 ]] || { echo "FAIL: __tests__/ 게이트가 halt하지 않음 (exit 0)"; exit 1; }
echo "$output27" | grep -q "HALT\|테스트 약화" \
  || { echo "FAIL: 테스트 약화 halt 메시지 없음. got: $output27"; exit 1; }
WT27="$PROJECT/milestones/regular/loops/$TEST27_TASK/.worktree"
[[ -f "$WT27/.loop/ESCALATION.md" ]] || { echo "FAIL: ESCALATION.md 미생성"; exit 1; }
loop cleanup "$TEST27_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 28: SPEC.md test_paths override가 기본 컨벤션 대체 ==="
TEST28_TASK="gate-tests-override"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST28_TASK"
# test_paths를 비표준 경로 'qa/**' 로 override
cat > "$PROJECT/milestones/regular/loops/$TEST28_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
test_paths:
  - "qa/**"
---

# Gate Test — test_paths Override
EOF

COUNTER28="$WORK_DIR/iter-count-28.txt"
echo "0" > "$COUNTER28"
export COUNTER28_PATH="$COUNTER28"

MOCK28="$WORK_DIR/mock28-bin"
mkdir -p "$MOCK28"
cat > "$MOCK28/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER28_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER28_PATH}"
if [[ $n -eq 1 ]]; then
  # iter 1: qa/check.sh 생성 (override 경로)
  mkdir -p qa
  echo "echo ok" > qa/check.sh
  git add qa/check.sh
  git commit -q -m "test: add qa check"
else
  # iter 2: qa/check.sh 수정 → halt
  echo "echo modified" > qa/check.sh
  git add qa/check.sh
  git commit -q -m "weaken: qa check"
fi
echo '{"result": "mock28", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK28/claude"

set +e
output28=$(PATH="$MOCK28:$PATH" MAX_ITERATIONS=5 WALL_CLOCK_MINUTES=5 loop start "$TEST28_TASK" 2>&1)
result28=$?
set -e
[[ $result28 -ne 0 ]] || { echo "FAIL: test_paths override 게이트가 halt하지 않음 (exit 0)"; exit 1; }
echo "$output28" | grep -q "HALT\|테스트 약화" \
  || { echo "FAIL: override halt 메시지 없음. got: $output28"; exit 1; }
loop cleanup "$TEST28_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 29: shasum fallback (sha256sum 부재 환경에서 동작) ==="
# vanilla macOS 시뮬레이션: PATH에서 sha256sum 디렉토리 제거하고 shasum만 남김
SHA256_BIN_PATH=$(command -v sha256sum 2>/dev/null || echo "")
SHASUM_BIN_PATH=$(command -v shasum 2>/dev/null || echo "")

if [[ -z "$SHASUM_BIN_PATH" ]]; then
  echo "SKIP: shasum 미설치 — fallback 시나리오 검증 불가"
else
  ISOLATED_PATH="$PATH"
  if [[ -n "$SHA256_BIN_PATH" ]]; then
    SHA256_DIR=$(dirname "$SHA256_BIN_PATH")
    ISOLATED_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "^${SHA256_DIR}$" | tr '\n' ':' | sed 's/:$//')
  fi

  if PATH="$ISOLATED_PATH" command -v sha256sum >/dev/null 2>&1; then
    echo "SKIP: sha256sum이 다른 디렉토리에도 존재 — 격리 불가능"
  else
    PATH="$ISOLATED_PATH" command -v shasum >/dev/null \
      || { echo "FAIL: 격리된 PATH에서 shasum도 사라짐"; exit 1; }

    mkdir -p "$PROJECT/milestones/regular/loops/shasum-fallback"
    cat > "$PROJECT/milestones/regular/loops/shasum-fallback/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Shasum Fallback Task
EOF
    set +e
    output29=$(PATH="$ISOLATED_PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
      bash "$LOOP_SH_SRC" start "shasum-fallback" --no-pr 2>&1)
    result29=$?
    set -e
    [[ $result29 -eq 0 ]] \
      || { echo "FAIL: shasum fallback 환경 실행 실패 (exit $result29). got: $output29"; exit 1; }
    WT29="$PROJECT/milestones/regular/loops/shasum-fallback/.worktree"
    [[ -f "$WT29/DONE" ]] || { echo "FAIL: DONE 파일 미생성 (해시 함수 미동작 의심)"; exit 1; }
    # 해시 함수가 빈 값이 아니어야 — iterations 로그 존재 확인
    [[ -f "$WT29/.loop/iterations/1.log" ]] || { echo "FAIL: 이터 로그 미생성"; exit 1; }
    loop cleanup "shasum-fallback" --force > /dev/null 2>&1
    echo "OK"
  fi
fi

echo "=== TEST 30: suppressor 게이트가 미커밋(working tree) 변경도 감지 ==="
TEST30_TASK="gate-suppressor-uncommitted"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST30_TASK"
cat > "$PROJECT/milestones/regular/loops/$TEST30_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Gate Test — Uncommitted Suppressor
EOF

COUNTER30="$WORK_DIR/iter-count-30.txt"
echo "0" > "$COUNTER30"
export COUNTER30_PATH="$COUNTER30"

MOCK30="$WORK_DIR/mock30-bin"
mkdir -p "$MOCK30"
cat > "$MOCK30/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER30_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER30_PATH}"
if [[ $n -eq 1 ]]; then
  # iter 1: 클린 코드 commit (suppressor 없음)
  mkdir -p src
  echo "x = 1" > src/clean.py
  git add src/clean.py
  git commit -q -m "feat: add clean code"
else
  # iter 2: 같은 파일에 suppressor 추가, NO commit (working tree만 변경)
  echo "x = 1  # noqa" > src/clean.py
  # commit 없음 — claude 비정상 종료 시나리오 시뮬레이션
fi
echo '{"result": "mock30", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK30/claude"

set +e
output30=$(PATH="$MOCK30:$PATH" MAX_ITERATIONS=5 WALL_CLOCK_MINUTES=5 loop start "$TEST30_TASK" 2>&1)
result30=$?
set -e
[[ $result30 -ne 0 ]] || { echo "FAIL: 미커밋 suppressor가 halt하지 않음 (exit 0)"; exit 1; }
echo "$output30" | grep -q "HALT\|Suppressor" \
  || { echo "FAIL: suppressor halt 메시지 없음. got: $output30"; exit 1; }
WT30="$PROJECT/milestones/regular/loops/$TEST30_TASK/.worktree"
[[ -f "$WT30/.loop/ESCALATION.md" ]] || { echo "FAIL: ESCALATION.md 미생성"; exit 1; }
loop cleanup "$TEST30_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 31: acquire_lock이 stale lock(죽은 PID)을 자동 정리 ==="
STALE_ACQUIRE_TASK="stale-acquire-task"
mkdir -p "$PROJECT/milestones/regular/loops/$STALE_ACQUIRE_TASK"
cat > "$PROJECT/milestones/regular/loops/$STALE_ACQUIRE_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Stale Acquire Task
EOF

# 죽은 PID로 락 미리 생성 (크래시 시뮬레이션) — 새 nested 경로
STALE_ACQUIRE_LOCK_31="$PROJECT/milestones/regular/loops/$STALE_ACQUIRE_TASK/.lock"
mkdir -p "$(dirname "$STALE_ACQUIRE_LOCK_31")"
echo "999999" > "$STALE_ACQUIRE_LOCK_31"

# loop start: 자동 정리 후 정상 진행되어야
set +e
output31=$(MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$STALE_ACQUIRE_TASK" 2>&1)
result31=$?
set -e
[[ $result31 -eq 0 ]] || { echo "FAIL: stale lock 자동 정리 실패 (exit $result31). got: $output31"; exit 1; }
echo "$output31" | grep -q "stale lock 자동 정리" \
  || { echo "FAIL: stale lock 정리 메시지 없음. got: $output31"; exit 1; }
WT31="$PROJECT/milestones/regular/loops/$STALE_ACQUIRE_TASK/.worktree"
[[ -d "$WT31" ]] || { echo "FAIL: 자동 정리 후 워크트리 미생성"; exit 1; }
loop cleanup "$STALE_ACQUIRE_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 32: acquire_lock이 빈/비숫자 PID도 stale로 인식 ==="
EMPTY_LOCK_TASK="empty-lock-task"
mkdir -p "$PROJECT/milestones/regular/loops/$EMPTY_LOCK_TASK"
cat > "$PROJECT/milestones/regular/loops/$EMPTY_LOCK_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Empty Lock Task
EOF

# 빈 락 파일 생성 (corrupted state 시뮬레이션) — 새 nested 경로
EMPTY_LOCK_32="$PROJECT/milestones/regular/loops/$EMPTY_LOCK_TASK/.lock"
mkdir -p "$(dirname "$EMPTY_LOCK_32")"
: > "$EMPTY_LOCK_32"

set +e
output32=$(MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$EMPTY_LOCK_TASK" 2>&1)
result32=$?
set -e
[[ $result32 -eq 0 ]] || { echo "FAIL: 빈 lock 정리 실패 (exit $result32). got: $output32"; exit 1; }
echo "$output32" | grep -q "stale lock 자동 정리" \
  || { echo "FAIL: 정리 메시지 없음. got: $output32"; exit 1; }
loop cleanup "$EMPTY_LOCK_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 33: secrets 게이트가 커밋된 변경에서 비밀 감지 (HEAD~1..HEAD) ==="
TEST33_TASK="gate-secrets-committed"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST33_TASK"
cat > "$PROJECT/milestones/regular/loops/$TEST33_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Gate Test — Secrets in Commit
EOF

# gitleaks mock: --log-opts=<range>로 git log -p 후 SECRET_KEY 매칭 검사
GITLEAKS_MOCK="$WORK_DIR/gitleaks-mock-bin"
mkdir -p "$GITLEAKS_MOCK"
cat > "$GITLEAKS_MOCK/gitleaks" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock: detect 서브커맨드, --log-opts 또는 --staged 처리
shift  # 'detect'
log_opts=""
staged=0
for a in "$@"; do
  case "$a" in
    --log-opts=*) log_opts="${a#--log-opts=}" ;;
    --staged) staged=1 ;;
  esac
done

if [[ -n "$log_opts" ]]; then
  # shellcheck disable=SC2086 # rev range는 단일 토큰
  if git log -p $log_opts 2>/dev/null | grep -q "SECRET_KEY="; then
    echo "leak: SECRET_KEY exposed in commit"
    exit 1
  fi
fi

if [[ $staged -eq 1 ]]; then
  if git diff --cached 2>/dev/null | grep -q "SECRET_KEY="; then
    echo "leak: SECRET_KEY exposed in staged"
    exit 1
  fi
fi
exit 0
MOCKEOF
chmod +x "$GITLEAKS_MOCK/gitleaks"

# claude mock: SECRET_KEY 포함 파일 commit
COUNTER33="$WORK_DIR/iter-count-33.txt"
echo "0" > "$COUNTER33"
export COUNTER33_PATH="$COUNTER33"
MOCK33="$WORK_DIR/mock33-bin"
mkdir -p "$MOCK33"
cat > "$MOCK33/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER33_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER33_PATH}"
mkdir -p config
echo "API_TOKEN=foo SECRET_KEY=abc123def456" > config/leak.env
git add config/leak.env
git commit -q -m "feat: add config (with leak)"
echo '{"result": "mock33", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK33/claude"

set +e
output33=$(PATH="$GITLEAKS_MOCK:$MOCK33:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 \
  loop start "$TEST33_TASK" 2>&1)
result33=$?
set -e
[[ $result33 -ne 0 ]] || { echo "FAIL: secrets 게이트가 halt하지 않음 (exit 0). got: $output33"; exit 1; }
echo "$output33" | grep -q "HALT.*Secrets\|Secrets 의심" \
  || { echo "FAIL: secrets halt 메시지 없음. got: $output33"; exit 1; }
WT33="$PROJECT/milestones/regular/loops/$TEST33_TASK/.worktree"
[[ -f "$WT33/.loop/ESCALATION.md" ]] || { echo "FAIL: ESCALATION.md 미생성"; exit 1; }
loop cleanup "$TEST33_TASK" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 34: 첫 start가 .gitignore 새 nested 패턴 자동 setup + 기존 .loops/locks/ 라인 제거 ==="
# 새 정책: milestones/**/loops/**/.worktree/ + milestones/**/loops/**/.lock 추가,
# 기존 .loops/locks/ 라인이 있으면 제거. 단일 chore commit으로 격리.
GITIGN_PROJECT="$WORK_DIR/gitign-project"
mkdir -p "$GITIGN_PROJECT"
git -C "$GITIGN_PROJECT" init -q
git -C "$GITIGN_PROJECT" config user.email "test@example.com"
git -C "$GITIGN_PROJECT" config user.name "Test"
git -C "$GITIGN_PROJECT" commit --allow-empty -m "initial" -q

# pre-state: 기존 .loops/locks/ 라인이 있는 .gitignore (legacy 마이그레이션 시나리오)
cat > "$GITIGN_PROJECT/.gitignore" <<'EOF'
node_modules
.loops/locks/
EOF
git -C "$GITIGN_PROJECT" add .gitignore
git -C "$GITIGN_PROJECT" commit -q -m "chore: pre-existing gitignore"

GITIGN_SPEC34="$WORK_DIR/gitign-spec-34.md"
cat > "$GITIGN_SPEC34" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---
# First Task
EOF
(cd "$GITIGN_PROJECT" && MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 bash "$LOOP_SH_SRC" start "first-task" --spec "$GITIGN_SPEC34" --no-pr > /dev/null 2>&1)

[[ -f "$GITIGN_PROJECT/.gitignore" ]] || { echo "FAIL: .gitignore 사라짐"; exit 1; }
grep -qxF 'milestones/**/loops/**/.worktree/' "$GITIGN_PROJECT/.gitignore" \
  || { echo "FAIL: .gitignore에 새 워크트리 패턴 없음. content: $(cat "$GITIGN_PROJECT/.gitignore")"; exit 1; }
grep -qxF 'milestones/**/loops/**/.lock' "$GITIGN_PROJECT/.gitignore" \
  || { echo "FAIL: .gitignore에 새 lock 패턴 없음. content: $(cat "$GITIGN_PROJECT/.gitignore")"; exit 1; }
# 기존 .loops/locks/ 라인은 제거되어야 함 (AC4)
grep -qxF '.loops/locks/' "$GITIGN_PROJECT/.gitignore" \
  && { echo "FAIL: 기존 .loops/locks/ 라인이 제거되지 않음. content: $(cat "$GITIGN_PROJECT/.gitignore")"; exit 1; }
# 사용자 라인은 보존
grep -qxF 'node_modules' "$GITIGN_PROJECT/.gitignore" \
  || { echo "FAIL: 기존 node_modules 라인이 삭제됨"; exit 1; }
# 단일 chore commit으로 격리 — 마지막 commit이 .gitignore만 건드려야 함
LAST_CHANGES_34=$(git -C "$GITIGN_PROJECT" log -1 --name-only --pretty=format: | grep -v '^$' | sort -u)
[[ "$LAST_CHANGES_34" == ".gitignore" ]] \
  || { echo "FAIL: 마지막 commit이 .gitignore 단독이 아님. got: $LAST_CHANGES_34"; exit 1; }
LAST_MSG_34=$(git -C "$GITIGN_PROJECT" log -1 --pretty=%s)
echo "$LAST_MSG_34" | grep -qE '^chore' \
  || { echo "FAIL: 마지막 commit이 chore prefix 아님. got: $LAST_MSG_34"; exit 1; }
echo "OK"

echo "=== TEST 35: 재호출 시 .gitignore 중복 추가 안 함 (idempotent) ==="
GITIGN_SPEC35="$WORK_DIR/gitign-spec-35.md"
cat > "$GITIGN_SPEC35" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---
# Second Task
EOF
# 두 번째 호출 시점에 변경 없음 확인 (commit 추가 없음)
HEAD_BEFORE_35=$(git -C "$GITIGN_PROJECT" rev-parse HEAD)
(cd "$GITIGN_PROJECT" && MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 bash "$LOOP_SH_SRC" start "second-task" --spec "$GITIGN_SPEC35" --no-pr > /dev/null 2>&1)
COUNT35_WT=$(grep -cxF 'milestones/**/loops/**/.worktree/' "$GITIGN_PROJECT/.gitignore")
COUNT35_LOCK=$(grep -cxF 'milestones/**/loops/**/.lock' "$GITIGN_PROJECT/.gitignore")
[[ $COUNT35_WT -eq 1 ]] \
  || { echo "FAIL: .worktree 패턴 중복 (${COUNT35_WT}개). content: $(cat "$GITIGN_PROJECT/.gitignore")"; exit 1; }
[[ $COUNT35_LOCK -eq 1 ]] \
  || { echo "FAIL: .lock 패턴 중복 (${COUNT35_LOCK}개). content: $(cat "$GITIGN_PROJECT/.gitignore")"; exit 1; }
# 이미 모두 정렬됐으면 추가 chore commit 없음 — HEAD 변동 없어야 (메인 레포 commit 기준)
HEAD_AFTER_35=$(git -C "$GITIGN_PROJECT" rev-parse HEAD)
[[ "$HEAD_BEFORE_35" == "$HEAD_AFTER_35" ]] \
  || { echo "FAIL: idempotent 호출인데 메인 브랜치 commit 추가됨 (before=$HEAD_BEFORE_35 after=$HEAD_AFTER_35)"; exit 1; }
echo "OK"

echo "=== TEST 36: 끝 newline 부재 .gitignore에 안전 추가 ==="
NL_PROJECT="$WORK_DIR/no-nl-project"
mkdir -p "$NL_PROJECT"
git -C "$NL_PROJECT" init -q
git -C "$NL_PROJECT" config user.email "t@e.com"
git -C "$NL_PROJECT" config user.name "Test"
git -C "$NL_PROJECT" commit --allow-empty -m "initial" -q

# 끝에 newline 없는 .gitignore 생성
printf 'node_modules' > "$NL_PROJECT/.gitignore"
[[ "$(tail -c1 "$NL_PROJECT/.gitignore")" != "" ]] \
  || { echo "FAIL: pre-state newline이 이미 있음 (테스트 setup 오류)"; exit 1; }

GITIGN_SPEC36="$WORK_DIR/gitign-spec-36.md"
cat > "$GITIGN_SPEC36" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---
# Task X
EOF
(cd "$NL_PROJECT" && MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 bash "$LOOP_SH_SRC" start "task-x" --spec "$GITIGN_SPEC36" --no-pr > /dev/null 2>&1)

# 두 라인이 정확히 분리됐는지 (붙어버리면 'node_modulesmilestones/...'가 됨)
grep -qx 'node_modules' "$NL_PROJECT/.gitignore" \
  || { echo "FAIL: node_modules 사라짐/병합. content: $(cat "$NL_PROJECT/.gitignore")"; exit 1; }
grep -qxF 'milestones/**/loops/**/.worktree/' "$NL_PROJECT/.gitignore" \
  || { echo "FAIL: 새 워크트리 패턴 부재"; exit 1; }
grep -qxF 'milestones/**/loops/**/.lock' "$NL_PROJECT/.gitignore" \
  || { echo "FAIL: 새 lock 패턴 부재"; exit 1; }
echo "OK"

echo "=== TEST 37: stash 감지가 비-영어 locale에서도 동작 (locale 독립) ==="
LOCALE_FOUND=""
LOCALE_LIST=$(locale -a 2>/dev/null || echo "")
for loc in ko_KR.UTF-8 ko_KR.utf8 ja_JP.UTF-8 zh_CN.UTF-8 de_DE.UTF-8 fr_FR.UTF-8; do
  # here-string으로 grep 호출 — `cmd | grep -q`는 pipefail에서 조기 종료 시 SIGPIPE로 false negative
  if grep -qxF "$loc" <<< "$LOCALE_LIST"; then
    LOCALE_FOUND="$loc"
    break
  fi
done

if [[ -z "$LOCALE_FOUND" ]]; then
  echo "SKIP: 비-영어 locale 미설치 — locale 독립 시나리오 검증 불가"
else
  TEST37_TASK="locale-stash"
  mkdir -p "$PROJECT/milestones/regular/loops/$TEST37_TASK"
  cat > "$PROJECT/milestones/regular/loops/$TEST37_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Locale Stash Test
EOF

  COUNTER37="$WORK_DIR/iter-count-37.txt"
  echo "0" > "$COUNTER37"
  export COUNTER37_PATH="$COUNTER37"
  MOCK37="$WORK_DIR/mock37-bin"
  mkdir -p "$MOCK37"
  cat > "$MOCK37/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER37_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER37_PATH}"
# fix:symptom commit + 미커밋 변경 (TEST 26과 동일 패턴, streak halt 트리거)
echo "p$n" > "lc_$n.txt"
git add "lc_$n.txt"
git commit -q -m "fix:symptom locale $n"
echo "u$n" > "lcu_$n.txt"
echo '{"result": "mock37", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
  chmod +x "$MOCK37/claude"

  set +e
  output37=$(LANG="$LOCALE_FOUND" LC_ALL="$LOCALE_FOUND" \
    PATH="$MOCK37:$PATH" MAX_ITERATIONS=5 WALL_CLOCK_MINUTES=5 \
    loop start "$TEST37_TASK" 2>&1)
  result37=$?
  set -e
  [[ $result37 -ne 0 ]] || { echo "FAIL: streak halt 안 됨 (exit 0)"; exit 1; }
  echo "$output37" | grep -q "stash에 보관됨" \
    || { echo "FAIL: $LOCALE_FOUND locale에서 stash WARN 누락 — locale 의존 회귀. got: $output37"; exit 1; }
  loop cleanup "$TEST37_TASK" --force > /dev/null 2>&1
  echo "OK ($LOCALE_FOUND)"
fi

echo "=== TEST 38: 새 테스트 추가는 weakening 게이트 통과 (TDD RED 보호) ==="
TDD_PROJECT="$WORK_DIR/tdd-add-project"
mkdir -p "$TDD_PROJECT/tests"
git -C "$TDD_PROJECT" init -q
git -C "$TDD_PROJECT" config user.email "test@example.com"
git -C "$TDD_PROJECT" config user.name "Test"
echo "def test_existing(): assert True" > "$TDD_PROJECT/tests/test_existing.py"
git -C "$TDD_PROJECT" add tests/test_existing.py
git -C "$TDD_PROJECT" commit -q -m "init with existing test"

COUNTER38="$WORK_DIR/iter-count-38.txt"
echo "0" > "$COUNTER38"
export COUNTER38_PATH="$COUNTER38"

MOCK38="$WORK_DIR/mock38-bin"
mkdir -p "$MOCK38"
cat > "$MOCK38/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER38_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER38_PATH}"
# 새 test 파일 추가 (RED 단계 시뮬레이션) — 기존 test_existing.py는 손대지 않음
echo "def test_new_$n(): assert False" > "tests/test_new_$n.py"
git add "tests/test_new_$n.py"
git commit -q -m "test: add new test_$n (RED)"
if [[ $n -ge 2 ]]; then touch DONE; fi
echo '{"result": "mock38", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK38/claude"

(
  cd "$TDD_PROJECT"
  mkdir -p "milestones/regular/loops/tdd-add"
  cat > "milestones/regular/loops/tdd-add/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# TDD RED — Adding New Test
EOF
  set +e
  output38=$(PATH="$MOCK38:$PATH" MAX_ITERATIONS=5 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "tdd-add" --no-pr 2>&1)
  result38=$?
  set -e
  [[ $result38 -eq 0 ]] || { echo "FAIL: 새 test 추가가 weakening halt 트리거 (regression). exit=$result38"; echo "$output38"; exit 1; }
  if echo "$output38" | grep -q "테스트 약화"; then
    echo "FAIL: '테스트 약화' 메시지 발생 — 신규 추가가 weakening으로 잘못 분류됨"
    echo "$output38"
    exit 1
  fi
  WT38="$TDD_PROJECT/milestones/regular/loops/tdd-add/.worktree"
  [[ -f "$WT38/DONE" ]] || { echo "FAIL: DONE 파일 없음"; exit 1; }
)
echo "OK"

echo "=== TEST 39: 기존 테스트 수정/삭제는 여전히 weakening halt ==="
TDD_MOD_PROJECT="$WORK_DIR/tdd-mod-project"
mkdir -p "$TDD_MOD_PROJECT/tests"
git -C "$TDD_MOD_PROJECT" init -q
git -C "$TDD_MOD_PROJECT" config user.email "t@e.com"
git -C "$TDD_MOD_PROJECT" config user.name "Test"
echo "def test_existing(): assert True" > "$TDD_MOD_PROJECT/tests/test_existing.py"
git -C "$TDD_MOD_PROJECT" add tests/test_existing.py
git -C "$TDD_MOD_PROJECT" commit -q -m "init"

MOCK39="$WORK_DIR/mock39-bin"
mkdir -p "$MOCK39"
cat > "$MOCK39/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
# 기존 test_existing.py 수정 (약화)
echo "def test_existing(): assert False  # weakened" > tests/test_existing.py
git add tests/test_existing.py
git commit -q -m "weaken: test_existing"
echo '{"result": "mock39", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK39/claude"

(
  cd "$TDD_MOD_PROJECT"
  mkdir -p "milestones/regular/loops/tdd-mod"
  cat > "milestones/regular/loops/tdd-mod/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# TDD — Existing Test Modified (must halt)
EOF
  set +e
  output39=$(PATH="$MOCK39:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "tdd-mod" --no-pr 2>&1)
  result39=$?
  set -e
  [[ $result39 -ne 0 ]] || { echo "FAIL: 기존 test 수정이 halt 트리거 안 됨 (exit 0)"; echo "$output39"; exit 1; }
  echo "$output39" | grep -q "테스트 약화" \
    || { echo "FAIL: weakening halt 메시지 없음. got: $output39"; exit 1; }
)
echo "OK"

echo "=== TEST 40: stop이 claude 자식 프로세스도 종료 (orphan 방지) ==="
ORPHAN_TASK="orphan-prevent"
mkdir -p "$PROJECT/milestones/regular/loops/$ORPHAN_TASK"
cat > "$PROJECT/milestones/regular/loops/$ORPHAN_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Orphan Prevention Test
EOF

# 오래 자는 mock claude — 자신의 PID를 파일에 기록
CLAUDE_PID_FILE="$WORK_DIR/orphan-claude.pid"
LONG_MOCK="$WORK_DIR/long-mock-bin"
mkdir -p "$LONG_MOCK"
cat > "$LONG_MOCK/claude" <<MOCKEOF
#!/usr/bin/env bash
cat > /dev/null
echo \$\$ > "$CLAUDE_PID_FILE"
sleep 60
MOCKEOF
chmod +x "$LONG_MOCK/claude"

# 백그라운드에서 loop start 실행
rm -f "$CLAUDE_PID_FILE"
PATH="$LONG_MOCK:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 \
  bash "$LOOP_SH_SRC" start "$ORPHAN_TASK" --no-pr > "$WORK_DIR/orphan-output.log" 2>&1 &
LOOP_PID=$!

# claude PID 파일이 생길 때까지 대기 (max 5초)
for _ in 1 2 3 4 5; do
  [[ -f "$CLAUDE_PID_FILE" ]] && break
  sleep 1
done
[[ -f "$CLAUDE_PID_FILE" ]] || {
  echo "FAIL: mock claude 미시작"
  kill -KILL "$LOOP_PID" 2>/dev/null
  exit 1
}
CLAUDE_REAL_PID=$(cat "$CLAUDE_PID_FILE")
kill -0 "$CLAUDE_REAL_PID" 2>/dev/null \
  || { echo "FAIL: claude 프로세스가 시작 안 됨"; exit 1; }

# stop으로 SIGTERM 전송
loop stop "$ORPHAN_TASK"

# claude 자식이 정리됐는지 확인 (최대 3초 grace)
ORPHAN_DEAD=0
for _ in 1 2 3; do
  if ! kill -0 "$CLAUDE_REAL_PID" 2>/dev/null; then
    ORPHAN_DEAD=1
    break
  fi
  sleep 1
done

if [[ $ORPHAN_DEAD -eq 0 ]]; then
  kill -KILL "$CLAUDE_REAL_PID" 2>/dev/null
  echo "FAIL: stop 후 claude 자식이 orphan으로 잔존 (PID $CLAUDE_REAL_PID)"
  exit 1
fi

# lock 파일 정리됐는지 (새 nested 경로)
[[ ! -f "$PROJECT/milestones/regular/loops/$ORPHAN_TASK/.lock" ]] \
  || { echo "FAIL: stop 후 lock 파일 잔존"; exit 1; }

echo "OK"

echo "=== TEST 41: --force cleanup이 실행 중 프로세스를 먼저 SIGTERM (race 방지) ==="
FORCE_TASK="force-cleanup-running"
mkdir -p "$PROJECT/milestones/regular/loops/$FORCE_TASK"
cat > "$PROJECT/milestones/regular/loops/$FORCE_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Force Cleanup Running Test
EOF

# 오래 자는 mock claude — 자신의 PID를 파일에 기록
CLAUDE_PID_FILE_41="$WORK_DIR/force-claude.pid"
LONG_MOCK_41="$WORK_DIR/force-mock-bin"
mkdir -p "$LONG_MOCK_41"
cat > "$LONG_MOCK_41/claude" <<MOCKEOF
#!/usr/bin/env bash
cat > /dev/null
echo \$\$ > "$CLAUDE_PID_FILE_41"
sleep 60
MOCKEOF
chmod +x "$LONG_MOCK_41/claude"

# 백그라운드에서 loop start
rm -f "$CLAUDE_PID_FILE_41"
PATH="$LONG_MOCK_41:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 \
  bash "$LOOP_SH_SRC" start "$FORCE_TASK" --no-pr > "$WORK_DIR/force-output.log" 2>&1 &
LOOP_PID_41=$!

# claude PID 파일 대기
for _ in 1 2 3 4 5; do
  [[ -f "$CLAUDE_PID_FILE_41" ]] && break
  sleep 1
done
[[ -f "$CLAUDE_PID_FILE_41" ]] || {
  echo "FAIL: mock claude 미시작"
  kill -KILL "$LOOP_PID_41" 2>/dev/null
  exit 1
}
CLAUDE_PID_41=$(cat "$CLAUDE_PID_FILE_41")
LOCK_FILE_41="$PROJECT/milestones/regular/loops/$FORCE_TASK/.lock"
[[ -f "$LOCK_FILE_41" ]] || { echo "FAIL: lock 파일 미생성"; exit 1; }

# --force cleanup
loop cleanup "$FORCE_TASK" --force > /dev/null 2>&1

# bash와 claude 모두 종료됐는지 (최대 3초 grace)
ALL_DEAD=0
for _ in 1 2 3; do
  if ! kill -0 "$LOOP_PID_41" 2>/dev/null && ! kill -0 "$CLAUDE_PID_41" 2>/dev/null; then
    ALL_DEAD=1
    break
  fi
  sleep 1
done

if [[ $ALL_DEAD -eq 0 ]]; then
  kill -KILL "$LOOP_PID_41" 2>/dev/null
  kill -KILL "$CLAUDE_PID_41" 2>/dev/null
  echo "FAIL: --force cleanup 후 프로세스 잔존 (bash $LOOP_PID_41, claude $CLAUDE_PID_41)"
  exit 1
fi

# lock·워크트리 정리
[[ ! -f "$LOCK_FILE_41" ]] || { echo "FAIL: lock 파일 잔존"; exit 1; }
WT_41="$PROJECT/milestones/regular/loops/$FORCE_TASK/.worktree"
[[ ! -d "$WT_41" ]] || { echo "FAIL: 워크트리 잔존"; exit 1; }

echo "OK"

echo "=== TEST 42: slash task-id의 lock이 hyphen task와 자연 분리 ==="
# 새 nested 정책: lock 파일은 milestones/<m>/loops/<c>/.lock — 디렉터리 구조가
# task-id를 그대로 반영해 충돌 가능성 자체가 없음. 'regular/col-fake'와
# 'col/fake'는 각자 다른 lock 디렉터리에 lock을 둠.
# 미리 'regular/col-fake' 위치에 살아있는 PID lock 설정
COL_FAKE_REGULAR_LOCK="$PROJECT/milestones/regular/loops/col-fake/.lock"
mkdir -p "$(dirname "$COL_FAKE_REGULAR_LOCK")"
echo "$$" > "$COL_FAKE_REGULAR_LOCK"

mkdir -p "$PROJECT/milestones/col/loops/fake"
cat > "$PROJECT/milestones/col/loops/fake/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Slash vs Hyphen Collision Test
EOF

set +e
output42=$(MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 loop start "col/fake" 2>&1)
result42=$?
set -e
[[ $result42 -eq 0 ]] || { echo "FAIL: slash task가 hyphen lock과 충돌 (false collision). exit=$result42, got: $output42"; exit 1; }

# 정리
rm -f "$COL_FAKE_REGULAR_LOCK"
loop cleanup "col/fake" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 43: task-id에 '__' 포함 거부 (slash 인코딩 예약) ==="
# prepare는 deprecated stub이므로 task-id 검증을 안 함 — 실제 진입점만 검사
for sub in start status stop cleanup logs; do
  set +e
  output=$(loop "$sub" "task__double" 2>&1)
  result=$?
  set -e
  [[ $result -ne 0 ]] || { echo "FAIL: ${sub}가 '__' task-id를 받아들임"; exit 1; }
  echo "$output" | grep -q "예약\|'__'" \
    || { echo "FAIL: ${sub}의 '__' 거부 메시지 없음. got: $output"; exit 1; }
done
echo "OK"

echo "=== TEST 44: task-id에 공백 포함 거부 ==="
for sub in start status stop cleanup logs; do
  set +e
  output=$(loop "$sub" "task with space" 2>&1)
  result=$?
  set -e
  [[ $result -ne 0 ]] || { echo "FAIL: ${sub}가 공백 task-id를 받아들임"; exit 1; }
  echo "$output" | grep -q "공백" \
    || { echo "FAIL: ${sub}의 공백 거부 메시지 없음. got: $output"; exit 1; }
done
echo "OK"

echo "=== TEST 45: slash task-id가 status 목록에 정확히 표시 (오인식 방지) ==="
# 기존 TEST 5에서 'goal-x/sub-task'가 prepare됐다 cleanup된 상태일 수 있음.
# 새로 깨끗한 slash task-id로 검증.
mkdir -p "$PROJECT/milestones/ns-foo/loops/sub-bar"
cat > "$PROJECT/milestones/ns-foo/loops/sub-bar/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Slash status test
EOF

output45=$(loop status 2>&1)
echo "$output45" | grep -q 'ns-foo/sub-bar' \
  || { echo "FAIL: status에 'ns-foo/sub-bar' 없음. got: $output45"; exit 1; }
# 'ns-foo'만 별개 task로 오인식되면 안 됨 — '^ns-foo<space>' 패턴 없어야
if echo "$output45" | grep -qE '^ns-foo[[:space:]]'; then
  echo "FAIL: 'ns-foo'가 별개 task로 오인식. got: $output45"
  exit 1
fi

# 정리 (워크트리 없으니 milestones/ 디렉토리만 직접 제거)
rm -rf "$PROJECT/milestones/ns-foo"
echo "OK"

echo "=== TEST 46: task-id에 '.' 단독 컴포넌트 거부 ==="
# compute_paths→validate_task_id 경로로 거부됨. start 진입점으로 검증
# (prepare는 stub이라 task-id를 검증하지 않음)
for invalid in "." "./foo" "foo/." "a/./b"; do
  set +e
  output=$(loop start "$invalid" 2>&1)
  result=$?
  set -e
  [[ $result -ne 0 ]] || { echo "FAIL: start가 '$invalid' task-id를 받아들임"; exit 1; }
  echo "$output" | grep -qE "'\\.'" \
    || { echo "FAIL: '$invalid'에 대해 '.' 거부 메시지 없음. got: $output"; exit 1; }
done
echo "OK"

echo "=== TEST 47: SPEC.md에 [NEEDS CLARIFICATION] 잔존 시 start 거부 ==="
# task 디렉터리·SPEC 시드
mkdir -p milestones/regular/loops/needs-clar-task
cat > milestones/regular/loops/needs-clar-task/SPEC.md <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Test SPEC

## 무엇을 만들 것인가
Test task with unresolved marker

## 수용 기준
- A1: When the user logs in, the system shall authenticate.
- [NEEDS CLARIFICATION: 어떤 인증 방식? OAuth/SSO/email-password?]

## 범위
포함:
src/

비-목표 / 제외:
none

## 검증
true
EOF

set +e
output=$(MAX_ITERATIONS=1 loop start needs-clar-task 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 마커 잔존 SPEC으로 start가 성공하면 안 됨"; exit 1; }
echo "$output" | grep -q "NEEDS CLARIFICATION\|spec.*resume" || { echo "FAIL: 마커 안내 메시지 없음. got: $output"; exit 1; }
# 락 안 잡혀야 함 (새 nested 경로)
[[ ! -f milestones/regular/loops/needs-clar-task/.lock ]] || { echo "FAIL: 차단 됐어야 하는데 락 잡힘"; exit 1; }
echo "OK"

echo "=== TEST 48: 단일 컴포넌트 task-id가 regular/<input>으로 정규화 ==="
# M1: 단일 컴포넌트 task-id 입력 시 'regular/' 자동 prefix.
# SPEC은 milestones/regular/loops/<child>/SPEC.md 에서 읽음.
# 워크트리는 milestones/regular/loops/<child>/.worktree/.
TEST48_ID="single-comp-task"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST48_ID"
cat > "$PROJECT/milestones/regular/loops/$TEST48_ID/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Single Component Normalization Task
EOF

MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 loop start "$TEST48_ID" > /dev/null 2>&1
WT48="$PROJECT/milestones/regular/loops/$TEST48_ID/.worktree"
[[ -d "$WT48" ]] || { echo "FAIL: regular/<input> 정규화 후 워크트리 미생성 (expected: $WT48)"; exit 1; }
[[ -f "$WT48/.loop/SPEC.md" ]] || { echo "FAIL: 워크트리에 .loop/SPEC.md 미복사"; exit 1; }
# 새 nested 정책: lock은 milestones/regular/loops/<id>/.lock에만 존재
[[ ! -d "$PROJECT/.loops/locks" ]] \
  || { echo "FAIL: 새 정책인데 legacy .loops/locks/ 디렉터리가 생성됨"; exit 1; }
loop cleanup "$TEST48_ID" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 49: 명시적 milestone/child task-id가 milestones/<m>/loops/<c>/SPEC.md를 읽음 ==="
mkdir -p "$PROJECT/milestones/m1/loops/c1"
cat > "$PROJECT/milestones/m1/loops/c1/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Explicit Milestone Task
EOF

MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 loop start "m1/c1" > /dev/null 2>&1
WT49="$PROJECT/milestones/m1/loops/c1/.worktree"
[[ -d "$WT49" ]] || { echo "FAIL: m1/c1 워크트리 미생성 (expected: $WT49)"; exit 1; }
[[ -f "$WT49/.loop/SPEC.md" ]] || { echo "FAIL: m1/c1 워크트리에 .loop/SPEC.md 미복사"; exit 1; }
loop cleanup "m1/c1" --force > /dev/null 2>&1
echo "OK"

echo "=== TEST 50: legacy .loops/<id>/SPEC.md fallback 없음 (cutover) ==="
# 의도: legacy 경로(.loops/<id>/SPEC.md)에만 SPEC을 두고, milestones/ 경로엔 없을 때
# start가 거부되는지 검증. M1 cutover에서 legacy fallback이 제거됐음.
LEGACY_ID="legacy-only-task"
# Legacy 경로에만 시드 (milestones/regular/loops/<id>/ 는 의도적으로 만들지 않음)
mkdir -p "$PROJECT/.loops/$LEGACY_ID"
cat > "$PROJECT/.loops/$LEGACY_ID/SPEC.md" <<'LEGACY_EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Legacy Path Only — Should Not Be Read
LEGACY_EOF

set +e
output50=$(MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 loop start "$LEGACY_ID" 2>&1)
result50=$?
set -e
[[ $result50 -ne 0 ]] || { echo "FAIL: legacy .loops/<id>/SPEC.md fallback이 동작함 (cutover 위반)"; exit 1; }
echo "$output50" | grep -q "SPEC.md가 없습니다\|milestones/" \
  || { echo "FAIL: legacy 부재 에러 메시지 없음. got: $output50"; exit 1; }
# 워크트리·락 잡혀선 안 됨 (새 nested 경로)
[[ ! -d "$PROJECT/milestones/regular/loops/$LEGACY_ID/.worktree" ]] \
  || { echo "FAIL: legacy fallback이 워크트리 생성"; exit 1; }
rm -rf "$PROJECT/.loops/$LEGACY_ID"
echo "OK"

echo "=== TEST 51: test_sweep_paths 선언 시 해당 경로 테스트 수정·삭제는 weakening halt 안 함 ==="
# AC1+5: sweep 경로 안 파일은 약화 검사에서 제외.
SWEEP_OK_PROJECT="$WORK_DIR/sweep-ok-project"
mkdir -p "$SWEEP_OK_PROJECT/tests"
git -C "$SWEEP_OK_PROJECT" init -q
git -C "$SWEEP_OK_PROJECT" config user.email "t@e.com"
git -C "$SWEEP_OK_PROJECT" config user.name "Test"
# 기본 컨벤션 매칭(tests/**)이지만 sweep으로 선언되므로 수정해도 halt 안 돼야
echo "def test_sweep(): assert True" > "$SWEEP_OK_PROJECT/tests/test_sweep_target.py"
git -C "$SWEEP_OK_PROJECT" add tests/test_sweep_target.py
git -C "$SWEEP_OK_PROJECT" commit -q -m "init sweep target"

COUNTER51="$WORK_DIR/iter-count-51.txt"
echo "0" > "$COUNTER51"
export COUNTER51_PATH="$COUNTER51"

MOCK51="$WORK_DIR/mock51-bin"
mkdir -p "$MOCK51"
cat > "$MOCK51/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
n=$(cat "${COUNTER51_PATH}")
n=$((n + 1))
echo "$n" > "${COUNTER51_PATH}"
if [[ $n -eq 1 ]]; then
  # iter 1: 기존 sweep 대상 파일 수정 (sweep 안이므로 weakening halt 없어야)
  # DONE은 만들지 않음 → 이터 종료 후 weakening 게이트가 반드시 실행됨
  echo "def test_sweep(): assert True  # sweep modified" > tests/test_sweep_target.py
  git add tests/test_sweep_target.py
  git commit -q -m "test: sweep modify"
else
  # iter 2: 정상 종료 (weakening 게이트가 iter 1을 통과했음을 입증)
  touch DONE
fi
echo '{"result": "mock51", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK51/claude"

(
  cd "$SWEEP_OK_PROJECT"
  mkdir -p "milestones/regular/loops/sweep-ok"
  cat > "milestones/regular/loops/sweep-ok/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
test_sweep_paths:
  - "tests/test_sweep_target.py"
---

# Sweep Allow Test
EOF
  set +e
  output51=$(PATH="$MOCK51:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "sweep-ok" --no-pr 2>&1)
  result51=$?
  set -e
  [[ $result51 -eq 0 ]] || { echo "FAIL: sweep 경로 수정이 weakening halt 트리거. exit=$result51"; echo "$output51"; exit 1; }
  if echo "$output51" | grep -q "테스트 약화"; then
    echo "FAIL: sweep 경로 수정에 '테스트 약화' 메시지 발생"
    echo "$output51"
    exit 1
  fi
  WT51="$SWEEP_OK_PROJECT/milestones/regular/loops/sweep-ok/.worktree"
  [[ -f "$WT51/DONE" ]] || { echo "FAIL: DONE 미생성"; exit 1; }
)
echo "OK"

echo "=== TEST 52: test_sweep_paths 선언됐으나 매칭 파일 0건 → stderr 경고 + halt 없음 ==="
# AC2: 패턴 오타·미생성 시 경고만, 진행 차단 안 함.
SWEEP_WARN_PROJECT="$WORK_DIR/sweep-warn-project"
mkdir -p "$SWEEP_WARN_PROJECT"
git -C "$SWEEP_WARN_PROJECT" init -q
git -C "$SWEEP_WARN_PROJECT" config user.email "t@e.com"
git -C "$SWEEP_WARN_PROJECT" config user.name "Test"
git -C "$SWEEP_WARN_PROJECT" commit --allow-empty -q -m "init"

MOCK52="$WORK_DIR/mock52-bin"
mkdir -p "$MOCK52"
cat > "$MOCK52/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
touch DONE
echo '{"result": "mock52", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK52/claude"

(
  cd "$SWEEP_WARN_PROJECT"
  mkdir -p "milestones/regular/loops/sweep-warn"
  cat > "milestones/regular/loops/sweep-warn/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
test_sweep_paths:
  - "nonexistent-dir/**"
---

# Sweep Empty Match Test
EOF
  set +e
  output52=$(PATH="$MOCK52:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "sweep-warn" --no-pr 2>&1)
  result52=$?
  set -e
  [[ $result52 -eq 0 ]] || { echo "FAIL: sweep 매칭 0건이 halt 트리거. exit=$result52"; echo "$output52"; exit 1; }
  echo "$output52" | grep -q "test_sweep_paths" \
    || { echo "FAIL: sweep 매칭 0건 경고 없음. got: $output52"; exit 1; }
  WT52="$SWEEP_WARN_PROJECT/milestones/regular/loops/sweep-warn/.worktree"
  [[ -f "$WT52/DONE" ]] || { echo "FAIL: DONE 미생성"; exit 1; }
)
echo "OK"

echo "=== TEST 53: test_sweep_paths 선언 시 sweep 밖 기존 테스트 수정은 여전히 weakening halt ==="
# AC4: sweep은 화이트리스트 면제 — 밖의 파일은 보호된다.
SWEEP_BOUND_PROJECT="$WORK_DIR/sweep-bound-project"
mkdir -p "$SWEEP_BOUND_PROJECT/tests"
git -C "$SWEEP_BOUND_PROJECT" init -q
git -C "$SWEEP_BOUND_PROJECT" config user.email "t@e.com"
git -C "$SWEEP_BOUND_PROJECT" config user.name "Test"
echo "def test_protected(): assert True" > "$SWEEP_BOUND_PROJECT/tests/test_protected.py"
echo "def test_sweep(): assert True" > "$SWEEP_BOUND_PROJECT/tests/test_sweep_zone.py"
git -C "$SWEEP_BOUND_PROJECT" add tests/test_protected.py tests/test_sweep_zone.py
git -C "$SWEEP_BOUND_PROJECT" commit -q -m "init both"

MOCK53="$WORK_DIR/mock53-bin"
mkdir -p "$MOCK53"
cat > "$MOCK53/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
# sweep 밖 파일 수정 (보호되어야 → halt 발생해야)
echo "def test_protected(): assert False  # weakened" > tests/test_protected.py
git add tests/test_protected.py
git commit -q -m "weaken: protected"
echo '{"result": "mock53", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK53/claude"

(
  cd "$SWEEP_BOUND_PROJECT"
  mkdir -p "milestones/regular/loops/sweep-bound"
  cat > "milestones/regular/loops/sweep-bound/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
test_sweep_paths:
  - "tests/test_sweep_zone.py"
---

# Sweep Boundary Test
EOF
  set +e
  output53=$(PATH="$MOCK53:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "sweep-bound" --no-pr 2>&1)
  result53=$?
  set -e
  [[ $result53 -ne 0 ]] || { echo "FAIL: sweep 밖 파일 수정이 halt 안 됨 (AC4 위반). exit=$result53"; echo "$output53"; exit 1; }
  echo "$output53" | grep -q "테스트 약화" \
    || { echo "FAIL: sweep 밖 약화 halt 메시지 없음. got: $output53"; exit 1; }
)
echo "OK"

echo "=== TEST 54: suppressor 게이트가 .loop/ 워커 메모리는 검사 제외 ==="
# 워커가 PLAN.md 등에 헌법 본문 인용 시 suppressor 패턴 문자열이 들어감 — false positive 방지
TEST54_TASK="gate-suppressor-loop-dir"
mkdir -p "$PROJECT/milestones/regular/loops/$TEST54_TASK"
cat > "$PROJECT/milestones/regular/loops/$TEST54_TASK/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Gate Test — .loop/ Excluded from Suppressor Scan
EOF

MOCK54="$WORK_DIR/mock54-bin"
mkdir -p "$MOCK54"
cat > "$MOCK54/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
# 워커가 PLAN.md에 헌법 본문 인용 (suppressor 패턴 문자열 포함) + commit
# 헌법 §3.1 출력 요건: 메모리 파일 갱신은 commit과 함께
mkdir -p .loop
cat > .loop/PLAN.md <<'PLAN_EOF'
- `# noqa`, `@ts-ignore`, `eslint-disable`, `#pragma warning disable` 등 경고 억제 지시어 신규 추가 금지
PLAN_EOF
git add .loop/PLAN.md
git commit -q -m "feat: cite suppressor rules in PLAN.md"
echo '{"result": "mock54", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK54/claude"

set +e
output54=$(PATH="$MOCK54:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 loop start "$TEST54_TASK" 2>&1)
set -e
echo "$output54" | grep -q "Suppressor 신규 추가" \
  && { echo "FAIL: .loop/PLAN.md의 suppressor 패턴 인용이 false positive halt 트리거"; echo "$output54"; exit 1; }
echo "$output54" | grep -q "이터 상한 도달" \
  || { echo "FAIL: loop이 MAX_ITERATIONS까지 정상 진행 못함 — false positive 부재만으로 OK 판정하면 mock·환경 이슈에서 false OK 발생"; echo "$output54"; exit 1; }
loop cleanup "$TEST54_TASK" --force > /dev/null 2>&1 || true
echo "OK"

echo "=== TEST 55: .gitignore가 legacy 라인 단독일 때 ensure_loops_setup die 안 함 ==="
# grep -vxF는 모든 라인이 제외되어 출력이 비면 exit 1 — 정상 케이스이므로 die 트리거 금지.
# 기존 TEST 34는 node_modules가 함께 있어 이 경로 미커버.
GITIGN_PROJECT55="$WORK_DIR/gitign-project-55"
mkdir -p "$GITIGN_PROJECT55"
git -C "$GITIGN_PROJECT55" init -q
git -C "$GITIGN_PROJECT55" config user.email "test@example.com"
git -C "$GITIGN_PROJECT55" config user.name "Test"
git -C "$GITIGN_PROJECT55" commit --allow-empty -m "initial" -q

# pre-state: .gitignore에 legacy 라인 단 한 줄
echo '.loops/locks/' > "$GITIGN_PROJECT55/.gitignore"
git -C "$GITIGN_PROJECT55" add .gitignore
git -C "$GITIGN_PROJECT55" commit -q -m "chore: gitignore legacy only"

GITIGN_SPEC55="$WORK_DIR/gitign-spec-55.md"
cat > "$GITIGN_SPEC55" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---
# Legacy-Only Gitignore Task
EOF

set +e
output55=$( (cd "$GITIGN_PROJECT55" && MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 bash "$LOOP_SH_SRC" start "legacy-only-task" --spec "$GITIGN_SPEC55" --no-pr) 2>&1 )
set -e
echo "$output55" | grep -q "기존 .loops/locks/ 라인 제거 실패" \
  && { echo "FAIL: legacy 라인 단독 .gitignore에서 die 오발동. got: $output55"; exit 1; }
# legacy 라인은 제거됐어야 함
grep -qxF '.loops/locks/' "$GITIGN_PROJECT55/.gitignore" \
  && { echo "FAIL: legacy 라인이 제거되지 않음. content: $(cat "$GITIGN_PROJECT55/.gitignore")"; exit 1; }
# 새 패턴은 추가됐어야 함
grep -qxF 'milestones/**/loops/**/.worktree/' "$GITIGN_PROJECT55/.gitignore" \
  || { echo "FAIL: 새 워크트리 패턴 없음. content: $(cat "$GITIGN_PROJECT55/.gitignore")"; exit 1; }
echo "OK"

echo "=== TEST 56: has_legacy=0일 때 갱신 메시지에 \"legacy 라인 제거\" 비포함 ==="
# bash ${var:+word}는 값이 "0"이어도 set/non-empty라 확장됨. has_legacy=0인데도
# 메시지가 "+ legacy 라인 제거"를 잘못 포함하던 버그 방지.
GITIGN_PROJECT56="$WORK_DIR/gitign-project-56"
mkdir -p "$GITIGN_PROJECT56"
git -C "$GITIGN_PROJECT56" init -q
git -C "$GITIGN_PROJECT56" config user.email "test@example.com"
git -C "$GITIGN_PROJECT56" config user.name "Test"
git -C "$GITIGN_PROJECT56" commit --allow-empty -m "initial" -q

# pre-state: legacy 라인 없음 (node_modules만)
echo 'node_modules' > "$GITIGN_PROJECT56/.gitignore"
git -C "$GITIGN_PROJECT56" add .gitignore
git -C "$GITIGN_PROJECT56" commit -q -m "chore: gitignore no legacy"

GITIGN_SPEC56="$WORK_DIR/gitign-spec-56.md"
cat > "$GITIGN_SPEC56" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---
# No Legacy Task
EOF

output56=$( (cd "$GITIGN_PROJECT56" && MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 bash "$LOOP_SH_SRC" start "no-legacy-task" --spec "$GITIGN_SPEC56" --no-pr) 2>&1 || true )
echo "$output56" | grep -q "legacy 라인 제거" \
  && { echo "FAIL: has_legacy=0인데 메시지에 \"legacy 라인 제거\" 포함. got: $output56"; exit 1; }
# 갱신 메시지 자체는 있어야 함 (새 패턴 추가됐으니)
echo "$output56" | grep -q "새 nested 패턴 추가" \
  || { echo "FAIL: .gitignore 갱신 메시지 없음. got: $output56"; exit 1; }
echo "OK"

echo "=== TEST 57: 워크트리 셋업이 main-tracked CLAUDE.md에 skip-worktree 설정 (false-positive halt 차단) ==="
# 헌법 cp가 매 iter의 git diff에 영구 modified로 남아 suppressor 게이트가 헌법 본문의 금지 설명 텍스트를
# false positive로 catch하던 문제 차단 검증. 사용자 main repo에 CLAUDE.md가 tracked인 환경 재현.
T57_PROJECT="$WORK_DIR/claude-tracked-project-57"
mkdir -p "$T57_PROJECT"
git -C "$T57_PROJECT" init -q
git -C "$T57_PROJECT" config user.email "test@example.com"
git -C "$T57_PROJECT" config user.name "Test"
echo "# user CLAUDE.md (40 lines simulated)" > "$T57_PROJECT/CLAUDE.md"
git -C "$T57_PROJECT" add CLAUDE.md
git -C "$T57_PROJECT" commit -q -m "chore: baseline with CLAUDE.md tracked"

mkdir -p "$T57_PROJECT/milestones/regular/loops/gate-skip-worktree"
cat > "$T57_PROJECT/milestones/regular/loops/gate-skip-worktree/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude:
    - CLAUDE.md
verify: 'true'
---

# Gate Test — CLAUDE.md skip-worktree
EOF

MOCK57="$WORK_DIR/mock57-bin"
mkdir -p "$MOCK57"
cat > "$MOCK57/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
# 워커가 코드 변경 0건 — 워크트리 CLAUDE.md modified만 남는 상태 재현 (fix 전엔 halt했던 시나리오)
echo '{"result": "mock57", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK57/claude"

(
  cd "$T57_PROJECT"
  set +e
  output57=$(PATH="$MOCK57:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "gate-skip-worktree" --no-pr 2>&1)
  set -e
  echo "$output57" | grep -q "Suppressor 신규 추가" \
    && { echo "FAIL: 워크트리 CLAUDE.md(헌법 cp)가 suppressor false positive halt 트리거 — skip-worktree 미작동"; echo "$output57"; exit 1; }
  echo "$output57" | grep -q "이터 상한 도달" \
    || { echo "FAIL: loop이 MAX_ITERATIONS까지 정상 진행 못함 (게이트 패스 불완전)"; echo "$output57"; exit 1; }
  # v0.2 cutover: 워크트리는 메인 레포 내부 milestones/<m>/loops/<c>/.worktree에 nested.
  # 이전 sibling 레이아웃(<project>-loops/) 경로 참조는 더 이상 유효하지 않음.
  WT57="$T57_PROJECT/milestones/regular/loops/gate-skip-worktree/.worktree"
  # skip-worktree 비트가 실제로 설정됐는지 확인
  git -C "$WT57" ls-files -v CLAUDE.md 2>/dev/null | grep -qE "^S " \
    || { echo "FAIL: CLAUDE.md에 skip-worktree 비트(S) 미설정"; git -C "$WT57" ls-files -v CLAUDE.md; exit 1; }
)
echo "OK"

echo "=== TEST 58: 워커가 CLAUDE.md unskip + commit 시 scope.exclude 위반 halt (분별 능력 활성화) ==="
# skip-worktree로 셋업 cp는 가려지지만 워커가 의도적으로 unskip하고 CLAUDE.md를 변경·commit하면
# scope check가 SPEC scope.exclude(CLAUDE.md)에 매치되어 정상 halt해야 함. 이전엔 case 절이
# CLAUDE.md를 명시 제외해 통과하던 hole 해소 검증.
T58_PROJECT="$WORK_DIR/claude-tracked-project-58"
mkdir -p "$T58_PROJECT"
git -C "$T58_PROJECT" init -q
git -C "$T58_PROJECT" config user.email "test@example.com"
git -C "$T58_PROJECT" config user.name "Test"
echo "# user CLAUDE.md" > "$T58_PROJECT/CLAUDE.md"
git -C "$T58_PROJECT" add CLAUDE.md
git -C "$T58_PROJECT" commit -q -m "chore: baseline with CLAUDE.md tracked"

mkdir -p "$T58_PROJECT/milestones/regular/loops/gate-scope-catch"
cat > "$T58_PROJECT/milestones/regular/loops/gate-scope-catch/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude:
    - CLAUDE.md
verify: 'true'
---

# Gate Test — CLAUDE.md scope catch
EOF

MOCK58="$WORK_DIR/mock58-bin"
mkdir -p "$MOCK58"
cat > "$MOCK58/claude" <<'MOCKEOF'
#!/usr/bin/env bash
cat > /dev/null
# 워커가 CLAUDE.md skip-worktree를 풀고 임의 변경 + commit — 헌법 manipulation 시도 시나리오
git update-index --no-skip-worktree CLAUDE.md 2>/dev/null || true
echo "# WORKER INJECTED" >> CLAUDE.md
git add CLAUDE.md
git commit -q -m "feat: worker tries to inject into constitution" --no-verify
echo '{"result": "mock58", "usage": {"input_tokens": 1, "output_tokens": 1}}'
MOCKEOF
chmod +x "$MOCK58/claude"

(
  cd "$T58_PROJECT"
  set +e
  output58=$(PATH="$MOCK58:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "gate-scope-catch" --no-pr 2>&1)
  set -e
  echo "$output58" | grep -qE "Scope 위반.*CLAUDE\.md" \
    || { echo "FAIL: CLAUDE.md commit이 scope.exclude 위반으로 catch 안 됨 (분별 능력 미동작)"; echo "$output58"; exit 1; }
)
echo "OK"

echo "=== TEST 59: 신규 contract — feat 브랜치 + 커밋된 SPEC를 worktree가 자연 포함 (외부 cp 없음) ==="
# 새 라이프사이클: spec 스킬이 feat/<task-id>-<slug> 브랜치에 SPEC.md를 commit. loop start는
# 그 브랜치를 직접 체크아웃해 worktree를 만들며 worktree 외부에서 SPEC를 추가 복사하지 않는다.
T59_PROJECT="$WORK_DIR/new-contract-feat"
mkdir -p "$T59_PROJECT"
git -C "$T59_PROJECT" init -q
git -C "$T59_PROJECT" config user.email "t@e.com"
git -C "$T59_PROJECT" config user.name "Test"
git -C "$T59_PROJECT" commit --allow-empty -m "initial" -q

# spec 스킬을 시뮬레이션: feat 브랜치 + SPEC commit (main 작업 트리는 변경하지 않음)
T59_BRANCH="feat/regular/n59-my-feature"
T59_LOOPS_REL="milestones/regular/loops/n59"
T59_DEFAULT_BRANCH=$(git -C "$T59_PROJECT" rev-parse --abbrev-ref HEAD)
git -C "$T59_PROJECT" checkout -q -b "$T59_BRANCH"
mkdir -p "$T59_PROJECT/$T59_LOOPS_REL"
cat > "$T59_PROJECT/$T59_LOOPS_REL/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# My Feature
EOF
git -C "$T59_PROJECT" add "$T59_LOOPS_REL/SPEC.md"
git -C "$T59_PROJECT" commit -q -m "feat(spec): n59 — My Feature"
# 원래 브랜치로 복귀 (main 트리 상태)
git -C "$T59_PROJECT" checkout -q "$T59_DEFAULT_BRANCH"
# 워킹 트리에는 SPEC.md가 없어야 (spec 스킬이 main 트리를 더럽히지 않았다는 가정)
[[ ! -f "$T59_PROJECT/$T59_LOOPS_REL/SPEC.md" ]] \
  || { echo "FAIL: setup 단계에서 main 작업 트리에 SPEC.md가 남아 있음 (test setup 오류)"; exit 1; }

(
  cd "$T59_PROJECT"
  set +e
  output59=$(MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 bash "$LOOP_SH_SRC" start "regular/n59" --no-pr 2>&1)
  result59=$?
  set -e
  WT59="$T59_PROJECT/$T59_LOOPS_REL/.worktree"
  [[ $result59 -eq 0 ]] || { echo "FAIL: 신규 contract start 실패. exit=$result59. got: $output59"; exit 1; }
  [[ -d "$WT59" ]] || { echo "FAIL: 워크트리 미생성: $WT59"; exit 1; }
  # SPEC.md는 worktree에서 자연 경로로 존재해야 (feat 브랜치 commit)
  [[ -f "$WT59/$T59_LOOPS_REL/SPEC.md" ]] \
    || { echo "FAIL: 워크트리 canonical 경로에 SPEC.md 없음 ($WT59/$T59_LOOPS_REL/SPEC.md)"; exit 1; }
  # 워크트리의 브랜치가 feat/<task-id>-<slug>여야
  CURR_BR=$(git -C "$WT59" rev-parse --abbrev-ref HEAD)
  [[ "$CURR_BR" == "$T59_BRANCH" ]] \
    || { echo "FAIL: 워크트리 브랜치가 feat가 아님 (got: $CURR_BR, expected: $T59_BRANCH)"; exit 1; }
)
echo "OK"

echo "=== TEST 60: 신규 contract cleanup — 메모리 파일 archive 안 함 + feat 브랜치 유지 ==="
# 동일 setup 재사용. --force는 mock의 untracked DONE/.loop/CLAUDE.md를 정리하기 위함
# (TEST 8과 동일 사유 — 정상 worker는 commit으로 정리)
(
  cd "$T59_PROJECT"
  bash "$LOOP_SH_SRC" cleanup "regular/n59" --force > /dev/null 2>&1
  WT60="$T59_PROJECT/$T59_LOOPS_REL/.worktree"
  [[ ! -d "$WT60" ]] || { echo "FAIL: cleanup 후 워크트리 잔존"; exit 1; }
  # 신규 contract: 메모리 파일이 archive되지 않아야
  ARCHIVE60="$T59_PROJECT/$T59_LOOPS_REL"
  [[ ! -f "$ARCHIVE60/PLAN.md" ]] \
    || { echo "FAIL: 신규 contract인데 PLAN.md가 main 작업트리로 archive됨"; exit 1; }
  [[ ! -f "$ARCHIVE60/NOTES.md" ]] \
    || { echo "FAIL: 신규 contract인데 NOTES.md가 archive됨"; exit 1; }
  [[ ! -f "$ARCHIVE60/HANDOFF.md" ]] \
    || { echo "FAIL: 신규 contract인데 HANDOFF.md가 archive됨"; exit 1; }
  [[ ! -f "$ARCHIVE60/RUN_LOG.md" ]] \
    || { echo "FAIL: 신규 contract인데 RUN_LOG.md가 archive됨"; exit 1; }
  # feat 브랜치는 보존되어야 (PR base)
  git -C "$T59_PROJECT" show-ref --verify --quiet "refs/heads/$T59_BRANCH" \
    || { echo "FAIL: cleanup 후 feat 브랜치가 사라짐: $T59_BRANCH"; exit 1; }
)
echo "OK"

echo "=== TEST 61: 신규 contract fail-fast — feat 브랜치 부재 + legacy SPEC 부재 ==="
T61_PROJECT="$WORK_DIR/new-contract-missing"
mkdir -p "$T61_PROJECT"
git -C "$T61_PROJECT" init -q
git -C "$T61_PROJECT" config user.email "t@e.com"
git -C "$T61_PROJECT" config user.name "Test"
git -C "$T61_PROJECT" commit --allow-empty -m "initial" -q
# SPEC 부재 + feat 브랜치 부재 상태에서 start
(
  cd "$T61_PROJECT"
  set +e
  output61=$(MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 bash "$LOOP_SH_SRC" start "regular/missing" --no-pr 2>&1)
  result61=$?
  set -e
  [[ $result61 -ne 0 ]] || { echo "FAIL: SPEC·feat 브랜치 둘 다 없는데 start 성공"; exit 1; }
  echo "$output61" | grep -qE "SPEC\.md|feat" \
    || { echo "FAIL: fail-fast 메시지에 SPEC·feat 안내 없음. got: $output61"; exit 1; }
  WT61="$T61_PROJECT/milestones/regular/loops/missing/.worktree"
  [[ ! -d "$WT61" ]] || { echo "FAIL: fail-fast인데 워크트리 생성됨"; exit 1; }
)
echo "OK"

echo "=== TEST 62: 신규 contract slug-fallback — feat/<task-id> (slug 없는 단독 브랜치) 동작 ==="
# 비-ASCII 제목 등으로 슬러그가 빈 경우 spec 스킬이 feat/<task-id>로 fallback. loop가 그것도 인식해야
T62_PROJECT="$WORK_DIR/new-contract-fallback"
mkdir -p "$T62_PROJECT"
git -C "$T62_PROJECT" init -q
git -C "$T62_PROJECT" config user.email "t@e.com"
git -C "$T62_PROJECT" config user.name "Test"
git -C "$T62_PROJECT" commit --allow-empty -m "initial" -q

T62_BRANCH="feat/regular/n62"      # slug 없음 — fallback
T62_LOOPS_REL="milestones/regular/loops/n62"
T62_DEFAULT_BRANCH=$(git -C "$T62_PROJECT" rev-parse --abbrev-ref HEAD)
git -C "$T62_PROJECT" checkout -q -b "$T62_BRANCH"
mkdir -p "$T62_PROJECT/$T62_LOOPS_REL"
cat > "$T62_PROJECT/$T62_LOOPS_REL/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# 비-ASCII 제목 작업 (한국어)
EOF
git -C "$T62_PROJECT" add "$T62_LOOPS_REL/SPEC.md"
git -C "$T62_PROJECT" commit -q -m "feat(spec): n62 fallback"
git -C "$T62_PROJECT" checkout -q "$T62_DEFAULT_BRANCH"

(
  cd "$T62_PROJECT"
  set +e
  output62=$(MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 bash "$LOOP_SH_SRC" start "regular/n62" --no-pr 2>&1)
  result62=$?
  set -e
  WT62="$T62_PROJECT/$T62_LOOPS_REL/.worktree"
  [[ $result62 -eq 0 ]] || { echo "FAIL: slug-fallback start 실패. exit=$result62. got: $output62"; exit 1; }
  [[ -d "$WT62" ]] || { echo "FAIL: 워크트리 미생성"; exit 1; }
  CURR_BR=$(git -C "$WT62" rev-parse --abbrev-ref HEAD)
  [[ "$CURR_BR" == "$T62_BRANCH" ]] \
    || { echo "FAIL: 워크트리 브랜치가 feat/<task-id>(fallback)가 아님 (got: $CURR_BR)"; exit 1; }
  bash "$LOOP_SH_SRC" cleanup "regular/n62" --force > /dev/null 2>&1
)
echo "OK"

echo ""
echo "=== 모든 테스트 통과 ==="
