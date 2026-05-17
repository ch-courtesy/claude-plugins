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

# 반박 코멘트 1회 게시 가드 — PR-level dispute에 한정 (AC6 기존 동작 보존).
# 인라인 thread reply는 별도 REPLIED_THREADS_FILE로 thread 단위 dedup (SPEC 153 AC4·AC5).
DISPUTE_FILE="$WT/.iterations/review-fix-dispute-posted"

# 인라인 thread reply dedup — 본 phase 사이클 동안 같은 thread에 최대 1개 reply (AC4).
# 서로 다른 thread는 각각 reply 허용 (AC5: phase 단위 상한 없음).
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

# ----- OWNER/REPO 식별 (인라인 thread reply용 gh api URL 구성) -----
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

# ----- 새 이벤트 수집 (PR comments + review threads + review summary) -----
# 3 소스의 모든 항목 ID 화이트리스트 후 SEEN_FILE에 없는 것만 new로 분류.
# - PR-level comments: gh api repos/{owner}/{repo}/issues/{n}/comments
# - Review summaries: gh pr view --json reviews
# - Review threads (inline): gh pr view --json reviewThreads → 각 comment ID
collect_new_events() {
  # 후보 ID만 emit (mark_seen은 caller가 성공 후에 별도 호출). 본 함수는 `$()`로
  # 호출돼 stdout이 변수로 캡처되므로 여기서 mark_seen하면 caller가 fix 실패해도
  # 이미 영구히 seen 처리됨 — rebase·claude·commit 중 실패 시 재시도 불가능.
  # jq 사전 검사는 진입부에서 완료됨.
  local pr_json
  pr_json=$( cd "$WT" && gh pr view "$PR_NUMBER" --json reviews,reviewThreads,comments 2>/dev/null || echo '{}')

  # PR-level comments (issue comments)
  while IFS= read -r raw_id; do
    [[ -z "$raw_id" ]] && continue
    local id="comment:$raw_id"
    is_seen "$id" || echo "$id"
  done < <( printf '%s' "$pr_json" | jq -r '.comments[]?.id // empty' )

  # Review summary entries
  while IFS= read -r raw_id; do
    [[ -z "$raw_id" ]] && continue
    local id="review:$raw_id"
    is_seen "$id" || echo "$id"
  done < <( printf '%s' "$pr_json" | jq -r '.reviews[]?.id // empty' )

  # Review threads inline comments
  while IFS= read -r raw_id; do
    [[ -z "$raw_id" ]] && continue
    local id="thread:$raw_id"
    is_seen "$id" || echo "$id"
  done < <( printf '%s' "$pr_json" | jq -r '.reviewThreads[]?.comments[]?.id // empty' )
}

# 신규 인라인 thread comments 수집 (SPEC 153 AC1·AC2·AC3·AC4).
#
# 출력: 새로운 inline thread comment마다 TSV 한 줄 — `<thread_id>\t<comment_id>\t<body>`
# (본문 내 탭/개행은 공백으로 정규화).
#
# `collect_new_events`가 emit하는 `thread:<comment_id>` 라인(SEEN_FILE dedup용)과
# 짝을 이룬다. 이 함수의 TSV는 본 phase가 (a) per-inline-comment 단위 응답 분기
# (b) thread_id 기반 reply dedup(REPLIED_THREADS_FILE) 적용에 필요한 메타데이터를
# 제공한다.
collect_new_inline_thread_comments() {
  local pr_json
  pr_json=$( cd "$WT" && gh pr view "$PR_NUMBER" --json reviewThreads 2>/dev/null || echo '{}')
  printf '%s' "$pr_json" | jq -r '
    .reviewThreads[]?
    | . as $t
    | .comments[]?
    | [
        ($t.id // ""),
        (.id // "" | tostring),
        (.body // "" | gsub("\t"; " ") | gsub("\n"; " "))
      ]
    | @tsv
  ' | while IFS=$'\t' read -r tid cid body; do
    [[ -z "$cid" ]] && continue
    local seen_id="thread:$cid"
    if ! is_seen "$seen_id"; then
      printf '%s\t%s\t%s\n' "$tid" "$cid" "$body"
    fi
  done
}

# 인라인 thread reply 게시 (SPEC 153 AC3). thread 단위 dedup(AC4) 적용.
# 성공 시 0, 실패 시 1 — caller가 다음 iter 재시도 여부 결정.
post_inline_thread_reply() {
  local tid="$1" cid="$2" body="$3"
  if [[ -z "$OWNER_REPO" ]]; then
    echo "WARN: OWNER_REPO 미식별 — 인라인 thread reply 게시 불가 (thread=$tid)" >&2
    return 1
  fi
  if is_thread_replied "$tid"; then
    echo "[review-fix-phase] thread $tid 이미 reply 게시됨 — skip (AC4 thread dedup)"
    return 0
  fi
  echo "[review-fix-phase] 인라인 thread reply 게시: thread=$tid comment=$cid"
  if ( cd "$WT" && gh api \
         --method POST \
         "repos/$OWNER_REPO/pulls/$PR_NUMBER/comments" \
         -f body="[autopilot:dispute] $body" \
         -F in_reply_to="$cid" >/dev/null 2>&1 ); then
    mark_thread_replied "$tid"
    return 0
  fi
  echo "WARN: gh api inline thread reply 실패 (thread=$tid comment=$cid) — 다음 iter 재시도" >&2
  return 1
}

# fix iter 성공 후 한 묶음으로 seen 마킹 — 실패 분기에서는 호출되지 않으므로 다음
# iter의 collect_new_events가 동일 ID를 재발견해 재시도 가능.
mark_events_seen() {
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    mark_seen "$id"
  done
}

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
  # 인라인 thread comments는 별도 TSV로도 수집 — 본 phase가 thread/comment ID와 본문을
  # 알아야 (1) per-comment 분기 verdict 해석, (2) thread 단위 reply dedup 적용이 가능.
  new_inline_tsv="$( collect_new_inline_thread_comments )"
  if [[ -z "$new_events" && -z "$new_inline_tsv" ]]; then
    sleep "$POLL_SECS"
    continue
  fi

  # 새 이벤트 요약 emit (AC6)
  echo "[review-fix-phase] 새 이벤트 감지:"
  printf '%s\n' "$new_events" | while IFS= read -r e; do
    [[ -n "$e" ]] && echo "  - $e"
  done
  if [[ -n "$new_inline_tsv" ]]; then
    echo "  inline thread comments:"
    while IFS=$'\t' read -r tid cid body; do
      [[ -z "$cid" ]] && continue
      echo "    - thread=$tid comment=$cid"
    done <<< "$new_inline_tsv"
  fi

  # (i) 재-rebase (AC7) — 실패 시 다음 iter에서 재시도 (recoverable)
  if ! bash "$SCRIPT_DIR/rebase-phase.sh" "$WT" "$BRANCH" "$PROJECT_ROOT"; then
    echo "WARN: fix iter 내 rebase 실패 — 다음 iter 시 재시도 (phase 계속)" >&2
    sleep "$POLL_SECS"
    continue
  fi

  # (ii) claude CLI fix 세션 (AC8) — 새 이벤트 본문을 stdin으로 전달.
  # SPEC 153: 인라인 thread comment는 per-comment 단위로 verdict를 요구한다 — FIX는
  # 그 코멘트가 가리키는 코드를 직접 수정, DISPUTE는 해당 inline thread 안에 reply.
  # PR-level comment·review summary는 기존 batch 'DISPUTE: ' 프로토콜 보존 (AC6).
  fix_prompt_body=$( cd "$WT" && gh pr view "$PR_NUMBER" --json comments,reviews,reviewThreads 2>/dev/null || echo "")
  claude_prompt=$(cat <<EOF
You are a fix worker for PR #$PR_NUMBER on branch '$BRANCH'.

New review events (PR-level comments + review summaries + inline thread comment ids):
$new_events

Inline thread comments (TSV: <thread_id>\t<comment_id>\t<body>):
$new_inline_tsv

Full PR comment/review JSON (for reference):
$fix_prompt_body

PROTOCOL:
  For PR-level comments and review summaries (batched, collective decision):
    - If you accept → fix the code (Edit/Write).
    - If reviewer is wrong → output a single line starting with 'DISPUTE: ' followed by
      a short dispute body (the caller will post it as ONE PR-level comment).
  For EACH inline thread comment listed above (per-comment 1:1 response):
    - If reviewer is correct → fix the referenced code AND output:
        INLINE <thread_id> <comment_id> FIX
    - If reviewer is wrong → output:
        INLINE <thread_id> <comment_id> DISPUTE <one-line dispute body>
    - Take a CONSERVATIVE stance: when uncertain whether the reviewer is right,
      prefer FIX over DISPUTE (reviewer-bot 갈등 완화).
  DO NOT push, commit, or post comments yourself.

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

  # (iv-A) PR-level DISPUTE 본문 감지 → PR 코멘트 1회 게시 (AC6 기존 동작 보존).
  # SPEC 153 AC6: PR-level comment 처리 경로는 변경 없이 보존된다 — phase당 1회 가드 유지.
  dispute_line=$( grep -m1 -E '^DISPUTE:' "$WT/$fix_log" 2>/dev/null || true )
  if [[ -n "$dispute_line" && ! -f "$DISPUTE_FILE" ]]; then
    dispute_body="${dispute_line#DISPUTE: }"
    # 반박 게시 — gh pr comment: PR-level 1개 코멘트.
    echo "[review-fix-phase] PR-level 반박 코멘트 게시 (dispute)"
    if ( cd "$WT" && gh pr comment "$PR_NUMBER" --body "[autopilot:dispute] $dispute_body" 2>&1 ); then
      touch "$DISPUTE_FILE"
    else
      # recoverable: 다음 iter에서 재시도 가능 (DISPUTE_FILE 없으므로 동일 dispute 재시도)
      echo "WARN: gh pr comment 실패 (PR-level 반박 게시) — 다음 iter 재시도 (phase 계속)" >&2
    fi
  fi

  # (iv-B) 인라인 thread comment per-comment verdict 파싱·dispatch (SPEC 153 AC1·AC3·AC4·AC5).
  # 라인 형식: `INLINE <thread_id> <comment_id> DISPUTE <body...>`
  # FIX verdict는 본 단계에서 별도 동작 없음 — 코드 변경은 (iii) commit/push가 이미 처리.
  # DISPUTE verdict는 해당 inline thread 안에 reply 1개 게시 (thread 단위 dedup).
  # phase 단위 횟수 상한 없음 — 서로 다른 thread들에 각각 reply 가능 (AC5).
  while IFS= read -r ln; do
    [[ "$ln" =~ ^INLINE[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+DISPUTE[[:space:]]+(.*)$ ]] || continue
    tid="${BASH_REMATCH[1]}"
    cid="${BASH_REMATCH[2]}"
    body="${BASH_REMATCH[3]}"
    post_inline_thread_reply "$tid" "$cid" "$body" || true
  done < "$WT/$fix_log"

  # 모든 단계 성공 — 본 iter의 new_events ID들을 seen 마킹 (실패 분기에서는 미도달)
  printf '%s\n' "$new_events" | mark_events_seen

  sleep "$POLL_SECS"
done

emit_escalation "MAX_ITER ($MAX_ITER) 도달 — 폴링 중단. 사용자 개입 필요 (PR #$PR_NUMBER)"
exit 1
