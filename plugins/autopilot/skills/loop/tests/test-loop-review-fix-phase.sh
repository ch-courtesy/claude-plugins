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

# ----- 실행 -----
test_spec_verify_command
test_phase_scripts_arg_validation
test_cleanup_phase_removes_worktree_and_branches
test_review_fix_phase_terminates_on_merged
test_rebase_phase_fast_forward

echo "----------"
echo "ALL TESTS PASSED"
