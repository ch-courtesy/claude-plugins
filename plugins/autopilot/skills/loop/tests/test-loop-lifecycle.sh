#!/usr/bin/env bash
# test-loop-lifecycle.sh
#
# cross-cwd × {primary, secondary} × {status, logs, cleanup} 매트릭스 회귀 가드.
# PR #230 R1·R2 codex blocking finding(보조 worktree follow-up 명령 정합) 영구 차단.
#
# 8 case:
#   L1 primary fab + status from main cwd
#   L2 primary fab + logs from main cwd
#   L3 secondary fab + status from secondary cwd (same-cwd)
#   L4 secondary fab + status from main cwd (cross-cwd, codex 핵심)
#   L5 secondary fab + logs from main cwd (cross-cwd)
#   L6 cleanup 이 전용 워크트리 제거 (spec 이 보조 worktree 안이어도 — no-secondary-reuse)
#   L7 legacy (no .loop-wt) + status fallback
#   L8 empty .loop-wt + status fallback

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_SH="$SCRIPT_DIR/../references/loop.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git 미설치"; exit 0; }
command -v yq  >/dev/null 2>&1 || { echo "SKIP: yq 미설치"; exit 0; }

fail=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fresh git repo + secondary worktree (detached)
git init -q "$TMP"
( cd "$TMP" && touch .gitkeep && git add .gitkeep && \
  git -c user.email=t@t -c user.name=t commit -q -m init )
MAIN="$TMP"
SEC="$TMP/.secondary"
git -C "$MAIN" worktree add --detach "$SEC" HEAD >/dev/null 2>&1

# spec + workspace fab
fab_run() {
  local spec_dir="$1" wt_path="$2"
  mkdir -p "$spec_dir"
  printf -- '---\nscope: {include: ["**"]}\n---\n# t\n' > "$spec_dir/spec.md"
  mkdir -p "$wt_path/.loop/signals" "$wt_path/.loop/iterations"
  printf '%s\n' "$spec_dir/spec.md" > "$wt_path/.loop/SPEC_PATH"
  echo log > "$wt_path/.loop/iterations/1.log"
  touch "$wt_path/.loop/signals/DONE"
  printf '%s\n' "$wt_path" > "$spec_dir/.loop-wt"
}

check_contains() {
  local label="$1" expected="$2" got="$3"
  if [[ "$got" == *"$expected"* ]]; then
    echo "PASS  $label"
  else
    echo "FAIL  $label  expected substring '$expected' in: $got"
    fail=1
  fi
}

# L1: Primary fab + status from main cwd
SPEC_DIR_P="$MAIN/p1"
fab_run "$SPEC_DIR_P" "$SPEC_DIR_P/.worktree"
out=$( cd "$MAIN" && bash "$LOOP_SH" status "$SPEC_DIR_P/spec.md" | tail -1 )
check_contains "L1 primary status" "terminal" "$out"

# L2: Primary + logs from main cwd
out=$( cd "$MAIN" && bash "$LOOP_SH" logs "$SPEC_DIR_P/spec.md" 2>&1 | grep -F 'signals/' | head -1 )
check_contains "L2 primary logs" "signals/DONE" "$out"

# L3: Secondary fab + status from secondary cwd
SPEC_DIR_S="$MAIN/s1"
fab_run "$SPEC_DIR_S" "$SEC"
out=$( cd "$SEC" && bash "$LOOP_SH" status "$SPEC_DIR_S/spec.md" | tail -1 )
check_contains "L3 secondary status same-cwd" "terminal" "$out"

# L4: Secondary + status from main cwd (cross-cwd — codex 핵심)
out=$( cd "$MAIN" && bash "$LOOP_SH" status "$SPEC_DIR_S/spec.md" | tail -1 )
check_contains "L4 secondary status cross-cwd" "terminal" "$out"

# L5: Secondary + logs from main cwd (cross-cwd)
out=$( cd "$MAIN" && bash "$LOOP_SH" logs "$SPEC_DIR_S/spec.md" 2>&1 | grep -F 'signals/' | head -1 )
check_contains "L5 secondary logs cross-cwd" "signals/DONE" "$out"

# L6: cleanup 은 항상 자신의 전용 워크트리를 제거한다 (보조라는 이유로 보존하지 않음).
#     SPEC 디렉토리가 보조 worktree(SEC) 안에 있어도, loop 의 전용 워크트리는
#     <SPEC_DIR>/.worktree(중첩) 이며 cleanup 이 이를 제거한다 (no-secondary-reuse).
SPEC_DIR_D="$SEC/d1"
mkdir -p "$SPEC_DIR_D"
printf -- '---\nscope: {include: ["**"]}\n---\n# t\n' > "$SPEC_DIR_D/spec.md"
git -C "$MAIN" worktree add --detach "$SPEC_DIR_D/.worktree" HEAD >/dev/null 2>&1
# prepare_workspace 와 동일하게 .loop/·.worktree/ 를 공통 git dir info/exclude 에 등록
# (ignored → untracked 아님 → git worktree remove 가 --force 없이 성공; 실제 start 동작).
gcd_d="$(git -C "$SPEC_DIR_D/.worktree" rev-parse --git-common-dir)"
[[ "$gcd_d" != /* ]] && gcd_d="$SPEC_DIR_D/.worktree/$gcd_d"
mkdir -p "$gcd_d/info"
for p in "CLAUDE.md" ".worktree/" ".loop/" ".loop-lock" ".loop-wt"; do
  grep -qxF "$p" "$gcd_d/info/exclude" 2>/dev/null || echo "$p" >> "$gcd_d/info/exclude"
done
mkdir -p "$SPEC_DIR_D/.worktree/.loop/signals"
touch "$SPEC_DIR_D/.worktree/.loop/signals/DONE"
printf '%s\n' "$SPEC_DIR_D/.worktree" > "$SPEC_DIR_D/.loop-wt"
( cd "$MAIN" && bash "$LOOP_SH" cleanup "$SPEC_DIR_D/spec.md" >/dev/null 2>&1 )
if [[ ! -d "$SPEC_DIR_D/.worktree" && ! -f "$SPEC_DIR_D/.loop-wt" ]]; then
  echo "PASS  L6 cleanup 이 전용 워크트리 제거 (spec in secondary)"
else
  echo "FAIL  L6 cleanup 이 전용 워크트리 제거  — worktree=$(test -d "$SPEC_DIR_D/.worktree" && echo 잔존 || echo OK), meta=$(test -f "$SPEC_DIR_D/.loop-wt" && echo 잔존 || echo OK)"
  fail=1
fi

# L7: Legacy (no .loop-wt) + status fallback
SPEC_DIR_L="$MAIN/legacy"
mkdir -p "$SPEC_DIR_L/.worktree/.loop/signals"
printf -- '---\nscope: {include: ["**"]}\n---\n# t\n' > "$SPEC_DIR_L/spec.md"
touch "$SPEC_DIR_L/.worktree/.loop/signals/DONE"
out=$( cd "$MAIN" && bash "$LOOP_SH" status "$SPEC_DIR_L/spec.md" | tail -1 )
check_contains "L7 legacy status (no .loop-wt)" "terminal" "$out"

# L8: Empty .loop-wt → fallback to default path
SPEC_DIR_E="$MAIN/empty_meta"
mkdir -p "$SPEC_DIR_E/.worktree/.loop/signals"
printf -- '---\nscope: {include: ["**"]}\n---\n# t\n' > "$SPEC_DIR_E/spec.md"
touch "$SPEC_DIR_E/.worktree/.loop/signals/DONE"
: > "$SPEC_DIR_E/.loop-wt"   # 빈 메타
out=$( cd "$MAIN" && bash "$LOOP_SH" status "$SPEC_DIR_E/spec.md" | tail -1 )
check_contains "L8 empty .loop-wt fallback" "terminal" "$out"

if [[ $fail -ne 0 ]]; then
  echo "FAIL: 일부 case 실패 — lifecycle"
  exit 1
fi
echo "PASS: lifecycle 매트릭스 모든 case (8건)"
