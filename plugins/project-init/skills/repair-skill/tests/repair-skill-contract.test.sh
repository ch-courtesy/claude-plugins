#!/usr/bin/env bash
# repair-skill: shared/rubric 평가→수정 계약 테스트.
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$DIR/SKILL.md"
README="$DIR/README.md"

fail=0
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fail=1; fi; }

check "SKILL.md exists" test -f "$SKILL"
check "README.md exists" test -f "$README"
check "name matches folder" grep -qE '^name: repair-skill$' "$SKILL"

check "description has WHAT(평가) keyword" grep -qE '평가' "$SKILL"
check "description has WHEN trigger keyword" grep -qE '활성화|할 때' "$SKILL"
check "description documents 'all' argument" grep -qF 'all' "$SKILL"

check "references shared rubric checker" grep -qF '../../shared/rubric/rule_checker.py' "$SKILL"
check "references shared rubric criteria" grep -qF '../../shared/rubric/criteria.md' "$SKILL"
check "does not depend on skill-rubric plugin at runtime" bash -c "! grep -qE 'plugins/skill-rubric|skill=\"rubric\"' '$SKILL'"

check "requires approval before applying fixes" grep -qE '승인' "$SKILL"
check "mentions diff presentation before apply" grep -qF 'diff' "$SKILL"
check "re-evaluates after applying approved fixes" grep -qE '재평가' "$SKILL"
check "MINOR items are report-only" grep -qF 'MINOR' "$SKILL"
check "reports pass with no edits when 0 BLOCKER/MAJOR" grep -qE '0건' "$SKILL"
check "rejection leaves item unresolved without edits" grep -qE '거부' "$SKILL"

check "no destructive tools in allowed-tools" bash -c "! grep -qE 'rm -rf|push --force' '$SKILL'"

# Bash 실행 인자는 cwd 비의존 절대경로(repo_root 기준)여야 한다 — Read 전용 상대경로(../../)와
# 구분: 코드펜스 안의 'python3 ...rule_checker.py' 줄에 상대경로가 남아있으면 실패.
check "rule_checker.py invocation uses repo-root-based absolute path, not a bare relative path" \
  bash -c "! grep -E '^python3 \.\./\.\./shared/rubric/rule_checker\.py' '$SKILL'"
# repo-root 확정 계약은 shared/rubric/checker-invocation.md 로 단일 출처화됨 — SKILL.md 가
# 그 계약을 참조하고, 계약 문서가 실제로 repo root 확정(git rev-parse)을 요구하는지 체인으로 검증.
CONTRACT="$DIR/../../shared/rubric/checker-invocation.md"
check "checker step references the shared invocation contract" \
  grep -qF '../../shared/rubric/checker-invocation.md' "$SKILL"
check "invocation contract resolves repo root before invoking the checker" \
  grep -qF 'git rev-parse --show-toplevel' "$CONTRACT"

if [ "$fail" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi
