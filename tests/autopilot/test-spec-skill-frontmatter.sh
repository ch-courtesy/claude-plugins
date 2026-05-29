#!/usr/bin/env bash
# SPEC 108: spec/SKILL.md frontmatter allowed-tools 보강 (9개) + §9.5.1 sed→awk 정규화.
#
# 본 스크립트는 SPEC 108 의 verify 항목으로 다음 AC를 정적·행위 검증한다:
#
# AC1 — spec/SKILL.md frontmatter `allowed-tools` 에 9개 신규 항목 모두 포함.
# AC2 — `allowed-tools` 의 모든 Bash 항목은 trailing `:*` 형식 (trailing ` *` 부재).
# AC3 — frontmatter YAML parse 성공.
# AC4 — catch-all 패턴 (`Bash(*)`·`*` 단독) 부재.
# AC5 — `gh pr` prefix 외 모든 `gh ` prefix 패턴 부재.
# AC6 — 중복 항목 부재.
# AC7 — rules/engineering/branch-and-slug.md "slug 규칙" H1 추출 코드가
#        macOS BSD sed·GNU sed 모두에서 syntax error 없이 실행 가능 (awk 기반).
#        정적 검사(기존 sed 패턴 부재) + 행위 동등성 검사(샘플 SPEC.md 입력).
#        (SPEC 220 에서 단일 출처가 references/feat-branch-commit.md →
#         rules/engineering/branch-and-slug.md 로 이동했으나 awk 추출 코드는 동일.)
#
# 의존성:
#   - yq (mikefarah Go 구현) — frontmatter YAML parse용.
#       macOS: brew install yq
#       Linux: apt install yq  /  snap install yq  /  https://github.com/mikefarah/yq/releases

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SPEC_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/spec/SKILL.md"
# SPEC 220: slug·브랜치 단일 출처가 spec 스킬 references → rules/engineering 로 외부화됨.
FEAT_BRANCH_MD="$REPO_ROOT/rules/engineering/branch-and-slug.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

yq --version 2>&1 | grep -qiE 'mikefarah|version v?[4-9]\.' \
  || fail "yq (mikefarah Go 구현) 필요 — 설치: macOS \`brew install yq\` / Linux https://github.com/mikefarah/yq/releases (apt install yq 는 kislyuk Python 구현으로 \`yq eval\` 미지원이므로 사용 불가)"

[[ -f "$SPEC_SKILL_MD" ]]  || fail "$SPEC_SKILL_MD 부재"
[[ -f "$FEAT_BRANCH_MD" ]] || fail "$FEAT_BRANCH_MD 부재"

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
ok "AC3: frontmatter YAML parse 통과"

# allowed-tools 가 YAML 배열인지 확인 + 항목 추출
spec_kind="$(printf '%s\n' "$SPEC_FM" | yq eval '.allowed-tools | tag' -)"
[[ "$spec_kind" == "!!seq" ]] \
  || fail "allowed-tools 가 YAML 배열(seq) 아님 (실측: $spec_kind)"

spec_items="$(printf '%s\n' "$SPEC_FM" | yq eval '.allowed-tools[]' -)"
[[ -n "$spec_items" ]] || fail "allowed-tools 배열 비어 있음"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC1: 현 경량 spec 계약 핵심 항목 포함 ==="
# 정합 갱신: 경량 redesign 으로 spec 스킬은 외부 상태(task·worktree)를 만들지
# 않으므로 과거 stale 항목(mktemp·EnterWorktree·ExitWorktree·TaskCreate·
# TaskUpdate — 제거된 task/worktree 기능)을 검증에서 제거한다. 본 배열은 현
# 경량 계약의 frontmatter allowed-tools 에 실제 존재해야 하는 핵심 항목만
# enumerate 한다 (trailing 형식 정규화 자체는 AC2 가 sed/tr 포함 전수로 검증).
REQUIRED_ITEMS=(
  'AskUserQuestion'
  'Read'
  'Write'
  'Skill'
  'Agent'
  'Bash(git log:*)'
  'Bash(awk:*)'
  'Bash(printf:*)'
  'Bash(pwd:*)'
  'Bash(mkdir -p docs/specs/**)'
  'ToolSearch'
)
missing=0
for req in "${REQUIRED_ITEMS[@]}"; do
  if ! grep -qxF -- "$req" <<< "$spec_items"; then
    echo "  MISSING: $req" >&2
    missing=1
  fi
done
(( missing == 0 )) || fail "AC1: 누락 항목 존재 (위 MISSING 참조)"
ok "AC1: 현 경량 계약 핵심 항목 모두 포함"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC2: trailing ' *' (공백+별표) 형식 부재 ==="
# Bash(...) 항목 중 닫는 괄호 직전이 ' *' (공백+별표) 인 경우 fail.
# trailing ` *` 는 모두 trailing `:*` 로 정규화돼야 한다.
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  case "$line" in
    'Bash('*' *)')
      fail "AC2: trailing ' *' (공백+별표) 형식 발견: $line"
      ;;
  esac
done <<< "$spec_items"
ok "AC2: trailing ' *' 형식 부재 (모든 Bash 항목 trailing :*)"

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
done <<< "$spec_items"
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
        gh\ pr*) : ;;
        gh\ *|gh:*)
          fail "AC5: gh pr 외 gh 패턴 발견: $line"
          ;;
      esac
      ;;
  esac
done <<< "$spec_items"
ok "AC5: gh pr 외 gh 패턴 부재"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC6: 중복 항목 부재 ==="
dup="$(printf '%s\n' "$spec_items" | grep -v '^$' | sort | uniq -d || true)"
if [[ -n "$dup" ]]; then
  fail "AC6: 중복 항목 존재: $dup"
fi
ok "AC6: 중복 항목 부재"

# ---------------------------------------------------------------------------
echo ""
echo "=== AC7: \"slug 규칙\" H1 추출 — BSD/GNU 호환 (awk 기반) ==="

# 1) 정적 검사 (negative) — 슬러그 도출 코드 (line starting with `title=$(`) 에
#    BSD-incompatible sed 호출 (`title=$(sed`) 가 잔존하지 않음.
#    원본 패턴: `title=$(sed -n '/^---$/,/^---$/!{/^# /{s/^# //p; q;}}' ...`
#    BSD sed 에서 "extra characters at the end of } command" 로 실패.
#    (단순 문자열 검사가 아닌 코드 라인 prefix 검사 — 본문 prose 의 historical 참조는 허용.)
if grep -qE '^title=\$\(sed' "$FEAT_BRANCH_MD"; then
  fail "AC7-static-negative: 슬러그 도출 코드 (title=\$(sed ...) 가 branch-and-slug.md 본문에 잔존"
fi
ok "AC7-static-negative: 슬러그 도출 코드에 sed 호출 부재"

# 2) 정적 검사 (positive) — awk 기반 슬러그 도출 코드 (`title=$(awk`) 가 본문에 존재
if ! grep -qE '^title=\$\(awk' "$FEAT_BRANCH_MD"; then
  fail "AC7-static-positive: 슬러그 도출 코드 (title=\$(awk ...) 부재"
fi
if ! grep -qF 'sub(/^# /, "")' "$FEAT_BRANCH_MD"; then
  fail "AC7-static-positive: H1 sub 토큰 'sub(/^# /, \"\")' 부재"
fi
ok "AC7-static-positive: 슬러그 도출 코드가 awk 기반"

# 3) 행위 동등성 — 본 스크립트 안에서 awk 추출 함수를 실행해
#    여러 샘플 SPEC.md 입력에 대해 기대 H1 출력과 일치하는지 확인.
#    (md 본문에서 명령 추출이 복잡하므로, md 와 동일한 awk 표현을 본 스크립트가 보유.)
extract_h1_awk() {
  awk '
    /^---$/ { fm = !fm; next }
    !fm && /^# / { sub(/^# /, ""); print; exit }
  ' "$1"
}

SAMPLE_DIR="$(mktemp -d)"
trap 'rm -rf "$SAMPLE_DIR"' EXIT

# Case 1: 정규 frontmatter + H1
cat > "$SAMPLE_DIR/case1.md" <<'EOF'
---
scope:
  include: ["foo"]
verify: "true"
---

# My Sample SPEC Title

## Section
body text
EOF
got="$(extract_h1_awk "$SAMPLE_DIR/case1.md")"
[[ "$got" == "My Sample SPEC Title" ]] \
  || fail "AC7-behavior(case1): 실측 '$got', 기대 'My Sample SPEC Title'"

# Case 2: frontmatter 없음, 바로 H1
cat > "$SAMPLE_DIR/case2.md" <<'EOF'
# Just A Title

body text
EOF
got="$(extract_h1_awk "$SAMPLE_DIR/case2.md")"
[[ "$got" == "Just A Title" ]] \
  || fail "AC7-behavior(case2): 실측 '$got', 기대 'Just A Title'"

# Case 3: H2 가 H1 보다 먼저 등장 — H1 만 추출
cat > "$SAMPLE_DIR/case3.md" <<'EOF'
---
foo: bar
---

## Subheading first
# Actual H1
## Another sub
EOF
got="$(extract_h1_awk "$SAMPLE_DIR/case3.md")"
[[ "$got" == "Actual H1" ]] \
  || fail "AC7-behavior(case3): 실측 '$got', 기대 'Actual H1'"

# Case 4: frontmatter 안의 '# 주석' 같은 라인이 잘못 매치되지 않는지
cat > "$SAMPLE_DIR/case4.md" <<'EOF'
---
# this is a yaml comment looking line in frontmatter
scope: foo
---

# Real Title
EOF
got="$(extract_h1_awk "$SAMPLE_DIR/case4.md")"
[[ "$got" == "Real Title" ]] \
  || fail "AC7-behavior(case4): 실측 '$got', 기대 'Real Title' (frontmatter 내부 '# ' 라인이 H1 으로 잘못 매치됨)"

ok "AC7-behavior: 4개 샘플 모두 정확히 H1 추출 (frontmatter·non-frontmatter·H2 우선·yaml 주석 내성)"

# ---------------------------------------------------------------------------
echo ""
echo "ALL CHECKS PASSED"
