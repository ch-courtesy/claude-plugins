#!/usr/bin/env bash
# merge.sh — autopilot:fsd 머지 + Done + cleanup (C4)
#
# 책임 (파이프라인 종착: "승인되면 머지되고 task 는 완료 상태가 된다"):
#   - 승인 확인: 승인 요청(PR)에 **승인 권한 신원**(별도 approver 봇/PAT)의
#     "승인됨"(APPROVED) 정식 리뷰가 있는지 확인한다. 자동 리뷰 봇의 self-approve 는
#     무효다(분리된 승인 권한 신원의 승인만 인정). 이 "승인됨"이 완료 전이의
#     명시적 신호다.
#   - 버전 범프 게이트(필수): 머지될 변경이 버전 워치 디렉토리(`plugins/**`)를
#     건드리면, 같은 승인 요청 안에서 패키지 매니페스트(`plugin.json`) 버전이
#     올랐는지 단언한다. 오르지 않았으면 머지를 차단하고 차단 기록을 남긴다.
#   - 머지: 기본 브랜치에 fast-forward 전용(--ff-only)으로 머지한다. 머지 커밋을
#     만들지 않으며 force 는 어떤 경로에서도 쓰지 않는다.
#   - 완료·정리: 머지가 확인되면 task 를 완료(Done) 상태로 전이하고(C1 공개 함수
#     계약 tb_set_status), 자율 실행기의 작업 공간 정리를 그 공개 정리
#     인터페이스(`loop.sh cleanup`)로 위임하며, 완료 기록을 남긴다.
#
# 불변식:
#   - force(강제) 머지·push 금지 (어떤 경로에서도).
#   - 작업 공간은 직접 지우지 않고 자율 실행기의 공개 cleanup 인터페이스로만 위임.
#   - 머지·버전 게이트는 단일 출처 규칙의 실행자다:
#       rules/engineering/versioning.md       (워치 디렉토리·머지 시 범프 강제)
#       rules/engineering/branch-and-slug.md   (ff-only 머지·원격 동기화·force 금지)
#
# **하지 않는 일** (다른 단위 책임):
#   - SKILL.md 수정(C0), task 상태 전이 정의(C1, 호출만), 승인 요청 조회·브랜치
#     헬퍼 정의(C2, 차용), 리뷰 루프(C3), poll 드레인(C5),
#     plugin.json 실제 버전 범프 수행(머지 오케스트레이션/사람 책임 — 본 단위는
#     범프 여부를 게이트로 검사만 한다), loop·dispatch 코드 변경(공개 인터페이스만 소비).
#
# 이 모듈은 sourcing(함수 라이브러리) 또는 직접 호출(디스패처) 양쪽으로 쓴다.
# 모든 외부 인터페이스(loop·git·forge·task backend CLI)는 주입 가능한 명령 변수로
# 두어 mock 인터페이스로 독립 검증한다(self-referential: runtime artifact 미검사).
#
# 환경 변수 (테스트에서 mock 으로 치환 가능):
#   GIT_CMD               git 호출 (기본: git).
#   FORGE_CMD             forge(PR) CLI 호출 (기본: gh).
#   LOOP_CMD              자율 실행기 driver 호출 (기본: 형제 loop.sh).
#   TASK_BACKEND_CMD      task backend 호출 (task-backend.sh 가 소비; mock 가능).
#   DEFAULT_BRANCH        base branch (기본: main).
#   APPROVER              승인 권한 신원 login (설정 시 그 신원의 승인만 인정).
#   REVIEW_BOT            자동 리뷰 봇 login (이 신원의 self-approve 는 무효).
#   WATCH_DIRS            버전 워치 디렉토리 prefix (기본: plugins/).
#   FSD_STATE_ROOT  상태 루트 (기본 <project_root>/.fsd).
#
# bash 3.2+ 호환 (associative array 미사용).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 상태 저장소 헬퍼(C0): set_field/get_field/get_branch/get_pr/log_event 등.
# shellcheck source=lib-state.sh
. "$SCRIPT_DIR/lib-state.sh"

# task 상태 전이(C1): tb_set_status / TB_STATUS_DONE 공개 계약.
# task-backend.sh 는 top-level 에서 `set -uo pipefail` 을 재설정하므로
# 소싱 직후 본 모듈의 `set -euo pipefail` 을 복원한다.
# shellcheck source=task-backend.sh
. "$SCRIPT_DIR/task-backend.sh"
set -euo pipefail

# 외부 인터페이스 — 전부 주입 가능(mock 검증). force 옵션은 어디서도 쓰지 않는다.
GIT_CMD="${GIT_CMD:-git}"
FORGE_CMD="${FORGE_CMD:-gh}"
LOOP_CMD_DEFAULT="bash $SCRIPT_DIR/../../loop/references/loop.sh"
LOOP_CMD="${LOOP_CMD:-$LOOP_CMD_DEFAULT}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
APPROVER="${APPROVER:-}"
REVIEW_BOT="${REVIEW_BOT:-}"
WATCH_DIRS="${WATCH_DIRS:-plugins/}"

die() { echo "ERROR: $*" >&2; exit 1; }

require_git_root() {
  PROJECT_ROOT="$($GIT_CMD rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  export PROJECT_ROOT
}

# =====================================================================
# 1) 승인 확인 — 승인 권한 신원의 "승인됨" 정식 리뷰가 있는가.
#    자동 리뷰 봇(REVIEW_BOT)의 self-approve 는 무효.
# =====================================================================

# pr_reviews <pr> — "STATE\tAUTHOR" 줄들. forge 의 공개 리뷰 조회만 사용.
pr_reviews() {
  # shellcheck disable=SC2086
  $FORGE_CMD pr view "$1" --json reviews \
    --jq '.reviews[] | "\(.state)\t\(.author.login)"' 2>/dev/null
}

# approval_ok <pr> — 승인 권한 신원의 APPROVED 리뷰가 있으면 0, 아니면 1.
#   - state 가 APPROVED 인 리뷰만 본다.
#   - author 가 REVIEW_BOT(자동 리뷰 봇)이면 self-approve 로 간주, 무효.
#   - APPROVER 가 설정되면 그 신원의 승인만 인정한다.
approval_ok() {
  local pr="$1" state author
  [[ -n "$pr" ]] || return 1
  while IFS=$'\t' read -r state author; do
    [[ "$state" == "APPROVED" ]] || continue
    [[ -n "$REVIEW_BOT" && "$author" == "$REVIEW_BOT" ]] && continue
    [[ -n "$APPROVER" && "$author" != "$APPROVER" ]] && continue
    return 0
  done < <(pr_reviews "$pr")
  return 1
}

# =====================================================================
# 2) 버전 범프 게이트 — versioning.md 실행자.
#    plugins/** 를 건드리면 같은 승인 요청 안에서 plugin.json 버전이 올라야 한다.
# =====================================================================

# merge_changed_files <branch> — 머지될 변경의 파일 경로(base..branch).
merge_changed_files() {
  # shellcheck disable=SC2086
  $GIT_CMD diff --name-only "origin/$DEFAULT_BRANCH...$1" 2>/dev/null
}

# touches_watch_dir <branch> — 워치 디렉토리 변경이 있으면 0.
touches_watch_dir() {
  merge_changed_files "$1" | grep -qE "^$WATCH_DIRS" 2>/dev/null
}

# changed_manifests <branch> — 변경된 plugin.json 경로들.
changed_manifests() {
  merge_changed_files "$1" | grep -E '(^|/)plugin\.json$' || true
}

# manifest_version_bumped <branch> — 변경된 plugin.json 중 하나라도 diff 에
#   version 필드 변경(추가된 "version" 줄)이 있으면 0(=범프됨), 아니면 1.
manifest_version_bumped() {
  local branch="$1" m
  while IFS= read -r m; do
    [[ -n "$m" ]] || continue
    # shellcheck disable=SC2086
    if $GIT_CMD diff "origin/$DEFAULT_BRANCH...$branch" -- "$m" 2>/dev/null \
        | grep -qE '^\+[[:space:]]*"version"'; then
      return 0
    fi
  done < <(changed_manifests "$branch")
  return 1
}

# version_gate <branch> — 워치 디렉토리를 건드리는데 범프가 없으면 1(차단).
#   워치 디렉토리 변경이 없으면 통과(0).
version_gate() {
  local branch="$1"
  if touches_watch_dir "$branch"; then
    manifest_version_bumped "$branch" && return 0
    return 1
  fi
  return 0
}

# =====================================================================
# 3) 머지 — fast-forward 전용. 머지 커밋·force 없음.
# =====================================================================

# merge_ff_only <branch> — base 를 동기화하고 ff-only 로 머지 후 base push.
#   force 옵션을 어디서도 쓰지 않는다.
merge_ff_only() {
  local branch="$1"
  # shellcheck disable=SC2086
  $GIT_CMD fetch origin "$DEFAULT_BRANCH" || die "fetch 실패: origin/$DEFAULT_BRANCH"
  # shellcheck disable=SC2086
  $GIT_CMD checkout "$DEFAULT_BRANCH" || die "checkout 실패: $DEFAULT_BRANCH"
  # shellcheck disable=SC2086
  $GIT_CMD merge --ff-only "$branch" \
    || die "fast-forward 머지 실패(머지 커밋·force 금지): $branch → $DEFAULT_BRANCH"
  # shellcheck disable=SC2086
  $GIT_CMD push origin "$DEFAULT_BRANCH" || die "base push 실패(force 금지): $DEFAULT_BRANCH"
}

# =====================================================================
# 4) 완료·정리 — Done 전이(C1) + cleanup 위임(loop 공개 인터페이스).
# =====================================================================

# transition_done <task-id> — C1 공개 함수 계약으로 Done 전이.
transition_done() {
  tb_set_status "$1" "$TB_STATUS_DONE"
  log_event "$1" "state → $TB_STATUS_DONE (merge 확인)"
}

# cleanup_workspace <spec> — 자율 실행기의 공개 정리 인터페이스로 위임.
cleanup_workspace() {
  # shellcheck disable=SC2086
  $LOOP_CMD cleanup "$1" || echo "WARN: cleanup 위임 실패(수동 정리 필요): $1" >&2
}

# =====================================================================
# 5) 메인 진입 — 승인·버전 게이트 통과 시 머지하고 Done·cleanup.
# =====================================================================

# merge_finish <spec> <task-id> [pr]
#   1) 승인 게이트: 승인 권한 신원의 APPROVED 없으면 머지 안 함.
#   2) 버전 게이트: plugins/** 변경 + 범프 없음이면 차단.
#   3) ff-only 머지(+ base push).
#   4) Done 전이 + cleanup 위임 + 완료 기록.
merge_finish() {
  local spec="$1" id="$2" pr="${3:-}"
  [[ -n "$spec" && -n "$id" ]] || die "사용: merge.sh finish <spec> <task-id> [pr]"
  ensure_task_dir "$id"

  local branch; branch="$(get_branch "$id")"
  [[ -n "$branch" ]] || die "작업 브랜치 미설정 task: $id (C2 forge 통합 선행 필요)"
  [[ -n "$pr" ]] || pr="$(get_pr "$id")"

  log_event "$id" "merge_finish spec=$spec branch=$branch pr=$pr"

  # 1) 승인 게이트.
  if ! approval_ok "$pr"; then
    log_event "$id" "승인 게이트 차단: 승인 권한 신원의 APPROVED 리뷰 없음 (pr=$pr). 머지 안 함."
    echo "task-id:  $id"
    echo "blocked:  approval — 승인 권한 신원의 '승인됨' 리뷰가 없습니다 (pr=$pr)."
    return 1
  fi

  # 2) 버전 범프 게이트.
  if ! version_gate "$branch"; then
    log_event "$id" "버전 게이트 차단: plugins/** 변경에 plugin.json 버전 범프 없음. 머지 안 함."
    echo "task-id:  $id"
    echo "blocked:  version-bump — plugins/** 를 건드리지만 plugin.json 버전이 오르지 않았습니다."
    return 1
  fi

  # 3) ff-only 머지.
  log_event "$id" "게이트 통과 → ff-only 머지: $branch → $DEFAULT_BRANCH"
  merge_ff_only "$branch"

  # 4) 완료·정리.
  transition_done "$id"
  cleanup_workspace "$spec"
  log_event "$id" "완료: 머지 확인, Done 전이, 작업 공간 정리 위임."

  echo "task-id:  $id"
  echo "state:    $TB_STATUS_DONE"
  echo "branch:   $branch → $DEFAULT_BRANCH (ff-only)"
  echo "pr:       $pr"
  echo "cleanup:  loop cleanup 위임 완료."
}

# ----- 사용법 -----
usage() {
  cat >&2 <<'EOF'
usage: merge.sh <command> [args]

Commands:
  finish <spec> <task-id> [pr]   승인·버전 게이트 통과 시 ff-only 머지 후
                                   Done 전이 + 작업 공간 정리 위임.
  approval <pr>                  승인 권한 신원의 APPROVED 리뷰 유무(0/1).
  version-gate <branch>          버전 범프 게이트 판정(0=통과, 1=차단).

환경 변수: GIT_CMD, FORGE_CMD, LOOP_CMD, TASK_BACKEND_CMD, DEFAULT_BRANCH,
          APPROVER, REVIEW_BOT, WATCH_DIRS, FSD_STATE_ROOT
EOF
  exit 1
}

# =====================================================================
# selftest — mock 인터페이스로 AC2~7 동작을 독립 검증(self-referential).
#   runtime artifact(실제 머지·PR)는 검사하지 않는다.
# =====================================================================
selftest() {
  local tmp ng nf nl pass=0 fail=0
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  export FSD_STATE_ROOT="$tmp/.fsd"

  ng="$tmp/git.sh"; nf="$tmp/forge.sh"; nl="$tmp/loop.sh"
  local trace="$tmp/trace"

  # mock git: force 가 보이면 즉시 exit 99. diff/merge 동작은 env 로 제어.
  cat >"$ng" <<'GIT'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in *force*|-f) exit 99;; esac; done
echo "git $*" >> "$TRACE"
case "$1" in
  rev-parse) echo "/repo" ;;
  fetch|checkout|push) exit 0 ;;
  merge) exit 0 ;;
  diff)
    if [[ "$*" == *"--name-only"* ]]; then printf '%s\n' $MOCK_FILES; return 0 2>/dev/null || exit 0; fi
    # diff <range> -- <path>: path 별 version 줄 노출 여부
    [[ -n "$MOCK_BUMP" ]] && echo '+  "version": "9.9.9"'
    ;;
esac
exit 0
GIT
  chmod +x "$ng"

  # mock forge: reviews JSON-jq 출력만 흉내(MOCK_REVIEWS = "STATE\tAUTHOR" 줄).
  cat >"$nf" <<'FORGE'
#!/usr/bin/env bash
echo "forge $*" >> "$TRACE"
if [[ "$1" == "pr" && "$2" == "view" ]]; then printf '%s\n' "$MOCK_REVIEWS"; fi
exit 0
FORGE
  chmod +x "$nf"

  # mock loop: cleanup 호출 기록.
  cat >"$nl" <<'LOOP'
#!/usr/bin/env bash
echo "loop $*" >> "$TRACE"
exit 0
LOOP
  chmod +x "$nl"

  # mock task backend: set-status 호출 기록(어휘는 task-backend 가 검증).
  mock_backend() {
    echo "backend $*" >> "$TRACE"
    case "$1" in get-status) echo "Review" ;; esac
  }
  export -f mock_backend

  export GIT_CMD="bash $ng" FORGE_CMD="bash $nf" LOOP_CMD="bash $nl"
  export TASK_BACKEND_CMD=mock_backend TRACE="$trace"
  export REVIEW_BOT="auto-review-bot" APPROVER="approver-bot"

  _reset() { : >"$trace"; }
  _setup_task() {
    local id="$1"; ensure_task_dir "$id"
    set_branch "$id" "feat/$id-x"; set_pr "$id" "77"
    set_field "$id" issue "77"
  }
  _check() { # <name> <cond 0/1> <desc>
    if [[ "$2" == "0" ]]; then echo "PASS: $1"; pass=$((pass+1));
    else echo "FAIL: $1 — $3"; fail=$((fail+1)); fi
  }
  _has() { grep -q "$1" "$trace" && echo 0 || echo 1; }
  _hasnt() { grep -q "$1" "$trace" && echo 1 || echo 0; }

  local spec="$tmp/SPEC.md"; printf '# T\n' >"$spec"

  # --- AC4/AC5/AC6: 승인 O + 워치 변경 없음 → 머지·Done·cleanup ---
  _reset; _setup_task t1
  MOCK_REVIEWS=$'APPROVED\tapprover-bot' MOCK_FILES="README.md" MOCK_BUMP="" \
    merge_finish "$spec" t1 >/dev/null 2>&1
  _check "AC4 ff-only 머지 호출" "$(_has 'git merge --ff-only')" "ff-only 머지 미호출"
  _check "AC5 Done 전이"        "$(_has 'backend set-status 77 Done')" "Done 전이 미호출"
  _check "AC6 cleanup 위임"     "$(_has 'loop cleanup')" "cleanup 위임 미호출"

  # --- AC2: 승인 없음 → 머지 안 함 ---
  _reset; _setup_task t2
  MOCK_REVIEWS=$'COMMENTED\tsomeone' MOCK_FILES="README.md" MOCK_BUMP="" \
    merge_finish "$spec" t2 >/dev/null 2>&1 || true
  _check "AC2 미승인 → 머지 안 함" "$(_hasnt 'git merge --ff-only')" "미승인인데 머지함"
  _check "AC2 미승인 → Done 안 함" "$(_hasnt 'backend set-status 77 Done')" "미승인인데 Done"

  # --- self-approve(자동 리뷰 봇) → 무효 → 머지 안 함 ---
  _reset; _setup_task t3
  MOCK_REVIEWS=$'APPROVED\tauto-review-bot' MOCK_FILES="README.md" MOCK_BUMP="" \
    merge_finish "$spec" t3 >/dev/null 2>&1 || true
  _check "self-approve 무효 → 머지 안 함" "$(_hasnt 'git merge --ff-only')" "self-approve 로 머지함"

  # --- AC3: plugins/** 변경 + 범프 없음 → 차단 ---
  _reset; _setup_task t4
  MOCK_REVIEWS=$'APPROVED\tapprover-bot' MOCK_FILES="plugins/foo/plugin.json" MOCK_BUMP="" \
    merge_finish "$spec" t4 >/dev/null 2>&1 || true
  _check "AC3 워치+범프없음 → 머지 차단" "$(_hasnt 'git merge --ff-only')" "범프 없는데 머지함"

  # --- AC3 반례: plugins/** 변경 + 범프 있음 → 머지 ---
  _reset; _setup_task t5
  MOCK_REVIEWS=$'APPROVED\tapprover-bot' MOCK_FILES="plugins/foo/plugin.json" MOCK_BUMP="1" \
    merge_finish "$spec" t5 >/dev/null 2>&1
  _check "AC3 워치+범프있음 → 머지" "$(_has 'git merge --ff-only')" "범프했는데 머지 안 함"

  # --- AC7: force 미사용(mock git 은 force 보면 exit99; 위 케이스 전부 통과했음) ---
  _check "AC7 force 미사용(머지 성공)" "$(_has 'git push origin main')" "force 사용/머지 실패"

  echo "----- selftest: $pass passed, $fail failed -----"
  [[ "$fail" -eq 0 ]]
}

# ----- 디스패처 (sourcing 시에는 실행되지 않음) -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  [[ $# -ge 1 ]] || usage
  SUB="$1"; shift || true
  case "$SUB" in
    finish)       require_git_root; merge_finish "$@" ;;
    approval)     [[ $# -ge 1 ]] || usage; approval_ok "$1" && echo approved || { echo unapproved; exit 1; } ;;
    version-gate) [[ $# -ge 1 ]] || usage; require_git_root; version_gate "$1" && echo pass || { echo block; exit 1; } ;;
    selftest)     selftest ;;
    -h|--help|help) usage ;;
    *) echo "알 수 없는 command: $SUB" >&2; usage ;;
  esac
fi
