#!/usr/bin/env bash
# review-loop.sh — autopilot:dispatch per-SPEC 리뷰 오케스트레이션 (M3)
#
# 책임 (열린 PR 을 승인까지 끌고 가는 한 라운드):
#   - 판정 산출: autopilot:review 생산자(REVIEW_PRODUCE_CMD)를 한 SPEC(키)에 대해 **1회**
#     호출해 단일 머신리더블 판정(pipeline_verdict: approve|request_changes|unavailable)과
#     분류된 재작업 브리프(rework_brief: must_adopt/defer/wont_adopt)를 받는다. 채택 분류는
#     생산자가 rules/change-adoption.md 를 단일 출처로 수행하며 이 모듈은 소비만 한다.
#   - 사람/head 게이트(보존): 열린 PR 의 최신 정식 리뷰가 **사람** 리뷰어의 변경 요청이면
#     자동수정하지 않고 에스컬레이션한다. head 가 직전 처리분과 같으면 멱등 no-op.
#   - 판정 분기:
#       request_changes → must_adopt 를 run-dir 하위 SPEC 델타로 만들어 같은 head 브랜치 위에서
#         자율 실행기로 구현하고 같은 head 브랜치로 push(새 PR 미생성, force 금지). 라운드 카운터
#         증가. defer 지적은 현 PR 에 섞지 않고 run-dir 에 별도 기록(백로그 분리).
#       approve         → 머지 진행가능(int-phase=approved). 추가 라운드 미시작.
#       unavailable     → 에스컬레이션.
#   - 무한루프 가드(세 겹): 라운드 상한(기본 3) 초과 / must_adopt 0인데 request_changes(무진전) /
#     차단성(must_adopt) 집합이 직전과 동일(핑퐁) → 에스컬레이션. 수렴 반복은 스케줄러 드레인 소유
#     (한 호출 = 한 라운드).
#
# 이 모듈은 규칙의 실행자다(규칙 재정의 금지):
#   rules/review.md / rules/change-adoption.md (생산자가 적용; 여기선 소비).
#
# 불변식:
#   - force(강제) push 금지. 새 PR 미생성(같은 head 브랜치 갱신만).
#   - per-SPEC 상태·델타·defer 는 run 디렉토리(.dispatch/runs/<run-id>/) 안에만 둔다.
#   - 키는 호출자(스케줄러)가 주입한다(재계산 안 함).
#
# 모든 외부 인터페이스(리뷰 생산자·포지 리뷰 메타·자율 실행기·git·forge)는 주입 가능한
# 명령 변수로 두어 mock 으로 독립 검증한다(self-referential). bash 3.2+ 호환.
#
# 환경 변수 (mock 치환 가능):
#   REVIEW_PRODUCE_CMD <key>      autopilot:review 생산자 호출 → 판정 JSON(stdout).
#   REVIEW_FETCH_CMD   <pr>       최신 정식 리뷰 메타(state/author/head 줄). 사람/head 게이트 전용.
#   IMPLEMENT_CMD <spec> <branch> head 브랜치 위 SPEC 델타 자율 구현.
#   REVIEW_ROUNDS_MAX             라운드 상한(기본 3).
#   GIT_CMD/FORGE_CMD/LOOP_CMD/DEFAULT_BRANCH   integration.sh 와 공유(push 등).

set -uo pipefail

RL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 통합 모듈(M2) 로드 → lib-integration(M1)·in_push_branch·in_work_branch·in_spec_title 확보.
if ! declare -f in_push_branch >/dev/null 2>&1; then
  # shellcheck source=integration.sh
  . "$RL_SCRIPT_DIR/integration.sh"
fi
# integration.sh 는 top-level 에서 set -uo pipefail. 본 모듈도 동일(반환코드 직접 처리).
set +e
set -uo pipefail

REVIEW_ROUNDS_MAX="${REVIEW_ROUNDS_MAX:-3}"
REVIEW_BOT_LOGIN_RE="${REVIEW_BOT_LOGIN_RE:-(\[bot\]$|claude|github-actions)}"

REVIEW_FETCH_CMD="${REVIEW_FETCH_CMD:-rl_review_fetch_gh}"
REVIEW_PRODUCE_CMD="${REVIEW_PRODUCE_CMD:-rl_produce_review_skill}"
IMPLEMENT_CMD="${IMPLEMENT_CMD:-rl_implement_loop}"

rl_die() { echo "review-loop: $*" >&2; return 1; }

# ===== 기본(gh/생산자/loop) 구현 — self-referential 검증은 mock 으로, 이 경로 미호출 =====
rl_review_fetch_gh() {
  local pr="$1"
  command -v gh >/dev/null 2>&1 || { rl_die "gh CLI 필요"; return 1; }
  gh pr view "$pr" --json reviews,headRefOid --jq '
    (.reviews | map(select(.state=="CHANGES_REQUESTED" or .state=="APPROVED" or .state=="COMMENTED")) | last) as $r
    | "state: \($r.state // "NONE")\nauthor: \($r.author.login // "")\nhead: \(.headRefOid // "")"
  ' 2>/dev/null
}

# 기본: autopilot:review 생산자를 per-SPEC 키(=--task)로 1회 호출.
rl_produce_review_skill() {
  bash "$RL_SCRIPT_DIR/../review/references/review.sh" run --task "$1"
}

# 기본: 자율 실행기(loop)에 SPEC 델타 위임. loop 는 --branch 미지원이므로 같은 PR 브랜치 위
# 재구현은 그 브랜치를 체크아웃한 워크트리 안에서 loop 를 secondary 모드로 호출해 수행한다
# (SPEC 위험 섹션). 이 기본 경로는 실제 실행이며 selftest 에선 mock 으로 대체된다.
rl_implement_loop() {
  local spec="$1" branch="$2"
  # shellcheck disable=SC2086
  ${LOOP_CMD:-true} start "$spec" >/dev/null 2>&1
}

# ===== 리뷰 메타 파싱 (사람/head 게이트 전용) =====
rl_review_field() {
  # shellcheck disable=SC2086
  $REVIEW_FETCH_CMD "$1" 2>/dev/null | grep -i -m1 "^$2:" | sed -E "s/^[^:]*:[[:space:]]*//"
}
rl_review_state()  { rl_review_field "$1" state; }
rl_review_author() { rl_review_field "$1" author; }
rl_review_head()   { rl_review_field "$1" head; }

rl_is_change_request() {
  local s; s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$s" in request_changes|changes_requested) return 0 ;; *) return 1 ;; esac
}
rl_is_bot() { printf '%s' "$1" | grep -qiE "$REVIEW_BOT_LOGIN_RE"; }

# ===== rework_brief 채택 분류 소비 (재분류 안 함) =====
# rl_produce_extract <produce-json> <key> <outfile> — rework_brief.<key> 항목을
#   "<title> — <body>" 한 줄씩 평탄화. title·body 모두 빈 항목은 제외(무진전 가드 보존).
rl_produce_extract() {
  local json="$1" bkey="$2" out="$3"
  : > "$out"
  printf '%s' "$json" \
    | jq -r --arg k "$bkey" '(.rework_brief[$k] // [])[]
        | ((.title // "") + (if (.body // "") != "" then " — " + .body else "" end))
        | select(. != "")' \
        2>/dev/null >> "$out" || true
}

# rl_blocking_hash <mustfile> — 차단성 집합의 순서무관 안정 해시(핑퐁 탐지).
rl_blocking_hash() {
  local f="$1"
  [[ -s "$f" ]] || { echo "EMPTY"; return 0; }
  if command -v sha1sum >/dev/null 2>&1; then LC_ALL=C sort "$f" | sha1sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then LC_ALL=C sort "$f" | shasum | awk '{print $1}'
  else LC_ALL=C sort "$f" | cksum | tr -d ' '; fi
}

# ===== 에스컬레이션 — int-phase=escalated(비완료 종착). 스케줄러가 failed 로 전파. =====
# rl_escalate <run_dir> <key> <reason>
rl_escalate() {
  local rd="$1" key="$2" reason="$3"
  int_set_phase "$rd" "$key" escalated
  int_log "$rd" "$key" "에스컬레이션: $reason"
  echo "escalate: $reason"
}

# ===== defer 분리 — run-dir 에 백로그로 별도 기록(현 PR 미혼합) =====
# rl_spinoff_backlog <run_dir> <key> <pr> <deferfile>
rl_spinoff_backlog() {
  local rd="$1" key="$2" pr="$3" deferfile="$4"
  [[ -s "$deferfile" ]] || return 0
  local out="$rd/backlog.$key.$pr.md" n=0 line text
  : > "$out"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n=$((n+1)); text="${line#*	}"
    printf '# 후속(백로그): 리뷰 지적 분리 (PR %s #%s)\n원 PR 범위를 넘는 리뷰 지적을 별도로 처리: %s\n\n' "$pr" "$n" "$text" >> "$out"
    int_log "$rd" "$key" "defer 지적 → 백로그 분리(현 PR 미혼합): $text"
  done < "$deferfile"
}

# ===== SPEC 델타 — must 지적을 run-dir 하위 델타 SPEC 으로 =====
# rl_spec_delta <run_dir> <key> <base-spec> <pr> <mustfile> — 델타 경로 echo.
rl_spec_delta() {
  local rd="$1" key="$2" base="$3" pr="$4" mustfile="$5"
  local out="$rd/delta.$key.$pr.spec.md"
  if [[ -f "$base" ]] && grep -qF '[NEEDS CLARIFICATION' "$base" 2>/dev/null; then
    cp "$base" "$out"
    printf '\n## 리뷰 재개 (PR %s)\n다음 봇 변경 요청을 반영해 미해결 마커를 해소한다:\n' "$pr" >> "$out"
  else
    {
      printf '# 리뷰 델타 (PR %s)\n\n' "$pr"
      printf '## 무엇을 만들 것인가\n원 SPEC(%s) 의 head 브랜치 위에서 아래 봇 변경 요청을 반영한다.\n\n' "$base"
      printf '## 수용 기준\n'
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
# rl_round <run_dir> <key> <base-spec> <pr> <branch>
#   반환: 0=재작업 라운드 수행, 10=에스컬레이션, 20=할 일 없음(대기), 30=approve.
rl_round() {
  local rd="$1" key="$2" base="$3" pr="$4" branch="$5"
  mkdir -p "$rd"

  # --- 사람/head 게이트(판정 단일출처 아님; 두 가지만) ---
  local state author head last
  state="$(rl_review_state "$pr")"
  author="$(rl_review_author "$pr")"
  head="$(rl_review_head "$pr")"

  if rl_is_change_request "$state" && ! rl_is_bot "$author"; then
    rl_escalate "$rd" "$key" "사람 리뷰어($author)의 변경 요청 — 자동수정 범위 밖"
    return 10
  fi
  last="$(int_get_head "$rd" "$key")"
  if [[ -n "$head" && "$head" == "$last" ]]; then
    int_log "$rd" "$key" "head 동일($head) — 새 커밋 없음, 라운드 미시작"
    return 20
  fi

  # --- 리뷰 생산자 1회 호출 → 단일 판정 ---
  local produce verdict
  # shellcheck disable=SC2086
  produce="$($REVIEW_PRODUCE_CMD "$key" 2>/dev/null)"
  verdict="$(printf '%s' "$produce" | jq -r '.pipeline_verdict // ""' 2>/dev/null)"

  case "$verdict" in
    unavailable)
      rl_escalate "$rd" "$key" "리뷰 판정 unavailable(diff 잘림·컨텍스트 불완전) — 자동수정 보류"
      return 10 ;;
    approve)
      int_set_verdict "$rd" "$key" approve
      int_set_head "$rd" "$key" "$head"
      int_set_phase "$rd" "$key" approved
      int_log "$rd" "$key" "리뷰 판정 approve — 머지 진행가능 전이(추가 라운드 미시작)"
      return 30 ;;
    request_changes) : ;;
    *)
      if [[ -z "$produce" ]]; then
        rl_escalate "$rd" "$key" "리뷰 생산자 출력 비었음(생산 실패·미설정) — 자동수정 보류"
      else
        rl_escalate "$rd" "$key" "리뷰 판정 미상(verdict='$verdict') — 생산자 출력 파싱 실패"
      fi
      return 10 ;;
  esac

  # --- request_changes: 재작업 라운드 ---
  int_set_verdict "$rd" "$key" request_changes
  local round; round="$(int_bump_review_round "$rd" "$key")"
  int_log "$rd" "$key" "재작업 라운드 $round 시작 (verdict=request_changes head=$head)"
  if [[ "$round" -gt "$REVIEW_ROUNDS_MAX" ]]; then
    rl_escalate "$rd" "$key" "라운드 상한($REVIEW_ROUNDS_MAX) 초과 — 자동수정 중지"
    return 10
  fi
  int_set_head "$rd" "$key" "$head"

  local mustfile deferfile
  mustfile="$rd/must.$key.$pr"; deferfile="$rd/defer.$key.$pr"
  rl_produce_extract "$produce" must_adopt "$mustfile"
  rl_produce_extract "$produce" defer      "$deferfile"

  if [[ ! -s "$mustfile" ]]; then
    rl_escalate "$rd" "$key" "must_adopt 0 인데 여전히 request_changes — 무진전"
    return 10
  fi

  local bh prev
  bh="$(rl_blocking_hash "$mustfile")"
  prev="$(int_get_blocking_hash "$rd" "$key")"
  if [[ -n "$prev" && "$bh" == "$prev" ]]; then
    rl_escalate "$rd" "$key" "차단성 지적 집합이 직전 라운드와 동일(핑퐁) — 무한루프 차단"
    return 10
  fi
  int_set_blocking_hash "$rd" "$key" "$bh"

  rl_spinoff_backlog "$rd" "$key" "$pr" "$deferfile"

  local delta; delta="$(rl_spec_delta "$rd" "$key" "$base" "$pr" "$mustfile")"
  # shellcheck disable=SC2086
  $IMPLEMENT_CMD "$delta" "$branch"
  in_push_branch "$branch"
  int_log "$rd" "$key" "라운드 $round: must 구현 → 같은 head 브랜치($branch) push(새 PR 미생성). 재리뷰는 다음 드레인."
  return 0
}

# ===== 단일 라운드 진입 (수렴은 스케줄러 드레인 소유) =====
# rl_review_loop <run_dir> <key> <base-spec> <pr> [branch]
rl_review_loop() {
  local rd="$1" key="$2" base="$3" pr="$4" branch="${5:-}"
  [[ -n "$rd" && -n "$key" && -n "$base" && -n "$pr" ]] \
    || { rl_die "사용: review-loop.sh run <run_dir> <key> <spec> <pr> [branch]"; return 1; }
  mkdir -p "$rd"
  [[ -n "$branch" ]] || branch="$(int_get_branch "$rd" "$key")"
  [[ -n "$branch" ]] || branch="$(in_work_branch "$(basename "$rd")" "$base")"
  int_set_branch "$rd" "$key" "$branch"

  rl_round "$rd" "$key" "$base" "$pr" "$branch"
  case "$?" in
    0)  echo "review-loop: 재작업 라운드 수행 — 같은 브랜치 재푸시 (key=$key pr=$pr)"; return 0 ;;
    30) echo "review-loop: approve — 머지 진행가능 (key=$key pr=$pr)"; return 0 ;;
    20) echo "review-loop: 대기 — 새 커밋 없음 (key=$key pr=$pr)"; return 0 ;;
    *)  echo "review-loop: 에스컬레이션으로 종료 (key=$key pr=$pr)"; return 0 ;;
  esac
}

# =====================================================================
# selftest — mock 인터페이스로 판정 분기·세 가드·사람/head 게이트·force 미사용 검증.
# =====================================================================
rl_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local rd="$TMP/.dispatch/runs/run1"; mkdir -p "$rd"

  # mock git: force 보면 exit99. push 기록.
  local PUSHLOG="$TMP/pushlog"; : > "$PUSHLOG"
  mock_git() {
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    case "$1" in push) printf '%s\n' "$*" >> "$PUSHLOG" ;; esac
    return 0
  }
  GIT_CMD=mock_git; FORGE_CMD=:; DEFAULT_BRANCH=main

  # mock 구현 위임.
  local IMPLLOG="$TMP/impllog"; : > "$IMPLLOG"
  mock_impl() { printf 'impl spec=%s branch=%s\n' "$1" "$2" >> "$IMPLLOG"; }
  IMPLEMENT_CMD=mock_impl

  # mock 포지 리뷰 메타 + 리뷰 생산자 판정(키별 파일).
  local RV="$TMP/review"; mkdir -p "$RV"
  mock_fetch()   { cat "$RV/$1.review" 2>/dev/null || true; }
  mock_produce() { cat "$RV/$1.produce" 2>/dev/null || true; }
  REVIEW_FETCH_CMD=mock_fetch; REVIEW_PRODUCE_CMD=mock_produce

  local base="$TMP/base.spec.md"
  printf '# 원본 기능 SPEC\n## 수용 기준\n1. 항상 X 한다.\n' > "$base"

  local fail=0 rc out delta
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }

  forge_meta() { printf 'state: NONE\nauthor: \nhead: %s\n' "$1"; }
  prod_rc() {
    local head="$1" must="$2" defer="${3:-}" mj dj='[]'
    mj="$(jq -n --arg t "$must" '[{title:$t, body:($t+" 상세"), severity:"blocking"}]')"
    [[ -n "$defer" ]] && dj="$(jq -n --arg t "$defer" '[{title:$t, body:($t+" 상세"), severity:"blocking"}]')"
    jq -n --arg h "$head" --argjson m "$mj" --argjson d "$dj" \
      '{pipeline_verdict:"request_changes", reviewed_context:{head_sha:$h},
        rework_brief:{must_adopt:$m, defer:$d, wont_adopt:[]}}'
  }
  prod_rc_empty() { jq -n --arg h "$1" '{pipeline_verdict:"request_changes", reviewed_context:{head_sha:$h}, rework_brief:{must_adopt:[], defer:[], wont_adopt:[]}}'; }
  prod_simple()   { jq -n --arg h "$1" --arg v "$2" '{pipeline_verdict:$v, reviewed_context:{head_sha:$h}, rework_brief:{must_adopt:[], defer:[], wont_adopt:[]}}'; }

  # ---- AC3: request_changes + 새 head → 재작업 라운드(구현·재푸시) ----
  local kA="a-aaa1"
  forge_meta sha-AAA > "$RV/101.review"; prod_rc sha-AAA '보안 입력 검증 추가' > "$RV/$kA.produce"
  rl_round "$rd" "$kA" "$base" 101 "feat/run1-a"; rc=$?
  chk "AC3 라운드 수행(rc=0)" "$rc" "0"
  chk "AC3 라운드 카운터=1" "$(int_review_round "$rd" "$kA")" "1"
  [[ -s "$IMPLLOG" ]] && ok "AC3 구현 실행됨" || bad "AC3 구현 실행됨"
  grep -q 'feat/run1-a' "$PUSHLOG" && ok "AC3 같은 head 브랜치 push" || bad "AC3 같은 head 브랜치 push"
  chk "AC3 head 처리 표시" "$(int_get_head "$rd" "$kA")" "sha-AAA"
  delta="$rd/delta.$kA.101.spec.md"
  grep -q '보안 입력 검증' "$delta" && ok "AC3 must 델타 반영" || bad "AC3 must 델타 반영"
  # 같은 head 재호출 → no-op(rc=20).
  rl_round "$rd" "$kA" "$base" 101 "feat/run1-a"; chk "AC5 동일 head 미시작(rc=20)" "$?" "20"

  # ---- AC6: approve → 머지 진행가능, 추가 라운드 미시작 ----
  local kB="b-bbb2"; : > "$IMPLLOG"
  forge_meta sha-B > "$RV/107.review"; prod_simple sha-B approve > "$RV/$kB.produce"
  rl_round "$rd" "$kB" "$base" 107 "feat/run1-b"; rc=$?
  chk "AC6 approve rc=30" "$rc" "30"
  chk "AC6 판정 기록=approve" "$(int_get_verdict "$rd" "$kB")" "approve"
  chk "AC6 phase=approved" "$(int_get_phase "$rd" "$kB")" "approved"
  chk "AC6 추가 라운드 미시작" "$(int_review_round "$rd" "$kB")" "0"
  [[ ! -s "$IMPLLOG" ]] && ok "AC6 approve 시 구현 미위임" || bad "AC6 approve 시 구현 미위임"
  rl_round "$rd" "$kB" "$base" 107 "feat/run1-b"; chk "AC6 approve 멱등(rc=20)" "$?" "20"

  # ---- AC4: unavailable → 에스컬레이션 ----
  local kU="u-uuu3"
  forge_meta sha-U > "$RV/108.review"; prod_simple sha-U unavailable > "$RV/$kU.produce"
  out="$(rl_round "$rd" "$kU" "$base" 108 "feat/run1-u")"; rc=$?
  chk "AC4 unavailable rc=10" "$rc" "10"
  case "$out" in *escalate*) ok "AC4 escalate 출력";; *) bad "AC4 escalate 출력";; esac
  chk "AC4 phase=escalated" "$(int_get_phase "$rd" "$kU")" "escalated"
  chk "AC4 라운드 미증가" "$(int_review_round "$rd" "$kU")" "0"

  # ---- AC5: 사람 리뷰어 변경요청 → 생산자 미consult·에스컬레이션 ----
  local kH="h-hhh4"
  printf 'state: CHANGES_REQUESTED\nauthor: human-dev\nhead: sha-H\n' > "$RV/102.review"
  prod_simple sha-H approve > "$RV/$kH.produce"
  out="$(rl_round "$rd" "$kH" "$base" 102 "feat/run1-h")"; rc=$?
  chk "AC5 사람=에스컬레이션(rc=10)" "$rc" "10"
  chk "AC5 phase=escalated" "$(int_get_phase "$rd" "$kH")" "escalated"
  chk "AC5 라운드 미증가" "$(int_review_round "$rd" "$kH")" "0"

  # ---- AC3 defer: defer 지적 → 별도 백로그 분리(현 PR 미혼합) ----
  local kD="d-ddd5"
  forge_meta sha-D > "$RV/103.review"; prod_rc sha-D '보안 검증 추가' '후속으로 리팩터' > "$RV/$kD.produce"
  rl_round "$rd" "$kD" "$base" 103 "feat/run1-d" >/dev/null; rc=$?
  chk "AC3 defer 라운드 수행" "$rc" "0"
  [[ -s "$rd/backlog.$kD.103.md" ]] && ok "AC3 백로그 분리 파일 생성" || bad "AC3 백로그 분리 파일 생성"
  delta="$rd/delta.$kD.103.spec.md"
  grep -q '보안 검증' "$delta" && ok "AC3 must 델타 반영" || bad "AC3 must 델타 반영"
  if grep -q '리팩터' "$delta"; then bad "AC3 defer 현PR 미혼합"; else ok "AC3 defer 현PR 미혼합"; fi

  # ---- AC4 가드: 라운드 상한(3) 초과 → 에스컬레이션 ----
  local kC="c-ccc6"
  int_set "$rd" "$kC" review-round 3
  forge_meta sha-C4 > "$RV/104.review"; prod_rc sha-C4 '보안 또 수정' > "$RV/$kC.produce"
  out="$(rl_round "$rd" "$kC" "$base" 104 "feat/run1-c")"; rc=$?
  chk "AC4 캡 초과 에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *상한*) ok "AC4 상한 사유";; *) bad "AC4 상한 사유";; esac

  # ---- AC4 가드: must 0 인데 request_changes → 무진전 에스컬레이션 ----
  local kN="n-nnn7"
  forge_meta sha-N > "$RV/105.review"; prod_rc_empty sha-N > "$RV/$kN.produce"
  out="$(rl_round "$rd" "$kN" "$base" 105 "feat/run1-n")"; rc=$?
  chk "AC4 무진전 에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *무진전*) ok "AC4 무진전 사유";; *) bad "AC4 무진전 사유";; esac

  # ---- AC4 가드: 빈 title/body must → 공백줄 무진전 우회 금지 ----
  local kE="e-eee8"
  forge_meta sha-E > "$RV/109.review"
  jq -n '{pipeline_verdict:"request_changes", reviewed_context:{head_sha:"sha-E"}, rework_brief:{must_adopt:[{title:"",body:"",severity:"blocking"}], defer:[], wont_adopt:[]}}' > "$RV/$kE.produce"
  out="$(rl_round "$rd" "$kE" "$base" 109 "feat/run1-e")"; rc=$?
  chk "AC4 빈 must=무진전(rc=10)" "$rc" "10"
  [[ ! -f "$rd/delta.$kE.109.spec.md" ]] && ok "AC4 공백 델타 미생성" || bad "AC4 공백 델타 미생성"

  # ---- AC4 가드: 핑퐁(차단성 집합 직전과 동일) → 에스컬레이션 ----
  local kP="p-ppp9"
  forge_meta sha-P1 > "$RV/106.review"; prod_rc sha-P1 '보안 입력 검증 누락' > "$RV/$kP.produce"
  rl_round "$rd" "$kP" "$base" 106 "feat/run1-p" >/dev/null; chk "AC4 핑퐁 1라운드 수행" "$?" "0"
  forge_meta sha-P2 > "$RV/106.review"; prod_rc sha-P2 '보안 입력 검증 누락' > "$RV/$kP.produce"
  out="$(rl_round "$rd" "$kP" "$base" 106 "feat/run1-p")"; rc=$?
  chk "AC4 핑퐁 에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *핑퐁*) ok "AC4 핑퐁 사유";; *) bad "AC4 핑퐁 사유";; esac

  # ---- force 미사용 (mock_git force 보면 exit99; 여기 도달했으면 미사용) ----
  [[ -s "$PUSHLOG" ]] && ok "재작업 라운드 실제 push 수행" || bad "재작업 라운드 실제 push 수행"
  if grep -qiE 'force|(^| )-f( |$)' "$PUSHLOG"; then bad "force push 미사용"; else ok "force push 미사용(push 인자에 force 없음)"; fi

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
    *) echo "usage: review-loop.sh {run <run_dir> <key> <spec> <pr> [branch]|round <run_dir> <key> <spec> <pr> <branch>|selftest}" >&2; exit 1 ;;
  esac
fi
