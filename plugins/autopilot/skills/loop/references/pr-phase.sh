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

# ----- base branch rebase (SPEC 103 M2/AC3·M3/AC4) -----
# PR 생성 직전에 origin/<base>로부터 fetch + rebase를 수행해 base 최신 변경분을 흡수한다.
# fast-forward(또는 동일 history)면 no-op으로 통과한다. 첫 평범한 rebase가 실패하면(충돌
# 가능성 — 본 단계 외 환경 오류도 포함될 수 있음) `-X theirs` 전략으로 정확히 1회만 재시도한다
# (M3/AC4 휴리스틱: feat 브랜치의 변경을 base 위에 우선 적용). 재시도도 실패하면 워크트리를
# `git rebase --abort`로 복구하고 명시적 사용자 알림 + non-zero exit (보수적 좌절).
# 1회 제한은 분기를 한 갈래만 두어 코드로 강제한다 — counter 변수 불필요.
echo "[pr-phase] origin/$DEFAULT_BRANCH fetch"
if ! ( cd "$WT" && git fetch origin "$DEFAULT_BRANCH" 2>&1 ); then
  echo "ERROR: git fetch origin $DEFAULT_BRANCH 실패" >&2
  exit 1
fi

echo "[pr-phase] origin/$DEFAULT_BRANCH rebase"
if ! ( cd "$WT" && git rebase "origin/$DEFAULT_BRANCH" 2>&1 ); then
  echo "[pr-phase] rebase 실패 감지 — 충돌 1회 자동 해결 시도 (-X theirs)"
  ( cd "$WT" && git rebase --abort 2>/dev/null || true )
  if ! ( cd "$WT" && git rebase -X theirs "origin/$DEFAULT_BRANCH" 2>&1 ); then
    ( cd "$WT" && git rebase --abort 2>/dev/null || true )
    echo "ERROR: rebase 충돌 자동 해결 실패 (1회 시도 후 좌절). 워크트리는 'git rebase --abort'로 복구됨 — 사용자 수동 해결 후 재시도하세요." >&2
    exit 1
  fi
  echo "[pr-phase] rebase 충돌 자동 해결 성공 (-X theirs)"
fi

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

  # 기존 body 가져오기 (fence 안만 교체하려면 필요).
  # PR 존재는 이미 확인됐으므로 view 실패는 환경 오류(권한·네트워크 등). 실패를 삼키면
  # existing_body가 빈 값이 되어 fence 검사 통과 못하고 new_body="$PR_BODY" 전면 재작성으로
  # 떨어져 사용자 수기 편집이 무음 소실됨 — 사용자 수기 보호 목표 위반. 즉시 abort.
  if ! existing_body=$( cd "$WT" && gh pr view "$pr_number" --json body --jq '.body' ); then
    echo "ERROR: gh pr view 실패 (PR #$pr_number) — 사용자 수기 body 보호 불가, abort" >&2
    exit 1
  fi

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

# ----- Monitor: stuck PR check 재트리거 (SPEC 103 M4/AC5) -----
# PR 생성·갱신 직후 같은 셸에서 동기적으로 PR check 상태를 polling한다.
# "stuck" 패턴 = (1) PR state OPEN + (2) reviewDecision 없음 (리뷰 미발생) +
#                (3) check가 모두 완료(COMPLETED state)된 상태.
# stuck 감지 시 `gh pr checks <num> --rerun`을 호출. 최대 3회 재트리거, 상한 도달 시
# 사용자 알림(stderr) + loop 정상 종료(상한은 에러가 아닌 경고).
# bounded loop으로 무한 루프 위험을 코드로 차단 — counter 외 추가 안전장치 불필요.

# PR number 추출 — 기존 PR 분기에선 pr_number 이미 set, 새 PR은 pr_url에서 추출
monitor_pr_number="${pr_number:-}"
if [[ -z "$monitor_pr_number" && -n "${pr_url:-}" ]]; then
  monitor_pr_number=$(printf '%s' "$pr_url" | sed -nE 's|.*/pull/([0-9]+).*|\1|p')
fi

if [[ -z "$monitor_pr_number" ]]; then
  echo "[pr-phase] PR number 추출 실패 — Monitor 단계 건너뜀" >&2
else
  echo "[pr-phase] Monitor 진입 (stuck check 재트리거 ≤3회, PR #$monitor_pr_number)"
  MAX_RERUN_ATTEMPTS=3
  rerun_attempts=0
  while (( rerun_attempts < MAX_RERUN_ATTEMPTS )); do
    # (1) PR state — MERGED/CLOSED면 monitor 종료 (review·done 단계 진입)
    monitor_pr_state=$( cd "$WT" && gh pr view "$monitor_pr_number" --json state --jq '.state' 2>/dev/null || printf '' )
    if [[ "$monitor_pr_state" == "MERGED" || "$monitor_pr_state" == "CLOSED" ]]; then
      echo "[pr-phase] PR 상태=$monitor_pr_state — Monitor 종료 (lifecycle 완료 단계)"
      # SPEC 103 M5/AC6: cleanup 후보 안내. 자동 삭제는 하지 않으며 사용자 명시 승인 필요.
      # 셸 드라이버는 안내만 출력하고, 실제 cleanup은 사용자가 'loop.sh cleanup <task-id>'를
      # 명시 호출하거나 SKILL 계층에서 AskUserQuestion 승인을 거친 뒤에만 수행한다.
      echo "[pr-phase] cleanup 후보: PR #$monitor_pr_number 가 $monitor_pr_state 상태 — worktree·feat 브랜치 정리 가능."
      echo "[pr-phase] 자동 삭제하지 않습니다 (AC6). 명시 승인 후 'loop.sh cleanup <task-id>'로 수동 정리하세요."
      break
    fi

    # (2) reviewDecision이 set이면 리뷰 활동 발생 → stuck 아님, monitor 종료
    monitor_review_decision=$( cd "$WT" && gh pr view "$monitor_pr_number" --json reviewDecision --jq '.reviewDecision' 2>/dev/null || printf '' )
    if [[ -n "$monitor_review_decision" && "$monitor_review_decision" != "null" ]]; then
      echo "[pr-phase] reviewDecision=$monitor_review_decision — Monitor 종료 (리뷰 진행)"
      break
    fi

    # (3) check 상태 조회
    monitor_checks_json=$( cd "$WT" && gh pr checks "$monitor_pr_number" --json state,conclusion 2>/dev/null || printf '' )
    if [[ -z "$monitor_checks_json" || "$monitor_checks_json" == "[]" ]]; then
      # check 정보 없음 — 실행 안 시작·집계 비었음 → stuck 아님 → monitor 종료
      echo "[pr-phase] check 정보 없음 — Monitor 종료"
      break
    fi
    # stuck 후보: 모든 check가 COMPLETED 상태일 때만. 비완료(WAITING/PENDING/IN_PROGRESS/
    # QUEUED/RUNNING 등 GitHub가 향후 추가할 모든 상태 포함)가 하나라도 있으면 stuck 아님.
    # 화이트리스트(진행 상태 목록) 대신 블랙리스트(완료 상태만 stuck 후보)로 판정해
    # GitHub API가 새 상태값을 추가해도 false-positive halt가 안 생기게 한다.
    if printf '%s' "$monitor_checks_json" | grep -oE '"state"[[:space:]]*:[[:space:]]*"[A-Z_]+"' | grep -qv 'COMPLETED'; then
      # 진행 중 check가 있으면 아직 stuck 아님 → monitor 종료
      echo "[pr-phase] check 진행 중 — Monitor 종료 (stuck 아님)"
      break
    fi

    # (1)+(2)+(3) 모두 충족 → stuck 감지, 재트리거
    rerun_attempts=$((rerun_attempts + 1))
    echo "[pr-phase] PR check stuck 감지 — 재트리거 시도 ${rerun_attempts}/${MAX_RERUN_ATTEMPTS}"
    if ! ( cd "$WT" && gh pr checks "$monitor_pr_number" --rerun 2>&1 ); then
      echo "[pr-phase] gh pr checks --rerun 실패 — Monitor 중단" >&2
      break
    fi
    # GitHub check 상태가 COMPLETED → QUEUED/IN_PROGRESS로 flip 되는 데 수초~수십초.
    # sleep 없이 즉시 재조회하면 여전히 COMPLETED로 보여 동일 stuck으로 재판정되고
    # 3회 상한이 수초 내에 모두 소진된다 — 상한이 실질적 재시도를 보장하지 못함.
    # 기본 10초 대기, 테스트는 LOOP_PR_RERUN_SLEEP_SECONDS=0으로 즉시 진행.
    # 상한 도달 시엔 다음 iteration이 없으므로 sleep 자체를 건너뛴다 (불필요한 10초 낭비 차단).
    (( rerun_attempts < MAX_RERUN_ATTEMPTS )) && sleep "${LOOP_PR_RERUN_SLEEP_SECONDS:-10}"
  done

  if (( rerun_attempts >= MAX_RERUN_ATTEMPTS )); then
    echo "WARN: PR check 재트리거 상한 도달 (${MAX_RERUN_ATTEMPTS}회) — 사용자 개입 필요 (PR #$monitor_pr_number)" >&2
  fi
fi
