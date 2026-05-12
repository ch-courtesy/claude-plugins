#!/usr/bin/env bash
# pr-phase.sh — loop DONE 이후 PR 생성·재사용 단계
#
# 사용:
#   bash pr-phase.sh <worktree> <branch> <task-id> <project-root>
#
# 책임:
#   1. default 브랜치 감지 (gh → git symbolic-ref → fail abort)
#   2. 현재 브랜치를 origin으로 push
#   3. 동일 head 브랜치의 open PR 존재 여부 확인
#      - 없으면: 새 PR 생성 (--base default --head branch)
#      - 있으면: 기존 PR 제목·body in-place 갱신
#   4. PR 제목 = SPEC 문서 제목 (첫 H1)
#   5. PR body = "무엇을 만들 것인가" 본문 + base..HEAD commit log,
#      marker fence(<!-- autopilot:pr-body:begin/end -->)로 감쌈.
#      task-id가 ^[0-9]+$ 패턴이면 본문 마지막 줄에 "Closes #<id>" 추가.
#   6. reviewer/label/assignee 플래그는 일체 설정 안 함 (AC7).
#   7. push·pr create·pr edit 중 어느 하나라도 실패 시 즉시 non-zero exit + 하위 stderr passthrough (AC8).
#   8. 성공 시 PR URL·state를 stdout으로 출력 (AC9). worktree·local 브랜치 보존.
#
# opt-in 감지(request_review SPEC frontmatter)는 caller(loop.sh)가 책임진다 — 본 스크립트는
# 호출되면 무조건 PR 단계를 실행한다.

set -euo pipefail

WT="${1:-}"
BRANCH="${2:-}"
TASK_ID="${3:-}"
# PROJECT_ROOT: 본 phase에서는 미사용 — 후속 phase(리뷰 모니터·자동 fix·완료 감지·정리)에서
# 메인 repo를 대상으로 cherry-pick·merge·worktree remove 등 워크트리 밖 작업을 수행할 때 필요.
# caller(loop.sh)는 이미 전달하고 있어 시그니처는 유지하되, 호출자 실수(누락) 방지를 위해 검증은
# 유지. 본 스크립트 내 사용 위치가 추가될 때 본 주석 제거.
PROJECT_ROOT="${4:-}"

[[ -n "$WT" && -n "$BRANCH" && -n "$TASK_ID" && -n "$PROJECT_ROOT" ]] \
  || { echo "사용: $0 <worktree> <branch> <task-id> <project-root>" >&2; exit 2; }
[[ -d "$WT" ]] || { echo "ERROR: 워크트리 디렉토리 없음: $WT" >&2; exit 1; }

# ----- default 브랜치 감지 (M2) -----
# 1차: gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
# 2차: git symbolic-ref refs/remotes/origin/HEAD → "origin/<name>" 끝 부분
# 둘 다 실패 → AC10에 따라 push·pr 명령 호출 전 abort.
detect_default_branch() {
  local b=""
  if command -v gh >/dev/null 2>&1; then
    b=$(cd "$WT" && gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)
  fi
  if [[ -z "$b" ]]; then
    local ref
    ref=$(cd "$WT" && git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)
    if [[ -n "$ref" ]]; then
      b="${ref#refs/remotes/origin/}"
    fi
  fi
  printf '%s' "$b"
}

DEFAULT_BRANCH="$(detect_default_branch)"
if [[ -z "$DEFAULT_BRANCH" ]]; then
  echo "ERROR: default 브랜치 감지 실패 (gh repo view / git symbolic-ref 모두 실패). PR 단계 abort." >&2
  exit 1
fi

# ----- SPEC 제목·본문 추출 (M3) -----
SPEC_FILE="$WT/.loop/SPEC.md"
[[ -f "$SPEC_FILE" ]] || { echo "ERROR: SPEC.md 없음: $SPEC_FILE" >&2; exit 1; }

# 첫 H1 (frontmatter 이후의 단일 # 라인)
extract_spec_title() {
  awk '
    /^---$/ { fm++; next }
    fm == 1 { next }
    /^# / { sub(/^# /, ""); print; exit }
  ' "$SPEC_FILE"
}

# "무엇을 만들 것인가" 섹션 본문 (다음 ## 라인 직전까지)
extract_what_section() {
  awk '
    /^## 무엇을 만들 것인가/ { in_section = 1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$SPEC_FILE"
}

SPEC_TITLE="$(extract_spec_title)"
[[ -n "$SPEC_TITLE" ]] || { echo "ERROR: SPEC.md에서 제목(H1)을 찾을 수 없음" >&2; exit 1; }
WHAT_SECTION="$(extract_what_section)"

# base..HEAD commit log (워크트리의 현재 브랜치 기준)
collect_commit_log() {
  local base="origin/$DEFAULT_BRANCH"
  # base가 존재하지 않으면 (신생 브랜치 — origin/HEAD가 fetch 안 됨 등) base 없이 전체 brief history
  if ! ( cd "$WT" && git rev-parse --verify "$base" >/dev/null 2>&1 ); then
    ( cd "$WT" && git log --pretty=format:'- %h %s' -n 10 2>/dev/null || true )
    return
  fi
  ( cd "$WT" && git log --pretty=format:'- %h %s' "$base..HEAD" 2>/dev/null || true )
}

COMMIT_LOG="$(collect_commit_log)"

# Body 본문 (fence 안 내용)
PR_BODY_INNER=$(printf '## 무엇을 만들 것인가\n%s\n\n## Commits\n%s' \
  "$(printf '%s' "$WHAT_SECTION" | sed -e 's/[[:space:]]*$//' )" \
  "${COMMIT_LOG:-(no new commits)}")

# task-id가 숫자(^[0-9]+$)면 Closes #<id> 추가 (M3, AC6)
# task-id는 정규화된 형태(<milestone>/<child>)일 수 있으므로 child 부분만 검사.
CHILD_ID="${TASK_ID##*/}"
if [[ "$CHILD_ID" =~ ^[0-9]+$ ]]; then
  PR_BODY_INNER="$PR_BODY_INNER

Closes #${CHILD_ID}"
fi

PR_BODY_FENCE_BEGIN='<!-- autopilot:pr-body:begin -->'
PR_BODY_FENCE_END='<!-- autopilot:pr-body:end -->'

PR_BODY="$(printf '%s\n%s\n%s' "$PR_BODY_FENCE_BEGIN" "$PR_BODY_INNER" "$PR_BODY_FENCE_END")"

# ----- 브랜치 push (M4) -----
echo "[pr-phase] origin으로 push: $BRANCH"
if ! ( cd "$WT" && git push --set-upstream origin "$BRANCH" 2>&1 ); then
  echo "ERROR: git push 실패 (브랜치: $BRANCH)" >&2
  exit 1
fi

# ----- open PR 존재 확인 (M5 trigger) -----
existing_pr_json=$(cd "$WT" && gh pr list --head "$BRANCH" --state open --json number,url 2>/dev/null || echo '[]')

# jq 없이 단순 검사 — number 키가 등장하면 PR 존재로 간주
existing_pr_count=0
if [[ "$existing_pr_json" != "[]" ]] && echo "$existing_pr_json" | grep -q '"number"'; then
  existing_pr_count=1
fi

if [[ $existing_pr_count -eq 0 ]]; then
  # ----- 새 PR 생성 (M4) -----
  echo "[pr-phase] 새 PR 생성 (base: $DEFAULT_BRANCH, head: $BRANCH)"
  if ! pr_url=$( cd "$WT" && gh pr create \
    --base "$DEFAULT_BRANCH" \
    --head "$BRANCH" \
    --title "$SPEC_TITLE" \
    --body "$PR_BODY" ); then
    echo "ERROR: gh pr create 실패" >&2
    exit 1
  fi
  echo "PR URL: $pr_url"
  echo "PR state: open"
else
  # ----- 기존 PR in-place 갱신 (M5) -----
  pr_number=$(echo "$existing_pr_json" | sed -nE 's/.*"number":[[:space:]]*([0-9]+).*/\1/p' | head -1)
  pr_url=$(echo "$existing_pr_json" | sed -nE 's/.*"url":[[:space:]]*"([^"]+)".*/\1/p' | head -1)
  echo "[pr-phase] 기존 open PR 재사용 (number: $pr_number)"

  # 기존 body 가져오기 (fence 안만 교체하려면 필요)
  existing_body=$( cd "$WT" && gh pr view "$pr_number" --json body --jq '.body' 2>/dev/null || true )

  # fence가 기존 body에 있으면 fence 안 영역만 교체, 없으면 전면 재작성 (1회 fence 삽입).
  new_body=""
  if [[ -n "$existing_body" ]] && \
     echo "$existing_body" | grep -qF "$PR_BODY_FENCE_BEGIN" && \
     echo "$existing_body" | grep -qF "$PR_BODY_FENCE_END"; then
    # fence 안만 교체 — awk로 begin..end 구간을 새 body로 대체.
    # 멀티라인 PR_BODY는 awk -v로 전달 시 POSIX 비보장(BSD/일부 mawk에서 첫 개행 잘림)이므로
    # ENVIRON 경유로 이식성 보장.
    new_body=$(printf '%s' "$existing_body" | PR_BODY_ENV="$PR_BODY" awk -v b="$PR_BODY_FENCE_BEGIN" -v e="$PR_BODY_FENCE_END" '
      BEGIN { in_fence = 0; new = ENVIRON["PR_BODY_ENV"] }
      $0 == b { in_fence = 1; print new; next }
      $0 == e { in_fence = 0; next }
      !in_fence { print }
    ')
  else
    new_body="$PR_BODY"
  fi

  if ! ( cd "$WT" && gh pr edit "$pr_number" --title "$SPEC_TITLE" --body "$new_body" ); then
    echo "ERROR: gh pr edit 실패 (PR #$pr_number)" >&2
    exit 1
  fi
  echo "PR URL: $pr_url"
  echo "PR state: open"
fi
