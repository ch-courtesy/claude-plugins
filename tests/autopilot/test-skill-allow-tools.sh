#!/usr/bin/env bash
# SPEC 113: autopilot:spec / autopilot:loop SKILL.md frontmatter 권한 허용
# 패턴 정적 검증.
#
# AC1·AC2 — 두 SKILL.md frontmatter에 권한 허용 패턴 배열이 존재.
# AC3    — 두 SKILL.md frontmatter는 YAML로 parse 성공.
# AC4    — 배열은 catch-all 패턴(`Bash(*)`·`*` 단독)을 포함하지 않는다.
# AC5    — 배열은 `gh pr` prefix를 제외한 모든 `gh ` prefix 패턴을 포함하지 않는다.
# AC6    — 배열 내 중복 항목 없음.
# AC7    — spec/SKILL.md 배열에 issue #113 본문 `autopilot:spec` + `공통·보조` 패턴 모두 포함.
# AC8    — loop/SKILL.md 배열에 issue #113 본문 `autopilot:loop` + `공통·보조` 패턴 모두 포함.
#
# 비교 기준 집합(AC7·AC8)은 SPEC 작성 시점의 issue body를 frozen reference로
# 본 스크립트에 박는다. 외부 API 호출은 수행하지 않는다.
#
# 의존성:
#   - yq (mikefarah Go 구현) — frontmatter YAML parse용.
#       macOS: brew install yq
#       Linux: apt install yq  /  snap install yq  /  https://github.com/mikefarah/yq/releases

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SPEC_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/spec/SKILL.md"
LOOP_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/loop/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

command -v yq >/dev/null 2>&1 || fail "yq (mikefarah) 필요 — target 프로젝트 의존성. 설치: macOS \`brew install yq\` / Linux \`apt install yq\` 또는 https://github.com/mikefarah/yq/releases"

[[ -f "$SPEC_SKILL_MD" ]] || fail "$SPEC_SKILL_MD 부재"
[[ -f "$LOOP_SKILL_MD" ]] || fail "$LOOP_SKILL_MD 부재"

# ---------------------------------------------------------------------------
# frontmatter 추출 (첫 --- ~ 두 번째 --- 사이)
extract_frontmatter() {
  awk '
    BEGIN { in_fm = 0; count = 0 }
    /^---$/ {
      count++
      if (count == 1) { in_fm = 1; next }
      if (count == 2) { exit }
    }
    in_fm { print }
  ' "$1"
}

SPEC_FM="$(extract_frontmatter "$SPEC_SKILL_MD")"
LOOP_FM="$(extract_frontmatter "$LOOP_SKILL_MD")"

[[ -n "$SPEC_FM" ]] || fail "spec SKILL.md frontmatter 추출 실패"
[[ -n "$LOOP_FM" ]] || fail "loop SKILL.md frontmatter 추출 실패"

# ---------------------------------------------------------------------------
echo "=== AC3: YAML parse ==="
echo "$SPEC_FM" | yq eval . - >/dev/null 2>&1 \
  || fail "AC3: spec SKILL.md frontmatter YAML parse 실패"
echo "$LOOP_FM" | yq eval . - >/dev/null 2>&1 \
  || fail "AC3: loop SKILL.md frontmatter YAML parse 실패"
ok "AC3: spec·loop SKILL.md frontmatter YAML parse 통과"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC1·AC2: allowed-tools 배열 존재 ==="
spec_kind="$(printf '%s\n' "$SPEC_FM" | yq eval '.allowed-tools | tag' -)"
loop_kind="$(printf '%s\n' "$LOOP_FM" | yq eval '.allowed-tools | tag' -)"
[[ "$spec_kind" == "!!seq" ]] \
  || fail "AC1: spec SKILL.md allowed-tools 가 YAML 배열(seq) 아님 (실측: $spec_kind)"
[[ "$loop_kind" == "!!seq" ]] \
  || fail "AC2: loop SKILL.md allowed-tools 가 YAML 배열(seq) 아님 (실측: $loop_kind)"
ok "AC1·AC2: 두 SKILL.md allowed-tools 가 YAML 배열"

# 배열 항목 수집 — newline-separated
spec_items="$(printf '%s\n' "$SPEC_FM" | yq eval '.allowed-tools[]' -)"
loop_items="$(printf '%s\n' "$LOOP_FM" | yq eval '.allowed-tools[]' -)"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC4: catch-all 패턴 부재 ==="
check_no_catchall() {
  local name="$1" items="$2" line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
      'Bash(*)'|'*')
        fail "AC4: $name 에 catch-all 패턴 발견: $line"
        ;;
    esac
  done <<< "$items"
}
check_no_catchall "spec" "$spec_items"
check_no_catchall "loop" "$loop_items"
ok "AC4: catch-all (Bash(*)·*) 부재"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC5: gh pr 외 gh 패턴 부재 ==="
# Bash(...) 안의 내부를 추출해 검사. 두 형태 모두 점검:
#   1) Bash(gh ...) - 공백으로 분리된 첫 단어
#   2) Bash(gh:...) - 콜론으로 분리된 prefix
check_gh_only_pr() {
  local name="$1" items="$2" line inner
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Bash(...) prefix 인 항목만 검사
    case "$line" in
      'Bash('*')')
        # 안쪽 내용 추출
        inner="${line#Bash(}"
        inner="${inner%)}"
        # gh 패턴 검사
        case "$inner" in
          gh\ pr*)
            : # 허용
            ;;
          gh\ *|gh:*)
            fail "AC5: $name 에 gh pr 외 gh 패턴 발견: $line"
            ;;
        esac
        ;;
    esac
  done <<< "$items"
}
check_gh_only_pr "spec" "$spec_items"
check_gh_only_pr "loop" "$loop_items"
ok "AC5: gh pr 외 gh 패턴 부재"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC6: 중복 항목 부재 ==="
check_no_dup() {
  local name="$1" items="$2" dup
  dup="$(printf '%s\n' "$items" | grep -v '^$' | sort | uniq -d || true)"
  if [[ -n "$dup" ]]; then
    fail "AC6: $name 에 중복 항목 존재: $dup"
  fi
}
check_no_dup "spec" "$spec_items"
check_no_dup "loop" "$loop_items"
ok "AC6: 중복 항목 부재"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC7·AC8: issue #113 본문 enumerate 패턴 포함 ==="

# issue #113 본문의 `autopilot:spec` 섹션 패턴 (gh 패턴 제외)
# SPEC 108 AC2 — spec/SKILL.md 의 trailing ' *' 는 ':*' 로 정규화됨.
# 'Bash(git branch *)' 는 short-prefix 'Bash(git branch:*)' 로 dedup 흡수 (SPEC 108).
SPEC_REQ=(
  'Bash(git -C * rev-parse:*)'
  'Bash(git -C * status --porcelain)'
  'Bash(git -C * log:*)'
  'Bash(git -C * branch:*)'
  'Bash(git -C * show-ref:*)'
  'Bash(git -C * for-each-ref:*)'
  'Bash(git -C * ls-files:*)'
  'Bash(git -C * diff:*)'
  'Bash(git -C * checkout:*)'
  'Bash(git -C * checkout -b:*)'
  'Bash(git -C * add:*)'
  'Bash(git -C * commit:*)'
  'Bash(git update-ref:*)'
  'Bash(git branch:*)'
  'Bash(git -C * hash-object -w:*)'
  'Bash(GIT_INDEX_FILE=* git -C * read-tree:*)'
  'Bash(GIT_INDEX_FILE=* git -C * update-index --add --cacheinfo:*)'
  'Bash(GIT_INDEX_FILE=* git -C * write-tree)'
  'Bash(git -C * commit-tree * -p:*)'
  'Bash(mkdir -p milestones/**)'
  'Bash(awk:*)'
  'Bash(sed:*)'
  'Bash(tr:*)'
  'Bash(grep -rE * plugins/autopilot/**)'
  'Bash(grep -rln * plugins/autopilot/**)'
)

# issue #113 본문의 `autopilot:loop` 섹션 패턴 (gh 패턴 제외)
# SPEC 170 — trailing wildcard 형식을 ` *`(공백+별표) → `:*` 로 정규화
LOOP_REQ=(
  'Bash(bash * loop.sh start:*)'
  'Bash(bash * loop.sh status:*)'
  'Bash(bash * loop.sh stop:*)'
  'Bash(bash * loop.sh list)'
  'Bash(bash * loop.sh cleanup:*)'
  'Bash(bash * loop.sh logs:*)'
  'Bash(tail -F /private/tmp/* | grep -E --line-buffered:*)'
  'Bash(tail -F /tmp/* | grep -E --line-buffered:*)'
)

# issue #113 본문의 `공통·보조` 섹션 패턴 (gh 패턴 제외).
# trailing wildcard가 없는 항목은 두 SKILL.md 공용.
COMMON_REQ_NO_WILDCARD=(
  'Bash(git -C * stash list)'
  'Bash(rm */ESCALATION.md)'
  'Bash(rm */DONE)'
  'Bash(cat */*.lock)'
)

# trailing wildcard가 있는 공통 패턴은 SKILL별 형식이 분리된다:
#   - loop/SKILL.md: SPEC 170 적용 → `:*`
#   - spec/SKILL.md: SPEC 108 적용 전 → ` *` (SPEC 108 머지 후 통일)
SPEC_COMMON_WILDCARD=(
  'Bash(git -C * stash pop *)'
  'Bash(git -C * stash show *)'
  'Bash(ps -p *)'
)
LOOP_COMMON_WILDCARD=(
  'Bash(git -C * stash pop:*)'
  'Bash(git -C * stash show:*)'
  'Bash(ps -p:*)'
)

check_contains_all() {
  local name="$1" items="$2"
  shift 2
  local missing=0 req
  for req in "$@"; do
    if ! grep -qxF -- "$req" <<< "$items"; then
      echo "  MISSING ($name): $req" >&2
      missing=1
    fi
  done
  if (( missing != 0 )); then
    fail "$name 에 누락 패턴 존재 (위 MISSING 항목 참조)"
  fi
}

check_contains_all "spec/SKILL.md" "$spec_items" \
  "${SPEC_REQ[@]}" "${COMMON_REQ_NO_WILDCARD[@]}" "${SPEC_COMMON_WILDCARD[@]}"
ok "AC7: spec SKILL.md 에 issue spec 섹션 + 공통·보조 섹션 패턴 모두 포함"

check_contains_all "loop/SKILL.md" "$loop_items" \
  "${LOOP_REQ[@]}" "${COMMON_REQ_NO_WILDCARD[@]}" "${LOOP_COMMON_WILDCARD[@]}"
ok "AC8: loop SKILL.md 에 issue loop 섹션 + 공통·보조 섹션 패턴 모두 포함"

echo ""
echo "ALL CHECKS PASSED"
