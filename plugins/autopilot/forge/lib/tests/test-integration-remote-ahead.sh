#!/usr/bin/env bash
# test-integration-remote-ahead.sh — 원격-앞섬 브랜치 통합 회귀 가드 (run 592 관측).
#   시나리오: 원격 작업 브랜치가 로컬 브랜치 ref 보다 앞서 있고(로컬이 원격 tip 의 조상 —
#   리뷰 수정 푸시 등 정당한 전진) open PR 이 존재.
#   기대: integrate 가 push 실패 없이 완료(rc=0, phase=review, PR 재사용). force 금지 유지.
#     - stale ref push 를 시도하지 않는다(원격이 이미 모든 로컬 커밋 보유 → push 불필요).
#     - 원격-앞섬을 stale 잔여로 오판해 PR close·원격 브랜치 삭제로 파괴하지 않는다.
#   mock git 은 실제 git 처럼 원격-앞섬 브랜치로의 non-ff push 를 거부한다(회귀 재현 조건).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

# integration.sh 를 source (하단 BASH_SOURCE 가드로 main 미실행).
# shellcheck disable=SC1091
. "$HERE/../integration.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
RD="$TMP/.autopilot/runs/20260714T000000-run592"; mkdir -p "$RD"
SPEC="$TMP/SPEC.md"
printf '# remote ahead feature x\n\n## 무엇\n...\n' > "$SPEC"
BRANCH="feat/20260714T000000-run592-remote-ahead-feature-x"

# ---- mock loop: 종료=DONE, paths 는 결과 워크트리 ----
LOOPWT="$TMP/loopwt"; mkdir -p "$LOOPWT"
mock_loop() {
  case "$1" in
    status) printf '{"state":"terminal","signals":["DONE"]}\n' ;;
    logs)   : ;;
    paths)  printf 'SPEC_PATH   %s\nWT          %s\nLOOP_DIR    %s\n' "$2" "$LOOPWT" "$LOOPWT/.loop" ;;
    cleanup) return 0 ;;
  esac
}
LOOP_CMD=mock_loop

# ---- mock git: 원격-앞섬 상태를 실제처럼 모사 ----
#   로컬 ref = localcommit / 원격 tip = remotetip / localcommit ⊂ remotetip (원격이 앞섬).
#   stale 로컬 ref 의 브랜치명 push 는 실제 git 처럼 non-ff 로 거부한다.
GITLOG="$TMP/gitlog" PUSHLOG="$TMP/pushlog" BRANCHES="$TMP/branches"
: > "$GITLOG"; : > "$PUSHLOG"; printf '%s\n' "$BRANCH" > "$BRANCHES"
mock_git() {
  if [[ "$1" == "-C" ]]; then shift 2; fi
  local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
  printf '%s\n' "$*" >> "$GITLOG"
  case "$1" in
    fetch|rebase) return 0 ;;
    ls-remote) printf 'remotetip\trefs/heads/%s\n' "$BRANCH" ;;
    rev-parse)
      case "$*" in
        *--verify*refs/heads/*) grep -Fxq "$BRANCH" "$BRANCHES" 2>/dev/null; return $? ;;
        *--absolute-git-dir*) printf '%s/gitdir\n' "$TMP"; return 0 ;;
        *refs/heads/*) grep -Fxq "$BRANCH" "$BRANCHES" 2>/dev/null && { echo "localcommit"; return 0; } || return 1 ;;
        *HEAD*) echo "localcommit"; return 0 ;;
      esac ;;
    merge-base)
      # --is-ancestor <A> <B>: A 가 B 의 조상인가.
      case "$*" in
        *origin/*)                       return 1 ;;  # base(origin/main) 전진 — 브랜치 조상 아님.
        *"remotetip localcommit"*)       return 1 ;;  # 원격 tip 은 로컬의 조상 아님(원격이 더 많음).
        *"localcommit remotetip"*)       return 0 ;;  # 로컬은 원격 tip 의 조상 = 원격-앞섬.
        *) return 1 ;;
      esac ;;
    branch) printf '%s\n' "$2" >> "$BRANCHES"; return 0 ;;
    push)
      printf '%s\n' "$*" >> "$PUSHLOG"
      case "$*" in
        *--delete*) return 0 ;;
        *)
          # 실제 git 재현: 원격이 앞선 브랜치로의 브랜치명/HEAD push 는 non-ff 거부.
          echo "! [rejected] $BRANCH -> $BRANCH (non-fast-forward)" >&2
          return 1 ;;
      esac ;;
    worktree) return 0 ;;
  esac
  return 0
}
GIT_CMD=mock_git

# ---- mock forge: open PR #91 존재(autopilot 소유 신호 포함 — 오판 시 파괴 경로 노출) ----
PRCLOSELOG="$TMP/prclose" PRLOG="$TMP/prlog"; : > "$PRCLOSELOG"; : > "$PRLOG"
mock_forge() {
  case "$1 $2" in
    "pr list")  echo "91" ;;
    "pr view")
      case "$*" in
        *"--json author"*)  echo "courtesy-bot" ;;
        *"--json reviews"*) printf 'courtesy-bot\t<!-- claude-formal-review head_sha=x verdict=approve -->\n' ;;
      esac ;;
    "pr close") printf '%s\n' "$3" >> "$PRCLOSELOG" ;;
    "pr create") printf '%s\n' "$*" >> "$PRLOG"; echo created ;;
  esac
  return 0
}
FORGE_CMD=mock_forge
DEFAULT_BRANCH=main

# ---- 실행 ----
rc=0; in_integrate "$SPEC" "$RD" "run592-key" >/dev/null 2>&1 || rc=$?

# ---- 단언 ----
chk "1: 원격-앞섬+open PR → integrate rc=0(push 실패 없음)" "$rc" "0"
chk "2: phase=review" "$(int_get_phase "$RD" "run592-key")" "review"
chk "3: open PR 재사용(pr=91)" "$(int_get_pr "$RD" "run592-key")" "91"
[[ ! -s "$PRLOG" ]] && ok "4: 새 PR 미생성(재사용)" || bad "4: 새 PR 미생성(재사용)"
[[ ! -s "$PRCLOSELOG" ]] && ok "5: 원격-앞섬을 stale 로 오판해 PR close 안 함" || bad "5: 원격-앞섬 PR close 안 함"
grep -q -- '--delete' "$PUSHLOG" && bad "6: 원격 브랜치 삭제 안 함(리뷰 커밋 보존)" || ok "6: 원격 브랜치 삭제 안 함(리뷰 커밋 보존)"
[[ ! -s "$PUSHLOG" ]] && ok "7: stale 로컬 ref push 시도 없음(원격이 이미 보유)" || bad "7: stale 로컬 ref push 시도 없음 (pushlog: $(cat "$PUSHLOG" 2>/dev/null | tr '\n' ';'))"
grep -qE "^fetch origin $BRANCH" "$GITLOG" && ok "8: 판정 직전 원격 브랜치 fetch(레이스 완화)" || bad "8: 판정 직전 원격 브랜치 fetch(레이스 완화)"
if grep -qiE 'force|(^| )-f( |$)' "$GITLOG"; then bad "9: force 미사용"; else ok "9: force 미사용"; fi

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || { echo "FAILURES present"; exit 1; }
