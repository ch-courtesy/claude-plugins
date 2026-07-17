#!/usr/bin/env bash
# test-create-task-scope-coverage.sh — scope-coverage 검증 정적 계약 테스트 (#498)
#
# create-task 등록 시 scope.include의 소스 파일을 덮는 기존 테스트 경로가 누락되면
# 플래그되는지를 검증한다. #483(새 테스트 작성자 명시) 보완 — 기존 테스트 경로는
# 등록 시 시스템이 자동 검증.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/create-task/SKILL.md"
MAP_FILE="$REPO_ROOT/plugins/autopilot/skills/create-task/references/scope-coverage-map.md"
CHECKER="$REPO_ROOT/plugins/autopilot/skills/create-task/references/scope-coverage-check.sh"
SHARED_TPL="$REPO_ROOT/plugins/autopilot/lib/references/task-body-template.md"  # feature·fix 작성자 공용 단일 출처

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

# === T1: scope-coverage-check.sh 존재 ===
echo "=== T1: scope-coverage-check.sh 존재 ==="
[[ -f "$CHECKER" ]] || fail "T1: scope-coverage-check.sh 부재"
ok "scope-coverage-check.sh 존재"

# === T2: scope-coverage-map.md 존재 (단일 출처) ===
echo "=== T2: scope-coverage-map.md 존재 (단일 출처) ==="
[[ -f "$MAP_FILE" ]] || fail "T2: references/scope-coverage-map.md 부재"
ok "scope-coverage-map.md 존재"

# === T3: SKILL.md에 scope-coverage 검증 언급 ===
echo "=== T3: SKILL.md scope-coverage 검증 언급 ==="
grep -qE 'scope.coverage|scope-coverage' "$SKILL_MD" \
  || fail "T3: SKILL.md에 scope-coverage 검증 없음"
ok "SKILL.md: scope-coverage 검증 언급"

# === T4: 소스만 scope에 있고 테스트 경로 누락 → SCOPE_COVERAGE_WARNING 출력 ===
echo "=== T4: 소스만 있고 테스트 누락 → SCOPE_COVERAGE_WARNING ==="
BODY_MISSING="---
scope:
  include:
    - plugins/autopilot/skills/create-task/**
    - plugins/autopilot/.claude-plugin/plugin.json
    - CHANGELOG.md
---

## 무엇을 만들 것인가
테스트 경로 누락 샘플 본문.
"
out="$(echo "$BODY_MISSING" | bash "$CHECKER")"
echo "$out" | grep -q 'SCOPE_COVERAGE_WARNING' \
  || fail "T4: 소스 테스트 누락 시 SCOPE_COVERAGE_WARNING 없음 (실제: '$out')"
ok "소스 테스트 누락 → SCOPE_COVERAGE_WARNING"

# === T5: 소스 + 테스트 경로 모두 포함 → 경고 없음 ===
echo "=== T5: 소스+테스트 경로 모두 포함 → 경고 없음 ==="
BODY_COVERED="---
scope:
  include:
    - plugins/autopilot/skills/create-task/**
    - tests/autopilot/test-create-task-status-transition.sh
    - tests/autopilot/test-create-task-scope-coverage.sh
    - plugins/autopilot/.claude-plugin/plugin.json
    - CHANGELOG.md
---

## 무엇을 만들 것인가
소스+테스트 모두 포함 샘플 본문.
"
out2="$(echo "$BODY_COVERED" | bash "$CHECKER")"
[[ -z "$out2" ]] \
  || fail "T5: 소스+테스트 모두 포함 시 경고 발생 (실제: '$out2')"
ok "소스+테스트 모두 포함 → 경고 없음"

# === T6: 테스트 경로만 → 오탐 없음 ===
echo "=== T6: 테스트-only 경로 → 오탐 없음 ==="
BODY_TEST_ONLY="---
scope:
  include:
    - tests/autopilot/test-create-task-status-transition.sh
---

## 무엇을 만들 것인가
테스트만 변경하는 샘플.
"
out3="$(echo "$BODY_TEST_ONLY" | bash "$CHECKER")"
[[ -z "$out3" ]] \
  || fail "T6: 테스트-only 경로에서 오탐 발생 (실제: '$out3')"
ok "테스트 경로만 → 오탐 없음"

# === T7: frontmatter 없는 본문 → 조용히 통과 ===
echo "=== T7: frontmatter 없는 본문 → 조용히 통과 ==="
BODY_NO_FM="## 무엇을 만들 것인가
frontmatter 없는 본문.
"
out4="$(echo "$BODY_NO_FM" | bash "$CHECKER")"
[[ -z "$out4" ]] \
  || fail "T7: frontmatter 없는 본문에서 오탐 발생 (실제: '$out4')"
ok "frontmatter 없음 → 조용히 통과"

# === T8: scope-coverage-check.sh가 0 exit만 반환 (누락 있어도 차단 금지) ===
echo "=== T8: scope-coverage-check.sh 항상 0 exit ==="
# 테스트 누락 케이스로 exit code 확인
echo "$BODY_MISSING" | bash "$CHECKER" > /dev/null
# set -e 환경에서 비-0 exit이면 여기까지 오지 못함
ok "scope-coverage-check.sh 항상 0 exit"

# === T9: feature task-body-template에 scope-coverage 보완 언급 ===
echo "=== T9: feature 본문 템플릿 scope-coverage 보완 언급 ==="
grep -qE 'scope-coverage|기존 테스트.*등록|등록.*기존 테스트' "$SHARED_TPL" \
  || fail "T9: feature task-body-template에 scope-coverage(#498) 보완 언급 없음"
ok "feature task-body-template: scope-coverage 보완 언급"

# === T10: fix task-body-template에 scope-coverage 보완 언급 ===
echo "=== T10: fix 본문 템플릿 scope-coverage 보완 언급 ==="
grep -qE 'scope-coverage|기존 테스트.*등록|등록.*기존 테스트' "$SHARED_TPL" \
  || fail "T10: fix task-body-template에 scope-coverage(#498) 보완 언급 없음"
ok "fix task-body-template: scope-coverage 보완 언급"

echo ""
echo "=== 모든 #498 scope-coverage 검증 테스트 통과 ==="
