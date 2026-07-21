#!/usr/bin/env bash
# test-execute-task-reentry-conflict-resync.sh — 재실행(open PR 존재) base sync 의 충돌 재통합 (#626 회귀 가드).
#   재진입은 forge integrate 를 재실행하고 integrate 는 리뷰 폴링 **전에** in_base_sync 를 탄다.
#   따라서 in_base_sync 가 open PR 충돌 브랜치를 재통합하면 "리뷰 폴링 전 재통합" 계약이 성립한다.
#   (a) 충돌: open PR + origin/main 충돌 전진 → origin/main merge-in 자율 해소 후 원격 작업
#       브랜치로 직접 push(INT_BASESYNC_PUSHED=1). non-force: 기존 원격 tip 은 새 tip 의 조상 보존.
#   (b) 무충돌: open PR + origin/main 클린 전진 → 기존 동작 유지(재작성·push 없음, rc0).
#   (c) 재통합 실패(push 거부): rc≠0 즉시 실패 — integrate 가 차단하므로 리뷰 폴링 상한 미소진
#       (driver 의 integrate-실패 즉시 blocked 는 test-execute-task-blocked-category.sh 가 가드).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEG="$HERE/../../../plugins/autopilot/lib/forge/lib/integration.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# mock forge: 모든 브랜치에 open PR #42 존재.
cat > "$TMP/bin/forge" << 'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "pr" && "${2:-}" == "list" ]] && echo "42"
exit 0
EOF
chmod +x "$TMP/bin/forge"

# ---- fixture: bare origin + 로컬 repo, 공통 조상 C0 에서 세 작업 브랜치 + main 충돌 전진 ----
git init -q --bare "$TMP/origin.git"
git init -q "$TMP/repo"
cd "$TMP/repo"
git config user.email t@t; git config user.name t
git remote add origin "$TMP/origin.git"   # 절대 경로(분리 워크트리에서도 해석)
printf 'base\n' > c.txt; printf 'base\n' > d.txt
git add .; git commit -qm C0
git push -q origin HEAD:main
C0="$(git rev-parse HEAD)"

git checkout -qb feat/9-x "$C0"; printf 'work\n' > c.txt;  git commit -qam work-x;  git push -q origin feat/9-x
git checkout -qb feat/9-y "$C0"; printf 'y\n'    > e.txt;  git add e.txt; git commit -qm work-y; git push -q origin feat/9-y
git checkout -qb feat/9-z "$C0"; printf 'work\n' > c.txt;  git commit -qam work-z;  git push -q origin feat/9-z

# main 전진: c.txt 를 바꿔 x·z 와 충돌, y 와는 무충돌.
git checkout -q --detach "$C0"; printf 'main2\n' > c.txt; git commit -qam main2
git push -q origin HEAD:main
git fetch -q origin

# integration.sh 를 소싱(함수만 노출) — 주입 변수로 mock 연결.
GIT_CMD=git DEFAULT_BRANCH=main FORGE_CMD="$TMP/bin/forge" LOOP_CMD=/bin/true
# shellcheck source=/dev/null
. "$INTEG"

# ---- (a) 충돌 브랜치: merge-in 재통합 + 직접 push ----
tip1="$(git ls-remote origin refs/heads/feat/9-x | awk '{print $1}')"
rc=0; in_base_sync feat/9-x >/dev/null 2>&1 || rc=$?
tip2="$(git ls-remote origin refs/heads/feat/9-x | awk '{print $1}')"
git fetch -q origin
[[ "$rc" == 0 ]] && ok "a: rc=0" || bad "a: rc=0 (got $rc)"
[[ "$tip2" != "$tip1" ]] && ok "a: 원격 tip 갱신(재통합 push)" || bad "a: 원격 tip 갱신(재통합 push)"
[[ "${INT_BASESYNC_PUSHED:-}" == "1" ]] && ok "a: INT_BASESYNC_PUSHED=1" || bad "a: INT_BASESYNC_PUSHED=1"
git merge-base --is-ancestor origin/main "$tip2" 2>/dev/null \
  && ok "a: origin/main 이 새 tip 의 조상(충돌 해소)" || bad "a: origin/main 이 새 tip 의 조상(충돌 해소)"
git merge-base --is-ancestor "$tip1" "$tip2" 2>/dev/null \
  && ok "a: 기존 tip 보존(non-force merge-in)" || bad "a: 기존 tip 보존(non-force merge-in)"
[[ "$(git show "$tip2:c.txt" 2>/dev/null)" == "work" ]] \
  && ok "a: 충돌 파일 작업 쪽 해소(incoming 기본)" || bad "a: 충돌 파일 작업 쪽 해소(incoming 기본)"
[[ "${INT_AUTORESOLVE_FLAG:-}" == "needs-verify" ]] \
  && ok "a: 비결정 표시(needs-verify)" || bad "a: 비결정 표시(needs-verify)"

# ---- (b) 무충돌 브랜치: 기존 동작 유지(재작성·push 없음) ----
tipy1="$(git ls-remote origin refs/heads/feat/9-y | awk '{print $1}')"
rc=0; in_base_sync feat/9-y >/dev/null 2>&1 || rc=$?
tipy2="$(git ls-remote origin refs/heads/feat/9-y | awk '{print $1}')"
[[ "$rc" == 0 ]] && ok "b: rc=0" || bad "b: rc=0 (got $rc)"
[[ "$tipy2" == "$tipy1" ]] && ok "b: 원격 tip 불변(무충돌 → 기존 동작)" || bad "b: 원격 tip 불변(무충돌 → 기존 동작)"
[[ -z "${INT_BASESYNC_PUSHED:-}" ]] && ok "b: INT_BASESYNC_PUSHED 미설정" || bad "b: INT_BASESYNC_PUSHED 미설정"

# ---- (c) 재통합 push 거부: 즉시 실패(rc≠0) ----
mkdir -p "$TMP/origin.git/hooks"
printf '#!/bin/sh\nexit 1\n' > "$TMP/origin.git/hooks/pre-receive"
chmod +x "$TMP/origin.git/hooks/pre-receive"
rc=0; in_base_sync feat/9-z >/dev/null 2>&1 || rc=$?
[[ "$rc" != 0 ]] && ok "c: 재통합 실패 시 rc≠0(즉시 차단 경로)" || bad "c: 재통합 실패 시 rc≠0(즉시 차단 경로)"

echo "----"
[[ $fail -eq 0 ]] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES present"; exit 1; }
