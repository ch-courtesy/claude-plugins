#!/usr/bin/env bash
# SPEC 170: autopilot:loop SKILL.md frontmatter — Read 추가 + 공백→콜론 정규화
# 패턴 정적 검증.
#
# AC1 — allowed-tools 에 `Read` 항목 포함
# AC2 — 모든 Bash 항목 trailing ` *`(공백+별표) 0개 (`:*` 정규화 형식 사용)
# AC3 — frontmatter YAML parse 성공
# AC4 — catch-all 패턴(`Bash(*)`·`*` 단독) 0개
# AC5 — `gh pr` 외 `gh ` prefix 패턴 0개
# AC6 — 중복 항목 0개
#
# 의존성:
#   - yq (mikefarah) — frontmatter YAML parse용

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
LOOP_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/loop/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

command -v yq >/dev/null 2>&1 \
  || fail "yq (mikefarah) 필요 — target 프로젝트 의존성. 설치: macOS \`brew install yq\` / Linux \`apt install yq\` 또는 https://github.com/mikefarah/yq/releases"

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

LOOP_FM="$(extract_frontmatter "$LOOP_SKILL_MD")"
[[ -n "$LOOP_FM" ]] || fail "loop SKILL.md frontmatter 추출 실패"

# ---------------------------------------------------------------------------
echo "=== AC3: YAML parse ==="
echo "$LOOP_FM" | yq eval . - >/dev/null 2>&1 \
  || fail "AC3: loop SKILL.md frontmatter YAML parse 실패"
ok "AC3: loop SKILL.md frontmatter YAML parse 통과"

# 배열 항목 수집 — newline-separated
loop_kind="$(printf '%s\n' "$LOOP_FM" | yq eval '.allowed-tools | tag' -)"
[[ "$loop_kind" == "!!seq" ]] \
  || fail "loop SKILL.md allowed-tools 가 YAML 배열(seq) 아님 (실측: $loop_kind)"

loop_items="$(printf '%s\n' "$LOOP_FM" | yq eval '.allowed-tools[]' -)"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC1: Read 항목 포함 ==="
if ! grep -qxF -- 'Read' <<< "$loop_items"; then
  fail "AC1: loop SKILL.md allowed-tools 에 'Read' 항목 누락"
fi
ok "AC1: Read 항목 포함"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC2: trailing ' *'(공백+별표) 패턴 부재 ==="
# Bash(...) 항목들에서 닫는 괄호 직전이 ' *'(공백 후 별표)로 끝나면 위반.
trailing_space_star=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  case "$line" in
    'Bash('*' *)')
      echo "  TRAILING-SPACE-STAR: $line" >&2
      trailing_space_star=$(( trailing_space_star + 1 ))
      ;;
  esac
done <<< "$loop_items"
if (( trailing_space_star > 0 )); then
  fail "AC2: trailing ' *'(공백+별표) 패턴 ${trailing_space_star}개 발견 — ':*' 형식으로 정규화 필요"
fi
ok "AC2: trailing ' *' 패턴 부재"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC4: catch-all 패턴 부재 ==="
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  case "$line" in
    'Bash(*)'|'*')
      fail "AC4: catch-all 패턴 발견: $line"
      ;;
  esac
done <<< "$loop_items"
ok "AC4: catch-all (Bash(*)·*) 부재"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC5: gh pr 외 gh 패턴 부재 ==="
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  case "$line" in
    'Bash('*')')
      inner="${line#Bash(}"
      inner="${inner%)}"
      case "$inner" in
        gh\ pr*)
          : # 허용
          ;;
        gh\ *|gh:*)
          fail "AC5: gh pr 외 gh 패턴 발견: $line"
          ;;
      esac
      ;;
  esac
done <<< "$loop_items"
ok "AC5: gh pr 외 gh 패턴 부재"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC6: 중복 항목 부재 ==="
dup="$(printf '%s\n' "$loop_items" | grep -v '^$' | sort | uniq -d || true)"
if [[ -n "$dup" ]]; then
  fail "AC6: 중복 항목 존재: $dup"
fi
ok "AC6: 중복 항목 부재"

echo ""
echo "ALL CHECKS PASSED"
