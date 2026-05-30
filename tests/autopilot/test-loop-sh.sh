#!/usr/bin/env bash
# loop.sh 통합 테스트 (현 spec-file-driven contract)
#
# 정체성 = 스펙 파일 절대 경로. 작업 공간 = <SPEC_DIR>/.worktree.
# 메타 = <WT>/.loop/{notes.md,iterations/,signals/,BASE_SHA,SPEC_PATH}.
# terminal 신호 = <WT>/.loop/signals/ 디렉토리 비어있지 않음 (driver 는 이름·내용 미파싱).
# lock = <SPEC_DIR>/.loop-lock. driver 는 자체 commit 도 gh 호출도 하지 않는다.
#
# claude CLI 를 mock 으로 대체해 subcommand·워크트리 생성·락·게이트 분기를 검증.
#
# 구 contract 검증 항목 제거 메모 (혼합 마이그레이션 — 대응 개념 없으면 삭제):
#   - prepare 서브커맨드: 제거됨 (dispatcher 에 없음).
#   - task-id 정체성·검증('..'/'__'/공백/'.'/slash/길이/regular 정규화): 제거됨
#     (정체성이 스펙 파일 경로로 전환, 경로 sanitize 개념 소멸).
#   - milestones/<m>/loops/<c> 중첩 레이아웃: 제거됨 (스펙은 임의 경로의 파일).
#   - feat 브랜치 기반 셋업: 제거됨 (워크트리는 HEAD 에서 --detach).
#   - task-issue / gh-comment halt 모델([blocked]/[handoff]): 제거됨
#     (terminal 은 signals/ 디렉토리, halt 는 stash+stderr+exit 1).
#   - --no-pr 플래그·PR phase: 본 테스트 비대상 (start 옵션에서 제거).
#   - PLAN.md/NOTES.md 등 메타 템플릿 시드: 제거됨 (메타는 .loop/ 아래만).
#   - .gitignore nested 패턴 setup(ensure_loops_setup)·.loops/locks 라인 제거: 제거됨
#     (제외는 워크트리 git-common-dir 의 info/exclude 로 처리).
#   - placeholder/[NEEDS CLARIFICATION] start 거부: 제거됨
#     (start 는 스펙 내용을 검증하지 않음 — cmd_start 주석 참조).

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

# 루트 .gitignore — 테스트 harness 의 `git add -A` 가 워크트리/메타 잔여물을 캡처하지
# 않게 보호 (loop.sh 자체는 워크트리 git-common-dir 의 info/exclude 로 제외 관리).
cat > "$PROJECT/.gitignore" <<'EOF'
.worktree/
.loop/
.loop-lock
.loop-wt
EOF
# main-tracked CLAUDE.md — start 가 constitution 으로 덮어쓰고 skip-worktree 설정하는
# 분별 능력(false-positive halt 차단)을 검증하기 위한 baseline.
echo "# placeholder root CLAUDE.md" > "$PROJECT/CLAUDE.md"
git add -A
git commit -q -m "chore: baseline (.gitignore + CLAUDE.md)"

# claude CLI mock — PATH 앞에 둠. 기본 동작: 즉시 terminal 신호(signals/DONE) 생성.
# iterate() 는 cd "$WT" 상태로 claude 를 호출하므로 cwd = 워크트리 루트.
MOCK_BIN="$WORK_DIR/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
mkdir -p .loop/signals
: > .loop/signals/DONE
echo '{"result": "mock", "usage": {"input_tokens": 100, "output_tokens": 50}}'
EOF
chmod +x "$MOCK_BIN/claude"
export PATH="$MOCK_BIN:$PATH"

# yq 의존 확인
command -v yq >/dev/null || { echo "SKIP: yq 미설치"; exit 0; }

# loop.sh 호출 헬퍼 (현 contract: start 에 추가 플래그 주입 없음)
loop() { bash "$LOOP_SH_SRC" "$@"; }

# 스펙 파일 생성 + 커밋 → 절대 경로 echo.
# 사용: SPEC=$(mkspec <name> <<'EOF' ...frontmatter+본문... EOF)
mkspec() {
  local name="$1"
  local dir="$PROJECT/specs/$name"
  mkdir -p "$dir"
  cat > "$dir/SPEC.md"
  git -C "$PROJECT" add -A
  git -C "$PROJECT" commit -q -m "spec: $name" >/dev/null
  printf '%s\n' "$dir/SPEC.md"
}

# 커스텀 mock claude 생성 → 디렉토리 경로 echo. 본문은 stdin 으로.
# 사용: M=$(mkmock <name> <<'EOF' ...script... EOF)
mkmock() {
  local d="$WORK_DIR/mock-$1"
  mkdir -p "$d"
  cat > "$d/claude"
  chmod +x "$d/claude"
  printf '%s\n' "$d"
}

PASS=0
ok() { echo "OK"; PASS=$((PASS + 1)); }

# ---------------------------------------------------------------------------
echo "=== TEST 1: 존재하지 않는 스펙 경로로 start 거부 ==="
set +e
output=$(loop start "$PROJECT/specs/nope/SPEC.md" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 비존재 스펙으로 start 가 성공함"; exit 1; }
echo "$output" | grep -q "스펙 파일을 찾을 수 없음" \
  || { echo "FAIL: '스펙 파일을 찾을 수 없음' 메시지 없음. got: $output"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 2: start 로 워크트리 생성 + 1 이터 (mock 즉시 DONE) ==="
SPEC2=$(mkspec basic <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Basic Test
## 무엇을 만들 것인가
Test task
EOF
)
BASE2=$(git -C "$PROJECT" rev-parse HEAD)
WT2="$PROJECT/specs/basic/.worktree"
MAX_ITERATIONS=10 WALL_CLOCK_MINUTES=10 loop start "$SPEC2"
[[ -d "$WT2" ]] || { echo "FAIL: 워크트리 미생성"; exit 1; }
[[ -f "$WT2/CLAUDE.md" ]] || { echo "FAIL: CLAUDE.md 미복사"; exit 1; }
diff "$CONSTITUTION_SRC" "$WT2/CLAUDE.md" >/dev/null \
  || { echo "FAIL: CLAUDE.md가 constitution.md와 다름"; exit 1; }
# 메타는 .loop/ 아래 (구 contract 의 .iterations/·PLAN.md 시드 아님)
[[ -f "$WT2/.loop/BASE_SHA" ]] || { echo "FAIL: .loop/BASE_SHA 미생성"; exit 1; }
[[ -f "$WT2/.loop/iterations/1.log" ]] || { echo "FAIL: .loop/iterations/1.log 미생성"; exit 1; }
[[ -f "$WT2/.loop/signals/DONE" ]] || { echo "FAIL: signals/DONE 미생성"; exit 1; }
[[ -f "$WT2/.loop/SPEC_PATH" ]] || { echo "FAIL: .loop/SPEC_PATH 미기록"; exit 1; }
[[ ! -f "$WT2/specs/basic/PLAN.md" ]] || { echo "FAIL: 구 contract PLAN.md가 시드됨"; exit 1; }
# git-common-dir info/exclude 에 제외 패턴 등록
GCD2=$(git -C "$WT2" rev-parse --git-common-dir); [[ "$GCD2" == /* ]] || GCD2="$WT2/$GCD2"
for pat in "CLAUDE.md" ".worktree/" ".loop/" ".loop-lock" ".loop-wt"; do
  grep -qxF "$pat" "$GCD2/info/exclude" || { echo "FAIL: exclude 에 $pat 없음"; exit 1; }
done
# BASE_SHA = worktree 생성 시점 부모 HEAD
[[ "$(tr -d '[:space:]' < "$WT2/.loop/BASE_SHA")" == "$BASE2" ]] \
  || { echo "FAIL: BASE_SHA 내용이 부모 HEAD와 불일치"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 3: 같은 스펙 이중 start 차단 (락) ==="
# TEST 2 의 worktree+DONE 가 남아있는 상태. lock 은 trap 으로 이미 해제됐으므로
# 살아있는 PID lock 을 직접 만들어 재진입 차단을 검증.
LOCK2="$PROJECT/specs/basic/.loop-lock"
echo "$$" > "$LOCK2"
set +e
output=$(loop start "$SPEC2" 2>&1)
result=$?
set -e
rm -f "$LOCK2"
[[ $result -ne 0 ]] || { echo "FAIL: 살아있는 lock 이 있는데 start 성공"; exit 1; }
echo "$output" | grep -q "이미 실행 중" || { echo "FAIL: '이미 실행 중' 메시지 없음. got: $output"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 4: status 가 해당 스펙의 terminal 상태 출력 ==="
out=$(loop status "$SPEC2" 2>&1)
echo "$out" | grep -q "DONE" || { echo "FAIL: status 에 signals(DONE) 미표시. got: $out"; exit 1; }
echo "$out" | grep -qE "terminal" || { echo "FAIL: status STATE 가 terminal 아님. got: $out"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 5: 기록 없는 스펙 status → 안내 메시지 ==="
SPEC_NR=$(mkspec norecord <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# No Record
EOF
)
out=$(loop status "$SPEC_NR" 2>&1)
echo "$out" | grep -q "실행 기록이 없습니다" || { echo "FAIL: 기록 없음 안내 메시지 없음. got: $out"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 6: list 가 실행을 열거 ==="
out=$(loop list 2>&1)
echo "$out" | grep -q "KEY" || { echo "FAIL: list 헤더 없음. got: $out"; exit 1; }
echo "$out" | grep -q "$SPEC2" || { echo "FAIL: list 에 basic 스펙 미표시. got: $out"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 7: cleanup 이 terminal 신호 없으면 거부 (--force 없이) ==="
# 신호 디렉토리를 비워 terminal 부재 상태로 만듦.
rm -f "$WT2/.loop/signals/"* 2>/dev/null || true
set +e
output=$(loop cleanup "$SPEC2" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: terminal 신호 없는데 cleanup 성공"; exit 1; }
echo "$output" | grep -q "terminal 신호가 없습니다" || { echo "FAIL: 거부 메시지 없음. got: $output"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 8: cleanup --force 로 워크트리 정리 ==="
loop cleanup "$SPEC2" --force >/dev/null 2>&1
[[ ! -d "$WT2" ]] || { echo "FAIL: --force cleanup 후 워크트리 잔존"; exit 1; }
[[ ! -f "$PROJECT/specs/basic/.loop-lock" ]] || { echo "FAIL: cleanup 후 lock 잔존"; exit 1; }
[[ ! -f "$PROJECT/specs/basic/.loop-wt" ]] || { echo "FAIL: cleanup 후 .loop-wt 잔존"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 9: cleanup 워크트리 부재 → 적절한 에러 ==="
set +e
output=$(loop cleanup "$SPEC2" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 워크트리 없는데 cleanup 성공"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 10: stop 이 stale lock(죽은 PID) 정리 ==="
SPEC_ST=$(mkspec stalelock <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Stale Lock
EOF
)
# 죽은 PID 로 lock 위조 (큰 PID — 비활성 가정)
DEAD_PID=999999
echo "$DEAD_PID" > "$PROJECT/specs/stalelock/.loop-lock"
out=$(loop stop "$SPEC_ST" 2>&1)
echo "$out" | grep -qE "stale|비활성" || { echo "FAIL: stale lock 정리 메시지 없음. got: $out"; exit 1; }
[[ ! -f "$PROJECT/specs/stalelock/.loop-lock" ]] || { echo "FAIL: stop 후 stale lock 잔존"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 11: acquire_lock 이 stale lock(죽은 PID) 자동 정리 (sourced) ==="
(
  set +e
  source "$LOOP_SH_SRC"
  LOCK_FILE="$WORK_DIR/al-stale.lock"
  SPEC_PATH="x"
  echo "999999" > "$LOCK_FILE"
  ( acquire_lock; [[ "$(cat "$LOCK_FILE")" == "$$" ]] ) || exit 1
)
[[ $? -eq 0 ]] || { echo "FAIL: acquire_lock 이 stale lock 자동 정리 실패"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 12: acquire_lock 이 빈/비숫자 PID 도 stale 로 인식 (sourced) ==="
(
  set +e
  source "$LOOP_SH_SRC"
  LOCK_FILE="$WORK_DIR/al-empty.lock"
  SPEC_PATH="x"
  : > "$LOCK_FILE"          # 빈 PID
  ( acquire_lock ) || exit 1
  LOCK_FILE="$WORK_DIR/al-nan.lock"
  echo "not-a-pid" > "$LOCK_FILE"
  ( acquire_lock ) || exit 1
)
[[ $? -eq 0 ]] || { echo "FAIL: acquire_lock 이 빈/비숫자 PID 를 stale 로 처리하지 못함"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 13: 메타(.loop/)는 scope 게이트에 잡히지 않음 + in-scope 변경 정상 ==="
# 회귀: 워커가 in-scope 코드 변경 + signals 작성을 함께 해도 scope 게이트 false-positive 없음.
# 메타·신호는 모두 .loop/ 아래(info/exclude)라 git diff 에 나타나지 않는다.
SPEC13=$(mkspec scope-framework <<'EOF'
---
scope:
  include:
    - "app/**"
  exclude:
    - "rules/**"
verify: 'true'
---
# Scope Framework
EOF
)
M13=$(mkmock scope-fw <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
if [[ ! -f .loop/did ]]; then
  : > .loop/did
  # in-scope 코드 변경을 커밋하고 신호는 보내지 않음 → 게이트가 실제로 평가됨
  mkdir -p app; echo "print('hi')" > app/main.py
  git add app/main.py; git commit -q -m "feat: hello" --no-verify
else
  mkdir -p .loop/signals; : > .loop/signals/DONE
fi
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
WT13="$PROJECT/specs/scope-framework/.worktree"
set +e
output=$(PATH="$M13:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 loop start "$SPEC13" 2>&1)
result=$?
set -e
[[ $result -eq 0 ]] || { echo "FAIL: in-scope 변경 + 메타 활동에 scope 게이트 false-positive. exit=$result"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "Scope 위반" && { echo "FAIL: scope 게이트가 메타/in-scope 를 위반으로 잡음"; exit 1; }
loop cleanup "$SPEC13" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 14: scope 위반(out-of-scope 커밋) 게이트 halt (BASE..HEAD) ==="
SPEC14=$(mkspec scope-violate <<'EOF'
---
scope:
  include:
    - "src/**"
  exclude: []
verify: 'true'
---
# Scope Violate
EOF
)
M14=$(mkmock scope-violate <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
echo "out of scope" > bad.txt
git add bad.txt; git commit -q -m "feat: out of scope" --no-verify
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M14:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC14" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: out-of-scope 커밋에도 halt 없이 0 exit"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -qE "Scope 위반|bad\.txt" || { echo "FAIL: scope 위반 메시지 없음. got: $output"; exit 1; }
loop cleanup "$SPEC14" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 15: 테스트 약화 게이트 — 기존 테스트 삭제 halt ==="
SPEC15=$(mkspec weaken-delete <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Weaken Delete
EOF
)
# 기존 테스트 파일 1개를 미리 커밋 (워크트리에 포함되도록)
mkdir -p "$PROJECT/specs/weaken-delete/tsrc"
echo "def test_a(): pass" > "$PROJECT/specs/weaken-delete/tsrc/a_test.py"
git -C "$PROJECT" add -A; git -C "$PROJECT" commit -q -m "test: seed a_test"
M15=$(mkmock weaken-delete <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
git rm -q specs/weaken-delete/tsrc/a_test.py
git commit -q -m "remove: a_test" --no-verify
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M15:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 loop start "$SPEC15" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 테스트 삭제에도 halt 없음"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "테스트 약화" || { echo "FAIL: 테스트 약화 halt 메시지 없음. got: $output"; exit 1; }
loop cleanup "$SPEC15" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 16: 테스트 약화 게이트 — 기존 테스트 수정 halt ==="
SPEC16=$(mkspec weaken-modify <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Weaken Modify
EOF
)
mkdir -p "$PROJECT/specs/weaken-modify/tsrc"
echo "def test_b(): assert True" > "$PROJECT/specs/weaken-modify/tsrc/b_test.py"
git -C "$PROJECT" add -A; git -C "$PROJECT" commit -q -m "test: seed b_test"
M16=$(mkmock weaken-modify <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
echo "def test_b(): pass  # weakened" > specs/weaken-modify/tsrc/b_test.py
git add specs/weaken-modify/tsrc/b_test.py
git commit -q -m "fix: weaken b_test" --no-verify
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M16:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 loop start "$SPEC16" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 테스트 수정에도 halt 없음"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "테스트 약화" || { echo "FAIL: 테스트 약화 halt 메시지 없음. got: $output"; exit 1; }
loop cleanup "$SPEC16" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 17: 새 테스트 추가는 weakening 게이트 통과 (TDD RED 보호) ==="
SPEC17=$(mkspec weaken-add <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Weaken Add
EOF
)
M17=$(mkmock weaken-add <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
if [[ ! -f .loop/added ]]; then
  : > .loop/added
  mkdir -p newt; echo "def test_new(): pass" > newt/new_test.py
  git add newt/new_test.py; git commit -q -m "test: add new_test" --no-verify
else
  mkdir -p .loop/signals; : > .loop/signals/DONE
fi
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M17:$PATH" MAX_ITERATIONS=3 WALL_CLOCK_MINUTES=5 loop start "$SPEC17" 2>&1)
result=$?
set -e
[[ $result -eq 0 ]] || { echo "FAIL: 새 테스트 추가가 halt 됨. exit=$result"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "테스트 약화" && { echo "FAIL: 새 테스트 추가를 약화로 오판"; exit 1; }
loop cleanup "$SPEC17" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 18: SPEC test_paths override 가 기본 휴리스틱 대체 ==="
SPEC18=$(mkspec test-paths <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
test_paths:
  - "specs/test-paths/lib/**"
verify: 'true'
---
# Test Paths Override
EOF
)
mkdir -p "$PROJECT/specs/test-paths/lib"
echo "x = 1" > "$PROJECT/specs/test-paths/lib/foo.py"
git -C "$PROJECT" add -A; git -C "$PROJECT" commit -q -m "seed lib/foo"
M18=$(mkmock test-paths <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
echo "x = 2  # changed" > specs/test-paths/lib/foo.py
git add specs/test-paths/lib/foo.py
git commit -q -m "change lib/foo" --no-verify
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M18:$PATH" MAX_ITERATIONS=2 WALL_CLOCK_MINUTES=5 loop start "$SPEC18" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: test_paths override 대상 변경에도 halt 없음"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "테스트 약화" || { echo "FAIL: override 대상 약화 halt 없음. got: $output"; exit 1; }
loop cleanup "$SPEC18" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 19: test_sweep_paths 선언 시 sweep 내 테스트 삭제는 halt 안 함 ==="
SPEC19=$(mkspec sweep-ok <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
test_sweep_paths:
  - "specs/sweep-ok/swept/**"
verify: 'true'
---
# Sweep OK
EOF
)
mkdir -p "$PROJECT/specs/sweep-ok/swept" "$PROJECT/specs/sweep-ok/keep"
echo "def test_old(): pass" > "$PROJECT/specs/sweep-ok/swept/old_test.py"
echo "def test_keep(): pass" > "$PROJECT/specs/sweep-ok/keep/keep_test.py"
git -C "$PROJECT" add -A; git -C "$PROJECT" commit -q -m "seed sweep files"
M19=$(mkmock sweep-ok <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
if [[ ! -f .loop/swept ]]; then
  : > .loop/swept
  git rm -q specs/sweep-ok/swept/old_test.py
  git commit -q -m "cleanup: remove swept old_test" --no-verify
else
  mkdir -p .loop/signals; : > .loop/signals/DONE
fi
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M19:$PATH" MAX_ITERATIONS=3 WALL_CLOCK_MINUTES=5 loop start "$SPEC19" 2>&1)
result=$?
set -e
[[ $result -eq 0 ]] || { echo "FAIL: sweep 내 테스트 삭제가 halt 됨. exit=$result"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "테스트 약화" && { echo "FAIL: sweep 내 삭제를 약화로 오판"; exit 1; }
loop cleanup "$SPEC19" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 20: test_sweep_paths 매칭 0건 → WARN 경고 + halt 없음 ==="
SPEC20=$(mkspec sweep-nomatch <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
test_sweep_paths:
  - "specs/sweep-nomatch/nonexistent/**"
verify: 'true'
---
# Sweep No Match
EOF
)
set +e
output=$(MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC20" 2>&1)
result=$?
set -e
[[ $result -eq 0 ]] || { echo "FAIL: sweep no-match 인데 비정상 종료. exit=$result"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "test_sweep_paths 선언됐으나 매칭 파일 없음" \
  || { echo "FAIL: sweep no-match WARN 경고 없음. got: $output"; exit 1; }
loop cleanup "$SPEC20" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 21: sweep 밖 기존 테스트 수정은 여전히 weakening halt ==="
M21=$(mkmock sweep-outside <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
echo "def test_keep(): pass  # weakened" > specs/sweep-ok/keep/keep_test.py
git add specs/sweep-ok/keep/keep_test.py
git commit -q -m "weaken keep_test" --no-verify
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
# SPEC19 의 sweep 선언을 재사용 (swept/** 만 sweep; keep/** 은 보호 대상)
set +e
output=$(PATH="$M21:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC19" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: sweep 밖 테스트 수정에도 halt 없음"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "테스트 약화" || { echo "FAIL: sweep 밖 약화 halt 없음. got: $output"; exit 1; }
loop cleanup "$SPEC19" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 22: 의존성 manifest 변경 게이트 halt ==="
SPEC22=$(mkspec dep-change <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Dep Change
EOF
)
# 워크트리 루트에 package.json 이 있도록 PROJECT 루트에 커밋 (maxdepth 2 내)
echo '{"name":"x","version":"1.0.0"}' > "$PROJECT/package.json"
git -C "$PROJECT" add -A; git -C "$PROJECT" commit -q -m "chore: add package.json"
M22=$(mkmock dep-change <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
echo '{"name":"x","version":"2.0.0"}' > package.json
git add package.json; git commit -q -m "chore: bump dep" --no-verify
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M22:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC22" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: manifest 변경에도 halt 없음"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "의존성 변경" || { echo "FAIL: 의존성 변경 halt 메시지 없음. got: $output"; exit 1; }
loop cleanup "$SPEC22" --force >/dev/null 2>&1
# 후속 테스트 오염 방지: package.json 제거
git -C "$PROJECT" rm -q package.json; git -C "$PROJECT" commit -q -m "chore: drop package.json"
ok

# ---------------------------------------------------------------------------
echo "=== TEST 23: suppressor 신규 추가 게이트 halt (커밋) ==="
SPEC23=$(mkspec suppressor <<'EOF'
---
scope:
  include: ["**"]
  exclude: []
verify: 'true'
---
# Suppressor
EOF
)
M23=$(mkmock suppressor <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
printf 'x = 1  # noqa\n' > sup.py
git add sup.py; git commit -q -m "feat: add sup" --no-verify
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M23:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC23" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: suppressor 추가에도 halt 없음"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "Suppressor 신규 추가" || { echo "FAIL: suppressor halt 메시지 없음. got: $output"; exit 1; }
loop cleanup "$SPEC23" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 24: suppressor 게이트가 미커밋(working tree) 변경도 감지 ==="
SPEC24=$(mkspec suppressor-wt <<'EOF'
---
scope:
  include: ["**"]
  exclude: []
verify: 'true'
---
# Suppressor WT
EOF
)
# tracked 파일을 미리 커밋 — working tree 수정이 git diff HEAD 에 나타나도록
# (untracked 신규 파일은 git diff 에 잡히지 않으므로 추적 파일 수정으로 검증).
mkdir -p "$PROJECT/specs/suppressor-wt/src"
echo "const a = 1;" > "$PROJECT/specs/suppressor-wt/src/base.js"
git -C "$PROJECT" add -A; git -C "$PROJECT" commit -q -m "seed base.js"
M24=$(mkmock suppressor-wt <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
# 커밋하지 않고 working tree 의 tracked 파일에 suppressor 추가
printf 'const b = 2;  // eslint-disable\n' >> specs/suppressor-wt/src/base.js
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M24:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC24" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 미커밋 suppressor 에도 halt 없음"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "Suppressor 신규 추가" || { echo "FAIL: 미커밋 suppressor halt 없음. got: $output"; exit 1; }
loop cleanup "$SPEC24" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 25: fix:symptom streak 게이트 halt (2회 연속) ==="
SPEC25=$(mkspec streak <<'EOF'
---
scope:
  include: ["**"]
  exclude: []
verify: 'true'
---
# Streak
EOF
)
M25=$(mkmock streak <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
echo a > s1.txt; git add s1.txt; git commit -q -m "fix:symptom 우회 1" --no-verify
echo b > s2.txt; git add s2.txt; git commit -q -m "fix:symptom 우회 2" --no-verify
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M25:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC25" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: fix:symptom 2연속에도 halt 없음"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "fix:symptom streak" || { echo "FAIL: streak halt 메시지 없음. got: $output"; exit 1; }
loop cleanup "$SPEC25" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 26: 진동 패턴 게이트 halt (최근 4 커밋 두 상태 토글) ==="
SPEC26=$(mkspec oscillation <<'EOF'
---
scope:
  include: ["**"]
  exclude: []
verify: 'true'
---
# Oscillation
EOF
)
M26=$(mkmock oscillation <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
for i in 1 2; do
  echo "a$i" > osc_a.txt; git add osc_a.txt; git commit -q -m "edit a $i" --no-verify
  echo "b$i" > osc_b.txt; git add osc_b.txt; git commit -q -m "edit b $i" --no-verify
done
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M26:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC26" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: 진동 패턴에도 halt 없음"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -q "진동 패턴" || { echo "FAIL: 진동 halt 메시지 없음. got: $output"; exit 1; }
loop cleanup "$SPEC26" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 27: secrets 게이트 (gitleaks 설치 시) ==="
if command -v gitleaks >/dev/null 2>&1; then
  SPEC27=$(mkspec secrets <<'EOF'
---
scope:
  include: ["**"]
  exclude: []
verify: 'true'
---
# Secrets
EOF
)
  M27=$(mkmock secrets <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
printf 'aws_secret_access_key = "AKIAIOSFODNN7EXAMPLEKEYDATA1234567890abc"\n' > leak.txt
git add leak.txt; git commit -q -m "oops" --no-verify
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
  set +e
  output=$(PATH="$M27:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC27" 2>&1)
  result=$?
  set -e
  [[ $result -ne 0 ]] || { echo "FAIL: secret 커밋에도 halt 없음"; echo "$output" | tail -10; exit 1; }
  echo "$output" | grep -q "Secrets 의심" || { echo "FAIL: secrets halt 메시지 없음. got: $output"; exit 1; }
  loop cleanup "$SPEC27" --force >/dev/null 2>&1
  ok
else
  echo "SKIP: gitleaks 미설치 — secrets 게이트 검증 생략"
fi

# ---------------------------------------------------------------------------
echo "=== TEST 28: halt 시 미커밋 변경이 stash 로 보관되면 WARN 출력 ==="
# TEST 24(미커밋 suppressor)와 동일 메커니즘 — halt 직전 미커밋 변경 존재 → stash WARN.
SPEC28=$(mkspec halt-stash <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Halt Stash
EOF
)
M28=$(mkmock halt-stash <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
# 미커밋 suppressor → suppressor halt 직전 working tree 에 변경 존재
printf 'z = 3  # noqa\n' > pending.py
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M28:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC28" 2>&1)
set -e
echo "$output" | grep -q "stash" || { echo "FAIL: halt 시 stash WARN 없음. got: $output"; exit 1; }
loop cleanup "$SPEC28" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 29: shasum fallback (sha256sum 부재 환경에서도 동작) ==="
# sha256sum 을 PATH 에서 가려 shasum 경로를 강제.
SHADIR="$WORK_DIR/no-sha256"
mkdir -p "$SHADIR"
cat > "$SHADIR/sha256sum" <<'EOF'
#!/usr/bin/env bash
echo "sha256sum: not available" >&2
exit 127
EOF
chmod +x "$SHADIR/sha256sum"
if command -v shasum >/dev/null 2>&1; then
  SPEC29=$(mkspec shasum-fb <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Shasum Fallback
EOF
)
  set +e
  output=$(PATH="$SHADIR:$MOCK_BIN:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC29" 2>&1)
  result=$?
  set -e
  [[ $result -eq 0 ]] || { echo "FAIL: shasum fallback 경로에서 start 실패. exit=$result"; echo "$output" | tail -10; exit 1; }
  loop cleanup "$SPEC29" --force >/dev/null 2>&1
  ok
else
  echo "SKIP: shasum 미설치 — fallback 검증 생략"
fi

# ---------------------------------------------------------------------------
echo "=== TEST 30: stop 이 실행 중 claude 자식까지 종료 (orphan 방지) ==="
SPEC30=$(mkspec orphan <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Orphan Prevent
EOF
)
CLAUDE_PID_FILE="$WORK_DIR/orphan-claude.pid"
M30=$(mkmock orphan <<MOCKEOF
#!/usr/bin/env bash
cat > /dev/null
echo \$\$ > "$CLAUDE_PID_FILE"
sleep 60
MOCKEOF
)
rm -f "$CLAUDE_PID_FILE"
PATH="$M30:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 \
  bash "$LOOP_SH_SRC" start "$SPEC30" > "$WORK_DIR/orphan.log" 2>&1 &
for _ in 1 2 3 4 5 6 7 8; do [[ -f "$CLAUDE_PID_FILE" ]] && break; sleep 1; done
[[ -f "$CLAUDE_PID_FILE" ]] || { echo "FAIL: mock claude 미시작"; exit 1; }
CLAUDE_REAL_PID=$(cat "$CLAUDE_PID_FILE")
loop stop "$SPEC30" >/dev/null 2>&1
ORPHAN_DEAD=0
for _ in 1 2 3 4; do kill -0 "$CLAUDE_REAL_PID" 2>/dev/null || { ORPHAN_DEAD=1; break; }; sleep 1; done
[[ $ORPHAN_DEAD -eq 1 ]] || { kill -KILL "$CLAUDE_REAL_PID" 2>/dev/null; echo "FAIL: stop 후 claude 자식 orphan 잔존"; exit 1; }
[[ ! -f "$PROJECT/specs/orphan/.loop-lock" ]] || { echo "FAIL: stop 후 lock 잔존"; exit 1; }
loop cleanup "$SPEC30" --force >/dev/null 2>&1 || true
ok

# ---------------------------------------------------------------------------
echo "=== TEST 31: --force cleanup 이 실행 중 프로세스를 먼저 SIGTERM ==="
SPEC31=$(mkspec force-cleanup <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Force Cleanup
EOF
)
CLAUDE_PID_FILE_31="$WORK_DIR/force-claude.pid"
M31=$(mkmock force-cleanup <<MOCKEOF
#!/usr/bin/env bash
cat > /dev/null
echo \$\$ > "$CLAUDE_PID_FILE_31"
sleep 60
MOCKEOF
)
rm -f "$CLAUDE_PID_FILE_31"
PATH="$M31:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=10 \
  bash "$LOOP_SH_SRC" start "$SPEC31" > "$WORK_DIR/force.log" 2>&1 &
LOOP_PID_31=$!
for _ in 1 2 3 4 5 6 7 8; do [[ -f "$CLAUDE_PID_FILE_31" ]] && break; sleep 1; done
[[ -f "$CLAUDE_PID_FILE_31" ]] || { echo "FAIL: mock claude 미시작"; kill -KILL "$LOOP_PID_31" 2>/dev/null; exit 1; }
CLAUDE_PID_31=$(cat "$CLAUDE_PID_FILE_31")
LOCK_FILE_31="$PROJECT/specs/force-cleanup/.loop-lock"
[[ -f "$LOCK_FILE_31" ]] || { echo "FAIL: lock 미생성"; exit 1; }
loop cleanup "$SPEC31" --force >/dev/null 2>&1
ALL_DEAD=0
for _ in 1 2 3 4; do
  if ! kill -0 "$LOOP_PID_31" 2>/dev/null && ! kill -0 "$CLAUDE_PID_31" 2>/dev/null; then ALL_DEAD=1; break; fi
  sleep 1
done
[[ $ALL_DEAD -eq 1 ]] || { kill -KILL "$LOOP_PID_31" "$CLAUDE_PID_31" 2>/dev/null; echo "FAIL: --force cleanup 후 프로세스 잔존"; exit 1; }
[[ ! -f "$LOCK_FILE_31" ]] || { echo "FAIL: cleanup 후 lock 잔존"; exit 1; }
[[ ! -d "$PROJECT/specs/force-cleanup/.worktree" ]] || { echo "FAIL: cleanup 후 워크트리 잔존"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo "=== TEST 32: 워크트리 셋업이 main-tracked CLAUDE.md 에 skip-worktree 설정 ==="
SPEC32=$(mkspec skipwt <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Skip Worktree
EOF
)
WT32="$PROJECT/specs/skipwt/.worktree"
MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC32" >/dev/null 2>&1
# CLAUDE.md 가 tracked 이고 skip-worktree 비트(S)가 설정돼야 함
git -C "$WT32" ls-files -v CLAUDE.md | grep -q '^S' \
  || { echo "FAIL: CLAUDE.md skip-worktree 비트 미설정. got: $(git -C "$WT32" ls-files -v CLAUDE.md)"; exit 1; }
loop cleanup "$SPEC32" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 33: 워커가 CLAUDE.md unskip + commit 시 scope.exclude 위반 halt ==="
SPEC33=$(mkspec exclude-claude <<'EOF'
---
scope:
  include: ["**/*"]
  exclude:
    - "CLAUDE.md"
verify: 'true'
---
# Exclude CLAUDE
EOF
)
M33=$(mkmock exclude-claude <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
git config user.email t@e.com; git config user.name T
git update-index --no-skip-worktree CLAUDE.md 2>/dev/null || true
printf '\n# worker tamper\n' >> CLAUDE.md
git add CLAUDE.md; git commit -q -m "chore: tamper CLAUDE.md" --no-verify
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M33:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC33" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: CLAUDE.md(scope.exclude) 커밋에도 halt 없음"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -qE "Scope 위반|CLAUDE\.md" || { echo "FAIL: scope.exclude 위반 halt 없음. got: $output"; exit 1; }
loop cleanup "$SPEC33" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 34: BASE_SHA 메타 부재 워크트리에서 게이트 명확한 halt ==="
SPEC34=$(mkspec missing-base <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Missing Base
EOF
)
# 1차: 정상 start (DONE) → BASE_SHA 생성.
MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC34" >/dev/null 2>&1
WT34="$PROJECT/specs/missing-base/.worktree"
[[ -f "$WT34/.loop/BASE_SHA" ]] || { echo "FAIL (전제): 1차 start 에서 BASE_SHA 미생성"; exit 1; }
# BASE_SHA 와 DONE 제거 후 noop mock 으로 재진입 → 게이트가 BASE_SHA 부재로 halt.
rm -f "$WT34/.loop/BASE_SHA" "$WT34/.loop/signals/"*
M34=$(mkmock missing-base <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo '{"result":"mock","usage":{"input_tokens":1,"output_tokens":1}}'
EOF
)
set +e
output=$(PATH="$M34:$PATH" MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC34" 2>&1)
result=$?
set -e
[[ $result -ne 0 ]] || { echo "FAIL: BASE_SHA 부재인데 0 exit 통과"; echo "$output" | tail -10; exit 1; }
echo "$output" | grep -qiE "BASE.?SHA" || { echo "FAIL: BASE_SHA 부재 진단 메시지 없음. got: $output"; exit 1; }
loop cleanup "$SPEC34" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 35: driver 는 자체 commit 을 만들지 않고 메타는 .loop/ 에 untracked ==="
SPEC35=$(mkspec no-meta-commit <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# No Meta Commit
EOF
)
BASE35=$(git -C "$PROJECT" rev-parse HEAD)
WT35="$PROJECT/specs/no-meta-commit/.worktree"
MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 loop start "$SPEC35" >/dev/null 2>&1
# driver/mock 무변경 → 워크트리 HEAD == 생성 시점 BASE (driver 메타 commit 0건)
[[ "$(git -C "$WT35" rev-parse HEAD)" == "$BASE35" ]] \
  || { echo "FAIL: driver 가 워크트리에 commit 을 만듦 (HEAD != BASE)"; exit 1; }
# 메타는 .loop/ 아래 untracked (git status 에 .loop 안 나옴 — info/exclude)
git -C "$WT35" status --porcelain | grep -q '\.loop' \
  && { echo "FAIL: .loop/ 메타가 git 에 추적됨 (untracked 여야 함)"; exit 1; }
# 구 contract 메타 템플릿이 워크트리에 잔존하지 않음
for meta_f in PLAN.md NOTES.md HANDOFF.md RUN_LOG.md ESCALATION.md; do
  [[ ! -f "$WT35/$meta_f" ]] || { echo "FAIL: 구 contract 메타 $meta_f 잔존"; exit 1; }
done
loop cleanup "$SPEC35" --force >/dev/null 2>&1
ok

# ---------------------------------------------------------------------------
echo "=== TEST 36: env/gates/paths/deps self-emit 단일 출처 동작 ==="
# 출력을 먼저 캡처한 뒤 grep — pipefail + grep -q 의 SIGPIPE 오탐 회피.
env_out=$(loop env);   grep -q "MAX_ITERATIONS" <<< "$env_out"  || { echo "FAIL: env 출력에 MAX_ITERATIONS 없음"; exit 1; }
gates_out=$(loop gates); grep -qE "scope 위반|scope" <<< "$gates_out" || { echo "FAIL: gates 출력에 scope 게이트 없음"; exit 1; }
deps_out=$(loop deps); grep -qi "yq" <<< "$deps_out"            || { echo "FAIL: deps 출력에 yq 없음"; exit 1; }
SPEC36=$(mkspec paths-check <<'EOF'
---
scope:
  include: ["**/*"]
  exclude: []
verify: 'true'
---
# Paths Check
EOF
)
pout=$(loop paths "$SPEC36" 2>&1)
echo "$pout" | grep -q "SPEC_PATH" || { echo "FAIL: paths 출력에 SPEC_PATH 없음. got: $pout"; exit 1; }
echo "$pout" | grep -q "WT" || { echo "FAIL: paths 출력에 WT 없음"; exit 1; }
echo "$pout" | grep -q "LOOP_DIR" || { echo "FAIL: paths 출력에 LOOP_DIR 없음"; exit 1; }
ok

# ---------------------------------------------------------------------------
echo ""
echo "=== 모든 테스트 통과 ($PASS) ==="
