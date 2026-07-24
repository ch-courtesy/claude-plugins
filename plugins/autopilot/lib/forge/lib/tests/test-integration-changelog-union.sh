#!/usr/bin/env bash
# test-integration-changelog-union.sh — 재동기화 자율 해소의 누적 계약 파일 양쪽 보존 (run 648).
#   시나리오: PR 이 열린 동안 base(main)가 CHANGELOG 최상단에 새 섹션을 추가해 재동기화
#   merge-in/rebase 가 충돌. 기존 구현은 파일 단위 한쪽 채택(checkout --ours/--theirs)이라
#   다른 쪽 섹션을 통째로 삭제한 결과를 만들었다(run 635 관측).
#   기대: 누적 계약 파일(INT_CHANGELOG_FILE, 기본 CHANGELOG.md)은 union 병합으로 양쪽 항목을
#   모두 보존하고, 그 결과가 base 쪽 라인을 하나라도 잃으면 커밋 전에 중단(rc!=0)한다.
#   일반 충돌 파일과 게이트 비활성(빈 값)은 기존 전략 동작 그대로(후방 호환).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

# shellcheck disable=SC1091
. "$HERE/../integration.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
DEFAULT_BRANCH=main
BRANCH=feat/x

# mk_repo <dir> [drop-old]  — main 에 CHANGELOG 기존 섹션, 브랜치·main 이 각각 최상단에 섹션 추가.
#   drop-old=1 이면 브랜치가 기존 섹션 라인을 함께 삭제한다(양쪽 보존 불가 = 손실 시나리오).
mk_repo() {
  local r="$1" drop="${2:-0}"
  mkdir -p "$r"; git -C "$r" init -q -b main
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  cat > "$r/CHANGELOG.md" <<'EOF'
# Changelog

## pkg 0.1.0

### 버그 수정
- 기존 항목 A
- 기존 항목 A2
- 기존 항목 A3
- 기존 항목 A4
EOF
  echo base > "$r/f.txt"
  git -C "$r" add -A; git -C "$r" commit -qm base

  git -C "$r" checkout -qb "$BRANCH"
  awk 'NR==2{print ""; print "## pkg 0.2.0"; print ""; print "### 기능"; print "- 브랜치 항목 B"} {print}' \
    "$r/CHANGELOG.md" > "$r/c.new"
  if [[ "$drop" == "1" ]]; then grep -v '^- 기존 항목 A4$' "$r/c.new" > "$r/c2" && mv "$r/c2" "$r/c.new"; fi
  mv "$r/c.new" "$r/CHANGELOG.md"
  echo branch > "$r/f.txt"
  git -C "$r" commit -aqm 'branch entry'

  git -C "$r" checkout -q main
  awk 'NR==2{print ""; print "## pkg 0.3.0"; print ""; print "### 기능"; print "- main 항목 C"} {print}' \
    "$r/CHANGELOG.md" > "$r/c.new" && mv "$r/c.new" "$r/CHANGELOG.md"
  echo mainside > "$r/f.txt"
  git -C "$r" commit -aqm 'main entry'
  git -C "$r" checkout -q "$BRANCH"
}

# main 쪽 CHANGELOG 라인 중 결과 파일에서 사라진 라인 수.
lost_lines() {
  local r="$1"
  git -C "$r" show "main:CHANGELOG.md" > "$r/.mainver"
  diff "$r/.mainver" "$r/CHANGELOG.md" | grep -c '^<' || true
}

# ---- 케이스 1: merge-in 재동기화 — 양쪽 보존 ----
R="$TMP/merge"; mk_repo "$R"
GIT_CMD="git -C $R"
git -C "$R" merge --no-commit --no-ff main >/dev/null 2>&1
rc=0; in_autoresolve_merge "$BRANCH" >/dev/null 2>&1 || rc=$?
chk "1: merge-in 자율 해소 rc=0" "$rc" "0"
grep -q '브랜치 항목 B' "$R/CHANGELOG.md" && ok "2: 브랜치 섹션 보존" || bad "2: 브랜치 섹션 보존"
grep -q 'main 항목 C' "$R/CHANGELOG.md" && ok "3: base(main) 섹션 보존" || bad "3: base(main) 섹션 보존"
grep -q '<<<<<<<\|>>>>>>>' "$R/CHANGELOG.md" && bad "4: 충돌 마커 없음" || ok "4: 충돌 마커 없음"
chk "5: base 대비 삭제 라인 0" "$(lost_lines "$R")" "0"
chk "6: 충돌 미해소 파일 없음" "$(git -C "$R" diff --name-only --diff-filter=U | wc -l | tr -d ' ')" "0"
chk "7: 일반 파일은 기존 전략(incoming=--ours=브랜치 쪽) 유지" "$(cat "$R/f.txt")" "branch"

# ---- 케이스 2: 양쪽 보존 실패(손실) → 커밋 전 중단 ----
R2="$TMP/lossy"; mk_repo "$R2" 1
GIT_CMD="git -C $R2"
git -C "$R2" merge --no-commit --no-ff main >/dev/null 2>&1
err="$(in_autoresolve_merge "$BRANCH" 2>&1)" && rc=0 || rc=$?
[[ "$rc" -ne 0 ]] && ok "8: 손실 해소는 실패(rc!=0) — 커밋·push 없음" || bad "8: 손실 해소는 실패(rc!=0)"
[[ -n "$err" ]] && ok "9: 중단 사유 출력" || bad "9: 중단 사유 출력"
[[ -e "$R2/.git/MERGE_HEAD" ]] && bad "10: 머지 중단(abort)됨" || ok "10: 머지 중단(abort)됨"

# ---- 케이스 3: 게이트 비활성(INT_CHANGELOG_FILE='') → 기존 동작 유지 ----
R3="$TMP/off"; mk_repo "$R3"
GIT_CMD="git -C $R3"
git -C "$R3" merge --no-commit --no-ff main >/dev/null 2>&1
rc=0; ( INT_CHANGELOG_FILE=''; GIT_CMD="git -C $R3"; in_autoresolve_merge "$BRANCH" >/dev/null 2>&1 ) || rc=$?
chk "11: 게이트 비활성 rc=0" "$rc" "0"
grep -q 'main 항목 C' "$R3/CHANGELOG.md" && bad "12: 비활성 시 기존 한쪽 채택 동작 유지" || ok "12: 비활성 시 기존 한쪽 채택 동작 유지"

# ---- 케이스 4: rebase 경로도 같은 보존 ----
R4="$TMP/rebase"; mk_repo "$R4"
GIT_CMD="git -C $R4"
git -C "$R4" rebase main >/dev/null 2>&1
rc=0; in_autoresolve_rebase "$BRANCH" >/dev/null 2>&1 || rc=$?
chk "13: rebase 자율 해소 rc=0" "$rc" "0"
grep -q '브랜치 항목 B' "$R4/CHANGELOG.md" && ok "14: rebase — 브랜치 섹션 보존" || bad "14: rebase — 브랜치 섹션 보존"
grep -q 'main 항목 C' "$R4/CHANGELOG.md" && ok "15: rebase — base 섹션 보존" || bad "15: rebase — base 섹션 보존"
chk "16: rebase — base 대비 삭제 라인 0" "$(lost_lines "$R4")" "0"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || { echo "FAILURES present"; exit 1; }
