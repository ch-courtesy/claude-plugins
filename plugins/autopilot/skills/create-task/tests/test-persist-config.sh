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

# ----- origin 경로(github): gh 스텁 + bare-repo origin 으로 결정적 검증 -----
mkrepo_origin() {  # <worktree> <bare-origin>
  local d="$1" bare="$2"
  rm -rf "$d" "$bare"; mkdir -p "$d"
  git init -q --bare "$bare"
  ( cd "$d" && git init -q -b main && git config user.email t@t && git config user.name t \
      && echo seed > README.md && git add README.md && git commit -qm seed \
      && git remote add origin "$bare" && git push -q origin main && git remote set-head origin main )
}
# gh 스텁 생성: $1=create결과(url), $2=merge성공여부(0/1)
mkstub_gh() {  # <path> <merge_rc>
  cat > "$1" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr create") echo "https://example.test/pr/1"; exit 0;;
  "pr view")   echo "https://example.test/pr/1"; exit 0;;
  "pr merge")  exit $2;;
esac
exit 0
EOF
  chmod +x "$1"
}

# --- 시나리오 4: origin 있음 + gh 미가용 → pending, exit 3 (조용한 persisted 금지) ---
R4="$(mktemp -d)"; mkrepo_origin "$R4/r" "$R4/origin.git"
mkdir -p "$R4/r/.autopilot"; printf '%s\n' "$CFG" > "$R4/r/.autopilot/task-backend.json"
rc4=0; out4="$(cd "$R4/r" && PBC_GH="$R4/no-such-gh" bash "$H" 2>/dev/null)" || rc4=$?
chk "4: gh 미가용 status pending" "$(printf '%s' "$out4" | jq -r .status)" "pending"
chk "4: gh 미가용 exit 3" "$rc4" "3"

# --- 시나리오 5: gh 있음 + pr merge 실패 → pr_created, exit 3 (persisted 아님) ---
R5="$(mktemp -d)"; mkrepo_origin "$R5/r" "$R5/origin.git"
mkdir -p "$R5/r/.autopilot"; printf '%s\n' "$CFG" > "$R5/r/.autopilot/task-backend.json"
mkstub_gh "$R5/gh" 1
rc5=0; out5="$(cd "$R5/r" && PBC_GH="$R5/gh" bash "$H" 2>/dev/null)" || rc5=$?
chk "5: 머지 실패 status pr_created" "$(printf '%s' "$out5" | jq -r .status)" "pr_created"
chk "5: 머지 실패 exit 3" "$rc5" "3"
chk "5: 브랜치는 origin 에 push됨" "$(cd "$R5/origin.git" && git rev-parse --verify --quiet refs/heads/chore/persist-task-backend-config >/dev/null && echo yes || echo no)" "yes"

# --- 시나리오 6: gh 있음 + merge(예약) 성공 → persisted, exit 0 ---
R6="$(mktemp -d)"; mkrepo_origin "$R6/r" "$R6/origin.git"
mkdir -p "$R6/r/.autopilot"; printf '%s\n' "$CFG" > "$R6/r/.autopilot/task-backend.json"
mkstub_gh "$R6/gh" 0
rc6=0; out6="$(cd "$R6/r" && PBC_GH="$R6/gh" bash "$H" 2>/dev/null)" || rc6=$?
chk "6: 머지 성공 status persisted" "$(printf '%s' "$out6" | jq -r .status)" "persisted"
chk "6: 머지 성공 exit 0" "$rc6" "0"

# --- 시나리오 7: gh 있음 + PR 생성·조회 모두 실패(빈 PR_URL) → pending(pr_created 아님), exit 3 ---
R7="$(mktemp -d)"; mkrepo_origin "$R7/r" "$R7/origin.git"
mkdir -p "$R7/r/.autopilot"; printf '%s\n' "$CFG" > "$R7/r/.autopilot/task-backend.json"
cat > "$R7/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "pr create") exit 1;;   # 생성 실패
  "pr view")   exit 1;;   # 조회도 실패 → PR_URL 빈 값
  "pr merge")  exit 0;;
esac
exit 0
EOF
chmod +x "$R7/gh"
rc7=0; out7="$(cd "$R7/r" && PBC_GH="$R7/gh" bash "$H" 2>/dev/null)" || rc7=$?
chk "7: PR 생성 실패 status pending" "$(printf '%s' "$out7" | jq -r .status)" "pending"
chk "7: PR 생성 실패 exit 3" "$rc7" "3"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || { echo "FAILURES present"; exit 1; }
