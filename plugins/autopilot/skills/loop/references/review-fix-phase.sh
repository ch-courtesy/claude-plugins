#!/usr/bin/env bash
# review-fix-phase.sh — SPEC 123 M2
#
# DONE → PR 생성·재사용이 끝난 직후 background로 띄워지는 리뷰 fix 루프.
# request_review: true opt-in일 때만 loop.sh가 호출한다.
#
# 사용:
#   bash review-fix-phase.sh <worktree> <branch> <task-id> <project-root> <pr-number>
#
# 동작 (SPEC 123 AC4·AC5·AC6·AC7·AC8·AC9·AC10·AC11·AC12·AC13·AC14·AC15·AC16):
#   1. 추상 상태 "리뷰 관련 상태" (Review) 전이 — gh project item-edit (envvar 부재 시 skip).
#   2. LOOP_REVIEW_POLL_SECS(기본 30초) 주기로 폴링:
#        a. PR state — MERGED → cleanup-phase 호출 후 종료 (auto-merge skip, AC13).
#                       CLOSED(unmerged) → 모든 후속 단계 skip 후 종료 (AC15).
#        b. reviewDecision == APPROVED → gh pr merge 시도, 성공 시 cleanup → 종료 (AC14).
#        c. owner의 코멘트 본문에 '/done' OR '합격' OR '통과' → gh pr merge → cleanup → 종료.
#        d. 신규 PR-level comments · review threads · review summary 수집:
#             - last-seen ID dedup, 없으면 sleep로 돌아감.
#             - 새 이벤트 발견 시:
#                 i.  요약 한 줄 stdout emit (AC6).
#                 ii. rebase-phase.sh 호출 (AC7).
#                 iii. claude CLI fix 세션 (AC8).
#                 iv. 코드 변경 시 commit + push (AC9).
#                 v.  세션 결과가 "DISPUTE: ..."로 시작하면 그 본문을 1개 PR 코멘트로 게시 (AC10).
#                     AC11: 이 외 어떤 GitHub 게시도 수행하지 않음.
#   3. LOOP_REVIEW_MAX_ITER 도달 시 무한 폴링 방지로 종료 (안전장치).
#   4. 어느 단계든 비-zero exit은 stdout "ESCALATION review-fix-phase: ..." emit 후 종료 (AC19).

set -euo pipefail

# ===== silent-fail 평가 (SPEC 181) — 단위 테스트 가능 =====
# 인자(8): fetch_fail pending total_checks reviews comments inline elapsed grace
# stdout(택일): ESCALATE_FETCH_FAIL | GRACE_SKIP | EMPTY_ROLLUP_SKIP | ESCALATE_STUCK | RESET_COUNTER
#
# 우선순위:
#   1) fetch_fail == 1                       → ESCALATE_FETCH_FAIL  (grace 무관 — fetch 실패는 즉시 escalate)
#   2) elapsed < grace                       → GRACE_SKIP           (PR 생성 직후 — Actions check 등록 전)
#   3) total_checks가 양의 정수가 아님       → EMPTY_ROLLUP_SKIP    (rollup 비어 있음·gh fetch 실패 등 — 정보 부족)
#   4) pending=0 + reviews/comments/inline=0 → ESCALATE_STUCK       (진짜 stuck — AC3 회귀 보존)
#   5) 그 외                                  → RESET_COUNTER       (자연 idle)
evaluate_silent_fail() {
  local last_fetch_fail="$1" pending="$2" total_checks="$3" reviews="$4" comments="$5" inline="$6" elapsed="$7" grace="$8"
  if [[ "$last_fetch_fail" == "1" ]]; then
    echo "ESCALATE_FETCH_FAIL"; return 0
  fi
  if (( elapsed < grace )); then
    echo "GRACE_SKIP"; return 0
  fi
  if ! [[ "$total_checks" =~ ^[1-9][0-9]*$ ]]; then
    echo "EMPTY_ROLLUP_SKIP"; return 0
  fi
  if [[ "$pending" == "0" && "$reviews" == "0" && "$comments" == "0" && "$inline" == "0" ]]; then
    echo "ESCALATE_STUCK"; return 0
  fi
  echo "RESET_COUNTER"
}

# ===== grace 기간 (silent-fail 조기 호출 방지) — SPEC 181 =====
# 환경변수: LOOP_REVIEW_PR_GRACE_SECS
# 기본값:  300 (5분) — GitHub Actions check 등록·큐 지연 흡수
# floor:   0  (음수 입력 시 0으로 clamp — grace=0은 grace 비활성화 동등)
GRACE_SECS="${LOOP_REVIEW_PR_GRACE_SECS:-300}"
if (( GRACE_SECS < 0 )); then
  GRACE_SECS=0
fi

# 테스트 모드 진입점: 함수만 expose 후 main 로직 skip (단위 테스트 진입점).
if [[ -n "${REVIEW_FIX_PHASE_TEST_MODE:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

WT="${1:-}"
BRANCH="${2:-}"
TASK_ID="${3:-}"
PROJECT_ROOT="${4:-}"
PR_NUMBER="${5:-}"

if [[ -z "$WT" || -z "$BRANCH" || -z "$TASK_ID" || -z "$PROJECT_ROOT" || -z "$PR_NUMBER" ]]; then
  echo "사용: $0 <worktree> <branch> <task-id> <project-root> <pr-number>" >&2
  exit 2
fi

emit_escalation() { echo "ESCALATION review-fix-phase: $*"; }
[[ -d "$WT" ]] || { emit_escalation "워크트리 없음: $WT"; exit 1; }

# jq는 SPEC 제약 절의 명시적 의존성 — collect_new_events·owner cmd 파싱이 jq에
# 직접 의존하므로 진입 시점에 사전 검사. 함수 내부 emit_escalation은 `$()` 캡처로
# stdout에 도달하지 못해 모니터링이 ESCALATION을 감지 못 함.
if ! command -v jq >/dev/null 2>&1; then
  emit_escalation "jq 미설치 — SPEC 제약 위반, phase 진입 불가"
  exit 1
fi

POLL_SECS="${LOOP_REVIEW_POLL_SECS:-30}"
MAX_ITER="${LOOP_REVIEW_MAX_ITER:-480}"   # 30초 × 480 ≈ 4시간 cutoff
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 본 phase 외 fix iter에서 claude CLI 호출 시 사용할 allowed-tools.
# caller(loop.sh)가 export한 AUTOPILOT_REVIEW_FIX_ALLOWED_TOOLS를 우선, 부재면 기본값.
# 범위 최소: gh pr 관련 / git rebase·add·commit·push / Read·Edit·Write.
ALLOWED_TOOLS_FIX="${AUTOPILOT_REVIEW_FIX_ALLOWED_TOOLS:-Bash(git add:*),Bash(git status:*),Bash(git diff:*),Bash(gh pr view:*),Bash(gh api repos/:*),Read,Edit,Write,Glob,Grep}"

# ----- 상태 전이: Review (gh project item-edit) — AC12 -----
if command -v gh >/dev/null 2>&1 \
   && [[ -n "${LOOP_PROJECT_ID:-}" && -n "${LOOP_STATUS_FIELD_ID:-}" \
         && -n "${LOOP_STATUS_REVIEW_OPTION_ID:-}" && -n "${LOOP_PROJECT_ITEM_ID:-}" ]]; then
  echo "[review-fix-phase] 상태 전이: Review (gh project item-edit)"
  gh project item-edit \
       --project-id "$LOOP_PROJECT_ID" \
       --id "$LOOP_PROJECT_ITEM_ID" \
       --field-id "$LOOP_STATUS_FIELD_ID" \
       --single-select-option-id "$LOOP_STATUS_REVIEW_OPTION_ID" >/dev/null 2>&1 \
    || echo "WARN: 상태 전이(Review) 실패 — 수동 확인 필요" >&2
else
  echo "[review-fix-phase] 상태 전이 환경변수 부재 — Review 전이 skip"
fi

# ----- last-seen ID 추적 파일 (dedup) -----
mkdir -p "$WT/.iterations" 2>/dev/null || true
SEEN_FILE="$WT/.iterations/review-fix-seen-ids"
touch "$SEEN_FILE"

is_seen() { grep -qxF "$1" "$SEEN_FILE" 2>/dev/null; }
mark_seen() { echo "$1" >> "$SEEN_FILE"; }

# 반박 코멘트 1회 게시 가드 — PR-level dispute에 한정 (SPEC 153 AC6 기존 동작 보존).
# 인라인 thread reply는 별도 REPLIED_THREADS_FILE로 thread 단위 dedup (SPEC 153 AC4·AC5).
DISPUTE_FILE="$WT/.iterations/review-fix-dispute-posted"

# 인라인 thread "응답 완료" 추적 — 본 phase 사이클 동안 같은 thread를 두 번 처리하지
# 않게 가드 (AC4). FIX(코드 변경)·DISPUTE(thread reply) 두 액션 모두 처리 직후
# `mark_thread_replied`로 기록된다 — 그렇지 않으면 다음 iter의 polling이 같은 thread를
# 다시 발견해 claude가 중복 FIX/DISPUTE를 emit할 수 있다 (불필요한 commit·reply).
# 파일명은 SPEC 153 초기 명칭 보존(과거 호환), 의미는 "responded" 확장.
# 서로 다른 thread들은 각각 처리 가능 (AC5: phase 단위 상한 없음).
REPLIED_THREADS_FILE="$WT/.iterations/review-fix-replied-threads"
touch "$REPLIED_THREADS_FILE"

is_thread_replied() { grep -qxF "$1" "$REPLIED_THREADS_FILE" 2>/dev/null; }
mark_thread_replied() { echo "$1" >> "$REPLIED_THREADS_FILE"; }

# owner cmd dedup — 매 폴링마다 동일 owner 코멘트 재처리 방지.
OWNER_CMD_SEEN_FILE="$WT/.iterations/owner-cmd-seen-ids"
touch "$OWNER_CMD_SEEN_FILE"

# auto_merge 연속 실패 카운터 (back-off + 한계 도달 시 escalation)
AUTO_MERGE_FAIL=0
AUTO_MERGE_FAIL_MAX="${LOOP_REVIEW_AUTO_MERGE_FAIL_MAX:-5}"

# ----- PR owner 식별 (owner cmd 검사용) -----
PR_OWNER=$( cd "$WT" && gh pr view "$PR_NUMBER" --json author --jq '.author.login' 2>/dev/null || echo "" )

# ----- owner/repo 식별 (인라인 thread reply용 gh api URL 구성) -----
# `repos/<owner>/<repo>/pulls/<n>/comments`에 in_reply_to=<comment-id>로 POST 시 사용.
OWNER_REPO=$( cd "$WT" && gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "" )

# ----- 종료 시 cleanup-phase 호출 헬퍼 -----
finalize_merged() {
  local reason="$1"
  echo "[review-fix-phase] PR #$PR_NUMBER $reason — cleanup-phase 호출"
  if ! bash "$SCRIPT_DIR/cleanup-phase.sh" "$WT" "$BRANCH" "$TASK_ID" "$PROJECT_ROOT"; then
    emit_escalation "cleanup-phase 실패 ($reason)"
    return 1
  fi
  return 0
}

# ----- 자동 머지 (AC14) -----
# 실패 시 caller가 retry 또는 한계 도달 escalation 결정. 본 함수 자체는 phase를
# 중단하지 않으므로 ESCALATION 토큰 emit 금지 — WARN으로만 보고 (모니터링 오경보 방지).
try_auto_merge() {
  local reason="$1"
  echo "[review-fix-phase] 자동 머지 시도: $reason"
  if ! ( cd "$WT" && gh pr merge "$PR_NUMBER" --auto --squash --delete-branch=false 2>&1 ); then
    # --auto가 안되면 즉시 머지 시도 (CI green 가정).
    if ! ( cd "$WT" && gh pr merge "$PR_NUMBER" --squash --delete-branch=false 2>&1 ); then
      echo "WARN: gh pr merge 실패 (reason=$reason) — caller가 retry 또는 한계 escalation 결정" >&2
      return 1
    fi
  fi
  return 0
}

# ----- 새 이벤트 수집 (3 소스 *독립 호출*) -----
# 3 소스의 모든 항목 ID 화이트리스트 후 SEEN_FILE에 없는 것만 new로 분류.
# 한 소스 fetch 실패가 다른 소스를 차단하지 않도록 *각각 독립 호출*. 단일
# `gh pr view --json reviews,...,comments` 묶음 호출은 일부 gh CLI 버전이
# 특정 필드(예: 과거의 inline review-thread 필드)를 지원하지 않을 때 호출
# 전체가 비-zero exit으로 실패하고 fallback이 빈 JSON으로 묻혀 silent-fail의
# 원인이 되었음.
# - PR-level issue comments         : gh api repos/{owner}/{repo}/issues/{n}/comments
# - Review summaries                : gh api repos/{owner}/{repo}/pulls/{n}/reviews
# - Review thread inline comments   : gh api repos/{owner}/{repo}/pulls/{n}/comments
# (REST endpoint로 통일해 gh CLI 버전 의존성을 최소화.)
#
# 호출 실패는 caller(폴링 루프)의 silent-fail / stuck 감지에 사용되므로
# FETCH_FAIL_FILE에 0|1 한 줄로 기록한다 — `$()` 캡처로 stdout이 변수에 묶이는
# 본 함수의 구조상 함수의 반환값을 이용해 fetch 실패를 전달할 수 없기 때문.
FETCH_FAIL_FILE="$WT/.iterations/review-fix-last-fetch-fail"
collect_new_events() {
  # 후보 ID만 emit (mark_seen은 caller가 성공 후에 별도 호출). 본 함수는 `$()`로
  # 호출돼 stdout이 변수로 캡처되므로 여기서 mark_seen하면 caller가 fix 실패해도
  # 이미 영구히 seen 처리됨 — rebase·claude·commit 중 실패 시 재시도 불가능.
  # jq 사전 검사는 진입부에서 완료됨.
  local fetch_fail=0
  local raw

  # (1) PR-level issue comments
  if raw=$( cd "$WT" && gh api "repos/{owner}/{repo}/issues/$PR_NUMBER/comments" 2>/dev/null ); then
    while IFS= read -r raw_id; do
      [[ -z "$raw_id" ]] && continue
      local id="comment:$raw_id"
      is_seen "$id" || echo "$id"
    done < <( printf '%s' "$raw" | jq -r '.[]?.id // empty' 2>/dev/null )
  else
    fetch_fail=1
  fi

  # (2) Review summary entries
  if raw=$( cd "$WT" && gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/reviews" 2>/dev/null ); then
    while IFS= read -r raw_id; do
      [[ -z "$raw_id" ]] && continue
      local id="review:$raw_id"
      is_seen "$id" || echo "$id"
    done < <( printf '%s' "$raw" | jq -r '.[]?.id // empty' 2>/dev/null )
  else
    fetch_fail=1
  fi

  # (3) Review thread inline comments — REST endpoint (gh CLI 버전 비의존)
  if raw=$( cd "$WT" && gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/comments" 2>/dev/null ); then
    while IFS= read -r raw_id; do
      [[ -z "$raw_id" ]] && continue
      local id="thread:$raw_id"
      is_seen "$id" || echo "$id"
    done < <( printf '%s' "$raw" | jq -r '.[]?.id // empty' 2>/dev/null )
  else
    fetch_fail=1
  fi

  # 이번 호출의 fetch 실패 여부 기록 — 폴링 루프가 silent-fail / stuck 감지에 사용
  if (( fetch_fail )); then
    echo 1 > "$FETCH_FAIL_FILE" 2>/dev/null || true
  else
    echo 0 > "$FETCH_FAIL_FILE" 2>/dev/null || true
  fi
}

# fix iter 성공 후 한 묶음으로 seen 마킹 — 실패 분기에서는 호출되지 않으므로 다음
# iter의 collect_new_events가 동일 ID를 재발견해 재시도 가능.
mark_events_seen() {
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    mark_seen "$id"
  done
}

# ----- silent-fail / consecutive-idle 감지 (stuck) -----
# 폴링이 연속 N회(>=3) 동안 새 이벤트 0건이면 silent-fail 패턴을 검사:
#   (i)  최근 collect_new_events 호출에서 한 소스라도 fetch 실패 — gh CLI 호환성·
#        토큰 권한·네트워크 문제로 이벤트를 못 가져왔는데 fallback이 묻혀 0건으로
#        보이는 경우 (stuck).
#   (ii) PR check 완료(pending 0) + 리뷰 0 + 코멘트 0 — 리뷰 흐름이 시작도 안 됐고
#        owner 의사 표시도 없음 (stuck).
# 위 두 조건 중 하나라도 해당하면 ESCALATION 토큰 emit 후 종료. 어디도 해당 안 되면
# 자연 idle(리뷰어 응답 대기 등)로 간주하고 카운터만 리셋해 다음 임계까지 계속
# 폴링한다 — false positive 방지. 임계 N은 envvar로 조정 가능하되 floor 3.
CONSECUTIVE_IDLE=0
CONSECUTIVE_IDLE_THRESHOLD="${LOOP_REVIEW_IDLE_THRESHOLD:-3}"
if (( CONSECUTIVE_IDLE_THRESHOLD < 3 )); then
  CONSECUTIVE_IDLE_THRESHOLD=3
fi

# ----- 메인 폴링 루프 -----
iter=0
while (( iter < MAX_ITER )); do
  iter=$((iter + 1))

  # (a) PR state 검사 — merged/closed 즉시 분기
  pr_state=$( cd "$WT" && gh pr view "$PR_NUMBER" --json state --jq '.state' 2>/dev/null || echo "")

  if [[ "$pr_state" == "MERGED" ]]; then
    # AC13: 이미 merged이면 자동 머지 skip → cleanup 진입.
    finalize_merged "merged 감지" || exit 1
    exit 0
  fi
  if [[ "$pr_state" == "CLOSED" ]]; then
    # AC15: closed(unmerged) — 모든 후속 단계 skip, 사용자 판단 대기.
    echo "[review-fix-phase] PR #$PR_NUMBER closed (unmerged) — cleanup 및 상태 전이 skip (AC15)"
    exit 0
  fi

  # (b) reviewDecision == APPROVED → 자동 머지 (연속 실패 시 linear back-off + 한계 escalation)
  review_decision=$( cd "$WT" && gh pr view "$PR_NUMBER" --json reviewDecision --jq '.reviewDecision' 2>/dev/null || echo "")
  if [[ "$review_decision" == "APPROVED" ]]; then
    if try_auto_merge "APPROVED"; then
      finalize_merged "APPROVED 후 머지" || exit 1
      exit 0
    fi
    AUTO_MERGE_FAIL=$((AUTO_MERGE_FAIL + 1))
    if (( AUTO_MERGE_FAIL >= AUTO_MERGE_FAIL_MAX )); then
      emit_escalation "auto_merge 연속 ${AUTO_MERGE_FAIL}회 실패 (한계 $AUTO_MERGE_FAIL_MAX) — 폴링 중단, 사용자 수동 머지 필요"
      exit 1
    fi
    sleep $(( POLL_SECS * AUTO_MERGE_FAIL ))   # linear back-off (CI·branch protection 정상화 대기)
    continue
  fi
  # APPROVED 외 분기 진입 시 카운터 리셋 (성공 path 복귀)
  AUTO_MERGE_FAIL=0

  # (c) owner cmd 검사: owner 코멘트 중 미본 것만 — dedup으로 재진입 차단.
  # 머지 실패 시 재시도 가능하도록 cmd-bearing 코멘트는 머지 *성공 후*에만 seen 마킹.
  # 비-cmd 코멘트는 즉시 seen 마킹 (재검사 불필요).
  if [[ -n "$PR_OWNER" ]]; then
    while IFS=$'\t' read -r oc_id oc_body; do
      [[ -z "$oc_id" ]] && continue
      grep -qxF "$oc_id" "$OWNER_CMD_SEEN_FILE" 2>/dev/null && continue
      # @tsv는 본문 내 실제 개행(`\n`)을 리터럴 두 글자 `\n`으로 이스케이프함 —
      # grep `[[:space:]]`가 이를 못 매칭하므로 실제 개행으로 복원.
      oc_body="${oc_body//\\n/$'\n'}"
      if printf '%s' "$oc_body" | grep -qE '(^|[[:space:]])(/done|합격|통과)([[:space:]]|$)'; then
        # cmd 검출 — 머지 성공 시에만 seen, 실패 시 다음 iter 재시도
        if try_auto_merge "owner cmd"; then
          echo "$oc_id" >> "$OWNER_CMD_SEEN_FILE"
          finalize_merged "owner cmd 후 머지" || exit 1
          exit 0
        fi
        # 머지 실패 — seen 마킹 보류, 다음 iter에서 try_auto_merge 재시도
      else
        # 비-cmd 코멘트 — 재검사 불필요, 즉시 seen
        echo "$oc_id" >> "$OWNER_CMD_SEEN_FILE"
      fi
    done < <( cd "$WT" && gh pr view "$PR_NUMBER" --json comments \
                --jq ".comments[]? | select(.author.login==\"$PR_OWNER\") | [.id, .body] | @tsv" 2>/dev/null )
  fi

  # (d) 신규 이벤트 수집·dispatch
  new_events="$( collect_new_events )"
  if [[ -z "$new_events" ]]; then
    CONSECUTIVE_IDLE=$((CONSECUTIVE_IDLE + 1))
    if (( CONSECUTIVE_IDLE >= CONSECUTIVE_IDLE_THRESHOLD )); then
      # silent-fail / stuck 패턴 평가 — evaluate_silent_fail에 위임 (SPEC 181).
      # 입력: fetch 실패 플래그 + rollup·활동 카운트 + PR 생성 후 경과 시간 + grace 기간.
      last_fetch_fail=$( cat "$FETCH_FAIL_FILE" 2>/dev/null || echo 0 )
      pending_checks=$( cd "$WT" && gh pr view "$PR_NUMBER" --json statusCheckRollup \
                          --jq '[.statusCheckRollup[]? | select((.status // "COMPLETED") != "COMPLETED")] | length' 2>/dev/null || echo "" )
      # SPEC 181 AC2: total_checks=0(빈 rollup)을 "체크 모두 완료"로 오판하지 않기 위해 별도 산출.
      total_checks=$( cd "$WT" && gh pr view "$PR_NUMBER" --json statusCheckRollup \
                        --jq '.statusCheckRollup | length' 2>/dev/null || echo "" )
      total_reviews=$( cd "$WT" && gh pr view "$PR_NUMBER" --json reviews --jq '.reviews | length' 2>/dev/null || echo "" )
      total_comments=$( cd "$WT" && gh pr view "$PR_NUMBER" --json comments --jq '.comments | length' 2>/dev/null || echo "" )
      # inline review thread comments는 `/pulls/{n}/comments` REST endpoint에 별도로 산다 —
      # `gh pr view --json comments`는 `/issues/{n}/comments`(PR-level conversation)만 반영하므로
      # claude-review가 inline만 게시한 케이스에서 false-positive ESCALATION을 막으려면 추가 체크.
      total_inline=$( cd "$WT" && gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/comments" --jq 'length' 2>/dev/null || echo "" )
      # PR 생성 후 경과 시간 — jq의 fromdateiso8601로 ISO 8601 → epoch 변환.
      # fetch 실패·파싱 실패 시 0 → elapsed가 매우 커져 grace 비활성화와 동등 (기존 동작으로 degrade, 안전).
      pr_created_ts=$( cd "$WT" && gh pr view "$PR_NUMBER" --json createdAt --jq '.createdAt | fromdateiso8601' 2>/dev/null || echo 0 )
      now_ts=$( date -u +%s )
      elapsed=$(( now_ts - pr_created_ts ))

      action=$(evaluate_silent_fail "$last_fetch_fail" "$pending_checks" "$total_checks" \
                                     "$total_reviews" "$total_comments" "$total_inline" \
                                     "$elapsed" "$GRACE_SECS")
      case "$action" in
        ESCALATE_FETCH_FAIL)
          emit_escalation "silent-fail 감지 (stuck): ${CONSECUTIVE_IDLE}회 연속 idle 중 이벤트 fetch 호출 실패 — 사용자 개입 필요 (PR #$PR_NUMBER)"
          exit 1
          ;;
        ESCALATE_STUCK)
          emit_escalation "silent-fail 감지 (stuck): ${CONSECUTIVE_IDLE}회 연속 idle + PR check 완료 + 리뷰·코멘트·inline·owner cmd 모두 부재 — 사용자 개입 필요 (PR #$PR_NUMBER)"
          exit 1
          ;;
        GRACE_SKIP)
          echo "[review-fix-phase] silent-fail check skip — PR 생성 후 ${elapsed}s (grace ${GRACE_SECS}s) — Actions check 등록 대기" >&2
          CONSECUTIVE_IDLE=0
          ;;
        EMPTY_ROLLUP_SKIP)
          echo "[review-fix-phase] silent-fail check skip — statusCheckRollup 비어 있음 (check 미등록 / fetch 실패) — 정보 부족, 다음 임계까지 폴링 계속" >&2
          CONSECUTIVE_IDLE=0
          ;;
        *)
          # RESET_COUNTER — 자연 idle (리뷰어 응답 대기 등) — 카운터만 리셋, 폴링 계속
          CONSECUTIVE_IDLE=0
          ;;
      esac
    fi
    sleep "$POLL_SECS"
    continue
  fi
  # 진전 (새 이벤트 감지) — idle 카운터 리셋
  CONSECUTIVE_IDLE=0

  # 새 이벤트 요약 emit (AC6)
  echo "[review-fix-phase] 새 이벤트 감지:"
  printf '%s\n' "$new_events" | while IFS= read -r e; do
    [[ -n "$e" ]] && echo "  - $e"
  done

  # (i) 재-rebase (AC7) — 실패 시 다음 iter에서 재시도 (recoverable)
  if ! bash "$SCRIPT_DIR/rebase-phase.sh" "$WT" "$BRANCH" "$PROJECT_ROOT"; then
    echo "WARN: fix iter 내 rebase 실패 — 다음 iter 시 재시도 (phase 계속)" >&2
    sleep "$POLL_SECS"
    continue
  fi

  # (ii) claude CLI fix 세션 (AC8) — 새 이벤트 본문을 stdin으로 전달
  # PR header(comments + reviews)와 review thread inline 코멘트를 분리 fetch —
  # 단일 `--json` 묶음 호출에 thread 필드를 포함시키면 gh CLI 버전에 따라
  # silent-fail 가능. 호출 실패 시 fallback은 의도적으로 "{}" / "[]"로 유지
  # (collect_new_events의 FETCH_FAIL_FILE이 silent-fail 감지를 책임지므로,
  # 본 위치에서 또 한번 escalation을 emit하면 중복·잡음).
  fix_prompt_header=$( cd "$WT" && gh pr view "$PR_NUMBER" --json comments,reviews 2>/dev/null || echo "{}" )
  fix_prompt_threads=$( cd "$WT" && gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/comments" 2>/dev/null || echo "[]" )
  fix_prompt_body=$(printf 'PR comments + reviews:\n%s\n\nReview thread inline comments:\n%s\n' "$fix_prompt_header" "$fix_prompt_threads")
  # Inline thread roots (in_reply_to_id == null) — 각 root이 INLINE per-thread 응답 1건의 대상.
  # SPEC 153에서 thread_id == comment_id (root.id). (iv-A) 파서가 INLINE 라인을 읽으므로
  # 본 변수를 프롬프트에 명시 주입해 dead-code 갭을 차단.
  # 이미 처리된 thread는 REPLIED_THREADS_FILE 기준으로 사전 제외 — (iv-A) dedup이
  # 후처리만 막을 뿐 claude의 edit·comment 자체는 이미 수행되므로, 프롬프트 진입 전에
  # 차단해야 불필요한 file edit·oscillation을 막을 수 있다.
  replied_threads_json='[]'
  if [[ -s "$REPLIED_THREADS_FILE" ]]; then
    replied_threads_json=$(jq -R -s -c 'split("\n") | map(select(length > 0))' < "$REPLIED_THREADS_FILE" 2>/dev/null || echo '[]')
  fi
  fix_prompt_inline_threads=$(printf '%s' "$fix_prompt_threads" | jq -r --argjson replied "$replied_threads_json" '
    [.[]?
      | select(.in_reply_to_id == null)
      | select((.id | tostring) as $sid | $replied | index($sid) | not)
    ]
    | if length == 0 then "(no active inline review threads)"
      else map("- thread_id=\(.id) path=\(.path // ""):\(.line // 0) body=\((.body // "") | gsub("\n"; " ") | gsub("\t"; " ") | .[0:240])") | join("\n")
      end
  ' 2>/dev/null || echo "(inline thread parse failed)")
  claude_prompt=$(cat <<EOF
You are a fix worker for PR #$PR_NUMBER on branch '$BRANCH'.
New review events:
$new_events

Full PR comment/review context (for reference):
$fix_prompt_body

Active inline review threads requiring per-thread response (SPEC 153):
$fix_prompt_inline_threads

Goal:
  PR-level comments and review summaries (batched, collective verdict):
    - If reviewer is correct → fix the code (Edit/Write).
    - If reviewer is wrong → emit a single line: 'DISPUTE: <one-line dispute body>'
      (the caller posts it as ONE PR-level comment — AC6 보존).

  EACH active inline review thread listed above (per-thread 1:1 response, SPEC 153 AC1·AC2·AC3):
    - If reviewer is correct → fix the referenced code, then emit ONE line:
        INLINE <thread_id> <thread_id> FIX
      AC2 fallback: 코드 변경 시도가 실패(빌드/테스트 실패·구문 오류 등)할 경우
      해당 thread에 대해 INLINE <thread_id> <thread_id> DISPUTE <one-line 실패 사유>로
      전환해 응답한다 (FIX → reply 자동 fallback, AC1 "정확히 하나" 보장 유지).
    - If reviewer is wrong → emit ONE line:
        INLINE <thread_id> <thread_id> DISPUTE <one-line dispute body>
    - 보수적 판정 (SPEC §제약 요건): 타당성이 불확실하면 FIX 분기로 결정한다
      (DISPUTE 남발 방지·reviewer-bot 갈등 완화).
    - The INLINE line format depends on action:
        FIX:     INLINE <thread_id> <comment_id> FIX                       (4 tokens, no body)
        DISPUTE: INLINE <thread_id> <comment_id> DISPUTE <body...>         (5 tokens, body required)
      Whitespace-separated. SPEC 153에서 thread_id와 comment_id는 같은 정수
      (root comment DB id). FIX 라인에 본문이 붙어도 파서는 skip하므로 기능 영향
      없지만, 형식 일관성을 위해 FIX는 4토큰만 출력한다.

  DO NOT push, commit, or create PRs yourself. DO NOT post comments yourself.

After working, output 'DONE' on the last line.
EOF
)

  cd "$WT"
  fix_log=".iterations/review-fix-iter-$iter.log"
  if ! printf '%s' "$claude_prompt" | claude \
        --print \
        --no-session-persistence \
        --add-dir . \
        --allowed-tools "$ALLOWED_TOOLS_FIX" \
        --output-format text > "$fix_log" 2>&1; then
    # recoverable: 다음 iter에서 재시도
    echo "WARN: claude fix 세션 실패 (iter $iter) — 다음 iter 재시도 (phase 계속)" >&2
    sleep "$POLL_SECS"
    cd "$PROJECT_ROOT"
    continue
  fi
  cd "$PROJECT_ROOT"

  # (iii) 코드 변경 있으면 commit + push (AC9)
  # `git diff --quiet`는 unstaged 변경만 검사하므로 staged-only 변경을 놓친다.
  # `git status --porcelain --untracked-files=no`로 staged+unstaged 모두 검사.
  # untracked 파일은 fix iter 산출로 간주하지 않음 (claude가 의도 외 파일 생성 시 commit에서 제외).
  if [[ -n "$( cd "$WT" && git status --porcelain --untracked-files=no 2>/dev/null )" ]]; then
    ( cd "$WT" \
        && git add -u \
        && git commit -q -m "fix(review-fix): iter $iter (PR #$PR_NUMBER)" \
        && git push origin "$BRANCH" ) \
      || { echo "WARN: fix commit/push 실패 (iter $iter) — 다음 iter 재시도 (phase 계속)" >&2; sleep "$POLL_SECS"; continue; }
  fi

  # (iv-A) INLINE per-comment thread reply POST (SPEC 153 AC1·AC3·AC4·AC5)
  # claude 출력에서 `INLINE <thread_id> <comment_id> <action> <body...>` 라인을 파싱.
  # action == DISPUTE 인 경우 해당 inline thread에 reply 1개 POST. thread_id 기준 dedup으로
  # 같은 phase 사이클 동안 같은 thread는 최대 1 reply (AC4). 서로 다른 thread들은 각각 reply 가능 (AC5).
  # action == FIX는 claude가 이미 코드 변경을 적용했음을 의미 — 위 (iii) commit/push 경로가 처리.
  # PR-level dispute(DISPUTE: ...) 본문은 본 블록과 무관, 아래 (iv-B)가 처리 — AC6 기존 동작 보존.
  #
  # 구조: INLINE 파서·dedup 마킹은 OWNER_REPO 유무와 무관하게 항상 수행한다 —
  # FIX 액션도 dedup이 필요하므로(다음 iter 중복 commit 방지) OWNER_REPO 미식별 시에도
  # 마킹은 진행되어야 한다. DISPUTE 분기의 gh api POST만 OWNER_REPO 가드로 보호.
  if [[ -z "$OWNER_REPO" ]] && grep -qE '^INLINE[[:space:]]' "$WT/$fix_log" 2>/dev/null; then
    echo "WARN: OWNER_REPO 미식별 — DISPUTE inline reply POST skip (FIX dedup은 계속 적용)" >&2
  fi
  while IFS= read -r inline_line; do
    [[ -z "$inline_line" ]] && continue
    # 토큰 분리: INLINE <thread_id> <comment_id> <action> <body...>
    # 마지막 변수가 나머지 토큰을 모두 흡수 (body 내 공백 보존).
    # `_comment_id` (underscore prefix): 디버그 로그 전용 — `in_reply_to`에는 항상
    # `$thread_id`를 사용 (thread root에 reply, AC3). 케이스 (c)처럼 두 값이 다를 수 있어도
    # reply 대상은 root이므로 `_comment_id`는 in_reply_to 인자로 쓰이지 않는다.
    read -r _tag thread_id _comment_id action inline_body <<<"$inline_line"
    [[ "$_tag" != "INLINE" ]] && continue
    [[ "$action" != "DISPUTE" && "$action" != "FIX" ]] && continue
    [[ -z "$thread_id" ]] && continue
    # 방어: thread_id가 정수가 아니면 skip — `gh api -F in_reply_to=<int>` REST 요구사항.
    # 비-수치값이 흘러들면 422를 받으므로 사전 차단(claude 출력 형식 위반 케이스 격리).
    if ! [[ "$thread_id" =~ ^[0-9]+$ ]]; then
      echo "WARN: INLINE thread_id 비-수치 ('$thread_id') — skip (in_reply_to 정수 요구)" >&2
      continue
    fi
    if is_thread_replied "$thread_id"; then
      continue   # AC4: 같은 thread 동일 phase 사이클 내 중복 처리 차단 (FIX·DISPUTE 공통)
    fi
    # FIX 액션: 코드 변경은 (iii)에서 이미 commit·push 완료. 본 분기는 dedup 마킹만.
    # 마킹하지 않으면 다음 polling iter에서 같은 thread가 fix_prompt_inline_threads에
    # 그대로 다시 포함돼 claude가 중복 FIX를 emit할 수 있다 (불필요한 commit·oscillation).
    # OWNER_REPO 유무와 무관 — gh api 호출 없음.
    if [[ "$action" == "FIX" ]]; then
      mark_thread_replied "$thread_id"
      continue
    fi
    # 이하 DISPUTE 분기 — inline thread에 reply 1개 POST. OWNER_REPO 필수.
    if [[ -z "$OWNER_REPO" ]]; then
      # OWNER_REPO는 phase 진입 시 1회 식별되므로 비어 있으면 phase 전체에서 비어 있다.
      # POST 불가 + 매 iter 재평가(oscillation) 차단을 위해 dedup만 마킹한다.
      # dispute는 사실상 lost — 사용자 수동 처리 필요 (상단 WARN 메시지 참조).
      mark_thread_replied "$thread_id"
      continue
    fi
    [[ -z "$inline_body" ]] && inline_body="(no body)"
    echo "[review-fix-phase] inline reply POST: thread $thread_id (comment $_comment_id)"
    # `--method POST`를 URL 앞에 두어 호출 로그가 `--method POST repos/.../pulls/N/comments`
    # 순서를 보장 (mock·실CI 양쪽 grep 패턴 호환).
    # `-F`(typed)로 in_reply_to를 정수 전송 — REST API는 정수 필드를 요구하므로
    # `-f`(JSON string)를 쓰면 422를 받는다. body는 그대로 문자열이라 `-f` 사용.
    if ( cd "$WT" && gh api \
            --method POST \
            "repos/$OWNER_REPO/pulls/$PR_NUMBER/comments" \
            -F "in_reply_to=$thread_id" \
            -f "body=[autopilot:dispute] $inline_body" >/dev/null 2>&1 ); then
      mark_thread_replied "$thread_id"
    else
      # recoverable: 다음 iter에서 재시도 가능 (mark_thread_replied 미호출이므로 동일 thread 재시도)
      echo "WARN: inline reply POST 실패 (thread $thread_id) — 다음 iter 재시도 (phase 계속)" >&2
    fi
  done < <( grep -E '^INLINE[[:space:]]' "$WT/$fix_log" 2>/dev/null || true )

  # (iv-B) PR-level DISPUTE 본문 감지 → PR 코멘트 1회 게시 (AC10·AC11 — SPEC 123 기존 경로)
  # `DISPUTE: <body>` 라인은 PR-level 의견 — gh pr comment 경로 (AC6 보존).
  # INLINE 라인은 본 블록 패턴(^DISPUTE:)에 일치하지 않으므로 영향 없음.
  dispute_line=$( grep -m1 -E '^DISPUTE:' "$WT/$fix_log" 2>/dev/null || true )
  if [[ -n "$dispute_line" && ! -f "$DISPUTE_FILE" ]]; then
    dispute_body="${dispute_line#DISPUTE: }"
    # 반박 게시 — gh pr comment (AC10): 1개 코멘트만.
    echo "[review-fix-phase] 반박 코멘트 게시 (dispute)"
    if ( cd "$WT" && gh pr comment "$PR_NUMBER" --body "[autopilot:dispute] $dispute_body" 2>&1 ); then
      touch "$DISPUTE_FILE"
    else
      # recoverable: 다음 iter에서 재시도 가능 (DISPUTE_FILE 없으므로 동일 dispute 재시도)
      echo "WARN: gh pr comment 실패 (반박 게시) — 다음 iter 재시도 (phase 계속)" >&2
    fi
  fi

  # 모든 단계 성공 — 본 iter의 new_events ID들을 seen 마킹 (실패 분기에서는 미도달)
  printf '%s\n' "$new_events" | mark_events_seen

  sleep "$POLL_SECS"
done

emit_escalation "MAX_ITER ($MAX_ITER) 도달 — 폴링 중단. 사용자 개입 필요 (PR #$PR_NUMBER)"
exit 1
