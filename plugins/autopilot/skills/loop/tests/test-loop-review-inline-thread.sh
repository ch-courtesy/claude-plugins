#!/usr/bin/env bash
# test-loop-review-inline-thread.sh — SPEC 153 inline review thread 1:1 응답 테스트
#
# 검증 대상 (SPEC 153 AC1~AC6):
#   (a) inline thread comment 타당 → 코드 수정 push 1회 (reply POST 없음)
#   (b) inline thread comment 부당 → 해당 inline thread에 reply 1개 게시 (in_reply_to)
#   (c) 같은 inline thread 재폴링/추가-comment 시 중복 reply 미게시 (REPLIED_THREADS 가드)
#   (d) 서로 다른 inline thread 2개 부당 판정 → 각 thread에 reply 1개씩 (총 2개)
#   (e) PR-level comment 부당 판정 → 기존 `gh pr comment` 경로 유지, 인라인 thread reply 미사용
#
# 외부 부수 효과(gh API, claude CLI, git push)는 stub binary로 격리.
# 모든 mock은 호출 인자를 $AUTOPILOT_TEST_GH_LOG에 기록해 assert 용도로 사용.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_REFS="$REPO_ROOT/plugins/autopilot/skills/loop/references"

WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf $WORK_DIR" EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# ----- 공통 셋업 헬퍼 -----
#
# 본 헬퍼는 격리된 main repo + bare remote + worktree(feat 브랜치) + 1개 추적 파일을
# 만든다. 호출 측은 echo로 받은 worktree·bare 경로를 사용해 mock·assertion을 구성.
_setup_worktree() {
  local case_name="$1"
  local project="$WORK_DIR/$case_name"
  local bare="$WORK_DIR/${case_name}.git"
  git init -q --bare -b main "$bare"
  mkdir -p "$project"
  (
    cd "$project"
    git init -q -b main
    git config user.email "t@e.com"; git config user.name "T"
    git remote add origin "$bare"
    echo "initial" > seed.txt
    git add seed.txt
    git commit -q -m initial
    git push -q origin main
    # rebase-phase의 default 브랜치 감지(git symbolic-ref) fallback 경로용
    git remote set-head origin main
    mkdir -p milestones/regular/loops/153
    git worktree add -q -b feat/153-test milestones/regular/loops/153/.worktree HEAD
    cd milestones/regular/loops/153/.worktree
    # 신규 fix iter가 수정할 추적 파일 (git add -u가 변경 감지하려면 tracked 필요)
    echo "// original" > fix-target.txt
    git add fix-target.txt
    git commit -q -m "feat: seed fix-target"
    git push -q -u origin feat/153-test
  ) >/dev/null 2>&1 || fail "$case_name: setup 실패"
  echo "$project|$bare"
}

# ----- 공통 mock 생성 헬퍼 -----
#
# 모든 case가 공유하는 gh 스텁. 호출 인자에 따라:
#   - gh pr view --json X [--jq E]      → AUTOPILOT_TEST_PR_FIXTURE를 jq로 projection/필터
#   - gh repo view --json X [--jq E]    → defaultBranchRef.name=main, nameWithOwner=owner/repo
#   - gh api -X POST repos/.../pulls/N/comments -f body=X -F in_reply_to=Y  → LOG 기록
#   - gh pr comment N --body X          → LOG 기록
#   - gh pr merge ...                   → LOG 기록 (호출 없으면 정상)
#   - gh project ...                    → 무음 성공
#
# 모든 호출은 LOG에 한 줄로 누적 기록 → 테스트가 grep으로 횟수·payload assert.
_make_mock_bin() {
  local mock_bin="$1"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
LOG="${AUTOPILOT_TEST_GH_LOG:-/dev/null}"
FIXTURE="${AUTOPILOT_TEST_PR_FIXTURE:-}"
# 매 호출을 raw로 기록 (각 인자 사이를 |로 구분)
{
  printf 'CALL'
  for arg in "$@"; do printf '|%s' "$arg"; done
  printf '\n'
} >> "$LOG"

case "${1:-}" in
  pr)
    case "${2:-}" in
      view)
        # --json, --jq 파싱
        shift 2
        json_fields="" jq_expr=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --json) json_fields="$2"; shift 2 ;;
            --jq)   jq_expr="$2"; shift 2 ;;
            *)      shift ;;
          esac
        done
        if [[ -z "$FIXTURE" || ! -f "$FIXTURE" ]]; then
          echo "{}"
          exit 0
        fi
        if [[ -n "$jq_expr" ]]; then
          jq -r "$jq_expr" < "$FIXTURE"
        elif [[ -n "$json_fields" ]]; then
          # 요청 필드만 projection
          local_filter="{ $(echo "$json_fields" | tr ',' '\n' | awk 'NF{printf "%s: (.%s // null),", $0, $0}' | sed 's/,$//') }"
          jq -c "$local_filter" < "$FIXTURE"
        else
          cat "$FIXTURE"
        fi
        exit 0 ;;
      comment)
        # 기록만 — 호출 자체는 위에서 LOG에 들어감
        exit 0 ;;
      merge)
        exit 0 ;;
    esac
    ;;
  api)
    # gh api ... 호출은 LOG에 기록만 (자세한 payload는 호출 인자 그대로 LOG에 남음)
    exit 0
    ;;
  repo)
    case "${2:-}" in
      view)
        shift 2
        jq_expr=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --jq) jq_expr="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        case "$jq_expr" in
          .nameWithOwner)         echo "owner/repo" ;;
          .defaultBranchRef.name) echo "main" ;;
          *)                       echo '{"nameWithOwner":"owner/repo","defaultBranchRef":{"name":"main"}}' ;;
        esac
        exit 0 ;;
    esac
    ;;
  project)
    exit 0 ;;
esac
exit 0
GH
  chmod +x "$mock_bin/gh"
}

# claude mock — AUTOPILOT_TEST_CLAUDE_OUT 환경변수의 내용을 stdout으로 emit하고,
# AUTOPILOT_TEST_CLAUDE_TOUCH 경로가 지정되면 그 파일에 한 줄 append (코드 변경 시뮬레이션).
_make_claude_mock() {
  local mock_bin="$1"
  cat > "$mock_bin/claude" <<'CL'
#!/usr/bin/env bash
if [[ -n "${AUTOPILOT_TEST_CLAUDE_TOUCH:-}" ]]; then
  echo "// fix applied" >> "$AUTOPILOT_TEST_CLAUDE_TOUCH"
fi
printf '%s\n' "${AUTOPILOT_TEST_CLAUDE_OUT:-DONE}"
exit 0
CL
  chmod +x "$mock_bin/claude"
}

# 단일 inline thread / 단일 comment fixture
_fixture_single_inline() {
  local out="$1"
  cat > "$out" <<'JSON'
{
  "state": "OPEN",
  "reviewDecision": null,
  "number": 1,
  "author": {"login": "owner"},
  "comments": [],
  "reviews": [],
  "reviewThreads": [
    {"id": "T1", "comments": [{"id": 101, "body": "Please rename foo to bar"}]}
  ]
}
JSON
}

# 같은 thread 안 두 comment fixture (within-iter 재폴링 시뮬: 둘 다 새 comment)
_fixture_two_comments_same_thread() {
  local out="$1"
  cat > "$out" <<'JSON'
{
  "state": "OPEN",
  "reviewDecision": null,
  "number": 1,
  "author": {"login": "owner"},
  "comments": [],
  "reviews": [],
  "reviewThreads": [
    {"id": "T1", "comments": [
      {"id": 101, "body": "First wrong comment"},
      {"id": 102, "body": "Second wrong comment (same thread)"}
    ]}
  ]
}
JSON
}

# 두 별개 thread fixture
_fixture_two_different_threads() {
  local out="$1"
  cat > "$out" <<'JSON'
{
  "state": "OPEN",
  "reviewDecision": null,
  "number": 1,
  "author": {"login": "owner"},
  "comments": [],
  "reviews": [],
  "reviewThreads": [
    {"id": "T1", "comments": [{"id": 101, "body": "Wrong A"}]},
    {"id": "T2", "comments": [{"id": 201, "body": "Wrong B"}]}
  ]
}
JSON
}

# PR-level 단일 comment fixture (inline thread 없음)
_fixture_pr_level_comment() {
  local out="$1"
  cat > "$out" <<'JSON'
{
  "state": "OPEN",
  "reviewDecision": null,
  "number": 1,
  "author": {"login": "owner"},
  "comments": [{"id": 901, "body": "PR-level nitpick", "author": {"login": "reviewer"}}],
  "reviews": [],
  "reviewThreads": []
}
JSON
}

# ----- (a) inline 타당 → 코드 수정 push 1회 -----
test_a_inline_valid_codefix_push() {
  local pair; pair=$(_setup_worktree "case_a") || fail "(a) setup"
  local project="${pair%|*}" bare="${pair#*|}"
  local wt="$project/milestones/regular/loops/153/.worktree"

  local mock_bin="$WORK_DIR/case_a_mock"
  _make_mock_bin "$mock_bin"
  _make_claude_mock "$mock_bin"

  local fixture="$WORK_DIR/case_a_pr.json"; _fixture_single_inline "$fixture"
  local log="$WORK_DIR/case_a_gh.log"; : > "$log"

  local before_sha; before_sha=$( cd "$bare" && git rev-parse refs/heads/feat/153-test )

  export AUTOPILOT_TEST_PR_FIXTURE="$fixture"
  export AUTOPILOT_TEST_GH_LOG="$log"
  export AUTOPILOT_TEST_CLAUDE_OUT=$'INLINE T1 101 FIX\nDONE'
  export AUTOPILOT_TEST_CLAUDE_TOUCH="$wt/fix-target.txt"
  export LOOP_REVIEW_POLL_SECS=1
  export LOOP_REVIEW_MAX_ITER=1

  PATH="$mock_bin:$PATH" bash "$SKILL_REFS/review-fix-phase.sh" "$wt" "feat/153-test" "regular/153" "$project" "1" \
       >"$WORK_DIR/case_a.out" 2>&1 || true

  local after_sha; after_sha=$( cd "$bare" && git rev-parse refs/heads/feat/153-test 2>/dev/null || echo "" )
  [[ "$before_sha" != "$after_sha" ]] \
    || { cat "$WORK_DIR/case_a.out"; fail "(a) inline 타당: bare에 push 없음 (SHA 미변경)"; }

  # 인라인 thread reply API 호출이 없어야 함
  if grep -F "CALL|api|" "$log" | grep -qE 'pulls/[0-9]+/comments'; then
    cat "$log"; fail "(a) inline 타당: FIX인데 인라인 reply POST 호출됨"
  fi
  # PR-level dispute (gh pr comment)도 없어야 함
  if grep -F "CALL|pr|comment|" "$log" >/dev/null 2>&1; then
    cat "$log"; fail "(a) inline 타당: FIX인데 gh pr comment 호출됨"
  fi
  pass "(a) inline 타당 → 코드 수정 push 1회 (reply 없음)"
}

# ----- (b) inline 부당 → 해당 inline thread에 reply 1개 게시 -----
test_b_inline_invalid_thread_reply() {
  local pair; pair=$(_setup_worktree "case_b") || fail "(b) setup"
  local project="${pair%|*}" bare="${pair#*|}"
  local wt="$project/milestones/regular/loops/153/.worktree"

  local mock_bin="$WORK_DIR/case_b_mock"
  _make_mock_bin "$mock_bin"
  _make_claude_mock "$mock_bin"

  local fixture="$WORK_DIR/case_b_pr.json"; _fixture_single_inline "$fixture"
  local log="$WORK_DIR/case_b_gh.log"; : > "$log"

  local before_sha; before_sha=$( cd "$bare" && git rev-parse refs/heads/feat/153-test )

  export AUTOPILOT_TEST_PR_FIXTURE="$fixture"
  export AUTOPILOT_TEST_GH_LOG="$log"
  export AUTOPILOT_TEST_CLAUDE_OUT=$'INLINE T1 101 DISPUTE reviewer is mistaken about naming\nDONE'
  unset AUTOPILOT_TEST_CLAUDE_TOUCH
  export LOOP_REVIEW_POLL_SECS=1
  export LOOP_REVIEW_MAX_ITER=1

  PATH="$mock_bin:$PATH" bash "$SKILL_REFS/review-fix-phase.sh" "$wt" "feat/153-test" "regular/153" "$project" "1" \
       >"$WORK_DIR/case_b.out" 2>&1 || true

  local after_sha; after_sha=$( cd "$bare" && git rev-parse refs/heads/feat/153-test 2>/dev/null || echo "" )
  [[ "$before_sha" == "$after_sha" ]] \
    || { cat "$WORK_DIR/case_b.out"; fail "(b) inline 부당: 코드 변경 없는데 push 발생"; }

  # 정확히 1개의 인라인 reply POST + in_reply_to=101 포함
  local post_count
  post_count=$(grep -F "CALL|api|" "$log" | grep -cE 'pulls/[0-9]+/comments' || true)
  [[ "$post_count" -eq 1 ]] \
    || { cat "$log"; fail "(b) inline 부당: pulls/N/comments POST $post_count 회 (기대 1)"; }
  grep -F "CALL|api|" "$log" | grep -qE 'in_reply_to[^|]*101' \
    || { cat "$log"; fail "(b) inline 부당: in_reply_to=101 인자 부재"; }

  # PR-level gh pr comment는 사용되지 않아야 함
  if grep -F "CALL|pr|comment|" "$log" >/dev/null 2>&1; then
    cat "$log"; fail "(b) inline 부당: PR-level gh pr comment fallback 사용됨"
  fi
  pass "(b) inline 부당 → inline thread reply 1개 (in_reply_to=101)"
}

# ----- (c) 같은 inline thread 추가 comment 시 중복 reply 미게시 -----
#
# 같은 thread T1에 두 개의 새 comment(101·102)가 폴링됐을 때:
#   - 첫 comment(101)에 대한 DISPUTE → reply POST (T1 → REPLIED_THREADS 기록)
#   - 두 번째 comment(102)에 대한 DISPUTE → REPLIED_THREADS에 T1 있으므로 reply 미게시
# 결과: 총 1개 POST.
test_c_same_thread_no_duplicate_reply() {
  local pair; pair=$(_setup_worktree "case_c") || fail "(c) setup"
  local project="${pair%|*}" bare="${pair#*|}"
  local wt="$project/milestones/regular/loops/153/.worktree"

  local mock_bin="$WORK_DIR/case_c_mock"
  _make_mock_bin "$mock_bin"
  _make_claude_mock "$mock_bin"

  local fixture="$WORK_DIR/case_c_pr.json"; _fixture_two_comments_same_thread "$fixture"
  local log="$WORK_DIR/case_c_gh.log"; : > "$log"

  export AUTOPILOT_TEST_PR_FIXTURE="$fixture"
  export AUTOPILOT_TEST_GH_LOG="$log"
  export AUTOPILOT_TEST_CLAUDE_OUT=$'INLINE T1 101 DISPUTE first\nINLINE T1 102 DISPUTE second\nDONE'
  unset AUTOPILOT_TEST_CLAUDE_TOUCH
  export LOOP_REVIEW_POLL_SECS=1
  export LOOP_REVIEW_MAX_ITER=1

  PATH="$mock_bin:$PATH" bash "$SKILL_REFS/review-fix-phase.sh" "$wt" "feat/153-test" "regular/153" "$project" "1" \
       >"$WORK_DIR/case_c.out" 2>&1 || true

  local post_count
  post_count=$(grep -F "CALL|api|" "$log" | grep -cE 'pulls/[0-9]+/comments' || true)
  [[ "$post_count" -eq 1 ]] \
    || { cat "$log"; fail "(c) 같은 thread 중복: pulls/N/comments POST $post_count 회 (기대 1, REPLIED_THREADS 가드)"; }
  pass "(c) 같은 inline thread 재폴링/추가 comment 시 중복 reply 미게시"
}

# ----- (d) 서로 다른 inline thread 2개 부당 → 각 thread에 reply 1개씩 (총 2개) -----
test_d_two_threads_two_replies() {
  local pair; pair=$(_setup_worktree "case_d") || fail "(d) setup"
  local project="${pair%|*}" bare="${pair#*|}"
  local wt="$project/milestones/regular/loops/153/.worktree"

  local mock_bin="$WORK_DIR/case_d_mock"
  _make_mock_bin "$mock_bin"
  _make_claude_mock "$mock_bin"

  local fixture="$WORK_DIR/case_d_pr.json"; _fixture_two_different_threads "$fixture"
  local log="$WORK_DIR/case_d_gh.log"; : > "$log"

  export AUTOPILOT_TEST_PR_FIXTURE="$fixture"
  export AUTOPILOT_TEST_GH_LOG="$log"
  export AUTOPILOT_TEST_CLAUDE_OUT=$'INLINE T1 101 DISPUTE body for A\nINLINE T2 201 DISPUTE body for B\nDONE'
  unset AUTOPILOT_TEST_CLAUDE_TOUCH
  export LOOP_REVIEW_POLL_SECS=1
  export LOOP_REVIEW_MAX_ITER=1

  PATH="$mock_bin:$PATH" bash "$SKILL_REFS/review-fix-phase.sh" "$wt" "feat/153-test" "regular/153" "$project" "1" \
       >"$WORK_DIR/case_d.out" 2>&1 || true

  local post_count
  post_count=$(grep -F "CALL|api|" "$log" | grep -cE 'pulls/[0-9]+/comments' || true)
  [[ "$post_count" -eq 2 ]] \
    || { cat "$log"; fail "(d) 다른 thread 2개: pulls/N/comments POST $post_count 회 (기대 2)"; }
  # 각 in_reply_to 값이 한 번씩 등장
  grep -F "CALL|api|" "$log" | grep -qE 'in_reply_to[^|]*101' \
    || { cat "$log"; fail "(d) thread T1 reply (in_reply_to=101) 부재"; }
  grep -F "CALL|api|" "$log" | grep -qE 'in_reply_to[^|]*201' \
    || { cat "$log"; fail "(d) thread T2 reply (in_reply_to=201) 부재"; }
  pass "(d) 서로 다른 thread 2개 부당 → 각 thread reply 1개씩 (총 2개)"
}

# ----- (e) PR-level dispute 경로 보존 -----
test_e_pr_level_dispute_preserved() {
  local pair; pair=$(_setup_worktree "case_e") || fail "(e) setup"
  local project="${pair%|*}" bare="${pair#*|}"
  local wt="$project/milestones/regular/loops/153/.worktree"

  local mock_bin="$WORK_DIR/case_e_mock"
  _make_mock_bin "$mock_bin"
  _make_claude_mock "$mock_bin"

  local fixture="$WORK_DIR/case_e_pr.json"; _fixture_pr_level_comment "$fixture"
  local log="$WORK_DIR/case_e_gh.log"; : > "$log"

  export AUTOPILOT_TEST_PR_FIXTURE="$fixture"
  export AUTOPILOT_TEST_GH_LOG="$log"
  # PR-level dispute는 기존 'DISPUTE: ' single-line 프로토콜 사용
  export AUTOPILOT_TEST_CLAUDE_OUT=$'DISPUTE: PR-level nitpick is wrong\nDONE'
  unset AUTOPILOT_TEST_CLAUDE_TOUCH
  export LOOP_REVIEW_POLL_SECS=1
  export LOOP_REVIEW_MAX_ITER=1

  PATH="$mock_bin:$PATH" bash "$SKILL_REFS/review-fix-phase.sh" "$wt" "feat/153-test" "regular/153" "$project" "1" \
       >"$WORK_DIR/case_e.out" 2>&1 || true

  # PR-level 경로: gh pr comment 정확히 1회 호출
  local pr_comment_count
  pr_comment_count=$(grep -cF "CALL|pr|comment|" "$log" || true)
  [[ "$pr_comment_count" -eq 1 ]] \
    || { cat "$log"; fail "(e) PR-level: gh pr comment $pr_comment_count 회 (기대 1)"; }

  # 인라인 thread reply API는 호출되지 않아야 함
  if grep -F "CALL|api|" "$log" | grep -qE 'pulls/[0-9]+/comments'; then
    cat "$log"; fail "(e) PR-level: 인라인 thread reply API 호출됨 (PR-level 경로가 inline으로 새어들어감)"
  fi
  pass "(e) PR-level dispute 경로 보존 (gh pr comment 1회, inline reply 없음)"
}

# ----- 실행 -----
test_a_inline_valid_codefix_push
test_b_inline_invalid_thread_reply
test_c_same_thread_no_duplicate_reply
test_d_two_threads_two_replies
test_e_pr_level_dispute_preserved

echo "----------"
echo "ALL INLINE THREAD TESTS PASSED"
