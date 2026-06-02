#!/usr/bin/env bash
# forge.sh — autopilot:fsd 종료신호→push→PR 통합 (C2)
#
# 책임 ("구현 완료"와 "승인 요청(Review)" 사이의 다리):
#   - 종료 신호 매핑: 자율 실행기(loop)의 공개 상태 인터페이스만으로 child 의
#     종료 의도를 읽어 task 상태로 매핑한다.
#       DONE(차단 없음)            → task: In Progress → Review + 통합(base sync→push→PR)
#       BLOCKED category=spec-gap  → task: In Design (차단 기록 + --resume 경로 표면화)
#       BLOCKED 그 외 하드 범주     → task: Blocked (사람 에스컬레이션, push·PR 안 함)
#   - base sync: 작업 브랜치를 default branch(main)에 rebase (fast-forward 가능할 때만).
#   - push: 작업 결과를 `feat/<task-id>-<slug>` 브랜치로 원격에 push.
#   - PR 생성/재사용: 같은 head 의 open PR 이 있으면 재사용, 없으면 생성.
#
# 불변식:
#   - force(강제) push·rebase 금지 (어떤 경로에서도).
#   - 종료 상태는 자율 실행기의 공개 인터페이스(`loop.sh status`/`logs`)로만 읽고,
#     child 워크트리·내부 신호 파일을 직접 열지 않는다.
#   - forge 통합은 단일 출처 규칙의 실행자다:
#       rules/orchestration/forge-integration.md  (책임표·신호 계약·DONE 통합 흐름)
#       rules/engineering/branch-and-slug.md       (브랜치명·slug·원격 동기화 절차)
#
# **하지 않는 일** (다른 단위 책임):
#   - SKILL.md·상태 전이 헬퍼 정의(C0/C1), 리뷰 루프(C3), 머지·Done·cleanup(C4),
#     poll 드레인(C5), loop·dispatch 코드 변경(공개 인터페이스만 소비).
#
# 이 모듈은 sourcing(함수 라이브러리) 또는 직접 호출(디스패처) 양쪽으로 쓴다.
# 모든 외부 인터페이스(loop·git·forge CLI)는 주입 가능한 명령 변수로 두어
# mock 인터페이스로 독립 검증한다(self-referential: runtime artifact 미검사).
#
# 환경 변수 (테스트에서 mock 으로 치환 가능):
#   LOOP_CMD              자율 실행기 driver 호출 (기본: 형제 loop.sh).
#   GIT_CMD               git 호출 (기본: git).
#   FORGE_CMD             forge(PR) CLI 호출 (기본: gh).
#   DEFAULT_BRANCH        base branch (기본: main).
#   FSD_STATE_ROOT  상태 루트 (기본 <project_root>/.fsd). lib-state.sh 참조.
#
# bash 3.2+ 호환 (associative array 미사용).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 상태 저장소 헬퍼 로드(C0). set_state/get_branch/set_pr/log_event 등.
# shellcheck source=lib-state.sh
. "$SCRIPT_DIR/lib-state.sh"

# 자율 실행기 공개 인터페이스 — dispatch 와 동일 패턴(주입 가능).
LOOP_CMD_DEFAULT="bash $SCRIPT_DIR/../../loop/references/loop.sh"
LOOP_CMD="${LOOP_CMD:-$LOOP_CMD_DEFAULT}"

# git·forge CLI — 주입 가능(mock 검증). force 옵션은 어디서도 쓰지 않는다.
GIT_CMD="${GIT_CMD:-git}"
FORGE_CMD="${FORGE_CMD:-gh}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# ----- task 상태 이름 (task backend 상태; EARS 수용 기준의 표면 어휘) -----
# C1 backend 전이 헬퍼가 생기면 set_state 자리에서 그 공개 함수로 위임한다.
ST_IN_PROGRESS="In Progress"
ST_REVIEW="Review"
ST_IN_DESIGN="In Design"
ST_BLOCKED="Blocked"

# ----- 공통 -----

die() { echo "ERROR: $*" >&2; exit 1; }

require_git_root() {
  PROJECT_ROOT="$($GIT_CMD rev-parse --show-toplevel 2>/dev/null)" \
    || die "git 저장소 안에서 실행해야 합니다."
  export PROJECT_ROOT
}

# =====================================================================
# 1) 종료 신호 판정 — 자율 실행기의 공개 인터페이스로만 읽는다.
#    참조 패턴: dispatch.sh 의 loop_status_state/loop_status_files/child_terminal_state.
# =====================================================================

# loop_status_state <spec> — loop status 출력의 STATE 컬럼.
loop_status_state() {
  # shellcheck disable=SC2086
  $LOOP_CMD status "$1" 2>/dev/null | awk 'NR==2 { print $2 }'
}

# loop_status_files <spec> — FILES 컬럼(signals/ 내 파일명 목록 또는 "-").
loop_status_files() {
  # shellcheck disable=SC2086
  $LOOP_CMD status "$1" 2>/dev/null | awk 'NR==2 { print $3 }'
}

# child_terminal_state <spec> — pending|running|done|failed
#   done   : STATE=terminal 이고 FILES 에 BLOCKED 없음(=DONE).
#   failed : STATE=terminal 이고 FILES 에 BLOCKED 있음(워커 컨벤션).
#   running: STATE=running|stale.   pending: 그 외.
child_terminal_state() {
  local st files
  st="$(loop_status_state "$1")"
  files="$(loop_status_files "$1")"
  case "$st" in
    terminal)
      if printf '%s' "$files" | grep -q 'BLOCKED'; then echo "failed"; else echo "done"; fi
      ;;
    running|stale) echo "running" ;;
    *) echo "pending" ;;
  esac
}

# loop_blocked_category <spec> — BLOCKED 신호의 category 범주.
#   공개 `logs` 인터페이스(signals/ 본문 dump)에서 첫 'category:' 줄을 읽는다.
#   forge 는 워크트리 신호 파일을 직접 열지 않는다(공개 인터페이스 경유).
#   미검출이면 'other'(하드 차단으로 보수적 처리).
loop_blocked_category() {
  local cat
  # set -euo pipefail 환경: grep 미매치 시 pipefail 로 파이프라인이 non-zero 가 되어
  # 할당문이 함수를 종료시킨다. `|| true` 로 감싸 미검출 시 빈 문자열→'other' fallback
  # 이 실제로 동작하게 한다(awk 한 번으로 추출해 파이프 단계도 줄인다).
  # shellcheck disable=SC2086
  cat="$($LOOP_CMD logs "$1" 2>/dev/null \
    | awk 'tolower($0) ~ /^category:/ { sub(/^[Cc][Aa][Tt][Ee][Gg][Oo][Rr][Yy]:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }' \
    || true)"
  [[ -n "$cat" ]] && printf '%s\n' "$cat" || printf '%s\n' "other"
}

# =====================================================================
# 2) task 상태 전이 (lib-state 미러; C1 backend 전이 헬퍼의 plug 지점).
# =====================================================================

transition_to_review()    { set_state "$1" "$ST_REVIEW";      log_event "$1" "state → $ST_REVIEW"; }
transition_to_in_design() { set_state "$1" "$ST_IN_DESIGN";   log_event "$1" "state → $ST_IN_DESIGN"; }
transition_to_blocked()   { set_state "$1" "$ST_BLOCKED";     log_event "$1" "state → $ST_BLOCKED ($2)"; }

# =====================================================================
# 3) 브랜치·slug — rules/engineering/branch-and-slug.md 실행자.
# =====================================================================

# spec_title <spec_path> — SPEC 첫 H1(frontmatter 밖) 제목.
spec_title() {
  awk '
    /^---$/ { fm = !fm; next }
    !fm && /^# / { sub(/^# /, ""); print; exit }
  ' "$1"
}

# slug_from_title <title> — branch-and-slug.md 단일 출처 규칙.
slug_from_title() {
  printf '%s' "$1" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -c 'a-z0-9-' '-' \
    | sed -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# work_branch <task-id> <spec_path> — 작업 브랜치명 feat/<task-id>-<slug>.
work_branch() {
  local id="$1" spec="$2" slug
  slug="$(slug_from_title "$(spec_title "$spec")")"
  [[ -n "$slug" ]] || die "SPEC 제목에서 slug 를 만들 수 없음(제목 수정 필요): $spec"
  printf 'feat/%s-%s\n' "$id" "$slug"
}

# =====================================================================
# 4) git 통합 — base sync(rebase, ff 가능 시) → push. force 금지.
# =====================================================================

# base_sync <branch> — 작업 브랜치를 default branch 에 rebase. 충돌 시 중단·위임.
#   force 옵션을 절대 쓰지 않는다.
base_sync() {
  local branch="$1"
  # shellcheck disable=SC2086
  $GIT_CMD fetch origin "$DEFAULT_BRANCH" || die "fetch 실패: origin/$DEFAULT_BRANCH"
  # shellcheck disable=SC2086
  $GIT_CMD checkout "$branch" || die "checkout 실패: $branch"
  # shellcheck disable=SC2086
  if ! $GIT_CMD rebase "origin/$DEFAULT_BRANCH"; then
    # shellcheck disable=SC2086
    $GIT_CMD rebase --abort || true
    die "rebase 충돌 — 사람에게 위임(force 금지): $branch ← origin/$DEFAULT_BRANCH"
  fi
}

# push_branch <branch> — 작업 브랜치를 원격에 push. force 금지.
push_branch() {
  # shellcheck disable=SC2086
  $GIT_CMD push origin "$1" || die "push 실패(force 금지): $1"
}

# =====================================================================
# 5) PR 생성/재사용 — 같은 head 의 open PR 이 있으면 재사용.
# =====================================================================

# existing_open_pr <branch> — head=branch 의 open PR 번호(없으면 빈 출력).
existing_open_pr() {
  # shellcheck disable=SC2086
  $FORGE_CMD pr list --head "$1" --state open 2>/dev/null \
    | awk 'NR==1 { print $1 }' | tr -d '#'
}

# ensure_pr <branch> <title> — open PR 재사용 또는 신규 생성. PR 번호를 echo.
ensure_pr() {
  local branch="$1" title="$2" n
  n="$(existing_open_pr "$branch")"
  if [[ -n "$n" ]]; then
    printf '%s\n' "$n"
    return 0
  fi
  # 신규 생성. body 자동 영역만 채우고 reviewer/label 은 정책 기본(미설정).
  # shellcheck disable=SC2086
  $FORGE_CMD pr create --head "$branch" --base "$DEFAULT_BRANCH" \
    --title "$title" --body "fsd 통합: 구현 완료, 승인 요청." \
    >/dev/null 2>&1 || die "PR 생성 실패: $branch"
  existing_open_pr "$branch"
}

# =====================================================================
# 6) 메인 진입 — 한 task 의 종료 신호를 읽어 매핑·통합한다.
# =====================================================================

# forge_integrate <spec_path> <task-id>
#   DONE   → Review + base sync → push → PR (이 순서).
#   spec-gap BLOCKED → In Design (차단 기록 + --resume 표면화).
#   기타 하드 BLOCKED → Blocked (push·PR 없음, 사람 에스컬레이션).
forge_integrate() {
  local spec="$1" id="$2"
  [[ -n "$spec" && -n "$id" ]] || die "사용: forge.sh integrate <spec> <task-id>"
  ensure_task_dir "$id"

  local term; term="$(child_terminal_state "$spec")"
  log_event "$id" "forge_integrate spec=$spec terminal=$term"

  case "$term" in
    done)
      local branch; branch="$(work_branch "$id" "$spec")"
      set_branch "$id" "$branch"
      log_event "$id" "base sync → push → PR (branch=$branch)"
      base_sync   "$branch"
      push_branch "$branch"
      local title pr
      title="$(spec_title "$spec")"
      pr="$(ensure_pr "$branch" "$title")"
      [[ -n "$pr" ]] && set_pr "$id" "$pr"
      transition_to_review "$id"
      log_event "$id" "PR=$pr 인계 — Review 대기"
      echo "task-id: $id"
      echo "state:   $ST_REVIEW"
      echo "branch:  $branch"
      echo "pr:      $pr"
      ;;
    failed)
      local cat; cat="$(loop_blocked_category "$spec")"
      if [[ "$cat" == "spec-gap" ]]; then
        transition_to_in_design "$id"
        log_event "$id" "BLOCKED spec-gap → In Design. 재개: fsd start --resume (스펙 강화 후)"
        echo "task-id: $id"
        echo "state:   $ST_IN_DESIGN"
        echo "category: spec-gap"
        echo "resume:  스펙 강화 후 --resume 로 재개하세요."
      else
        transition_to_blocked "$id" "$cat"
        log_event "$id" "하드 차단($cat) → Blocked. push·PR 안 함. 사람 에스컬레이션."
        echo "task-id: $id"
        echo "state:   $ST_BLOCKED"
        echo "category: $cat"
        echo "escalate: 사람 판단 필요 (push·PR 미수행)."
      fi
      ;;
    running|pending)
      echo "task-id: $id"
      echo "terminal: $term (아직 종료 신호 없음 — 통합 보류)"
      return 0
      ;;
    *)
      die "알 수 없는 terminal state: $term"
      ;;
  esac
}

# ----- 사용법 -----
usage() {
  cat >&2 <<'EOF'
usage: forge.sh <command> [args]

Commands:
  integrate <spec> <task-id>   종료 신호를 읽어 매핑·통합:
                                 DONE→Review(+base sync→push→PR) /
                                 spec-gap→In Design / 하드 BLOCKED→Blocked.
  terminal  <spec>             child 종료 상태(done|failed|running|pending) 출력.
  category  <spec>             BLOCKED 범주(spec-gap|...|other) 출력.

환경 변수: LOOP_CMD, GIT_CMD, FORGE_CMD, DEFAULT_BRANCH, FSD_STATE_ROOT
EOF
  exit 1
}

# ----- 디스패처 (sourcing 시에는 실행되지 않음) -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  [[ $# -ge 1 ]] || usage
  SUB="$1"; shift || true
  case "$SUB" in
    integrate) require_git_root; forge_integrate "$@" ;;
    terminal)  [[ $# -ge 1 ]] || usage; child_terminal_state "$1" ;;
    category)  [[ $# -ge 1 ]] || usage; loop_blocked_category "$1" ;;
    -h|--help|help) usage ;;
    *) echo "알 수 없는 command: $SUB" >&2; usage ;;
  esac
fi
