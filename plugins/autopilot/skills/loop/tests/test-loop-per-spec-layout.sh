#!/usr/bin/env bash
# test-loop-per-spec-layout.sh
#
# per-spec 디렉토리 레이아웃에서 loop 의 per-spec 아티팩트(워크트리·락·메타·신호)가
# 스펙 디렉토리 하위로 격리되는지 검증 (compute_paths 가 아티팩트 위치의 SoT).
#
# SPEC: spec/loop/dispatch per-spec directory layout 전환.
#   AC2 — loop 실행 아티팩트가 스펙의 docs/specs/<date>-<slug>/ 하위에 생성, 최상위 아님.
#   AC3 — 서로 다른 두 스펙의 락·워크트리가 각자 디렉토리에 격리(충돌·덮어쓰기 없음).
#   AC4 — 구 형식(<date>-<slug>.md)·신 형식(<date>-<slug>/SPEC.md) 경로 모두 해석.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_SH="$SCRIPT_DIR/../references/loop.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git 미설치"; exit 0; }

# loop.sh source — dispatcher 는 BASH_SOURCE guard 로 비실행.
# shellcheck source=../references/loop.sh
source "$LOOP_SH"
set +e

fail=0
chk() {
  local label="$1" got="$2" exp="$3"
  if [[ "$got" == "$exp" ]]; then
    echo "PASS  $label"
  else
    echo "FAIL  $label  got='$got' exp='$exp'"
    fail=1
  fi
}
chk_ne() {
  local label="$1" a="$2" b="$3"
  if [[ "$a" != "$b" ]]; then
    echo "PASS  $label"
  else
    echo "FAIL  $label  두 값이 같음='$a'"
    fail=1
  fi
}

REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
git -C "$REPO" commit --allow-empty -qm init

SPECS="$REPO/docs/specs"
mkdir -p "$SPECS/2026-05-30-foo" "$SPECS/2026-05-30-bar"
printf -- '---\n---\n# foo\n' > "$SPECS/2026-05-30-foo/SPEC.md"
printf -- '---\n---\n# bar\n' > "$SPECS/2026-05-30-bar/SPEC.md"
printf -- '---\n---\n# old\n' > "$SPECS/2026-05-30-old.md"

# ---- 신 형식 foo ----
compute_paths "$SPECS/2026-05-30-foo/SPEC.md"
foo_specdir="$SPEC_DIR"; foo_wt="$WT"; foo_lock="$LOCK_FILE"; foo_loop="$LOOP_DIR"

chk "AC2 foo SPEC_DIR=per-spec 디렉토리" "$foo_specdir" "$SPECS/2026-05-30-foo"
chk "AC2 foo WT 하위" "$foo_wt" "$SPECS/2026-05-30-foo/.worktree"
chk "AC2 foo LOCK 하위" "$foo_lock" "$SPECS/2026-05-30-foo/.loop-lock"
chk "AC2 foo LOOP_DIR 하위" "$foo_loop" "$SPECS/2026-05-30-foo/.worktree/.loop"
chk_ne "AC2 foo LOCK 가 docs/specs 최상위 아님" "$foo_lock" "$SPECS/.loop-lock"

# ---- 신 형식 bar ----
compute_paths "$SPECS/2026-05-30-bar/SPEC.md"
bar_specdir="$SPEC_DIR"; bar_wt="$WT"; bar_lock="$LOCK_FILE"

chk "AC2 bar SPEC_DIR=per-spec 디렉토리" "$bar_specdir" "$SPECS/2026-05-30-bar"
chk_ne "AC3 foo·bar LOCK 격리" "$foo_lock" "$bar_lock"
chk_ne "AC3 foo·bar WT 격리" "$foo_wt" "$bar_wt"

# ---- 구 형식 old (호환) ----
compute_paths "$SPECS/2026-05-30-old.md"
chk "AC4 구 형식 SPEC_DIR=docs/specs (보존)" "$SPEC_DIR" "$SPECS"
chk "AC4 구 형식 WT" "$WT" "$SPECS/.worktree"
chk "AC4 구 형식 LOCK" "$LOCK_FILE" "$SPECS/.loop-lock"

if [[ $fail -ne 0 ]]; then
  echo "FAIL: 일부 case 실패 — per-spec layout 격리"
  exit 1
fi
echo "PASS: per-spec layout 아티팩트 격리 (AC2/AC3/AC4)"
