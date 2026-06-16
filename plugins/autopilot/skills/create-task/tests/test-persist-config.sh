#!/usr/bin/env bash
# test-persist-config.sh — create-task 백엔드 config 영속화 헬퍼 계약 검증.
#   - 멱등성: 메인에 동일 config가 추적되면 skip(새 커밋 없음).
#   - config-only: 영속화 커밋 diff에 .autopilot/task-backend.json 만 포함.
#   - 워킹트리에 다른 변경이 있어도 config 커밋엔 섞이지 않음.
# origin 없는 로컬(direct) repo 로 전 경로를 결정적으로 검증한다.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H="$HERE/../persist-backend-config.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

mkrepo() {
  local d="$1"
  rm -rf "$d"; mkdir -p "$d"
  ( cd "$d" && git init -q -b main && git config user.email t@t && git config user.name t \
      && echo seed > README.md && git add README.md && git commit -qm seed )
}

CFG='{"backend":"github-project","lease_ttl_seconds":300}'

# --- 시나리오 1: 미설정 → 영속화, config-only, 메인 추적 ---
R1="$(mktemp -d)/r"; mkrepo "$R1"
mkdir -p "$R1/.autopilot"; printf '%s\n' "$CFG" > "$R1/.autopilot/task-backend.json"
out1="$(cd "$R1" && bash "$H" 2>/dev/null)" || bad "persist exit code"
chk "1: status persisted" "$(printf '%s' "$out1" | jq -r .status)" "persisted"
# 메인(HEAD) 에 추적 파일로 존재
chk "1: 메인 추적됨" "$(cd "$R1" && git show HEAD:.autopilot/task-backend.json >/dev/null 2>&1 && echo yes || echo no)" "yes"
# 영속화 커밋 diff 는 config 파일만
pcommit="$(cd "$R1" && git log --all --diff-filter=A --format=%H -- .autopilot/task-backend.json | head -1)"
files="$(cd "$R1" && git show --name-only --format= "$pcommit" | grep -v '^$' | sort | tr '\n' ' ')"
chk "1: config-only diff" "$files" ".autopilot/task-backend.json "

# --- 시나리오 2: 멱등 재실행 → skip, 새 커밋 없음 ---
before="$(cd "$R1" && git rev-list --all --count)"
out2="$(cd "$R1" && bash "$H" 2>/dev/null)" || bad "persist re-run exit code"
chk "2: status skip" "$(printf '%s' "$out2" | jq -r .status)" "skip"
after="$(cd "$R1" && git rev-list --all --count)"
chk "2: 커밋수 불변(멱등)" "$before" "$after"

# --- 시나리오 3: 워킹트리 다른 변경 존재 → config 커밋에 미혼입 ---
R3="$(mktemp -d)/r"; mkrepo "$R3"
mkdir -p "$R3/.autopilot"; printf '%s\n' "$CFG" > "$R3/.autopilot/task-backend.json"
echo "dirty change" >> "$R3/README.md"          # 추적 파일 수정
echo "scratch" > "$R3/other.txt"                  # 미추적 파일
( cd "$R3" && bash "$H" >/dev/null 2>&1 ) || bad "3: persist exit"
pcommit3="$(cd "$R3" && git log --all --diff-filter=A --format=%H -- .autopilot/task-backend.json | head -1)"
files3="$(cd "$R3" && git show --name-only --format= "$pcommit3" | grep -v '^$' | sort | tr '\n' ' ')"
chk "3: 더티 트리에도 config-only" "$files3" ".autopilot/task-backend.json "

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || { echo "FAILURES present"; exit 1; }
