#!/usr/bin/env bash
# rebase-phase.sh — SPEC 123 M1 + SPEC 169 push sync policy
#
# PR 생성·재사용 직전, 그리고 review-fix 루프의 각 fix iter 직전에 호출되는 단일 sync helper.
# 워크트리의 feat 브랜치를 default 브랜치로 동기화한다.
#
# 동기화 모드 (SPEC 169):
#   - 원격 트래킹 브랜치 부재 → rebase 경로 (history 재배치, 깨끗한 linear history)
#   - 원격 트래킹 브랜치 존재 → merge 경로 (자기 commit SHA 보존, force push 회피)
# 두 경로 어디서도 force push(`--force`·`--force-with-lease` 포함)를 도입하지 않는다.
#
# 사용:
#   bash rebase-phase.sh <worktree> <branch> <project-root>
#
# 동작 요약:
#   1. default 브랜치 감지 (gh repo view → git symbolic-ref → 실패 abort)
#   2. origin/<default> fetch
#   3. `git ls-remote --heads origin <branch>`로 원격 브랜치 존재 여부 판정 → SYNC_MODE
#   4. rebase 경로: `git rebase origin/<default>`
#      merge  경로: `git merge --ff-only origin/<default>` → 실패 시 non-ff `git merge --no-edit`
#   5. 충돌 시 claude CLI 세션 1회로 자동 해소 시도 (SPEC 123 AC2 / SPEC 169 AC5).
#      - claude 미설치·세션 실패·해소 후 잔존 → 해당 모드의 abort 명령으로 워크트리 복구 + 비-zero exit.
#   6. 어떤 단계든 비-zero exit 시 stdout 첫 줄에 "ESCALATION" prefix를 출력해
#      caller(loop.sh·pr-phase.sh·review-fix-phase.sh)가 종료 신호로 감지하게 한다.
#
# 파일명은 SPEC 169 이후에도 `rebase-phase.sh` 그대로 유지(rename은 환경변수·문서 파급 회피로 SPEC 범위 외).
# 의미는 "sync helper" — 본 스크립트 자체는 두 모드를 모두 책임진다.

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

# ----- 동기화 모드 판정 (SPEC 169 AC1) -----
# `git ls-remote --heads --exit-code origin <branch>`는 원격에 해당 ref가 있으면 0,
# 없으면 2를 반환. 원격에 자기 브랜치가 이미 존재하면 history 재작성이 force push를
# 강제하므로 merge로 base 변경분만 흡수한다. 부재 시(첫 PR 진입 전)는 깨끗한 linear
# history를 위해 rebase로 재배치한다.
SYNC_MODE="rebase"
ls_remote_rc=0
( cd "$WT" && git ls-remote --heads --exit-code origin "$BRANCH" >/dev/null 2>&1 ) || ls_remote_rc=$?
if (( ls_remote_rc == 0 )); then
  SYNC_MODE="merge"
elif (( ls_remote_rc != 2 )); then
  emit_escalation "git ls-remote 실패 (exit $ls_remote_rc) — SYNC_MODE 판정 불가 (네트워크/인증 오류 가능, 브랜치 부재(rc=2)와 구분)"
  exit 1
fi
echo "[rebase-phase] sync mode: $SYNC_MODE (origin/$BRANCH $( [[ $SYNC_MODE == merge ]] && echo present || echo absent ))"

# allowed-tools는 caller(loop.sh)에서 export한 환경 변수 또는 본 스크립트 기본값.
# 환경 변수 이름은 SPEC 169 이후에도 `AUTOPILOT_REBASE_ALLOWED_TOOLS` 유지 — rename은
# SPEC 169 범위 외(파급 회피).
ALLOWED_TOOLS_REBASE="${AUTOPILOT_REBASE_ALLOWED_TOOLS:-Bash(git add:*),Bash(git status:*),Bash(git diff:*),Bash(cat:*),Bash(ls:*),Read,Edit,Write}"

# ----- 공통 충돌 해소 helper (claude CLI 1회) -----
# 두 경로(rebase·merge)가 동일한 해소 전략을 공유한다 — claude 세션에 conflict marker
# 파일을 알리고 in-place로 해소하게 한 뒤 `git add`까지 위임, 본 스크립트가 continue.
# 반환:
#   0 = 세션 완료 + unresolved 잔존 없음 (caller가 mode별 --continue 수행)
#   1 = claude 미설치 또는 세션 비-zero exit
#   2 = 세션 후에도 unresolved 잔존
resolve_conflicts_via_claude() {
  local mode_label="$1"   # "rebase" 또는 "merge" — 로그·프롬프트 어휘만 분기
  if ! command -v claude >/dev/null 2>&1; then
    return 1
  fi
  # claude 세션에 conflict marker가 있는 파일 목록 + diff를 stdin으로 넘긴다.
  local conflict_files
  conflict_files=$( cd "$WT" && git diff --name-only --diff-filter=U 2>/dev/null || true )
  # claude 세션이 충돌을 해소할 수 있도록 작업 디렉토리·헌법(워크트리 CLAUDE.md)을 제공.
  # --dangerously-skip-permissions는 사용하지 않고 allowed-tools로 명시 범위 제한.
  local claude_prompt
  claude_prompt=$(cat <<EOF
You are inside a git $mode_label conflict on branch '$BRANCH' onto 'origin/$DEFAULT_BRANCH'.
Conflicted files:
$conflict_files

Goal: resolve each conflict in-place, preferring the intent of branch '$BRANCH' (feat
branch) but keeping any non-conflicting changes from base. Edit each file to remove
the '<<<<<<<', '=======', '>>>>>>>' markers. Then run 'git add' on each resolved
file. DO NOT run 'git rebase --continue' or 'git merge --continue' yourself — the
caller will do that. DO NOT push, commit, or create branches.

When done, output a single line: 'RESOLVED'.
EOF
)
  mkdir -p "$WT/.iterations" 2>/dev/null || true   # 독립 호출 시에도 로그 쓰기 보장
  local claude_exit=0
  ( cd "$WT" && printf '%s' "$claude_prompt" | claude \
      --print \
      --no-session-persistence \
      --add-dir . \
      --allowed-tools "$ALLOWED_TOOLS_REBASE" \
      --output-format text \
      > ".iterations/${mode_label}-conflict.log" 2>&1 ) || claude_exit=$?
  if (( claude_exit != 0 )); then
    return 1
  fi
  # claude 세션이 파일을 모두 git add 했는지 확인 (unresolved 잔존 검사).
  if ( cd "$WT" && git diff --name-only --diff-filter=U 2>/dev/null | grep -q . ); then
    return 2
  fi
  return 0
}

# ----- rebase 경로 (SPEC 169 AC2): 원격 트래킹 부재 → history 재배치 -----
if [[ "$SYNC_MODE" == "rebase" ]]; then
  echo "[rebase-phase] rebase onto origin/$DEFAULT_BRANCH"
  if ( cd "$WT" && git rebase "origin/$DEFAULT_BRANCH" 2>&1 ); then
    echo "[rebase-phase] rebase 성공 (충돌 없음)"
    exit 0
  fi
  echo "[rebase-phase] rebase 충돌 감지 — claude CLI 자동 해소 시도 (1회)"
  rc=0
  resolve_conflicts_via_claude "rebase" || rc=$?
  if (( rc != 0 )); then
    ( cd "$WT" && git rebase --abort 2>/dev/null || true )
    if (( rc == 1 )); then
      emit_escalation "claude CLI 미설치 또는 세션 실패 — 워크트리 rebase --abort 복구"
    else
      emit_escalation "claude 해소 후에도 충돌 잔존 — 워크트리 rebase --abort 복구"
    fi
    exit 1
  fi
  if ( cd "$WT" && GIT_EDITOR=true git rebase --continue 2>&1 ); then
    echo "[rebase-phase] rebase 충돌 자동 해소 성공 (claude CLI)"
    exit 0
  fi
  ( cd "$WT" && git rebase --abort 2>/dev/null || true )
  emit_escalation "claude 해소 후에도 git rebase --continue 실패 — 워크트리 rebase --abort 복구"
  exit 1
fi

# ----- merge 경로 (SPEC 169 AC3): 원격 트래킹 존재 → 자기 SHA 보존 -----
# 1차 ff-only: base 변화 없음 또는 feat가 base의 후손인 경우 no-op으로 통과 (불필요 merge commit 회피).
# 2차 non-ff:  diverged base를 흡수해 새 merge commit 생성. 자기 commit SHA는 그대로 reachable.
echo "[rebase-phase] merge from origin/$DEFAULT_BRANCH (ff-only 우선 시도)"
if ( cd "$WT" && git merge --ff-only "origin/$DEFAULT_BRANCH" 2>&1 ); then
  echo "[rebase-phase] fast-forward 또는 already up-to-date — merge commit 없음"
  exit 0
fi
echo "[rebase-phase] non-ff merge 시도 — base 변경분 흡수"
if ( cd "$WT" && git merge --no-edit "origin/$DEFAULT_BRANCH" 2>&1 ); then
  echo "[rebase-phase] merge 성공 (merge commit 생성)"
  exit 0
fi
echo "[rebase-phase] merge 충돌 감지 — claude CLI 자동 해소 시도 (1회)"
rc=0
resolve_conflicts_via_claude "merge" || rc=$?
if (( rc != 0 )); then
  ( cd "$WT" && git merge --abort 2>/dev/null || true )
  if (( rc == 1 )); then
    emit_escalation "claude CLI 미설치 또는 세션 실패 — 워크트리 merge --abort 복구"
  else
    emit_escalation "claude 해소 후에도 충돌 잔존 — 워크트리 merge --abort 복구"
  fi
  exit 1
fi
# `git merge --continue` (git 2.12+)는 editor를 띄우므로 GIT_EDITOR=true로 silence.
if ( cd "$WT" && GIT_EDITOR=true git merge --continue 2>&1 ); then
  echo "[rebase-phase] merge 충돌 자동 해소 성공 (claude CLI)"
  exit 0
fi
( cd "$WT" && git merge --abort 2>/dev/null || true )
emit_escalation "claude 해소 후에도 git merge --continue 실패 — 워크트리 merge --abort 복구"
exit 1
