#!/usr/bin/env bash
# rebase-phase.sh — SPEC 123 M1
#
# PR 생성·재사용 직전, 그리고 review-fix 루프의 각 fix iter 직전에 호출되어
# 워크트리의 feat 브랜치를 default 브랜치로 rebase한다.
#
# 사용:
#   bash rebase-phase.sh <worktree> <branch> <project-root>
#
# 동작:
#   1. default 브랜치 감지 (gh repo view → git symbolic-ref → 실패 abort)
#   2. origin/<default> fetch
#   3. git rebase origin/<default>
#   4. 성공 시 0 exit (fast-forward·동일 history 포함).
#   5. 실패(충돌) 시 claude CLI 세션 1회로 자동 해소 시도 (SPEC 123 AC2).
#      - claude CLI 미설치·실패 시 보수적 좌절 (rebase --abort + non-zero exit).
#   6. 자동 해소 후 `git rebase --continue` 시도, 그래도 실패하면 abort.
#   7. 어떤 단계든 비-zero exit 시 stdout 첫 줄에 "ESCALATION" prefix를 출력해
#      caller(loop.sh·review-fix-phase.sh)가 종료 신호로 감지하게 한다 (SPEC 123 AC19).

set -euo pipefail

WT="${1:-}"
BRANCH="${2:-}"
PROJECT_ROOT="${3:-}"

if [[ -z "$WT" || -z "$BRANCH" || -z "$PROJECT_ROOT" ]]; then
  echo "사용: $0 <worktree> <branch> <project-root>" >&2
  exit 2
fi
[[ -d "$WT" ]] || { echo "ERROR: 워크트리 없음: $WT" >&2; exit 1; }

emit_escalation() {
  # caller 감지용 단일 라인 — stdout(또는 caller가 redirect한 stream).
  echo "ESCALATION rebase-phase: $*"
}

detect_default_branch() {
  local b=""
  if command -v gh >/dev/null 2>&1; then
    b=$(cd "$WT" && gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)
  fi
  if [[ -z "$b" ]]; then
    local ref
    ref=$(cd "$WT" && git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)
    [[ -n "$ref" ]] && b="${ref#refs/remotes/origin/}"
  fi
  printf '%s' "$b"
}

DEFAULT_BRANCH="$(detect_default_branch)"
if [[ -z "$DEFAULT_BRANCH" ]]; then
  emit_escalation "default 브랜치 감지 실패 (gh repo view / git symbolic-ref 모두 실패)"
  exit 1
fi

echo "[rebase-phase] origin/$DEFAULT_BRANCH fetch"
if ! ( cd "$WT" && git fetch origin "$DEFAULT_BRANCH" 2>&1 ); then
  emit_escalation "git fetch origin $DEFAULT_BRANCH 실패"
  exit 1
fi

echo "[rebase-phase] rebase onto origin/$DEFAULT_BRANCH"
if ( cd "$WT" && git rebase "origin/$DEFAULT_BRANCH" 2>&1 ); then
  echo "[rebase-phase] rebase 성공 (충돌 없음)"
  exit 0
fi

# ----- 충돌 — claude CLI 1회 자동 해소 시도 -----
echo "[rebase-phase] rebase 충돌 감지 — claude CLI 자동 해소 시도 (1회)"

if ! command -v claude >/dev/null 2>&1; then
  ( cd "$WT" && git rebase --abort 2>/dev/null || true )
  emit_escalation "claude CLI 미설치 — 충돌 자동 해소 불가"
  exit 1
fi

# claude 세션에 conflict marker가 있는 파일 목록 + diff를 stdin으로 넘긴다.
# allowed-tools는 caller(loop.sh)에서 export한 환경 변수 또는 본 스크립트 기본값.
ALLOWED_TOOLS_REBASE="${AUTOPILOT_REBASE_ALLOWED_TOOLS:-Bash(git add:*),Bash(git status:*),Bash(git diff:*),Bash(cat:*),Bash(ls:*),Read,Edit,Write}"

# claude 세션이 충돌을 해소할 수 있도록 작업 디렉토리·헌법(워크트리 CLAUDE.md)을 제공.
# --dangerously-skip-permissions는 사용하지 않고 allowed-tools로 명시 범위 제한.
conflict_files=$( cd "$WT" && git diff --name-only --diff-filter=U 2>/dev/null || true )

claude_prompt=$(cat <<EOF
You are inside a git rebase conflict on branch '$BRANCH' onto 'origin/$DEFAULT_BRANCH'.
Conflicted files:
$conflict_files

Goal: resolve each conflict in-place, preferring the intent of branch '$BRANCH' (feat
branch) but keeping any non-conflicting changes from base. Edit each file to remove
the '<<<<<<<', '=======', '>>>>>>>' markers. Then run 'git add' on each resolved
file. DO NOT run 'git rebase --continue' yourself — the caller will do that. DO NOT
push, commit, or create branches.

When done, output a single line: 'RESOLVED'.
EOF
)

claude_exit=0
( cd "$WT" && printf '%s' "$claude_prompt" | claude \
    --print \
    --no-session-persistence \
    --add-dir . \
    --allowed-tools "$ALLOWED_TOOLS_REBASE" \
    --output-format text \
    > .iterations/rebase-conflict.log 2>&1 ) || claude_exit=$?

if (( claude_exit != 0 )); then
  ( cd "$WT" && git rebase --abort 2>/dev/null || true )
  emit_escalation "claude CLI 충돌 해소 세션 실패 (exit $claude_exit) — 워크트리 abort 복구 완료"
  exit 1
fi

# claude 세션이 파일을 모두 git add 했는지 확인 후 rebase --continue
if ! ( cd "$WT" && git diff --name-only --diff-filter=U 2>/dev/null | grep -q . ); then
  if ( cd "$WT" && GIT_EDITOR=true git rebase --continue 2>&1 ); then
    echo "[rebase-phase] 충돌 자동 해소 성공 (claude CLI)"
    exit 0
  fi
fi

( cd "$WT" && git rebase --abort 2>/dev/null || true )
emit_escalation "claude CLI 해소 후에도 git rebase --continue 실패 — 워크트리 abort 복구"
exit 1
