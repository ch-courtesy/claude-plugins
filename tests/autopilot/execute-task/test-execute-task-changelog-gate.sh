#!/usr/bin/env bash
# test-execute-task-changelog-gate.sh — CHANGELOG 순수-추가 게이트 (#628)
#
# CHANGELOG 는 누적 계약(추가만)이다. 워커가 base 전진을 못 따라가 기존 섹션을 자기
# 항목으로 덮어쓰면(기존 라인 삭제) 통합이 그 변경을 머지 후보로 통과시키지 않고
# 차단해야 한다. 추가만 있는 변경(삭제 0)은 기존대로 통과한다. 경로는
# INT_CHANGELOG_FILE 로 설정 가능하며(빈 값=게이트 비활성 우회), base 에 파일이
# 없으면 적용하지 않는다(정책 비내장).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
INTEGRATION="$REPO_ROOT/plugins/autopilot/lib/forge/lib/integration.sh"
fail=0; ok(){ echo "PASS  $1"; }; bad(){ echo "FAIL  $1"; fail=1; }
chk(){ [[ "$2" == "$3" ]] && ok "$1" || bad "$1 (want '$3' got '$2')"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---- fixture repo: main 에 기존 CHANGELOG 항목 2개 ----
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
cat > "$REPO/CHANGELOG.md" <<'EOF'
# Changelog

## pkg 0.2.0

### 기능
- 기존 항목 B

## pkg 0.1.0

### 기능
- 기존 항목 A
-- 각주형 라인(더블대시 시작)
EOF
echo base > "$REPO/f.txt"
git -C "$REPO" add -A; git -C "$REPO" commit -qm base

# 브랜치 add-only: 최상단에 새 섹션 추가만(삭제 0).
git -C "$REPO" checkout -qb feat/add
awk 'NR==2{print ""; print "## pkg 0.3.0"; print ""; print "### 기능"; print "- 새 항목 C"} {print}' \
  "$REPO/CHANGELOG.md" > "$REPO/CHANGELOG.md.new" && mv "$REPO/CHANGELOG.md.new" "$REPO/CHANGELOG.md"
git -C "$REPO" commit -aqm 'add entry'

# 브랜치 delete: 기존 0.2.0 섹션을 자기 항목으로 교체(기존 라인 삭제).
git -C "$REPO" checkout -q main
git -C "$REPO" checkout -qb feat/del
sed -e 's/## pkg 0.2.0/## pkg 0.9.9/' -e 's/- 기존 항목 B/- 내 항목/' "$REPO/CHANGELOG.md" > "$REPO/CHANGELOG.md.new" \
  && mv "$REPO/CHANGELOG.md.new" "$REPO/CHANGELOG.md"
git -C "$REPO" commit -aqm 'overwrite entry'
git -C "$REPO" checkout -q main

# integration.sh 를 함수로 source (CLI 미실행 가드 존재).
# shellcheck source=/dev/null
. "$INTEGRATION"
GIT_CMD="git -C $REPO"
DEFAULT_BRANCH=main

# ---- 게이트 함수 단위: 삭제 → 차단(rc!=0) + 우회 안내, 추가만 → 통과 ----
err="$(in_changelog_additive_gate "feat/del" 2>&1)" && rc=0 || rc=$?
chk "삭제 브랜치 차단 rc!=0" "$([[ $rc -ne 0 ]] && echo blocked)" "blocked"
case "$err" in *INT_CHANGELOG_FILE*) ok "차단 문구에 우회 방법 명시";; *) bad "차단 문구에 우회 방법 명시 (got: $err)";; esac
in_changelog_additive_gate "feat/add" 2>/dev/null && ok "추가-만 브랜치 통과" || bad "추가-만 브랜치 통과"

# 빈 값 우회: INT_CHANGELOG_FILE='' → 게이트 비활성. (서브셸 — 이후 기본값 오염 방지)
( INT_CHANGELOG_FILE=''; in_changelog_additive_gate "feat/del" 2>/dev/null ) \
  && ok "빈 INT_CHANGELOG_FILE → 게이트 비활성(우회)" || bad "빈 INT_CHANGELOG_FILE → 게이트 비활성(우회)"

# 파일 부재 → 미적용: base 에 없는 경로를 지정하면 통과.
( INT_CHANGELOG_FILE='NOPE.md'; in_changelog_additive_gate "feat/del" 2>/dev/null ) \
  && ok "base 에 파일 부재 → 게이트 미적용" || bad "base 에 파일 부재 → 게이트 미적용"

# '-- ' 로 시작하는 콘텐츠 라인 삭제도 잡는다(diff 렌더 '--- ...' 가 파일 헤더로 오인되면 미탐).
git -C "$REPO" checkout -qb feat/del-dashes main
grep -v '^-- 각주형' "$REPO/CHANGELOG.md" > "$REPO/CHANGELOG.md.new" && mv "$REPO/CHANGELOG.md.new" "$REPO/CHANGELOG.md"
git -C "$REPO" commit -aqm 'delete double-dash line'
git -C "$REPO" checkout -q main
in_changelog_additive_gate "feat/del-dashes" 2>/dev/null && rc=0 || rc=$?
chk "'-- ' 시작 라인 삭제도 차단" "$([[ $rc -ne 0 ]] && echo blocked)" "blocked"

# ---- integrate-direct 배선: DONE 태스크의 CHANGELOG 삭제 브랜치는 review 로 못 간다 ----
# mock loop: 항상 terminal DONE, WT=삭제 브랜치 tip 의 분리 워크트리.
DELWT="$TMP/delwt"
git -C "$REPO" worktree add -q --detach "$DELWT" feat/del
mock_loop() {
  case "$1" in
    status) printf '{"state":"terminal","signals":["DONE"]}\n' ;;
    logs)   : ;;
    paths)  printf 'WT          %s\n' "$MOCK_WT" ;;
    cleanup) : ;;
  esac
}
LOOP_CMD=mock_loop

# 삭제 브랜치를 결정적 작업 브랜치명으로 별칭(브랜치 생성) — in_work_branch 계약 충족.
SPEC="$TMP/SPEC.md"; printf '# gate del case\n' > "$SPEC"
RD="$TMP/.autopilot/runs/rid1"; mkdir -p "$RD"
git -C "$REPO" branch -f feat/rid1-gate-del-case feat/del
MOCK_WT="$DELWT" in_integrate_direct "$SPEC" "$RD" "k-del00000" >/dev/null 2>&1 && rc=0 || rc=$?
chk "direct: 삭제 브랜치 rc=4(하드 차단)" "$rc" "4"
chk "direct: 삭제 브랜치 phase=blocked(review 진입 금지)" "$(int_get_phase "$RD" "k-del00000")" "blocked"

# 추가-만 브랜치는 기존대로 review 진입.
ADDWT="$TMP/addwt"
git -C "$REPO" worktree add -q --detach "$ADDWT" feat/add
SPEC2="$TMP/SPEC2.md"; printf '# gate add case\n' > "$SPEC2"
RD2="$TMP/.autopilot/runs/rid2"; mkdir -p "$RD2"
git -C "$REPO" branch -f feat/rid2-gate-add-case feat/add
MOCK_WT="$ADDWT" in_integrate_direct "$SPEC2" "$RD2" "k-add00000" >/dev/null 2>&1 && rc=0 || rc=$?
chk "direct: 추가-만 브랜치 rc=0(통과)" "$rc" "0"
chk "direct: 추가-만 브랜치 phase=review" "$(int_get_phase "$RD2" "k-add00000")" "review"

echo "----"; [[ $fail -eq 0 ]] && echo "ALL PASS" || echo "FAILURES present"; exit $fail
