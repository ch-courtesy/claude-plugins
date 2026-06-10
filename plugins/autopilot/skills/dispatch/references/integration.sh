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
# 2b) loop 결과 → 작업 브랜치 이식 다리 (forge·direct 공통 헬퍼).
#   loop 은 결과를 자기 워크트리에만 커밋하고 dispatch run-id 브랜치를 만들지 않는다.
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
#   이미 있으면 그대로 사용(재실행 멱등). 어떤 경로에서도 force 로 옮기지 않는다.
#   forge·direct 서브모드가 공유하는 단일 진입(브랜치 이식 중복 방지).
in_ensure_work_branch() {
  local branch="$1" spec="$2"
  # shellcheck disable=SC2086
  if $GIT_CMD rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1; then
    return 0   # 이미 존재 — 멱등, force 재배치 안 함.
  fi
  local commit; commit="$(in_loop_result_commit "$spec")" || return 1
  # shellcheck disable=SC2086
  $GIT_CMD branch "$branch" "$commit" \
    || { in_die "작업 브랜치 생성 실패: $branch ← $commit"; return 1; }
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
  # origin/main 이 이미 브랜치 조상이면 동기화 불필요 — 재작성 없이 push 는 fast-forward.
  # shellcheck disable=SC2086
  if $GIT_CMD merge-base --is-ancestor "origin/$DEFAULT_BRANCH" "$branch" 2>/dev/null; then
    return 0
  fi
  # base 가 전진했고 원격 브랜치(open PR)가 이미 있으면, rebase 재작성은 SHA 를 바꿔
  # force 없는 push 를 non-fast-forward 로 실패시킨다(force 금지). 따라서 재작성하지 않고
  # 그대로 둔다 — base 정합은 머지 단계의 ff-only 게이트가 별도로 강제한다(여기서 force·
  # 재작성하지 않는다). 최초 통합(원격 브랜치 미존재)에서만 rebase 후 새 브랜치 push(ff-safe).
  if [[ -n "$(in_existing_open_pr "$branch")" ]]; then
    return 0
  fi
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
#   브랜치 미상 → 보존(보수적). in_handle_blocked(워커 자기 escalation)와 dispatch reap/timeout
#   오케스트레이션(CLI: cleanup-on-fail)이 공유하는 단일 진입.
in_cleanup_failed_worktree() {
  local spec="$1" rd="$2" branch
  local rid; rid="$(basename "$rd")"
  branch="$(in_work_branch "$rid" "$spec" 2>/dev/null || true)"
  in_cleanup_worktree_if_preserved "$spec" "$branch"
}

# =====================================================================
# 4) PR 생성/재사용 — 같은 head 의 open PR 이 있으면 재사용.
#    본문은 정적 한 줄이 아니라 in_pr_body 의 구조화 본문(SPEC 추적성·요약·실행 컨텍스트).
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

# in_pr_body <spec_path> <run-id> — 구조화 PR 본문(결정적) stdout.
#   자동 리뷰 식별 줄(dispatch 자동 생성·자동 적대 리뷰) + 추적성(SPEC 경로) + 실행 컨텍스트
#   (dispatch run-id) + 조건부 이슈 cross-reference(Refs #n, rules/context.md 형식) + 요약
#   (SPEC 의도 섹션, 없으면 생략).
in_pr_body() {
  local spec="$1" rid="$2"
  printf '🤖 이 PR 은 dispatch 가 자동 생성했으며 자동 적대 리뷰를 거칩니다.\n\n'
  printf 'SPEC: %s\n' "$spec"
  printf 'dispatch-run: %s\n' "$rid"
  local issue; issue="$(in_spec_issue "$spec")"
  [[ -n "$issue" ]] && printf 'Refs #%s\n' "$issue"
  local summary; summary="$(in_pr_summary "$spec")"
  if [[ -n "${summary//[$' \t\n']/}" ]]; then
    printf '\n## 요약\n\n%s\n' "$summary"
  fi
}

# in_ensure_pr <branch> <title> <spec> <run-id> — open PR 재사용 또는 신규 생성. PR 번호 echo.
#   신규 생성 PR 에만 자동 리뷰 표시를 단다(제목 '🤖 [자동 리뷰]' 접두 + 본문 식별 줄(in_pr_body)) —
#   open PR 재사용(조기 반환) 경로는 기존 PR 제목·본문을 건드리지 않는다(수정 호출 없음).
#   본문은 임시 파일 + --body-file 로 전달해 셸 인용·줄바꿈 손상 없이 멀티라인을 보존한다.
in_ensure_pr() {
  local branch="$1" title="$2" spec="$3" rid="$4" n
  n="$(in_existing_open_pr "$branch")"
  if [[ -n "$n" ]]; then printf '%s\n' "$n"; return 0; fi
  local bodyf; bodyf="$(mktemp)" || { in_die "PR 본문 임시 파일 생성 실패"; return 1; }
  in_pr_body "$spec" "$rid" > "$bodyf"
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
      int_log "$rd" "$key" "base sync → push → PR (branch=$branch)"
      in_base_sync   "$branch" || { int_set_phase "$rd" "$key" blocked; return 4; }
      in_push_branch "$branch" || { int_set_phase "$rd" "$key" blocked; return 4; }
      local title pr
      title="$(in_spec_title "$spec")"
      pr="$(in_ensure_pr "$branch" "$title" "$spec" "$rid")" || { int_set_phase "$rd" "$key" blocked; return 4; }
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
    echo "resume:   스펙 강화 후 dispatch --resume 로 재개하세요(push·PR 미수행)."
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
                                        보존). dispatch reap/timeout 으로 child 를 종료할 때
                                        오케스트레이션이 호출하는 진입(워커 escalation 과 동일 정책).

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
      # merge-base --is-ancestor: MOCK_ANCESTOR=1 이면 조상(0), 기본 비조상(1).
      merge-base) [[ "${MOCK_ANCESTOR:-0}" == "1" ]] && return 0 || return 1 ;;
      rev-parse)
        case "$*" in
          *--verify*refs/heads/*)
            local b="${*##*refs/heads/}"; b="${b%% *}"
            grep -Fxq "$b" "$BRANCHES" 2>/dev/null && return 0 || return 1 ;;
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
  local PRLOG="$TMP/prlog" PRBODY="$TMP/prbody"; : > "$PRLOG"; : > "$PRBODY"
  mock_forge() {
    case "$1 $2" in
      "pr list")   [[ -n "${MOCK_EXISTING_PR:-}" ]] && echo "$MOCK_EXISTING_PR" || true ;;
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
  # ---- AC: 신규 생성 PR 의 자동 리뷰 표시(제목 접두 태그 + 본문 식별 줄) ----
  grep -Fq -- '--title 🤖 [자동 리뷰] ' "$PRLOG" \
    && ok "AC 신규 PR 제목 자동 리뷰 접두 태그" || bad "AC 신규 PR 제목 자동 리뷰 접두 태그"
  grep -Fq '자동 적대 리뷰' "$PRBODY" \
    && ok "AC 신규 PR 본문 자동 리뷰 식별 줄" || bad "AC 신규 PR 본문 자동 리뷰 식별 줄"

  # ---- AC: open PR 존재 → 재사용(새 PR 미생성) + 기존 브랜치 rebase 재작성 안 함 ----
  #   (Codex blocking 회귀 가드: base 전진+원격 브랜치 존재 시 rebase 는 non-ff push 를 부른다.)
  local kR="x-rrr2222"; : > "$PRLOG"; : > "$GITLOG"
  MOCK_EXISTING_PR="55" in_integrate "$spec" "$rd" "$kR" >/dev/null; rc=$?
  chk "AC2 재사용 rc=0" "$rc" "0"
  chk "AC2 재사용 pr=55" "$(int_get_pr "$rd" "$kR")" "55"
  [[ ! -s "$PRLOG" ]] && ok "AC2 open PR 재사용(새 PR 미생성)" || bad "AC2 open PR 재사용(새 PR 미생성)"
  if grep -q 'rebase' "$GITLOG"; then bad "기존 PR 재통합 시 rebase 재작성(non-ff 위험)"; else ok "기존 PR 재통합 시 rebase 재작성 안 함(non-ff 회피)"; fi

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

  # ---- U2: cleanup-on-fail CLI 헬퍼(dispatch reap/timeout 경로 공유 진입) ----
  #   dispatch 가 child 를 reap/stop 할 때 오케스트레이션이 호출하는 동일 정책 진입점.
  local kCLI="x-cli2222"; : > "$CLEANUPLOG"
  printf '%s\n' "$wbF" > "$REMOTE_BRANCHES"
  in_cleanup_worktree_if_preserved "$spec" "$wbF"
  grep -Fxq "$spec" "$CLEANUPLOG" && ok "U2 헬퍼: 원격보존 → cleanup" || bad "U2 헬퍼: 원격보존 → cleanup"
  : > "$CLEANUPLOG"; : > "$REMOTE_BRANCHES"
  in_cleanup_worktree_if_preserved "$spec" "$wbF"
  [[ ! -s "$CLEANUPLOG" ]] && ok "U2 헬퍼: 미보존 → 보존" || bad "U2 헬퍼: 미보존 → 보존"

  # ---- PR 본문 구조화(in_pr_body): SPEC 경로·run-id 포함, 요약 섹션 본문(주석 제거),
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
  body="$(in_pr_body "$specB" "20260604T000000-abc1234")"
  case "$body" in *"$specB"*) ok "본문 SPEC 경로 포함";; *) bad "본문 SPEC 경로 포함";; esac
  case "$body" in *20260604T000000-abc1234*) ok "본문 run-id 포함";; *) bad "본문 run-id 포함";; esac
  case "$body" in *"요약 첫 줄이다."*"요약 둘째 줄이다."*) ok "본문 요약 섹션 전체 포함";; *) bad "본문 요약 섹션 전체 포함";; esac
  case "$body" in *"설명용 주석"*) bad "본문 요약 주석 제거";; *) ok "본문 요약 주석 제거";; esac
  case "$body" in *"목적 (왜)"*) bad "본문 다음 섹션 미포함(요약 경계)";; *) ok "본문 다음 섹션 미포함(요약 경계)";; esac
  case "$body" in *'Refs #'*) bad "이슈 없음 → cross-reference 미생성";; *) ok "이슈 없음 → cross-reference 미생성";; esac
  case "$body" in *'dispatch 통합:'*) bad "정적 한 줄 본문 부재";; *) ok "정적 한 줄 본문 부재";; esac

  # ---- 요약 섹션 부재 → 요약 블록 생략, 나머지 본문 정상 생성 ----
  body="$(in_pr_body "$spec" "rid7777")"   # $spec 에는 '무엇을 만들 것인가' 섹션이 없다.
  case "$body" in *"$spec"*) ok "요약 부재: SPEC 경로 정상";; *) bad "요약 부재: SPEC 경로 정상";; esac
  case "$body" in *rid7777*) ok "요약 부재: run-id 정상";; *) bad "요약 부재: run-id 정상";; esac
  case "$body" in *'## 요약'*) bad "요약 부재 시 요약 블록 생략";; *) ok "요약 부재 시 요약 블록 생략";; esac

  # ---- 이슈 식별 정보(frontmatter issue:) 존재 → cross-reference 한 줄 ----
  local specI="$TMP/SPECI.md"
  printf -- '---\nissue: 42\n---\n\n# 이슈 기능 Z\n' > "$specI"
  body="$(in_pr_body "$specI" "rid8888")"
  case "$body" in *'Refs #42'*) ok "이슈 존재 → Refs #42 한 줄";; *) bad "이슈 존재 → Refs #42 한 줄";; esac
  printf -- '---\nissue: "#43"\n---\n\n# 이슈 기능 W\n' > "$specI"
  body="$(in_pr_body "$specI" "rid8888")"
  case "$body" in *'Refs #43'*) ok "이슈 '#43' 표기 정규화";; *) bad "이슈 '#43' 표기 정규화";; esac

  # ---- PR 생성이 --body-file 로 멀티라인 본문을 forge 에 전달(줄바꿈 보존) ----
  local kB="x-bbb0000"; : > "$PRLOG"; : > "$PRBODY"; : > "$PUSHLOG"
  st_done > "$LP/SPECB.md.json"; : > "$LP/SPECB.md.logs"
  MOCK_EXISTING_PR="" in_integrate "$specB" "$rd" "$kB" >/dev/null; rc=$?
  chk "본문 통합 rc=0" "$rc" "0"
  grep -q -- '--body-file' "$PRLOG" && ok "PR 생성에 --body-file 사용" || bad "PR 생성에 --body-file 사용"
  [[ "$(wc -l < "$PRBODY")" -gt 1 ]] && ok "forge 전달 본문 멀티라인(줄바꿈 보존)" || bad "forge 전달 본문 멀티라인(줄바꿈 보존)"
  grep -Fq "$specB" "$PRBODY" && ok "forge 전달 본문에 SPEC 경로" || bad "forge 전달 본문에 SPEC 경로"
  grep -q '20260604T000000-abc1234' "$PRBODY" && ok "forge 전달 본문에 run-id" || bad "forge 전달 본문에 run-id"
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
