#!/usr/bin/env bash
# rubric-fix-bootstrap 수용 조건 계약 테스트.
# S-README: 스킬 폴더에 사람 대상 README.md 가 존재한다(계약·포인터 수준).
# T-KEYWORDS: SKILL.md description 에 사용자 자연어 동의어 키워드가 보강되어 있다.
# no-code-duplication: README 가 SKILL.md 의 진행 순서 본문을 복제하지 않는다.
set -u

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$DIR/SKILL.md"
README="$DIR/README.md"

fail=0
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then echo "ok   - $desc"; else echo "FAIL - $desc"; fail=1; fi; }

# description 줄을 임시 파일로 추출(백틱 등 셸 해석 회피)
DESC_FILE="$(mktemp)"
trap 'rm -f "$DESC_FILE"' EXIT
grep -E '^description:' "$SKILL" > "$DESC_FILE" || true

# S-README: 폴더 내 README.md 존재
check "README.md exists" test -f "$README"

# T-KEYWORDS: description 에 자연어 동의어 키워드 보강
check "description has '초기화' keyword"   grep -qF '초기화' "$DESC_FILE"
check "description has '설정/세팅' keyword" grep -qE '설정|세팅' "$DESC_FILE"
check "description has '셋업/구성' keyword" grep -qE '셋업|구성' "$DESC_FILE"

# 불변식: description 의 WHAT/WHEN 핵심 토큰 보존
check "description keeps 'AGENTS.md'"      grep -qF 'AGENTS.md' "$DESC_FILE"
check "description keeps '벤더 골격'"       grep -qF '벤더 골격' "$DESC_FILE"
check "description keeps 'rule-creator' delegation" grep -qF 'rule-creator' "$DESC_FILE"

# no-code-duplication: README 가 SKILL 진행 순서 헤더를 복제하지 않음
if [ -f "$README" ]; then
  check "README does not copy '## 진행 순서' section" bash -c "! grep -qF '## 진행 순서' '$README'"
fi

if [ "$fail" -eq 0 ]; then echo "PASS"; exit 0; else echo "FAILED"; exit 1; fi
