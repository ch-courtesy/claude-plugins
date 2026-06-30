#!/usr/bin/env bash
# test-versioning-parity-exception.sh — 버전 parity 제약 예외 조항 가드 (PR 544 리뷰 델타 라운드 2)
#
# rules/engineering/versioning.md는 "다음 릴리스로 미루지 않는다"·"예외가 필요하면 먼저 이 룰을
# 갱신한다"고 명시하면서도, 여러 산출물 간 버전 parity를 강제하는 기존 자동 검증(예:
# codex-parity-contract.test.sh)이 scope 밖 동기화를 요구해 버전업이 불가능한 경우의 예외를
# 두지 않았다. 그 결과 plugins/project-init 변경에서 versioning.md 자체를 고치면서도
# plugin.json 버전을 올리지 않는 선택이 "정책 위반"으로만 보였다(PR 544 Claude 리뷰
# non_blocking/85). 라이브 룰과 그 부트스트랩 템플릿 모두에 parity 예외 조항이 있는지 고정한다.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
LIVE_RULE="$REPO_ROOT/rules/engineering/versioning.md"
TEMPLATE="$REPO_ROOT/plugins/project-init/skills/engineering-rule-creator/templates/versioning.md"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

echo "=== T1: 라이브 룰에 parity 예외 조항 존재 ==="
grep -q 'parity 예외' "$LIVE_RULE" \
  && ok "rules/engineering/versioning.md: parity 예외 조항 존재" \
  || fail "T1: rules/engineering/versioning.md에 parity 예외 조항이 없음"

echo "=== T2: 부트스트랩 템플릿에 parity 예외 조항 존재 ==="
grep -q 'parity 예외' "$TEMPLATE" \
  && ok "templates/versioning.md: parity 예외 조항 존재" \
  || fail "T2: templates/versioning.md에 parity 예외 조항이 없음"

echo "=== T3: 예외 조항이 머지 강제 절 안에 있음(섹션 구조 유지) ==="
for f in "$LIVE_RULE" "$TEMPLATE"; do
  awk '/^## 머지 강제/{flag=1} /^## 릴리스 절차/{flag=0} flag' "$f" | grep -q 'parity 예외' \
    || fail "T3: $f 에서 parity 예외 조항이 '머지 강제' 절 밖에 있음"
done
ok "두 문서 모두 parity 예외 조항이 '머지 강제' 절 안에 위치"

echo "ALL PASS"
