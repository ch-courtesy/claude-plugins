#!/usr/bin/env bash
# per-spec directory layout 전환 — 정적 계약 검증 (rule 문서 + spec 스킬).
#
# SPEC: spec/loop/dispatch per-spec directory layout 전환.
#   AC1 — spec 스킬 산출물은 항상 docs/specs/<date>-<slug>/SPEC.md (단일 파일 미생성).
#   AC6 — 빈 slug → fallback 없이 abort.
#   AC8 — slug·파일명 단일 출처 규칙 문서는 신 레이아웃을 기술하고, 모든 경로 예시·
#         commit 스테이징 지시가 신 레이아웃과 일치하며, 구 단일 파일 경로 표현이
#         남지 않아야 한다.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
RULE_MD="$REPO_ROOT/rules/engineering/branch-and-slug.md"
SPEC_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/spec/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$RULE_MD" ]]       || fail "rule 문서 부재: $RULE_MD"
[[ -f "$SPEC_SKILL_MD" ]] || fail "spec SKILL.md 부재: $SPEC_SKILL_MD"

# 구 단일 파일 경로 패턴: docs/specs/<...>-<slug>.md  (디렉토리 레이아웃이 아님)
#   신 레이아웃 docs/specs/<...>-<slug>/SPEC.md 는 제외하고 단일 .md 만 검출.
# 정규식: docs/specs/...-slug.md 로 끝나고 바로 뒤가 / 가 아닌 형태.
OLD_PATH_RE='docs/specs/<[^`]*-<slug>\.md'

echo "=== AC8-1: rule 문서가 신 레이아웃 <date>-<slug>/SPEC.md 기술 ==="
grep -qF 'docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md' "$RULE_MD" \
  || fail "AC8-1: rule 문서에 신 레이아웃 경로 'docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md' 부재"
ok "AC8-1: rule 문서 신 레이아웃 경로 존재"

echo ""
echo "=== AC8-2: rule 문서에 구 단일 파일 경로 표현 부재 ==="
if grep -nE "$OLD_PATH_RE" "$RULE_MD"; then
  fail "AC8-2: rule 문서에 구 단일 파일 경로(docs/specs/<...>-<slug>.md) 잔존"
fi
ok "AC8-2: rule 문서 구 단일 파일 경로 부재"

echo ""
echo "=== AC1-1: spec SKILL.md 산출 경로가 신 레이아웃 ==="
grep -qF 'docs/specs/<YYYY-MM-DD>-<slug>/SPEC.md' "$SPEC_SKILL_MD" \
  || fail "AC1-1: spec SKILL.md 에 신 레이아웃 산출 경로 부재"
ok "AC1-1: spec SKILL.md 신 레이아웃 산출 경로 존재"

echo ""
echo "=== AC1-2: spec SKILL.md 구 단일 파일 경로는 backward-compat 문맥에서만 허용 ==="
# authoring 출력은 항상 신 레이아웃. 구 단일 파일 경로 표현이 나타나면 그 줄은
# 반드시 '구 형식'(legacy 수용) 라벨을 함께 가져야 한다 — --resume 의 양형식 수용
# (AC4)은 합법, 그 외 산출 경로로서의 잔존은 결함.
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if ! grep -qF '구 형식' <<< "$line"; then
    echo "  offending: $line" >&2
    fail "AC1-2: spec SKILL.md 에 backward-compat 라벨 없는 구 단일 파일 경로 잔존"
  fi
done < <(grep -E "$OLD_PATH_RE" "$SPEC_SKILL_MD" || true)
ok "AC1-2: 구 단일 파일 경로는 backward-compat 문맥에서만 등장"

echo ""
echo "=== AC1-3: spec SKILL.md description 은 신 레이아웃만 표기 ==="
desc_line=$(grep -m1 '^description:' "$SPEC_SKILL_MD" || true)
grep -qF 'docs/specs/<날짜>-<slug>/SPEC.md' <<< "$desc_line" \
  || fail "AC1-3: description 에 신 레이아웃 'docs/specs/<날짜>-<slug>/SPEC.md' 부재"
grep -qE 'docs/specs/<날짜>-<slug>\.md' <<< "$desc_line" \
  && fail "AC1-3: description 에 구 단일 파일 경로 잔존"
ok "AC1-3: description 신 레이아웃만 표기"

echo ""
echo "=== AC6: 빈 slug abort 지시 보존 (rule + spec) ==="
grep -qE 'abort|중단' "$RULE_MD" \
  || fail "AC6: rule 문서에 빈 slug abort 지시 부재"
grep -qE 'abort|중단' "$SPEC_SKILL_MD" \
  || fail "AC6: spec SKILL.md 에 빈 slug abort 지시 부재"
ok "AC6: 빈 slug abort 지시 보존"

echo ""
echo "ALL CHECKS PASSED"
