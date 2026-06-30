#!/usr/bin/env bash
# create-skill: shared/rubric 단일 출처 참조 계약 테스트.
# 5단계 품질 자가점검이 자체 사본이 아니라 shared/rubric/criteria.md를 참조하는지 확인한다.
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$DIR/SKILL.md"
README="$DIR/README.md"

fail=0
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fail=1; fi; }

check "SKILL.md references shared rubric criteria" grep -qF '../../shared/rubric/criteria.md' "$SKILL"
check "README references shared rubric criteria" grep -qF '../../shared/rubric/criteria.md' "$README"
check "local quality-criteria.md copy removed" test ! -e "$DIR/references/quality-criteria.md"
check "SKILL.md does not reference local quality-criteria.md" bash -c "! grep -qF 'references/quality-criteria.md' '$SKILL'"
check "skill-template.md still present" test -f "$DIR/references/skill-template.md"

if [ "$fail" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi
