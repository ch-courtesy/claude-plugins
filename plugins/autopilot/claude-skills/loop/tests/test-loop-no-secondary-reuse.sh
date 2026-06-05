#!/usr/bin/env bash
# test-loop-no-secondary-reuse.sh
#
# SPEC: loop-no-secondary-worktree-reuse.
# loop 은 호출 위치와 무관하게 항상 <SPEC_DIR>/.worktree 전용 워크트리를 새로 만든다.
# 보조(secondary) git 워크트리 안에서 호출돼도 그 enclosing 워크트리를 재사용하지 않는다.
#
# Case:
#   N1 보조 worktree 안에서 prepare_workspace → WT == <SPEC_DIR>/.worktree (enclosing 재사용 금지)
#   N2 생성된 .worktree 가 실제 등록된 git 워크트리 (HEAD 해석 가능)
#   N3 .loop-wt 메타 == <SPEC_DIR>/.worktree (보조 top-level 아님)
#   N4 전용 워크트리 생성 실패 시 abort (0 이 아닌 코드)
#   N5 보조 재사용 헬퍼(is_secondary_worktree / apply_secondary_override) 제거됨 — 재도입 가드
#   N6 cleanup 은 생성 워크트리를 제거한다 (보조라는 이유로 보존하지 않음)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOP_SH="$SCRIPT_DIR/../references/loop.sh"

command -v git >/dev/null 2>&1 || { echo "SKIP: git 미설치"; exit 0; }

# loop.sh source — dispatcher 는 BASH_SOURCE guard 로 비실행.
# shellcheck source=../references/loop.sh
source "$LOOP_SH"
set +e   # loop.sh 의 errexit 해제

fail=0
chk() {
  local label="$1" cond="$2"
  if [[ "$cond" == "1" ]]; then echo "PASS  $label"; else echo "FAIL  $label"; fail=1; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fresh git repo + 보조(secondary) worktree
git init -q "$TMP"
( cd "$TMP" && touch .gitkeep && git add .gitkeep && \
  git -c user.email=t@t -c user.name=t commit -q -m init )
MAIN="$TMP"
SEC="$TMP/.secondary"
git -C "$MAIN" worktree add --detach "$SEC" HEAD >/dev/null 2>&1

# SPEC 디렉토리를 보조 worktree 안에 둔다 (enclosing 워크트리 안).
SPEC_DIR_S="$SEC/docs/specs/2026-06-05-x"
mkdir -p "$SPEC_DIR_S"
printf -- '---\nscope: {include: ["**"]}\n---\n# x\n' > "$SPEC_DIR_S/SPEC.md"

# ---- N1/N2/N3: 보조 worktree 안 SPEC 에서 prepare_workspace 가 전용 워크트리를 만든다 ----
# prepare_workspace 는 절대경로(git -C)만 사용 → cwd 비의존. 직접 호출해 globals 검사.
compute_paths "$SPEC_DIR_S/SPEC.md"
SPEC_PATH="$SPEC_DIR_S/SPEC.md"
prepare_workspace >/dev/null 2>&1

[[ "$WT" == "$SPEC_DIR_S/.worktree" ]] && chk "N1 WT==전용 .worktree (enclosing 재사용 금지)" 1 || chk "N1 WT==전용 .worktree (got: $WT)" 0
[[ "$WT" != "$SEC" ]] && chk "N1b WT != 보조 top-level" 1 || chk "N1b WT != 보조 top-level" 0

# N2: 등록된 git 워크트리인지 — HEAD 해석 가능 + .git 파일 존재
if git -C "$WT" rev-parse HEAD >/dev/null 2>&1 && [[ -e "$WT/.git" ]]; then
  chk "N2 .worktree 가 실제 등록 워크트리" 1
else
  chk "N2 .worktree 가 실제 등록 워크트리" 0
fi

# N3: 메타가 전용 워크트리를 가리킴
meta=""
[[ -f "$SPEC_DIR_S/.loop-wt" ]] && IFS= read -r meta < "$SPEC_DIR_S/.loop-wt"
[[ "$meta" == "$SPEC_DIR_S/.worktree" ]] && chk "N3 .loop-wt 메타==전용 .worktree" 1 || chk "N3 .loop-wt 메타==전용 .worktree (got: $meta)" 0

# ---- N4: 전용 워크트리 생성 실패 시 abort ----
SPEC_DIR_F="$MAIN/docs/specs/2026-06-05-fail"
mkdir -p "$SPEC_DIR_F"
printf -- '---\nscope: {include: ["**"]}\n---\n# f\n' > "$SPEC_DIR_F/SPEC.md"
# .worktree 경로를 일반 파일로 선점 → git worktree add 실패 유도.
: > "$SPEC_DIR_F/.worktree"
rc=0
(
  compute_paths "$SPEC_DIR_F/SPEC.md"
  SPEC_PATH="$SPEC_DIR_F/SPEC.md"
  prepare_workspace
) >/dev/null 2>&1
rc=$?
[[ "$rc" -ne 0 ]] && chk "N4 생성 실패 시 abort (rc=$rc)" 1 || chk "N4 생성 실패 시 abort (rc=$rc)" 0

# ---- N5: 보조 재사용 헬퍼 제거됨 (재도입 가드) ----
if declare -F is_secondary_worktree >/dev/null 2>&1 || declare -F apply_secondary_override >/dev/null 2>&1; then
  chk "N5 보조 재사용 헬퍼 제거됨" 0
else
  chk "N5 보조 재사용 헬퍼 제거됨" 1
fi

# ---- N6: cleanup 은 생성 워크트리를 제거(보존하지 않음) ----
# N1 에서 만든 SPEC_DIR_S/.worktree 를 terminal 후 정리.
mkdir -p "$SPEC_DIR_S/.worktree/.loop/signals"
touch "$SPEC_DIR_S/.worktree/.loop/signals/DONE"
( cd "$SEC" && bash "$LOOP_SH" cleanup "$SPEC_DIR_S/SPEC.md" >/dev/null 2>&1 )
if [[ ! -d "$SPEC_DIR_S/.worktree" && ! -f "$SPEC_DIR_S/.loop-wt" ]]; then
  chk "N6 cleanup 이 생성 워크트리 제거" 1
else
  chk "N6 cleanup 이 생성 워크트리 제거 (.worktree=$(test -d "$SPEC_DIR_S/.worktree" && echo 잔존 || echo OK))" 0
fi

if [[ $fail -ne 0 ]]; then
  echo "FAIL: 일부 case 실패 — no-secondary-reuse"
  exit 1
fi
echo "PASS: no-secondary-reuse 모든 case"
