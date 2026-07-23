#!/usr/bin/env bash
# test-integration-worktree-delta.sh — 워크트리 델타 커밋 push 회귀 가드 (run 638 관측).
#   시나리오: 리뷰-수정 커밋이 loop 워크트리의 분리(detached) HEAD 에만 쌓이고 로컬 브랜치
#   ref 는 stale(#452: 공유 체크아웃 미오염을 위해 로컬 ref 미갱신).
#   기대: push 판정을 **실제 통합 대상 커밋**(워크트리 HEAD) 기준으로 수행한다.
#     A. 로컬 ref=f / 워크트리 HEAD=f+1 / 원격 tip=f → 델타 커밋을 직접 push(생략 아님).
#     B. 원격 tip 이 이미 델타 커밋을 포함 → 정당한 원격-앞섬으로 push 생략(run 592 불변).
#     C. 워크트리 델타 없음 + 원격-앞섬 → 기존대로 push 생략.
#     D. 브랜치 ref 가 이미 origin/main 에 포함(머지 완료) → 무관한 run 워크트리 커밋을
#        되찾지 않는다(오염 방지 가드).
#   어떤 경로에서도 force 미사용.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

# integration.sh 를 source (하단 BASH_SOURCE 가드로 main 미실행).
# shellcheck disable=SC1091
. "$HERE/../integration.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BRANCH="feat/20260723T000000-run638-feature"
REF_COMMIT="f"          # 로컬 브랜치 ref (stale)
WT_HEADS="f"            # 워크트리 HEAD 목록 (케이스별 설정)
REMOTE_TIP="f"          # 원격 작업 브랜치 tip (케이스별 설정)
MERGED=0                # 브랜치 ref 가 origin/main 에 포함되는가

# ---- mock git: 커밋 그래프를 조상 목록으로 모사 ----
#   f       ← 브랜치 ref
#   fplus1  ← 리뷰 델타(워크트리 HEAD), f 의 자손
#   unrelated ← 무관한 run 워크트리 HEAD, f 의 자손(머지 후 시나리오)
#   remotetip ← 원격이 정당하게 앞선 커밋, f 의 자손
PUSHLOG="$TMP/pushlog" GITLOG="$TMP/gitlog"
mock_anc() {   # mock_anc <commit> → 자기 자신 포함 조상 목록
  case "$1" in
    f)         echo "f" ;;
    fplus1)    echo "f fplus1" ;;
    fplus2)    echo "f fplus1 fplus2" ;;
    unrelated) echo "f unrelated" ;;
    remotetip) echo "f remotetip" ;;
    *)         echo "$1" ;;
  esac
}
mock_git() {
  if [[ "$1" == "-C" ]]; then shift 2; fi
  local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
  printf '%s\n' "$*" >> "$GITLOG"
  case "$1" in
    fetch) return 0 ;;
    ls-remote) [[ -n "$REMOTE_TIP" ]] && printf '%s\trefs/heads/%s\n' "$REMOTE_TIP" "$BRANCH"; return 0 ;;
    rev-parse)
      case "$*" in
        *refs/heads/*) printf '%s\n' "$REF_COMMIT"; return 0 ;;
        *) printf '%s\n' "$REF_COMMIT"; return 0 ;;
      esac ;;
    worktree)
      # `worktree list --porcelain` 형식(HEAD 줄만 소비된다).
      local h; for h in $WT_HEADS; do
        printf 'worktree %s/wt-%s\nHEAD %s\ndetached\n\n' "$TMP" "$h" "$h"
      done; return 0 ;;
    merge-base)
      local A="$3" B="$4"
      [[ "$A" == refs/heads/* ]] && A="$REF_COMMIT"
      [[ "$B" == refs/heads/* ]] && B="$REF_COMMIT"
      if [[ "$B" == "origin/main" ]]; then [[ "$MERGED" == "1" ]] && return 0 || return 1; fi
      printf '%s\n' "$(mock_anc "$B")" | tr ' ' '\n' | grep -Fxq "$A"; return $? ;;
    push) printf '%s\n' "$*" >> "$PUSHLOG"; return 0 ;;
  esac
  return 0
}
GIT_CMD=mock_git
DEFAULT_BRANCH=main

ERRLOG="$TMP/errlog"
run_case() { : > "$PUSHLOG"; : > "$GITLOG"; in_push_branch "$BRANCH" >/dev/null 2>"$ERRLOG"; }

# ---- A: 워크트리 델타 커밋이 원격에 없음 → 델타 커밋 직접 push ----
WT_HEADS="fplus1"; REMOTE_TIP="f"; MERGED=0
run_case
if grep -Fxq "push origin fplus1:refs/heads/$BRANCH" "$PUSHLOG"; then
  ok "A: stale ref 뒤의 워크트리 델타 커밋을 원격 작업 브랜치로 직접 push"
else
  bad "A: 워크트리 델타 커밋 push (pushlog: $(tr '\n' ';' < "$PUSHLOG"))"
fi

# ---- B: 원격이 이미 델타 커밋 포함 → 생략(run 592 불변) ----
WT_HEADS="fplus1"; REMOTE_TIP="fplus1"; MERGED=0
run_case
[[ ! -s "$PUSHLOG" ]] && ok "B: 원격이 통합 대상 커밋을 이미 포함 → push 생략" \
  || bad "B: 정당한 원격-앞섬 push 생략 (pushlog: $(tr '\n' ';' < "$PUSHLOG"))"

# ---- C: 워크트리 델타 없음 + 원격-앞섬 → 생략 ----
WT_HEADS="f"; REMOTE_TIP="remotetip"; MERGED=0
run_case
[[ ! -s "$PUSHLOG" ]] && ok "C: 델타 없음 + 원격-앞섬 → push 생략" \
  || bad "C: 델타 없음 + 원격-앞섬 push 생략 (pushlog: $(tr '\n' ';' < "$PUSHLOG"))"

# ---- D: 브랜치가 이미 origin/main 에 포함 → 무관 워크트리 커밋 되찾지 않음 ----
WT_HEADS="unrelated"; REMOTE_TIP="f"; MERGED=1
run_case
grep -q "unrelated" "$PUSHLOG" && bad "D: 머지된 브랜치에 무관 워크트리 커밋 push(오염)" \
  || ok "D: 머지된 브랜치는 워크트리 커밋 되찾지 않음(오염 방지)"
grep -qE "^fetch origin main" "$GITLOG" && ok "D2: 머지 가드 판정 전 base fetch(stale 가드 방지)" \
  || bad "D2: 머지 가드 판정 전 base fetch"

# ---- F: 자손 후보가 둘 이상 → 모호로 되찾지 않고 조용히 넘기지 않음(표면화) ----
WT_HEADS="fplus1 fplus2"; REMOTE_TIP="f"; MERGED=0
run_case
grep -qE "fplus1|fplus2" "$PUSHLOG" && bad "F: 모호한 후보를 임의 선택해 push" \
  || ok "F: 자손 후보 둘 이상 → 되찾지 않음(모호)"
grep -q "모호" "$ERRLOG" && ok "F2: 모호 생략을 stderr 로 표면화(조용한 재발 방지)" \
  || bad "F2: 모호 생략 표면화 (errlog: $(tr '\n' ';' < "$ERRLOG"))"

# ---- force 금지 ----
if grep -qiE 'force|(^| )-f( |$)' "$GITLOG"; then bad "E: force 미사용"; else ok "E: force 미사용"; fi

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || { echo "FAILURES present"; exit 1; }
