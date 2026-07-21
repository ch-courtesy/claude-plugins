#!/usr/bin/env bash
# test-integration-stale-branch.sh — stale 로컬 작업 브랜치 재사용 회귀 가드 (task 605 관측).
#   시나리오: 재실행 시 동명의 로컬 작업 브랜치가 남아 있는데, 그 브랜치가 loop 의 최신 결과
#   커밋을 조상으로 포함하지 않는다(낡은 시도의 커밋).
#   기대: 통합이 stale 브랜치를 조용히 재사용해 push 하지 않고 불일치를 표면화(차단)한다.
#     - 루프 결과 커밋이 유실되지 않는다(낡은 커밋 push·PR 미수행).
#     - 브랜치가 결과 커밋을 이미 담고 있으면 기존대로 멱등 통과.
#     - 어떤 경로에서도 force 미사용.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

# integration.sh 를 source (하단 BASH_SOURCE 가드로 main 미실행).
# shellcheck disable=SC1091
. "$HERE/../integration.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
RD="$TMP/.autopilot/runs/20260721T000000-run605"; mkdir -p "$RD"
SPEC="$TMP/SPEC.md"
printf '# stale branch feature x\n\n## 무엇\n...\n' > "$SPEC"
BRANCH="feat/20260721T000000-run605-stale-branch-feature-x"

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

# ---- mock git ----
#   로컬 브랜치 존재(tip=stalecommit) / loop 결과 커밋 = resultcommit.
#   ANCESTOR: 브랜치가 결과 커밋을 포함하는가(1=stale, 0=포함) — 케이스별 토글.
GITLOG="$TMP/gitlog" PUSHLOG="$TMP/pushlog" BRANCHES="$TMP/branches"
: > "$GITLOG"; : > "$PUSHLOG"; printf '%s\n' "$BRANCH" > "$BRANCHES"
ANCESTOR=1
mock_git() {
  if [[ "$1" == "-C" ]]; then shift 2; fi
  local a; for a in "$@"; do case "$a" in *force*|-f) echo "FORCE USED" >&2; exit 99;; esac; done
  printf '%s\n' "$*" >> "$GITLOG"
  case "$1" in
    fetch|rebase|worktree) return 0 ;;
    ls-remote) return 0 ;;   # 원격 브랜치 미존재(원격을 지워도 재현 — SPEC 재현 맥락).
    rev-parse)
      case "$*" in
        *--verify*refs/heads/*) grep -Fxq "$BRANCH" "$BRANCHES" 2>/dev/null; return $? ;;
        *--absolute-git-dir*) printf '%s/gitdir\n' "$TMP"; return 0 ;;
        *refs/heads/*) grep -Fxq "$BRANCH" "$BRANCHES" 2>/dev/null && { echo "stalecommit"; return 0; } || return 1 ;;
        *HEAD*) echo "resultcommit"; return 0 ;;
      esac ;;
    merge-base)
      # --is-ancestor <A> <B>: A 가 B 의 조상인가.
      case "$*" in
        *"resultcommit refs/heads/"*) return "$ANCESTOR" ;;  # 결과 커밋 ⊂ 브랜치?
        *"origin/main"*)              return 0 ;;            # base 는 브랜치 조상(동기화 불필요).
        *) return 1 ;;
      esac ;;
    branch) printf '%s\n' "$2" >> "$BRANCHES"; return 0 ;;
    push) printf '%s\n' "$*" >> "$PUSHLOG"; return 0 ;;
  esac
  return 0
}
GIT_CMD=mock_git

# ---- mock forge ----
PRLOG="$TMP/prlog"; : > "$PRLOG"
mock_forge() {
  case "$1 $2" in
    "pr list")   : ;;                                        # open PR 없음.
    "pr create") printf '%s\n' "$*" >> "$PRLOG"; echo created ;;
  esac
  return 0
}
FORGE_CMD=mock_forge
DEFAULT_BRANCH=main

# ---- 케이스 A: stale 브랜치(결과 커밋 미포함) → 차단·표면화, 유실 없음 ----
ANCESTOR=1
rc=0; err="$(in_integrate "$SPEC" "$RD" "run605-key" 2>&1 >/dev/null)" || rc=$?
chk "A1: stale 브랜치 → integrate 차단(rc=4)" "$rc" "4"
chk "A2: phase=blocked" "$(int_get_phase "$RD" "run605-key")" "blocked"
[[ ! -s "$PUSHLOG" ]] && ok "A3: 낡은 브랜치 push 안 함(결과 커밋 유실 방지)" || bad "A3: 낡은 브랜치 push 안 함 (pushlog: $(tr '\n' ';' < "$PUSHLOG"))"
[[ ! -s "$PRLOG" ]] && ok "A4: PR 미생성" || bad "A4: PR 미생성"
printf '%s' "$err" | grep -q "resultcommit" && ok "A5: 불일치 표면화(결과 커밋 명시)" || bad "A5: 불일치 표면화(결과 커밋 명시) (err: $err)"

# ---- 케이스 B: 브랜치가 결과 커밋 포함 → 기존대로 멱등 통과 ----
ANCESTOR=0
rc=0; in_ensure_work_branch "$BRANCH" "$SPEC" 2>/dev/null || rc=$?
chk "B1: 결과 커밋 포함 브랜치 → 멱등 통과(rc=0)" "$rc" "0"

# ---- 케이스 C: 브랜치 미존재 → 결과 커밋에서 생성(기존 동작) ----
printf '' > "$BRANCHES"
rc=0; in_ensure_work_branch "$BRANCH" "$SPEC" 2>/dev/null || rc=$?
chk "C1: 브랜치 미존재 → 생성(rc=0)" "$rc" "0"
grep -Fxq "$BRANCH" "$BRANCHES" && ok "C2: 결과 커밋에서 브랜치 생성" || bad "C2: 결과 커밋에서 브랜치 생성"

# ---- 케이스 E: 결과 커밋 미판독(loop 워크트리 이상) + 브랜치 존재 → 조용한 통과 아님(차단) ----
#   terminal=done 은 loop 워크트리 존재를 전제하므로 미판독은 정상 재진입이 아니라 이상.
printf '%s\n' "$BRANCH" > "$BRANCHES"
mock_loop_nowt() {
  case "$1" in
    status) printf '{"state":"terminal","signals":["DONE"]}\n' ;;
    paths)  : ;;   # WT 경로 미제공 — 결과 커밋 판독 불가.
    *) : ;;
  esac
}
LOOP_CMD=mock_loop_nowt
rc=0; in_ensure_work_branch "$BRANCH" "$SPEC" 2>/dev/null || rc=$?
[[ "$rc" != "0" ]] && ok "E1: 결과 커밋 미판독 → 조용한 통과 아님(rc!=0)" || bad "E1: 결과 커밋 미판독 → 조용한 통과 아님(rc!=0)"
LOOP_CMD=mock_loop

# ---- 공통: force 미사용 ----
if grep -qiE 'force|(^| )-f( |$)' "$GITLOG"; then bad "D1: force 미사용"; else ok "D1: force 미사용"; fi

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || { echo "FAILURES present"; exit 1; }
