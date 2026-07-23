#!/usr/bin/env bash
# integration.sh — forge per-SPEC 통합 (M2)
#
# 책임 ("loop DONE" 과 "리뷰 승인 요청(PR)" 사이의 다리):
#   - 종료 신호 판정: loop 의 공개 구조화 상태(`status --json`)로만 child 종료 의도를
#     읽어 통합 분기로 매핑한다.
#       DONE(차단 없음)            → base sync → push(feat/<run-id>-<slug>) → PR 생성/재사용,
#                                     int-phase=review.
#       BLOCKED category=spec-gap  → push·PR 없이 스펙 보강 재개 안내, int-phase=blocked-spec-gap.
#       BLOCKED 그 외 하드 범주     → push·PR 없이 사람 에스컬레이션, int-phase=blocked.
#   - base sync: 작업 브랜치를 default branch(main)에 rebase(fast-forward 가능할 때만).
#   - push: 작업 결과를 `feat/<run-id>-<slug>` 브랜치로 push.
#   - PR 생성/재사용: 같은 head 의 open PR 이 있으면 재사용, 없으면 생성.
#
# 불변식:
#   - force(강제) push·rebase 금지(어떤 경로에서도).
#   - 종료 상태·BLOCKED 범주는 loop 의 공개 인터페이스(status --json / logs)로만 읽고
#     child 워크트리·내부 신호 파일을 직접 열지 않는다.
#   - 브랜치명·slug 는 rules/engineering/branch-and-slug.md 단일 출처(feat/<id>-<slug>).
#   - per-SPEC 상태는 state-io.sh(run-dir + 불투명 key)로만 보관한다.
#
# 키 계약: 통합 모듈은 per-SPEC 키를 **재계산하지 않고** 호출자(execute-task)에게서 받는다
#   (호출자가 spec_slug+hash7 로 한 번 계산해 모든 통합 모듈 호출에 같은 키를 넘긴다).
#   → spec_slug/hash7 의 모듈 간 중복·표류를 만들지 않는다.
#
# 모든 외부 인터페이스(loop·git·forge CLI)는 주입 가능한 명령 변수로 두어 mock 으로
# 독립 검증한다(self-referential: 실제 PR·push 미수행). bash 3.2+ 호환.
#
# 환경 변수 (테스트에서 mock 으로 치환 가능):
#   LOOP_CMD        loop driver 호출 (기본: 형제 loop.sh).
#   GIT_CMD         git 호출 (기본: git). force 옵션 미사용.
#   FORGE_CMD       forge(PR) CLI 호출 (기본: gh).
#   DEFAULT_BRANCH  base branch (기본: main).

set -uo pipefail

IN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# per-SPEC 상태 헬퍼(M1) 로드.
if ! declare -f int_set >/dev/null 2>&1; then
  # shellcheck source=state-io.sh
  . "$IN_SCRIPT_DIR/state-io.sh"
fi

LOOP_CMD_DEFAULT="bash $IN_SCRIPT_DIR/../../../skills/loop/references/loop.sh"
LOOP_CMD="${LOOP_CMD:-$LOOP_CMD_DEFAULT}"
GIT_CMD="${GIT_CMD:-git}"
FORGE_CMD="${FORGE_CMD:-gh}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
# 신뢰 봇(App bot) 로그인 정규식 — 재실행 stale 잔여의 'autopilot 소유 PR' 판정용
#   (merge.sh REVIEW_BOT_LOGINS_RE 컨벤션 동일: App bot / github-actions / courtesy-bot).
INT_REVIEW_BOT_LOGINS_RE="${INT_REVIEW_BOT_LOGINS_RE:-(\[bot\]$|^github-actions$|courtesy-bot)}"

in_die() { echo "integration: $*" >&2; return 1; }

# =====================================================================
# 1) 종료 신호 판정 — loop 공개 구조화 상태(status --json)만 사용.
#    child 종료 상태: done/failed/running/pending/unknown.
# =====================================================================

in_loop_status_json() {
  # shellcheck disable=SC2086
  $LOOP_CMD status --json "$1" 2>/dev/null
}

# in_child_terminal_state <spec> — done|failed|running|pending|unknown
#   done    : .state=terminal 이고 signals 에 BLOCKED 없음.
#   failed  : .state=terminal 이고 signals 에 BLOCKED 있음(워커 컨벤션).
#   running : .state=running|stale.   pending: idle|absent.   unknown: 상태 부재.
in_child_terminal_state() {
  local json st
  json="$(in_loop_status_json "$1")"
  if [[ -z "$json" ]]; then echo "unknown"; return; fi
  st="$(printf '%s' "$json" | yq -r '.state' 2>/dev/null)"
  case "$st" in
    terminal)
      local sigs; sigs="$(printf '%s' "$json" | yq -r '.signals[]' 2>/dev/null || true)"
      if printf '%s\n' "$sigs" | grep -Fxq 'BLOCKED'; then echo "failed"; else echo "done"; fi
      ;;
    running|stale) echo "running" ;;
    idle|absent)   echo "pending" ;;
    *) echo "unknown" ;;
  esac
}

# in_blocked_category <spec> — BLOCKED 신호 본문의 category(없으면 other).
#   loop 의 공개 `logs` 인터페이스(signals/ 본문 dump)에서 첫 'category:' 줄을 읽는다.
#   워크트리 신호 파일을 직접 열지 않는다(공개 인터페이스 경유).
in_blocked_category() {
  local cat
  # shellcheck disable=SC2086
  cat="$($LOOP_CMD logs "$1" 2>/dev/null \
    | awk 'tolower($0) ~ /^category:/ { sub(/^[Cc][Aa][Tt][Ee][Gg][Oo][Rr][Yy]:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }' \
    || true)"
  [[ -n "$cat" ]] && printf '%s\n' "$cat" || printf '%s\n' "other"
}

# =====================================================================
# 2) 브랜치·slug — rules/engineering/branch-and-slug.md 실행자.
# =====================================================================

# in_spec_title <spec_path> — frontmatter 밖 첫 H1.
in_spec_title() {
  awk '
    /^---[[:space:]]*$/ { fm = !fm; next }
    !fm && /^# / { sub(/^# /, ""); print; exit }
  ' "$1"
}

# in_slug_from_title <title> — 소문자·비영숫자→하이픈·압축.
in_slug_from_title() {
  printf '%s' "$1" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -c 'a-z0-9-' '-' \
    | sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# in_work_branch <run-id> <spec_path> — feat/<run-id>-<slug>. 빈 slug 면 중단.
in_work_branch() {
  local rid="$1" spec="$2" slug
  slug="$(in_slug_from_title "$(in_spec_title "$spec")")"
  [[ -n "$slug" ]] || { in_die "SPEC 제목에서 slug 를 만들 수 없음(제목 수정 필요): $spec"; return 1; }
  printf 'feat/%s-%s\n' "$rid" "$slug"
}

# =====================================================================
# 2b) loop 결과 → 작업 브랜치 이식 다리 (forge·direct 공통 헬퍼).
#   loop 은 결과를 자기 워크트리에만 커밋하고 run-id 작업 브랜치를 만들지 않는다.
#   통합이 push·머지 대상으로 쓰기 전에, 작업 브랜치가 없으면 loop 결과 커밋에서 만든다.
#   결과 위치는 loop 의 공개 인터페이스(`loop paths`)로만 얻는다 — 내부 신호·메타 파일을
#   직접 열지 않는다(공개 경로에서 결과 커밋을 읽는 것까지가 소비 경계). force 금지·멱등.
# =====================================================================

# in_loop_worktree <spec> — loop 공개 `paths` 출력에서 작업 트리(WT) 경로.
#   값 내부 공백을 보존한다(loop 은 경로 공백을 보존하므로 첫 토큰만 취하지 않는다).
in_loop_worktree() {
  # shellcheck disable=SC2086
  $LOOP_CMD paths "$1" 2>/dev/null \
    | awk '/^WT[[:space:]]/ { sub(/^WT[[:space:]]+/, ""); print; exit }'
}

# in_loop_result_commit <spec> — loop 결과 커밋(작업 트리 HEAD).
#   공개 경로(WT)에서 결과 커밋을 읽는다(loop 내부 신호·메타 파일 미열람).
in_loop_result_commit() {
  local wt; wt="$(in_loop_worktree "$1")"
  [[ -n "$wt" ]] || { in_die "loop 작업 트리 경로를 얻을 수 없음(loop paths): $1"; return 1; }
  local sha
  # shellcheck disable=SC2086
  sha="$($GIT_CMD -C "$wt" rev-parse HEAD 2>/dev/null)" \
    || { in_die "loop 결과 커밋(HEAD) 읽기 실패: $wt"; return 1; }
  [[ -n "$sha" ]] || { in_die "loop 결과 커밋이 비어 있음: $wt"; return 1; }
  printf '%s\n' "$sha"
}

# in_ensure_work_branch <branch> <spec> — 작업 브랜치 보장(없으면 loop 결과 커밋에서 생성).
#   이미 있으면 loop 결과 커밋을 조상으로 포함할 때만 그대로 사용(재실행 멱등) — 포함하지
#   않으면(낡은 시도의 stale 브랜치, task 605) 조용히 재사용해 결과 커밋을 유실하는 대신
#   불일치를 표면화해 차단한다. 어떤 경로에서도 force 로 옮기지 않는다.
#   forge·direct 서브모드가 공유하는 단일 진입(브랜치 이식 중복 방지).
in_ensure_work_branch() {
  local branch="$1" spec="$2"
  # 결과 커밋은 브랜치 존재 여부와 무관하게 필수 — terminal=done 은 loop 워크트리 존재를
  # 전제하므로(status 는 <WT>/.loop/signals 로 판정), 미판독은 정상 재진입이 아니라 이상이다.
  # 조용한 통과 대신 표면화한다(in_loop_result_commit 이 in_die 로 사유를 낸다).
  local commit; commit="$(in_loop_result_commit "$spec")" || return 1
  # shellcheck disable=SC2086
  if $GIT_CMD rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    if $GIT_CMD merge-base --is-ancestor "$commit" "refs/heads/$branch" 2>/dev/null; then
      return 0   # 결과 커밋 포함 — 멱등, force 재배치 안 함.
    fi
    in_die "stale 작업 브랜치: $branch 가 loop 결과 커밋($commit)을 포함하지 않음 — 조용한 재사용은 결과를 유실하므로 차단(force 재배치 금지). 정리: 로컬 브랜치 삭제(git branch -D $branch, 원격 동명 브랜치·열린 PR 도 정리) 후 재실행하세요."
    return 1
  fi
  # shellcheck disable=SC2086
  $GIT_CMD branch "$branch" "$commit" \
    || { in_die "작업 브랜치 생성 실패: $branch ← $commit"; return 1; }
}

# =====================================================================
# 3) git 통합 — base sync(rebase, ff 가능 시) → push. force 금지.
#    타겟 전진으로 인한 충돌은 워커가 전략으로 자율 해소하고 비결정 표시로 머지 전 재검증을
#    유도한다(버전 범프 정책은 컨슈밍 프로젝트 소유 — plugin.json 충돌도 일반 충돌로 처리).
#    자동 해결·재동기화·재시도는 non-force. 정책 단일 출처: 본 절 + 워커 계약(subagent-prompt.md).
# =====================================================================

# INT_AUTORESOLVE_FLAG — 직전 base sync 에서 충돌을 전략으로 해소했으면 'needs-verify'.
#   워커는 이 표시가 있으면 머지 전 검증(완료 조건/selftest)을 재실행하고 통과할 때만
#   진행한다(거짓 green 방지). 충돌 해소가 없었으면 비어 있음.
INT_AUTORESOLVE_FLAG=""

# in_autoresolve_rebase <branch> — 진행 중(충돌 정지) rebase 를 자율 해결.
#   파일별: FORGE_CONFLICT_STRATEGY (기본 incoming=재적용 중 작업 커밋 쪽 --theirs,
#   base=새 베이스 쪽 --ours) + 비결정 표시. plugin.json 버전 충돌도 일반 충돌로 처리한다
#   (버전 범프 정책은 컨슈밍 프로젝트 소유 — 통합 엔진은 버전-전용 해소를 집행하지 않음).
#   닫으면 rebase --continue 후 0, 닫지 못하면 abort 후 1. force 미사용.
in_autoresolve_rebase() {
  local branch="$1" f resolved_general=0 unmerged
  # shellcheck disable=SC2086
  unmerged="$($GIT_CMD diff --name-only --diff-filter=U 2>/dev/null)"
  [[ -n "$unmerged" ]] || { $GIT_CMD rebase --abort 2>/dev/null || true; return 1; }
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    # shellcheck disable=SC2086
    case "${FORGE_CONFLICT_STRATEGY:-incoming}" in
      base) $GIT_CMD checkout --ours   -- "$f" 2>/dev/null || true ;;
      *)    $GIT_CMD checkout --theirs -- "$f" 2>/dev/null || true ;;
    esac
    resolved_general=1
    # shellcheck disable=SC2086
    $GIT_CMD add -- "$f" 2>/dev/null || true
  done <<< "$unmerged"
  # shellcheck disable=SC2086
  if [[ -n "$($GIT_CMD diff --name-only --diff-filter=U 2>/dev/null)" ]]; then
    $GIT_CMD rebase --abort 2>/dev/null || true; return 1
  fi
  [[ "$resolved_general" == "1" ]] && INT_AUTORESOLVE_FLAG="needs-verify"
  printf 'autoresolve: base-sync rebase 자율 해결 (branch=%s general=%s flag=%s)\n' \
    "$branch" "$resolved_general" "${INT_AUTORESOLVE_FLAG:-deterministic}" >&2
  # shellcheck disable=SC2086
  $GIT_CMD rebase --continue || { $GIT_CMD rebase --abort 2>/dev/null || true; return 1; }
  return 0
}

# in_autoresolve_merge <branch> — 진행 중(충돌 정지) merge-in 을 자율 해결(open PR 재동기화 전용).
#   in_autoresolve_rebase 와 같은 전략 축이나 방향이 반대: merge-in 에선 --ours=작업 브랜치 쪽,
#   --theirs=새 베이스(origin/main) 쪽. incoming(기본)=작업 커밋 쪽 --ours, base=--theirs.
#   비결정 표시(INT_AUTORESOLVE_FLAG)는 rebase 경로와 동일 계약. 커밋은 호출자 책임.
#   닫지 못하면 merge --abort 후 1. force 미사용.
in_autoresolve_merge() {
  local branch="$1" f resolved_general=0 unmerged
  # shellcheck disable=SC2086
  unmerged="$($GIT_CMD diff --name-only --diff-filter=U 2>/dev/null)"
  [[ -n "$unmerged" ]] || { $GIT_CMD merge --abort 2>/dev/null || true; return 1; }
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    # shellcheck disable=SC2086
    case "${FORGE_CONFLICT_STRATEGY:-incoming}" in
      base) $GIT_CMD checkout --theirs -- "$f" 2>/dev/null || true ;;
      *)    $GIT_CMD checkout --ours   -- "$f" 2>/dev/null || true ;;
    esac
    resolved_general=1
    # shellcheck disable=SC2086
    $GIT_CMD add -- "$f" 2>/dev/null || true
  done <<< "$unmerged"
  # shellcheck disable=SC2086
  if [[ -n "$($GIT_CMD diff --name-only --diff-filter=U 2>/dev/null)" ]]; then
    $GIT_CMD merge --abort 2>/dev/null || true; return 1
  fi
  [[ "$resolved_general" == "1" ]] && INT_AUTORESOLVE_FLAG="needs-verify"
  printf 'autoresolve: open-PR base 재동기화 merge-in 자율 해결 (branch=%s general=%s flag=%s)\n' \
    "$branch" "$resolved_general" "${INT_AUTORESOLVE_FLAG:-deterministic}" >&2
  return 0
}

# in_resync_open_pr <branch> — open PR 재실행 경로의 base 정합(#626). 분리 워크트리 안에서 호출됨.
#   원격 tip(리뷰 수정 푸시로 로컬 ref 보다 앞설 수 있음) 기준으로 origin/main merge-in 을 시도:
#     클린(충돌 없음) → 병합을 버리고 기존 동작 유지(재작성·push 없음 — 머지 단계 ff 게이트가 정합).
#     충돌           → 전략 자율 해소로 머지 커밋 생성 후 원격 작업 브랜치로 직접 push(non-force,
#                      merge-in 은 원격 tip 위에 커밋을 얹으므로 fast-forward push 성립).
#     해소 불가       → 병합 중단 후 1 — integrate 가 즉시 차단(리뷰 폴링 진입 전, 상한 미소진).
in_resync_open_pr() {
  local branch="$1" tip
  # shellcheck disable=SC2086
  $GIT_CMD fetch origin "$branch" >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  tip="$($GIT_CMD rev-parse --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null)" || tip=""
  # shellcheck disable=SC2086
  [[ -n "$tip" ]] || tip="$($GIT_CMD rev-parse "refs/heads/$branch" 2>/dev/null)"
  [[ -n "$tip" ]] || { in_die "open PR 재동기화: 브랜치 tip 확인 실패: $branch"; return 1; }
  # 분리 HEAD 를 원격 tip 으로 이동(워크트리는 이미 detached — reset 은 브랜치 ref 를 건드리지 않음).
  # shellcheck disable=SC2086
  $GIT_CMD reset --hard "$tip" >/dev/null 2>&1 \
    || { in_die "open PR 재동기화: tip 이동 실패: $branch"; return 1; }
  # shellcheck disable=SC2086
  if $GIT_CMD merge --no-commit --no-ff "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
    # 충돌 없음 — 기존 동작 보존: 재작성·push 없이 반환(정합은 머지 단계 ff-only 게이트가 강제).
    $GIT_CMD merge --abort >/dev/null 2>&1 || true
    return 0
  fi
  in_autoresolve_merge "$branch" \
    || { in_die "open PR 재동기화 충돌 자율 해소 실패 — 사람 위임(force 금지): $branch ← origin/$DEFAULT_BRANCH"; return 1; }
  # shellcheck disable=SC2086
  $GIT_CMD commit -m "merge: origin/$DEFAULT_BRANCH into $branch — base 재동기화(충돌 자율 해소)" >/dev/null 2>&1 \
    || { $GIT_CMD merge --abort >/dev/null 2>&1 || true
         in_die "open PR 재동기화 머지 커밋 실패: $branch"; return 1; }
  # shellcheck disable=SC2086
  $GIT_CMD push origin "HEAD:refs/heads/$branch" >/dev/null 2>&1 \
    || { in_die "open PR 재동기화 push 실패(force 금지): $branch"; return 1; }
  INT_BASESYNC_PUSHED=1
  return 0
}

# in_base_sync <branch> — 작업 브랜치를 origin/main 으로 정합(필요 시 rebase)한다.
#   #452: rebase 를 공유 체크아웃에서 수행하면 (성공 시에도) 공유 체크아웃이 작업 브랜치로 남고,
#   병렬 실행 시 서로의 브랜치를 덮어쓰는 경쟁이 생긴다. 그래서 **전용 분리(detached) 임시 워크트리**를
#   만들어 그 안에서(git -C <wt>) 코어를 실행하고 끝나면 제거한다 — 공유 체크아웃을 전혀 건드리지
#   않으므로 병렬에서도 안전하다. `--detach` 라 같은 브랜치가 다른 곳(예: 이전 실행이 남긴 공유
#   체크아웃)에 체크아웃돼 있어도 워크트리 생성이 실패하지 않는다. rebase 가 필요한 경우 그 결과를
#   **원격 작업 브랜치로 직접 push** 하고(로컬 $branch ref 미갱신 → 공유 체크아웃 미오염) INT_BASESYNC_PUSHED
#   를 세워 in_integrate 가 in_push_branch 를 건너뛰게 한다. rebase 불필요(조기 반환) 경우엔 in_push_branch 가 push.
in_base_sync() {
  local branch="$1" _rc _wt _gd _save_git="$GIT_CMD"
  INT_BASESYNC_PUSHED=""
  _wt="$(mktemp -d)/wt"
  # shellcheck disable=SC2086
  $GIT_CMD worktree add --quiet --detach "$_wt" "$branch" \
    || { in_die "전용 워크트리 생성 실패: $branch"; rmdir "$(dirname "$_wt")" 2>/dev/null || true; return 1; }
  # 코어의 모든 git 호출을 전용 워크트리(분리 HEAD)로 지정. 공유 체크아웃은 전혀 건드리지 않는다.
  # 코어는 rebase 가 필요하면 그 결과를 원격으로 직접 push 하고 INT_BASESYNC_PUSHED=1 을 세운다.
  GIT_CMD="$_save_git -C $_wt"
  _in_base_sync_core "$branch"; _rc=$?
  # 실패-경로의 mid-rebase 만 조건부 정리(성공/조기반환 경로엔 불필요한 rebase 호출을 남기지 않음).
  # shellcheck disable=SC2086
  _gd="$($GIT_CMD rev-parse --absolute-git-dir 2>/dev/null || true)"
  if [[ -n "$_gd" && ( -d "$_gd/rebase-merge" || -d "$_gd/rebase-apply" ) ]]; then
    # shellcheck disable=SC2086
    $GIT_CMD rebase --abort >/dev/null 2>&1 || true
  fi
  GIT_CMD="$_save_git"
  # shellcheck disable=SC2086
  $GIT_CMD worktree remove "$_wt" >/dev/null 2>&1 || true
  rmdir "$(dirname "$_wt")" 2>/dev/null || true
  return "$_rc"
}

_in_base_sync_core() {
  local branch="$1"
  local tries="${FORGE_BASESYNC_RETRIES:-3}" i=0 pre post
  INT_AUTORESOLVE_FLAG=""
  # shellcheck disable=SC2086
  $GIT_CMD fetch origin "$DEFAULT_BRANCH" || { in_die "fetch 실패: origin/$DEFAULT_BRANCH"; return 1; }
  # #452: 작업 브랜치를 checkout 하지 않는다 — 워크트리가 이미 그 커밋에서 분리(detached)돼 있고,
  # 같은 브랜치를 checkout 하면 다른 워크트리에 체크아웃된 경우 충돌한다. rebase 는 분리 HEAD 에서
  # 수행하고, 그 결과는 원격 작업 브랜치로 직접 push 한다(로컬 $branch ref 미갱신 → 공유 체크아웃 미오염).
  # origin/main 이 이미 브랜치 조상이면 동기화 불필요 — 재작성 없이 push 는 fast-forward.
  # shellcheck disable=SC2086
  if $GIT_CMD merge-base --is-ancestor "origin/$DEFAULT_BRANCH" "$branch" 2>/dev/null; then
    return 0
  fi
  # base 가 전진했고 원격 브랜치(open PR)가 이미 있으면, rebase 재작성은 SHA 를 바꿔 force 없는
  # push 를 non-fast-forward 로 실패시킨다. 충돌이 없으면 재작성하지 않고 그대로 둔다 — base 정합은
  # 머지 단계의 ff-only 게이트(그쪽도 자율 재동기화)가 강제한다. 단, **충돌**이면 그대로 두면 리뷰가
  # 영영 승인 불가(재실행 무한 루프, #626) — rebase 대신 origin/main 을 merge-in(history 미재작성
  # → non-force push, rules/version-control/git.md)해 해소 후 직접 push 한다.
  if [[ -n "$(in_existing_open_pr "$branch")" ]]; then
    in_resync_open_pr "$branch"
    return $?
  fi
  # 최초 통합(원격 브랜치 미존재): rebase 후 push(ff-safe). 충돌은 자율 해결하고, 해결 도중
  # 타겟이 또 전진하면(레이스) 갱신된 origin/main 으로 유한 횟수 재rebase 한다(non-force).
  while : ; do
    # shellcheck disable=SC2086
    pre="$($GIT_CMD rev-parse "origin/$DEFAULT_BRANCH" 2>/dev/null)"
    # shellcheck disable=SC2086
    if ! $GIT_CMD rebase "origin/$DEFAULT_BRANCH"; then
      in_autoresolve_rebase "$branch" \
        || { in_die "rebase 충돌 자율 해결 실패 — 사람 위임(force 금지): $branch ← origin/$DEFAULT_BRANCH"; return 1; }
    fi
    # 레이스 감지: 자율 해결 도중 origin/main 이 전진했으면 재시도.
    # shellcheck disable=SC2086
    $GIT_CMD fetch origin "$DEFAULT_BRANCH" 2>/dev/null || true
    # shellcheck disable=SC2086
    post="$($GIT_CMD rev-parse "origin/$DEFAULT_BRANCH" 2>/dev/null)"
    [[ "$pre" == "$post" ]] && break
    i=$((i+1))
    [[ "$i" -ge "$tries" ]] && { in_die "base sync 레이스 한도 초과($tries) — 사람 위임(force 금지): $branch"; return 1; }
  done
  # #452: rebase 결과(분리 HEAD)를 원격 작업 브랜치로 **직접 push** 한다 — 로컬 $branch ref 를
  # 갱신하지 않으므로, 그 브랜치가 공유 체크아웃에 체크아웃돼 있어도 공유 체크아웃을 더럽히지 않는다.
  # (이 분기는 원격 브랜치 미존재 = 최초 통합이라 ff-safe.) in_integrate 는 INT_BASESYNC_PUSHED 를
  # 보고 in_push_branch 를 건너뛴다.
  # shellcheck disable=SC2086
  $GIT_CMD push origin "HEAD:refs/heads/$branch" \
    || { in_die "작업 브랜치 push 실패(force 금지): $branch"; return 1; }
  INT_BASESYNC_PUSHED=1
  return 0
}

# in_worktree_delta_commit <branch> <ref_commit> — 로컬 브랜치 ref 뒤에 남은 워크트리 델타 커밋.
#   #452 설계상 loop·리뷰 재구현은 분리(detached) 워크트리 HEAD 만 전진시키고 로컬 브랜치 ref 는
#   갱신하지 않는다(공유 체크아웃 미오염). 그래서 리뷰-수정 커밋은 브랜치 ref 에 없고 워크트리
#   HEAD 에만 있다(run 638) — ref 만 보면 "원격-앞섬"으로 오판해 push 를 생략하고 수정을 유실한다.
#   ref_commit 의 **엄격한 자손**인 워크트리 HEAD 를 실제 통합 대상으로 되찾는다. 되찾을 것이
#   없으면 빈 출력(= 기존 ref 기준 동작). 오염 방지 가드:
#     - 브랜치 ref 가 이미 origin/<default> 에 포함되면(머지 완료 등) 무관한 run 워크트리가
#       자손으로 잡힐 수 있으므로 되찾지 않는다.
#     - 자손 후보가 둘 이상이면 어느 것이 대상인지 모호하므로 되찾지 않는다.
in_worktree_delta_commit() {
  local branch="$1" ref_commit="$2" c cands=""
  [[ -n "$ref_commit" ]] || return 0
  # 가드 판정 전에 base 를 fetch 한다 — stale 한 origin/<default> 로는 "이미 머지됨"을 놓쳐
  # 가드가 헛돈다(무관 워크트리 커밋 되찾기 위험).
  # shellcheck disable=SC2086
  $GIT_CMD fetch origin "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  if $GIT_CMD merge-base --is-ancestor "refs/heads/$branch" "origin/$DEFAULT_BRANCH" 2>/dev/null; then
    return 0
  fi
  while read -r c; do
    [[ -n "$c" && "$c" != "$ref_commit" ]] || continue
    # shellcheck disable=SC2086
    $GIT_CMD merge-base --is-ancestor "$ref_commit" "$c" 2>/dev/null && cands="$cands $c"
  done < <($GIT_CMD worktree list --porcelain 2>/dev/null | awk '$1=="HEAD" { print $2 }')
  # shellcheck disable=SC2086
  set -- $cands
  if [[ "$#" -gt 1 ]]; then
    # 조용히 생략하면 이 결함(리뷰-수정 유실)이 흔적 없이 재발한다 — 표면화한다.
    echo "integration: 워크트리 델타 후보가 둘 이상($*) — 통합 대상 모호로 되찾지 않음: $branch" >&2
    return 0
  fi
  [[ "$#" -eq 1 ]] && printf '%s\n' "$1"
  return 0
}

in_push_branch() {
  # 원격-앞섬 정합(run 592): **통합 대상 커밋**이 원격 tip 의 조상이면(리뷰 수정 푸시 등 정당한
  # 전진으로 원격이 앞섬) 원격이 이미 모든 로컬 커밋을 보유 — push 는 불필요하고 non-ff 로
  # 거부만 되므로 건너뛴다. 통합 대상은 stale 할 수 있는 로컬 브랜치 ref 가 아니라 그 뒤의
  # 워크트리 델타 커밋까지 포함한다(run 638). fetch 시점 레이스 완화를 위해 판정 직전에 원격
  # ref 를 fetch 한다. force 금지 유지.
  local branch="$1" tip ref_commit delta local_commit refspec
  # shellcheck disable=SC2086
  ref_commit="$($GIT_CMD rev-parse "refs/heads/$branch" 2>/dev/null)"
  delta="$(in_worktree_delta_commit "$branch" "$ref_commit")"
  local_commit="${delta:-$ref_commit}"
  tip="$(in_remote_tip "$branch")"
  if [[ -n "$tip" ]]; then
    # shellcheck disable=SC2086
    $GIT_CMD fetch origin "$branch" >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    if [[ -n "$local_commit" ]] && $GIT_CMD merge-base --is-ancestor "$local_commit" "$tip" 2>/dev/null; then
      echo "integration: push 생략 — 원격 브랜치가 통합 대상 커밋을 이미 포함(원격-앞섬): $branch" >&2
      return 0
    fi
  fi
  # 델타가 있으면 그 커밋을 원격 작업 브랜치로 **직접 push** 한다(#452 와 동일 방식) — 로컬
  # $branch ref 를 갱신하지 않으므로 공유 체크아웃을 더럽히지 않는다. force 아님(ff push).
  refspec="$branch"
  [[ -n "$delta" ]] && refspec="$delta:refs/heads/$branch"
  # shellcheck disable=SC2086
  $GIT_CMD push origin "$refspec" || { in_die "push 실패(force 금지): $branch"; return 1; }
}

# =====================================================================
# 3d) CHANGELOG 순수-추가 게이트 (#628) — CHANGELOG 는 누적 계약(추가만).
#   워커가 base 전진을 못 따라가 기존 섹션을 자기 항목으로 덮어쓰면(기존 라인 삭제) 직전
#   릴리스 기록이 소실된 채 머지될 수 있다(리뷰 봇 포착은 확률적). 통합이 결정적으로 막는다:
#   base 대비 브랜치 쪽 변경(three-dot diff = merge-base 기준)이 CHANGELOG 라인을 삭제하면
#   머지 후보(PR·리뷰)로 통과시키지 않고 차단한다. three-dot 이라 base 전진분(형제 머지)은
#   오탐하지 않고, base 재동기화 merge-in 이 main 항목을 덮어쓴 경우는 merge-base 전진으로
#   잡힌다. 경로는 INT_CHANGELOG_FILE 로 설정 가능(기본 CHANGELOG.md) — 빈 값이면 게이트
#   비활성(정당한 오타 수정·항목 재배치 우회), base 에 파일이 없으면 적용하지 않는다
#   (버전·changelog 정책은 컨슈밍 프로젝트 소유 — 존재할 때만 계약을 지킨다).
# =====================================================================

# in_changelog_additive_gate <branch> — 순수-추가면 0, 기존 라인 삭제 감지면 1(사유 stderr).
#   INT_BASESYNC_PUSHED=1 이면 base sync 가 분리 워크트리에서 원격으로 직접 push 한 상태라
#   로컬 ref 가 결과를 반영하지 않는다 — 원격 tip(origin/<branch>)을 게이트 대상으로 삼는다.
in_changelog_additive_gate() {
  local branch="$1" file="${INT_CHANGELOG_FILE-CHANGELOG.md}" base ref del
  [[ -n "$file" ]] || return 0        # 빈 값 = 게이트 비활성(명시적 우회).
  # shellcheck disable=SC2086
  if $GIT_CMD rev-parse --verify --quiet "refs/remotes/origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
    base="refs/remotes/origin/$DEFAULT_BRANCH"
  elif $GIT_CMD rev-parse --verify --quiet "refs/heads/$DEFAULT_BRANCH" >/dev/null 2>&1; then
    base="refs/heads/$DEFAULT_BRANCH"
  else
    return 0                          # base 미상 → 판정 불가, 게이트 미적용.
  fi
  # shellcheck disable=SC2086
  $GIT_CMD cat-file -e "$base:$file" 2>/dev/null || return 0   # base 에 파일 존재할 때만 적용.
  if [[ "${INT_BASESYNC_PUSHED:-}" == "1" ]]; then
    # shellcheck disable=SC2086
    $GIT_CMD fetch origin "$branch" >/dev/null 2>&1 || true
    ref="refs/remotes/origin/$branch"
  else
    ref="refs/heads/$branch"
  fi
  # 삭제 라인 수: diff '-' 줄 중 파일 헤더(정확히 '--- a/…' 또는 '--- /dev/null')와 빈 줄
  # 삭제(단독 '-')는 제외. 헤더를 '^---' 전체로 제외하면 '-- ' 로 시작하는 콘텐츠 라인의
  # 삭제('---…' 로 렌더)가 미탐된다 — 실제 헤더 형태만 정확히 제외한다.
  # shellcheck disable=SC2086
  del="$($GIT_CMD diff "$base...$ref" -- "$file" 2>/dev/null \
    | awk '/^-/ && !/^--- (a\/|\/dev\/null)/ && $0 != "-" { n++ } END { print n+0 }')"
  if [[ "${del:-0}" -gt 0 ]]; then
    in_die "CHANGELOG 순수-추가 게이트: $file 의 기존 라인 ${del}개 삭제 감지 — CHANGELOG 는 누적 계약(추가만)이라 머지 후보로 통과시키지 않는다(branch=$branch). 기존 섹션을 덮어쓰지 말고 자기 항목을 최상단에 '추가'로 재작성하세요. 정당한 오타 수정·항목 재배치라면 INT_CHANGELOG_FILE='' 로 게이트를 끄고 재실행해 우회할 수 있다."
    return 1
  fi
  return 0
}

# =====================================================================
# 3c) 재실행 stale 잔여 정리 — 직전 실패/blocked 시도가 남긴 원격 작업 브랜치/열린 PR 이
#   현재 로컬 작업 커밋과 non-ff 비호환이고 **현재 실행 소유 stale 잔여**로 식별되면,
#   push 전에 안전하게 정리(PR close + 원격 브랜치 삭제)해 non-ff push 거부를 막는다.
#   force 금지(브랜치 삭제는 history 재작성이 아님). 소유 신호 두 가지를 **모두** 만족할
#   때만 정리하고, 그렇지 않으면(외부 생성 동명 브랜치 가능) **건드리지 않는다**(오삭제 방지):
#     1. 원격에 결정적 작업 브랜치명(feat/<rid>-<slug>)이 존재(= 이 함수에 넘어온 branch).
#     2. 그 위 열린 PR 이 신뢰 봇(App bot) 작성이고 *-formal-review 마커를 가짐.
# =====================================================================

# in_remote_tip <branch> — origin 의 작업 브랜치 tip SHA(ls-remote). 미존재면 빈 출력.
in_remote_tip() {
  # shellcheck disable=SC2086
  $GIT_CMD ls-remote --heads origin "$1" 2>/dev/null | awk 'NR==1 { print $1 }'
}

# in_remote_ff_incompatible <branch> <local_commit> — 원격 브랜치가 존재하고 그 tip 이
#   local_commit 의 조상이 **아니면**(force 없는 push 가 non-fast-forward 로 거부) 0,
#   원격 미존재 또는 ff 호환이면 1. ancestry 비교용 객체를 위해 원격 ref 를 fetch 한다.
in_remote_ff_incompatible() {
  local branch="$1" local_commit="$2" tip
  tip="$(in_remote_tip "$branch")"
  [[ -n "$tip" ]] || return 1          # 원격 미존재 → 호환(신규 push).
  # shellcheck disable=SC2086
  $GIT_CMD fetch origin "$branch" >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  $GIT_CMD merge-base --is-ancestor "$tip" "$local_commit" 2>/dev/null && return 1
  # 원격-앞섬(로컬이 원격 tip 의 조상): 원격이 이미 로컬 커밋을 모두 보유(리뷰 수정 푸시 등
  # 정당한 전진) — stale 잔여가 아니라 건강한 상태이므로 보존한다(push 는 in_push_branch 가
  # 원격-앞섬을 감지해 생략 → non-ff 문제 없음). run 592 회귀: 오판 시 리뷰 커밋 파괴.
  # shellcheck disable=SC2086
  $GIT_CMD merge-base --is-ancestor "$local_commit" "$tip" 2>/dev/null && return 1
  return 0
}

# in_pr_autopilot_owned <pr> — 열린 PR 이 autopilot 소유 신호를 모두 가지면 0, 아니면 1.
#   (a) 작성자 login 이 신뢰 봇(App bot), (b) 그 PR 에 신뢰 봇이 남긴 *-formal-review 마커 존재.
#   #432: 봇 정규식은 login 필드 단독에 적용한다(login\tbody 결합 라인 grep 은 앵커가 깨짐).
in_pr_autopilot_owned() {
  local pr="$1" author
  [[ -n "$pr" ]] || return 1
  # shellcheck disable=SC2086
  author="$($FORGE_CMD pr view "$pr" --json author --jq '.author.login' 2>/dev/null)"
  printf '%s\n' "$author" | grep -qE "$INT_REVIEW_BOT_LOGINS_RE" || return 1
  # shellcheck disable=SC2086
  $FORGE_CMD pr view "$pr" --json reviews \
      --jq '.reviews[] | (.author.login // "")+"\t"+((.body // "")|gsub("[\n\t]";" "))' 2>/dev/null \
    | awk -F'\t' '$2 ~ /-formal-review/ { print $1 }' \
    | grep -qE "$INT_REVIEW_BOT_LOGINS_RE"
}

# in_clear_stale_residue <branch> — 재실행 진입 시 non-ff 인 autopilot-소유 stale 잔여 정리.
#   두 소유 신호를 모두 만족할 때만 PR close + 원격 브랜치 삭제(force 아님). 그 외는 보존.
#   정리는 통합의 사전 단계 — 실패해도 rc 를 바꾸지 않고(후속 push 가 비호환을 표면화) 0 반환.
in_clear_stale_residue() {
  local branch="$1" local_commit pr
  [[ -n "$branch" ]] || return 0
  # shellcheck disable=SC2086
  local_commit="$($GIT_CMD rev-parse "refs/heads/$branch" 2>/dev/null)"
  [[ -n "$local_commit" ]] || return 0
  in_remote_ff_incompatible "$branch" "$local_commit" || return 0   # 원격부재/ff호환 → 보존.
  pr="$(in_existing_open_pr "$branch")"
  [[ -n "$pr" ]] || return 0                                        # 열린 PR 없음 → 소유 확증 불가 → 보존.
  in_pr_autopilot_owned "$pr" || return 0                           # 외부 소유 가능 → 미훼손(보존).
  echo "integration: 재실행 stale 잔여 정리(non-ff) — PR #$pr close + 원격 브랜치 삭제(force 금지): $branch" >&2
  # shellcheck disable=SC2086
  $FORGE_CMD pr close "$pr" >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  $GIT_CMD push origin --delete "$branch" >/dev/null 2>&1 || true
  return 0
}

# in_stale_remote_guard <branch> — 자동 정리 불가한 stale 원격 작업 브랜치를 push 전에 차단(#630).
#   in_clear_stale_residue 가 정리하지 못한 잔재(열린 PR 없음 = 소유 확증 불가)가 non-ff 로 남아
#   있으면, base sync 는 이를 '최초 통합(원격 미존재)'으로 오인해 push 하고 "push 실패" 한 줄로만
#   끝난다 — 무엇을 어떻게 치울지 알 수 없어 재실행이 같은 자리에서 무한 반복된다. 여기서 정리
#   방법을 담은 사유로 즉시 차단한다. force 재배치·소유 미확증 원격 자동 삭제는 하지 않는다.
#   열린 PR 이 있는 경로는 기존 재동기화(in_resync_open_pr)가 처리하므로 건드리지 않는다.
in_stale_remote_guard() {
  local branch="$1" local_commit
  [[ -n "$branch" ]] || return 0
  # shellcheck disable=SC2086
  local_commit="$($GIT_CMD rev-parse "refs/heads/$branch" 2>/dev/null)"
  [[ -n "$local_commit" ]] || return 0
  in_remote_ff_incompatible "$branch" "$local_commit" || return 0   # 원격부재/ff호환 → 기존 동작.
  [[ -z "$(in_existing_open_pr "$branch")" ]] || return 0           # 열린 PR → 재동기화 경로 소관.
  in_die "stale 원격 작업 브랜치: origin/$branch 가 이번 결과 커밋($local_commit)과 non-fast-forward 라 force 없이 push 할 수 없다(force 금지). 열린 PR 이 없어 소유를 확증할 수 없으므로 자동 삭제하지 않는다. 정리: (1) 'git fetch origin $branch && git log --oneline origin/$branch' 로 보존할 커밋이 없는지 확인, (2) 'git push origin --delete $branch' 로 원격 브랜치 삭제, (3) execute-task start 로 재실행."
  return 1
}

# =====================================================================
# 3b) 실패/터미널 경로 조건부 워크트리 정리 — "보존되면 정리, 아니면 보존"(비대칭).
#   머지 성공 경로는 merge.sh 가 무조건 정리(머지=대상 브랜치에 보존)한다. 여기서는 실패/비완료
#   터미널에서 #350 의 고아 워크트리를 정리하되, 그 작업이 다른 곳에 보존돼 있을 때만 정리한다.
#   "보존됨" 판정 단일 출처 = 작업 브랜치가 대상 리모트(origin)에 존재(=통합 단계에서 push 됨).
#   정리는 loop 공개 cleanup 위임으로만 수행(직접 rm 금지) — loop cleanup 의 신호 가드가
#   비터미널(실행 중) 워크트리를 비파괴로 보존하므로, 실행 중 워크트리는 위임해도 지워지지 않는다.
# =====================================================================

# in_branch_on_remote <branch> — 작업 브랜치가 대상 리모트에 존재하면 0, 아니면 1.
#   원격 ref 를 직접 조회(ls-remote)해 로컬 추적 ref 의 stale 가능성을 피한다. 빈 브랜치명은
#   '미보존'으로 본다(보수적 — 의심 시 보존). 위험: 오판 시 미보존 WIP 를 지우지 않도록 보존 쪽.
in_branch_on_remote() {
  local branch="$1"
  [[ -n "$branch" ]] || return 1
  local out
  # shellcheck disable=SC2086
  out="$($GIT_CMD ls-remote --heads origin "$branch" 2>/dev/null)"
  [[ -n "$out" ]]
}

# in_cleanup_worktree_if_preserved <spec> <branch> — 실패/터미널 경로 조건부 워크트리 정리.
#   작업이 원격 브랜치로 보존돼 있으면 loop 공개 cleanup 위임으로 정리하고, 미보존(원격에 없음
#   = 워크트리가 유일 사본)이면 보존한다(디버깅·재개). 정리 실패는 경고로 표면화(조용한 실패
#   금지)하되 호출자의 머지·완료 판정(rc)을 뒤집지 않는다(정리는 터미널 판정의 사후 단계). rc 0 유지.
in_cleanup_worktree_if_preserved() {
  local spec="$1" branch="$2"
  [[ -n "$spec" ]] || return 0
  if in_branch_on_remote "$branch"; then
    # shellcheck disable=SC2086
    $LOOP_CMD cleanup "$spec" >/dev/null 2>&1 \
      || echo "WARN: 워크트리 cleanup 위임 실패(수동 정리 가능, 머지·완료 판정 유지): $spec" >&2
  else
    echo "INFO: 작업 브랜치 원격 미보존 → 워크트리 보존(유일 사본·디버깅·재개): $spec" >&2
  fi
  return 0
}

# in_cleanup_failed_worktree <spec> <run_dir> — 실패-경로 진입점(브랜치명을 결정적으로 도출).
#   작업 브랜치명은 rid(run_dir basename)+SPEC slug 로 결정적(in_work_branch). slug 도출 실패 시
#   브랜치 미상 → 보존(보수적). in_handle_blocked(워커 자기 escalation)와 호출 레이어의
#   child 종료 정리(CLI: cleanup-on-fail)가 공유하는 단일 진입.
in_cleanup_failed_worktree() {
  local spec="$1" rd="$2" branch
  local rid; rid="$(basename "$rd")"
  branch="$(in_work_branch "$rid" "$spec" 2>/dev/null || true)"
  in_cleanup_worktree_if_preserved "$spec" "$branch"
}

# =====================================================================
# 4) PR 생성/재사용 — 같은 head 의 open PR 이 있으면 재사용.
#    본문은 정적 한 줄이 아니라 in_pr_body 의 구조화 본문(이슈 참조·요약·작업 내용).
# =====================================================================

in_existing_open_pr() {
  # shellcheck disable=SC2086
  $FORGE_CMD pr list --head "$1" --state open 2>/dev/null \
    | awk 'NR==1 { print $1 }' | tr -d '#'
}

# in_pr_summary <spec_path> — SPEC 의 '## 무엇을 만들 것인가' 섹션 본문(HTML 설명 주석 제거).
#   섹션이 없으면 빈 출력(호출자가 요약 블록을 생략). 다음 헤딩(#/##)에서 경계를 닫는다.
#   섹션 헤더 문자열에 과결합하지 않도록 정확 헤더 한 줄만 인식하고, 그 외 형식 변화엔
#   "요약 생략 + 나머지 정상" 으로 강건하게 동작한다(SPEC 제약).
in_pr_summary() {
  awk '
    /^##?[[:space:]]/ {
      if (insec) exit
      if ($0 ~ /^## 무엇을 만들 것인가[[:space:]]*$/) { insec = 1; next }
    }
    insec {
      if (incmt) { if (index($0, "-->")) incmt = 0; next }
      if ($0 ~ /^[[:space:]]*<!--/) { if (!index($0, "-->")) incmt = 1; next }
      print
    }
  ' "$1"
}

# in_spec_issue <spec_path> — frontmatter 의 이슈 식별 정보(issue: 키). 없으면 빈 출력.
#   forward-compatible: 키가 SPEC 에 존재할 때만 값을 내고, 따옴표·선행 '#' 표기를 정규화한다.
in_spec_issue() {
  awk '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm && /^---[[:space:]]*$/ { exit }
    fm && /^issue:[[:space:]]*/ {
      sub(/^issue:[[:space:]]*/, ""); gsub(/["'\''#[:space:]]/, ""); print; exit
    }
  ' "$1"
}

# in_done_summary <spec_path> — loop 공개 logs 인터페이스(`loop logs`)에서 워커가 signals/DONE
#   에 남긴 완료 요약(diff 기반 무엇을·왜) 본문을 추출한다. DONE 신호가 없거나 본문이 비어 있으면
#   빈 출력(호출자가 '## 작업 내용' 섹션을 생략). 내부 signals 파일을 직접 열지 않고, `logs` 출력의
#   "===== signals/DONE =====" 섹션만 골라낸다(다음 "===== " 섹션 경계에서 닫음, in_pr_summary 와
#   동일 패턴).
in_done_summary() {
  # shellcheck disable=SC2086
  $LOOP_CMD logs "$1" 2>/dev/null | awk '
    /^===== signals\/DONE =====$/ { insec = 1; next }
    insec && /^===== / { exit }
    insec { print }
  '
}

# in_pr_body <spec_path> — 구조화 PR 본문(결정적) stdout. 단일 경로(#556) — 발신 주체 구분
#   없음(라이브 호출자는 execute-task 뿐). 사람이 읽는 실질 내용만 담는다(#554 — 자동생성 안내
#   문구·run 추적 줄 없음): 조건부 이슈 cross-reference(Refs #n, rules/context.md 형식)
#   + 요약(SPEC 의도 섹션, 없으면 생략) + 작업 내용(loop DONE 완료 요약, 없으면 생략; #539).
#   첫 요소(Refs 또는 요약)가 선행 공백 줄 없이 시작하도록 블록 사이에만 빈 줄을 넣는다.
in_pr_body() {
  local spec="$1" first=1
  local issue; issue="$(in_spec_issue "$spec")"
  if [[ -n "$issue" ]]; then printf 'Refs #%s\n' "$issue"; first=0; fi
  local summary; summary="$(in_pr_summary "$spec")"
  if [[ -n "${summary//[$' \t\n']/}" ]]; then
    [[ "$first" == 1 ]] || printf '\n'
    printf '## 요약\n\n%s\n' "$summary"
    first=0
  fi
  local done_summary; done_summary="$(in_done_summary "$spec")"
  if [[ -n "${done_summary//[$' \t\n']/}" ]]; then
    [[ "$first" == 1 ]] || printf '\n'
    printf '## 작업 내용\n\n%s\n' "$done_summary"
  fi
}

# in_ensure_pr <branch> <title> <spec> — open PR 재사용 또는 신규 생성. PR 번호 echo.
#   신규 생성 PR 에만 자동 리뷰 표시를 단다(제목 '🤖 [자동 리뷰]' 접두) —
#   open PR 재사용(조기 반환) 경로는 기존 PR 제목·본문을 건드리지 않는다(수정 호출 없음).
#   본문은 임시 파일 + --body-file 로 전달해 셸 인용·줄바꿈 손상 없이 멀티라인을 보존한다.
in_ensure_pr() {
  local branch="$1" title="$2" spec="$3" n
  n="$(in_existing_open_pr "$branch")"
  if [[ -n "$n" ]]; then printf '%s\n' "$n"; return 0; fi
  local bodyf; bodyf="$(mktemp)" || { in_die "PR 본문 임시 파일 생성 실패"; return 1; }
  in_pr_body "$spec" > "$bodyf"
  # shellcheck disable=SC2086
  $FORGE_CMD pr create --head "$branch" --base "$DEFAULT_BRANCH" \
    --title "🤖 [자동 리뷰] $title" --body-file "$bodyf" \
    >/dev/null 2>&1 || { rm -f "$bodyf"; in_die "PR 생성 실패: $branch"; return 1; }
  rm -f "$bodyf"
  in_existing_open_pr "$branch"
}

# =====================================================================
# 5) 메인 진입 — 한 SPEC 의 종료 신호를 읽어 매핑·통합한다.
# =====================================================================

# in_integrate <spec> <run_dir> <key>
#   반환: 0=통합 성공(int-phase=review) / 3=spec-gap 차단 / 4=하드 차단 / 20=미종료(대기).
in_integrate() {
  local spec="$1" rd="$2" key="$3"
  [[ -n "$spec" && -n "$rd" && -n "$key" ]] || { in_die "사용: integration.sh integrate <spec> <run_dir> <key>"; return 1; }
  mkdir -p "$rd"
  local rid; rid="$(basename "$rd")"

  local term; term="$(in_child_terminal_state "$spec")"
  int_log "$rd" "$key" "integrate spec=$spec terminal=$term"

  case "$term" in
    done)
      local branch; branch="$(in_work_branch "$rid" "$spec")" || { int_set_phase "$rd" "$key" blocked; return 4; }
      int_set_branch "$rd" "$key" "$branch"
      int_set_phase "$rd" "$key" integrating
      # 다리: push 대상으로 쓰기 전에 작업 브랜치가 없으면 loop 결과 커밋에서 생성(멱등).
      in_ensure_work_branch "$branch" "$spec" || { int_set_phase "$rd" "$key" blocked; return 4; }
      # 재실행 안전: 직전 실패/blocked 가 남긴 non-ff·autopilot-소유 stale 원격 브랜치/PR 을
      # push 전에 정리(force 금지·미소유 보존) — non-ff push 거부를 막는다.
      in_clear_stale_residue "$branch"
      # 정리하지 못한 non-ff 잔재는 push 전에 정리 방법을 담은 사유로 차단(#630) — 재실행 무한 반복 방지.
      in_stale_remote_guard "$branch" || { int_set_phase "$rd" "$key" blocked; return 4; }
      int_log "$rd" "$key" "base sync → push → PR (branch=$branch)"
      in_base_sync   "$branch" || { int_set_phase "$rd" "$key" blocked; return 4; }
      # #452: rebase 경로에선 base_sync 가 분리 워크트리에서 원격으로 직접 push 하므로(INT_BASESYNC_PUSHED)
      # in_push_branch 를 건너뛴다. rebase 불필요(조기 반환) 경로에선 ref 이름으로 push.
      [[ "${INT_BASESYNC_PUSHED:-}" == "1" ]] || in_push_branch "$branch" || { int_set_phase "$rd" "$key" blocked; return 4; }
      # CHANGELOG 순수-추가 게이트(#628): 기존 항목 삭제 변경은 PR(머지 후보)로 넘기지 않는다.
      in_changelog_additive_gate "$branch" || { int_set_phase "$rd" "$key" blocked; return 4; }
      local title pr
      title="$(in_spec_title "$spec")"
      pr="$(in_ensure_pr "$branch" "$title" "$spec")" || { int_set_phase "$rd" "$key" blocked; return 4; }
      [[ -n "$pr" ]] && int_set_pr "$rd" "$key" "$pr"
      int_set_phase "$rd" "$key" review
      int_log "$rd" "$key" "PR=$pr 인계 — review 대기"
      echo "key:    $key"
      echo "phase:  review"
      echo "branch: $branch"
      echo "pr:     $pr"
      return 0
      ;;
    failed)
      in_handle_blocked "$spec" "$rd" "$key"; return $?
      ;;
    running|pending)
      echo "key:      $key"
      echo "terminal: $term (아직 종료 신호 없음 — 통합 보류)"
      return 20
      ;;
    *)
      int_set_phase "$rd" "$key" blocked
      in_die "알 수 없는 terminal state: $term (보수적으로 하드 차단 처리)"
      return 4
      ;;
  esac
}

# in_handle_blocked <spec> <run_dir> <key> — failed(BLOCKED) 종료를 범주별로 매핑한다
#   (push·PR 미수행). in_integrate(풀 파이프라인)와 in_integrate_direct(직접 머지)가 공유해
#   범주 분기 산식 중복을 막는다. 반환 3=spec-gap, 4=하드 차단.
in_handle_blocked() {
  local spec="$1" rd="$2" key="$3" cat
  cat="$(in_blocked_category "$spec")"
  # 실패/터미널 사후 단계: 작업이 원격에 보존돼 있으면 고아 워크트리를 조건부 정리한다(#350).
  #   미보존(유일 사본)이면 보존 — 정리는 판정의 사후 단계라 rc 를 바꾸지 않는다.
  in_cleanup_failed_worktree "$spec" "$rd"
  if [[ "$cat" == "spec-gap" ]]; then
    int_set_phase "$rd" "$key" blocked-spec-gap
    int_log "$rd" "$key" "BLOCKED spec-gap → 스펙 보강 재개 경로 안내(push·PR 안 함)"
    echo "key:      $key"
    echo "phase:    blocked-spec-gap"
    echo "category: spec-gap"
    echo "resume:   스펙(태스크 본문) 강화 후 execute-task start 로 재개하세요(push·PR 미수행)."
    return 3
  fi
  int_set_phase "$rd" "$key" blocked
  int_log "$rd" "$key" "하드 차단($cat) → 사람 에스컬레이션(push·PR 안 함)"
  echo "key:      $key"
  echo "phase:    blocked"
  echo "category: $cat"
  echo "escalate: 사람 판단 필요(push·PR 미수행)."
  return 4
}

# in_integrate_direct <spec> <run_dir> <key> — forge 미구성 직접 머지 서브모드.
#   승인 요청(PR) 없이, 종료신호 판정·작업 브랜치 식별만 기존 헬퍼로 재사용해 **적대적 리뷰
#   게이트(phase=review)** 로 넘긴다. push·PR 을 수행하지 않는다(리뷰는 로컬 작업 브랜치 diff
#   로 수행하고, approve 후 머지는 호출자의 머지 헬퍼가 ff-only + version 게이트로 직접 수행).
#   BLOCKED 분기는 in_integrate 와 동일(공유 헬퍼).
#   반환: 0=리뷰 게이트 진입(phase=review) / 3=spec-gap 차단 / 4=하드 차단 / 20=미종료(대기).
in_integrate_direct() {
  local spec="$1" rd="$2" key="$3"
  [[ -n "$spec" && -n "$rd" && -n "$key" ]] || { in_die "사용: integration.sh integrate-direct <spec> <run_dir> <key>"; return 1; }
  mkdir -p "$rd"
  local rid; rid="$(basename "$rd")"

  local term; term="$(in_child_terminal_state "$spec")"
  int_log "$rd" "$key" "integrate-direct spec=$spec terminal=$term"

  case "$term" in
    done)
      local branch; branch="$(in_work_branch "$rid" "$spec")" || { int_set_phase "$rd" "$key" blocked; return 4; }
      int_set_branch "$rd" "$key" "$branch"
      # 다리: 머지 대상으로 쓰기 전에 작업 브랜치가 없으면 loop 결과 커밋에서 생성(멱등·공통 헬퍼).
      in_ensure_work_branch "$branch" "$spec" || { int_set_phase "$rd" "$key" blocked; return 4; }
      # CHANGELOG 순수-추가 게이트(#628): 기존 항목 삭제 변경은 리뷰(머지 후보)로 넘기지 않는다.
      in_changelog_additive_gate "$branch" || { int_set_phase "$rd" "$key" blocked; return 4; }
      int_set_phase "$rd" "$key" review
      int_log "$rd" "$key" "직접 통합(승인 요청·PR·push 우회) → 적대적 리뷰 게이트: branch=$branch → review"
      echo "key:    $key"
      echo "phase:  review"
      echo "branch: $branch"
      return 0
      ;;
    failed)
      in_handle_blocked "$spec" "$rd" "$key"; return $?
      ;;
    running|pending)
      echo "key:      $key"
      echo "terminal: $term (아직 종료 신호 없음 — 직접 머지 보류)"
      return 20
      ;;
    *)
      int_set_phase "$rd" "$key" blocked
      in_die "알 수 없는 terminal state: $term (보수적으로 하드 차단 처리)"
      return 4
      ;;
  esac
}

# ----- 사용법 -----
in_usage() {
  cat >&2 <<'EOF'
usage: integration.sh <command> [args]

Commands:
  integrate <spec> <run_dir> <key>   종료 신호를 읽어 매핑·통합(풀 파이프라인):
                                        DONE→push→PR(phase=review) /
                                        spec-gap→blocked-spec-gap / 하드 BLOCKED→blocked.
  integrate-direct <spec> <run_dir> <key>
                                     forge 미구성 직접 통합: 승인·PR·push 없이 작업 브랜치만
                                        식별해 적대적 리뷰 게이트로(phase=review) / BLOCKED
                                        분기는 integrate 와 동일.
  terminal  <spec>                   child 종료 상태(done|failed|running|pending|unknown).
  category  <spec>                   BLOCKED 범주(spec-gap|...|other).
  cleanup-on-fail <spec> <run_dir>   실패/터미널 경로 조건부 워크트리 정리(보존되면 정리, 아니면
                                        보존). 호출 레이어가 child 를 종료 정리할 때 호출하는
                                        진입(워커 escalation 과 동일 정책).

환경 변수: LOOP_CMD, GIT_CMD, FORGE_CMD, DEFAULT_BRANCH
EOF
  return 1
}

# =====================================================================
# selftest — mock 인터페이스(loop/git/forge)로 통합 분기·force 미사용 독립 검증.
# =====================================================================
in_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local rd="$TMP/.autopilot/runs/20260604T000000-abc1234"; mkdir -p "$rd"

  # mock loop: status --json / logs / paths 를 spec 별 파일로 흉내.
  #   paths: loop 공개 인터페이스 — 작업 트리(WT) 경로를 알려준다(브랜치 이식 다리 입력).
  local LP="$TMP/loop"; mkdir -p "$LP"
  local LOOPWT="$TMP/loopwt"; mkdir -p "$LOOPWT"   # mock loop 결과 워크트리 경로.
  local CLEANUPLOG="$TMP/cleanuplog"; : > "$CLEANUPLOG"   # loop cleanup 위임 기록(워크트리 정리).
  mock_loop() {
    case "$1" in
      status) shift; [[ "$1" == "--json" ]] && shift; cat "$LP/$(basename "$1").json" 2>/dev/null || true ;;
      logs)   cat "$LP/$(basename "$2").logs" 2>/dev/null || true ;;
      paths)  printf 'SPEC_PATH   %s\nWT          %s\nLOOP_DIR    %s\n' "$2" "$LOOPWT" "$LOOPWT/.loop" ;;
      # cleanup: 워크트리 정리 위임. MOCK_CLEANUP_FAIL=1 이면 실패(WARN 표면화 검증용).
      cleanup) printf '%s\n' "$2" >> "$CLEANUPLOG"; [[ "${MOCK_CLEANUP_FAIL:-}" == "1" ]] && return 1 || return 0 ;;
    esac
  }
  export -f mock_loop 2>/dev/null || true
  LOOP_CMD=mock_loop

  # mock git: force 인자 보면 exit99(selftest 즉사). push/fetch/checkout/rebase 기록.
  #   브랜치 존재를 실제로 모사한다(BRANCHES 파일) — checkout 을 무조건 성공시키지 않는다(AC5).
  #   rev-parse --verify refs/heads/<b> = 브랜치 존재 검사, rev-parse HEAD = 결과 커밋,
  #   branch <name> [<commit>] = 브랜치 생성(force 금지 보장됨).
  local PUSHLOG="$TMP/pushlog" GITLOG="$TMP/gitlog" BRANCHES="$TMP/branches" REMOTE_BRANCHES="$TMP/remotebranches"
  : > "$PUSHLOG"; : > "$GITLOG"; : > "$BRANCHES"; : > "$REMOTE_BRANCHES"
  mock_git() {
    # 선행 -C <dir> 흡수(loop 결과 워크트리에서 결과 커밋을 읽을 때 사용).
    if [[ "$1" == "-C" ]]; then shift 2; fi
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    printf '%s\n' "$*" >> "$GITLOG"
    case "$1" in
      # ls-remote --heads origin <branch> — 원격 작업 브랜치 존재 모사(REMOTE_BRANCHES 파일).
      #   존재하면 "<sha>\trefs/heads/<branch>" 한 줄 출력(비어있지 않음 = 보존됨), 없으면 빈 출력.
      ls-remote)
        local rb="${@: -1}"   # 마지막 인자 = 브랜치명(ls-remote --heads origin <branch>).
        if grep -Fxq "$rb" "$REMOTE_BRANCHES" 2>/dev/null; then printf 'deadbeef\trefs/heads/%s\n' "$rb"; fi ;;
      push) printf '%s\n' "$*" >> "$PUSHLOG" ;;
      # merge-base --is-ancestor: origin/* 조상 질의는 MOCK_ANCESTOR(base sync 용),
      #   그 외(원격 tip→로컬 작업 커밋 ff 호환 질의)는 MOCK_REMOTE_FF(재실행 stale 판정용).
      merge-base)
        case "$*" in
          *origin/*) [[ "${MOCK_ANCESTOR:-0}" == "1" ]] && return 0 || return 1 ;;
          *)         [[ "${MOCK_REMOTE_FF:-0}" == "1" ]] && return 0 || return 1 ;;
        esac ;;
      rev-parse)
        case "$*" in
          *--verify*refs/heads/*)
            local b="${*##*refs/heads/}"; b="${b%% *}"
            grep -Fxq "$b" "$BRANCHES" 2>/dev/null && return 0 || return 1 ;;
          *refs/heads/*)   # 로컬 작업 커밋 조회(브랜치 존재 시 결정적 SHA, 없으면 실패).
            local b="$*"; b="${b##*refs/heads/}"; b="${b%% *}"
            grep -Fxq "$b" "$BRANCHES" 2>/dev/null && { echo "localcommit-$b"; return 0; } || return 1 ;;
          *HEAD*) echo "resultcommitsha7"; return 0 ;;
        esac ;;
      branch) printf '%s\n' "$2" >> "$BRANCHES" ;;   # branch <name> [<commit>]
      checkout)
        # 실제처럼: 존재하지 않는 브랜치 checkout 은 실패한다(무조건 성공 금지).
        grep -Fxq "$2" "$BRANCHES" 2>/dev/null || { echo "error: pathspec '$2' did not match" >&2; return 1; } ;;
      rebase|fetch) : ;;
    esac
    return 0
  }
  GIT_CMD=mock_git

  # mock forge: pr list(재사용 제어 MOCK_PR), pr create 기록.
  #   pr create 의 --body-file 내용을 PRBODY 로 캡처 — forge 전달 시점의 본문(줄바꿈 보존) 검증용.
  local PRLOG="$TMP/prlog" PRBODY="$TMP/prbody" PRCLOSELOG="$TMP/prclose"; : > "$PRLOG"; : > "$PRBODY"; : > "$PRCLOSELOG"
  mock_forge() {
    case "$1 $2" in
      "pr list")   [[ -n "${MOCK_EXISTING_PR:-}" ]] && echo "$MOCK_EXISTING_PR" || true ;;
      "pr view")   # --json author → 작성자 login(MOCK_PR_AUTHOR); --json reviews → login\tbody 줄들(MOCK_PR_REVIEWS).
        case "$*" in
          *"--json author"*)  printf '%s\n' "${MOCK_PR_AUTHOR:-}" ;;
          *"--json reviews"*) printf '%b' "${MOCK_PR_REVIEWS:-}" ;;
        esac ;;
      "pr close")  printf '%s\n' "$3" >> "$PRCLOSELOG" ;;   # 재실행 stale PR close 기록.
      "pr create")
        printf '%s\n' "$*" >> "$PRLOG"
        local _prev='' _a
        for _a in "$@"; do [[ "$_prev" == "--body-file" ]] && cat "$_a" >> "$PRBODY" 2>/dev/null; _prev="$_a"; done
        echo created ;;
    esac
    return 0
  }
  FORGE_CMD=mock_forge
  DEFAULT_BRANCH=main

  local spec="$TMP/SPEC.md"
  printf '# 멋진 기능 X\n\n## 무엇\n...\n' > "$spec"

  local fail=0 rc out
  ok()  { echo "PASS  $1"; }
  bad() { echo "FAIL  $1"; fail=1; }
  chk() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }

  st_done()    { printf '{"state":"terminal","signals":["DONE"]}\n'; }
  st_blocked() { printf '{"state":"terminal","signals":["BLOCKED"]}\n'; }
  st_running() { printf '{"state":"running","signals":[]}\n'; }

  # ---- AC1/AC4/AC5: 대상 작업 브랜치 부재 → loop 결과 커밋에서 생성되어 통합 전진 ----
  #   브랜치가 처음부터 없는 상태(BRANCHES 비어 checkout 이 실패하는 조건)에서, 다리가 loop
  #   결과 커밋으로 브랜치를 만들어 phase=blocked 로 떨어지지 않고 push·PR 까지 전진하는지.
  local kN="x-nnn0000" wbN="feat/20260604T000000-abc1234-x"
  st_done > "$LP/SPEC.md.json"; : > "$LP/SPEC.md.logs"
  : > "$BRANCHES"; : > "$PUSHLOG"; : > "$PRLOG"
  grep -Fxq "$wbN" "$BRANCHES" 2>/dev/null && bad "AC5 사전조건: 브랜치가 미리 존재" || ok "AC5 사전조건: 작업 브랜치 부재"
  MOCK_EXISTING_PR="" in_integrate "$spec" "$rd" "$kN" >/dev/null; rc=$?
  chk "AC4 브랜치 부재서 통합 전진 rc=0(blocked 아님)" "$rc" "0"
  chk "AC4 phase=review(blocked 아님)" "$(int_get_phase "$rd" "$kN")" "review"
  grep -Fxq "$wbN" "$BRANCHES" && ok "AC1 작업 브랜치가 loop 결과 커밋에서 생성됨" || bad "AC1 작업 브랜치가 loop 결과 커밋에서 생성됨"
  grep -q "$wbN" "$PUSHLOG" && ok "AC4 생성된 브랜치 push 전진" || bad "AC4 생성된 브랜치 push 전진"
  # AC(#452): base_sync 가 전용 분리(detached) 워크트리에서 격리 실행한다(공유 체크아웃 미접촉·병렬 안전,
  # 같은 브랜치가 다른 곳에 체크아웃돼 있어도 --detach 라 실패하지 않음). 성공 후 update-ref 로 작업 브랜치 ref 전진.
  grep -qE '^worktree add .*--detach' "$GITLOG" && ok "AC#452 분리(detached) 워크트리 격리(브랜치 체크아웃 충돌 회피)" || bad "AC#452 분리(detached) 워크트리 격리"
  grep -qE 'push origin HEAD:refs/heads/' "$PUSHLOG" && ok "AC#452 rebase 결과를 원격으로 직접 push(로컬 ref 미갱신)" || bad "AC#452 직접 push(HEAD:refs/heads)"
  grep -qE '^update-ref refs/heads/' "$GITLOG" && bad "AC#452 update-ref 로 로컬 브랜치 ref 갱신(공유 체크아웃 오염 위험)" || ok "AC#452 로컬 브랜치 ref 직접 갱신 안 함(공유 체크아웃 미오염)"
  grep -qE '^worktree remove ' "$GITLOG" && ok "AC#452 전용 워크트리 정리" || bad "AC#452 전용 워크트리 정리"

  # ---- AC: DONE → base sync→push→PR, phase=review, branch/pr 기록 ----
  local kA="x-aaa1111"
  st_done > "$LP/SPEC.md.json"; : > "$LP/SPEC.md.logs"
  MOCK_EXISTING_PR="" out="$(in_integrate "$spec" "$rd" "$kA")"; rc=$?
  chk "AC2 DONE 통합 rc=0" "$rc" "0"
  chk "AC2 phase=review" "$(int_get_phase "$rd" "$kA")" "review"
  chk "AC2 branch=feat/<rid>-<slug>" "$(int_get_branch "$rd" "$kA")" "feat/20260604T000000-abc1234-x"
  grep -q 'feat/20260604T000000-abc1234-x' "$PUSHLOG" && ok "AC2 작업 브랜치 push" || bad "AC2 작업 브랜치 push"
  grep -q 'pr create' "$PRLOG" && ok "AC2 PR 생성" || bad "AC2 PR 생성"
  grep -q 'rebase' "$GITLOG" && ok "AC2 base sync rebase" || bad "AC2 base sync rebase"
  # ---- AC: 신규 생성 PR 제목 접두 태그 유지 + 본문 자동생성 식별 줄 부재(#554) ----
  grep -Fq -- '--title 🤖 [자동 리뷰] ' "$PRLOG" \
    && ok "AC 신규 PR 제목 자동 리뷰 접두 태그" || bad "AC 신규 PR 제목 자동 리뷰 접두 태그"
  grep -Fq '자동 적대 리뷰' "$PRBODY" \
    && bad "AC 신규 PR 본문 자동생성 식별 줄 부재" || ok "AC 신규 PR 본문 자동생성 식별 줄 부재"

  # ---- AC: open PR 존재 → 재사용(새 PR 미생성) + 기존 브랜치 rebase 재작성 안 함 ----
  #   (Codex blocking 회귀 가드: base 전진+원격 브랜치 존재 시 rebase 는 non-ff push 를 부른다.)
  local kR="x-rrr2222"; : > "$PRLOG"; : > "$GITLOG"
  MOCK_EXISTING_PR="55" in_integrate "$spec" "$rd" "$kR" >/dev/null; rc=$?
  chk "AC2 재사용 rc=0" "$rc" "0"
  chk "AC2 재사용 pr=55" "$(int_get_pr "$rd" "$kR")" "55"
  [[ ! -s "$PRLOG" ]] && ok "AC2 open PR 재사용(새 PR 미생성)" || bad "AC2 open PR 재사용(새 PR 미생성)"
  if grep -q 'rebase' "$GITLOG"; then bad "기존 PR 재통합 시 rebase 재작성(non-ff 위험)"; else ok "기존 PR 재통합 시 rebase 재작성 안 함(non-ff 회피)"; fi

  # ---- AC(SPEC #462): 재실행 stale 잔여 정리 — autopilot-소유 non-ff 원격 작업 브랜치+PR 은
  #   push 전에 PR close + 원격 브랜치 삭제(force 금지)로 정리해 non-ff push 실패를 막는다.
  #   소유 신호 두 가지(결정적 브랜치명 원격 존재 + App봇 PR + *-formal-review 마커)가
  #   모두 있을 때만 정리하고, ff 호환·외부 소유는 미훼손(force 금지·오삭제 방지). ----
  local wbST="feat/20260604T000000-abc1234-x"
  # (a) non-ff + autopilot-소유 → 정리(원격 삭제 + PR close) 후 통합 전진(rc=0).
  local kST="x-st00aaaa"; : > "$PUSHLOG"; : > "$PRLOG"; : > "$PRCLOSELOG"; : > "$BRANCHES"; : > "$GITLOG"
  st_done > "$LP/SPEC.md.json"; : > "$LP/SPEC.md.logs"
  printf '%s\n' "$wbST" > "$REMOTE_BRANCHES"      # 결정적 브랜치명 원격 존재(신호1).
  MOCK_EXISTING_PR="91" MOCK_PR_AUTHOR="courtesy-bot" \
    MOCK_PR_REVIEWS="courtesy-bot\t<!-- claude-formal-review head_sha=x verdict=approve -->\n" \
    MOCK_REMOTE_FF=0 in_integrate "$spec" "$rd" "$kST" >/dev/null; rc=$?
  chk "AC#462 stale 정리 후 통합 rc=0(non-ff 실패 아님)" "$rc" "0"
  grep -q -- '--delete' "$PUSHLOG" && ok "AC#462 stale 원격 작업 브랜치 삭제(non-ff 해소)" || bad "AC#462 stale 원격 작업 브랜치 삭제"
  grep -Fxq "91" "$PRCLOSELOG" && ok "AC#462 stale PR close" || bad "AC#462 stale PR close"
  if grep -qiE 'force|(^| )-f( |$)' "$GITLOG"; then bad "AC#462 정리 force 미사용"; else ok "AC#462 정리 force 미사용"; fi

  # (b) ff 호환 원격(+PR) → 정리하지 않음(건강한 재사용 보존).
  local kSF="x-st11bbbb"; : > "$PUSHLOG"; : > "$PRCLOSELOG"; : > "$BRANCHES"
  st_done > "$LP/SPEC.md.json"; : > "$LP/SPEC.md.logs"
  printf '%s\n' "$wbST" > "$REMOTE_BRANCHES"
  MOCK_EXISTING_PR="92" MOCK_PR_AUTHOR="courtesy-bot" \
    MOCK_PR_REVIEWS="courtesy-bot\t<!-- claude-formal-review head_sha=x verdict=approve -->\n" \
    MOCK_REMOTE_FF=1 in_integrate "$spec" "$rd" "$kSF" >/dev/null
  grep -q -- '--delete' "$PUSHLOG" && bad "AC#462 ff 호환 원격 삭제(오삭제)" || ok "AC#462 ff 호환 원격 미삭제(재사용 보존)"
  [[ ! -s "$PRCLOSELOG" ]] && ok "AC#462 ff 호환 PR 미close" || bad "AC#462 ff 호환 PR 미close"

  # (c) non-ff 이지만 외부 소유(비-봇 author·마커 없음) → 미훼손(force 금지·오삭제 방지).
  local kSE="x-st22cccc"; : > "$PUSHLOG"; : > "$PRCLOSELOG"; : > "$BRANCHES"
  st_done > "$LP/SPEC.md.json"; : > "$LP/SPEC.md.logs"
  printf '%s\n' "$wbST" > "$REMOTE_BRANCHES"
  MOCK_EXISTING_PR="93" MOCK_PR_AUTHOR="outside-human" MOCK_PR_REVIEWS="" \
    MOCK_REMOTE_FF=0 in_integrate "$spec" "$rd" "$kSE" >/dev/null
  grep -q -- '--delete' "$PUSHLOG" && bad "AC#462 외부 소유 동명 브랜치 삭제(오삭제)" || ok "AC#462 외부 소유 동명 브랜치 미삭제"
  [[ ! -s "$PRCLOSELOG" ]] && ok "AC#462 외부 소유 PR 미close" || bad "AC#462 외부 소유 PR 미close"
  : > "$REMOTE_BRANCHES"

  # ---- AC(#630): 자동 정리 불가한 stale 원격 작업 브랜치(열린 PR 없음 = 소유 확증 불가)는
  #   '최초 통합'으로 오인해 non-ff push 로 실패하는 대신, push 전에 정리 방법을 담은 사유로 차단한다.
  #   force 덮어쓰기·소유 미확증 원격 자동 삭제는 하지 않는다. ----
  local kSR="x-sr33dddd"; : > "$PUSHLOG"; : > "$PRLOG"; : > "$PRCLOSELOG"; : > "$BRANCHES"; : > "$GITLOG"
  st_done > "$LP/SPEC.md.json"; : > "$LP/SPEC.md.logs"
  printf '%s\n' "$wbST" > "$REMOTE_BRANCHES"
  err="$(MOCK_EXISTING_PR="" MOCK_REMOTE_FF=0 in_integrate "$spec" "$rd" "$kSR" 2>&1 >/dev/null)"; rc=$?
  chk "AC#630 정리 불가 stale 원격 → rc=4(차단)" "$rc" "4"
  chk "AC#630 phase=blocked" "$(int_get_phase "$rd" "$kSR")" "blocked"
  case "$err" in
    *"git push origin --delete $wbST"*) ok "AC#630 차단 사유에 정리 방법(명령) 포함";;
    *) bad "AC#630 차단 사유에 정리 방법(명령) 포함 (got: $err)";;
  esac
  [[ ! -s "$PUSHLOG" ]] && ok "AC#630 차단 시 push 미수행(force 금지)" || bad "AC#630 차단 시 push 미수행(force 금지)"
  [[ ! -s "$PRCLOSELOG" ]] && ok "AC#630 소유 미확증 원격 자동 삭제·PR close 안 함" || bad "AC#630 소유 미확증 자동 삭제 안 함"
  : > "$REMOTE_BRANCHES"

  # ---- AC9: spec-gap BLOCKED → push·PR 없이 blocked-spec-gap ----
  local kS="x-sss3333"; : > "$PUSHLOG"; : > "$PRLOG"
  st_blocked > "$LP/SPEC.md.json"; printf 'category: spec-gap\n' > "$LP/SPEC.md.logs"
  out="$(in_integrate "$spec" "$rd" "$kS")"; rc=$?
  chk "AC9 spec-gap rc=3" "$rc" "3"
  chk "AC9 phase=blocked-spec-gap" "$(int_get_phase "$rd" "$kS")" "blocked-spec-gap"
  case "$out" in *resume*) ok "AC9 재개 안내";; *) bad "AC9 재개 안내";; esac
  [[ ! -s "$PUSHLOG" && ! -s "$PRLOG" ]] && ok "AC9 spec-gap push·PR 미수행" || bad "AC9 spec-gap push·PR 미수행"

  # ---- AC9: 하드 BLOCKED → push·PR 없이 blocked ----
  local kH="x-hhh4444"; : > "$PUSHLOG"; : > "$PRLOG"
  st_blocked > "$LP/SPEC.md.json"; printf 'category: environment-gap\n' > "$LP/SPEC.md.logs"
  out="$(in_integrate "$spec" "$rd" "$kH")"; rc=$?
  chk "AC9 하드 BLOCKED rc=4" "$rc" "4"
  chk "AC9 phase=blocked" "$(int_get_phase "$rd" "$kH")" "blocked"
  case "$out" in *escalate*) ok "AC9 에스컬레이션 안내";; *) bad "AC9 에스컬레이션 안내";; esac
  [[ ! -s "$PUSHLOG" && ! -s "$PRLOG" ]] && ok "AC9 하드 push·PR 미수행" || bad "AC9 하드 push·PR 미수행"

  # ---- 미종료(running) → 통합 보류 no-op ----
  local kP="x-ppp5555"
  st_running > "$LP/SPEC.md.json"
  in_integrate "$spec" "$rd" "$kP" >/dev/null; rc=$?
  chk "running rc=20(보류)" "$rc" "20"
  chk "running phase 미설정" "$(int_get_phase "$rd" "$kP")" ""

  # ---- AC3/AC7: integrate-direct DONE → branch 세팅·phase=review(적대적 리뷰 게이트 진입),
  #   push·PR 미수행. (direct 서브모드도 머지 직전 리뷰 한 단계를 거치므로 merging 이 아니라
  #   review 로 떨어진다 — 머지는 리뷰 approve 뒤.)
  #   (GITLOG 은 비우지 않는다 — 아래 'git/push 실제 수행됨' 위생 단언이 누적 GITLOG 를 본다.)
  local kD="x-ddd6666"; : > "$PUSHLOG"; : > "$PRLOG"
  st_done > "$LP/SPEC.md.json"; : > "$LP/SPEC.md.logs"
  in_integrate_direct "$spec" "$rd" "$kD" >/dev/null; rc=$?
  chk "AC3 integrate-direct rc=0" "$rc" "0"
  chk "AC7 direct phase=review(리뷰 게이트)" "$(int_get_phase "$rd" "$kD")" "review"
  chk "AC3 direct branch=feat/<rid>-<slug>" "$(int_get_branch "$rd" "$kD")" "feat/20260604T000000-abc1234-x"
  [[ ! -s "$PUSHLOG" && ! -s "$PRLOG" ]] && ok "AC3 direct push·PR 미수행" || bad "AC3 direct push·PR 미수행"

  # ---- AC3: integrate-direct BLOCKED spec-gap → blocked-spec-gap(push·PR 없음) ----
  local kDS="x-ddd7777"; : > "$PUSHLOG"; : > "$PRLOG"
  st_blocked > "$LP/SPEC.md.json"; printf 'category: spec-gap\n' > "$LP/SPEC.md.logs"
  in_integrate_direct "$spec" "$rd" "$kDS" >/dev/null; rc=$?
  chk "AC3 direct spec-gap rc=3" "$rc" "3"
  chk "AC3 direct phase=blocked-spec-gap" "$(int_get_phase "$rd" "$kDS")" "blocked-spec-gap"
  [[ ! -s "$PUSHLOG" && ! -s "$PRLOG" ]] && ok "AC3 direct spec-gap push·PR 미수행" || bad "AC3 direct spec-gap push·PR 미수행"

  # ---- U2: 실패-경로 조건부 워크트리 정리 — 원격 브랜치 존재(보존됨) → loop cleanup 위임 ----
  #   in_handle_blocked(워커 자기 escalation) 가 작업이 원격에 보존돼 있으면 고아 워크트리를 정리한다(#350).
  local wbF="feat/20260604T000000-abc1234-x"
  local kF="x-fff8888"; : > "$CLEANUPLOG"; : > "$PUSHLOG"; : > "$PRLOG"
  st_blocked > "$LP/SPEC.md.json"; printf 'category: environment-gap\n' > "$LP/SPEC.md.logs"
  printf '%s\n' "$wbF" > "$REMOTE_BRANCHES"   # 원격에 작업 브랜치 존재 = 보존됨.
  in_integrate "$spec" "$rd" "$kF" >/dev/null; rc=$?
  chk "U2 실패+원격보존 rc=4(하드 차단 유지)" "$rc" "4"
  grep -Fxq "$spec" "$CLEANUPLOG" && ok "U2 원격보존 → 워크트리 cleanup 위임" || bad "U2 원격보존 → 워크트리 cleanup 위임"
  [[ ! -s "$PUSHLOG" && ! -s "$PRLOG" ]] && ok "U2 실패경로 push·PR 미수행(보존)" || bad "U2 실패경로 push·PR 미수행(보존)"

  # ---- U2: 원격 브랜치 없음(유일 사본) → 워크트리 보존(cleanup 미위임) ----
  local kP2="x-ppp9999"; : > "$CLEANUPLOG"
  st_blocked > "$LP/SPEC.md.json"; printf 'category: environment-gap\n' > "$LP/SPEC.md.logs"
  : > "$REMOTE_BRANCHES"   # 원격에 브랜치 없음 = 미보존(유일 사본).
  in_integrate "$spec" "$rd" "$kP2" >/dev/null; rc=$?
  chk "U2 실패+원격없음 rc=4" "$rc" "4"
  [[ ! -s "$CLEANUPLOG" ]] && ok "U2 미보존 → 워크트리 보존(cleanup 미위임)" || bad "U2 미보존 → 워크트리 보존(cleanup 미위임)"

  # ---- U2: spec-gap(재개 경로)도 원격 미보존이면 워크트리 보존 ----
  local kSG="x-sgg0000"; : > "$CLEANUPLOG"
  st_blocked > "$LP/SPEC.md.json"; printf 'category: spec-gap\n' > "$LP/SPEC.md.logs"
  : > "$REMOTE_BRANCHES"
  in_integrate "$spec" "$rd" "$kSG" >/dev/null; rc=$?
  chk "U2 spec-gap rc=3" "$rc" "3"
  [[ ! -s "$CLEANUPLOG" ]] && ok "U2 spec-gap 미보존 → 워크트리 보존" || bad "U2 spec-gap 미보존 → 워크트리 보존"

  # ---- U2: cleanup 위임 실패 → WARN 표면화, 머지·완료 판정(rc) 뒤집지 않음(정리는 사후 단계) ----
  local kCF="x-cff1111"; : > "$CLEANUPLOG"
  st_blocked > "$LP/SPEC.md.json"; printf 'category: environment-gap\n' > "$LP/SPEC.md.logs"
  printf '%s\n' "$wbF" > "$REMOTE_BRANCHES"
  err="$(MOCK_CLEANUP_FAIL=1 in_integrate "$spec" "$rd" "$kCF" 2>&1 >/dev/null)"; rc=$?
  chk "U2 cleanup 실패해도 rc=4(판정 유지)" "$rc" "4"
  case "$err" in *WARN*) ok "U2 cleanup 실패 경고 표면화(조용한 실패 금지)";; *) bad "U2 cleanup 실패 경고 표면화(조용한 실패 금지)";; esac

  # ---- U2: cleanup-on-fail CLI 헬퍼(호출 레이어 child 종료 정리 공유 진입) ----
  #   호출 레이어가 child 를 종료 정리할 때 호출하는 동일 정책 진입점.
  local kCLI="x-cli2222"; : > "$CLEANUPLOG"
  printf '%s\n' "$wbF" > "$REMOTE_BRANCHES"
  in_cleanup_worktree_if_preserved "$spec" "$wbF"
  grep -Fxq "$spec" "$CLEANUPLOG" && ok "U2 헬퍼: 원격보존 → cleanup" || bad "U2 헬퍼: 원격보존 → cleanup"
  : > "$CLEANUPLOG"; : > "$REMOTE_BRANCHES"
  in_cleanup_worktree_if_preserved "$spec" "$wbF"
  [[ ! -s "$CLEANUPLOG" ]] && ok "U2 헬퍼: 미보존 → 보존" || bad "U2 헬퍼: 미보존 → 보존"

  # ---- PR 본문 구조화(in_pr_body): 자동생성 안내·run 추적 줄 부재(#554), 요약 섹션 본문(주석 제거),
  #   이슈 식별 정보 조건부 cross-reference, 정적 한 줄 부재. ----
  local specB="$TMP/SPECB.md" body
  cat > "$specB" <<'SPECEOF'
---
slug: pr-body-test
---

# 본문 기능 Y

## 무엇을 만들 것인가
<!-- 설명용 주석: 이 줄은 본문에 들어가면 안 된다. -->
요약 첫 줄이다.
요약 둘째 줄이다.

## 목적 (왜)
이유.
SPECEOF
  body="$(in_pr_body "$specB")"
  case "$body" in *"$specB"*) bad "본문 SPEC 경로 부재(#554)";; *) ok "본문 SPEC 경로 부재(#554)";; esac
  case "$body" in '## 요약'*) ok "본문 선두 요약(선행 공백 줄 없음)";; *) bad "본문 선두 요약(선행 공백 줄 없음)";; esac
  case "$body" in *"요약 첫 줄이다."*"요약 둘째 줄이다."*) ok "본문 요약 섹션 전체 포함";; *) bad "본문 요약 섹션 전체 포함";; esac
  case "$body" in *"설명용 주석"*) bad "본문 요약 주석 제거";; *) ok "본문 요약 주석 제거";; esac
  case "$body" in *"목적 (왜)"*) bad "본문 다음 섹션 미포함(요약 경계)";; *) ok "본문 다음 섹션 미포함(요약 경계)";; esac
  case "$body" in *'Refs #'*) bad "이슈 없음 → cross-reference 미생성";; *) ok "이슈 없음 → cross-reference 미생성";; esac

  # ---- 요약 섹션 부재 → 요약 블록 생략 (식별 줄·run 줄도 없으므로 본문 전체 빈 출력, #554) ----
  body="$(in_pr_body "$spec")"   # $spec 에는 '무엇을 만들 것인가' 섹션·이슈가 없다.
  case "$body" in *'## 요약'*) bad "요약 부재 시 요약 블록 생략";; *) ok "요약 부재 시 요약 블록 생략";; esac
  [[ -z "$body" ]] && ok "요약·이슈 부재 → 본문 빈 출력(#554)" || bad "요약·이슈 부재 → 본문 빈 출력(#554)"

  # ---- 이슈 식별 정보(frontmatter issue:) 존재 → cross-reference 한 줄 ----
  local specI="$TMP/SPECI.md"
  printf -- '---\nissue: 42\n---\n\n# 이슈 기능 Z\n' > "$specI"
  body="$(in_pr_body "$specI")"
  case "$body" in *'Refs #42'*) ok "이슈 존재 → Refs #42 한 줄";; *) bad "이슈 존재 → Refs #42 한 줄";; esac
  case "$body" in 'Refs #42'*) ok "본문 선두 Refs(선행 공백 줄 없음)";; *) bad "본문 선두 Refs(선행 공백 줄 없음)";; esac
  printf -- '---\nissue: "#43"\n---\n\n# 이슈 기능 W\n' > "$specI"
  body="$(in_pr_body "$specI")"
  case "$body" in *'Refs #43'*) ok "이슈 '#43' 표기 정규화";; *) bad "이슈 '#43' 표기 정규화";; esac

  # ---- execute-task materialize 경로: 임시 materialize SPEC(.autopilot/runs/<id>/SPEC.md) 본문 ----
  #   (a) .autopilot/runs/·절대 경로 누출 부재,
  #   (b) 자동생성 식별 줄·run 추적 줄 부재(#554), (c) 태스크 참조(Refs #n)·요약 보존. ----
  local specET="$TMP/.autopilot/runs/777/SPEC.md"
  mkdir -p "$TMP/.autopilot/runs/777"
  printf -- '---\nslug: et-body\nissue: 777\n---\n\n# ET 기능\n\n## 무엇을 만들 것인가\nET 요약 줄.\n' > "$specET"
  body="$(in_pr_body "$specET")"
  case "$body" in *'.autopilot/runs/'*) bad "ET: .autopilot/runs 임시 경로 누출 부재";; *) ok "ET: .autopilot/runs 임시 경로 누출 부재";; esac
  case "$body" in *"$specET"*) bad "ET: 절대 SPEC 경로 부재";; *) ok "ET: 절대 SPEC 경로 부재";; esac
  case "$body" in *'자동 생성'*) bad "ET: 자동생성 식별 줄 부재(#554)";; *) ok "ET: 자동생성 식별 줄 부재(#554)";; esac
  case "$body" in *'자동 적대 리뷰'*) bad "ET: 리뷰 식별 줄 부재(#554)";; *) ok "ET: 리뷰 식별 줄 부재(#554)";; esac
  case "$body" in *'Refs #777'*) ok "ET: 태스크 이슈 참조(Refs #777) 보존";; *) bad "ET: 태스크 이슈 참조(Refs #777) 보존";; esac
  case "$body" in *'task-run:'*) bad "ET: task-run 줄 부재(#554)";; *) ok "ET: task-run 줄 부재(#554)";; esac
  case "$body" in *'ET 요약 줄.'*) ok "ET: 요약 섹션 보존";; *) bad "ET: 요약 섹션 보존";; esac

  # ---- AC(#539): execute-task DONE 작업 내용 — loop 공개 logs(signals/DONE 섹션)에서 워커
  #   완료 요약을 읽어 '## 작업 내용' 섹션으로 포함한다(내부 signals 파일 직접 열람 아님,
  #   $LOOP_CMD logs 경유). specET 의 basename 이 "SPEC.md" 라 mock_loop 의 logs 는
  #   $LP/SPEC.md.logs 를 읽는다(mock 의 basename-키 컨벤션). ----
  printf '\n===== signals/DONE =====\n무엇을: X 함수 수정\n왜: 버그 수정\n' > "$LP/SPEC.md.logs"
  body="$(in_pr_body "$specET")"
  case "$body" in *'## 작업 내용'*) ok "ET: DONE 요약 있음 → 작업 내용 섹션 포함";; *) bad "ET: DONE 요약 있음 → 작업 내용 섹션 포함";; esac
  case "$body" in *'무엇을: X 함수 수정'*'왜: 버그 수정'*) ok "ET: 작업 내용 섹션에 DONE 요약 본문 보존";; *) bad "ET: 작업 내용 섹션에 DONE 요약 본문 보존";; esac

  # ---- 작업 내용이 첫 요소(이슈·요약 부재)인 경우도 선행 공백 줄 없이 시작(#554) ----
  #   (basename 이 SPEC.md 라 위에서 채운 $LP/SPEC.md.logs 의 DONE 요약을 공유 — 의도적 재사용)
  local specET2="$TMP/.autopilot/runs/778/SPEC.md"
  mkdir -p "$TMP/.autopilot/runs/778"
  printf -- '# ET 기능 2\n' > "$specET2"
  body="$(in_pr_body "$specET2")"
  case "$body" in '## 작업 내용'*) ok "본문 선두 작업 내용(선행 공백 줄 없음)";; *) bad "본문 선두 작업 내용(선행 공백 줄 없음)";; esac

  # ---- AC(#539): DONE 신호는 있으나 본문이 비어있음 → 작업 내용 섹션 생략 ----
  printf '\n===== signals/DONE =====\n' > "$LP/SPEC.md.logs"
  body="$(in_pr_body "$specET")"
  case "$body" in *'## 작업 내용'*) bad "ET: DONE 요약 비어있음 → 작업 내용 섹션 생략";; *) ok "ET: DONE 요약 비어있음 → 작업 내용 섹션 생략";; esac

  # ---- AC(#539): DONE 신호 자체가 없음 → 작업 내용 섹션 생략 ----
  : > "$LP/SPEC.md.logs"
  body="$(in_pr_body "$specET")"
  case "$body" in *'## 작업 내용'*) bad "ET: DONE 신호 부재 → 작업 내용 섹션 생략";; *) ok "ET: DONE 신호 부재 → 작업 내용 섹션 생략";; esac

  # ---- 단일 경로(#556): 발신 주체 구분 없음 — materialize 마커(.autopilot/runs) 없는 spec 경로도
  #   DONE 요약이 있으면 '## 작업 내용' 섹션을 포함한다(#539 동작을 단일 경로로 유지).
  #   ($spec 의 basename 도 "SPEC.md" 라 같은 mock 로그 파일을 공유 — 의도적 재사용). ----
  printf '\n===== signals/DONE =====\n무엇을: Y\n' > "$LP/SPEC.md.logs"
  body="$(in_pr_body "$spec")"
  case "$body" in *'## 작업 내용'*) ok "#556 단일 경로: 비-materialize spec 도 DONE 요약 → 작업 내용 포함";; *) bad "#556 단일 경로: 비-materialize spec 도 DONE 요약 → 작업 내용 포함";; esac
  : > "$LP/SPEC.md.logs"

  # ---- PR 생성이 --body-file 로 멀티라인 본문을 forge 에 전달(줄바꿈 보존) ----
  local kB="x-bbb0000"; : > "$PRLOG"; : > "$PRBODY"; : > "$PUSHLOG"
  st_done > "$LP/SPECB.md.json"; : > "$LP/SPECB.md.logs"
  MOCK_EXISTING_PR="" in_integrate "$specB" "$rd" "$kB" >/dev/null; rc=$?
  chk "본문 통합 rc=0" "$rc" "0"
  grep -q -- '--body-file' "$PRLOG" && ok "PR 생성에 --body-file 사용" || bad "PR 생성에 --body-file 사용"
  [[ "$(wc -l < "$PRBODY")" -gt 1 ]] && ok "forge 전달 본문 멀티라인(줄바꿈 보존)" || bad "forge 전달 본문 멀티라인(줄바꿈 보존)"
  grep -Fq "$specB" "$PRBODY" && bad "forge 전달 본문 SPEC 경로 부재(#554)" || ok "forge 전달 본문 SPEC 경로 부재(#554)"
  grep -q '20260604T000000-abc1234' "$PRBODY" && bad "forge 전달 본문 run-id 부재(#554)" || ok "forge 전달 본문 run-id 부재(#554)"
  # 요약 두 줄이 각각 독립 줄로 존재 = 요약 내부 줄바꿈이 원형 그대로 보존됨(개수 단언 보강).
  grep -Fxq '요약 첫 줄이다.' "$PRBODY" && grep -Fxq '요약 둘째 줄이다.' "$PRBODY" \
    && ok "forge 전달 본문에 요약(각 줄 원형 보존)" || bad "forge 전달 본문에 요약(각 줄 원형 보존)"

  # ---- AC2: loop 공개 paths 의 WT 값에 공백이 있어도 경로를 통째로 읽는다(첫 토큰 절단 금지) ----
  mock_loop_spaced() { [[ "$1" == "paths" ]] && printf 'WT          /tmp/my work/.worktree\n'; }
  ( LOOP_CMD=mock_loop_spaced
    [[ "$(in_loop_worktree "$spec")" == "/tmp/my work/.worktree" ]] ) \
    && ok "AC2 WT 공백 경로 보존" || bad "AC2 WT 공백 경로 보존"

  # ---- AC: force 미사용 (mock_git 은 force 보면 exit99; 여기 도달했으면 미사용) ----
  [[ -s "$PUSHLOG" || -s "$GITLOG" ]] && ok "git/push 실제 수행됨" || bad "git/push 실제 수행됨"
  if grep -qiE 'force|(^| )-f( |$)' "$GITLOG"; then bad "force 미사용"; else ok "force 미사용(git 인자에 force 없음)"; fi

  # ---- AC: in_autoresolve_rebase 일반(비결정) 충돌 → 전략 해소 + needs-verify 표시(워커 재검증 유도) ----
  #   #482: plugin.json 버전 충돌도 결정적 해소가 아니라 일반 전략으로 처리된다(버전 범프 정책 비간섭).
  local U2LOG="$TMP/arlog"; : > "$U2LOG"; rm -f "$TMP/ar_done"
  mock_git_ar() {
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    printf '%s\n' "$*" >> "$U2LOG"
    if [[ "$1" == "diff" && "$*" == *--diff-filter=U* ]]; then
      # add 전엔 미해결(코드 파일 + plugin.json 동시 충돌), add 후엔 해결됨.
      [[ -f "$TMP/ar_done" ]] || printf '%s\n%s\n' "src/foo.sh" "plugins/autopilot/.claude-plugin/plugin.json"
      return 0
    fi
    [[ "$1" == "add" ]] && : > "$TMP/ar_done"
    return 0
  }
  INT_AUTORESOLVE_FLAG=""
  GIT_CMD=mock_git_ar FORGE_CONFLICT_STRATEGY=incoming in_autoresolve_rebase "feat/x" >/dev/null 2>&1; rc=$?
  GIT_CMD=mock_git
  chk "AC autoresolve 일반 충돌 rc=0" "$rc" "0"
  chk "AC autoresolve 비결정→needs-verify" "$INT_AUTORESOLVE_FLAG" "needs-verify"
  grep -q 'checkout --theirs' "$U2LOG" && ok "AC autoresolve incoming 전략=--theirs(작업 커밋 쪽)" || bad "AC autoresolve incoming 전략=--theirs"
  grep -q 'checkout --theirs -- plugins/autopilot/.claude-plugin/plugin.json' "$U2LOG" \
    && ok "AC#482 plugin.json 버전 충돌도 일반 전략(--theirs)으로 처리(결정적 해소 제거)" \
    || bad "AC#482 plugin.json 버전 충돌 일반 전략 처리(--theirs)"
  grep -q 'rebase --continue' "$U2LOG" && ok "AC autoresolve rebase --continue 로 진행" || bad "AC autoresolve rebase --continue"
  if grep -qiE 'force' "$U2LOG"; then bad "AC autoresolve force 미사용"; else ok "AC autoresolve force 미사용"; fi
  INT_AUTORESOLVE_FLAG=""

  # ---- env 개명(#556): FORGE_CONFLICT_STRATEGY=base → --ours(새 베이스 쪽) 전략 적용 ----
  : > "$U2LOG"; rm -f "$TMP/ar_done"
  INT_AUTORESOLVE_FLAG=""
  GIT_CMD=mock_git_ar FORGE_CONFLICT_STRATEGY=base in_autoresolve_rebase "feat/x" >/dev/null 2>&1; rc=$?
  GIT_CMD=mock_git
  chk "#556 autoresolve base 전략 rc=0" "$rc" "0"
  grep -q 'checkout --ours' "$U2LOG" \
    && ok "#556 FORGE_CONFLICT_STRATEGY=base → --ours(새 베이스 쪽)" \
    || bad "#556 FORGE_CONFLICT_STRATEGY=base → --ours(새 베이스 쪽)"
  INT_AUTORESOLVE_FLAG=""

  # ---- 회귀 가드(#482): 버전-전용 충돌 해소·동일-버전 자동 재범프 경로가 제거됐다(정책-불간섭) ----
  #   버전 범프는 컨슈밍 프로젝트 소유 정책(versioning.md) — 통합 엔진은 버전 함수로 집행하지 않는다.
  local _fn
  for _fn in in_reapply_bump in_conflict_version_only in_resolve_version_conflict \
             in_semver_gt in_ensure_version_ahead _in_ensure_version_ahead_core in_json_version; do
    if declare -f "$_fn" >/dev/null 2>&1; then bad "회귀: $_fn 함수 잔존(버전 경로 미제거)"; else ok "회귀: $_fn 함수 제거됨"; fi
  done

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ----- CLI 진입 (sourcing 시 미실행) -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SUB="${1:-}"; shift || true
  case "$SUB" in
    integrate)        in_integrate "$@" ;;
    integrate-direct) in_integrate_direct "$@" ;;
    terminal)  [[ $# -ge 1 ]] || in_usage; in_child_terminal_state "$1" ;;
    category)  [[ $# -ge 1 ]] || in_usage; in_blocked_category "$1" ;;
    cleanup-on-fail) [[ $# -ge 2 ]] || in_usage; in_cleanup_failed_worktree "$1" "$2" ;;
    selftest)  in_selftest ;;
    -h|--help|help) in_usage ;;
    *) echo "알 수 없는 command: $SUB" >&2; in_usage ;;
  esac
fi
