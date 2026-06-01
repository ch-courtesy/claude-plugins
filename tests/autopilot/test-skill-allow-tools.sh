#!/usr/bin/env bash
# autopilot:spec SKILL.md frontmatter 권한 허용 패턴 정적 검증 (spec 전용).
#
# 원래 이 테스트는 issue #113("spec·loop" 권한 계약)을 따라 spec·loop 두 SKILL.md를
# 한 파일에서 함께 검사했다. 그러나 두 스킬은 각각 독립 재설계로 권한 계약이 바뀌었고
# (spec 경량화 40c0e42 — git plumbing 제거 / loop v0.7.0 8f3b75d — phase 스크립트 제거),
# #113의 결합은 공통 섹션·공통 위생 규칙을 한 곳에 둔 역사적 산물일 뿐 구조적 의존이 아니다.
# 본 테스트는 spec 전용으로 분리해 현 경량 spec 계약만 검증한다. loop 권한 검증은 범위 밖이다.
#
# AC1 — spec SKILL.md frontmatter 에 allowed-tools 배열이 존재(YAML seq).
# AC3 — spec SKILL.md frontmatter 는 YAML 로 parse 성공.
# AC4 — 배열은 catch-all 패턴(`Bash(*)`·`*` 단독)을 포함하지 않는다.
# AC5 — 배열은 `gh pr` prefix 를 제외한 모든 `gh ` prefix 패턴을 포함하지 않는다.
# AC6 — 배열 내 중복 항목 없음.
# AC7 — 경량 spec 계약: 현 spec/SKILL.md 가 선언해야 하는 큐레이트 Bash 패턴을 모두 포함.
#
# 비교 기준 집합(AC7)은 경량화 후 spec 계약을 frozen reference 로 본 스크립트에 박는다.
# 외부 API 호출은 수행하지 않는다.
#
# 의존성:
#   - yq (mikefarah Go 구현) — frontmatter YAML parse용.
#       macOS: brew install yq
#       Linux: apt install yq  /  snap install yq  /  https://github.com/mikefarah/yq/releases

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SPEC_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/spec/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

command -v yq >/dev/null 2>&1 || fail "yq (mikefarah) 필요 — target 프로젝트 의존성. 설치: macOS \`brew install yq\` / Linux \`apt install yq\` 또는 https://github.com/mikefarah/yq/releases"

[[ -f "$SPEC_SKILL_MD" ]] || fail "$SPEC_SKILL_MD 부재"

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
[[ -n "$SPEC_FM" ]] || fail "spec SKILL.md frontmatter 추출 실패"

# ---------------------------------------------------------------------------
echo "=== AC3: YAML parse ==="
echo "$SPEC_FM" | yq eval . - >/dev/null 2>&1 \
  || fail "AC3: spec SKILL.md frontmatter YAML parse 실패"
ok "AC3: spec SKILL.md frontmatter YAML parse 통과"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC1: allowed-tools 배열 존재 ==="
spec_kind="$(printf '%s\n' "$SPEC_FM" | yq eval '.allowed-tools | tag' -)"
[[ "$spec_kind" == "!!seq" ]] \
  || fail "AC1: spec SKILL.md allowed-tools 가 YAML 배열(seq) 아님 (실측: $spec_kind)"
ok "AC1: spec SKILL.md allowed-tools 가 YAML 배열"

# 배열 항목 수집 — newline-separated
spec_items="$(printf '%s\n' "$SPEC_FM" | yq eval '.allowed-tools[]' -)"

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
ok "AC6: 중복 항목 부재"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC7: 경량 spec 계약 — 큐레이트 Bash 패턴 포함 ==="
# 경량화(40c0e42) 후 spec 은 git plumbing·worktree·Task 권한을 갖지 않는다.
# spec 은 SPEC 문서 저작에 필요한 읽기·요약·문서 작성용 Bash 만 선언한다.
SPEC_REQ=(
  'Bash(git log:*)'
  'Bash(git status:*)'
  'Bash(ls:*)'
  'Bash(cat:*)'
  'Bash(find:*)'
  'Bash(grep:*)'
  'Bash(echo:*)'
  'Bash(head:*)'
  'Bash(awk:*)'
  'Bash(sed:*)'
  'Bash(tr:*)'
  'Bash(printf:*)'
  'Bash(pwd:*)'
  'Bash(mkdir -p docs/specs/**)'
  'Bash(mkdir -p:*)'
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

check_contains_all "spec/SKILL.md" "$spec_items" "${SPEC_REQ[@]}"
ok "AC7: spec SKILL.md 에 경량 계약 Bash 패턴 모두 포함"

# ---------------------------------------------------------------------------
# 경량 계약 negative: spec 은 git 쓰기·plumbing·worktree 권한을 갖지 않는다.
echo ""
echo "=== AC7b: 경량 계약 — git 쓰기·plumbing 권한 부재 ==="
for forbidden in 'commit-tree' 'write-tree' 'read-tree' 'update-ref' 'hash-object' 'git worktree' 'git -C * commit' 'git -C * checkout'; do
  if grep -qF -- "$forbidden" <<< "$spec_items"; then
    fail "AC7b: spec/SKILL.md 에 경량 계약 위반 권한 잔존: $forbidden (경량화 40c0e42 로 제거됨)"
  fi
done
ok "AC7b: git 쓰기·plumbing·worktree 권한 부재 (경량 계약 준수)"

echo ""
echo "ALL CHECKS PASSED"
