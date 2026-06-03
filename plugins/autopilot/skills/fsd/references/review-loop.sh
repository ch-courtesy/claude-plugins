#!/usr/bin/env bash
# review-loop.sh — autopilot:fsd 리뷰 오케스트레이션 (C3)
#
# 책임 (비전 핵심: "리뷰 상태 task 는 판정을 받아 같은 PR 브랜치에 구현·푸시해 해결하고,
# 승인까지 반복한다"):
#   - 판정 산출: autopilot:review 생산자(REVIEW_PRODUCE_CMD)를 한 작업에 대해 **1회** 호출해
#     단일 머신리더블 판정(pipeline_verdict: approve|request_changes|unavailable)과 분류된
#     재작업 브리프(rework_brief: must_adopt/defer/wont_adopt)를 받는다. 봇 리뷰 fetch·로컬
#     채택 분류는 이제 생산자가 소유한다(이 모듈은 분류 결과를 소비만 한다).
#   - 포지 사람/head 게이트(보존): 열린 승인 요청의 최신 정식 리뷰가 **사람** 리뷰어의 변경
#     요청이면 자동수정하지 않고 사람에게 에스컬레이션한다. 대상 head 가 직전 처리분과 같으면
#     새 커밋이 없으니 멱등 no-op(생산자를 호출하지 않는다).
#   - 판정 분기:
#       request_changes → must_adopt 를 SPEC 델타로 만들어 task 본문 재동기화 후 head 브랜치
#         위에서 자율 실행기로 구현하고 같은 head 브랜치로 push(새 승인 요청 미생성, force 금지).
#         리뷰 라운드 카운터를 증가시킨다. defer 지적은 별도 백로그 task 로 분리(현 PR 미혼합).
#       approve         → 머지 진행가능 상태로 전이(state=review-approved), 추가 라운드 미시작.
#       unavailable     → 사람에게 에스컬레이션(승인 요청 Review 유지).
#   - 무한루프 가드(세 겹): 라운드 수 상한(기본 3) 초과 → 중지·에스컬레이션. must_adopt 가
#     0인데도 여전히 request_changes 면(무진전) 에스컬레이션. 차단성(must_adopt) 집합이 직전
#     라운드와 동일하면(핑퐁) 에스컬레이션. 수렴 반복은 poll 드레인이 소유(한 호출=한 라운드).
#
# 이 모듈은 규칙의 실행자다(규칙 재정의 금지):
#   - rules/review.md           리뷰 원칙(재리뷰=재확인)
#   - rules/change-adoption.md  반드시 반영 / 후속 분리 / 반영 불필요 결정 프레임(생산자가 적용)
#
# 차용(정의하지 않고 호출만):
#   - autopilot:review   review.sh run --task <id> (판정·재작업 브리프 생산)
#   - C1 task-backend.sh : tb_create_task / tb_sync_body / tb_comment
#   - C2 forge.sh        : work_branch / push_branch (PR 신규 생성 안 함)
#   - C0 lib-state.sh    : review_round / bump_review_round / set_head·get_head / set_state / log_event
#
# 불변식:
#   - force(강제) push 금지 (어떤 경로에서도).
#   - 새 승인 요청을 만들지 않는다(같은 head 브랜치 갱신만).
#   - self-referential: 검증은 mock 인터페이스로만 하며 runtime artifact(실제 PR·브랜치)를
#     직접 검사하지 않는다(`bash review-loop.sh selftest`).
#
# 모든 외부 인터페이스(리뷰 생산자·포지 리뷰 메타·자율 실행기·git·forge·backend)는 주입 가능한
# 명령 변수로 두어 mock 으로 독립 검증한다. bash 3.2+ 호환 (associative array 미사용).

set -uo pipefail

RL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 의존 모듈 로드(C0/C1/C2). 이미 source 되어 있으면 재로드하지 않는다.
if ! declare -f set_field >/dev/null 2>&1; then
  # shellcheck source=lib-state.sh
  . "$RL_SCRIPT_DIR/lib-state.sh"
fi
if ! declare -f tb_set_status >/dev/null 2>&1; then
  # shellcheck source=task-backend.sh
  . "$RL_SCRIPT_DIR/task-backend.sh"
fi
if ! declare -f push_branch >/dev/null 2>&1; then
  # shellcheck source=forge.sh
  . "$RL_SCRIPT_DIR/forge.sh"
fi
# forge.sh 는 `set -e` 를 켠다. 본 모듈은 의도적으로 -e 없이(반환코드 직접 처리) 돌므로
# 의존 로드 후 -e 를 끄고 -u·pipefail 만 유지한다(반환코드 기반 분기를 보존).
set +e
set -uo pipefail

# ===== 설정 (주입 가능) =====
# 라운드 수 상한. 사용자 확정 결정: 봇 리뷰만, 3라운드 캡.
REVIEW_ROUNDS_MAX="${REVIEW_ROUNDS_MAX:-3}"

# 자동 리뷰 봇 식별 정규식(사람 리뷰어와 구분). 기본: 봇 계정 관용 패턴.
REVIEW_BOT_LOGIN_RE="${REVIEW_BOT_LOGIN_RE:-(\[bot\]$|claude|github-actions)}"

# 외부 인터페이스 — mock 으로 치환 가능.
#   REVIEW_FETCH_CMD <pr>   : 최신 정식 리뷰 메타데이터를 key: value 줄로 출력
#                             (state:, author:, head: 최소 3줄). **사람 리뷰어 변경요청
#                             판정·head 신선도** 게이트에만 쓴다(판정의 단일 출처 아님).
#   REVIEW_PRODUCE_CMD <task>: autopilot:review 생산자를 호출해 단일 머신리더블 판정 JSON
#                             (pipeline_verdict·rework_brief·reviewed_context)을 stdout 으로.
#                             이 판정이 approve/request_changes/unavailable 분기의 단일 출처.
#   IMPLEMENT_CMD <spec> <branch> : head 브랜치 위에서 SPEC 델타를 자율 구현.
REVIEW_FETCH_CMD="${REVIEW_FETCH_CMD:-rl_review_fetch_gh}"
REVIEW_PRODUCE_CMD="${REVIEW_PRODUCE_CMD:-rl_produce_review_skill}"
IMPLEMENT_CMD="${IMPLEMENT_CMD:-rl_implement_loop}"

rl_die() { echo "review-loop: $*" >&2; return 1; }

# ===== 기본(gh/생산자) 구현 — self-referential 검증은 mock 으로, 이 경로 미호출 =====
rl_review_fetch_gh() {
  local pr="$1"
  command -v gh >/dev/null 2>&1 || { rl_die "gh CLI 필요"; return 1; }
  # 최신 정식 리뷰(가장 마지막 제출분)의 상태·작성자·대상 커밋.
  gh pr view "$pr" --json reviews,headRefOid --jq '
    (.reviews | map(select(.state=="CHANGES_REQUESTED" or .state=="APPROVED" or .state=="COMMENTED")) | last) as $r
    | "state: \($r.state // "NONE")\nauthor: \($r.author.login // "")\nhead: \(.headRefOid // "")"
  ' 2>/dev/null
}

# REVIEW_PRODUCE_CMD 기본: 형제 autopilot:review 생산자 스킬을 한 작업에 대해 1회 호출.
#   생산자가 diff·SPEC 수용기준·기존 스레드를 모아 다관점 리뷰 후 단일 판정 JSON 을 낸다.
rl_produce_review_skill() {
  local task="$1"
  bash "$RL_SCRIPT_DIR/../../review/references/review.sh" run --task "$task"
}

# IMPLEMENT_CMD 기본: 자율 실행기(loop)에 SPEC 델타를 위임. head 브랜치 위에서 구현.
rl_implement_loop() {
  local spec="$1" branch="$2"
  # shellcheck disable=SC2086
  ${LOOP_CMD:-true} start "$spec" --branch "$branch" >/dev/null 2>&1
}

# ===== 리뷰 메타데이터 파싱 =====
rl_review_field() {
  # rl_review_field <pr> <key>
  # shellcheck disable=SC2086
  $REVIEW_FETCH_CMD "$1" 2>/dev/null \
    | grep -i -m1 "^$2:" \
    | sed -E "s/^[^:]*:[[:space:]]*//"
}

rl_review_state()  { rl_review_field "$1" state; }
rl_review_author() { rl_review_field "$1" author; }
rl_review_head()   { rl_review_field "$1" head; }

# rl_is_change_request <state> — request_changes / CHANGES_REQUESTED 면 0.
#   상태 어휘를 소문자로 정규화해 두 표기(request_changes·changes_requested)를 모두 받는다.
rl_is_change_request() {
  local s
  s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$s" in
    request_changes|changes_requested) return 0 ;;
    *) return 1 ;;
  esac
}

# rl_is_bot <author> — 자동 리뷰 봇이면 0, 사람이면 1.
rl_is_bot() {
  printf '%s' "$1" | grep -qiE "$REVIEW_BOT_LOGIN_RE"
}

# ===== 채택 분류 =====
# 채택 분류(반드시 반영/후속/반영 불필요)와 안전경계 고정은 이제 autopilot:review 생산자가
# rules/change-adoption.md 를 단일 출처로 수행한다(rework_brief.must_adopt/defer/wont_adopt).
# review-loop 는 생산자의 분류 결과를 소비하기만 하고 재분류하지 않는다(정의 표류 방지).
#
# rl_produce_extract <produce-json> <key> <outfile> — rework_brief.<key> 항목을
#   "<title> — <body>" 한 줄씩 outfile 로 평탄화(SPEC 델타·백로그 분리 입력).
rl_produce_extract() {
  local json="$1" key="$2" out="$3"
  : > "$out"
  printf '%s' "$json" \
    | jq -r --arg k "$key" '(.rework_brief[$k] // [])[]
        | ((.title // "") + (if (.body // "") != "" then " — " + .body else "" end))' \
        2>/dev/null >> "$out" || true
}

# rl_blocking_hash <mustfile> — 차단성(must_reflect) 지적 집합의 안정 해시(핑퐁 탐지용).
#   순서 무관하게 같은 집합이면 같은 값. 해시 도구가 없으면 정렬 본문으로 대체.
rl_blocking_hash() {
  local f="$1"
  [[ -s "$f" ]] || { echo "EMPTY"; return 0; }
  if command -v sha1sum >/dev/null 2>&1; then
    LC_ALL=C sort "$f" | sha1sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    LC_ALL=C sort "$f" | shasum | awk '{print $1}'
  else
    LC_ALL=C sort "$f" | cksum | tr -d ' '
  fi
}

# ===== 에스컬레이션 — 사람 인계. 승인 요청은 Review 상태로 유지(Blocked 전이 금지). =====
# rl_escalate <task-id> <reason>
rl_escalate() {
  local id="$1" reason="$2"
  log_event "$id" "에스컬레이션(handoff): $reason — 승인 요청 Review 유지"
  tb_comment "$id" handoff "리뷰 자동수정 루프 에스컬레이션: $reason" 2>/dev/null || true
  echo "escalate: $reason"
}

# ===== 후속 분리 — defer 지적을 별도 백로그 task 로 (현 PR 에 미혼합) =====
# rl_spinoff_backlog <task-id> <pr> <deferfile> — defer 지적마다 백로그 task 분리.
rl_spinoff_backlog() {
  local id="$1" pr="$2" deferfile="$3"
  [[ -s "$deferfile" ]] || return 0
  local td spec n=0 line text
  td="$(task_dir "$id")"; ensure_task_dir "$id"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n=$((n+1))
    text="${line#*	}"
    spec="$td/.backlog-$pr-$n.spec.md"
    {
      printf '# 후속: 리뷰 지적 분리 (PR %s #%s)\n\n' "$pr" "$n"
      printf '## 무엇을 만들 것인가\n원 PR 의 범위를 넘어서는 리뷰 지적을 별도로 처리한다.\n\n'
      printf '## 수용 기준 (EARS)\n1. 시스템은 다음 지적을 반영한다: %s\n' "$text"
    } > "$spec"
    # C1 백엔드로 별도 백로그 task 생성(현 승인 요청에 섞지 않음).
    tb_create_task "${id}-bl-${pr}-${n}" "$spec" "$TB_STATUS_BACKLOG" >/dev/null 2>&1 || true
    log_event "$id" "defer 지적 → 별도 백로그 task 분리: ${id}-bl-${pr}-${n}"
  done < "$deferfile"
}

# ===== SPEC 델타 — 마커 유무로 재개/증분 =====
# rl_spec_delta <task-id> <base-spec> <pr> <mustfile> — must 지적을 SPEC 델타로.
#   원 SPEC 에 미해결 마커가 남아 있으면 그 자리에서 재개, 없으면 같은 계보에 증분 델타.
rl_spec_delta() {
  local id="$1" base="$2" pr="$3" mustfile="$4"
  local td out; td="$(task_dir "$id")"; ensure_task_dir "$id"
  out="$td/.review-delta-$pr.spec.md"
  if [[ -f "$base" ]] && grep -qF '[NEEDS CLARIFICATION' "$base" 2>/dev/null; then
    # 재개: 원 SPEC 을 토대로 마커 자리를 리뷰 지적으로 해소.
    cp "$base" "$out"
    printf '\n## 리뷰 재개 (PR %s)\n다음 봇 변경 요청을 반영해 미해결 마커를 해소한다:\n' "$pr" >> "$out"
  else
    # 증분: 같은 SPEC 계보에 리뷰 델타를 덧붙인 새 SPEC.
    {
      printf '# 리뷰 델타 (PR %s)\n\n' "$pr"
      printf '## 무엇을 만들 것인가\n원 SPEC(%s) 의 head 브랜치 위에서 아래 봇 변경 요청을 반영한다.\n\n' "$base"
      printf '## 수용 기준 (EARS)\n'
    } > "$out"
  fi
  local n=0 line text
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n=$((n+1)); text="${line#*	}"
    printf '%s. 시스템은 다음 봇 지적을 반영한다: %s\n' "$n" "$text" >> "$out"
  done < "$mustfile"
  echo "$out"
}

# ===== 한 리뷰 라운드 (원자 단위 = 생산자 1회 호출) =====
# rl_round <task-id> <base-spec> <pr> <branch>
#   생산자를 정확히 1회 호출해 단일 판정을 얻고 그에 따라 전이한다(수렴 루프는 poll 드레인이 소유).
#   반환: 0=재작업 라운드 수행(request_changes), 10=에스컬레이션, 20=할 일 없음(대기),
#         30=approve(머지 진행가능 전이).
rl_round() {
  local id="$1" base="$2" pr="$3" branch="$4"

  # --- 포지 사람/head 게이트(보존): 판정의 단일 출처가 아니라 두 가지만 본다. ---
  #   (a) 사람 리뷰어의 변경 요청이면 자동수정하지 않고 에스컬레이션(AC: 사람 우선).
  #   (b) head 가 직전 처리분과 같으면 새 커밋이 없으니 멱등 no-op.
  local state author head last
  state="$(rl_review_state "$pr")"
  author="$(rl_review_author "$pr")"
  head="$(rl_review_head "$pr")"

  if rl_is_change_request "$state" && ! rl_is_bot "$author"; then
    rl_escalate "$id" "사람 리뷰어($author)의 변경 요청 — 자동수정 범위 밖"
    return 10
  fi
  last="$(get_head "$id")"
  if [[ -n "$head" && "$head" == "$last" ]]; then
    log_event "$id" "head 동일($head) — 새 커밋 없음, 라운드 미시작"
    return 20
  fi

  # --- 리뷰 생산자 1회 호출 → 단일 머신리더블 판정. ---
  local produce verdict
  # shellcheck disable=SC2086
  produce="$($REVIEW_PRODUCE_CMD "$id" 2>/dev/null)"
  verdict="$(printf '%s' "$produce" | jq -r '.pipeline_verdict // ""' 2>/dev/null)"

  case "$verdict" in
    unavailable)
      rl_escalate "$id" "리뷰 판정 unavailable(diff 잘림 또는 컨텍스트 불완전) — 자동수정 보류"
      return 10
      ;;
    approve)
      # 머지 진행가능 상태로 전이. 추가 재구현 라운드를 시작하지 않는다(라운드 미증가).
      set_field "$id" review-verdict approve
      set_head "$id" "$head"
      set_state "$id" "review-approved"
      log_event "$id" "리뷰 판정 approve — 머지 진행가능 전이(추가 라운드 미시작)"
      return 30
      ;;
    request_changes)
      : # 아래에서 재작업 라운드 진행.
      ;;
    *)
      rl_escalate "$id" "리뷰 판정 미상(verdict='$verdict') — 생산자 출력 파싱 실패"
      return 10
      ;;
  esac

  # --- request_changes: 재작업 라운드. ---
  set_field "$id" review-verdict request_changes

  # AC: 라운드 캡 초과 → 중지·에스컬레이션(승인 요청 Review 유지).
  local round; round="$(bump_review_round "$id")"
  log_event "$id" "재작업 라운드 $round 시작 (verdict=request_changes head=$head)"
  if [[ "$round" -gt "$REVIEW_ROUNDS_MAX" ]]; then
    rl_escalate "$id" "라운드 상한($REVIEW_ROUNDS_MAX) 초과 — 자동수정 중지(승인 요청 Review 유지)"
    return 10
  fi
  set_head "$id" "$head"   # 이번 head 처리 표시

  # 생산자 rework_brief 채택 분류 결과 소비(재분류 안 함): must_adopt·defer 추출.
  local td mustfile deferfile
  td="$(task_dir "$id")"; ensure_task_dir "$id"
  mustfile="$td/.review-must-$pr"; deferfile="$td/.review-defer-$pr"
  rl_produce_extract "$produce" must_adopt "$mustfile"
  rl_produce_extract "$produce" defer      "$deferfile"

  # AC: must_adopt 가 0인데도 여전히 request_changes → 무진전 에스컬레이션.
  if [[ ! -s "$mustfile" ]]; then
    rl_escalate "$id" "must_adopt 0 인데 여전히 request_changes — 무진전"
    return 10
  fi

  # AC: 차단성(must_adopt) 집합이 직전 라운드와 동일 → 핑퐁 에스컬레이션.
  local bh prev
  bh="$(rl_blocking_hash "$mustfile")"
  prev="$(get_field "$id" review-blocking-hash "")"
  if [[ -n "$prev" && "$bh" == "$prev" ]]; then
    rl_escalate "$id" "차단성 지적 집합이 직전 라운드와 동일(핑퐁) — 생산자↔fsd 무한루프 차단"
    return 10
  fi
  set_field "$id" review-blocking-hash "$bh"

  # AC: defer 지적은 현 승인 요청에 섞지 않고 별도 백로그 task 로 분리.
  rl_spinoff_backlog "$id" "$pr" "$deferfile"

  # AC: must 지적 → SPEC 델타 → 본문 재동기화 → head 브랜치 위 구현 → 같은 브랜치 push.
  local delta; delta="$(rl_spec_delta "$id" "$base" "$pr" "$mustfile")"
  tb_sync_body "$id" "$delta" 2>/dev/null || true
  # shellcheck disable=SC2086
  $IMPLEMENT_CMD "$delta" "$branch"
  # 같은 head 브랜치로 push(새 승인 요청 생성 안 함). force 금지 — forge.push_branch 사용.
  push_branch "$branch"
  log_event "$id" "라운드 $round: must 구현 → 같은 head 브랜치($branch) push (새 PR 미생성). 재리뷰는 다음 드레인."
  return 0
}

# ===== 단일 라운드 진입 (수렴 루프는 오케스트레이터=poll 드레인이 소유) =====
# rl_review_loop <task-id> <base-spec> <pr> [branch]
#   "생산자를 한 번 호출" 계약: 한 호출 = 한 라운드. 반복·수렴은 poll 반복 드레인이 책임진다.
rl_review_loop() {
  local id="$1" base="$2" pr="$3" branch="${4:-}"
  [[ -n "$id" && -n "$base" && -n "$pr" ]] || { rl_die "사용: review-loop.sh run <task-id> <spec> <pr> [branch]"; return 1; }
  ensure_task_dir "$id"
  [[ -n "$branch" ]] || branch="$(get_branch "$id")"
  [[ -n "$branch" ]] || branch="$(work_branch "$id" "$base")"
  set_branch "$id" "$branch"

  rl_round "$id" "$base" "$pr" "$branch"
  case "$?" in
    0)  echo "review-loop: 재작업 라운드 수행 — 같은 브랜치 재푸시 (task=$id pr=$pr)"; return 0 ;;
    30) echo "review-loop: approve — 머지 진행가능 (task=$id pr=$pr)"; return 0 ;;
    20) echo "review-loop: 대기 — 새 커밋 없음 (task=$id pr=$pr)"; return 0 ;;
    *)  echo "review-loop: 에스컬레이션으로 종료 (task=$id pr=$pr, Review 유지)"; return 0 ;;
  esac
}

# ===== 자체 검증 (mock 인터페이스) =====
# self-referential: runtime artifact(실제 PR·브랜치) 미검사. 리뷰 판정은 생산자 mock.
rl_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  export FSD_STATE_ROOT="$TMP/.fsd"
  export PROJECT_ROOT="$TMP"

  # --- mock 백엔드 (task-backend) ---
  local BK="$TMP/backend"; mkdir -p "$BK"; echo 0 > "$BK/.counter"
  mock_backend() {
    local verb="$1"; shift
    case "$verb" in
      create) local n; n=$(( $(cat "$BK/.counter") + 1 )); echo "$n" > "$BK/.counter"
              : > "$BK/$n.status"; : > "$BK/$n.body"; echo "$n" ;;
      get-status) cat "$BK/$1.status" 2>/dev/null || true ;;
      set-status) printf '%s' "$2" > "$BK/$1.status" ;;
      get-body)   cat "$BK/$1.body" 2>/dev/null || true ;;
      set-body)   cp "$2" "$BK/$1.body" ;;
      comment)    printf '%s\n' "$2" >> "$BK/$1.comments" ;;
      *) return 2 ;;
    esac
  }
  export TASK_BACKEND_CMD=mock_backend

  # --- mock git/forge (force 인자 보면 exit99) ---
  local PUSHLOG="$TMP/pushlog" PRLOG="$TMP/prlog"; : > "$PUSHLOG"; : > "$PRLOG"
  mock_git() {
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    case "$1" in
      push) printf '%s\n' "$*" >> "$PUSHLOG" ;;
      *) : ;;
    esac
  }
  mock_forge() {
    # pr create 가 호출되면 기록(있으면 안 됨 — 새 PR 금지).
    case "$1 $2" in "pr create") printf '%s\n' "$*" >> "$PRLOG" ;; esac
    case "$1 $2" in "pr list") : ;; esac
  }
  export GIT_CMD=mock_git FORGE_CMD=mock_forge DEFAULT_BRANCH=main

  # --- mock 자율 실행기 ---
  local IMPLLOG="$TMP/impllog"; : > "$IMPLLOG"
  mock_impl() { printf 'impl spec=%s branch=%s\n' "$1" "$2" >> "$IMPLLOG"; }
  export IMPLEMENT_CMD=mock_impl

  # --- mock 포지 리뷰 메타(사람/head 게이트) + 리뷰 생산자 판정 ---
  #   .review  : state/author/head (사람 리뷰어 변경요청·head-신선도 판정에만 사용)
  #   .produce : 생산자 단일 판정 JSON (pipeline_verdict·rework_brief·reviewed_context)
  local RV="$TMP/review"; mkdir -p "$RV"
  mock_review_fetch() { cat "$RV/$1.review" 2>/dev/null || true; }
  mock_produce()      { cat "$RV/$1.produce" 2>/dev/null || true; }
  export REVIEW_FETCH_CMD=mock_review_fetch REVIEW_PRODUCE_CMD=mock_produce

  local base="$TMP/base.spec.md"
  printf '# 원본 기능 SPEC\n## 수용 기준 (EARS)\n1. 항상 X 한다.\n' > "$base"

  local fail=0 rc out delta
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }

  # 사람 리뷰 없는 평범한 포지 메타(생산자가 판정의 단일 출처). head 만 의미 있음.
  forge_meta() { printf 'state: NONE\nauthor: \nhead: %s\n' "$1"; }
  # 생산자 판정 JSON 생성기.
  #   prod_rc <head> <must-title> [<defer-title>] — request_changes.
  prod_rc() {
    local head="$1" must="$2" defer="${3:-}"
    local mj dj='[]'
    mj="$(jq -n --arg t "$must" '[{title:$t, body:($t+" 상세"), severity:"blocking"}]')"
    [[ -n "$defer" ]] && dj="$(jq -n --arg t "$defer" '[{title:$t, body:($t+" 상세"), severity:"blocking"}]')"
    jq -n --arg h "$head" --argjson m "$mj" --argjson d "$dj" \
      '{pipeline_verdict:"request_changes", reviewed_context:{head_sha:$h},
        rework_brief:{must_adopt:$m, defer:$d, wont_adopt:[]}}'
  }
  prod_rc_empty() {  # request_changes 인데 must_adopt 0 (무진전).
    local head="$1"
    jq -n --arg h "$head" '{pipeline_verdict:"request_changes", reviewed_context:{head_sha:$h},
        rework_brief:{must_adopt:[], defer:[], wont_adopt:[]}}'
  }
  prod_simple() {  # approve | unavailable.
    local head="$1" v="$2"
    jq -n --arg h "$head" --arg v "$v" '{pipeline_verdict:$v, reviewed_context:{head_sha:$h},
        rework_brief:{must_adopt:[], defer:[], wont_adopt:[]}}'
  }

  setup_task() {
    local id="$1" pr="$2"
    set_field "$id" issue "$pr"; mock_backend set-status "$pr" "Review"
    set_field "$id" backend-status "Review"; set_branch "$id" "feat/$id-x"
    set_field "$id" review-round 0
  }

  # ---- AC2: 생산자 request_changes + 새 head → 재작업 라운드(구현·재푸시) ----
  setup_task tA 101
  forge_meta sha-AAA > "$RV/101.review"
  prod_rc sha-AAA '보안 입력 검증 추가' > "$RV/tA.produce"
  rl_round tA "$base" 101 "feat/tA-x"; rc=$?
  chk "AC2 라운드 수행(rc=0)" "$rc" "0"
  chk "AC2 라운드 카운터=1" "$(review_round tA)" "1"
  [[ -s "$IMPLLOG" ]] && ok "AC2 구현 실행됨" || bad "AC2 구현 실행됨"
  grep -q 'feat/tA-x' "$PUSHLOG" && ok "AC2 같은 head 브랜치 push" || bad "AC2 같은 head 브랜치 push"
  [[ ! -s "$PRLOG" ]] && ok "AC2 새 PR 미생성" || bad "AC2 새 PR 미생성"
  chk "AC2 head 처리 표시" "$(get_head tA)" "sha-AAA"
  # 같은 head 재호출 → 새 커밋 없음(rc=20).
  rl_round tA "$base" 101 "feat/tA-x"; chk "AC2 동일 head 미시작" "$?" "20"

  # ---- AC3: 생산자 approve → 머지 진행가능 전이, 추가 라운드 미시작 ----
  setup_task tB 107
  : > "$IMPLLOG"
  forge_meta sha-B > "$RV/107.review"
  prod_simple sha-B approve > "$RV/tB.produce"
  rl_round tB "$base" 107 "feat/tB-x"; rc=$?
  chk "AC3 approve rc=30" "$rc" "30"
  chk "AC3 판정 기록=approve" "$(get_field tB review-verdict)" "approve"
  chk "AC3 머지 진행가능 전이" "$(get_state tB)" "review-approved"
  chk "AC3 추가 라운드 미시작" "$(review_round tB)" "0"
  [[ ! -s "$IMPLLOG" ]] && ok "AC3 approve 시 구현 미위임" || bad "AC3 approve 시 구현 미위임"
  # 멱등: 같은 head 재호출 → no-op(rc=20), 재머지·재구현 없음.
  rl_round tB "$base" 107 "feat/tB-x"; chk "AC3 approve 멱등(rc=20)" "$?" "20"

  # ---- AC4a: 생산자 unavailable → 에스컬레이션 ----
  setup_task tU 108
  forge_meta sha-U > "$RV/108.review"
  prod_simple sha-U unavailable > "$RV/tU.produce"
  out="$(rl_round tU "$base" 108 "feat/tU-x")"; rc=$?
  chk "AC4a unavailable 에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *escalate*) ok "AC4a escalate 출력";; *) bad "AC4a escalate 출력";; esac
  chk "AC4a 라운드 미증가" "$(review_round tU)" "0"

  # ---- AC4b: 사람 리뷰어 변경요청 → 생산자 미consult·에스컬레이션 ----
  setup_task tH 102
  printf 'state: CHANGES_REQUESTED\nauthor: human-dev\nhead: sha-H\n' > "$RV/102.review"
  prod_simple sha-H approve > "$RV/tH.produce"   # 생산자가 approve 여도 사람 변경요청 우선.
  out="$(rl_round tH "$base" 102 "feat/tH-x")"; rc=$?
  chk "AC4b 사람=에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *escalate*) ok "AC4b escalate 출력";; *) bad "AC4b escalate 출력";; esac
  chk "AC4b 라운드 미증가" "$(review_round tH)" "0"
  chk "AC4b 상태 Review 유지" "$(get_field tH backend-status)" "Review"

  # ---- AC5: defer 지적 → 별도 백로그 task 분리(현 PR 미혼합) ----
  setup_task tD 103
  forge_meta sha-D > "$RV/103.review"
  prod_rc sha-D '보안 검증 추가' '후속으로 리팩터' > "$RV/tD.produce"
  rl_round tD "$base" 103 "feat/tD-x" >/dev/null; rc=$?
  chk "AC5 라운드 수행" "$rc" "0"
  chk "AC5 백로그 task 분리" "$(get_field tD-bl-103-1 backend-status '')" "Backlog"
  delta="$(task_dir tD)/.review-delta-103.spec.md"
  grep -q '보안 검증' "$delta" && ok "AC5 must 델타 반영" || bad "AC5 must 델타 반영"
  if grep -q '리팩터' "$delta"; then bad "AC5 defer 현PR 미혼합"; else ok "AC5 defer 현PR 미혼합"; fi

  # ---- AC7: force push 미사용 (mock git 은 force 인자 보면 exit99) ----
  ok "AC7 force push 미사용(mock force→exit99 미발동)"

  # ---- AC8: 라운드 상한(3) 초과 → 중지 + 에스컬레이션, Review 유지 ----
  setup_task tC 104
  set_field tC review-round 3   # 다음 라운드는 4 → 초과.
  forge_meta sha-C4 > "$RV/104.review"
  prod_rc sha-C4 '보안 또 수정' > "$RV/tC.produce"
  out="$(rl_round tC "$base" 104 "feat/tC-x")"; rc=$?
  chk "AC8 캡 초과 에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *상한*) ok "AC8 상한 사유";; *) bad "AC8 상한 사유";; esac
  chk "AC8 상태 Review 유지" "$(get_field tC backend-status)" "Review"

  # ---- AC9: must 0 인데 여전히 request_changes → 무진전 에스컬레이션 ----
  setup_task tN 105
  forge_meta sha-N > "$RV/105.review"
  prod_rc_empty sha-N > "$RV/tN.produce"
  out="$(rl_round tN "$base" 105 "feat/tN-x")"; rc=$?
  chk "AC9 무진전 에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *무진전*) ok "AC9 무진전 사유";; *) bad "AC9 무진전 사유";; esac

  # ---- AC10: 차단성(must_adopt) 집합 직전 라운드와 동일 → 핑퐁 에스컬레이션 ----
  setup_task tP 106
  forge_meta sha-P1 > "$RV/106.review"
  prod_rc sha-P1 '보안 입력 검증 누락' > "$RV/tP.produce"
  rl_round tP "$base" 106 "feat/tP-x" >/dev/null; chk "AC10 1라운드 수행" "$?" "0"
  # 같은 차단성 지적이 새 head 로 다시 옴(생산자가 동일 must 반복).
  forge_meta sha-P2 > "$RV/106.review"
  prod_rc sha-P2 '보안 입력 검증 누락' > "$RV/tP.produce"
  out="$(rl_round tP "$base" 106 "feat/tP-x")"; rc=$?
  chk "AC10 핑퐁 에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *핑퐁*) ok "AC10 핑퐁 사유";; *) bad "AC10 핑퐁 사유";; esac

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ===== CLI 진입 (source 시 미실행) =====
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    run)      shift; rl_review_loop "$@" ;;
    round)    shift; rl_round "$@" ;;
    selftest) rl_selftest ;;
    *) echo "usage: review-loop.sh {run <task-id> <spec> <pr> [branch]|round <task-id> <spec> <pr> <branch>|selftest}" >&2; exit 1 ;;
  esac
fi
