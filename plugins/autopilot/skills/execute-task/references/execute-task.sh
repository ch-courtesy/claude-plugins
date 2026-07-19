#!/usr/bin/env bash
# execute-task.sh — 단일 태스크 전체 생애 드라이버 (구현→리뷰→머지→done).
#
# 책임(결정적 글루): 태스크 본문 materialize → in_progress + heartbeat lease →
#   loop.sh 로 구현(포그라운드) → DONE/BLOCKED 분류 → forge 어댑터로 integrate→review→merge →
#   백엔드 상태 전이(review/done/blocked). 의존성·DAG 는 다루지 않는다(workflow-task 가 fan-out).
#
# 재사용 엔진(런타임 호출, 그대로 둠): loop.sh(ralph), forge 어댑터(통합/리뷰/머지 엔진 래핑).
# 백엔드 연동: task-backend/adapter.sh. 무인 실행: 대화형 호출 없음, 차단은 blocked 상태+로그.
#
# 모킹: ADAPTER_CMD / LOOP_CMD / FORGE_CMD 환경변수로 엔진 치환(테스트).
set -euo pipefail

# 링크드 워크트리 안에서 호출할 때 --show-toplevel 은 워크트리 루트를 반환해 중첩 경로가 생긴다.
# worktree list --porcelain 의 첫 항목(항상 메인 워크트리)으로 메인 리포 루트를 확정하고,
# 구버전 git(< 2.7) 또는 git 미설치 환경은 --show-toplevel 으로 폴백한다.
ROOT_DIR="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10); exit}')" || true
[[ -n "$ROOT_DIR" ]] || ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PLUGIN="$ROOT_DIR/plugins/autopilot"
# 플러그인 자신이 소비처가 아닐 때(설치형): 스크립트 위치 기준으로도 해석
[[ -d "$PLUGIN" ]] || PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

ADAPTER_CMD="${ADAPTER_CMD:-bash $PLUGIN/lib/task-backend/adapter.sh}"
FORGE_CMD="${FORGE_CMD:-bash $PLUGIN/lib/forge/forge.sh}"
LOOP_CMD="${LOOP_CMD:-bash $PLUGIN/skills/loop/references/loop.sh}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-60}"
REVIEW_MAX="${REVIEW_MAX:-5}"
# 비동기 호스팅 리뷰 봇 승인 폴링(PR 경로). 봇 승인 게시 지연(관측 ~2.5분)을 상한 내에서 대기.
APPROVAL_WAIT_MAX="${APPROVAL_WAIT_MAX:-360}"          # 총 대기 상한(초, 논리 누적)
APPROVAL_POLL_INTERVAL="${APPROVAL_POLL_INTERVAL:-20}" # 폴링 간격(초)
APPROVAL_CHECK_CMD="${APPROVAL_CHECK_CMD:-et_approval_gh}"  # <pr> → 승인이면 rc0 (mock 치환 가능)
# 미해결 리뷰 스레드 가산 게이트(태그 무관, #493). <pr> → 차단 없음(clear)이면 rc0, 미해결 스레드 존재/조회실패면 rc1.
#   approval 신호와 AND 결합돼 승인 판정을 가린다(mock 치환 가능). merge.sh mg_blocking_inline_gate 미러.
BLOCKING_CHECK_CMD="${BLOCKING_CHECK_CMD:-et_blocking_inline_gh}"
SLEEP_CMD="${SLEEP_CMD:-sleep}"                        # 폴링 sleep (테스트 no-op 치환 가능)
# 신뢰 봇 로그인(.github/workflows/{codex,claude}-review.yml 컨벤션) — merge.sh mg_approval_gh 와 동일.
REVIEW_BOT_LOGINS_RE="${REVIEW_BOT_LOGINS_RE:-(\[bot\]$|^github-actions$|courtesy-bot)}"

die() { echo "execute-task: $*" >&2; exit 1; }

# et_reason_excerpt <text> — 실패 출력에서 백엔드 로그용 사유 발췌(마지막 20줄, 한 줄 평탄화).
#   integrate/merge 실패 사유가 stderr 로만 흘러 유실되는 무로그 blocked 방지(run 592).
et_reason_excerpt() { printf '%s\n' "$1" | tail -n 20 | tr '\n' ' '; }

# forge 단계 blocked 의 category 표면화(#600) — 자가개선 seam(using-autopilot 카테고리→행동 매핑)이
#   소비할 값을 blocked 로그 선두에 싣는다. 사유별 기계적 규칙(사이트 고정, 임의 판단 없음):
#     원격·브랜치·머지 게이트 등 환경 차단(integrate/merge 실패) → environment-gap
#     리뷰 수렴·판정 문제(review 진전 불가/미승인·폴링 상한)     → other (진단 후 분류)

# et_cleanup_dirs <dir>... — 주어진 디렉토리들을 정리(멱등, 부재·중복이어도 무해).
#   merge 성공 직후 정리와 done 선제 가드 정리(#541)가 공유하는 단일 출처.
#   대상: run-dir(.autopilot/runs/<id> — materialize SPEC·.worktree·run 상태, #580 통합),
#   리뷰 상태(<git-root>/.review/tasks/<id>, #528).
et_cleanup_dirs() {
  local d
  for d in "$@"; do rm -rf "$d" 2>/dev/null || true; done
}

# et_approval_gh <pr> — PR 호스팅 리뷰가 승인 상태면 0, 아니면 1.
#   승인 신호 두 가지(merge.sh mg_approval_gh / review-loop rl_review_fetch_gh 와 동일 컨벤션):
#     (a) 공식 APPROVE 리뷰 → reviewDecision==APPROVED.
#     (b) App 토큰 self-approve 불가로 APPROVE→COMMENT 강등된 신뢰 봇의 현재 head verdict=approve 마커.
#   머지 직전 merge.sh 의 단발 승인 게이트(미해결 리뷰 스레드 가산 차단 포함)가 재검증한다.
et_approval_gh() {
  local pr="$1" decision head
  [[ -n "$pr" ]] || return 1
  command -v gh >/dev/null 2>&1 || return 1
  decision="$(gh pr view "$pr" --json reviewDecision --jq '.reviewDecision' 2>/dev/null)"
  [[ "$decision" == "APPROVED" ]] && return 0
  head="$(gh pr view "$pr" --json headRefOid --jq '.headRefOid' 2>/dev/null)"
  [[ -n "$head" ]] || return 1
  # 봇 로그인 정규식(REVIEW_BOT_LOGINS_RE)은 **login 필드 단독**에 적용해야 앵커(\[bot\]$/
  #   ^github-actions$)가 성립한다. login\tbody 결합 라인에 grep 하면 본문이 탭 뒤에 이어져
  #   앵커가 영영 깨진다(#432). et_blocking_inline_gh 와 동일 컨벤션으로 awk 가 현재 head 의
  #   verdict=approve 마커를 가진 리뷰의 login 만 추출 → 그 login 을 신뢰봇 grep.
  gh pr view "$pr" --json reviews \
       --jq '.reviews[] | (.author.login // "") + "\t" + ((.body // "")|gsub("[\n\t]";" "))' 2>/dev/null \
     | awk -F'\t' -v h="$head" '$2 ~ ("head_sha=" h "[^>]*verdict=approve") {print $1}' \
     | grep -qE "$REVIEW_BOT_LOGINS_RE"
}

# et_blocking_inline_gh <pr> — 현재 head 에 신뢰봇이 남긴 **미해결**(isResolved=false) 리뷰 스레드가
#   없으면 0(clear=머지 가능), 하나라도 있으면 1(차단=대기) — 태그 무관(#493).
#   merge.sh mg_blocking_inline_gate / review-loop.sh 와 동일 컨벤션(commit.oid==head, 신뢰봇 로그인).
#   게이트는 스레드를 **스스로 resolve 하지 않는다** — resolved 전이는 봇/리뷰어
#   책임이고 여기선 폴링으로 관찰만 한다. head/owner·name 미확정·조회/파싱 실패는 보수적 차단
#   (default-deny=1)하되, 호출자(폴링 루프)의 상한과 결합돼 영구 멈춤은 없다.
et_blocking_inline_gh() {
  local pr="$1" head on owner name raw out
  [[ -n "$pr" ]] || return 1
  command -v gh >/dev/null 2>&1 || return 1
  head="$(gh pr view "$pr" --json headRefOid --jq '.headRefOid' 2>/dev/null)"
  [[ -n "$head" ]] || return 1   # head 미확정 → 보수적 차단
  on="$(gh repo view --json owner,name --jq '.owner.login+" "+.name' 2>/dev/null)" || on=""
  owner="${on%% *}"; name="${on##* }"
  [[ -n "$owner" && -n "$name" ]] || return 1   # repo 미확정 → 보수적 차단
  # 모든 reviewThreads 페이지를 --paginate(pageInfo+after:$endCursor)로 따라간다(100개 초과 누락 방지).
  raw="$(gh api graphql --paginate -F owner="$owner" -F name="$name" -F pr="$pr" -f query='
query($owner:String!,$name:String!,$pr:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){
    pullRequest(number:$pr){
      reviewThreads(first:100, after:$endCursor){
        pageInfo{hasNextPage endCursor}
        nodes{isResolved comments(first:100){nodes{author{login} commit{oid} body}}}
      }
    }}}' 2>/dev/null)"
  [[ -n "$raw" ]] || return 1   # 조회 실패 → 보수적 차단
  # 미해결(isResolved=false) 스레드의 코멘트만: login\tcommit_oid\tbody.
  out="$(printf '%s' "$raw" | jq -r '
        .data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved==false)
        | .comments.nodes[]
        | (.author.login // "")+"\t"+(.commit.oid // "")+"\t"+((.body // "")|gsub("[\n\t]";" "))' 2>/dev/null)" \
    || return 1   # 파싱 실패 → 보수적 차단
  # 미해결 + 현재 head 대응(field2==head) 줄의 login 을 신뢰봇 grep(태그 무관, #493).
  if printf '%s\n' "$out" \
       | awk -F'\t' -v h="$head" '$2==h {print $1}' \
       | grep -qE "$REVIEW_BOT_LOGINS_RE"; then
    return 1   # 신뢰봇 미해결 리뷰 스레드 존재 → 차단
  fi
  return 0
}

HB_PID=""
PARENT_ALIVE_FILE=""
cleanup_hb() {
  [[ -n "${HB_PID:-}" ]] && kill "$HB_PID" 2>/dev/null || true
  [[ -n "${PARENT_ALIVE_FILE:-}" ]] && rm -f "$PARENT_ALIVE_FILE" 2>/dev/null || true
}
trap cleanup_hb EXIT

et_start() {
  local id="" stop_at=""
  while [[ $# -gt 0 ]]; do case "$1" in
    --stop-at) stop_at="$2"; shift 2;;
    -*) shift;;
    *) [[ -z "$id" ]] && id="$1"; shift;;
  esac; done
  [[ -n "$id" ]] || die "start <task-id> [--stop-at review]"

  # done 선제 가드(#541): 백엔드 status 가 이미 done 이면 파이프라인을 재실행하지 않고 잔존
  #   .autopilot/runs/<id>/ 만 멱등 정리 후 즉시 종료한다. materialize 는 디렉토리를
  #   재생성하므로 이 가드는 materialize/claim 호출 전에 와야 한다. 조회 실패(네트워크/백엔드 오류 등)는
  #   보수적으로 무시하고 기존 파이프라인 진행으로 폴백한다(오탐으로 정상 진행 중인 태스크를 막지 않음).
  local pre_status
  pre_status="$($ADAPTER_CMD get_task --task-id "$id" 2>/dev/null | jq -r '.status // empty' 2>/dev/null)" || pre_status=""
  if [[ "$pre_status" == "done" ]]; then
    et_cleanup_dirs "$ROOT_DIR/.autopilot/runs/$id" "$ROOT_DIR/.review/tasks/$id"
    echo "execute-task: 이미 done — 정리 후 skip ($id)"
    return 0
  fi

  local sp; sp="$($ADAPTER_CMD materialize --task-id "$id" | jq -r .spec_path)"
  [[ -n "$sp" && "$sp" != null ]] || die "materialize 실패: $id"

  local owner; owner="$(hostname 2>/dev/null || echo host)-$$"

  # 원자적 실행권 획득(중복 실행 방지). 이미 다른 실행자가 점유 중이면 조용히 skip(에러 아님).
  local claimed; claimed="$($ADAPTER_CMD claim --task-id "$id" --owner "$owner" | jq -r '.claimed // false')"
  if [[ "$claimed" != "true" ]]; then echo "execute-task: 이미 다른 실행자가 점유 — skip ($id)"; return 0; fi

  # review 재진입 감지: 이전 실행이 forge 단계 진입 전에 review_entered 마커를 찍었으면 loop 생략.
  local run_dir="$ROOT_DIR/.autopilot/runs/$id"
  local reentry=0
  [[ -f "$run_dir/review_entered" ]] && reentry=1

  # reclaim: 죽은 워커 잔재 정리(최초 실행/loop-단계 재진입). forge-단계 재진입(reentry=1)은 loop 가
  #   이미 DONE 이라 회수할 워커가 없고, 완료된 .worktree 를 forge integrate 가 loop 결과(HEAD)로 읽으므로
  #   cleanup(=git worktree remove)으로 지우면 integrate 가 재실패한다 → reentry 일 때는 건너뛴다.
  (( reentry )) || $LOOP_CMD cleanup "$sp" --force >/dev/null 2>&1 || true

  # 백그라운드 heartbeat (lease 갱신). 연속 실패 시 lease 를 잃어 이중 실행 위험 → fail-fast 로 메인 중단.
  # SIGKILL orphan 방지: 부모 PID 와 시작 시간을 미리 캡처해 subshell 에서 생존 확인 후 자가종료.
  # /proc 가용 시(Linux): 시작 시간 비교로 PID 재사용·SIGKILL 양쪽 감지. 비가용 시: ppid+세마포어 조합.
  local PARENT_PID=$$
  local PARENT_STARTTIME; PARENT_STARTTIME="$(awk '{print $22}' /proc/$$/stat 2>/dev/null || true)"
  # 세마포어 파일: EXIT trap 삭제 → SIGTERM 후 PID 재사용 시에도 heartbeat 가 정상 종료로 오인 없음.
  # SIGKILL 시 EXIT trap 미실행으로 파일 잔존 가능 — 비-Linux 는 ppid 기반으로 SIGKILL 도 감지.
  PARENT_ALIVE_FILE="/tmp/execute-task-$$.alive"
  touch "$PARENT_ALIVE_FILE" 2>/dev/null || PARENT_ALIVE_FILE=""
  ( fail=0
    while true; do
      # orphan 자가종료: 부모(execute-task 메인 프로세스)가 종료되면 heartbeat 도 즉시 종료.
      # /proc 가용 시: 존재 + 시작 시간 비교(PID 재사용 구분). 비가용 시: ppid(SIGKILL)+세마포어(SIGTERM).
      if [[ -n "$PARENT_STARTTIME" ]]; then
        if [[ -r "/proc/$PARENT_PID/stat" ]]; then
          [[ "$(awk '{print $22}' "/proc/$PARENT_PID/stat" 2>/dev/null)" == "$PARENT_STARTTIME" ]] || exit 0
        else
          exit 0
        fi
      else
        # 비-Linux: ppid 기반(SIGKILL 포함) + 세마포어(SIGTERM/정상 종료) 조합.
        # SIGKILL 후 subshell 이 init 에 re-parent → ppid ≠ PARENT_PID → 자가종료.
        # $BASHPID(bash 4+): subshell 자신의 PID. ps -o ppid= 는 macOS/BSD 이식성 높음.
        if [[ -n "${BASHPID:-}" ]]; then
          _ppid="$(ps -o ppid= -p "$BASHPID" 2>/dev/null | tr -d ' ')"
          if [[ -n "$_ppid" ]]; then [[ "$_ppid" == "$PARENT_PID" ]] || exit 0; fi
        fi
        # 세마포어: EXIT trap 기반(SIGTERM/정상 종료). $BASHPID 미지원 시 주요 감지 수단.
        if [[ -n "${PARENT_ALIVE_FILE:-}" && ! -f "$PARENT_ALIVE_FILE" ]]; then exit 0; fi
      fi
      if $ADAPTER_CMD renew_lease --task-id "$id" --owner "$owner" >/dev/null 2>&1; then fail=0
      else fail=$((fail+1)); if (( fail >= 3 )); then
        echo "execute-task: heartbeat lease 갱신 연속 실패 — 작업 중단($id)" >&2
        kill -TERM $$ 2>/dev/null || true; exit 1
      fi; fi
      sleep "$HEARTBEAT_INTERVAL"
    done ) &
  HB_PID=$!

  if (( ! reentry )); then
    # 구현 (포그라운드 블로킹)
    $LOOP_CMD start "$sp" || true

    # 분류
    local sj signals; sj="$($LOOP_CMD status --json "$sp" 2>/dev/null || echo '{}')"
    # loop status --json 은 JSON 계약 → 필수 의존성 jq 로 읽는다(미선언 yq 회피).
    signals="$(printf '%s' "$sj" | jq -r '.signals[]?' 2>/dev/null || true)"
    if printf '%s\n' "$signals" | grep -Fxq BLOCKED; then
      $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "loop BLOCKED" >/dev/null
      $ADAPTER_CMD append_log --task-id "$id" --marker blocked --text "loop BLOCKED" >/dev/null
      return 1
    fi
    if ! printf '%s\n' "$signals" | grep -Fxq DONE; then
      $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "loop 미완(DONE 신호 없음)" >/dev/null
      return 1
    fi

    $ADAPTER_CMD set_status --task-id "$id" --status review >/dev/null
    if [[ "$stop_at" == "review" ]]; then echo "execute-task: review 단계 정지 ($id)"; return 0; fi
  else
    echo "execute-task: review 재진입 — forge 단계부터 재시작 ($id)" >&2
    $ADAPTER_CMD set_status --task-id "$id" --status review >/dev/null
  fi

  # forge: integrate → review(승인까지 반복, 가드) → merge (origin 라우팅)
  # crash 후 재진입 경로 표지: forge 진입 직전에 찍어, 이후 crash 시 다음 실행이 loop 를 재실행하지 않도록 한다.
  mkdir -p "$run_dir"
  touch "$run_dir/review_entered" 2>/dev/null || true
  local key="$id"
  local iout branch pr=""
  iout="$($FORGE_CMD integrate "$sp" "$run_dir" "$key" 2>&1)" || {
    $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "integrate 실패" >/dev/null
    $ADAPTER_CMD append_log --task-id "$id" --marker blocked --text "category: environment-gap — integrate 실패: $(et_reason_excerpt "$iout")" >/dev/null
    echo "$iout" >&2; return 1; }
  branch="$(printf '%s' "$iout" | sed -n 's/^branch:[[:space:]]*//p' | head -1)"
  pr="$(printf '%s' "$iout" | sed -n 's/^pr:[[:space:]]*//p' | head -1)"

  local approved=0
  if [[ -n "$pr" ]]; then
    # PR(forge) 경로: review 라운드(=rl_round, $FORGE_CMD review)의 반환코드로 분기한다(#426).
    #   리워크로 진전 가능 → 진행 / 진전 불가 → 빠른 실패 / 깨끗+비동기 승인 대기만 → 폴링 유지.
    #   반환코드 계약(forge/lib review-loop.sh rl_round, 소비만 — 변경 없음):
    #     30 = approve         → 머지 진행(merge.sh 가 미해결 스레드 가산 게이트를 머지 직전 재검증).
    #     0  = 재작업 재푸시(진전) → 새 head 가 올라갔으니 재리뷰 위해 루프 계속(무의미 대기 아님).
    #     10 = 에스컬레이션/라운드상한/핑퐁(진전 불가) → 폴링 상한 더 안 기다리고 즉시 blocked.
    #     20 = 할 일 없음(깨끗한 코드가 비동기 봇 승인만 대기) → 기존 APPROVAL_WAIT_MAX 폴링 유지(#419).
    #          이때만 폴링이 의미: 승인 = 호스팅 승인 신호 AND 현재 head 미해결 리뷰 스레드 없음.
    #     기타 비-0 = 미정의 신호 → 보수적 즉시 blocked(default-deny). rl_round 미경유 호출은 없다.
    case "$APPROVAL_POLL_INTERVAL" in ''|*[!0-9]*|0) APPROVAL_POLL_INTERVAL=1;; esac
    # 비숫자/빈값 상한은 산술 비교((( waited >= MAX )))를 0>=0 으로 망가뜨려 즉시 오종료(또는
    # 빈값 시 무한 멈춤)시키므로 기본값(360)으로 보정한다. 0 은 "대기 없이 1회 확인"으로 안전히
    # 허용한다(간격과 달리 0 이어도 영구 멈춤이 없다 — 첫 확인 후 0>=0 으로 정상 종료).
    case "$APPROVAL_WAIT_MAX" in ''|*[!0-9]*) APPROVAL_WAIT_MAX=360;; esac
    local waited=0 rounds=0 rrc
    while true; do
      rounds=$((rounds+1))
      rrc=0; $FORGE_CMD review "$run_dir" "$key" "$sp" "$pr" "$branch" || rrc=$?
      case "$rrc" in
        30) approved=1; break ;;   # approve → 머지(아래 merge 가 #423 가산 게이트 재검증)
        0)  continue ;;            # 재작업 재푸시(진전) → 재리뷰 위해 루프 계속
        20)                        # 깨끗+비동기 봇 승인 대기 → 승인 폴링 유지(정당한 대기)
          if $APPROVAL_CHECK_CMD "$pr" && $BLOCKING_CHECK_CMD "$pr"; then approved=1; break; fi
          (( waited >= APPROVAL_WAIT_MAX )) && break
          $SLEEP_CMD "$APPROVAL_POLL_INTERVAL"
          waited=$((waited + APPROVAL_POLL_INTERVAL)) ;;
        *)                         # 10(에스컬레이션/라운드상한/핑퐁) 등 진전 불가 → 빠른 실패
          $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "리뷰 진전 불가(리워크로 해소 불가, rl_round rc=$rrc) — 폴링 상한 대기 생략" >/dev/null
          $ADAPTER_CMD append_log --task-id "$id" --marker blocked --text "category: other — review 진전 불가(rc=$rrc) — 즉시 종료($rounds 라운드)" >/dev/null
          return 1 ;;
      esac
    done
    if (( ! approved )); then
      $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "리뷰 미승인(승인 폴링 상한 ${APPROVAL_WAIT_MAX}s 초과)" >/dev/null
      $ADAPTER_CMD append_log --task-id "$id" --marker blocked --text "category: other — review 승인 미게시 — 폴링 상한 초과($rounds 라운드)" >/dev/null
      return 1
    fi
  else
    # direct(PR 없음) 경로: 로컬 동기 리뷰 — 비동기 승인 대기 불필요(기존 동작 보존).
    local n=0
    while (( n < REVIEW_MAX )); do
      n=$((n+1))
      if $FORGE_CMD review "$run_dir" "$key" "$sp" "$pr" "$branch"; then approved=1; break; fi
      # 비-0: 재작업/대기/에스컬레이션 — review-loop 내부 가드가 재구현/판정. 한 라운드 더 시도.
    done
    if (( ! approved )); then
      $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "리뷰 미승인(에스컬레이션/가드)" >/dev/null
      $ADAPTER_CMD append_log --task-id "$id" --marker blocked --text "category: other — review 미승인 ($n 라운드)" >/dev/null
      return 1
    fi
  fi

  # merge 출력을 캡처해 실패 시 사유를 백엔드 로그에 남긴다(무로그 blocked 방지, run 592).
  local mout
  if mout="$($FORGE_CMD merge "$sp" "$run_dir" "$key" "$pr" 2>&1)"; then
    if [[ -n "$mout" ]]; then printf '%s\n' "$mout"; fi
    $ADAPTER_CMD set_status --task-id "$id" --status done >/dev/null
    $ADAPTER_CMD append_log --task-id "$id" --marker handoff --text "merged ${branch:+($branch)}" >/dev/null
    # .autopilot/runs/<id>/(materialize SPEC 포함)·.review/tasks/<id>/ 정리 — dirname sp 는 통상
    # run_dir 와 동일(#580 통합)하나 TB_ROOT≠ROOT_DIR 환경 대비로 둘 다 전달(멱등이라 무해).
    et_cleanup_dirs "$(dirname "$sp")" "$run_dir" "$ROOT_DIR/.review/tasks/$id"
    echo "execute-task: done ($id)"
  else
    $ADAPTER_CMD set_status --task-id "$id" --status blocked --reason "merge 실패" >/dev/null
    $ADAPTER_CMD append_log --task-id "$id" --marker blocked --text "category: environment-gap — merge 실패: $(et_reason_excerpt "$mout")" >/dev/null
    echo "$mout" >&2
    return 1
  fi
}

et_passthrough() {  # status|stop|logs <task-id> → loop 위임
  local sub="$1" id="$2"
  local sp; sp="$($ADAPTER_CMD materialize --task-id "$id" | jq -r .spec_path)"
  $LOOP_CMD "$sub" "$sp"
}

main() {
  local verb="${1:-}"; shift || true
  case "$verb" in
    start) et_start "$@";;
    status|stop|logs) et_passthrough "$verb" "$@";;
    ""|-h|--help|help) echo "usage: execute-task.sh start <task-id> [--stop-at review] | status|stop|logs <task-id>" >&2; exit 2;;
    *) die "알 수 없는 동사: $verb";;
  esac
}
# 직접 실행 시에만 main 구동. source 시(단위 테스트)엔 함수만 노출하고 실행하지 않는다.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
