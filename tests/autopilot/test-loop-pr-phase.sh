#!/usr/bin/env bash
# test-loop-pr-phase.sh — loop DONE 이후 PR 생성·재사용 phase 단위·e2e 테스트
#
# 검증 대상:
# - `request_review` opt-in 감지 + skip 경로 (AC1)
# - 메타 플래그 미지정: --reviewer/--label/--assignee 없음 (AC7)
# - (후속 이터: default branch 감지 실패 abort, body 합성, open PR 재사용, push 실패 등)
#
# 모든 외부 호출(gh·git push)은 stub binary로 격리해 네트워크·원격 접근을 발생시키지 않음.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_REFS="$REPO_ROOT/plugins/autopilot/skills/loop/references"
LOOP_SH_SRC="$SKILL_REFS/loop.sh"

[[ -x "$LOOP_SH_SRC" ]] || { echo "FAIL: loop.sh 실행 불가"; exit 1; }

# 임시 작업 공간
WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf $WORK_DIR" EXIT

command -v yq >/dev/null || { echo "SKIP: yq 미설치"; exit 0; }

# ----- 공용 헬퍼 -----

# 가짜 프로젝트 repo 생성 (bare repo를 origin으로 부착해 push가 실제 네트워크에 안 나감)
make_project_with_remote() {
  local name="$1"
  local project="$WORK_DIR/$name"
  local bare="$WORK_DIR/$name.git"

  git init -q --bare "$bare"
  mkdir -p "$project"
  cd "$project"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git remote add origin "$bare"
  git commit --allow-empty -q -m "initial"
  git commit --allow-empty -q -m "chore: baseline"
  git push -q origin master 2>/dev/null || git push -q origin main 2>/dev/null || git push -q origin HEAD
  cd - >/dev/null

  echo "$project"
}

# 매번 새 mock bin 디렉토리 — claude·gh·git push wrapper를 자유롭게 분리 설치
make_mock_bin() {
  local name="$1"
  local d="$WORK_DIR/$name"
  mkdir -p "$d"
  echo "$d"
}

# 단순 claude mock — stdin 소비 + DONE 작성 + JSON 응답
install_claude_done_mock() {
  local mock_bin="$1"
  cat > "$mock_bin/claude" <<'CLAUDE_EOF'
#!/usr/bin/env bash
cat > /dev/null
touch DONE
echo '{"result": "mock", "usage": {"input_tokens": 1, "output_tokens": 1}}'
CLAUDE_EOF
  chmod +x "$mock_bin/claude"
}

# gh mock — 모든 호출의 argv를 LOG_FILE에 한 줄씩 기록. PR URL stub을 stdout으로 반환.
# 환경변수 GH_LOG_FILE 경로에 호출 인자 기록 (한 줄/호출 — 공백 join, multiline body는 잘림).
# 환경변수 GH_CALL_DIR 가 지정되면 호출별 argv 전체를 한 줄/인자 형식으로 디렉토리에 덤프
#   (multiline --body 보존 — 본 디렉토리 사용 필수 시 본문 inspection 가능).
# 환경변수 GH_OPEN_PR_NUMBER 가 비어있지 않으면 `pr list`·`pr view` 출력에 그 PR을 포함.
# 환경변수 GH_REPO_VIEW_FAIL=1 — `repo view` 호출 시 exit 1 (default branch 감지 실패 시뮬레이션).
# 환경변수 GH_FAIL_PR_CREATE=1 — `pr create` 호출 시 exit 1 + stderr 에러 (AC8 시뮬레이션).
# 환경변수 GH_FAIL_PR_EDIT=1 — `pr edit` 호출 시 exit 1 + stderr 에러 (AC8 시뮬레이션).
install_gh_record_mock() {
  local mock_bin="$1"
  cat > "$mock_bin/gh" <<'GH_EOF'
#!/usr/bin/env bash
# argv 기록 (단일 라인)
if [[ -n "${GH_LOG_FILE:-}" ]]; then
  # 공백·따옴표 보존을 위해 NUL 구분으로도 적지만, 단순 테스트 용도는 한 줄 join으로 충분
  printf '%s\n' "$*" >> "$GH_LOG_FILE"
fi

# 호출별 argv 덤프 (한 줄/인자 — multiline --body 보존)
if [[ -n "${GH_CALL_DIR:-}" ]]; then
  mkdir -p "$GH_CALL_DIR"
  __gh_idx=$(ls "$GH_CALL_DIR" 2>/dev/null | wc -l | tr -d ' ')
  __gh_idx=$((__gh_idx + 1))
  __gh_sub1="${1:-_}"
  __gh_sub2="${2:-_}"
  __gh_file=$(printf '%s/%03d-%s-%s.argv' "$GH_CALL_DIR" "$__gh_idx" "$__gh_sub1" "$__gh_sub2")
  printf '%s\n' "$@" > "$__gh_file"
fi

case "${1:-}" in
  repo)
    # gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
    # 기본 branch 응답 (또는 GH_REPO_VIEW_FAIL=1 시 exit 1)
    if [[ "${2:-}" == "view" ]]; then
      if [[ "${GH_REPO_VIEW_FAIL:-0}" == "1" ]]; then
        echo "repo view error: forbidden (mock)" >&2
        exit 1
      fi
      echo "${GH_DEFAULT_BRANCH:-main}"
      exit 0
    fi
    ;;
  pr)
    case "${2:-}" in
      list)
        # pr list --head <branch> --state open --json number,url
        if [[ -n "${GH_OPEN_PR_NUMBER:-}" ]]; then
          printf '[{"number":%s,"url":"%s","title":"%s","body":"%s"}]\n' \
            "$GH_OPEN_PR_NUMBER" "${GH_OPEN_PR_URL:-https://github.example/x/y/pull/$GH_OPEN_PR_NUMBER}" \
            "${GH_OPEN_PR_TITLE:-existing title}" "${GH_OPEN_PR_BODY:-existing body}"
        else
          echo '[]'
        fi
        exit 0
        ;;
      view)
        if [[ -n "${GH_OPEN_PR_NUMBER:-}" ]]; then
          # --jq '.body' (또는 --jq=.body) 가 있으면 body 텍스트만 출력 (실제 gh의 jq 적용 모방).
          # 그래야 pr-phase.sh가 fence 마커 부분 교체 경로를 실제로 실행한다.
          want_body=0
          for arg in "$@"; do
            case "$arg" in
              .body|--jq=.body) want_body=1;;
            esac
          done
          if [[ $want_body -eq 1 ]]; then
            printf '%s\n' "${GH_OPEN_PR_BODY:-existing body}"
          else
            printf '{"number":%s,"url":"%s","title":"%s","body":"%s"}\n' \
              "$GH_OPEN_PR_NUMBER" "${GH_OPEN_PR_URL:-https://github.example/x/y/pull/$GH_OPEN_PR_NUMBER}" \
              "${GH_OPEN_PR_TITLE:-existing title}" "${GH_OPEN_PR_BODY:-existing body}"
          fi
          exit 0
        fi
        echo "no pr" >&2
        exit 1
        ;;
      create)
        if [[ "${GH_FAIL_PR_CREATE:-0}" == "1" ]]; then
          echo "gh pr create failed (mock: boom-create)" >&2
          exit 1
        fi
        # PR URL을 stdout으로 출력 (실제 gh의 동작 모방)
        echo "${GH_PR_URL:-https://github.example/x/y/pull/1}"
        exit 0
        ;;
      edit)
        if [[ "${GH_FAIL_PR_EDIT:-0}" == "1" ]]; then
          echo "gh pr edit failed (mock: boom-edit)" >&2
          exit 1
        fi
        exit 0
        ;;
    esac
    ;;
esac
exit 0
GH_EOF
  chmod +x "$mock_bin/gh"
}

# argv 덤프 디렉토리에서 특정 subcommand 호출의 --body 인자 추출
# 사용: extract_body_from_call "<CALL_DIR>" "pr-create"  → 첫 매치 호출의 --body 값을 stdout
# gh mock은 각 argv를 한 줄씩 기록(multiline body는 여러 줄 차지)하므로 --body 라인 다음부터
# 다음 "--<flag>" 라인 또는 EOF 직전까지를 body로 본다.
extract_body_from_call() {
  local call_dir="$1"
  local pattern="$2"  # 예: "pr-create" 또는 "pr-edit"
  local f
  f=$(ls "$call_dir" 2>/dev/null | grep -F "$pattern" | head -1)
  [[ -n "$f" ]] || return 1
  awk '
    BEGIN { take = 0 }
    take == 1 {
      if (/^--[a-zA-Z]/) { exit }
      print
      next
    }
    /^--body$/ { take = 1; next }
  ' "$call_dir/$f"
}

# argv 덤프 디렉토리에서 특정 subcommand 호출의 --title 인자 추출
extract_title_from_call() {
  local call_dir="$1"
  local pattern="$2"
  local f
  f=$(ls "$call_dir" 2>/dev/null | grep -F "$pattern" | head -1)
  [[ -n "$f" ]] || return 1
  awk '
    /^--title$/ { take = 1; next }
    take == 1 { print; exit }
  ' "$call_dir/$f"
}

# argv 덤프 디렉토리에서 특정 subcommand 호출 횟수
count_calls() {
  local call_dir="$1"
  local pattern="$2"
  ls "$call_dir" 2>/dev/null | grep -cF "$pattern" || true
}

echo "=== TEST 1: AC1 — request_review 미지정 시 PR phase skip (gh 호출 0회) ==="
T1_NAME="optout-no-key"
T1_PROJECT="$(make_project_with_remote "$T1_NAME")"
T1_MOCK="$(make_mock_bin "${T1_NAME}-mock")"
install_claude_done_mock "$T1_MOCK"
install_gh_record_mock "$T1_MOCK"
T1_GH_LOG="$WORK_DIR/${T1_NAME}-gh.log"
: > "$T1_GH_LOG"

mkdir -p "$T1_PROJECT/milestones/regular/loops/optout-task"
cat > "$T1_PROJECT/milestones/regular/loops/optout-task/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
---

# Opt-out Task

## 무엇을 만들 것인가
opt-out 검증용.
EOF

(
  cd "$T1_PROJECT"
  GH_LOG_FILE="$T1_GH_LOG" PATH="$T1_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "optout-task" > "$WORK_DIR/${T1_NAME}.out" 2>&1
)

# gh 호출이 0회여야 함
[[ -f "$T1_GH_LOG" ]] || { echo "FAIL: gh log 파일 없음"; exit 1; }
gh_calls_t1=$(wc -l < "$T1_GH_LOG" | tr -d ' ')
[[ "$gh_calls_t1" -eq 0 ]] \
  || { echo "FAIL: opt-out인데 gh가 ${gh_calls_t1}회 호출됨. log:"; cat "$T1_GH_LOG"; exit 1; }

# DONE은 정상 생성됐어야 (기존 동작 회귀)
[[ -f "$T1_PROJECT/milestones/regular/loops/optout-task/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo "=== TEST 2: AC2 + AC7 — request_review: true 시 gh pr create 호출 + 메타 플래그 미지정 ==="
T2_NAME="optin-meta-clean"
T2_PROJECT="$(make_project_with_remote "$T2_NAME")"
T2_MOCK="$(make_mock_bin "${T2_NAME}-mock")"
install_claude_done_mock "$T2_MOCK"
install_gh_record_mock "$T2_MOCK"
T2_GH_LOG="$WORK_DIR/${T2_NAME}-gh.log"
: > "$T2_GH_LOG"

mkdir -p "$T2_PROJECT/milestones/regular/loops/optin-task"
cat > "$T2_PROJECT/milestones/regular/loops/optin-task/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Opt-in Task

## 무엇을 만들 것인가
opt-in 검증용 task.
EOF

(
  cd "$T2_PROJECT"
  GH_LOG_FILE="$T2_GH_LOG" PATH="$T2_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "optin-task" > "$WORK_DIR/${T2_NAME}.out" 2>&1
)

# gh가 호출됐어야 (≥1회)
[[ -f "$T2_GH_LOG" ]] || { echo "FAIL: gh log 없음"; exit 1; }
gh_calls_t2=$(wc -l < "$T2_GH_LOG" | tr -d ' ')
[[ "$gh_calls_t2" -ge 1 ]] \
  || { echo "FAIL: opt-in인데 gh 미호출. log empty"; exit 1; }

# gh pr create 가 최소 1번 호출됐어야
grep -qE '^pr create ' "$T2_GH_LOG" \
  || { echo "FAIL: gh pr create 호출 기록 없음. log:"; cat "$T2_GH_LOG"; exit 1; }

# 메타 플래그 미지정 — AC7
if grep -qE '(--reviewer|--label|--assignee)' "$T2_GH_LOG"; then
  echo "FAIL: gh 호출에 메타 플래그가 포함됨 (AC7 위반). log:"; cat "$T2_GH_LOG"; exit 1
fi

# DONE 유지
[[ -f "$T2_PROJECT/milestones/regular/loops/optin-task/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo "=== TEST 3: AC10 — default 브랜치 감지 실패 시 push·pr create 호출 전 abort ==="
# gh repo view 가 exit 1 + git symbolic-ref refs/remotes/origin/HEAD 도 미설정 →
# detect_default_branch 가 빈 문자열 반환 → pr-phase.sh non-zero exit, push·pr create 호출 0회.
T3_NAME="default-branch-fail"
T3_PROJECT="$(make_project_with_remote "$T3_NAME")"
T3_MOCK="$(make_mock_bin "${T3_NAME}-mock")"
install_claude_done_mock "$T3_MOCK"
install_gh_record_mock "$T3_MOCK"
T3_GH_LOG="$WORK_DIR/${T3_NAME}-gh.log"
: > "$T3_GH_LOG"

mkdir -p "$T3_PROJECT/milestones/regular/loops/dbfail-task"
cat > "$T3_PROJECT/milestones/regular/loops/dbfail-task/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Default Branch Fail Task

## 무엇을 만들 것인가
default branch 감지 실패 abort 검증.
EOF

set +e
(
  cd "$T3_PROJECT"
  GH_LOG_FILE="$T3_GH_LOG" GH_REPO_VIEW_FAIL=1 PATH="$T3_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "dbfail-task" > "$WORK_DIR/${T3_NAME}.out" 2>&1
)
t3_exit=$?
set -e

# AC10: loop start exit ≠ 0 (PR phase가 abort했기 때문)
[[ $t3_exit -ne 0 ]] \
  || { echo "FAIL: default branch 감지 실패에도 exit 0. out:"; cat "$WORK_DIR/${T3_NAME}.out"; exit 1; }

# stderr/stdout 합본에 default branch 감지 실패 메시지
grep -q "default 브랜치 감지 실패" "$WORK_DIR/${T3_NAME}.out" \
  || { echo "FAIL: default 브랜치 감지 실패 메시지 없음. out:"; cat "$WORK_DIR/${T3_NAME}.out"; exit 1; }

# gh pr create / pr edit 호출 0회 (push도 0회지만 gh log로는 검사 불가 — 별도 git wrapper 필요).
# AC10 핵심은 PR 생성·갱신 시도 안 함.
if grep -qE '^pr (create|edit) ' "$T3_GH_LOG"; then
  echo "FAIL: default branch 감지 실패 후에도 pr create/edit 호출됨. log:"; cat "$T3_GH_LOG"; exit 1
fi

# DONE은 정상 생성됐어야 (PR 단계만 실패, 워커 본체는 성공)
[[ -f "$T3_PROJECT/milestones/regular/loops/dbfail-task/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미생성"; exit 1; }
echo "OK"

echo "=== TEST 4: AC6 — 숫자 task-id 시 PR body 마지막에 'Closes #<id>' 추가 ==="
T4_NAME="closes-numeric"
T4_PROJECT="$(make_project_with_remote "$T4_NAME")"
T4_MOCK="$(make_mock_bin "${T4_NAME}-mock")"
install_claude_done_mock "$T4_MOCK"
install_gh_record_mock "$T4_MOCK"
T4_GH_LOG="$WORK_DIR/${T4_NAME}-gh.log"
T4_CALL_DIR="$WORK_DIR/${T4_NAME}-calls"
: > "$T4_GH_LOG"

mkdir -p "$T4_PROJECT/milestones/regular/loops/42"
cat > "$T4_PROJECT/milestones/regular/loops/42/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Numeric Task ID

## 무엇을 만들 것인가
숫자 task-id의 Closes 자동 링크.
EOF

(
  cd "$T4_PROJECT"
  GH_LOG_FILE="$T4_GH_LOG" GH_CALL_DIR="$T4_CALL_DIR" PATH="$T4_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "42" > "$WORK_DIR/${T4_NAME}.out" 2>&1
)

# pr create 호출의 --body 인자에 'Closes #42' 포함
t4_body="$(extract_body_from_call "$T4_CALL_DIR" "pr-create")"
[[ -n "$t4_body" ]] \
  || { echo "FAIL: pr create의 --body 추출 불가. call dir:"; ls "$T4_CALL_DIR"; exit 1; }
echo "$t4_body" | grep -qF "Closes #42" \
  || { echo "FAIL: 숫자 task-id인데 body에 'Closes #42' 없음. body:"; echo "$t4_body"; exit 1; }
echo "OK"

echo "=== TEST 5: AC6 — 비숫자 task-id 시 'Closes #' 자동 링크 생략 ==="
T5_NAME="closes-nonnumeric"
T5_PROJECT="$(make_project_with_remote "$T5_NAME")"
T5_MOCK="$(make_mock_bin "${T5_NAME}-mock")"
install_claude_done_mock "$T5_MOCK"
install_gh_record_mock "$T5_MOCK"
T5_GH_LOG="$WORK_DIR/${T5_NAME}-gh.log"
T5_CALL_DIR="$WORK_DIR/${T5_NAME}-calls"
: > "$T5_GH_LOG"

mkdir -p "$T5_PROJECT/milestones/regular/loops/foo-task"
cat > "$T5_PROJECT/milestones/regular/loops/foo-task/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Non-numeric Task ID

## 무엇을 만들 것인가
비숫자 task-id 검증.
EOF

(
  cd "$T5_PROJECT"
  GH_LOG_FILE="$T5_GH_LOG" GH_CALL_DIR="$T5_CALL_DIR" PATH="$T5_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "foo-task" > "$WORK_DIR/${T5_NAME}.out" 2>&1
)

t5_body="$(extract_body_from_call "$T5_CALL_DIR" "pr-create")"
[[ -n "$t5_body" ]] \
  || { echo "FAIL: pr create의 --body 추출 불가"; ls "$T5_CALL_DIR"; exit 1; }
if echo "$t5_body" | grep -qE 'Closes #[0-9]+'; then
  echo "FAIL: 비숫자 task-id인데 body에 'Closes #<num>' 있음 (AC6 위반). body:"
  echo "$t5_body"; exit 1
fi
echo "OK"

echo "=== TEST 6: AC3+AC4+AC5 — 기존 open PR 재사용 (pr edit) + 제목·본문 동기화 ==="
T6_NAME="reuse-existing-pr"
T6_PROJECT="$(make_project_with_remote "$T6_NAME")"
T6_MOCK="$(make_mock_bin "${T6_NAME}-mock")"
install_claude_done_mock "$T6_MOCK"
install_gh_record_mock "$T6_MOCK"
T6_GH_LOG="$WORK_DIR/${T6_NAME}-gh.log"
T6_CALL_DIR="$WORK_DIR/${T6_NAME}-calls"
: > "$T6_GH_LOG"

mkdir -p "$T6_PROJECT/milestones/regular/loops/reuse-task"
cat > "$T6_PROJECT/milestones/regular/loops/reuse-task/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Reuse Existing PR Title

## 무엇을 만들 것인가
기존 open PR을 in-place로 갱신하는 경로.
EOF

(
  cd "$T6_PROJECT"
  GH_LOG_FILE="$T6_GH_LOG" GH_CALL_DIR="$T6_CALL_DIR" \
    GH_OPEN_PR_NUMBER=99 \
    PATH="$T6_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "reuse-task" > "$WORK_DIR/${T6_NAME}.out" 2>&1
)

# AC3: pr create 호출 0회
if grep -qE '^pr create ' "$T6_GH_LOG"; then
  echo "FAIL: 기존 PR 있는데 pr create 호출됨 (AC3 위반). log:"; cat "$T6_GH_LOG"; exit 1
fi

# pr edit 99 호출 1회 이상
grep -qE '^pr edit 99( |$)' "$T6_GH_LOG" \
  || { echo "FAIL: pr edit 99 호출 기록 없음. log:"; cat "$T6_GH_LOG"; exit 1; }

# AC4: 제목 == SPEC의 H1
t6_title="$(extract_title_from_call "$T6_CALL_DIR" "pr-edit")"
[[ "$t6_title" == "Reuse Existing PR Title" ]] \
  || { echo "FAIL: pr edit 제목이 SPEC H1과 불일치. got='$t6_title'"; exit 1; }

# AC5: body가 SPEC '무엇을 만들 것인가' 본문 포함
t6_body="$(extract_body_from_call "$T6_CALL_DIR" "pr-edit")"
echo "$t6_body" | grep -qF "기존 open PR을 in-place로 갱신하는 경로" \
  || { echo "FAIL: pr edit body가 SPEC 본문을 포함하지 않음. body:"; echo "$t6_body"; exit 1; }
echo "$t6_body" | grep -qF "## Commits" \
  || { echo "FAIL: pr edit body가 commit log 섹션을 포함하지 않음. body:"; echo "$t6_body"; exit 1; }

# AC7: 메타 플래그 미지정 (재사용 경로에도 동일)
if grep -qE '(--reviewer|--label|--assignee)' "$T6_GH_LOG"; then
  echo "FAIL: 재사용 경로에 메타 플래그 포함됨. log:"; cat "$T6_GH_LOG"; exit 1
fi
echo "OK"

echo "=== TEST 7: AC8 — gh pr create 실패 시 loop non-zero exit + stderr passthrough ==="
T7_NAME="create-fail"
T7_PROJECT="$(make_project_with_remote "$T7_NAME")"
T7_MOCK="$(make_mock_bin "${T7_NAME}-mock")"
install_claude_done_mock "$T7_MOCK"
install_gh_record_mock "$T7_MOCK"
T7_GH_LOG="$WORK_DIR/${T7_NAME}-gh.log"
: > "$T7_GH_LOG"

mkdir -p "$T7_PROJECT/milestones/regular/loops/createfail-task"
cat > "$T7_PROJECT/milestones/regular/loops/createfail-task/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Create Fail Task

## 무엇을 만들 것인가
pr create 실패 시 abort 검증.
EOF

set +e
(
  cd "$T7_PROJECT"
  GH_LOG_FILE="$T7_GH_LOG" GH_FAIL_PR_CREATE=1 PATH="$T7_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "createfail-task" > "$WORK_DIR/${T7_NAME}.out" 2>&1
)
t7_exit=$?
set -e

# AC8: loop start exit ≠ 0
[[ $t7_exit -ne 0 ]] \
  || { echo "FAIL: pr create 실패에도 loop exit 0. out:"; cat "$WORK_DIR/${T7_NAME}.out"; exit 1; }

# stderr passthrough: mock의 'boom-create' 문자열이 출력에 포함돼야
grep -q "boom-create" "$WORK_DIR/${T7_NAME}.out" \
  || { echo "FAIL: gh stderr passthrough 미동작 ('boom-create' 없음). out:"; cat "$WORK_DIR/${T7_NAME}.out"; exit 1; }

# 워크트리·DONE 보존 (AC9 정신 — 워크트리는 유지)
[[ -d "$T7_PROJECT/milestones/regular/loops/createfail-task/.worktree" ]] \
  || { echo "FAIL: 워크트리 미보존"; exit 1; }
[[ -f "$T7_PROJECT/milestones/regular/loops/createfail-task/.worktree/DONE" ]] \
  || { echo "FAIL: DONE 미보존"; exit 1; }
echo "OK"

echo "=== TEST 8: AC9 — 성공 시 PR URL·state stdout 출력 + worktree·local 브랜치 보존 ==="
T8_NAME="success-stdout"
T8_PROJECT="$(make_project_with_remote "$T8_NAME")"
T8_MOCK="$(make_mock_bin "${T8_NAME}-mock")"
install_claude_done_mock "$T8_MOCK"
install_gh_record_mock "$T8_MOCK"
T8_GH_LOG="$WORK_DIR/${T8_NAME}-gh.log"
: > "$T8_GH_LOG"

mkdir -p "$T8_PROJECT/milestones/regular/loops/success-task"
cat > "$T8_PROJECT/milestones/regular/loops/success-task/SPEC.md" <<'EOF'
---
scope:
  include:
    - "**/*"
  exclude: []
verify: 'true'
request_review: true
---

# Success Task

## 무엇을 만들 것인가
AC9 성공 출력·보존 검증.
EOF

T8_PR_URL="https://github.example/x/y/pull/777"
(
  cd "$T8_PROJECT"
  GH_LOG_FILE="$T8_GH_LOG" GH_PR_URL="$T8_PR_URL" PATH="$T8_MOCK:$PATH" \
    MAX_ITERATIONS=1 WALL_CLOCK_MINUTES=5 \
    bash "$LOOP_SH_SRC" start "success-task" > "$WORK_DIR/${T8_NAME}.out" 2>&1
)

# AC9: PR URL stdout 출력
grep -qF "$T8_PR_URL" "$WORK_DIR/${T8_NAME}.out" \
  || { echo "FAIL: PR URL ($T8_PR_URL) stdout 미출력. out:"; cat "$WORK_DIR/${T8_NAME}.out"; exit 1; }

# AC9: PR state(open) stdout 출력
grep -qE "PR state:[[:space:]]*open" "$WORK_DIR/${T8_NAME}.out" \
  || { echo "FAIL: PR state stdout 미출력. out:"; cat "$WORK_DIR/${T8_NAME}.out"; exit 1; }

# AC9: 워크트리 보존
[[ -d "$T8_PROJECT/milestones/regular/loops/success-task/.worktree" ]] \
  || { echo "FAIL: 워크트리 미보존"; exit 1; }

# AC9: local 브랜치 보존 (워크트리에 체크아웃된 브랜치 = HEAD 참조 정상)
(
  cd "$T8_PROJECT/milestones/regular/loops/success-task/.worktree"
  git rev-parse --abbrev-ref HEAD > /dev/null 2>&1
) || { echo "FAIL: 워크트리의 HEAD 브랜치 미보존"; exit 1; }
echo "OK"

echo "=== TEST 9: M7 — request_review 키 이름이 SKILL.md·spec-template.md·driver 사이 동기화 ==="
# 키 이름이 세 파일 중 어느 한쪽에서 누락·오타 나면 opt-in 자체가 동작 안 함.
# 세 곳 모두에 정확히 `request_review` 토큰이 등장해야 함.
T9_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/loop/SKILL.md"
T9_SPEC_TEMPLATE="$REPO_ROOT/plugins/autopilot/skills/spec/references/spec-template.md"
T9_DRIVER_LOOP="$REPO_ROOT/plugins/autopilot/skills/loop/references/loop.sh"
T9_DRIVER_PR="$REPO_ROOT/plugins/autopilot/skills/loop/references/pr-phase.sh"

for f in "$T9_SKILL_MD" "$T9_SPEC_TEMPLATE" "$T9_DRIVER_LOOP"; do
  [[ -f "$f" ]] || { echo "FAIL: 파일 없음: $f"; exit 1; }
  grep -qF 'request_review' "$f" \
    || { echo "FAIL: $f 에 'request_review' 키 누락"; exit 1; }
done

# pr-phase.sh는 caller가 opt-in 체크하므로 키 등장 불필요 — 존재만 확인.
[[ -f "$T9_DRIVER_PR" ]] || { echo "FAIL: pr-phase.sh 없음"; exit 1; }
echo "OK"

echo ""
echo "=== 모든 PR phase 테스트 통과 ==="
