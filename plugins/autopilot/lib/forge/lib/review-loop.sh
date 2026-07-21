#!/usr/bin/env bash
# review-loop.sh — forge per-SPEC 리뷰 오케스트레이션 (M3)
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
#   - per-SPEC 상태·델타·defer 는 run 디렉토리(.autopilot/runs/<id>/) 안에만 둔다.
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

# 통합 모듈(M2) 로드 → state-io(M1)·in_push_branch·in_work_branch·in_spec_title 확보.
if ! declare -f in_push_branch >/dev/null 2>&1; then
  # shellcheck source=integration.sh
  . "$RL_SCRIPT_DIR/integration.sh"
fi
# integration.sh 는 top-level 에서 set -uo pipefail. 본 모듈도 동일(반환코드 직접 처리).
set +e
set -uo pipefail

REVIEW_ROUNDS_MAX="${REVIEW_ROUNDS_MAX:-3}"
# 신뢰봇 로그인 판별(세 게이트 공용: 승인 마커·현재-head 재리뷰 증거·미해결 스레드 차단).
#   `-bot$`: GitHub App 이 아닌 머신유저 리뷰봇 계정의 접미 관례(예: courtesy-bot) — #627.
#   접미 앵커라 임의 계정 오포섭을 최소화한다. 저장소별 커스텀은 env override 로.
REVIEW_BOT_LOGIN_RE="${REVIEW_BOT_LOGIN_RE:-(\[bot\]$|-bot$|claude|github-actions)}"

REVIEW_FETCH_CMD="${REVIEW_FETCH_CMD:-rl_review_fetch_gh}"
REVIEW_PRODUCE_CMD="${REVIEW_PRODUCE_CMD:-rl_produce_review_skill}"
IMPLEMENT_CMD="${IMPLEMENT_CMD:-rl_implement_loop}"

rl_die() { echo "review-loop: $*" >&2; return 1; }

# ===== 기본(gh/생산자/loop) 구현 — self-referential 검증은 mock 으로, 이 경로 미호출 =====
rl_review_fetch_gh() {
  local pr="$1" head decision approve="" findings
  command -v gh >/dev/null 2>&1 || { rl_die "gh CLI 필요"; return 1; }
  head="$(gh pr view "$pr" --json headRefOid --jq '.headRefOid' 2>/dev/null)"
  decision="$(gh pr view "$pr" --json reviewDecision --jq '.reviewDecision' 2>/dev/null)"
  # 최신 정식 리뷰 상태/작성자(사람 변경요청 게이트 전용).
  gh pr view "$pr" --json reviews --jq '
    (.reviews | map(select(.state=="CHANGES_REQUESTED" or .state=="APPROVED" or .state=="COMMENTED")) | last) as $r
    | "state: \($r.state // "NONE")\nauthor: \($r.author.login // "")"
  ' 2>/dev/null
  echo "head: ${head:-}"
  # 승인: 공식 APPROVED 또는 신뢰 봇이 현재 head 에 남긴 승인 마커(verdict=approve, *-formal-review).
  if [[ "$decision" == "APPROVED" ]]; then approve=1; fi
  # 봇 로그인 정규식은 **login 필드 단독**에 적용해야 앵커(\[bot\]$)가 성립한다 — login\tbody
  #   결합 라인에 grep 하면 본문 때문에 앵커가 깨진다(#432). awk 로 현재 head 의 verdict=approve
  #   마커를 가진 리뷰의 login 만 추출 → 그 login 을 신뢰봇 grep(아래 [blocking] 인라인 게이트와 동일).
  #   리뷰 본문(login\tbody)은 1회 조회해 승인 마커·공식 재리뷰 실재 증거(#549) 검사에 공용한다.
  local rbodies=""
  [[ -n "$head" ]] && rbodies="$(gh pr view "$pr" --json reviews \
        --jq '.reviews[] | (.author.login // "") + "\t" + ((.body // "")|gsub("[\n\t]";" "))' 2>/dev/null)"
  if [[ -z "$approve" && -n "$rbodies" ]] && printf '%s\n' "$rbodies" \
       | awk -F'\t' -v h="$head" '$2 ~ ("head_sha=" h "[^>]*verdict=approve") {print $1}' \
       | grep -qE "$REVIEW_BOT_LOGIN_RE"; then approve=1; fi
  # 현재 head 에 대한 공식 재리뷰 실재 증거 — 신뢰봇의 *-formal-review 마커(verdict 무관; 워크플로는
  #   approve/comment 모두 마커를 게시). GitHub 는 과거 커밋의 미해결 인라인 코멘트 앵커가 살아 있으면
  #   commit.oid 를 최신 head 로 재매핑하므로, oid==head 만으로는 "이번 head 가 재평가됨"을 뜻하지
  #   않는다(#549 거짓 핑퐁). 증거 없으면 아래에서 재매핑 스레드를 새 차단 지적으로 채택하지 않는다.
  local reviewed=""
  if [[ -n "$rbodies" ]] && printf '%s\n' "$rbodies" \
       | awk -F'\t' -v h="$head" '$2 ~ ("-formal-review[^>]*head_sha=" h) {print $1}' \
       | grep -qE "$REVIEW_BOT_LOGIN_RE"; then reviewed=1; fi
  # 현재 head 미해결(isResolved=false) 스레드의 인라인 코멘트만 조회(GraphQL): login\tcommit_oid\tbody.
  #   resolve 된 스레드는 제외해 resolve→재리뷰 데드락을 막는다. raw JSON 을 jq 로 필터
  #   (mock=raw 반환으로 isResolved 필터를 결정적 검증). 조회/owner 확정 실패·head 미확정은
  #   보수적 차단(default-deny).
  local on owner name raw comments crc=0 blocking=""
  on="$(gh repo view --json owner,name --jq '.owner.login+" "+.name' 2>/dev/null)" || on=""
  owner="${on%% *}"; name="${on##* }"
  if [[ -z "$head" || -z "$owner" || -z "$name" ]]; then
    crc=1
  else
    # 모든 reviewThreads 페이지를 --paginate(pageInfo+after:$endCursor)로 따라간다(100개 초과
    #   스레드 누락 방지). comments first:100(단일 스레드 100개 초과는 비현실적). gh 는 페이지별
    #   JSON 을 연결 출력하고 아래 jq 가 스트림 전체를 처리한다.
    raw="$(gh api graphql --paginate -F owner="$owner" -F name="$name" -F pr="$pr" -f query='
query($owner:String!,$name:String!,$pr:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){
    pullRequest(number:$pr){
      reviewThreads(first:100, after:$endCursor){
        pageInfo{hasNextPage endCursor}
        nodes{isResolved comments(first:100){nodes{author{login} commit{oid} body}}}
      }
    }}}' 2>/dev/null)"
    if [[ $? -ne 0 || -z "$raw" ]]; then
      crc=1
    else
      comments="$(printf '%s' "$raw" | jq -r '
            .data.repository.pullRequest.reviewThreads.nodes[]
            | select(.isResolved==false)
            | .comments.nodes[]
            | (.author.login // "")+"\t"+(.commit.oid // "")+"\t"+((.body // "")|gsub("[\n\t]";" "))' 2>/dev/null)" || crc=1
    fi
  fi
  # 신뢰봇이 현재 head 에 남긴 미해결 리뷰 스레드 — approve 를 가리는 가산 차단(태그 무관, #493; PR #385).
  if [[ $crc -ne 0 ]]; then
    blocking="FETCH_FAILED"
  elif printf '%s\n' "$comments" \
       | awk -F'\t' -v h="$head" '$2==h {print $1}' \
       | grep -qE "$REVIEW_BOT_LOGIN_RE"; then
    blocking=1
  fi
  # 현재 head 미해결 스레드의 전체 인라인 지적(타당성 판단은 워커가 change-adoption 으로 — 원천만 평탄화).
  findings="$(printf '%s\n' "$comments" | awk -F'\t' -v h="$head" '$2==h{print $3}' \
       | sed -E 's/<!--[^>]*-->//g' | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  # #600: 신뢰봇 미해결 스레드의 실재를 verdict 와 별도로 표면화 — rl_round 같은-head 게이트가
  #   pending 교착(그곳 주석 참조)을 식별하는 신호.
  [[ "$blocking" == "1" ]] && echo "blocked: 1"
  if [[ -n "$approve" && -z "$blocking" ]]; then
    echo "verdict: approve"
  elif [[ "$blocking" == "FETCH_FAILED" ]]; then
    # 인라인 조회 실패 → 거짓 승인 금지. changes 로 표면화(무진전 가드가 에스컬레이션 유도).
    #   fetchfail 마커: 이 changes 는 실재 증거(미해결 스레드+공식 재리뷰 마커)가 아닌 합성 판정임을
    #   구분한다 — #571 같은 head 재평가 게이트가 일시적 조회 실패로 재작업 라운드를 소모하지 않게.
    echo "verdict: changes"
    echo "fetchfail: 1"
    echo "finding: 미해결 리뷰 스레드 조회 실패 — default-deny(보수적 차단), 확인 필요"
  elif [[ -n "$findings" && -n "$reviewed" ]]; then
    echo "verdict: changes"
    echo "finding: $findings"
  else
    # 지적이 없거나, 있어도 현재 head 공식 재리뷰 증거가 없으면(재매핑 추정) 대기(#549).
    #   blocking 에 의한 approve 가림(#493)은 위에서 그대로 유지된다 — 거짓 승인은 없다.
    echo "verdict: pending"
  fi
}

# 기본: autopilot:review 생산자를 per-SPEC 키(=--task)로 1회 호출.
rl_produce_review_skill() {
  bash "$RL_SCRIPT_DIR/../../../skills/review/references/review.sh" run --task "$1"
}

# 기본: 자율 실행기(loop)에 SPEC 델타 위임. loop 는 --branch 미지원이므로 같은 PR 브랜치 위
# 재구현은 그 브랜치가 체크아웃된 워크트리 안에서 loop 를 secondary 모드로 호출해 수행한다
# (SPEC 위험 섹션).
#   (1) feat 브랜치가 이미 체크아웃된 워크트리가 있으면 그 안에서 수행.
#   (2) 없으면(구현 워크트리는 `worktree add --detach` 라 어떤 로컬 브랜치에도 미체크아웃 — 갭X)
#       feat 브랜치(로컬 ref)가 **실제로 존재할 때만** 그 브랜치를 체크아웃한 전용 임시 워크트리를
#       만들어 그 안에서 loop 를 수행한다. feat 브랜치 ref 확인 후에만 진행하므로 엉뚱한 체크아웃의
#       변경을 push 하지 않는 불변식이 보존된다. ref 가 없으면 거짓 성공 대신 비-0(에스컬레이션 유도).
# (selftest 갭X 케이스를 빼면 IMPLEMENT_CMD 가 mock 으로 대체되어 이 경로를 타지 않는다.)
rl_implement_loop() {
  local spec="$1" branch="$2" wt rc tmpwt
  wt="$(${GIT_CMD:-git} worktree list --porcelain 2>/dev/null \
    | awk -v b="refs/heads/$branch" '$1=="worktree"{w=$2} $1=="branch"&&$2==b{print w; exit}')"
  if [[ -n "$wt" ]]; then
    # shellcheck disable=SC2086
    ( cd "$wt" && ${LOOP_CMD:-true} start "$spec" >/dev/null 2>&1 )
    return $?
  fi
  # feat 브랜치 ref 가 없으면 확보 불가 — 엉뚱한 체크아웃 push 금지 불변식(거짓 성공 대신 비-0).
  ${GIT_CMD:-git} rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1 || return 1
  tmpwt="$(mktemp -d)/wt"
  # shellcheck disable=SC2086
  ${GIT_CMD:-git} worktree add --quiet "$tmpwt" "$branch" >/dev/null 2>&1 \
    || { rmdir "$(dirname "$tmpwt")" 2>/dev/null || true; return 1; }
  # shellcheck disable=SC2086
  ( cd "$tmpwt" && ${LOOP_CMD:-true} start "$spec" >/dev/null 2>&1 ); rc=$?
  # shellcheck disable=SC2086
  ${GIT_CMD:-git} worktree remove --force "$tmpwt" >/dev/null 2>&1 || true
  rmdir "$(dirname "$tmpwt")" 2>/dev/null || true
  return $rc
}

# ===== 리뷰 메타 파싱 (사람/head 게이트 전용) =====
rl_review_field() {
  # shellcheck disable=SC2086
  $REVIEW_FETCH_CMD "$1" 2>/dev/null | grep -i -m1 "^$2:" | sed -E "s/^[^:]*:[[:space:]]*//"
}
rl_review_state()  { rl_review_field "$1" state; }
rl_review_author() { rl_review_field "$1" author; }
rl_review_head()   { rl_review_field "$1" head; }
rl_review_verdict() { rl_review_field "$1" verdict; }
# rl_review_findings <pr> — PR 인라인 지적을 한 줄씩(빈 줄 제외). forge rework brief(must_adopt) 원천.
rl_review_findings() {
  # shellcheck disable=SC2086
  $REVIEW_FETCH_CMD "$1" 2>/dev/null | grep -i '^finding:' | sed -E 's/^[^:]*:[[:space:]]*//' | sed '/^$/d'
}

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
    # #571: approve 기록 후 같은 head 에 뒤늦게 도착한 신뢰봇 미해결 스레드(봇 게시 순서 레이스)는
    #   fetch 판정이 changes(현재 head 공식 재리뷰 실재 증거 동반 — #549 가드 경유)로 나타난다.
    #   이때 no-op(rc=20) 하면 새 커밋은 rework 만이 만들 수 있어 영구 교착 — 게이트를 통과시켜
    #   아래 verdict 분기가 재작업 라운드를 시작하게 한다. 재작업 진입이 verdict 기록을
    #   request_changes 로 바꾸므로 같은 head 재평가는 1회로 수렴하고, 무한 라운드는 기존 세 가드
    #   (라운드 상한·무진전·핑퐁)에 귀속된다. pending(#549 재매핑 추정)과 조회 실패 합성 changes
    #   (fetchfail — 실재 증거 아님)는 그대로 대기.
    local rec_verdict gate_verdict=""
    rec_verdict="$(int_get_verdict "$rd" "$key")"
    [[ "$rec_verdict" == "approve" ]] && gate_verdict="$(rl_review_verdict "$pr")"
    if [[ "$rec_verdict" == "approve" && "$gate_verdict" == "changes" \
          && -z "$(rl_review_field "$pr" fetchfail)" ]]; then
      int_log "$rd" "$key" "head 동일($head)이나 approve 기록 후 미해결 신뢰봇 스레드 도착 — 재평가(재작업 진입)"
    # #600: approve 기록 후 같은 head 에 신뢰봇 미해결 스레드가 승인을 가리는데(blocked=1, #493) 현재
    #   head 공식 재리뷰 증거가 없어 판정이 pending(#549 — 재작업 채택 금지)인 조합은, 승인·재작업·새
    #   커밋 모두 막힌 3자 교착이다. 폴링 상한까지 무행동 대기(rc=20 반복) 대신 근거 있는 에스컬레이션
    #   으로 유한 시간 내 종착한다 — #493(승인 가림)·#549(증거 없는 재작업 금지)는 그대로 보존.
    elif [[ "$rec_verdict" == "approve" && "$gate_verdict" == "pending" \
          && "$(rl_review_field "$pr" blocked)" == "1" ]]; then
      rl_escalate "$rd" "$key" "approve 기록 후 같은 head($head)의 신뢰봇 미해결 스레드가 승인을 가리나 현재 head 재리뷰 증거 없음(#549) — 재작업·머지 모두 불가 교착, 스레드 해소·수동 개입 필요"
      return 10
    # #627: 머지 게이트 차단(phase=blocked) 후 재진입은 integration 이 phase 를 review 로 재설정한다.
    #   이때 head 불변+판정 approve 조합이 else(rc=20) 로 떨어지면 approved 재전이 경로가 없어 폴링
    #   상한까지 무행동 대기 — approved 로 재전이해 머지로 복귀시킨다(유한 종착). phase==review 로
    #   좁혀 의도한 강등 시나리오만 겨냥한다 — approved 정상 멱등(rc=20)을 보존하고, merged/merging
    #   등에서의 직접 재호출이 phase 를 역행시키지 않는다.
    elif [[ "$rec_verdict" == "approve" && "$gate_verdict" == "approve" \
          && "$(int_get_phase "$rd" "$key")" == "review" ]]; then
      int_set_phase "$rd" "$key" approved
      int_log "$rd" "$key" "head 동일($head)·판정 approve 인데 phase 강등 상태 — approved 재전이(머지 복귀, #627)"
      return 30
    else
      int_log "$rd" "$key" "head 동일($head) — 새 커밋 없음, 라운드 미시작"
      return 20
    fi
  fi

  # --- PR 리뷰 판정(로컬 review 스킬 미호출) — verdict 는 PR 승인 상태/마커, 지적은 PR 인라인 코멘트 ---
  local verdict; verdict="$(rl_review_verdict "$pr")"
  case "$verdict" in
    approve)
      int_set_verdict "$rd" "$key" approve
      int_set_head "$rd" "$key" "$head"
      int_set_phase "$rd" "$key" approved
      int_log "$rd" "$key" "PR 승인(상태/마커) — 머지 진행가능 전이(추가 라운드 미시작)"
      return 30 ;;
    changes) : ;;
    *)
      int_log "$rd" "$key" "PR 리뷰 미판정(verdict='${verdict:-none}') — 대기(새 판정 없음)"
      return 20 ;;
  esac

  # --- changes: PR 인라인 지적을 rework brief(must_adopt)로 같은 브랜치 위 재구현 ---
  # 타당성 분류(반드시 반영/후속/미반영)는 워커가 change-adoption 으로 판단한다(여기선 지적을 전달만).
  int_set_verdict "$rd" "$key" request_changes
  local round; round="$(int_bump_review_round "$rd" "$key")"
  int_log "$rd" "$key" "재작업 라운드 $round 시작 (PR 변경요청 head=$head)"
  if [[ "$round" -gt "$REVIEW_ROUNDS_MAX" ]]; then
    rl_escalate "$rd" "$key" "라운드 상한($REVIEW_ROUNDS_MAX) 초과 — 자동수정 중지"
    return 10
  fi
  int_set_head "$rd" "$key" "$head"

  local mustfile; mustfile="$rd/must.$key.$pr"
  rl_review_findings "$pr" > "$mustfile"
  if [[ ! -s "$mustfile" ]]; then
    rl_escalate "$rd" "$key" "변경요청인데 채택할 PR 인라인 지적 0 — 무진전"
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

  local delta; delta="$(rl_spec_delta "$rd" "$key" "$base" "$pr" "$mustfile")"
  # 구현이 작업 브랜치에서 실패하면 거짓 성공·엉뚱한 push 대신 에스컬레이션(자동수정 보류).
  # 갭Z: rework 를 유발한 PR 인라인 finding(must)을 reason 에 표면화 — 정당한 차단성 escalate 임을
  #   오케스트레이터가 식별해 'false escalation' 오진·수동 머지 우회를 막는다.
  # shellcheck disable=SC2086
  if ! $IMPLEMENT_CMD "$delta" "$branch"; then
    local fz; fz="$(tr '\n' ';' < "$mustfile" | sed -E 's/;+$//; s/;/; /g')"
    rl_escalate "$rd" "$key" "재구현 실패 — 작업 브랜치($branch) 워크트리 확보 불가(자동수정 보류). 유발 finding: $fz"
    return 10
  fi
  in_push_branch "$branch"
  int_log "$rd" "$key" "라운드 $round: PR 지적 구현 → 같은 head 브랜치($branch) push. 재리뷰는 다음 드레인."
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
# direct 서브모드 리뷰 — forge 미구성(PR 없음) 환경의 적대적 리뷰 게이트.
#   forge 리뷰 루프 기계(생산자 1회 호출·must 재구현·세 가드·defer 분리·SPEC 델타)를
#   그대로 재사용하되, PR 의존(사람/PR 메타 게이트·원격 push)을 제거한다:
#     - 판정: 리뷰 생산자(REVIEW_PRODUCE_CMD)를 키 기준 1회 호출(로컬 작업 브랜치 diff 리뷰).
#     - 멱등 head 게이트: 원격/PR 메타가 아니라 로컬 작업 브랜치 HEAD 로 본다.
#     - request_changes: must 를 SPEC 델타로 로컬 작업 브랜치 위 재구현(원격 push 없음).
#     - approve: 머지 진행가능(호출자가 phase=merging 으로 전이).
#   세 가드(라운드 상한·무진전·핑퐁)는 forge 경로와 동일 헬퍼로 공유한다.
# =====================================================================

# rl_local_head <branch> — 로컬 작업 브랜치 HEAD(원격·PR 조회 없음). 없으면 빈값.
rl_local_head() {
  # shellcheck disable=SC2086
  $GIT_CMD rev-parse --verify --quiet "refs/heads/$1" 2>/dev/null
}

# rl_round_direct <run_dir> <key> <base-spec> <branch>
#   반환: 0=재작업(로컬 재구현), 10=에스컬레이션, 20=대기(새 커밋 없음), 30=approve.
rl_round_direct() {
  local rd="$1" key="$2" base="$3" branch="$4"
  mkdir -p "$rd"
  local pr="local"   # PR 없음 — 파일 네이밍용 고정 토큰(원격 PR 미참조).

  # --- 멱등 head 게이트 — 로컬 작업 브랜치 HEAD(사람/PR 메타 게이트는 PR 없으므로 미적용) ---
  local head last
  head="$(rl_local_head "$branch")"
  last="$(int_get_head "$rd" "$key")"
  if [[ -n "$head" && "$head" == "$last" ]]; then
    int_log "$rd" "$key" "head 동일($head) — 새 커밋 없음, 라운드 미시작(direct)"
    return 20
  fi

  # --- 리뷰 생산자 1회 호출 → 단일 판정(PR 없이 키 기준, 로컬 diff 리뷰) ---
  local produce verdict
  # shellcheck disable=SC2086
  produce="$($REVIEW_PRODUCE_CMD "$key" 2>/dev/null)"
  verdict="$(printf '%s' "$produce" | jq -r '.pipeline_verdict // ""' 2>/dev/null)"

  case "$verdict" in
    unavailable)
      rl_escalate "$rd" "$key" "리뷰 판정 unavailable(diff 잘림·컨텍스트 불완전) — 자동수정 보류(direct)"
      return 10 ;;
    approve)
      int_set_verdict "$rd" "$key" approve
      int_set_head "$rd" "$key" "$head"
      int_log "$rd" "$key" "리뷰 판정 approve(direct) — 머지 진행가능(추가 라운드 미시작)"
      return 30 ;;
    request_changes) : ;;
    *)
      if [[ -z "$produce" ]]; then
        rl_escalate "$rd" "$key" "리뷰 생산자 출력 비었음(생산 실패·미설정) — 자동수정 보류(direct)"
      else
        rl_escalate "$rd" "$key" "리뷰 판정 미상(verdict='$verdict') — 생산자 출력 파싱 실패(direct)"
      fi
      return 10 ;;
  esac

  # --- request_changes: 재작업 라운드(세 가드 공유) ---
  int_set_verdict "$rd" "$key" request_changes
  local round; round="$(int_bump_review_round "$rd" "$key")"
  int_log "$rd" "$key" "재작업 라운드 $round 시작(direct, verdict=request_changes head=$head)"
  if [[ "$round" -gt "$REVIEW_ROUNDS_MAX" ]]; then
    rl_escalate "$rd" "$key" "라운드 상한($REVIEW_ROUNDS_MAX) 초과 — 자동수정 중지(direct)"
    return 10
  fi
  int_set_head "$rd" "$key" "$head"

  local mustfile deferfile
  mustfile="$rd/must.$key.$pr"; deferfile="$rd/defer.$key.$pr"
  rl_produce_extract "$produce" must_adopt "$mustfile"
  rl_produce_extract "$produce" defer      "$deferfile"

  if [[ ! -s "$mustfile" ]]; then
    rl_escalate "$rd" "$key" "must_adopt 0 인데 여전히 request_changes — 무진전(direct)"
    return 10
  fi

  local bh prev
  bh="$(rl_blocking_hash "$mustfile")"
  prev="$(int_get_blocking_hash "$rd" "$key")"
  if [[ -n "$prev" && "$bh" == "$prev" ]]; then
    rl_escalate "$rd" "$key" "차단성 지적 집합이 직전 라운드와 동일(핑퐁) — 무한루프 차단(direct)"
    return 10
  fi
  int_set_blocking_hash "$rd" "$key" "$bh"

  rl_spinoff_backlog "$rd" "$key" "$pr" "$deferfile"

  local delta; delta="$(rl_spec_delta "$rd" "$key" "$base" "$pr" "$mustfile")"
  # 로컬 작업 브랜치 워크트리에서 재구현(원격 push 없음). 실패 시 거짓 성공 대신 에스컬레이션.
  # shellcheck disable=SC2086
  if ! $IMPLEMENT_CMD "$delta" "$branch"; then
    rl_escalate "$rd" "$key" "재구현 실패 — 작업 브랜치($branch) 워크트리에서 구현 불가(direct, 자동수정 보류)"
    return 10
  fi
  int_log "$rd" "$key" "라운드 $round: must 로컬 재구현(원격 push·PR 없음, 작업 브랜치=$branch). 재리뷰는 다음 드레인."
  return 0
}

# rl_review_loop_direct <run_dir> <key> <base-spec> [branch] — direct 단일 라운드 진입.
#   approve 면 phase=merging 으로 전이(승인 의례 없이 머지 헬퍼가 skip_approval 로 머지).
rl_review_loop_direct() {
  local rd="$1" key="$2" base="$3" branch="${4:-}"
  [[ -n "$rd" && -n "$key" && -n "$base" ]] \
    || { rl_die "사용: review-loop.sh run-direct <run_dir> <key> <spec> [branch]"; return 1; }
  mkdir -p "$rd"
  [[ -n "$branch" ]] || branch="$(int_get_branch "$rd" "$key")"
  [[ -n "$branch" ]] || branch="$(in_work_branch "$(basename "$rd")" "$base")"
  int_set_branch "$rd" "$key" "$branch"

  rl_round_direct "$rd" "$key" "$base" "$branch"
  case "$?" in
    30) int_set_phase "$rd" "$key" merging
        echo "review-loop(direct): approve — 머지 진행가능 (key=$key branch=$branch)"; return 0 ;;
    0)  echo "review-loop(direct): 재작업 라운드 — 로컬 재구현 (key=$key branch=$branch)"; return 0 ;;
    20) echo "review-loop(direct): 대기 — 새 커밋 없음 (key=$key branch=$branch)"; return 0 ;;
    *)  echo "review-loop(direct): 에스컬레이션으로 종료 (key=$key branch=$branch)"; return 0 ;;
  esac
}

# =====================================================================
# selftest — mock 인터페이스로 판정 분기·세 가드·사람/head 게이트·force 미사용 검증.
# =====================================================================
rl_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local rd="$TMP/.autopilot/runs/run1"; mkdir -p "$rd"

  # mock git: force 보면 exit99. push 기록.
  local PUSHLOG="$TMP/pushlog"; : > "$PUSHLOG"
  mock_git() {
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    case "$1" in
      push)      printf '%s\n' "$*" >> "$PUSHLOG" ;;
      rev-parse) printf '%s\n' "${MOCK_HEAD:-}" ;;   # direct 로컬 작업 브랜치 HEAD 모사.
    esac
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

  # forge_review <head> <verdict:approve|changes|pending> [finding...] — PR 리뷰 구동 mock(로컬 review 미사용).
  forge_review() {
    local head="$1" verdict="$2"; shift 2
    printf 'state: NONE\nauthor: \nhead: %s\nverdict: %s\n' "$head" "$verdict"
    local f; for f in "$@"; do printf 'finding: %s\n' "$f"; done
  }
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

  # ---- forge: changes(PR 인라인 지적) + 새 head → 재작업 라운드(구현·재푸시), 로컬 review 미호출 ----
  local kA="a-aaa1"
  forge_review sha-AAA changes '보안 입력 검증 추가' > "$RV/101.review"
  rl_round "$rd" "$kA" "$base" 101 "feat/run1-a"; rc=$?
  chk "changes 라운드 수행(rc=0)" "$rc" "0"
  chk "라운드 카운터=1" "$(int_review_round "$rd" "$kA")" "1"
  [[ -s "$IMPLLOG" ]] && ok "구현 실행됨" || bad "구현 실행됨"
  grep -q 'feat/run1-a' "$PUSHLOG" && ok "같은 head 브랜치 push" || bad "같은 head 브랜치 push"
  chk "head 처리 표시" "$(int_get_head "$rd" "$kA")" "sha-AAA"
  delta="$rd/delta.$kA.101.spec.md"
  grep -q '보안 입력 검증' "$delta" && ok "PR 지적 델타 반영" || bad "PR 지적 델타 반영"
  # 같은 head 재호출 → no-op(rc=20).
  rl_round "$rd" "$kA" "$base" 101 "feat/run1-a"; chk "동일 head 미시작(rc=20)" "$?" "20"

  # ---- 재구현 실패 → 거짓 성공·엉뚱한 push 대신 에스컬레이션 ----
  local kF="f-fff9"
  forge_review sha-FFF changes '구현 불가 항목' > "$RV/119.review"
  out="$(IMPLEMENT_CMD='false' rl_round "$rd" "$kF" "$base" 119 "feat/run1-f" 2>/dev/null)"; rc=$?
  chk "구현 실패 → 에스컬레이션(rc=10)" "$rc" "10"
  if grep -q 'feat/run1-f' "$PUSHLOG"; then bad "구현 실패인데 push 함"; else ok "구현 실패 → push 안 함"; fi
  # 갭Z: rework 유발 finding 을 escalate reason 에 표면화(정상 차단을 오케스트레이터가 식별).
  case "$out" in *구현\ 불가\ 항목*) ok "갭Z 재구현 실패 escalate 에 유발 finding 포함";; *) bad "갭Z 재구현 실패 escalate 에 유발 finding 포함 (out='$out')";; esac

  # ---- 갭X: detached 구현 워크트리 + 존재하는 feat 브랜치 → rework 가 feat 브랜치 워크트리 확보 ----
  #   selftest 는 IMPLEMENT_CMD 를 mock 으로 두지만, 이 케이스는 실제 rl_implement_loop 를 진짜 git
  #   으로 구동해 detached 구현 워크트리에서도 feat 브랜치를 대상으로 loop 가 도는지 검증한다(갭X 회귀 가드).
  local GX; GX="$(mktemp -d)"
  ( cd "$GX"
    git init -q && git config user.email t@t && git config user.name t || exit 1
    git commit -q --allow-empty -m init
    git branch feat/gx                              # 통합이 생성한 로컬 feat ref(어디에도 미체크아웃)
    git worktree add -q --detach "$GX/impl" HEAD    # 구현 워크트리 = detached HEAD
    printf '#!/usr/bin/env bash\ngit rev-parse --abbrev-ref HEAD > "%s/branch.seen"\n' "$GX" > "$GX/loopmock"
    chmod +x "$GX/loopmock"
    cd "$GX/impl"                                   # 현실 시나리오: detached 구현 워크트리 안에서 호출
    GIT_CMD=git LOOP_CMD="$GX/loopmock" rl_implement_loop "$GX/spec.md" feat/gx )
  if [[ "$(cat "$GX/branch.seen" 2>/dev/null)" == "feat/gx" ]]; then
    ok "갭X detached 워크트리에서 feat 브랜치 확보 후 rework"
  else
    bad "갭X detached 워크트리에서 feat 브랜치 확보 후 rework (seen='$(cat "$GX/branch.seen" 2>/dev/null)')"
  fi
  # feat 브랜치 ref 부재 → 확보 불가 → 비-0(엉뚱한 체크아웃 push 금지 불변식 보존).
  ( cd "$GX" && GIT_CMD=git LOOP_CMD="$GX/loopmock" rl_implement_loop "$GX/spec.md" feat/nope ); rc=$?
  chk "갭X feat 브랜치 부재 → 확보 불가(비-0)" "$rc" "1"
  rm -rf "$GX"

  # ---- approve(PR 상태/마커) → 머지 진행가능, 추가 라운드·구현 미시작(로컬 review 미호출) ----
  local kB="b-bbb2"; : > "$IMPLLOG"
  forge_review sha-B approve > "$RV/107.review"
  rl_round "$rd" "$kB" "$base" 107 "feat/run1-b"; rc=$?
  chk "approve rc=30" "$rc" "30"
  chk "판정 기록=approve" "$(int_get_verdict "$rd" "$kB")" "approve"
  chk "phase=approved" "$(int_get_phase "$rd" "$kB")" "approved"
  chk "추가 라운드 미시작" "$(int_review_round "$rd" "$kB")" "0"
  [[ ! -s "$IMPLLOG" ]] && ok "approve 시 구현 미위임" || bad "approve 시 구현 미위임"
  rl_round "$rd" "$kB" "$base" 107 "feat/run1-b"; chk "approve 멱등(rc=20)" "$?" "20"

  # ---- #571: approve 기록 후 같은 head 에 뒤늦게 도착한 blocking 스레드 → 재작업(영구 교착 아님) ----
  #   봇 게시 순서 레이스: 승인 마커 먼저 기록(rc=30, head 처리됨) → 같은 head 에 신뢰봇 미해결
  #   인라인 스레드 도착(공식 재리뷰 실재 증거 동반 → fetch 판정 changes). head 멱등 게이트가
  #   verdict 재평가보다 먼저 no-op(rc=20) 처리하면 새 커밋을 만들 주체가 없어 영구 교착한다.
  local kL="l-lll5"; : > "$IMPLLOG"
  forge_review sha-L approve > "$RV/108.review"
  rl_round "$rd" "$kL" "$base" 108 "feat/run1-l"; chk "#571 선행 approve(rc=30)" "$?" "30"
  forge_review sha-L changes '늦게 도착한 차단 지적' > "$RV/108.review"
  rl_round "$rd" "$kL" "$base" 108 "feat/run1-l"; rc=$?
  chk "#571 같은 head approve 기록 후 changes → 재작업 라운드(rc=0)" "$rc" "0"
  [[ -s "$IMPLLOG" ]] && ok "#571 재작업 구현 실행됨" || bad "#571 재작업 구현 실행됨"
  # 재작업 진입이 verdict 기록을 request_changes 로 바꿔 같은 head 재평가는 1회 수렴 — 재호출 no-op.
  rl_round "$rd" "$kL" "$base" 108 "feat/run1-l"; chk "#571 재작업 후 같은 head 재호출 no-op(rc=20)" "$?" "20"
  # approve 기록 + 현재 판정 pending(#549 재매핑 추정·증거 없음) → 재평가 아닌 대기 유지(가드 보존).
  local kL2="l2-lll6"
  forge_review sha-L2 approve > "$RV/109.review"
  rl_round "$rd" "$kL2" "$base" 109 "feat/run1-l2" >/dev/null
  forge_review sha-L2 pending > "$RV/109.review"
  rl_round "$rd" "$kL2" "$base" 109 "feat/run1-l2"; chk "#571 approve 기록+pending → 대기(rc=20, #549 보존)" "$?" "20"
  # approve 기록 + 인라인 조회 실패(default-deny 합성 changes, fetchfail 마커) → 실재 증거가 아니므로
  #   재평가하지 않고 대기 — 일시적 API 오류가 처리 불가능한 합성 finding 재작업 라운드를 소모하지 않는다.
  local kL3="l3-lll7"; : > "$IMPLLOG"
  forge_review sha-L3 approve > "$RV/111.review"
  rl_round "$rd" "$kL3" "$base" 111 "feat/run1-l3" >/dev/null
  printf 'state: NONE\nauthor: \nhead: sha-L3\nverdict: changes\nfetchfail: 1\nfinding: 미해결 리뷰 스레드 조회 실패 — default-deny(보수적 차단), 확인 필요\n' > "$RV/111.review"
  rl_round "$rd" "$kL3" "$base" 111 "feat/run1-l3"; chk "#571 approve 기록+조회 실패 changes → 대기(rc=20, 합성 finding 재작업 금지)" "$?" "20"
  [[ ! -s "$IMPLLOG" ]] && ok "#571 조회 실패 시 재작업 미실행" || bad "#571 조회 실패 시 재작업 미실행"

  # ---- #600: approve 기록+pending+blocked(3자 교착 — rl_round 게이트 주석 참조) → 에스컬레이션 ----
  local kL4="l4-lll8"; : > "$IMPLLOG"
  forge_review sha-L4 approve > "$RV/112.review"
  rl_round "$rd" "$kL4" "$base" 112 "feat/run1-l4" >/dev/null
  printf 'state: NONE\nauthor: \nhead: sha-L4\nblocked: 1\nverdict: pending\n' > "$RV/112.review"
  out="$(rl_round "$rd" "$kL4" "$base" 112 "feat/run1-l4")"; rc=$?
  chk "#600 approve 기록+pending+blocked → 에스컬레이션(rc=10, 무행동 대기 아님)" "$rc" "10"
  chk "#600 phase=escalated" "$(int_get_phase "$rd" "$kL4")" "escalated"
  case "$out" in *교착*) ok "#600 교착 사유 표면화";; *) bad "#600 교착 사유 표면화 (out='$out')";; esac
  [[ ! -s "$IMPLLOG" ]] && ok "#600 증거 없는 스레드 재작업 미실행(#549 보존)" || bad "#600 증거 없는 스레드 재작업 미실행(#549 보존)"

  # ---- #627: approve 기록+같은 head+판정 approve 인데 phase 가 강등된 상태 → approved 재전이 ----
  #   머지 게이트 차단(phase=blocked) 후 재진입하면 integration 이 phase=review 로 재설정한다.
  #   이때 head 불변+판정 approve 조합이 rc=20 무한 반복하면 머지 복귀가 영구 불가 — 재전이로 종착.
  local kM="m-mmm3"; : > "$IMPLLOG"
  forge_review sha-M approve > "$RV/113.review"
  rl_round "$rd" "$kM" "$base" 113 "feat/run1-m"; chk "#627 선행 approve(rc=30)" "$?" "30"
  int_set_phase "$rd" "$kM" review   # 머지 게이트 차단 후 재진입이 phase 를 review 로 강등한 상황 모사
  rl_round "$rd" "$kM" "$base" 113 "feat/run1-m"; rc=$?
  chk "#627 같은 head approve/approve+phase 강등 → approved 재전이(rc=30, rc=20 반복 아님)" "$rc" "30"
  chk "#627 재전이 후 phase=approved" "$(int_get_phase "$rd" "$kM")" "approved"
  [[ ! -s "$IMPLLOG" ]] && ok "#627 재전이 시 구현 미위임" || bad "#627 재전이 시 구현 미위임"
  # phase=approved 정상 상태의 같은 head 재호출은 기존 멱등 유지(rc=20) — kB 케이스와 동일 계약.
  rl_round "$rd" "$kM" "$base" 113 "feat/run1-m"; chk "#627 재전이 후 재호출 멱등(rc=20)" "$?" "20"
  # 재전이는 phase==review 강등 시나리오만 겨냥 — merged 등 다른 phase 를 approved 로 역행시키지 않는다.
  int_set_phase "$rd" "$kM" merged
  rl_round "$rd" "$kM" "$base" 113 "feat/run1-m"; chk "#627 phase=merged 재호출 → 역행 없이 대기(rc=20)" "$?" "20"
  chk "#627 phase=merged 유지(approved 역행 안 함)" "$(int_get_phase "$rd" "$kM")" "merged"

  # ---- pending(승인X·지적X) → 대기(rc=20), 로컬 review 미호출 ----
  local kPd="pd-ppp0"
  forge_review sha-PD pending > "$RV/110.review"
  rl_round "$rd" "$kPd" "$base" 110 "feat/run1-pd"; rc=$?
  chk "pending rc=20(대기)" "$rc" "20"
  chk "pending 라운드 미증가" "$(int_review_round "$rd" "$kPd")" "0"

  # ---- 사람 리뷰어 변경요청(state CHANGES_REQUESTED) → 에스컬레이션 ----
  local kH="h-hhh4"
  printf 'state: CHANGES_REQUESTED\nauthor: human-dev\nhead: sha-H\nverdict: changes\nfinding: 사람 지적\n' > "$RV/102.review"
  out="$(rl_round "$rd" "$kH" "$base" 102 "feat/run1-h")"; rc=$?
  chk "사람=에스컬레이션(rc=10)" "$rc" "10"
  chk "사람 phase=escalated" "$(int_get_phase "$rd" "$kH")" "escalated"
  chk "사람 라운드 미증가" "$(int_review_round "$rd" "$kH")" "0"

  # ---- 라운드 상한(3) 초과 → 에스컬레이션 ----
  local kC="c-ccc6"
  int_set "$rd" "$kC" review-round 3
  forge_review sha-C4 changes '보안 또 수정' > "$RV/104.review"
  out="$(rl_round "$rd" "$kC" "$base" 104 "feat/run1-c")"; rc=$?
  chk "캡 초과 에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *상한*) ok "상한 사유";; *) bad "상한 사유";; esac

  # ---- changes 인데 채택할 인라인 지적 0 → 무진전 에스컬레이션 ----
  local kN="n-nnn7"
  printf 'state: NONE\nauthor: \nhead: sha-N\nverdict: changes\n' > "$RV/105.review"
  out="$(rl_round "$rd" "$kN" "$base" 105 "feat/run1-n")"; rc=$?
  chk "무진전 에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *무진전*) ok "무진전 사유";; *) bad "무진전 사유";; esac

  # ---- 핑퐁(차단성 집합 직전과 동일) → 에스컬레이션 ----
  local kP="p-ppp9"
  forge_review sha-P1 changes '보안 입력 검증 누락' > "$RV/106.review"
  rl_round "$rd" "$kP" "$base" 106 "feat/run1-p" >/dev/null; chk "핑퐁 1라운드 수행" "$?" "0"
  forge_review sha-P2 changes '보안 입력 검증 누락' > "$RV/106.review"
  out="$(rl_round "$rd" "$kP" "$base" 106 "feat/run1-p")"; rc=$?
  chk "핑퐁 에스컬레이션(rc=10)" "$rc" "10"
  case "$out" in *핑퐁*) ok "핑퐁 사유";; *) bad "핑퐁 사유";; esac

  # =====================================================================
  # direct 서브모드 리뷰 게이트 — PR 없는 로컬 작업 브랜치 리뷰(원격 push 없음).
  #   approve/request_changes/세 가드/unavailable 를 mock 으로 검증.
  # =====================================================================

  # ---- AC7: direct approve → phase=merging(승인 의례 없이 머지 진행가능), push 없음 ----
  local kDA="da-aaaa1" bp ap
  prod_simple sha-DA approve > "$RV/$kDA.produce"
  bp=$(wc -l < "$PUSHLOG")
  MOCK_HEAD=sha-DA rl_review_loop_direct "$rd" "$kDA" "$base" "feat/run1-da" >/dev/null; rc=$?
  chk "AC7 direct approve rc=0" "$rc" "0"
  chk "AC7 direct approve→phase=merging" "$(int_get_phase "$rd" "$kDA")" "merging"
  chk "AC7 direct verdict=approve" "$(int_get_verdict "$rd" "$kDA")" "approve"
  ap=$(wc -l < "$PUSHLOG")
  [[ "$bp" == "$ap" ]] && ok "AC9 direct approve 원격 push 없음" || bad "AC9 direct approve 원격 push 없음"

  # ---- AC8/AC9: direct request_changes → 로컬 재구현(push 없음), 라운드 카운터·델타 ----
  local kDR="dr-rrrr2"; : > "$IMPLLOG"
  prod_rc sha-DR '로컬 보안 검증 추가' > "$RV/$kDR.produce"
  bp=$(wc -l < "$PUSHLOG")
  MOCK_HEAD=sha-DR rl_round_direct "$rd" "$kDR" "$base" "feat/run1-dr"; rc=$?
  chk "AC8 direct request_changes 라운드 수행(rc=0)" "$rc" "0"
  chk "AC8 direct 라운드 카운터=1" "$(int_review_round "$rd" "$kDR")" "1"
  [[ -s "$IMPLLOG" ]] && ok "AC8 direct 로컬 재구현 실행" || bad "AC8 direct 로컬 재구현 실행"
  ap=$(wc -l < "$PUSHLOG")
  [[ "$bp" == "$ap" ]] && ok "AC9 direct 재구현 원격 push 없음" || bad "AC9 direct 재구현 원격 push 없음"
  delta="$rd/delta.$kDR.local.spec.md"
  grep -q '로컬 보안 검증' "$delta" && ok "AC8 direct must 델타 반영" || bad "AC8 direct must 델타 반영"
  # 같은 head 재호출 → no-op(rc=20).
  MOCK_HEAD=sha-DR rl_round_direct "$rd" "$kDR" "$base" "feat/run1-dr"; chk "AC8 direct 동일 head 미시작(rc=20)" "$?" "20"

  # ---- AC10 가드: direct 라운드 상한(3) 초과 → 에스컬레이션(머지 안 함) ----
  local kDC="dc-cccc3"
  int_set "$rd" "$kDC" review-round 3
  prod_rc sha-DC '또 수정' > "$RV/$kDC.produce"
  out="$(MOCK_HEAD=sha-DC rl_round_direct "$rd" "$kDC" "$base" "feat/run1-dc")"; rc=$?
  chk "AC10 direct 상한 초과 에스컬레이션(rc=10)" "$rc" "10"
  chk "AC10 direct phase=escalated" "$(int_get_phase "$rd" "$kDC")" "escalated"

  # ---- AC10 가드: direct must 0 인데 request_changes → 무진전 에스컬레이션 ----
  local kDN="dn-nnnn4"
  prod_rc_empty sha-DN > "$RV/$kDN.produce"
  out="$(MOCK_HEAD=sha-DN rl_round_direct "$rd" "$kDN" "$base" "feat/run1-dn")"; rc=$?
  chk "AC10 direct 무진전 에스컬레이션(rc=10)" "$rc" "10"

  # ---- AC10 가드: direct 핑퐁(차단성 집합 직전과 동일) → 에스컬레이션 ----
  local kDP="dp-pppp5"
  prod_rc sha-DP1 '같은 차단 지적' > "$RV/$kDP.produce"
  MOCK_HEAD=sha-DP1 rl_round_direct "$rd" "$kDP" "$base" "feat/run1-dp" >/dev/null; chk "AC10 direct 핑퐁 1R 수행" "$?" "0"
  prod_rc sha-DP2 '같은 차단 지적' > "$RV/$kDP.produce"
  out="$(MOCK_HEAD=sha-DP2 rl_round_direct "$rd" "$kDP" "$base" "feat/run1-dp")"; rc=$?
  chk "AC10 direct 핑퐁 에스컬레이션(rc=10)" "$rc" "10"

  # ---- AC7: direct unavailable → 에스컬레이션 ----
  local kDU="du-uuuu6"
  prod_simple sha-DU unavailable > "$RV/$kDU.produce"
  MOCK_HEAD=sha-DU rl_round_direct "$rd" "$kDU" "$base" "feat/run1-du" >/dev/null; rc=$?
  chk "AC7 direct unavailable 에스컬레이션(rc=10)" "$rc" "10"

  # =====================================================================
  # AC4/AC5/AC6: rl_review_fetch_gh — 현재 head 신뢰봇 **미해결 스레드(태그 무관, #493)** 가
  #   approve 를 가린다(verdict=approve → changes). gh 를 시나리오 변수 mock 으로 치환.
  #   SC_* 는 substitution 안에서 env-prefix 해야 함수 환경에 도달한다.
  # =====================================================================
  gh() {
    case "$1 $2" in
      "pr view")
        case "$*" in
          *"--json headRefOid"*)     printf '%s\n' "${SC_HEAD:-}" ;;
          *"--json reviewDecision"*) printf '%s\n' "${SC_DECISION:-}" ;;
          *"--json reviews"*)
            case "$*" in
              *'"\t"'*) printf '%b' "${SC_REVIEWS:-}" ;;                       # 마커 jq(login\tbody)
              *)        printf '%b' "${SC_SUMMARY:-state: NONE\nauthor: \n}" ;; # state/author 요약
            esac ;;
        esac ;;
      "repo view") printf '%s %s\n' "${SC_OWNER:-o}" "${SC_NAME:-n}" ;;
      "api graphql"|"api "*|api) [[ "${SC_API_FAIL:-}" == "1" ]] && return 1; printf '%s' "${SC_THREADS:-}" ;;
    esac
    return 0
  }
  # thr <isResolved> <login> <oid> <body> — 단일 리뷰 스레드 raw GraphQL JSON 빌더.
  thr() { printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":%s,"comments":{"nodes":[{"author":{"login":"%s"},"commit":{"oid":"%s"},"body":"%s"}]}}]}}}}}' "$1" "$2" "$3" "$4"; }
  rvg() { rl_review_fetch_gh "${1:-200}" 2>/dev/null | grep -i '^verdict:' | sed -E 's/^[^:]*:[[:space:]]*//'; }
  local GH="sha-GH"
  local GBLK; GBLK="$(thr false "github-actions[bot]" "$GH" "**[blocking/98] 차단 지적**")"
  local GOKC; GOKC="$(thr false "github-actions[bot]" "$GH" "**[non_blocking/85] 정보성**")"
  # 비승인 공식 리뷰 마커(verdict=comment) — 인라인 지적을 남긴 공식 재리뷰의 실재 증거(#549).
  local MARK_RC2="github-actions[bot]\t<!-- claude-formal-review head_sha=$GH verdict=comment -->\n"
  local MARK_RCOLD2="github-actions[bot]\t<!-- claude-formal-review head_sha=oldSHA verdict=comment -->\n"

  # 인라인 지적이 있는 케이스는 그 지적을 남긴 공식 재리뷰의 마커(MARK_RC2, #549 증거)를 동반한다
  #   — 실제 워크플로는 인라인 지적 제출 시 항상 verdict=comment 마커 리뷰를 함께 게시한다.
  chk "AC4 approve+head [blocking] → changes" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_REVIEWS="$MARK_RC2" SC_THREADS="$GBLK" rvg)" "changes"
  # #493: 미해결이면 태그 무관 차단 — approve 라도 미해결 non_blocking 스레드는 changes 로 표면화.
  chk "approve+미해결 non_blocking(정보성) → changes(태그 무관)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_REVIEWS="$MARK_RC2" SC_THREADS="$GOKC" rvg)" "changes"
  # #493: 태그 없는 미해결 스레드도 차단(차단 판정이 태그에 의존하지 않음).
  chk "approve+태그없는 미해결 스레드 → changes" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_REVIEWS="$MARK_RC2" SC_THREADS="$(thr false "github-actions[bot]" "$GH" "태그 없는 일반 코멘트")" rvg)" "changes"
  chk "AC4 비승인+head [blocking] → changes" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$GH" SC_REVIEWS="$MARK_RC2" SC_THREADS="$GBLK" rvg)" "changes"
  chk "resolved 스레드 [blocking]+approve → approve(차단 안 함)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_THREADS="$(thr true "github-actions[bot]" "$GH" "**[blocking/98] 해결됨**")" rvg)" "approve"
  chk "pagination: 2페이지의 [blocking]+approve → changes" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_REVIEWS="$MARK_RC2" SC_THREADS="$(thr false "github-actions[bot]" "$GH" "**[non_blocking/80] 1p**")$(thr false "github-actions[bot]" "$GH" "**[blocking/98] 2p**")" rvg)" "changes"
  chk "AC3 outdated [blocking]+approve → approve(차단 안 함)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_THREADS="$(thr false "github-actions[bot]" "oldSHA" "**[blocking/98] 이전**")" rvg)" "approve"
  chk "AC3 비신뢰봇 [blocking]+approve → approve(차단 안 함)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_THREADS="$(thr false "random-human" "$GH" "**[blocking/98] 위조**")" rvg)" "approve"
  # #432: 봇 로그인 정규식을 login 필드 단독에 적용해야 앵커가 성립 — 결합 라인 grep 회귀 가드.
  #   GEMPTY: 미해결 스레드 없음(blocking·findings 공히 비어 마커 경로만 격리).
  local GEMPTY='{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}'
  local MARK_GA2="github-actions[bot]\t<!-- claude-formal-review head_sha=$GH verdict=approve -->\n"
  local MARK_CX2="codex[bot]\t<!-- codex-formal-review head_sha=$GH verdict=approve -->\n"
  local MARK_EVIL2="evil-user\t<!-- forged head_sha=$GH verdict=approve -->\n"
  local MARK_OLD2="github-actions[bot]\t<!-- claude-formal-review head_sha=oldSHA verdict=approve -->\n"
  chk "#432 github-actions[bot] 마커승인 → approve" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$GH" SC_REVIEWS="$MARK_GA2" SC_THREADS="$GEMPTY" rvg)" "approve"
  chk "#432 codex[bot] 마커승인 → approve" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$GH" SC_REVIEWS="$MARK_CX2" SC_THREADS="$GEMPTY" rvg)" "approve"
  chk "#432 비신뢰(evil-user) 마커 → 미승인(pending)" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$GH" SC_REVIEWS="$MARK_EVIL2" SC_THREADS="$GEMPTY" rvg)" "pending"
  chk "#432 head 불일치 마커 → 미승인(pending)" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$GH" SC_REVIEWS="$MARK_OLD2" SC_THREADS="$GEMPTY" rvg)" "pending"
  # #549 거짓 핑퐁 가드: GitHub 는 과거 커밋의 미해결 인라인 코멘트 앵커가 살아 있으면 commit.oid 를
  #   최신 head 로 재매핑한다 — oid==head 만으로 "이번 head 재평가됨"을 뜻하지 않는다. 현재 head 에
  #   대한 신뢰봇 *-formal-review 마커(verdict 무관)가 없으면 재매핑 스레드를 새 차단 지적으로
  #   채택하지 않고 pending(대기)으로 보고한다.
  chk "#549 재리뷰 마커 없는 재매핑 스레드 → pending" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$GH" SC_THREADS="$GBLK" rvg)" "pending"
  chk "#549 구 head 마커만 존재(재매핑) → pending" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$GH" SC_REVIEWS="$MARK_RCOLD2" SC_THREADS="$GBLK" rvg)" "pending"
  chk "#549 approve 결정+마커 없는 재매핑 스레드 → pending(거짓 승인·거짓 changes 모두 아님)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_THREADS="$GBLK" rvg)" "pending"
  chk "#549 현재 head 재리뷰 마커(비승인) 존재+미해결 스레드 → changes(가드 유지)" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$GH" SC_REVIEWS="$MARK_RC2" SC_THREADS="$GBLK" rvg)" "changes"
  chk "AC5 인라인 조회 실패 → changes(default-deny)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_API_FAIL=1 rvg)" "changes"
  out="$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_API_FAIL=1 rl_review_fetch_gh 205 2>/dev/null)"
  case "$out" in *조회\ 실패*|*default-deny*) ok "AC5 조회 실패 finding 표면화";; *) bad "AC5 조회 실패 finding 표면화";; esac
  # #600: 승인 가림 pending 에 blocked=1 표면화(교착 식별 신호 — rl_round 게이트 주석 참조).
  chk "#600 approve 가림+증거 없음 → pending 에 blocked=1 표면화" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_THREADS="$GBLK" rl_review_fetch_gh 206 2>/dev/null | grep -c '^blocked: 1')" "1"
  chk "#600 스레드 없는 pending 은 blocked 미표면화" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$GH" SC_REVIEWS="$MARK_OLD2" SC_THREADS="$GEMPTY" rl_review_fetch_gh 207 2>/dev/null | grep -c '^blocked: 1')" "0"
  # #627: `*-bot` 접미 머신유저(예: courtesy-bot)도 신뢰봇 — GitHub App 이 아닌 실리뷰봇 계정 관례.
  #   미인식이면 blocked=0·reviewed=0 으로 approve 가 합성돼 승인 가림(#493)이 무력화된다.
  local MARK_CB="courtesy-bot\t<!-- claude-formal-review head_sha=$GH verdict=comment -->\n"
  local CBBLK; CBBLK="$(thr false "courtesy-bot" "$GH" "**[blocking/90] 실봇 차단 지적**")"
  chk "#627 courtesy-bot 미해결 스레드+approve → changes(approve 합성 금지)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_REVIEWS="$MARK_CB" SC_THREADS="$CBBLK" rvg)" "changes"
  chk "#627 courtesy-bot 마커승인 → approve" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$GH" SC_REVIEWS="courtesy-bot\t<!-- claude-formal-review head_sha=$GH verdict=approve -->\n" SC_THREADS="$GEMPTY" rvg)" "approve"
  # 배제 방향: `-bot` 접미가 아닌 계정(abbot)은 여전히 비신뢰 — 차단 게이트에 잡히지 않는다.
  chk "#627 비접미 계정(abbot) 스레드 → 차단 안 함(approve 유지)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$GH" SC_THREADS="$(thr false "abbot" "$GH" "**[blocking/90] 위조**")" rvg)" "approve"
  unset -f gh

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
    run)         shift; rl_review_loop "$@" ;;
    run-direct)  shift; rl_review_loop_direct "$@" ;;
    round)       shift; rl_round "$@" ;;
    round-direct) shift; rl_round_direct "$@" ;;
    selftest) rl_selftest ;;
    *) echo "usage: review-loop.sh {run <run_dir> <key> <spec> <pr> [branch]|run-direct <run_dir> <key> <spec> [branch]|round ...|round-direct <run_dir> <key> <spec> <branch>|selftest}" >&2; exit 1 ;;
  esac
fi
