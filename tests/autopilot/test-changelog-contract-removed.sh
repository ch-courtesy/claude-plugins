#!/usr/bin/env bash
# test-changelog-contract-removed.sh — changelog 메커니즘 제거 후 잔존 계약 가드 (PR 544 리뷰 델타)
#
# CHANGELOG.md 삭제 + rules/engineering/versioning.md의 changelog 절 제거 이후에도
# engineering-rule-creator 스킬의 활성화 설명·README와 autopilot feature/fix
# task-body-template이 여전히 changelog 지원을 광고/권장하면, changelog 요청이 더 이상
# changelog 를 다루지 않는 스킬로 라우팅되거나 새 태스크가 삭제된 CHANGELOG.md 를
# scope에 다시 포함시킬 수 있다. 이 회귀를 막는다.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
RULE_SKILL="$REPO_ROOT/plugins/project-init/skills/engineering-rule-creator/SKILL.md"
RULE_README="$REPO_ROOT/plugins/project-init/skills/engineering-rule-creator/README.md"
SHARED_TPL="$REPO_ROOT/plugins/autopilot/lib/references/task-body-template.md"  # feature·fix 작성자 공용 단일 출처

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

echo "=== T1: engineering-rule-creator SKILL.md가 changelog 지원을 광고하지 않음 ==="
grep -qi 'changelog' "$RULE_SKILL" \
  && fail "T1: SKILL.md가 여전히 changelog 트리거/언급을 포함" \
  || ok "SKILL.md: changelog 언급 없음"

echo "=== T2: engineering-rule-creator README.md가 changelog 지원을 광고하지 않음 ==="
grep -qi 'changelog' "$RULE_README" \
  && fail "T2: README.md가 여전히 changelog 언급을 포함" \
  || ok "README.md: changelog 언급 없음"

echo "=== T3: 공용 task-body-template이 CHANGELOG.md를 scope 권장하지 않음 ==="
grep -q 'CHANGELOG.md' "$SHARED_TPL" \
  && fail "T3: 공용 task-body-template이 여전히 CHANGELOG.md를 scope 권장" \
  || ok "공용 task-body-template: CHANGELOG.md 권장 없음"

echo "=== T4: 공용 task-body-template(fix 진단 포함 형판)이 CHANGELOG.md를 scope 권장하지 않음 ==="
grep -q 'CHANGELOG.md' "$SHARED_TPL" \
  && fail "T4: 공용 task-body-template(fix 진단 포함 형판)이 여전히 CHANGELOG.md를 scope 권장" \
  || ok "공용 task-body-template(재확인): CHANGELOG.md 권장 없음"

echo "ALL PASS"
