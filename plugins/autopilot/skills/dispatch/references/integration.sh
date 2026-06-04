#!/usr/bin/env bash
# integration.sh — autopilot:dispatch per-SPEC 통합 (M2)
#
# 책임 ("loop DONE" 과 "리뷰 승인 요청(PR)" 사이의 다리):
#   - 종료 신호 판정: loop 의 공개 구조화 상태(`status --json`)로만 child 종료 의도를
#     읽어 통합 분기로 매핑한다(dispatch.sh 의 child_terminal_state 와 동일 산식).
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
#   - per-SPEC 상태는 lib-integration.sh(run-dir + 불투명 key)로만 보관한다.
#
# 키 계약: 통합 모듈은 per-SPEC 키를 **재계산하지 않고** 호출자(스케줄러)에게서 받는다
#   (dispatch.sh 가 spec_slug+hash7 로 한 번 계산해 모든 통합 모듈 호출에 같은 키를 넘긴다).
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
  # shellcheck source=lib-integration.sh
  . "$IN_SCRIPT_DIR/lib-integration.sh"
fi

LOOP_CMD_DEFAULT="bash $IN_SCRIPT_DIR/../../loop/references/loop.sh"
LOOP_CMD="${LOOP_CMD:-$LOOP_CMD_DEFAULT}"
GIT_CMD="${GIT_CMD:-git}"
FORGE_CMD="${FORGE_CMD:-gh}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

in_die() { echo "integration: $*" >&2; return 1; }

# =====================================================================
# 1) 종료 신호 판정 — loop 공개 구조화 상태(status --json)만 사용.
#    dispatch.sh child_terminal_state 와 동일 의미(done/failed/running/pending/unknown).
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
# 3) git 통합 — base sync(rebase, ff 가능 시) → push. force 금지.
# =====================================================================

in_base_sync() {
  local branch="$1"
  # shellcheck disable=SC2086
  $GIT_CMD fetch origin "$DEFAULT_BRANCH" || { in_die "fetch 실패: origin/$DEFAULT_BRANCH"; return 1; }
  # shellcheck disable=SC2086
  $GIT_CMD checkout "$branch" || { in_die "checkout 실패: $branch"; return 1; }
  # shellcheck disable=SC2086
  if ! $GIT_CMD rebase "origin/$DEFAULT_BRANCH"; then
    # shellcheck disable=SC2086
    $GIT_CMD rebase --abort || true
    in_die "rebase 충돌 — 사람 위임(force 금지): $branch ← origin/$DEFAULT_BRANCH"; return 1
  fi
}

in_push_branch() {
  # shellcheck disable=SC2086
  $GIT_CMD push origin "$1" || { in_die "push 실패(force 금지): $1"; return 1; }
}

# =====================================================================
# 4) PR 생성/재사용 — 같은 head 의 open PR 이 있으면 재사용.
# =====================================================================

in_existing_open_pr() {
  # shellcheck disable=SC2086
  $FORGE_CMD pr list --head "$1" --state open 2>/dev/null \
    | awk 'NR==1 { print $1 }' | tr -d '#'
}

# in_ensure_pr <branch> <title> — open PR 재사용 또는 신규 생성. PR 번호 echo.
in_ensure_pr() {
  local branch="$1" title="$2" n
  n="$(in_existing_open_pr "$branch")"
  if [[ -n "$n" ]]; then printf '%s\n' "$n"; return 0; fi
  # shellcheck disable=SC2086
  $FORGE_CMD pr create --head "$branch" --base "$DEFAULT_BRANCH" \
    --title "$title" --body "dispatch 통합: 구현 완료, 승인 요청." \
    >/dev/null 2>&1 || { in_die "PR 생성 실패: $branch"; return 1; }
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
      int_log "$rd" "$key" "base sync → push → PR (branch=$branch)"
      in_base_sync   "$branch" || { int_set_phase "$rd" "$key" blocked; return 4; }
      in_push_branch "$branch" || { int_set_phase "$rd" "$key" blocked; return 4; }
      local title pr
      title="$(in_spec_title "$spec")"
      pr="$(in_ensure_pr "$branch" "$title")" || { int_set_phase "$rd" "$key" blocked; return 4; }
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
      local cat; cat="$(in_blocked_category "$spec")"
      if [[ "$cat" == "spec-gap" ]]; then
        int_set_phase "$rd" "$key" blocked-spec-gap
        int_log "$rd" "$key" "BLOCKED spec-gap → 스펙 보강 재개 경로 안내(push·PR 안 함)"
        echo "key:      $key"
        echo "phase:    blocked-spec-gap"
        echo "category: spec-gap"
        echo "resume:   스펙 강화 후 dispatch --resume 로 재개하세요(push·PR 미수행)."
        return 3
      else
        int_set_phase "$rd" "$key" blocked
        int_log "$rd" "$key" "하드 차단($cat) → 사람 에스컬레이션(push·PR 안 함)"
        echo "key:      $key"
        echo "phase:    blocked"
        echo "category: $cat"
        echo "escalate: 사람 판단 필요(push·PR 미수행)."
        return 4
      fi
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

# ----- 사용법 -----
in_usage() {
  cat >&2 <<'EOF'
usage: integration.sh <command> [args]

Commands:
  integrate <spec> <run_dir> <key>   종료 신호를 읽어 매핑·통합:
                                        DONE→push→PR(phase=review) /
                                        spec-gap→blocked-spec-gap / 하드 BLOCKED→blocked.
  terminal  <spec>                   child 종료 상태(done|failed|running|pending|unknown).
  category  <spec>                   BLOCKED 범주(spec-gap|...|other).

환경 변수: LOOP_CMD, GIT_CMD, FORGE_CMD, DEFAULT_BRANCH
EOF
  return 1
}

# =====================================================================
# selftest — mock 인터페이스(loop/git/forge)로 통합 분기·force 미사용 독립 검증.
# =====================================================================
in_selftest() {
  local TMP; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' RETURN
  local rd="$TMP/.dispatch/runs/20260604T000000-abc1234"; mkdir -p "$rd"

  # mock loop: status --json / logs 를 spec 별 파일로 흉내.
  local LP="$TMP/loop"; mkdir -p "$LP"
  mock_loop() {
    case "$1" in
      status) shift; [[ "$1" == "--json" ]] && shift; cat "$LP/$(basename "$1").json" 2>/dev/null || true ;;
      logs)   cat "$LP/$(basename "$2").logs" 2>/dev/null || true ;;
    esac
  }
  export -f mock_loop 2>/dev/null || true
  LOOP_CMD=mock_loop

  # mock git: force 인자 보면 exit99(selftest 즉사). push/fetch/checkout/rebase 기록.
  local PUSHLOG="$TMP/pushlog" GITLOG="$TMP/gitlog"; : > "$PUSHLOG"; : > "$GITLOG"
  mock_git() {
    local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
    printf '%s\n' "$*" >> "$GITLOG"
    case "$1" in
      push) printf '%s\n' "$*" >> "$PUSHLOG" ;;
      rebase|fetch|checkout) : ;;
    esac
    return 0
  }
  GIT_CMD=mock_git

  # mock forge: pr list(재사용 제어 MOCK_PR), pr create 기록.
  local PRLOG="$TMP/prlog"; : > "$PRLOG"
  mock_forge() {
    case "$1 $2" in
      "pr list")   [[ -n "${MOCK_EXISTING_PR:-}" ]] && echo "$MOCK_EXISTING_PR" || true ;;
      "pr create") printf '%s\n' "$*" >> "$PRLOG"; echo created ;;
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

  # ---- AC: open PR 존재 → 재사용(새 PR 미생성) ----
  local kR="x-rrr2222"; : > "$PRLOG"
  MOCK_EXISTING_PR="55" in_integrate "$spec" "$rd" "$kR" >/dev/null; rc=$?
  chk "AC2 재사용 rc=0" "$rc" "0"
  chk "AC2 재사용 pr=55" "$(int_get_pr "$rd" "$kR")" "55"
  [[ ! -s "$PRLOG" ]] && ok "AC2 open PR 재사용(새 PR 미생성)" || bad "AC2 open PR 재사용(새 PR 미생성)"

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

  # ---- AC: force 미사용 (mock_git 은 force 보면 exit99; 여기 도달했으면 미사용) ----
  [[ -s "$PUSHLOG" || -s "$GITLOG" ]] && ok "git/push 실제 수행됨" || bad "git/push 실제 수행됨"
  if grep -qiE 'force|(^| )-f( |$)' "$GITLOG"; then bad "force 미사용"; else ok "force 미사용(git 인자에 force 없음)"; fi

  echo "----"
  [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"
  return $fail
}

# ----- CLI 진입 (sourcing 시 미실행) -----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  SUB="${1:-}"; shift || true
  case "$SUB" in
    integrate) in_integrate "$@" ;;
    terminal)  [[ $# -ge 1 ]] || in_usage; in_child_terminal_state "$1" ;;
    category)  [[ $# -ge 1 ]] || in_usage; in_blocked_category "$1" ;;
    selftest)  in_selftest ;;
    -h|--help|help) in_usage ;;
    *) echo "알 수 없는 command: $SUB" >&2; in_usage ;;
  esac
fi
