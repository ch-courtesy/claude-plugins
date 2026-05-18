#!/usr/bin/env bash
# test-loop-review-fix-phase.sh — SPEC 123 rebase·review-fix·cleanup phase 테스트
#
# 검증 대상:
#  - rebase-phase.sh / review-fix-phase.sh / cleanup-phase.sh 존재·실행권
#  - SPEC 검증 명령(grep 키워드 체크)이 통과
#  - rebase-phase.sh: 인자 부족 시 non-zero, 정상 인자에서 rebase 호출
#  - review-fix-phase.sh: 종료 신호(merged/closed/APPROVED/owner cmd) 분기 동작
#  - cleanup-phase.sh: worktree remove + branch -D + push --delete 호출
#  - loop.sh: request_review opt-in 분기 + allowed-tools 상수 + 3개 phase 호출 link
#
# 외부 부수 효과(git push·gh API·claude CLI)는 모두 stub binary로 격리.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_REFS="$REPO_ROOT/plugins/autopilot/skills/loop/references"

WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf $WORK_DIR" EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# ----- 구조 검증: SPEC 명령 (grep 키워드) -----
test_spec_verify_command() {
  local S="$REPO_ROOT/plugins/autopilot/skills/loop"
  test -f "$S/references/rebase-phase.sh"        || fail "rebase-phase.sh 부재"
  test -f "$S/references/review-fix-phase.sh"    || fail "review-fix-phase.sh 부재"
  test -f "$S/references/cleanup-phase.sh"       || fail "cleanup-phase.sh 부재"
  grep -qE 'merged|closed'             "$S/references/review-fix-phase.sh" || fail "review-fix: merged|closed 키워드 부재"
  grep -qE 'APPROVED'                  "$S/references/review-fix-phase.sh" || fail "review-fix: APPROVED 키워드 부재"
  grep -qE '/done|합격|통과'           "$S/references/review-fix-phase.sh" || fail "review-fix: owner cmd 어휘 부재"
  grep -q  'sleep'                     "$S/references/review-fix-phase.sh" || fail "review-fix: sleep 부재 (폴링)"
  grep -q  'rebase'                    "$S/references/rebase-phase.sh"     || fail "rebase-phase: rebase 부재"
  grep -q  'worktree remove'           "$S/references/cleanup-phase.sh"    || fail "cleanup: worktree remove 부재"
  grep -qE 'branch -D|push --delete'   "$S/references/cleanup-phase.sh"    || fail "cleanup: branch -D | push --delete 부재"
  grep -qE 'review-fix-phase|rebase-phase|cleanup-phase' "$S/references/loop.sh" || fail "loop.sh: 새 phase ref 부재"
  grep -q  'gh project item-edit' "$S/references/loop.sh" "$S/references/review-fix-phase.sh" "$S/references/cleanup-phase.sh" \
    || fail "gh project item-edit 부재 (어느 phase에도 없음)"
  grep -q  'gh pr merge'               "$S/references/review-fix-phase.sh" || fail "review-fix: gh pr merge 부재"
  grep -q  'gh pr comment'             "$S/references/review-fix-phase.sh" || fail "review-fix: gh pr comment 부재"
  grep -qE '반박|dispute'              "$S/references/review-fix-phase.sh" || fail "review-fix: 반박 어휘 부재"
  grep -qE 'allowed-tools|--allowed-tools' "$S/references/loop.sh"         || fail "loop.sh: allowed-tools 부재"
  grep -qE 'review-fix|rebase|cleanup' "$S/SKILL.md"                       || fail "SKILL.md: phase 어휘 부재"
  grep -qE '상태 전이|Status'          "$S/SKILL.md"                       || fail "SKILL.md: 상태 어휘 부재"
  grep -qE '자동 머지|auto[- ]?merge'  "$S/SKILL.md"                       || fail "SKILL.md: 자동 머지 어휘 부재"
  # SPEC 153 prompt → 파서 contract 정적 검증 — claude mock이 stdin을 무시하므로
  # 런타임 테스트만으로는 prompt가 INLINE 포맷 출력을 지시하는지 확인 불가.
  # production source에서 prompt-출력 contract의 양쪽이 모두 INLINE 어휘를 갖는지 grep.
  grep -qE 'INLINE[[:space:]]+<thread_id>'  "$S/references/review-fix-phase.sh" \
    || fail "review-fix: claude prompt에 INLINE <thread_id> 포맷 지시 부재 — (iv-A) 파서가 dead code 위험"
  grep -qE '^[[:space:]]*read.*INLINE|grep.*\^INLINE' "$S/references/review-fix-phase.sh" \
    || fail "review-fix: INLINE 라인 파서 부재 (read/grep ^INLINE 없음)"
  # in_reply_to 타입 검증 — REST API는 정수 필드. `-F`(typed) 사용 강제.
  grep -qE '\-F[[:space:]]+"in_reply_to=' "$S/references/review-fix-phase.sh" \
    || fail "review-fix: in_reply_to에 -F (typed integer) 사용 부재 (REST 422 위험)"
  ! grep -qE '\-f[[:space:]]+"in_reply_to=' "$S/references/review-fix-phase.sh" \
    || fail "review-fix: in_reply_to에 -f (string) 사용 — REST API가 422 반환"
  pass "SPEC 검증 명령 통과"
}

# ----- 인자 부족 시 phase 스크립트 non-zero exit -----
test_phase_scripts_arg_validation() {
  local s
  for s in rebase-phase.sh review-fix-phase.sh cleanup-phase.sh; do
    if bash "$SKILL_REFS/$s" 2>/dev/null; then
      fail "$s: 인자 없이 호출됐는데 0 exit (인자 검증 누락)"
    fi
  done
  pass "phase 스크립트 인자 부족 시 non-zero exit"
}

# ----- cleanup-phase.sh: PR merged 후 worktree·branch 정리 -----
test_cleanup_phase_removes_worktree_and_branches() {
  local project="$WORK_DIR/proj"
  local bare="$WORK_DIR/proj.git"
  git init -q --bare -b main "$bare"
  mkdir -p "$project"
  (
    cd "$project"
    git init -q -b main
    git config user.email "t@e.com"; git config user.name "T"
    git remote add origin "$bare"
    git commit --allow-empty -q -m initial
    git push -q origin main
    mkdir -p milestones/regular/loops/123
    # 새 feat 브랜치를 worktree에 직접 생성 (main repo는 main 유지 — 'already used' 회피)
    git worktree add -q -b feat/123-test milestones/regular/loops/123/.worktree HEAD
    cd milestones/regular/loops/123/.worktree
    git commit --allow-empty -q -m "feat: x"
    git push -q -u origin feat/123-test
  ) || fail "cleanup test setup 실패"
  local wt="$project/milestones/regular/loops/123/.worktree"
  [[ -d "$wt" ]] || fail "셋업: worktree 없음"

  # mock bin (gh stub to avoid network)
  local mock_bin="$WORK_DIR/mock_bin"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
# gh stub — 본 테스트의 cleanup phase에서 호출되는 'gh project item-edit'를 무음 성공
exit 0
GH
  chmod +x "$mock_bin/gh"

  PATH="$mock_bin:$PATH" bash "$SKILL_REFS/cleanup-phase.sh" "$wt" "feat/123-test" "regular/123" "$project" \
    || fail "cleanup-phase 실패 exit"

  [[ ! -d "$wt" ]] || fail "cleanup 후 worktree 잔존: $wt"
  ( cd "$project" && git rev-parse --verify feat/123-test 2>/dev/null ) \
    && fail "cleanup 후 로컬 feat 브랜치 잔존"
  ( cd "$bare" && git rev-parse --verify feat/123-test 2>/dev/null ) \
    && fail "cleanup 후 origin feat 브랜치 잔존"
  pass "cleanup-phase: worktree + local feat + origin feat 모두 제거"
}

# ----- review-fix-phase.sh: 종료 신호(merged) 감지 즉시 종료 -----
test_review_fix_phase_terminates_on_merged() {
  local project="$WORK_DIR/rf_proj"
  local bare="$WORK_DIR/rf_proj.git"
  git init -q --bare -b main "$bare"
  mkdir -p "$project"
  (
    cd "$project"
    git init -q -b main
    git config user.email "t@e.com"; git config user.name "T"
    git remote add origin "$bare"
    git commit --allow-empty -q -m initial
    git push -q origin main
    mkdir -p milestones/regular/loops/123
    git worktree add -q -b feat/123-rf milestones/regular/loops/123/.worktree HEAD
    cd milestones/regular/loops/123/.worktree
    git commit --allow-empty -q -m "feat: y"
  ) || fail "review-fix test setup 실패"
  local wt="$project/milestones/regular/loops/123/.worktree"

  # gh mock — PR view 호출에 즉시 MERGED 반환
  local mock_bin="$WORK_DIR/rf_mock"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
# 단순 mock: --jq 인자 값에 따라 적절한 필드만 반환.
# review-fix-phase.sh가 호출하는 4가지 --jq 패턴 처리:
#   .state, .reviewDecision, .author.login,
#   .comments[] | select(...).body
case "${1:-}/${2:-}" in
  pr/view)
    jq_expr=""
    for ((i=1; i<=$#; i++)); do
      if [[ "${!i}" == "--jq" ]]; then
        j=$((i+1)); jq_expr="${!j}"
      fi
    done
    case "$jq_expr" in
      .state)              echo "MERGED" ;;
      .reviewDecision)     echo "" ;;
      .author.login)       echo "owner" ;;
      *)                   echo '{"state":"MERGED","reviewDecision":null,"reviews":[],"comments":[],"reviewThreads":[],"number":1,"author":{"login":"owner"}}' ;;
    esac
    exit 0
    ;;
  pr/list)
    echo '[{"number":1}]'; exit 0 ;;
  api/*)
    echo '[]'; exit 0 ;;
  project/*)
    exit 0 ;;
esac
exit 0
GH
  chmod +x "$mock_bin/gh"
  cat > "$mock_bin/claude" <<'CL'
#!/usr/bin/env bash
exit 0
CL
  chmod +x "$mock_bin/claude"

  # 빠른 폴링 (1초)·iter 상한 (5회) — 즉시 MERGED 감지로 1회 polling 후 종료
  export LOOP_REVIEW_POLL_SECS=1
  export LOOP_REVIEW_MAX_ITER=5
  out=$(PATH="$mock_bin:$PATH" bash "$SKILL_REFS/review-fix-phase.sh" "$wt" "feat/123-rf" "regular/123" "$project" "1" 2>&1) \
    || fail "review-fix-phase 실패 exit. out=$out"
  echo "$out" | grep -qiE 'merged|종료' \
    || fail "review-fix-phase: MERGED 종료 신호 출력 부재. out=$out"
  pass "review-fix-phase: MERGED 즉시 종료"
}

# ----- rebase-phase.sh: 정상 fast-forward (충돌 없음) 시 0 exit -----
test_rebase_phase_fast_forward() {
  local project="$WORK_DIR/rb_proj"
  local bare="$WORK_DIR/rb_proj.git"
  git init -q --bare -b main "$bare"
  mkdir -p "$project"
  (
    cd "$project"
    git init -q -b main
    git config user.email "t@e.com"; git config user.name "T"
    git remote add origin "$bare"
    git commit --allow-empty -q -m initial
    git push -q origin main
    # default 브랜치 감지(rebase-phase.sh)의 git symbolic-ref 경로용
    git remote set-head origin main
    mkdir -p milestones/regular/loops/123
    git worktree add -q -b feat/123-rb milestones/regular/loops/123/.worktree HEAD
    cd milestones/regular/loops/123/.worktree
    git commit --allow-empty -q -m "feat: z"
  ) || fail "rebase test setup 실패"
  local wt="$project/milestones/regular/loops/123/.worktree"

  # gh를 stub해 'gh repo view' 호출이 무음 실패하게 (default branch 감지가
  # git symbolic-ref fallback으로 떨어지게)
  local rb_mock="$WORK_DIR/rb_mock"
  mkdir -p "$rb_mock"
  cat > "$rb_mock/gh" <<'GH'
#!/usr/bin/env bash
exit 1
GH
  chmod +x "$rb_mock/gh"

  PATH="$rb_mock:$PATH" bash "$SKILL_REFS/rebase-phase.sh" "$wt" "feat/123-rb" "$project" \
    || fail "rebase-phase: fast-forward에서 0 exit 기대 (충돌 없음)"
  pass "rebase-phase: fast-forward 0 exit"
}

# =====================================================================
# SPEC 153 — inline review thread comment 1:1 응답 테스트 케이스 (a)~(e)
# =====================================================================
#
# 공통 셋업: 격리 main repo + bare remote + worktree(feat/153-test) + 1개 commit.
# 공통 mock: gh stub은 AUTOPILOT_TEST_PR_FIXTURE(JSON 파일) + AUTOPILOT_TEST_INLINE_FIXTURE
# (JSON 배열 파일)로 PR 본문·인라인 리뷰 코멘트를 주입. 모든 gh 호출은
# AUTOPILOT_TEST_GH_LOG에 한 줄씩 기록 — POST/comments 호출 횟수 등 assertion에 사용.
# claude stub은 AUTOPILOT_TEST_CLAUDE_OUT의 내용을 stdout으로 emit하고,
# AUTOPILOT_TEST_CLAUDE_TOUCH가 지정되면 해당 경로에 파일 변경을 만든다(commit 트리거).

_inline_setup_worktree() {
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
    git commit --allow-empty -q -m initial
    git push -q origin main
    # rebase-phase.sh의 default branch 감지 fallback(git symbolic-ref) 경로용
    git remote set-head origin main
    mkdir -p milestones/regular/loops/153
    git worktree add -q -b feat/153-test milestones/regular/loops/153/.worktree HEAD
    cd milestones/regular/loops/153/.worktree
    # claude mock이 append할 추적 파일 (--untracked-files=no 모드의 commit 트리거)
    echo "// initial" > fix-target.txt
    git add fix-target.txt
    git commit -q -m "feat: x"
    git push -q -u origin feat/153-test
  ) >/dev/null 2>&1 || fail "$case_name setup"
  printf '%s|%s\n' "$project" "$bare"
}

# gh stub — 인라인 thread fixture 기반 응답 + 모든 호출을 log 파일에 기록.
# 호출 형식: gh <cmd> <subcmd> [args...] [--jq <expr>]
_inline_make_gh_mock() {
  local mock_bin="$1"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/gh" <<'GH'
#!/usr/bin/env bash
log_file="${AUTOPILOT_TEST_GH_LOG:-/dev/null}"
echo "CALL|$*" >> "$log_file" 2>/dev/null || true

jq_expr=""
method=""
for ((i=1; i<=$#; i++)); do
  case "${!i}" in
    --jq)     j=$((i+1)); jq_expr="${!j}" ;;
    --method) j=$((i+1)); method="${!j}" ;;
    -X)       j=$((i+1)); method="${!j}" ;;
  esac
done

_pr_fixture() { [[ -f "${AUTOPILOT_TEST_PR_FIXTURE:-}" ]] && cat "$AUTOPILOT_TEST_PR_FIXTURE" || echo "{}"; }
_inline_fixture() { [[ -f "${AUTOPILOT_TEST_INLINE_FIXTURE:-}" ]] && cat "$AUTOPILOT_TEST_INLINE_FIXTURE" || echo "[]"; }

case "${1:-}/${2:-}" in
  pr/view)
    case "$jq_expr" in
      .state)            _pr_fixture | jq -r '.state // ""' ;;
      .reviewDecision)   _pr_fixture | jq -r '.reviewDecision // ""' ;;
      .author.login)     _pr_fixture | jq -r '.author.login // ""' ;;
      "")                _pr_fixture ;;
      *)
        # statusCheckRollup / reviews|length / comments|length / .comments[]?| select 등
        if [[ "$jq_expr" == *statusCheckRollup* ]]; then echo "0"
        elif [[ "$jq_expr" == *reviews* && "$jq_expr" == *length* ]]; then echo "0"
        elif [[ "$jq_expr" == *comments* && "$jq_expr" == *length* ]]; then echo "0"
        elif [[ "$jq_expr" == *comments*select*author.login* ]]; then echo ""
        else echo ""
        fi
        ;;
    esac
    exit 0 ;;
  pr/list)
    echo '[{"number":1}]'; exit 0 ;;
  pr/comment)
    # PR-level fallback (case e). 호출 자체가 log에 기록됨.
    exit 0 ;;
  pr/merge)
    exit 0 ;;
  repo/view)
    case "$jq_expr" in
      .nameWithOwner)            echo "owner/repo" ;;
      .defaultBranchRef.name)    echo "main" ;;
      "")                        echo '{"nameWithOwner":"owner/repo","defaultBranchRef":{"name":"main"}}' ;;
      *)                         echo "" ;;
    esac
    exit 0 ;;
  api/*)
    # URL은 첫 positional non-flag 인자에서 추출 ($2는 flag일 수 있음 — 예: `--method`).
    # 가능 형태: `gh api <URL>` / `gh api --method POST <URL>` / `gh api -X POST <URL>` / 추가 -f·-F 인자
    url=""
    for ((u=2; u<=$#; u++)); do
      a="${!u}"
      case "$a" in
        --method|-X) u=$((u+1)) ;;   # flag 값 1개 건너뜀
        -f|-F)       u=$((u+1)) ;;   # -f/-F key=value의 value 건너뜀 (URL 전이라 가능성 낮지만 안전)
        --jq)        u=$((u+1)) ;;
        -*)          ;;              # 기타 flag — 값 없는 toggle 가정
        *) url="$a"; break ;;
      esac
    done
    if [[ "$method" == "POST" && "$url" == *"/pulls/"*"/comments" ]]; then
      # inline thread reply POST. 실 GitHub REST API의 타입 검증을 모방:
      #   - `in_reply_to`는 정수 필드 → `-F`(typed) 필수, `-f`(string)면 422.
      #   - `body`는 문자열 → `-f`/`-F` 둘 다 허용 (검증 안 함).
      # `-f in_reply_to=<val>`이 인자에 포함되면 mock도 422-equivalent로 fail.
      bad_inreplyto=0
      for ((k=1; k<=$#; k++)); do
        if [[ "${!k}" == "-f" ]]; then
          n=$((k+1))
          [[ "${!n}" == in_reply_to=* ]] && bad_inreplyto=1
        fi
      done
      if (( bad_inreplyto )); then
        echo "MOCK_GH_API_422: in_reply_to passed as -f (string) — REST API requires integer (-F)" >&2
        exit 22
      fi
      # log은 위에서 이미 기록됨.
      exit 0
    fi
    if [[ "$url" == *"/pulls/"*"/comments" ]]; then
      if [[ "$jq_expr" == "length" ]]; then _inline_fixture | jq -r 'length'
      elif [[ -n "$jq_expr" ]]; then _inline_fixture | jq -r "$jq_expr"
      else _inline_fixture
      fi
      exit 0
    fi
    if [[ "$url" == *"/issues/"*"/comments" ]]; then
      if [[ -n "$jq_expr" ]]; then echo "[]" | jq -r "$jq_expr"; else echo "[]"; fi
      exit 0
    fi
    if [[ "$url" == *"/pulls/"*"/reviews" ]]; then
      if [[ -n "$jq_expr" ]]; then echo "[]" | jq -r "$jq_expr"; else echo "[]"; fi
      exit 0
    fi
    echo "[]"; exit 0 ;;
  project/*)
    exit 0 ;;
esac
exit 0
GH
  chmod +x "$mock_bin/gh"
}

_inline_make_claude_mock() {
  local mock_bin="$1"
  cat > "$mock_bin/claude" <<'CL'
#!/usr/bin/env bash
cat >/dev/null   # stdin 무시
if [[ -n "${AUTOPILOT_TEST_CLAUDE_TOUCH:-}" ]]; then
  mkdir -p "$(dirname "$AUTOPILOT_TEST_CLAUDE_TOUCH")" 2>/dev/null || true
  echo "// fix applied" >> "$AUTOPILOT_TEST_CLAUDE_TOUCH"
fi
printf '%s\n' "${AUTOPILOT_TEST_CLAUDE_OUT:-DONE}"
exit 0
CL
  chmod +x "$mock_bin/claude"
}

# fixture builders
_inline_fixture_pr_open() {
  cat > "$1" <<'JSON'
{"state":"OPEN","reviewDecision":null,"number":1,"author":{"login":"owner"},"comments":[],"reviews":[]}
JSON
}
_inline_fixture_one_comment() {
  cat > "$1" <<'JSON'
[{"id":101,"body":"please rename foo to bar","in_reply_to_id":null}]
JSON
}
_inline_fixture_two_same_thread() {
  cat > "$1" <<'JSON'
[
  {"id":101,"body":"first wrong comment","in_reply_to_id":null},
  {"id":102,"body":"second comment same thread","in_reply_to_id":101}
]
JSON
}
_inline_fixture_two_threads() {
  cat > "$1" <<'JSON'
[
  {"id":101,"body":"thread A comment","in_reply_to_id":null},
  {"id":201,"body":"thread B comment","in_reply_to_id":null}
]
JSON
}

# 공통 실행 helper — 단일 iter로 review-fix-phase 호출
_inline_run_phase() {
  local mock_bin="$1" wt="$2" project="$3" out_file="$4"
  export LOOP_REVIEW_POLL_SECS=1
  export LOOP_REVIEW_MAX_ITER=1
  PATH="$mock_bin:$PATH" bash "$SKILL_REFS/review-fix-phase.sh" "$wt" "feat/153-test" "regular/153" "$project" "1" \
       >"$out_file" 2>&1 || true
}

# ----- (a) inline 타당 → 코드 수정 push 1회 -----
test_a_inline_valid_codefix_push() {
  local pair; pair=$(_inline_setup_worktree "case_a")
  local project="${pair%|*}" bare="${pair#*|}"
  local wt="$project/milestones/regular/loops/153/.worktree"

  local mock_bin="$WORK_DIR/case_a_mock"
  _inline_make_gh_mock "$mock_bin"
  _inline_make_claude_mock "$mock_bin"

  local pr_fixture="$WORK_DIR/case_a_pr.json"; _inline_fixture_pr_open "$pr_fixture"
  local inline_fixture="$WORK_DIR/case_a_inline.json"; _inline_fixture_one_comment "$inline_fixture"
  local log="$WORK_DIR/case_a_gh.log"; : > "$log"

  local before_sha; before_sha=$( cd "$bare" && git rev-parse refs/heads/feat/153-test )

  export AUTOPILOT_TEST_PR_FIXTURE="$pr_fixture"
  export AUTOPILOT_TEST_INLINE_FIXTURE="$inline_fixture"
  export AUTOPILOT_TEST_GH_LOG="$log"
  export AUTOPILOT_TEST_CLAUDE_OUT=$'INLINE 101 101 FIX\nDONE'
  export AUTOPILOT_TEST_CLAUDE_TOUCH="$wt/fix-target.txt"

  _inline_run_phase "$mock_bin" "$wt" "$project" "$WORK_DIR/case_a.out"

  local after_sha; after_sha=$( cd "$bare" && git rev-parse refs/heads/feat/153-test 2>/dev/null || echo "" )
  [[ "$before_sha" != "$after_sha" ]] \
    || { cat "$WORK_DIR/case_a.out"; fail "(a) inline 타당: bare에 push 없음 (SHA 미변경)"; }

  # POST inline reply 없어야 함
  if grep -F "CALL|" "$log" | grep -qE -- '--method[[:space:]]+POST.*pulls/[0-9]+/comments|-X[[:space:]]+POST.*pulls/[0-9]+/comments'; then
    cat "$log"; fail "(a) inline 타당: 코드 수정인데 inline reply POST 발생"
  fi
  unset AUTOPILOT_TEST_CLAUDE_TOUCH
  pass "(a) inline 타당 → 코드 수정 push 1회 (reply 0)"
}

# ----- (b) inline 부당 → 해당 thread에 reply 1개 -----
test_b_inline_invalid_thread_reply() {
  local pair; pair=$(_inline_setup_worktree "case_b")
  local project="${pair%|*}" bare="${pair#*|}"
  local wt="$project/milestones/regular/loops/153/.worktree"

  local mock_bin="$WORK_DIR/case_b_mock"
  _inline_make_gh_mock "$mock_bin"
  _inline_make_claude_mock "$mock_bin"

  local pr_fixture="$WORK_DIR/case_b_pr.json"; _inline_fixture_pr_open "$pr_fixture"
  local inline_fixture="$WORK_DIR/case_b_inline.json"; _inline_fixture_one_comment "$inline_fixture"
  local log="$WORK_DIR/case_b_gh.log"; : > "$log"

  local before_sha; before_sha=$( cd "$bare" && git rev-parse refs/heads/feat/153-test )

  export AUTOPILOT_TEST_PR_FIXTURE="$pr_fixture"
  export AUTOPILOT_TEST_INLINE_FIXTURE="$inline_fixture"
  export AUTOPILOT_TEST_GH_LOG="$log"
  export AUTOPILOT_TEST_CLAUDE_OUT=$'INLINE 101 101 DISPUTE reviewer is mistaken about naming\nDONE'
  unset AUTOPILOT_TEST_CLAUDE_TOUCH

  _inline_run_phase "$mock_bin" "$wt" "$project" "$WORK_DIR/case_b.out"

  local after_sha; after_sha=$( cd "$bare" && git rev-parse refs/heads/feat/153-test 2>/dev/null || echo "" )
  [[ "$before_sha" == "$after_sha" ]] \
    || { cat "$WORK_DIR/case_b.out"; fail "(b) inline 부당: 코드 변경 없는데 push 발생"; }

  local post_count
  post_count=$(grep -F "CALL|" "$log" | grep -cE -- '--method[[:space:]]+POST.*pulls/[0-9]+/comments|-X[[:space:]]+POST.*pulls/[0-9]+/comments' || true)
  [[ "$post_count" -eq 1 ]] \
    || { cat "$log"; fail "(b) inline 부당: POST inline reply $post_count 회 (기대 1)"; }
  grep -F "CALL|" "$log" | grep -qE 'in_reply_to[^|]*101' \
    || { cat "$log"; fail "(b) inline 부당: in_reply_to=101 인자 부재"; }

  # PR-level gh pr comment fallback 사용되지 않아야 함
  if grep -E '^CALL\|pr comment' "$log" >/dev/null 2>&1; then
    cat "$log"; fail "(b) inline 부당: PR-level gh pr comment fallback 사용됨"
  fi
  pass "(b) inline 부당 → inline thread reply 1개 (in_reply_to=101)"
}

# ----- (c) 같은 thread 재폴링 시 중복 reply 미게시 -----
# 같은 thread 안 두 comment(101 root, 102 reply-of-101)가 동시 폴링되어도 thread-level dedup으로 reply 1개.
test_c_same_thread_no_duplicate_reply() {
  local pair; pair=$(_inline_setup_worktree "case_c")
  local project="${pair%|*}" bare="${pair#*|}"
  local wt="$project/milestones/regular/loops/153/.worktree"

  local mock_bin="$WORK_DIR/case_c_mock"
  _inline_make_gh_mock "$mock_bin"
  _inline_make_claude_mock "$mock_bin"

  local pr_fixture="$WORK_DIR/case_c_pr.json"; _inline_fixture_pr_open "$pr_fixture"
  local inline_fixture="$WORK_DIR/case_c_inline.json"; _inline_fixture_two_same_thread "$inline_fixture"
  local log="$WORK_DIR/case_c_gh.log"; : > "$log"

  export AUTOPILOT_TEST_PR_FIXTURE="$pr_fixture"
  export AUTOPILOT_TEST_INLINE_FIXTURE="$inline_fixture"
  export AUTOPILOT_TEST_GH_LOG="$log"
  export AUTOPILOT_TEST_CLAUDE_OUT=$'INLINE 101 101 DISPUTE first body\nINLINE 101 102 DISPUTE second body\nDONE'
  unset AUTOPILOT_TEST_CLAUDE_TOUCH

  _inline_run_phase "$mock_bin" "$wt" "$project" "$WORK_DIR/case_c.out"

  local post_count
  post_count=$(grep -F "CALL|" "$log" | grep -cE -- '--method[[:space:]]+POST.*pulls/[0-9]+/comments|-X[[:space:]]+POST.*pulls/[0-9]+/comments' || true)
  [[ "$post_count" -eq 1 ]] \
    || { cat "$log"; fail "(c) 같은 thread 두 comment: POST inline reply $post_count 회 (기대 1, thread dedup)"; }
  pass "(c) 같은 thread 재폴링/내부 dedup → reply 1개"
}

# ----- (d) 서로 다른 inline thread 2개 부당 → 각 thread reply 1개씩 (총 2) -----
test_d_two_threads_two_replies() {
  local pair; pair=$(_inline_setup_worktree "case_d")
  local project="${pair%|*}" bare="${pair#*|}"
  local wt="$project/milestones/regular/loops/153/.worktree"

  local mock_bin="$WORK_DIR/case_d_mock"
  _inline_make_gh_mock "$mock_bin"
  _inline_make_claude_mock "$mock_bin"

  local pr_fixture="$WORK_DIR/case_d_pr.json"; _inline_fixture_pr_open "$pr_fixture"
  local inline_fixture="$WORK_DIR/case_d_inline.json"; _inline_fixture_two_threads "$inline_fixture"
  local log="$WORK_DIR/case_d_gh.log"; : > "$log"

  export AUTOPILOT_TEST_PR_FIXTURE="$pr_fixture"
  export AUTOPILOT_TEST_INLINE_FIXTURE="$inline_fixture"
  export AUTOPILOT_TEST_GH_LOG="$log"
  export AUTOPILOT_TEST_CLAUDE_OUT=$'INLINE 101 101 DISPUTE body for A\nINLINE 201 201 DISPUTE body for B\nDONE'
  unset AUTOPILOT_TEST_CLAUDE_TOUCH

  _inline_run_phase "$mock_bin" "$wt" "$project" "$WORK_DIR/case_d.out"

  local post_count
  post_count=$(grep -F "CALL|" "$log" | grep -cE -- '--method[[:space:]]+POST.*pulls/[0-9]+/comments|-X[[:space:]]+POST.*pulls/[0-9]+/comments' || true)
  [[ "$post_count" -eq 2 ]] \
    || { cat "$log"; fail "(d) 다른 thread 2개: POST inline reply $post_count 회 (기대 2)"; }
  grep -F "CALL|" "$log" | grep -qE 'in_reply_to[^|]*101' \
    || { cat "$log"; fail "(d) thread A reply (in_reply_to=101) 부재"; }
  grep -F "CALL|" "$log" | grep -qE 'in_reply_to[^|]*201' \
    || { cat "$log"; fail "(d) thread B reply (in_reply_to=201) 부재"; }
  pass "(d) 서로 다른 thread 2개 → 각 thread reply 1개씩 (총 2)"
}

# ----- (e) PR-level dispute / review summary / owner cmd 경로 보존 -----
# PR-level DISPUTE 본문(기존 흐름)이 gh pr comment를 통해 1회 게시되는지 확인.
# inline reply POST는 없어야 함.
test_e_pr_level_dispute_preserved() {
  local pair; pair=$(_inline_setup_worktree "case_e")
  local project="${pair%|*}" bare="${pair#*|}"
  local wt="$project/milestones/regular/loops/153/.worktree"

  local mock_bin="$WORK_DIR/case_e_mock"
  _inline_make_gh_mock "$mock_bin"
  _inline_make_claude_mock "$mock_bin"

  local pr_fixture="$WORK_DIR/case_e_pr.json"; _inline_fixture_pr_open "$pr_fixture"
  # PR-level이 trigger되도록 inline은 비우고, PR-level 이슈 코멘트 트리거 대신
  # 단순히 inline fixture에 1개 두고 claude가 PR-level DISPUTE를 emit하는 케이스를 검증.
  local inline_fixture="$WORK_DIR/case_e_inline.json"; _inline_fixture_one_comment "$inline_fixture"
  local log="$WORK_DIR/case_e_gh.log"; : > "$log"

  export AUTOPILOT_TEST_PR_FIXTURE="$pr_fixture"
  export AUTOPILOT_TEST_INLINE_FIXTURE="$inline_fixture"
  export AUTOPILOT_TEST_GH_LOG="$log"
  export AUTOPILOT_TEST_CLAUDE_OUT=$'DISPUTE: PR-level concern about overall approach\nDONE'
  unset AUTOPILOT_TEST_CLAUDE_TOUCH

  _inline_run_phase "$mock_bin" "$wt" "$project" "$WORK_DIR/case_e.out"

  # 기존 gh pr comment 경로 1회 호출
  local pr_comment_count
  pr_comment_count=$(grep -cE '^CALL\|pr comment' "$log" || true)
  [[ "$pr_comment_count" -eq 1 ]] \
    || { cat "$log"; fail "(e) PR-level DISPUTE: gh pr comment $pr_comment_count 회 (기대 1, 기존 경로 보존)"; }

  # inline reply POST는 없어야 함 (PR-level은 PR-level 경로로만 처리)
  if grep -F "CALL|" "$log" | grep -qE -- '--method[[:space:]]+POST.*pulls/[0-9]+/comments|-X[[:space:]]+POST.*pulls/[0-9]+/comments'; then
    cat "$log"; fail "(e) PR-level DISPUTE: inline reply POST 발생 (PR-level은 inline 경로 쓰지 않아야 함)"
  fi
  pass "(e) PR-level dispute · review summary · owner cmd 경로 보존"
}

# ----- 실행 -----
test_spec_verify_command
test_phase_scripts_arg_validation
test_cleanup_phase_removes_worktree_and_branches
test_review_fix_phase_terminates_on_merged
test_rebase_phase_fast_forward
test_a_inline_valid_codefix_push
test_b_inline_invalid_thread_reply
test_c_same_thread_no_duplicate_reply
test_d_two_threads_two_replies
test_e_pr_level_dispute_preserved

echo "----------"
echo "ALL TESTS PASSED"
