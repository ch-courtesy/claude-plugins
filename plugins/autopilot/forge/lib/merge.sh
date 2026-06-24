#!/usr/bin/env bash
# merge.sh — forge per-SPEC 머지 (M4)
#
# 책임 (파이프라인 종착: "리뷰가 approve 로 수렴하면 머지되고 SPEC 은 done(=머지됨)이 된다"):
#   - 머지: 백엔드 가용 여부로 라우팅. **백엔드(forge host) 가용 시 로컬 머지 금지** — 호스트의
#     PR 기반 서버사이드 머지로만 통합한다(로컬 `git checkout <base>` 안 함). 백엔드/origin 미가용
#     (direct)일 때만 default 브랜치에 fast-forward 전용(--ff-only) 로컬 머지(+base push)한다. 머지
#     커밋·force 금지. 머지 구간은 run-dir 락으로 **직렬화**한다(동시 머지 레이스 차단, 두 경로 공통).
#   - 완료: 머지 확인되면 int-phase=merged(스케줄러가 SPEC 을 done 으로 전이) + 작업 공간
#     정리를 loop 의 공개 cleanup 인터페이스로 위임.
#
# 분리 approver 신원 요구 없음:
#   머지는 **가용한 forge 토큰**(예: gh 인증)으로 수행한다. 별도의 분리 승인 신원(APPROVER)의
#   정식 APPROVED 리뷰를 머지 전제로 두지 않는다 — 리뷰 수렴(approve) 판정은 상위 리뷰 루프가
#   책임지고, 이 모듈은 게이트 통과 시 가용 토큰으로 머지한다. forge 서브모드는 통합이 PR 을 통하며
#   (작업 브랜치 push→PR→**서버사이드 PR 머지**, 로컬 base 체크아웃 안 함), direct 서브모드(forge
#   백엔드 미가용)는 PR 없이 로컬 작업 브랜치를 ff-only 로 머지한다.
#
# 불변식:
#   - force(강제) 머지·push 금지. 머지는 git merge --ff-only 만.
#   - 작업 공간은 직접 지우지 않고 loop 공개 cleanup 으로만 위임.
#   - per-SPEC 상태는 lib-integration.sh(run-dir + 키)로만. 키는 호출자 주입.
#
# 모든 외부 인터페이스(git·forge·loop CLI)는 주입 가능. mock 으로 독립 검증
# (self-referential: 실제 머지·PR 미수행). bash 3.2+ 호환.
#
# 환경 변수 (mock 치환 가능):
#   GIT_CMD/FORGE_CMD/LOOP_CMD/DEFAULT_BRANCH   integration.sh 와 공유.

set -uo pipefail

MG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 통합 모듈(M2) → lib-integration(M1) 확보.
if ! declare -f int_set >/dev/null 2>&1; then
  # shellcheck source=lib-integration.sh
  . "$MG_SCRIPT_DIR/lib-integration.sh"
fi
set +e
set -uo pipefail

GIT_CMD="${GIT_CMD:-git}"
FORGE_CMD="${FORGE_CMD:-gh}"
LOOP_CMD_DEFAULT="bash $MG_SCRIPT_DIR/../../skills/loop/references/loop.sh"
LOOP_CMD="${LOOP_CMD:-$LOOP_CMD_DEFAULT}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
MERGE_APPROVAL_CMD="${MERGE_APPROVAL_CMD:-mg_approval_gh}"
# 서버사이드 PR 머지 완료 확인 폴링 — `--auto`(예약) 성공을 곧 머지 완료로 보지 않고 실제
# PR state==MERGED 를 폴링 확인한다(예약만 되고 미머지인 상태로 완료 처리되는 것 방지).
MERGE_CONFIRM_WAIT_MAX="${MERGE_CONFIRM_WAIT_MAX:-360}"          # 총 확인 폴링 상한(초)
MERGE_CONFIRM_POLL_INTERVAL="${MERGE_CONFIRM_POLL_INTERVAL:-20}" # 폴링 간격(초)
MG_SLEEP_CMD="${MG_SLEEP_CMD:-sleep}"                            # 폴링 sleep(테스트 no-op 치환 가능)

mg_die() { echo "merge: $*" >&2; return 1; }

# ===== forge 승인 게이트 — PR 호스팅 리뷰 승인 확인(승인 전 머지 차단) =====
# 승인 신호 두 가지(.github/workflows/{codex,claude}-review.yml 컨벤션):
#   (a) 공식 APPROVE 리뷰 → reviewDecision==APPROVED.
#   (b) App 토큰이 self-approve 불가해 APPROVE→COMMENT 로 강등된 경우 → 신뢰 봇이 현재 head 에
#       남긴 본문 마커 `<!-- <prefix> head_sha=<sha> verdict=approve -->`(prefix=*-formal-review).
# 신뢰 봇 로그인(App bot / github-actions[bot])만 마커를 신뢰한다(위조 마커 거부).
REVIEW_BOT_LOGINS_RE="${REVIEW_BOT_LOGINS_RE:-(\[bot\]$|^github-actions$|courtesy-bot)}"
# 차단성 인라인 태그(리터럴 부분문자열) — 리뷰 워크플로 본문 `**[<severity>/<conf>] title**` 형식
# (.github/workflows/{codex,claude}-review.yml). `[blocking` 는 `[non_blocking` 을 매치하지 않음.
# 봇 컨벤션 결합을 끊기 위해 주입 가능 변수로 둔다(awk index() 리터럴 매치 → awk별 escape 비의존).
BLOCKING_TAG="${BLOCKING_TAG:-[blocking}"

# mg_blocking_inline_gate <pr> <head> — 현재 head 에 신뢰봇이 남긴 **미해결** [blocking] 인라인이
#   하나라도 있으면 1(차단), 없으면 0(통과).
#   - 미해결 판정: 리뷰 스레드 isResolved(GraphQL). resolve 된 스레드는 제외 → resolve→재리뷰
#     워크플로 데드락 방지(commit_id 일치만으로 영구 차단하지 않음).
#   - 현재 head 대응: 코멘트 commit.oid==head(재푸시로 head 가 바뀌면 outdated 는 자동 해소).
#   - owner/name·head 미확정·조회/파싱 실패는 보수적 차단(default-deny)하고 사유를 stderr 로 표면화.
#   - GraphQL raw JSON 을 받아 실제 jq 로 필터 → isResolved 필터를 mock(raw 반환)으로 결정적 검증.
mg_blocking_inline_gate() {
  local pr="$1" head="$2" on owner name raw out
  if [[ -z "$head" ]]; then
    echo "merge: 승인 차단 — 현재 head 미확정으로 [blocking] 인라인 검증 불가(default-deny)" >&2
    return 1
  fi
  # shellcheck disable=SC2086
  on="$($FORGE_CMD repo view --json owner,name --jq '.owner.login+" "+.name' 2>/dev/null)" || on=""
  owner="${on%% *}"; name="${on##* }"
  if [[ -z "$owner" || -z "$name" ]]; then
    echo "merge: 승인 차단 — repo owner/name 미확정으로 [blocking] 검증 불가(default-deny)" >&2
    return 1
  fi
  # 모든 reviewThreads 페이지를 --paginate(pageInfo+after:$endCursor)로 따라간다 — 100개 초과
  #   스레드의 [blocking]을 놓치지 않게. comments 는 단일 스레드 기준 충분한 first:100(한 라인
  #   대화가 100개 초과는 비현실적). gh 출력은 페이지별 JSON 의 연결 스트림이고, 아래 jq 가 그
  #   스트림 전체를 처리한다(mock 도 다중-페이지 JSON 을 연결해 돌려줘 결정적 검증).
  # shellcheck disable=SC2086
  raw="$($FORGE_CMD api graphql --paginate -F owner="$owner" -F name="$name" -F pr="$pr" -f query='
query($owner:String!,$name:String!,$pr:Int!,$endCursor:String){
  repository(owner:$owner,name:$name){
    pullRequest(number:$pr){
      reviewThreads(first:100, after:$endCursor){
        pageInfo{hasNextPage endCursor}
        nodes{isResolved comments(first:100){nodes{author{login} commit{oid} body}}}
      }
    }}}' 2>/dev/null)"
  if [[ $? -ne 0 || -z "$raw" ]]; then
    echo "merge: 승인 차단 — 리뷰 스레드 조회 실패, [blocking] 검증 불가(default-deny)" >&2
    return 1
  fi
  # 미해결(isResolved=false) 스레드의 코멘트만: login\tcommit_oid\tbody.
  out="$(printf '%s' "$raw" | jq -r '
        .data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved==false)
        | .comments.nodes[]
        | (.author.login // "")+"\t"+(.commit.oid // "")+"\t"+((.body // "")|gsub("[\n\t]";" "))' 2>/dev/null)" \
    || { echo "merge: 승인 차단 — 리뷰 스레드 파싱 실패(default-deny)" >&2; return 1; }
  # 미해결 + 현재 head 대응(field2==head) + [blocking] 태그(field3 리터럴) 줄의 login 을 신뢰봇 grep.
  if printf '%s\n' "$out" \
       | awk -F'\t' -v h="$head" -v tag="$BLOCKING_TAG" '$2==h && index($3,tag)>0 {print $1}' \
       | grep -qE "$REVIEW_BOT_LOGINS_RE"; then
    echo "merge: 승인 차단 — 신뢰봇이 현재 head($head)에 남긴 미해결 [blocking] 인라인 존재" >&2
    return 1
  fi
  return 0
}

# mg_approval_gh <pr> — 승인이면 "APPROVED" 출력(없으면 빈 값). 주입 가능(MERGE_APPROVAL_CMD).
#   승인 신호(reviewDecision==APPROVED 또는 현재 head verdict=approve 마커)가 있어도, 현재 head 의
#   신뢰봇 미해결 [blocking] 인라인이 있으면 승인을 가린다(가산 차단, PR #385 회귀 가드).
mg_approval_gh() {
  local pr="$1" decision head approved=""
  # shellcheck disable=SC2086
  decision="$($FORGE_CMD pr view "$pr" --json reviewDecision --jq '.reviewDecision' 2>/dev/null)"
  # shellcheck disable=SC2086
  head="$($FORGE_CMD pr view "$pr" --json headRefOid --jq '.headRefOid' 2>/dev/null)"
  if [[ "$decision" == "APPROVED" ]]; then
    approved=1
  # 강등 승인: 신뢰 봇이 현재 head 에 남긴 verdict=approve 마커.
  #   봇 로그인 정규식은 **login 필드 단독**에 적용해야 앵커(\[bot\]$/^github-actions$)가 성립한다.
  #   login\tbody 결합 라인에 grep 하면 본문 때문에 앵커가 영영 깨진다(#432). awk 로 현재 head 의
  #   verdict=approve 마커를 가진 리뷰의 login 만 추출 → 그 login 을 신뢰봇 grep(blocking 게이트 미러).
  # shellcheck disable=SC2086
  elif [[ -n "$head" ]] && $FORGE_CMD pr view "$pr" --json reviews \
        --jq '.reviews[] | (.author.login // "") + "\t" + ((.body // "")|gsub("[\n\t]";" "))' 2>/dev/null \
       | awk -F'\t' -v h="$head" '$2 ~ ("head_sha=" h "[^>]*verdict=approve") {print $1}' \
       | grep -qE "$REVIEW_BOT_LOGINS_RE"; then
    approved=1
  fi
  [[ -n "$approved" ]] || return 0
  # 승인 신호가 있어도 현재 head 의 신뢰봇 [blocking] 인라인이 가린다(차단되면 APPROVED 미출력).
  mg_blocking_inline_gate "$pr" "$head" || return 0
  echo "APPROVED"
}
# mg_approval_gate <pr> — forge PR 의 호스팅 리뷰가 APPROVED 면 0, 아니면 1(차단).
#   stderr 는 의도적으로 통과시킨다 — default-deny([blocking] 검출·인라인 조회 실패) 사유가
#   거짓 승인 없이 관찰 가능하도록(AC5). stdout 만 캡처하므로 판정에는 영향 없다.
mg_approval_gate() {
  local decision
  decision="$($MERGE_APPROVAL_CMD "$1" | tr -d '[:space:]')"
  [[ "$decision" == "APPROVED" ]]
}

# ===== 2) 머지 직렬화 락 — run-dir 단위(mkdir 원자성) =====
# mg_try_lock <run_dir> — 비차단 획득(성공 0, 점유중 1).
mg_try_lock() { mkdir "$1/.merge.lock" 2>/dev/null; }
# mg_release_lock <run_dir>
mg_release_lock() { rmdir "$1/.merge.lock" 2>/dev/null || true; }
# mg_acquire_lock <run_dir> [tries] — 바운드 대기 차단 획득(성공 0, 시간초과 1).
mg_acquire_lock() {
  local rd="$1" tries="${2:-600}" i=0
  while ! mg_try_lock "$rd"; do
    i=$((i+1)); [[ "$i" -ge "$tries" ]] && return 1
    sleep "${MERGE_LOCK_SLEEP:-1}"
  done
  return 0
}

# ===== 3) ff-only 머지 — 락 보호 구간. 머지 커밋·force 없음. 가용 토큰으로 수행 =====
# mg_merge_ff_only <run_dir> <branch>
mg_merge_ff_only() {
  local rd="$1" branch="$2"
  local tries="${DISPATCH_MERGE_RETRIES:-3}" i=0 rc=1
  mg_acquire_lock "$rd" || { mg_die "머지 락 획득 실패(직렬화 대기 초과): $rd"; return 1; }
  # 임계구간: main 체크아웃 + ff-only 머지 + base push(가용 토큰). 타겟이 fetch~push 사이
  # 전진해 ff/push 가 깨지는 레이스는 non-force 재fetch 후 유한 횟수 재시도로 자가 치유한다
  # (branch 가 여전히 갱신된 타겟의 자손이면 다음 시도에서 ff 성공). force 는 쓰지 않는다.
  while [[ "$i" -lt "$tries" ]]; do
    i=$((i+1)); rc=0
    {
      # shellcheck disable=SC2086
      $GIT_CMD fetch origin "$DEFAULT_BRANCH" \
        && $GIT_CMD checkout "$DEFAULT_BRANCH" \
        && $GIT_CMD merge --ff-only "$branch" \
        && $GIT_CMD push origin "$DEFAULT_BRANCH"
    } || rc=$?
    [[ "$rc" -eq 0 ]] && break
  done
  mg_release_lock "$rd"
  # 재시도 후에도 실패면(branch base 가 stale = 타겟의 자손이 아님), 워커가 base 재동기화
  # (integration.sh integrate 의 자율 충돌 해결)를 거쳐 finish 를 재시도하거나 에스컬레이션한다.
  [[ "$rc" -eq 0 ]] || { mg_die "fast-forward 머지/푸시 실패($tries 회 재시도 후, 머지 커밋·force 금지): $branch → $DEFAULT_BRANCH — 워커 base 재동기화 후 재시도 필요"; return 1; }
}

# ===== 3b) 서버사이드 PR 머지 — forge 백엔드(github 등) 가용 경로. 로컬 checkout 금지 =====
# mg_merge_pr_serverside <run_dir> <pr> <branch>
#   백엔드가 가용(PR 존재)하면 로컬 `git checkout <base>`+ff+push 로 통합하지 않고, 호스트의
#   PR 기반 서버사이드 머지로만 통합한다(본 SPEC 핵심 — 로컬 머지 금지). persist-config 헬퍼와
#   동일 패턴: `pr merge --auto --merge`(예약: 보호 브랜치·필수 체크 통과 후 머지) → 실패 시
#   `--merge`(즉시) 폴백.
#   **머지 발행 ≠ 머지 완료**: `--auto` 는 예약만 돼도 0 을 반환할 수 있다(필수 체크가 나중에
#   실패하면 실제 머지는 안 일어남). 발행 성공을 곧 merged 로 처리하면 미머지 PR 이 done 처리되어
#   사라질 수 있으므로, 발행 후 **실제 PR state==MERGED 를 폴링 확인**해야만 성공(0)으로 반환한다.
#   상한(MERGE_CONFIRM_WAIT_MAX) 내 MERGED 미도달이면 차단(비완료 종착). 직렬화 락은 머지 *발행*
#   구간에만 보유하고(분 단위 폴링 동안 점유 안 함; auto-merge 수렴은 호스트가 직렬화), 폴링은
#   락 밖에서 한다. force 미사용. 로컬 base 미체크아웃 → 멀티-워크트리 `already checked out` 무관.
mg_merge_pr_serverside() {
  local rd="$1" pr="$2" branch="$3" issued=0
  [[ -n "$pr" ]] || { mg_die "서버사이드 PR 머지: PR 미지정(forge 경로엔 PR 필요): $branch"; return 1; }
  local wmax="$MERGE_CONFIRM_WAIT_MAX" ival="$MERGE_CONFIRM_POLL_INTERVAL"
  case "$wmax" in ''|*[!0-9]*) wmax=360;; esac
  case "$ival" in ''|*[!0-9]*|0) ival=20;; esac

  # 발행 임계구간(락 보유): 호스트 PR 머지(예약/즉시) 발행. 로컬 checkout 없음.
  mg_acquire_lock "$rd" || { mg_die "머지 락 획득 실패(직렬화 대기 초과): $rd"; return 1; }
  # shellcheck disable=SC2086
  if $FORGE_CMD pr merge "$pr" --auto --merge >/dev/null 2>&1; then issued=1
  # shellcheck disable=SC2086
  elif $FORGE_CMD pr merge "$pr" --merge >/dev/null 2>&1; then issued=1
  fi
  mg_release_lock "$rd"
  [[ "$issued" -eq 1 ]] || { mg_die "서버사이드 PR 머지 발행 실패(권한·브랜치 보호·체크 등): pr=$pr branch=$branch — 조용한 성공 금지, 차단 종착"; return 1; }

  # 발행 성공 ≠ 완료. 실제 PR state==MERGED 를 폴링 확인(락 밖)해야만 머지 완료로 본다.
  local waited=0 state
  while true; do
    # shellcheck disable=SC2086
    state="$($FORGE_CMD pr view "$pr" --json state --jq '.state' 2>/dev/null || true)"
    [[ "$state" == "MERGED" ]] && return 0
    (( waited >= wmax )) && break
    $MG_SLEEP_CMD "$ival"; waited=$((waited + ival))
  done
  mg_die "서버사이드 PR 머지 미확정(머지 발행됐으나 ${wmax}s 내 PR state==MERGED 미도달, 마지막 state='${state:-unknown}'): pr=$pr branch=$branch — 예약만 되고 미머지일 수 있어 완료로 보지 않음(차단 종착)"
  return 1
}

# ===== 4) 정리 — loop 공개 cleanup 위임 =====
mg_cleanup_workspace() {
  # shellcheck disable=SC2086
  $LOOP_CMD cleanup "$1" >/dev/null 2>&1 || echo "WARN: cleanup 위임 실패(수동 정리 필요): $1" >&2
}

# mg_delete_merged_branch <branch> — 머지 확정된 작업 브랜치 정리(원격+로컬, force 없는 일반 삭제).
#   머지 성공의 사후 단계: ff-머지 확정 이후에만 호출된다. 삭제 실패는 경고로 표면화(조용한 실패
#   금지)하되 rc 0 을 유지해 머지·완료 판정을 뒤집지 않는다(고아 브랜치는 다음 정리 기회에).
#   워커가 raw `gh`/`git push --delete` 로 직접 삭제하지 않고, 머지 확정 후 이 결정적 헬퍼만 삭제한다.
# mg_delete_branch_refs <branch> — 작업 브랜치 ref 삭제(원격 존재 시 + 로컬 존재 시), force 없는
#   일반 삭제. 결정적 단일 삭제 경로(머지 후 단건 정리·sweep 일괄 정리 공용). 워커가 raw
#   `gh`/`git push --delete` 로 직접 삭제하지 않고 이 헬퍼만 삭제한다.
#   존재하는 ref 삭제가 실패하면 WARN(조용한 실패 금지) + rc=1, 아니면 rc=0. "없음"은 실패가
#   아니다(미push·로컬 미존재를 삭제 실패로 오인해 spurious WARN 내지 않음).
mg_delete_branch_refs() {
  local branch="$1" rc=0
  [[ -n "$branch" ]] || return 0
  # 원격(대상 리모트) 작업 브랜치 삭제 — 원격에 존재할 때만 시도(미push 브랜치는 대상 없음).
  # shellcheck disable=SC2086
  if [[ -n "$($GIT_CMD ls-remote --heads origin "$branch" 2>/dev/null)" ]]; then
    # shellcheck disable=SC2086
    $GIT_CMD push origin --delete "$branch" >/dev/null 2>&1 \
      || { echo "WARN: 원격 작업 브랜치 삭제 실패(수동 정리 가능): origin/$branch" >&2; rc=1; }
  fi
  # 로컬 작업 브랜치 삭제 — force(-D) 아닌 일반 삭제(-d). 로컬에 존재할 때만 시도
  # (sweep 은 원격 추적 브랜치 기준이라 로컬 사본이 없을 수 있음 — 없는 것을 실패로 오인 금지).
  # shellcheck disable=SC2086
  if $GIT_CMD show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    # shellcheck disable=SC2086
    $GIT_CMD branch -d "$branch" >/dev/null 2>&1 \
      || { echo "WARN: 로컬 작업 브랜치 삭제 실패(수동 정리 가능): $branch" >&2; rc=1; }
  fi
  return $rc
}

mg_delete_merged_branch() {
  local branch="$1"
  [[ -n "$branch" ]] || return 0
  # 머지 확정 후 사후 단계 — 삭제 실패는 WARN 으로 표면화하되 rc 0 을 유지해 머지·완료 판정을
  # 뒤집지 않는다(고아 브랜치는 다음 정리 기회·sweep 에서). 실제 삭제는 결정적 공용 헬퍼가 수행.
  mg_delete_branch_refs "$branch" || true
  return 0
}

# ===== 4b) sweep — dispatch 자기 출처 작업 브랜치 중 대상 머지된 것 일괄 정리(명시 요청) =====
# 머지 시점 단건 정리(#363)는 그 머지가 삭제하는 한 브랜치만 다룬다. 정책 이전·외부(수동) 머지로
# 원격에 누적된 dispatch 작업 브랜치는 소급 정리되지 않으므로, 명시 요청으로 도는 일괄 정리를 둔다.
# 안전 불변식: (1) dispatch 자기 출처(네이밍 시그니처)만 대상 — 사람·타 도구 브랜치는 이름이
# 비슷해도 제외. (2) 대상 브랜치 조상(=머지 확인된) 것만 삭제, 미머지는 보존. (3) force 없는 일반
# 삭제(공용 결정적 헬퍼). (4) 부분 실패는 경고로 격리해 다른 브랜치 처리를 막지 않음.

# dispatch 전용 네이밍 시그니처: feat/<run-id>-<slug>, <run-id>=<YYYYMMDDTHHMMSS>-<sha7>.
#   (dispatch.sh: ts=date -u +%Y%m%dT%H%M%S, h=sha256 첫 7자[0-9a-f]). 사람/타 도구 브랜치는 불일치.
#   (주입 override 가능. `{n}` 인터벌은 ${:-default} 안에서 `}` 가 확장을 일찍 닫으므로 조건 대입으로 둔다.)
if [[ -z "${SWEEP_BRANCH_SIGNATURE_RE:-}" ]]; then
  SWEEP_BRANCH_SIGNATURE_RE='^feat/[0-9]{8}T[0-9]{6}-[0-9a-f]{7}-'
fi

# mg_sweep_remote_dispatch_branches — origin 원격 추적 브랜치 중 dispatch 출처 시그니처에 맞는
#   브랜치명(origin/ 제거)만 출력. HEAD 포인터·기본 브랜치·사람 생성 feat/* 는 시그니처 불일치로 제외.
mg_sweep_remote_dispatch_branches() {
  # shellcheck disable=SC2086
  $GIT_CMD branch -r 2>/dev/null \
    | sed -E 's/^[[:space:]*+]*//; s#^origin/##' \
    | grep -E "$SWEEP_BRANCH_SIGNATURE_RE" || true
}

# mg_sweep_is_merged <branch> <target> — 원격 추적 <branch> 가 <target> 의 조상(=머지됨)이면 0.
mg_sweep_is_merged() {
  local branch="$1" target="$2"
  # shellcheck disable=SC2086
  $GIT_CMD merge-base --is-ancestor "origin/$branch" "origin/$target" >/dev/null 2>&1
}

# mg_sweep_merged_branches [target] — dispatch 자기 출처 작업 브랜치 중 target 에 머지된 것 일괄 삭제.
#   target 미지정 시 DEFAULT_BRANCH. 명시 요청(정비 진입점)으로만 돈다(자동 무인 파괴 아님).
mg_sweep_merged_branches() {
  local target="${1:-$DEFAULT_BRANCH}"
  [[ -n "$target" ]] || { mg_die "sweep: 대상 브랜치 미정(DEFAULT_BRANCH 또는 인자 필요)"; return 1; }
  # 최신 원격 상태 동기화 + 삭제된 원격 추적 ref prune(stale 추적 ref 로 오삭제 방지).
  # shellcheck disable=SC2086
  $GIT_CMD fetch --prune origin >/dev/null 2>&1 || true

  local deleted=0 skipped=0 failed=0 b
  echo "sweep: target=$target (dispatch 자기 출처 머지 브랜치 일괄 정리)"
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    if mg_sweep_is_merged "$b" "$target"; then
      if mg_delete_branch_refs "$b"; then
        echo "deleted: $b"; deleted=$((deleted+1))
      else
        echo "failed:  $b (삭제 실패 — 위 WARN 참조, 다른 브랜치 계속)"; failed=$((failed+1))
      fi
    else
      echo "skipped: $b (미머지 — 보존)"; skipped=$((skipped+1))
    fi
  done < <(mg_sweep_remote_dispatch_branches)
  echo "----"
  echo "sweep done: target=$target deleted=$deleted skipped=$skipped failed=$failed"
  return 0
}

# ===== 5) 메인 진입 — 게이트 통과 시 머지하고 phase=merged =====
# mg_merge_finish <spec> <run_dir> <key> [pr] [direct]
#   direct=1 이면 direct 서브모드(forge 백엔드 미가용 — PR 없이 **로컬 ff-only** 머지) 계약으로,
#   PR 보강·승인 게이트·PR 출력을 건너뛴다. direct≠1(forge 백엔드 가용)은 PR 기반 **서버사이드
#   머지**로만 통합하고 로컬 base 체크아웃을 하지 않는다(백엔드 가용 시 로컬 머지 금지).
#   직렬화 락·작업공간 정리는 두 서브모드 공통. 버전 범프 정책은 컨슈밍 프로젝트 소유라
#   머지 엔진은 간섭하지 않는다(정책-불간섭).
#   머지는 분리 approver 승인을 전제하지 않고 가용 토큰으로 수행한다(리뷰 수렴은 상위 책임).
#   반환: 0=머지 완료(phase=merged) / 1=차단(phase=blocked, 비완료 종착 — forge PR 없음·미승인·
#         서버사이드 머지 실패).
mg_merge_finish() {
  local spec="$1" rd="$2" key="$3" pr="${4:-}" direct="${5:-}"
  [[ -n "$spec" && -n "$rd" && -n "$key" ]] || { mg_die "사용: merge.sh finish <spec> <run_dir> <key> [pr] [direct]"; return 1; }
  mkdir -p "$rd"

  local branch; branch="$(int_get_branch "$rd" "$key")"
  [[ -n "$branch" ]] || { mg_die "작업 브랜치 미설정(통합 선행 필요): key=$key"; return 1; }
  # direct 서브모드(direct=1)는 PR 없이 동작하는 계약 — PR 보강을 건너뛴다
  # (같은 key 가 이전 forge 경로·재개에서 가졌을 수 있는 stale PR 을 끌어오지 않음).
  [[ "$direct" == "1" ]] || { [[ -n "$pr" ]] || pr="$(int_get_pr "$rd" "$key")"; }
  int_log "$rd" "$key" "merge_finish spec=$spec branch=$branch pr=$pr direct=${direct:-0}"

  # 1) forge PR 존재 게이트 — forge 경로(direct≠1)는 PR 을 통해 통합한다. PR 이 없으면
  #    (생성 누락·상태 손상) 대상 브랜치에 PR 없이 직접 머지해 PR 리뷰 경로를 우회하는 것을
  #    막기 위해 차단한다(비완료 종착). direct 는 PR 없이 동작하는 계약이라 적용하지 않는다.
  if [[ "$direct" != "1" && -z "$pr" ]]; then
    int_set_phase "$rd" "$key" blocked
    int_log "$rd" "$key" "forge PR 없음 차단: PR 미보강(생성 누락·상태 손상) — PR 없이 머지 안 함(비완료 종착)"
    echo "key:     $key"
    echo "blocked: no-pr — forge 서브모드인데 PR 이 없습니다(PR 없이 대상 브랜치에 직접 머지하지 않습니다)."
    return 1
  fi

  # 1b) forge 승인 게이트 — PR 의 호스팅 리뷰가 APPROVED 일 때만 머지(승인 전 머지 차단).
  #     direct 는 PR 없이 동작하는 계약이라 적용하지 않는다(direct 승인은 review-loop 가 phase 로 보증).
  if [[ "$direct" != "1" ]] && ! mg_approval_gate "$pr"; then
    int_set_phase "$rd" "$key" blocked
    int_log "$rd" "$key" "승인 게이트 차단: PR($pr) reviewDecision!=APPROVED — 승인 전 머지 안 함(비완료 종착)"
    echo "key:     $key"
    echo "blocked: not-approved — PR 이 APPROVED 가 아닙니다(승인 전 머지하지 않습니다)."
    return 1
  fi

  # 2) 머지 실행 — 백엔드 가용 여부로 라우팅. **백엔드(forge) 가용 시 로컬 머지 금지**.
  #    direct=1(forge 백엔드/origin 미가용) → 로컬 ff-only(checkout+ff+push). review 스킬이
  #      phase 로 승인 보증하는 로컬 direct 머지(PR/서버 없음).
  #    direct≠1(forge 백엔드 가용, PR 존재) → 호스트의 PR 기반 서버사이드 머지만. 로컬
  #      `git checkout <base>` 를 타지 않으므로 멀티-워크트리 `already checked out` 결함이 제거된다.
  int_set_phase "$rd" "$key" merging
  if [[ "$direct" == "1" ]]; then
    int_log "$rd" "$key" "게이트 통과 → direct 로컬 ff-only 머지(직렬화, 가용 토큰): $branch → $DEFAULT_BRANCH"
    mg_merge_ff_only "$rd" "$branch" || { int_set_phase "$rd" "$key" blocked; return 1; }
  else
    int_log "$rd" "$key" "게이트 통과 → forge 서버사이드 PR 머지(직렬화, 로컬 checkout 금지): pr=$pr"
    mg_merge_pr_serverside "$rd" "$pr" "$branch" || { int_set_phase "$rd" "$key" blocked; return 1; }
  fi

  # 3) 완료. 머지 확정 후 사후 단계로 정리한다(순서: 워크트리 정리 → 작업 브랜치 삭제).
  #    워크트리를 먼저 위임 정리해야 그 워크트리에 체크아웃된 작업 브랜치를 로컬에서 삭제할 수 있다.
  #    정리 실패는 경고로 표면화하되 머지·완료 판정을 뒤집지 않는다(아래 헬퍼들이 rc 0 유지).
  #    작업 브랜치 삭제는 **direct(로컬) 머지에서만** 워커가 수행한다. 서버사이드 경로는 머지가
  #    예약(--auto)일 수 있어 원격 브랜치를 지금 지우면 예약 머지를 취소할 수 있으므로, 원격
  #    작업 브랜치 정리는 호스트(repo head-branch 자동삭제)·dispatch sweep 에 맡긴다.
  int_set_phase "$rd" "$key" merged
  mg_cleanup_workspace "$spec"
  [[ "$direct" == "1" ]] && mg_delete_merged_branch "$branch"
  int_log "$rd" "$key" "완료: 머지 확인, phase=merged, 작업 공간 정리 위임(direct 는 작업 브랜치도 삭제)."
  echo "key:     $key"
  echo "phase:   merged"
  if [[ "$direct" == "1" ]]; then
    echo "branch:  $branch → $DEFAULT_BRANCH (ff-only)"
  else
    echo "branch:  $branch → $DEFAULT_BRANCH (PR #$pr 서버사이드 머지)"
  fi
  # direct 서브모드는 PR 없이 동작 — PR 필드 생략(stale PR 출력 방지).
  [[ "$direct" == "1" ]] || echo "pr:      $pr"
  return 0
}

# ----- 사용법 -----
mg_usage() {
  cat >&2 <<'EOF'
usage: merge.sh <command> [args]

Commands:
  finish <spec> <run_dir> <key> [pr] [direct]
                                   승인 게이트 통과 시 직렬화 ff-only 머지(가용 토큰) 후
                                   phase=merged + 작업 공간 정리 위임. direct=1 이면 PR 없이.
  sweep [target]                   dispatch 자기 출처 작업 브랜치 중 target(미지정 시 DEFAULT_BRANCH)
                                   에 머지된 것만 force 없이 일괄 삭제. 미머지·비-dispatch 브랜치는
                                   보존. 부분 실패는 경고로 격리. 명시 요청 정비 진입점.

환경 변수: GIT_CMD FORGE_CMD LOOP_CMD DEFAULT_BRANCH SWEEP_BRANCH_SIGNATURE_RE
EOF
  return 1
}

# =====================================================================
# selftest — mock 인터페이스로 ff-only·직렬화 락·force 미사용·승인 게이트 검증.
#   (분리 approver 요구 없음 — 머지는 승인 게이트 통과 시 가용 토큰으로 수행.)
#   (버전 범프 정책은 컨슈밍 프로젝트 소유 — 머지 엔진 비간섭.)
# =====================================================================
mg_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local rd="$TMP/.dispatch/runs/run1"; mkdir -p "$rd"
  local trace="$TMP/trace"; : > "$trace"

  mock_git() {
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    echo "git $*" >> "$trace"
    case "$1" in
      ls-remote)
        # 기본 mock: 작업 브랜치가 원격에 존재한다고 본다(forge 머지 성공 경로의 원격 삭제 검증).
        echo "deadbeef refs/heads/work"; return 0 ;;
    esac
    return 0
  }
  # mock forge: 서버사이드 머지 발행은 성공, state 폴링은 MERGED 를 돌려줘 완료를 모사한다
  #   (mg_merge_pr_serverside 의 "발행 ≠ 완료" 계약 — state==MERGED 확인 후에야 0 반환).
  mock_forge() {
    echo "forge $*" >> "$trace"
    case "$*" in *"pr view"*state*) echo "MERGED" ;; esac
    return 0
  }
  mock_loop() { echo "loop $*" >> "$trace"; return 0; }
  mock_approval() { echo "${MOCK_APPROVED:-APPROVED}"; }
  GIT_CMD=mock_git; FORGE_CMD=mock_forge; LOOP_CMD=mock_loop; MERGE_APPROVAL_CMD=mock_approval
  DEFAULT_BRANCH=main

  local spec="$TMP/SPEC.md"; printf '# T\n' > "$spec"
  local fail=0
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }
  has()   { grep -q "$1" "$trace"; }
  setup() { local k="$1"; int_set_branch "$rd" "$k" "feat/run1-$k"; int_set_pr "$rd" "$k" 77; }
  reset() { : > "$trace"; }

  # ---- forge: 승인됨 → 서버사이드 PR 머지 + phase=merged + cleanup (approver 불필요) ----
  #   백엔드 가용 경로는 로컬 checkout/ff/push 를 타지 않고 호스트 PR 머지로만 통합한다.
  reset; setup k1
  mg_merge_finish "$spec" "$rd" k1 >/dev/null 2>&1; local rc=$?
  chk "forge 머지 rc=0(approver 불필요)" "$rc" "0"
  has 'forge pr merge' && ok "서버사이드 PR 머지 호출" || bad "서버사이드 PR 머지 호출"
  if has 'git checkout main'; then bad "forge 가용인데 로컬 checkout main(로컬머지 금지 위반)"; else ok "로컬 checkout main 미호출"; fi
  if has 'git merge --ff-only'; then bad "forge 가용인데 로컬 ff 머지(로컬머지 금지 위반)"; else ok "로컬 ff 머지 미호출"; fi
  if has 'git push origin main'; then bad "forge 가용인데 로컬 base push(로컬머지 금지 위반)"; else ok "로컬 base push 미호출"; fi
  chk "phase=merged" "$(int_get_phase "$rd" k1)" "merged"
  has 'loop cleanup' && ok "cleanup 위임" || bad "cleanup 위임"
  # 서버사이드(예약 가능) 경로 — 워커가 원격/로컬 작업 브랜치를 직접 지우지 않는다(예약 머지 취소 방지,
  #   호스트 자동삭제·sweep 에 위임). direct 경로 단위 검증은 아래 kdelfail/kdnoremote 가 담당.
  if has 'push origin --delete feat/run1-k1'; then bad "서버사이드인데 원격 작업브랜치 직접 삭제(예약 머지 취소 위험)"; else ok "서버사이드 → 원격 작업브랜치 직접 삭제 안 함"; fi
  if has 'branch -d feat/run1-k1'; then bad "서버사이드인데 로컬 작업브랜치 직접 삭제"; else ok "서버사이드 → 로컬 작업브랜치 직접 삭제 안 함"; fi

  # ---- forge: 서버사이드 머지 실패(권한·브랜치 보호 등) → 차단(rc=1), 조용한 성공 금지 ----
  reset; setup kssfail
  mock_forge_mergefail() { echo "forge $*" >> "$trace"; case "$1 $2" in "pr merge") return 1;; esac; return 0; }
  FORGE_CMD=mock_forge_mergefail \
    mg_merge_finish "$spec" "$rd" kssfail >/dev/null 2>&1; rc=$?
  chk "서버사이드 머지 실패 rc=1(차단)" "$rc" "1"
  chk "서버사이드 머지 실패 phase=blocked" "$(int_get_phase "$rd" kssfail)" "blocked"
  if has 'loop cleanup'; then bad "머지 실패인데 cleanup 위임(조용한 성공)"; else ok "머지 실패 → cleanup 미위임(차단 종착)"; fi

  # ---- forge: PR 미승인(reviewDecision!=APPROVED) → 차단(승인 전 머지 차단, PR #353 회귀 가드) ----
  reset; setup knapp
  MOCK_APPROVED="REVIEW_REQUIRED" \
    mg_merge_finish "$spec" "$rd" knapp >/dev/null 2>&1; rc=$?
  chk "forge 미승인 rc=1(차단)" "$rc" "1"
  if has 'git merge --ff-only'; then bad "미승인인데 머지함"; else ok "미승인 → 머지 안 함"; fi
  chk "미승인 phase=blocked" "$(int_get_phase "$rd" knapp)" "blocked"
  # 차단(비머지)에서는 작업 브랜치를 보존 — 삭제 금지(실패/비완료=보존).
  if has 'push origin --delete'; then bad "차단인데 원격 브랜치 삭제함(보존 위반)"; else ok "차단 → 원격 브랜치 보존"; fi
  if has 'branch -d'; then bad "차단인데 로컬 브랜치 삭제함(보존 위반)"; else ok "차단 → 로컬 브랜치 보존"; fi

  # ---- 회귀 가드(#482): 머지 엔진은 버전 범프 정책에 간섭하지 않는다(정책-불간섭) ----
  #   버전 범프는 컨슈밍 프로젝트 소유 정책(versioning.md)이므로 플러그인 머지 엔진은 게이트로
  #   집행하지 않는다. plugins/ 를 건드린 브랜치가 plugin.json 범프 없이도 버전 사유로 차단되지
  #   않고(승인됨이면 서버사이드 머지로 통과), 버전 게이트 함수·차단 메시지가 잔존하지 않아야 한다.
  if declare -f mg_version_gate >/dev/null 2>&1; then bad "회귀: mg_version_gate 함수 잔존(게이트 미제거)"; else ok "회귀: mg_version_gate 함수 제거됨"; fi
  reset; setup kvg
  out="$(mg_merge_finish "$spec" "$rd" kvg 2>&1)"; rc=$?
  chk "회귀: plugins/ 변경+범프없음 rc=0(버전 비차단)" "$rc" "0"
  chk "회귀: phase=merged(버전 게이트 부재)" "$(int_get_phase "$rd" kvg)" "merged"
  case "$out" in *version-bump*) bad "회귀: version-bump 차단 메시지 잔존";; *) ok "회귀: version-bump 차단 메시지 없음";; esac

  # ---- forge: PR 없음(보강 실패·상태 손상) → 차단(rc=1), merge/push 미호출 (codex blocking/96 가드) ----
  reset
  int_set_branch "$rd" knopr "feat/run1-knopr"   # PR 미설정(int_set_pr 안 함) → int_get_pr 빈 값
  mg_merge_finish "$spec" "$rd" knopr >/dev/null 2>&1; rc=$?
  chk "forge PR없음 rc=1(차단)" "$rc" "1"
  if has 'git merge --ff-only'; then bad "forge PR없음인데 머지/push 호출됨(차단 실패)"; else ok "forge PR없음 머지/push 미호출"; fi
  chk "forge PR없음 phase=blocked" "$(int_get_phase "$rd" knopr)" "blocked"
  # 대조: direct=1 은 PR 없이도 머지(PR 게이트는 forge 전용).
  reset
  int_set_branch "$rd" kdnopr "feat/run1-kdnopr"
  mg_merge_finish "$spec" "$rd" kdnopr "" 1 >/dev/null 2>&1; rc=$?
  chk "direct PR없음 rc=0(머지)" "$rc" "0"
  has 'git merge --ff-only' && ok "direct PR없음에도 머지함(forge 전용 게이트)" || bad "direct PR없음인데 머지 안 됨(게이트가 direct에 오적용)"

  # ---- direct=1 → PR 없이 ff-only 머지 ----
  reset; setup kd1   # setup 은 int_set_pr 77 을 심는다 — direct 경로가 이 stale PR 을 끌어오면 안 된다.
  out="$(mg_merge_finish "$spec" "$rd" kd1 "" 1 2>/dev/null)"; rc=$?
  chk "direct 머지 rc=0" "$rc" "0"
  has 'git merge --ff-only' && ok "direct ff-only 머지" || bad "direct ff-only 머지"
  chk "direct phase=merged" "$(int_get_phase "$rd" kd1)" "merged"
  case "$out" in *77*) bad "direct stale PR(77) 미출력";; *) ok "direct stale PR(77) 미출력";; esac

  # ---- 브랜치 삭제 실패 → 경고로 표면화, 머지 판정(merged)은 유지(정리는 사후 단계) ----
  #   작업 브랜치 삭제는 direct(로컬) 머지 경로의 사후 단계 — direct=1 로 검증한다.
  reset; setup kdelfail
  # 삭제 명령만 실패시키는 mock — 머지/push 는 성공, delete 만 rc=1.
  mock_git_delfail() {
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    echo "git $*" >> "$trace"
    case "$1 $2" in
      "push origin") case "$*" in *--delete*) return 1;; esac ;;
      "branch -d") return 1 ;;
    esac
    case "$1" in
      ls-remote) echo "deadbeef refs/heads/work"; return 0 ;;  # 원격에 존재 → 삭제 시도되고 실패해 WARN
    esac
    return 0
  }
  err="$(GIT_CMD=mock_git_delfail mg_merge_finish "$spec" "$rd" kdelfail "" 1 2>&1 >/dev/null)"; rc=$?
  chk "삭제 실패해도 머지 rc=0" "$rc" "0"
  chk "삭제 실패해도 phase=merged" "$(int_get_phase "$rd" kdelfail)" "merged"
  case "$err" in *WARN*) ok "브랜치 삭제 실패 경고 표면화";; *) bad "브랜치 삭제 실패 경고 표면화(조용한 실패 금지)";; esac

  # ---- 원격에 작업 브랜치 없음(direct 등 미push) → 원격 삭제 시도 안 함, spurious WARN 없음 ----
  #   삭제는 머지 성공의 사후 단계 — 원격에 없는 브랜치 삭제 실패를 "정리 실패"로 오인해 WARN 을
  #   내면 조용한-실패-금지 신호가 흐려진다. ls-remote 로 존재 시에만 삭제·WARN.
  reset; setup kdnoremote
  mock_git_noremote() {
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    echo "git $*" >> "$trace"
    case "$1" in
      ls-remote) return 0 ;;  # 원격에 브랜치 없음 = 빈 출력
      push) case "$*" in *--delete*) return 1;; esac ;;  # 호출되면 실패(원격에 없으므로)
    esac
    return 0
  }
  err="$(GIT_CMD=mock_git_noremote mg_merge_finish "$spec" "$rd" kdnoremote "" 1 2>&1 >/dev/null)"; rc=$?
  chk "원격 미존재 direct 머지 rc=0" "$rc" "0"
  if has 'push origin --delete feat/run1-kdnoremote'; then bad "원격 미존재인데 원격 삭제 시도(불필요)"; else ok "원격 미존재 → 원격 삭제 미시도"; fi
  case "$err" in *"원격 작업 브랜치 삭제 실패"*) bad "원격 미존재인데 spurious WARN 방출";; *) ok "원격 미존재 → spurious WARN 없음";; esac

  # ---- 머지 락 직렬화 — 점유 중엔 두 번째 획득 실패, 해제 후 성공 ----
  mg_try_lock "$rd" && ok "락 1차 획득" || bad "락 1차 획득"
  if mg_try_lock "$rd"; then bad "점유 중 2차 획득 차단"; else ok "점유 중 2차 획득 차단"; fi
  mg_release_lock "$rd"
  mg_try_lock "$rd" && ok "해제 후 재획득" || bad "해제 후 재획득"
  mg_release_lock "$rd"

  # ---- force 미사용 (mock_git force 보면 exit99; 위 머지 케이스 통과 = 미사용) ----
  reset; setup k7
  mg_merge_finish "$spec" "$rd" k7 >/dev/null 2>&1
  if grep -qiE 'force|(^| )-f( |$)' "$trace"; then bad "force 미사용"; else ok "force 미사용(git 인자에 force 없음)"; fi

  # ---- sweep — dispatch 자기 출처 작업 브랜치 중 대상 머지된 것만 일괄 삭제 ----
  #   원격 작업 브랜치 집합(dispatch 시그니처 + 사람 생성 혼재) 중:
  #     aaaaaaa(머지됨)        → 삭제(원격 push --delete, force 없음)
  #     bbbbbbb(미머지)        → 건너뜀(보존, 삭제 금지)
  #     ccccccc(머지됨·삭제실패) → 실패로 보고(WARN, 다른 브랜치 계속)
  #     feat/manual-feature   → dispatch 출처 아님 → 머지됐어도 절대 안 건드림(이름 유사해도 제외)
  reset
  mock_git_sweep() {
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    echo "git $*" >> "$trace"
    case "$1 $2" in
      "branch -r")
        cat <<'BR'
  origin/HEAD -> origin/main
  origin/main
  origin/feat/manual-feature
  origin/feat/20260101T010101-aaaaaaa-merged-spec
  origin/feat/20260101T020202-bbbbbbb-unmerged-spec
  origin/feat/20260101T030303-ccccccc-delfail
BR
        return 0 ;;
      "merge-base --is-ancestor")
        # $3=origin/<branch> $4=origin/main. 미머지 하나만 1, 나머지 머지됨(0).
        case "$3" in *bbbbbbb-unmerged*) return 1;; *) return 0;; esac ;;
      "show-ref --verify") return 1 ;;   # 로컬 작업 브랜치 없음(원격만) → branch -d 미호출(가드)
    esac
    case "$1" in
      ls-remote) echo "deadbeef refs/heads/x"; return 0 ;;   # 원격 존재
      push) case "$*" in *--delete*delfail*) return 1;; *--delete*) return 0;; esac ;;
      fetch) return 0 ;;
    esac
    return 0
  }
  sweepout="$(GIT_CMD=mock_git_sweep DEFAULT_BRANCH=main mg_sweep_merged_branches 2>"$TMP/sweep_err")"; rc=$?
  swerr="$(cat "$TMP/sweep_err" 2>/dev/null)"; rm -f "$TMP/sweep_err"
  chk "sweep rc=0" "$rc" "0"
  # 머지된 dispatch 브랜치 삭제(원격 push --delete, force 없음).
  has 'push origin --delete feat/20260101T010101-aaaaaaa-merged-spec' \
    && ok "sweep 머지 브랜치 삭제(원격)" || bad "sweep 머지 브랜치 삭제(원격)"
  # 미머지 dispatch 브랜치는 절대 삭제 안 함(보존).
  if has 'push origin --delete feat/20260101T020202-bbbbbbb-unmerged'; then
    bad "sweep 미머지 브랜치 삭제함(보존 위반)"; else ok "sweep 미머지 → 보존(삭제 안 함)"; fi
  # dispatch 출처 아닌 사람 생성 브랜치는 절대 안 건드림(이름 유사해도 제외).
  if has 'push origin --delete feat/manual-feature'; then
    bad "sweep 비-dispatch 브랜치 삭제함(출처 오인)"; else ok "sweep 비-dispatch 브랜치 제외"; fi
  case "$sweepout" in *manual-feature*) bad "sweep 보고에 비-dispatch 브랜치 노출";; *) ok "sweep 보고 비-dispatch 제외";; esac
  # 로컬 브랜치 없으면(show-ref 가드) branch -d 미호출.
  if has 'branch -d'; then bad "sweep 로컬 미존재인데 branch -d 호출(가드 누락)"; else ok "sweep 로컬 미존재 → branch -d 미호출"; fi
  # 관찰 가능 보고: deleted/skipped/failed 분류 + 요약.
  case "$sweepout" in *"deleted=1 skipped=1 failed=1"*) ok "sweep 요약 보고(deleted=1 skipped=1 failed=1)";; *) bad "sweep 요약 보고(deleted=1 skipped=1 failed=1) got=[$sweepout]";; esac
  # 부분 실패 격리: 삭제 실패 브랜치는 WARN, 다른 브랜치 처리 계속(aaaaaaa 삭제됨).
  case "$swerr" in *WARN*) ok "sweep 부분 실패 WARN 표면화";; *) bad "sweep 부분 실패 WARN 표면화(조용한 실패 금지)";; esac
  # force 미사용(sweep 경로).
  if grep -qiE 'force|(^| )-f( |$)' "$trace"; then bad "sweep force 미사용"; else ok "sweep force 미사용"; fi

  # =====================================================================
  # 승인 게이트 ── 현재 head 의 신뢰봇 미해결 [blocking] 인라인이 approve 를 가린다(PR #385).
  #   mg_approval_gh 를 직접 호출(merge_finish 경로는 MERGE_APPROVAL_CMD 가 mock 이라
  #   gh-경로를 안 탐). FORGE_CMD 를 시나리오 변수로 구동하는 mock 으로 치환.
  # =====================================================================
  # mock gh: pr view --json {reviewDecision|headRefOid|reviews}, repo view(--jq → "owner name"),
  #   api graphql(리뷰 스레드 raw JSON). graphql 조회 실패는 SC_API_FAIL=1.
  mock_forge_gh() {
    case "$1" in
      pr)
        case "$*" in
          *"--json reviewDecision"*) printf '%s\n' "${SC_DECISION:-}" ;;
          *"--json headRefOid"*)     printf '%s\n' "${SC_HEAD:-}" ;;
          *"--json reviews"*)        printf '%b' "${SC_REVIEWS:-}" ;;  # login\tbody 줄들
        esac ;;
      repo) printf '%s %s\n' "${SC_OWNER:-o}" "${SC_NAME:-n}" ;;
      api)
        [[ "${SC_API_FAIL:-}" == "1" ]] && return 1
        printf '%s' "${SC_THREADS:-}" ;;  # 리뷰 스레드 raw GraphQL JSON(게이트 내부 jq 가 필터)
    esac
    return 0
  }
  # thr <isResolved> <login> <oid> <body> — 단일 리뷰 스레드 raw GraphQL JSON 빌더.
  thr() { printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":%s,"comments":{"nodes":[{"author":{"login":"%s"},"commit":{"oid":"%s"},"body":"%s"}]}}]}}}}}' "$1" "$2" "$3" "$4"; }
  # ag — mg_approval_gh 출력(APPROVED/빈값). 시나리오 SC_* 는 호출부 env-prefix 로 주입하되
  #   반드시 substitution 안에서 prefix 해야 ag 환경에 도달한다(밖에 두면 chk 에만 걸림).
  ag() { FORGE_CMD=mock_forge_gh mg_approval_gh "${1:-700}" 2>/dev/null | tr -d '[:space:]'; }
  local H="headSHA1"
  # 마커 경로 grep 은 login\tbody 줄에 앵커 정규식을 적용 → 비앵커 매치되는 courtesy-bot 사용.
  local MARK="courtesy-bot\t<!-- claude-formal-review head_sha=$H verdict=approve -->\n"
  local BLK; BLK="$(thr false "github-actions[bot]" "$H" "**[blocking/98] 차단 지적**")"
  local OK_C; OK_C="$(thr false "github-actions[bot]" "$H" "**[non_blocking/85] 정보성**")"

  # AC2: APPROVED 인데 현재 head 신뢰봇 미해결 [blocking] → 승인 아님(차단).
  chk "AC2 approved+head [blocking] → 차단(빈값)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$H" SC_THREADS="$BLK" ag)" ""
  # AC1: blocking 없음 + APPROVED → APPROVED 통과.
  chk "AC1 approved+blocking없음 → APPROVED" \
    "$(SC_DECISION=APPROVED SC_HEAD="$H" SC_THREADS="$OK_C" ag)" "APPROVED"
  # isResolved: resolve 된 스레드의 [blocking] → 차단 안 함(APPROVED) — resolve→재리뷰 데드락 방지.
  chk "resolved 스레드 [blocking] → 차단 안 함(APPROVED)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$H" SC_THREADS="$(thr true "github-actions[bot]" "$H" "**[blocking/98] 해결됨**")" ag)" "APPROVED"
  # 페이지네이션: 2페이지 연결 JSON 중 2페이지에 head [blocking] → 차단(--paginate 전 페이지 처리).
  chk "pagination: 2페이지의 [blocking] → 차단(빈값)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$H" SC_THREADS="$(thr false "github-actions[bot]" "$H" "**[non_blocking/80] 1p**")$(thr false "github-actions[bot]" "$H" "**[blocking/98] 2p**")" ag)" ""
  # AC3: 비신뢰 작성자 [blocking] + APPROVED → 차단 근거 아님(통과).
  chk "AC3 비신뢰봇 [blocking] → 차단 안 함(APPROVED)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$H" SC_THREADS="$(thr false "random-human" "$H" "**[blocking/98] 위조**")" ag)" "APPROVED"
  # AC3: outdated(이전 head) [blocking] + APPROVED → 차단 근거 아님(통과).
  chk "AC3 outdated [blocking] → 차단 안 함(APPROVED)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$H" SC_THREADS="$(thr false "github-actions[bot]" "oldSHA" "**[blocking/98] 이전**")" ag)" "APPROVED"
  # AC2: 강등 승인 마커(verdict=approve) + head 미해결 [blocking] → 차단.
  chk "AC2 마커승인+head [blocking] → 차단(빈값)" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$H" SC_REVIEWS="$MARK" SC_THREADS="$BLK" ag)" ""
  # 강등 승인 마커 + blocking 없음 → APPROVED.
  chk "마커승인+blocking없음 → APPROVED" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$H" SC_REVIEWS="$MARK" SC_THREADS="$OK_C" ag)" "APPROVED"
  # #432: 봇 로그인 정규식을 login 필드 단독에 적용해야 앵커(\[bot\]$/^github-actions$)가 성립.
  #   결합 라인(login\tbody) grep 회귀 가드 — [bot]/github-actions 계열 마커 승인 감지.
  local MARK_GA="github-actions[bot]\t<!-- claude-formal-review head_sha=$H verdict=approve -->\n"
  local MARK_CX="codex[bot]\t<!-- codex-formal-review head_sha=$H verdict=approve -->\n"
  local MARK_EVIL="evil-user\t<!-- forged head_sha=$H verdict=approve -->\n"
  local MARK_OLD="github-actions[bot]\t<!-- claude-formal-review head_sha=otherSHA verdict=approve -->\n"
  chk "#432 github-actions[bot] 마커승인 → APPROVED" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$H" SC_REVIEWS="$MARK_GA" SC_THREADS="$OK_C" ag)" "APPROVED"
  chk "#432 codex[bot] 마커승인 → APPROVED" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$H" SC_REVIEWS="$MARK_CX" SC_THREADS="$OK_C" ag)" "APPROVED"
  chk "#432 비신뢰(evil-user) 마커 → 미승인(빈값)" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$H" SC_REVIEWS="$MARK_EVIL" SC_THREADS="$OK_C" ag)" ""
  chk "#432 head 불일치 마커 → 미승인(빈값)" \
    "$(SC_DECISION=REVIEW_REQUIRED SC_HEAD="$H" SC_REVIEWS="$MARK_OLD" SC_THREADS="$OK_C" ag)" ""
  # AC5: 스레드 조회 실패 + APPROVED → default-deny(차단).
  chk "AC5 스레드 조회 실패 → default-deny(차단)" \
    "$(SC_DECISION=APPROVED SC_HEAD="$H" SC_API_FAIL=1 ag)" ""
  # AC5: head 미확정 + APPROVED → default-deny(차단).
  chk "AC5 head 미확정 → default-deny(차단)" \
    "$(SC_DECISION=APPROVED SC_HEAD="" SC_THREADS="$OK_C" ag)" ""
  # AC5: 조회 실패 시 stderr 표면화(거짓 승인 금지).
  ( SC_DECISION=APPROVED SC_HEAD=$H SC_API_FAIL=1 FORGE_CMD=mock_forge_gh mg_approval_gh 708 ) \
    2>"$TMP/ag_err" >/dev/null
  case "$(cat "$TMP/ag_err" 2>/dev/null)" in *차단*|*default-deny*) ok "AC5 조회 실패 stderr 표면화";; *) bad "AC5 조회 실패 stderr 표면화";; esac
  # AC5 Wired: 전체 게이트(mg_approval_gate→mg_approval_gh)에서 default-deny 사유가 stderr 로 살아남고
  #   판정은 차단(rc=1)임. mg_approval_gate 의 stderr 미차단이 관찰성을 보존하는지 검증.
  ( SC_DECISION=APPROVED SC_HEAD=$H SC_API_FAIL=1 \
    FORGE_CMD=mock_forge_gh MERGE_APPROVAL_CMD=mg_approval_gh mg_approval_gate 709 ) \
    2>"$TMP/gate_err"; rc=$?
  chk "AC5 게이트 default-deny 차단(rc=1)" "$rc" "1"
  case "$(cat "$TMP/gate_err" 2>/dev/null)" in *차단*|*default-deny*) ok "AC5 게이트 stderr 사유 보존(Wired)";; *) bad "AC5 게이트 stderr 사유 보존(Wired)";; esac

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ----- CLI 진입 (sourcing 시 미실행) -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SUB="${1:-}"; shift || true
  case "$SUB" in
    finish)       mg_merge_finish "$@" ;;
    sweep)        mg_sweep_merged_branches "$@" ;;
    selftest)     mg_selftest ;;
    -h|--help|help) mg_usage ;;
    *) echo "알 수 없는 command: $SUB" >&2; mg_usage ;;
  esac
fi
